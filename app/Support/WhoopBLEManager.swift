import CoreBluetooth
import FitnessCore
import Foundation

public struct DiscoveredWhoopDevice: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let profile: WhoopBandProfile
}

/// Native iOS CoreBluetooth transport combining `noop`'s `StandingConnect` + state restoration (`com.openwhoop.ble.central`)
/// with `edge`'s framing, `WhoopSessionCoordinator`, and atomic `whoop.sqlite` persistence.
@MainActor
public final class WhoopBLEManager: NSObject, ObservableObject {
    public static let restoreID = "com.openwhoop.ble.central"
    public static let bgProcessingID = "com.hitesh.fitnessapp.whoop.backfill"
    private static let savedUUIDKey = "WhoopSavedPeripheralUUID"
    private static let savedProfileKey = "WhoopSavedBandProfile"

    @Published public private(set) var bluetoothState: CBManagerState = .unknown
    @Published public private(set) var phase: WhoopConnPhase = .idle
    @Published public private(set) var discoveredDevices: [DiscoveredWhoopDevice] = []
    @Published public private(set) var connectedName: String?
    @Published public private(set) var serialNumber: String?
    @Published public private(set) var isMaverick = false
    @Published public private(set) var liveHrBpm: Int?
    @Published public private(set) var batteryPct: Double?
    @Published public private(set) var charging: Bool?
    @Published public private(set) var wristOn: Bool?
    @Published public private(set) var offloadActive = false
    @Published public private(set) var lastSyncNote = "Not synced this session"
    @Published public private(set) var faultWarning: String?
    @Published public private(set) var substrateSummary: WhoopSubstrateSummary?
    @Published public private(set) var lastWhoopExport: ISODate?
    @Published public private(set) var foundWhoopFiles: [URL] = []

    private var central: CBCentralManager?
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var activePeripheral: CBPeripheral?
    private var cmdToStrapChar: CBCharacteristic?
    private var notifyChars: [CBCharacteristic] = []
    private var pendingSubscribeCount = 0
    private var restoreNeedsResubscribe = false

    private var coordinator: WhoopSessionCoordinator?
    private var store: WhoopStore?
    private let fileService: WhoopDatabaseFileService?
    private let clock: AppClock
    private var scanRotationIndex = 0
    private var scanRotationTask: Task<Void, Never>?

    private var bondGiveUp = WhoopBondRefusalGiveUp()
    private var marginalRadio = WhoopMarginalRadioDetector()
    private var postBondLoop = WhoopPostBondTimeoutLoopDetector()

    private static let lastWhoopExportKey = "lastWhoopExportDate"

    public init(location: AppDatabaseLocation?, clock: AppClock) {
        self.fileService = location.map { WhoopDatabaseFileService(location: $0) }
        self.clock = clock
        self.lastWhoopExport = UserDefaults.standard.string(forKey: Self.lastWhoopExportKey).flatMap { ISODate($0) }
        super.init()
        // Open existing whoop.sqlite if already unlocked & on disk so UI shows counts immediately without touching BLE in UI tests.
        openExistingStoreIfAvailable()
    }

    public static var bundledWhoopDatabaseURL: URL? {
        Bundle.main.url(forResource: "whoop", withExtension: "sqlite")
    }

    public var hasBundledWhoopDatabase: Bool {
        Self.bundledWhoopDatabaseURL != nil
    }

    public var hasWhoopDatabase: Bool {
        fileService?.exists == true
    }

    // MARK: Database Management (Independent of fitness.sqlite)

    public func openExistingStoreIfAvailable() {
        guard let fileService else { return }
        foundWhoopFiles = fileService.filesInDocuments()
        guard fileService.exists else {
            store = nil
            substrateSummary = nil
            return
        }
        do {
            let opened = try fileService.openLiveStore()
            store = opened
            substrateSummary = try opened?.summary()
            if let pct = substrateSummary?.latestBatteryPct { batteryPct = pct }
            if let chg = substrateSummary?.latestCharging { charging = chg }
        } catch {
            faultWarning = "Could not open whoop.sqlite: \(error.localizedDescription)"
        }
    }

    public func refreshSummaryAndFiles() {
        guard let fileService else { return }
        foundWhoopFiles = fileService.filesInDocuments()
        if store == nil, fileService.exists {
            openExistingStoreIfAvailable()
        } else if let store {
            substrateSummary = try? store.summary()
        }
    }

    public func loadBundledWhoopData() throws {
        guard let url = Self.bundledWhoopDatabaseURL else {
            throw ValidationError("No bundled WHOOP database in this build")
        }
        try importWhoopDatabase(from: url)
    }

    public func importWhoopDatabase(from url: URL) throws {
        guard let fileService else { throw ValidationError("App data folder unavailable") }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // Close open handle before atomic swap
        store = nil
        try fileService.importDatabase(from: url, today: clock.today())
        openExistingStoreIfAvailable()
    }

    public func exportWhoopDatabase() throws -> URL {
        guard let fileService else { throw ValidationError("App data folder unavailable") }
        if store == nil { openExistingStoreIfAvailable() }
        guard let store else { throw ValidationError("No WHOOP database to export yet") }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("whoop-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let today = clock.today()
        let out = try fileService.export(from: store.db, today: today, to: directory)
        lastWhoopExport = today
        UserDefaults.standard.set(today.string, forKey: Self.lastWhoopExportKey)
        return out
    }

    // MARK: BLE Lifecycle

    public func ensureCentralStarted() {
        guard central == nil else { return }
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: Self.restoreID,
                CBCentralManagerOptionShowPowerAlertKey: true,
            ])
    }

    public func startScan() {
        ensureCentralStarted()
        guard let central, central.state == .poweredOn else {
            lastSyncNote = "Waiting for Bluetooth power on…"
            phase = .scanning
            return
        }
        discoveredDevices.removeAll()
        phase = .scanning
        lastSyncNote = "Scanning for WHOOP 4.0 / 5.0 / MG…"
        scanWithCurrentFamilyWindow()
    }

    public func stopScan() {
        scanRotationTask?.cancel()
        scanRotationTask = nil
        central?.stopScan()
        if phase == .scanning { phase = .idle }
    }

    public func connect(to device: DiscoveredWhoopDevice) {
        stopScan()
        guard let peripheral = peripheralsByID[device.id] else { return }
        saveTarget(uuid: device.id, profile: device.profile)
        engageStandingConnect(peripheral: peripheral, profile: device.profile)
    }

    public func reconnectSavedBand() {
        ensureCentralStarted()
        guard let central, central.state == .poweredOn else { return }
        connectCore(central: central)
    }

    public func disconnectAndForget() {
        scanRotationTask?.cancel()
        scanRotationTask = nil
        if let p = activePeripheral {
            central?.cancelPeripheralConnection(p)
        }
        activePeripheral = nil
        cmdToStrapChar = nil
        notifyChars.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.savedUUIDKey)
        phase = .idle
        connectedName = nil
        liveHrBpm = nil
        offloadActive = false
        lastSyncNote = "Disconnected"
    }

    public func triggerManualSync() {
        guard let char = cmdToStrapChar, let p = activePeripheral, var coord = coordinator else {
            reconnectSavedBand()
            return
        }
        let frame = coord.buildManualBackfillRequest()
        coordinator = coord
        writeFrame(frame, to: char, on: p)
        lastSyncNote = "Requested historical backfill (0x16)…"
    }

    public func toggleLiveHeartRate(_ enabled: Bool) {
        guard let char = cmdToStrapChar, let p = activePeripheral, var coord = coordinator else { return }
        let frame = coord.buildRealtimeHrToggle(on: enabled)
        coordinator = coord
        writeFrame(frame, to: char, on: p)
        if !enabled { liveHrBpm = nil }
    }

    public func sendBackgroundHighFreqPrompt() {
        guard let char = cmdToStrapChar, let p = activePeripheral, var coord = coordinator else { return }
        if let frame = coord.buildHighFreqSyncPrompt() {
            coordinator = coord
            writeFrame(frame, to: char, on: p)
        }
    }

    // MARK: 5-Step connectCore & StandingConnect

    private func connectCore(central: CBCentralManager) {
        guard !bondGiveUp.stillPaused(now: Date()) else {
            faultWarning = "Bond refusal pause active. Forget WHOOP in iOS Settings → Bluetooth and re-pair."
            phase = .error
            return
        }

        let savedProfileRaw = UserDefaults.standard.string(forKey: Self.savedProfileKey)
        let preferredProfile: WhoopBandProfile = savedProfileRaw == "gen4" ? .gen4 : .gen5

        // Step 1: Already restored active peripheral
        if let p = activePeripheral, p.state == .connected {
            engageStandingConnect(peripheral: p, profile: preferredProfile)
            return
        }

        // Step 2: Saved peripheral UUID via retrievePeripherals(withIdentifiers:)
        if let uuidStr = UserDefaults.standard.string(forKey: Self.savedUUIDKey),
           let uuid = UUID(uuidString: uuidStr),
           let known = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            peripheralsByID[known.identifier] = known
            engageStandingConnect(peripheral: known, profile: preferredProfile)
            return
        }

        // Step 3 & 4: System-connected GATT peripherals matching Gen5, Maverick, Gen4, or FD4B
        let allServiceCBUUIDs = Self.allWhoopServiceCBUUIDs
        let sysConnected = central.retrieveConnectedPeripherals(withServices: allServiceCBUUIDs)
        if let sys = sysConnected.first {
            let prof = Self.inferProfile(name: sys.name, serviceUUIDs: nil) ?? preferredProfile
            peripheralsByID[sys.identifier] = sys
            saveTarget(uuid: sys.identifier, profile: prof)
            engageStandingConnect(peripheral: sys, profile: prof)
            return
        }

        // Step 5: Background-safe service-UUID scan with 8s family rotation (including 16-bit FD4B)
        startScan()
    }

    private func engageStandingConnect(peripheral: CBPeripheral, profile: WhoopBandProfile) {
        activePeripheral = peripheral
        peripheral.delegate = self
        connectedName = peripheral.name ?? "WHOOP Strap"
        if coordinator?.deviceID != peripheral.identifier.uuidString {
            coordinator = WhoopSessionCoordinator(profile: profile, deviceID: peripheral.identifier.uuidString)
        }
        if store == nil, let fileService {
            store = try? fileService.openOrCreateLiveStore()
        }
        if peripheral.state == .connected {
            phase = .discovering
            peripheral.discoverServices(Self.allWhoopServiceCBUUIDs)
        } else {
            phase = .connecting
            central?.connect(peripheral, options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            ])
        }
    }

    private func scanWithCurrentFamilyWindow() {
        guard let central, central.state == .poweredOn else { return }
        let groups: [[CBUUID]] = [
            [CBUUID(string: WhoopGattProfile.gen5.service), CBUUID(string: WhoopGattProfile.maverick.service), CBUUID(string: WhoopGattProfile.whoopAdvService16Bit)],
            [CBUUID(string: WhoopGattProfile.gen4.service), CBUUID(string: WhoopGattProfile.whoopAdvService16Bit)],
        ]
        let targetServices = groups[scanRotationIndex % groups.count]
        scanRotationIndex += 1
        central.scanForPeripherals(withServices: targetServices, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        scanRotationTask?.cancel()
        scanRotationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled, self.phase == .scanning else { return }
            self.scanWithCurrentFamilyWindow()
        }
    }

    private func saveTarget(uuid: UUID, profile: WhoopBandProfile) {
        UserDefaults.standard.set(uuid.uuidString, forKey: Self.savedUUIDKey)
        UserDefaults.standard.set(profile.isGen5 ? "gen5" : "gen4", forKey: Self.savedProfileKey)
    }

    private func writeFrame(_ bytes: [UInt8], to characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(Data(bytes), for: characteristic, type: writeType)
    }

    private static var allWhoopServiceCBUUIDs: [CBUUID] {
        [
            CBUUID(string: WhoopGattProfile.gen5.service),
            CBUUID(string: WhoopGattProfile.maverick.service),
            CBUUID(string: WhoopGattProfile.gen4.service),
            CBUUID(string: WhoopGattProfile.whoopAdvService16Bit),
        ]
    }

    private static func inferProfile(name: String?, serviceUUIDs: [CBUUID]?) -> WhoopBandProfile? {
        if let uuids = serviceUUIDs {
            let strs = Set(uuids.map { $0.uuidString.uppercased() })
            if strs.contains(WhoopGattProfile.gen5.service.uppercased()) || strs.contains(WhoopGattProfile.maverick.service.uppercased()) {
                return .gen5
            }
            if strs.contains(WhoopGattProfile.gen4.service.uppercased()) {
                return .gen4
            }
        }
        if let n = name?.uppercased() {
            if n.contains("WHOOP 5") || n.contains("MAVERICK") || n.contains("MG") { return .gen5 }
            if n.contains("WHOOP") { return .gen5 }
        }
        return nil
    }
}

extension WhoopBLEManager: CBCentralManagerDelegate {
    nonisolated public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]) ?? []
        Task { @MainActor in
            for p in restored {
                self.peripheralsByID[p.identifier] = p
                self.activePeripheral = p
                p.delegate = self
                self.restoreNeedsResubscribe = true
            }
        }
    }

    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let st = central.state
        Task { @MainActor in
            self.bluetoothState = st
            guard st == .poweredOn else {
                if st == .unauthorized {
                    self.faultWarning = "Bluetooth permission denied. Enable Bluetooth in Settings."
                }
                return
            }
            self.openExistingStoreIfAvailable()
            if self.phase == .scanning {
                self.scanWithCurrentFamilyWindow()
            } else if self.activePeripheral != nil || UserDefaults.standard.string(forKey: Self.savedUUIDKey) != nil {
                self.connectCore(central: central)
            }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                           advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        Task { @MainActor in
            self.peripheralsByID[peripheral.identifier] = peripheral
            let profile = Self.inferProfile(name: advName, serviceUUIDs: advUUIDs) ?? .gen5
            let item = DiscoveredWhoopDevice(
                id: peripheral.identifier,
                name: advName ?? "WHOOP (\(peripheral.identifier.uuidString.prefix(6)))",
                rssi: RSSI.intValue,
                profile: profile)
            if let idx = self.discoveredDevices.firstIndex(where: { $0.id == item.id }) {
                self.discoveredDevices[idx] = item
            } else {
                self.discoveredDevices.append(item)
            }

            if let saved = UserDefaults.standard.string(forKey: Self.savedUUIDKey),
               saved == peripheral.identifier.uuidString {
                self.stopScan()
                self.engageStandingConnect(peripheral: peripheral, profile: profile)
            }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.faultWarning = nil
            self.connectedName = peripheral.name ?? "WHOOP Strap"
            self.phase = .discovering
            peripheral.delegate = self
            peripheral.discoverServices(Self.allWhoopServiceCBUUIDs)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let msg = error?.localizedDescription ?? "Connection failed"
        Task { @MainActor in
            if msg.localizedCaseInsensitiveContains("peer removed pairing") || msg.localizedCaseInsensitiveContains("encryption") {
                _ = self.bondGiveUp.recordRefusal(authRefusal: true, now: Date())
                self.faultWarning = "Stale iOS Bluetooth bond detected. Forget WHOOP in iOS Settings → Bluetooth, then reconnect."
                self.phase = .error
                return
            }
            // StandingConnect: re-issue connect() so CoreBluetooth auto-completes when strap returns in range
            self.phase = .reconnecting
            central.connect(peripheral, options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            ])
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.coordinator?.discardActiveBurstOnDisconnect()
            self.offloadActive = false
            self.liveHrBpm = nil
            self.cmdToStrapChar = nil
            self.notifyChars.removeAll()

            // StandingConnect: immediately post zero-radio-duty pending connect unless user explicitly forgot the strap
            if UserDefaults.standard.string(forKey: Self.savedUUIDKey) == peripheral.identifier.uuidString,
               !self.bondGiveUp.stillPaused(now: Date()) {
                self.phase = .reconnecting
                self.lastSyncNote = "Waiting for WHOOP in range (StandingConnect)…"
                central.connect(peripheral, options: [
                    CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                    CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                ])
            } else {
                self.phase = .idle
            }
        }
    }
}

extension WhoopBLEManager: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let services = peripheral.services else { return }
            for svc in services {
                let idUpper = svc.uuid.uuidString.uppercased()
                if idUpper == WhoopGattProfile.gen5.service.uppercased() || idUpper == WhoopGattProfile.maverick.service.uppercased() {
                    self.coordinator = WhoopSessionCoordinator(profile: .gen5, deviceID: peripheral.identifier.uuidString)
                    self.saveTarget(uuid: peripheral.identifier, profile: .gen5)
                } else if idUpper == WhoopGattProfile.gen4.service.uppercased() {
                    self.coordinator = WhoopSessionCoordinator(profile: .gen4, deviceID: peripheral.identifier.uuidString)
                    self.saveTarget(uuid: peripheral.identifier, profile: .gen4)
                }
                peripheral.discoverCharacteristics(nil, for: svc)
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard let chars = service.characteristics else { return }
            let gatt = (self.coordinator?.profile.isGen5 == false) ? WhoopGattProfile.gen4 : WhoopGattProfile.gen5
            let notifySet: Set<String> = [
                gatt.cmdFrom.uppercased(),
                gatt.events.uppercased(),
                gatt.data.uppercased(),
                WhoopGattProfile.maverick.cmdFrom.uppercased(),
                WhoopGattProfile.maverick.events.uppercased(),
                WhoopGattProfile.maverick.data.uppercased(),
            ]
            let cmdToSet: Set<String> = [
                gatt.cmdTo.uppercased(),
                WhoopGattProfile.maverick.cmdTo.uppercased(),
            ]

            self.phase = .subscribing
            for c in chars {
                let u = c.uuid.uuidString.uppercased()
                if cmdToSet.contains(u) {
                    self.cmdToStrapChar = c
                } else if notifySet.contains(u) || c.properties.contains(.notify) {
                    self.notifyChars.append(c)
                    if self.restoreNeedsResubscribe && c.isNotifying {
                        // Force fresh CCCD write after state restoration (`setNotifyValue(false)` -> `true`)
                        peripheral.setNotifyValue(false, for: c)
                    }
                    self.pendingSubscribeCount += 1
                    peripheral.setNotifyValue(true, for: c)
                }
            }
            self.restoreNeedsResubscribe = false
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let errText = error?.localizedDescription
        Task { @MainActor in
            if let errText {
                if errText.localizedCaseInsensitiveContains("insufficient") || errText.localizedCaseInsensitiveContains("encryption") {
                    _ = self.bondGiveUp.recordRefusal(authRefusal: true, now: Date())
                    self.faultWarning = "CCCD subscription refused (encryption/bond error). Forget WHOOP in iOS Settings → Bluetooth."
                    self.phase = .error
                    return
                }
            }
            if self.pendingSubscribeCount > 0 { self.pendingSubscribeCount -= 1 }
            if self.pendingSubscribeCount == 0, let cmdChar = self.cmdToStrapChar, var coord = self.coordinator {
                self.phase = .settingUp
                let bootFrames = coord.onLinkReady()
                self.coordinator = coord
                for f in bootFrames {
                    self.writeFrame(f, to: cmdChar, on: peripheral)
                }
                self.phase = .listening
                self.lastSyncNote = "Connected · syncing telemetry"
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }
        let bytes = [UInt8](data)
        Task { @MainActor in
            if self.store == nil, let fileService = self.fileService {
                self.store = try? fileService.openOrCreateLiveStore()
            }
            guard let store = self.store, var coord = self.coordinator else { return }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            do {
                let out = try coord.receiveRawDataFromStrap(bytes, store: store, nowMs: nowMs)
                self.coordinator = coord
                self.isMaverick = coord.isMaverick
                if let s = coord.serialNumber { self.serialNumber = s }
                if let pct = coord.batteryPct { self.batteryPct = pct }
                if let chg = coord.charging { self.charging = chg }
                if let w = coord.wristOn { self.wristOn = w }
                self.offloadActive = coord.offloadActive
                if let hr = out.liveHr { self.liveHrBpm = hr.hrBpm }

                if coord.corruptionTripped {
                    self.faultWarning = "High BLE frame corruption (>20%). Reconnecting cleanly…"
                    self.central?.cancelPeripheralConnection(peripheral)
                    return
                }

                if let cmdChar = self.cmdToStrapChar {
                    for tx in out.txFrames {
                        self.writeFrame(tx, to: cmdChar, on: peripheral)
                    }
                }
                if out.historyCompleted || !out.txFrames.isEmpty {
                    self.substrateSummary = try? store.summary()
                    if out.historyCompleted {
                        self.lastSyncNote = "Caught up · \(self.substrateSummary?.oneHzCount ?? 0) 1 Hz rows"
                    }
                }
            } catch {
                self.faultWarning = error.localizedDescription
            }
        }
    }
}
