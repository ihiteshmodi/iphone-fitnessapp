import CryptoKit
import Foundation

public struct WhoopBatteryRow: Equatable, Sendable {
    public let deviceID: String
    public let ts: Int
    public let batteryPct: Double?
    public let charging: Bool?
    public let wristOn: Bool?
    public let millivolts: Int?
    public let chargeUnits: Int?
    public let source: String

    public init(deviceID: String = "", ts: Int, batteryPct: Double?, charging: Bool?, wristOn: Bool?,
                millivolts: Int?, chargeUnits: Int?, source: String) {
        self.deviceID = deviceID
        self.ts = ts
        self.batteryPct = batteryPct
        self.charging = charging
        self.wristOn = wristOn
        self.millivolts = millivolts
        self.chargeUnits = chargeUnits
        self.source = source
    }
}

public struct WhoopBacklogRow: Equatable, Sendable {
    public let deviceID: String
    public let ts: Int
    public let written: Int
    public let used: Int
    public let capacity: Int
    public let trimPage: Int
    public let wrapCount: Int
    public let freeRecords: Int
    public let deviceFamily: String

    public init(deviceID: String = "", ts: Int, written: Int, used: Int, capacity: Int,
                trimPage: Int, wrapCount: Int, freeRecords: Int, deviceFamily: String) {
        self.deviceID = deviceID
        self.ts = ts
        self.written = written
        self.used = used
        self.capacity = capacity
        self.trimPage = trimPage
        self.wrapCount = wrapCount
        self.freeRecords = freeRecords
        self.deviceFamily = deviceFamily
    }
}

public struct WhoopRawArchiveRow: Equatable, Sendable {
    public let deviceID: String
    public let counter: Int?
    public let packetType: Int
    public let recTs: Int?
    public let capturedAtMs: Int64
    public let reason: String
    public let frame: Data

    public init(deviceID: String = "", counter: Int?, packetType: Int, recTs: Int?,
                capturedAtMs: Int64, reason: String, frame: Data) {
        self.deviceID = deviceID
        self.counter = counter
        self.packetType = packetType
        self.recTs = recTs
        self.capturedAtMs = capturedAtMs
        self.reason = reason
        self.frame = frame
    }
}

public struct WhoopLiveCoverageRow: Equatable, Sendable {
    public let startTs: Int
    public let endTs: Int
    public let steps: Int
    public let day: String
    public let source: String
    public let deviceID: String

    public init(startTs: Int, endTs: Int, steps: Int, day: String, source: String = "band", deviceID: String = "") {
        self.startTs = startTs
        self.endTs = endTs
        self.steps = steps
        self.day = day
        self.source = source
        self.deviceID = deviceID
    }
}

public struct WhoopEventRow: Equatable, Sendable {
    public let deviceID: String
    public let rawInnerHex: String
    public let info: WhoopEventInfo
    public let capturedAtMs: Int64

    public init(deviceID: String = "", rawInnerHex: String, info: WhoopEventInfo, capturedAtMs: Int64) {
        self.deviceID = deviceID
        self.rawInnerHex = rawInnerHex
        self.info = info
        self.capturedAtMs = capturedAtMs
    }
}

public struct WhoopSyncBatch: Equatable, Sendable {
    public var deviceID: String
    public var gen4Records: [WhoopR24Record]
    public var gen4R10Records: [WhoopR10Lite]
    public var gen5Samples: [WhoopGen5HistorySample]
    public var ecgRawPackets: [WhoopLabradorR16Raw]
    public var archives: [WhoopRawArchiveRow]
    public var events: [WhoopEventRow]
    public var batteryRows: [WhoopBatteryRow]
    public var backlogRows: [WhoopBacklogRow]
    public var liveCoverageSpans: [WhoopLiveCoverageRow]
    public var trimTokenHex: String?
    public var capturedAtMs: Int64

    public init(deviceID: String = "", gen4Records: [WhoopR24Record] = [], gen4R10Records: [WhoopR10Lite] = [],
                gen5Samples: [WhoopGen5HistorySample] = [], ecgRawPackets: [WhoopLabradorR16Raw] = [],
                archives: [WhoopRawArchiveRow] = [], events: [WhoopEventRow] = [],
                batteryRows: [WhoopBatteryRow] = [], backlogRows: [WhoopBacklogRow] = [],
                liveCoverageSpans: [WhoopLiveCoverageRow] = [], trimTokenHex: String? = nil, capturedAtMs: Int64) {
        self.deviceID = deviceID
        self.gen4Records = gen4Records
        self.gen4R10Records = gen4R10Records
        self.gen5Samples = gen5Samples
        self.ecgRawPackets = ecgRawPackets
        self.archives = archives
        self.events = events
        self.batteryRows = batteryRows
        self.backlogRows = backlogRows
        self.liveCoverageSpans = liveCoverageSpans
        self.trimTokenHex = trimTokenHex
        self.capturedAtMs = capturedAtMs
    }

    public var hadDurableRows: Bool {
        !gen4Records.isEmpty || !gen4R10Records.isEmpty || !gen5Samples.isEmpty || !ecgRawPackets.isEmpty
            || archives.contains { $0.reason != "gate_dropped" }
    }
}

public struct WhoopSubstrateSummary: Equatable, Sendable {
    public let oneHzCount: Int
    public let rrCount: Int
    public let rawArchiveCount: Int
    public let liveCoverageCount: Int
    public let oldestRecTs: Int?
    public let latestRecTs: Int?
    public let latestCounter: Int?
    public let strapTrimHex: String?
    public let latestBatteryPct: Double?
    public let latestCharging: Bool?

    public init(oneHzCount: Int, rrCount: Int, rawArchiveCount: Int, liveCoverageCount: Int,
                oldestRecTs: Int?, latestRecTs: Int?, latestCounter: Int?,
                strapTrimHex: String?, latestBatteryPct: Double?, latestCharging: Bool?) {
        self.oneHzCount = oneHzCount
        self.rrCount = rrCount
        self.rawArchiveCount = rawArchiveCount
        self.liveCoverageCount = liveCoverageCount
        self.oldestRecTs = oldestRecTs
        self.latestRecTs = latestRecTs
        self.latestCounter = latestCounter
        self.strapTrimHex = strapTrimHex
        self.latestBatteryPct = latestBatteryPct
        self.latestCharging = latestCharging
    }
}

public enum WhoopLivePedometer {
    /// Minimal 100 Hz stride-periodicity pedometer for `live_coverage` windows while live IMU `0x33`/`0x2B` is active.
    public static func countSteps(frames: [WhoopImuFrame]) -> Int {
        let mags = frames.flatMap(\.mags)
        guard mags.count >= 25 else { return 0 }
        let mean = mags.reduce(0, +) / Double(mags.count)
        let dyn = mags.map { max(0.0, $0 - max(0.85, mean)) }
        var steps = 0
        var lastPeakIdx = -30
        for i in 1..<(dyn.count - 1) {
            if dyn[i] > 0.18 && dyn[i] >= dyn[i - 1] && dyn[i] > dyn[i + 1] && (i - lastPeakIdx) >= 28 {
                steps += 1
                lastPeakIdx = i
            }
        }
        return steps
    }
}

public final class WhoopStore {
    private static let countableTables: Set<String> = [
        "decoded_onehz", "decoded_rr", "live_coverage", "raw_archive_frames",
        "band_battery", "band_backlog", "band_events", "events", "sync_cursor",
        "samples", "ecg_reading", "ecg_reading_packet", "ecg_raw_packet",
    ]

    public let db: Database

    public init(_ db: Database) throws {
        self.db = db
        try WhoopSubstrateSchema.apply(to: db)
    }

    public static func inMemory() throws -> WhoopStore {
        try WhoopStore(try Database(path: ":memory:"))
    }

    /// Commits a sync batch inside a single `BEGIN IMMEDIATE ... COMMIT` with `PRAGMA synchronous = FULL`
    /// BEFORE `0x17` flash-trim ACK may be transmitted.
    public func commitSyncBatch(_ batch: WhoopSyncBatch) throws {
        if db.path != ":memory:" {
            try db.execute("PRAGMA synchronous = FULL")
        }
        let updatedSec = Int64(batch.capturedAtMs / 1000)

        try db.transaction {
            var maxCounter: Int64?
            var maxRecTs: Int64?

            func trackHighWater(counter: Int, recTs: Int) {
                let c = Int64(counter)
                let t = Int64(recTs)
                if maxCounter == nil || c > maxCounter! { maxCounter = c }
                if maxRecTs == nil || t > maxRecTs! { maxRecTs = t }
            }

            func replaceRR(deviceID: String, tsMs: Int64, recTs: Int, subsec: Int?, rrMs: [Int], family: String) throws {
                try db.execute("DELETE FROM decoded_rr WHERE device_id = ? AND ts_ms = ?", [
                    .text(deviceID), .int(tsMs),
                ])
                guard !rrMs.isEmpty else { return }
                let beatTimes = WhoopBeatTiming.beatTimesMs(recTs: recTs, tsSubsec: subsec, rrMs: rrMs)
                for (idx, rr) in rrMs.enumerated() {
                    let beatTs = idx < beatTimes.count ? beatTimes[idx] : nil
                    let rrTsMs = beatTs ?? tsMs
                    try db.execute("""
                        INSERT INTO decoded_rr (
                            device_id, ts_ms, rec_ts, beat_index, rr_ts_ms, rr_ms, device_family, source, beat_ts_ms
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, 'band', ?)
                        """, [
                        .text(deviceID), .int(tsMs), .int(Int64(recTs)),
                        .int(Int64(idx)), .int(rrTsMs), .int(Int64(rr)),
                        .text(family), .optional(beatTs),
                    ])
                }
            }

            for rec in batch.gen4Records {
                let tsMs = Int64(rec.tsEpoch) * 1000
                let hrVal: Int? = rec.hr > 0 ? rec.hr : nil
                let ax: Double? = rec.accelG.count > 0 ? rec.accelG[0] : nil
                let ay: Double? = rec.accelG.count > 1 ? rec.accelG[1] : nil
                let az: Double? = rec.accelG.count > 2 ? rec.accelG[2] : nil
                let spo2Red: Int? = rec.spo2RedRaw > 0 ? rec.spo2RedRaw : nil
                let spo2Ir: Int? = rec.spo2IrRaw > 0 ? rec.spo2IrRaw : nil
                try db.execute("""
                    INSERT OR REPLACE INTO decoded_onehz (
                        device_id, ts_ms, rec_ts, counter, hr, ax, ay, az,
                        spo2_red_raw, spo2_ir_raw, skin_temp_raw, ambient_raw,
                        hr_valid, device_family, source, ts_subsec
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'gen4', 'band', ?)
                    """, [
                    .text(batch.deviceID), .int(tsMs), .int(Int64(rec.tsEpoch)),
                    .int(Int64(rec.counter)), .optional(hrVal),
                    .optional(ax), .optional(ay), .optional(az),
                    .optional(spo2Red), .optional(spo2Ir),
                    .int(Int64(rec.skinTempRaw)), .int(Int64(rec.ambientRaw)),
                    .int(hrVal != nil ? 1 : 0), .int(Int64(rec.tsSubsec)),
                ])
                try replaceRR(deviceID: batch.deviceID, tsMs: tsMs, recTs: rec.tsEpoch, subsec: rec.tsSubsec, rrMs: rec.rrIntervalsMs, family: "gen4")
                trackHighWater(counter: rec.counter, recTs: rec.tsEpoch)
            }

            for r10 in batch.gen4R10Records {
                let tsMs = Int64(r10.tsEpoch) * 1000
                let hrVal: Int? = r10.hr > 0 ? r10.hr : nil
                try db.execute("""
                    INSERT OR REPLACE INTO decoded_onehz (
                        device_id, ts_ms, rec_ts, counter, hr, hr_valid, device_family, source, ts_subsec
                    ) VALUES (?, ?, ?, ?, ?, ?, 'gen4', 'band', 0)
                    """, [
                    .text(batch.deviceID), .int(tsMs), .int(Int64(r10.tsEpoch)),
                    .int(Int64(r10.counter)), .optional(hrVal), .int(hrVal != nil ? 1 : 0),
                ])
                try replaceRR(deviceID: batch.deviceID, tsMs: tsMs, recTs: r10.tsEpoch, subsec: nil, rrMs: r10.rrIntervalsMs, family: "gen4")
                trackHighWater(counter: r10.counter, recTs: r10.tsEpoch)
            }

            for s in batch.gen5Samples {
                let tsMs = Int64(s.unix) * 1000
                let hrVal: Int? = s.heartRate > 0 ? s.heartRate : nil
                let hrAltVal: Int? = s.heartRateAlt > 0 ? s.heartRateAlt : nil
                let ax: Double? = s.gravityG.count > 0 ? s.gravityG[0] : nil
                let ay: Double? = s.gravityG.count > 1 ? s.gravityG[1] : nil
                let az: Double? = s.gravityG.count > 2 ? s.gravityG[2] : nil
                try db.execute("""
                    INSERT OR REPLACE INTO decoded_onehz (
                        device_id, ts_ms, rec_ts, counter, hr, ax, ay, az,
                        spo2_red_raw, skin_temp_raw, step_count, step_cadence, activity_class,
                        skin_temp_c, hr_valid, hr_alt, device_family, source,
                        temp_ch2_c, temp_ch3_c, signal_quality_logvar, dyn_accel_g, ts_subsec, band_sleep_state
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'gen5', 'band', ?, ?, ?, ?, ?, ?)
                    """, [
                    .text(batch.deviceID), .int(tsMs), .int(Int64(s.unix)),
                    .int(Int64(s.recordIndex)), .optional(hrVal),
                    .optional(ax), .optional(ay), .optional(az),
                    .int(Int64(s.spo2CandidateRaw)), .int(Int64(s.skinTempRawCenti)),
                    .int(Int64(s.stepMotionCounter)), .int(Int64(s.stepCadence)),
                    .optional(s.activityClassKnown), .optional(s.skinTempCOrNull),
                    .int(hrVal != nil ? 1 : 0), .optional(hrAltVal),
                    .optional(s.tempAux1C), .optional(s.tempAux2C),
                    .optional(s.signalQualityLogVariance), .optional(s.dynamicAccelerationG),
                    .int(Int64(s.tsSubsec)), .int(Int64(s.sleepStateRawNibble)),
                ])
                try replaceRR(deviceID: batch.deviceID, tsMs: tsMs, recTs: s.unix, subsec: s.tsSubsec, rrMs: s.rrIntervalsMs, family: "gen5")
                trackHighWater(counter: s.recordIndex, recTs: s.unix)
            }

            for ecg in batch.ecgRawPackets {
                try db.execute("""
                    INSERT OR REPLACE INTO ecg_raw_packet (
                        hex, device_id, sequence, strap_seconds, strap_subsec, captured_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """, [
                    .text(ecg.innerHex), .text(batch.deviceID),
                    .int(Int64(ecg.sequence)), .int(Int64(ecg.strapSeconds)),
                    .int(Int64(ecg.subseconds)), .int(batch.capturedAtMs),
                ])
                trackHighWater(counter: ecg.sequence, recTs: ecg.strapSeconds)
            }

            for arch in batch.archives {
                let devID = arch.deviceID.isEmpty ? batch.deviceID : arch.deviceID
                let digest = Insecure.SHA1.hash(data: arch.frame)
                let hashData = Data(digest)
                try db.execute("""
                    INSERT OR IGNORE INTO raw_archive_frames (
                        device_id, hash, counter, packet_type, rec_ts, captured_at, reason, frame
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, [
                    .text(devID), .blob(hashData), .optional(arch.counter),
                    .int(Int64(arch.packetType)), .optional(arch.recTs),
                    .int(arch.capturedAtMs), .text(arch.reason), .blob(arch.frame),
                ])
            }

            for ev in batch.events {
                let devID = ev.deviceID.isEmpty ? batch.deviceID : ev.deviceID
                try db.execute("""
                    INSERT OR REPLACE INTO band_events (
                        device_id, hex, event_id, name, ts, payload_json, captured_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, [
                    .text(devID), .text(ev.rawInnerHex),
                    .int(Int64(ev.info.eventID)), .text(ev.info.name),
                    .int(Int64(ev.info.tsEpoch)), .text(ev.info.payloadJSON),
                    .int(ev.capturedAtMs),
                ])
                try db.execute("""
                    INSERT OR REPLACE INTO events (device_id, hex, event_id, ts, captured_at)
                    VALUES (?, ?, ?, ?, ?)
                    """, [
                    .text(devID), .text(ev.rawInnerHex),
                    .int(Int64(ev.info.eventID)), .int(Int64(ev.info.tsEpoch)),
                    .int(ev.capturedAtMs),
                ])
            }

            for b in batch.batteryRows {
                let devID = b.deviceID.isEmpty ? batch.deviceID : b.deviceID
                try db.execute("""
                    INSERT OR REPLACE INTO band_battery (
                        device_id, ts, battery_pct, charging, wrist_on, millivolts, charge_units, source
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, [
                    .text(devID), .int(Int64(b.ts)), .optional(b.batteryPct),
                    .optional(b.charging.map { $0 ? 1 : 0 }),
                    .optional(b.wristOn.map { $0 ? 1 : 0 }),
                    .optional(b.millivolts), .optional(b.chargeUnits), .text(b.source),
                ])
            }

            for bl in batch.backlogRows {
                let devID = bl.deviceID.isEmpty ? batch.deviceID : bl.deviceID
                try db.execute("""
                    INSERT OR REPLACE INTO band_backlog (
                        device_id, ts, written, used, capacity, trim_page, wrap_count, free_records, device_family
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [
                    .text(devID), .int(Int64(bl.ts)), .int(Int64(bl.written)), .int(Int64(bl.used)),
                    .int(Int64(bl.capacity)), .int(Int64(bl.trimPage)),
                    .int(Int64(bl.wrapCount)), .int(Int64(bl.freeRecords)), .text(bl.deviceFamily),
                ])
            }

            for span in batch.liveCoverageSpans {
                let devID = span.deviceID.isEmpty ? batch.deviceID : span.deviceID
                try db.execute("""
                    INSERT INTO live_coverage (start_ts, end_ts, steps, day, source, device_id)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, [
                    .int(Int64(span.startTs)), .int(Int64(span.endTs)), .int(Int64(span.steps)),
                    .text(span.day), .text(span.source), .text(devID),
                ])
            }

            if let maxC = maxCounter {
                let prev = Int64(try cursorValue("counter_hw") ?? "") ?? 0
                if maxC > prev {
                    try upsertCursor(name: "counter_hw", value: String(maxC), updatedAt: updatedSec)
                }
            }
            if let maxT = maxRecTs {
                let prev = Int64(try cursorValue("rec_ts_hw") ?? "") ?? 0
                if maxT > prev {
                    try upsertCursor(name: "rec_ts_hw", value: String(maxT), updatedAt: updatedSec)
                }
            }
            if let trimHex = batch.trimTokenHex {
                try upsertCursor(name: "strap_trim", value: trimHex, updatedAt: updatedSec)
            }
        }
    }

    public func upsertCursor(name: String, value: String, updatedAt: Int64) throws {
        try db.execute("""
            INSERT INTO sync_cursor (name, value, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(name) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """, [.text(name), .text(value), .int(updatedAt)])
    }

    public func cursorValue(_ name: String) throws -> String? {
        try db.query("SELECT value FROM sync_cursor WHERE name = ?", [.text(name)]).first?.optionalText("value")
    }

    public func count(_ table: String) throws -> Int {
        guard Self.countableTables.contains(table) else { throw ValidationError("Unknown WHOOP table \(table)") }
        return try db.query("SELECT COUNT(*) AS c FROM \(table)").first?.int("c") ?? 0
    }

    public func summary() throws -> WhoopSubstrateSummary {
        let oneHzRow = try db.query("""
            SELECT COUNT(*) AS c, MIN(rec_ts) AS min_ts, MAX(rec_ts) AS max_ts, MAX(counter) AS max_c
            FROM decoded_onehz
            """).first
        let oneHzCount = oneHzRow?.int("c") ?? 0
        let rrCount = try count("decoded_rr")
        let rawArchiveCount = try count("raw_archive_frames")
        let liveCoverageCount = try count("live_coverage")
        let strapTrim = try cursorValue("strap_trim")
        let battRow = try db.query("""
            SELECT battery_pct, charging FROM band_battery
            WHERE battery_pct IS NOT NULL
            ORDER BY ts DESC LIMIT 1
            """).first
        return WhoopSubstrateSummary(
            oneHzCount: oneHzCount,
            rrCount: rrCount,
            rawArchiveCount: rawArchiveCount,
            liveCoverageCount: liveCoverageCount,
            oldestRecTs: oneHzCount > 0 ? oneHzRow?.optionalInt("min_ts") : nil,
            latestRecTs: oneHzCount > 0 ? oneHzRow?.optionalInt("max_ts") : nil,
            latestCounter: oneHzCount > 0 ? oneHzRow?.optionalInt("max_c") : nil,
            strapTrimHex: strapTrim,
            latestBatteryPct: battRow?.optionalDouble("battery_pct"),
            latestCharging: battRow?.optionalInt("charging").map { $0 != 0 })
    }

    private static func hexToData(_ hex: String) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex, let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) {
            if let b = UInt8(hex[idx..<next], radix: 16) { bytes.append(b) }
            idx = next
        }
        return Data(bytes)
    }
}

public struct WhoopDatabaseFileService {
    public static let notWhoopDatabase = "This is not a WHOOP / OpenStrap database"
    private static let sqliteHeader = Array("SQLite format 3\0".utf8)
    private static let requiredTables: Set<String> = ["decoded_onehz", "decoded_rr", "sync_cursor"]

    public let location: AppDatabaseLocation

    public init(location: AppDatabaseLocation) {
        self.location = location
    }

    public var databaseURL: URL { location.directory.appendingPathComponent("whoop.sqlite") }
    public var exists: Bool { FileManager.default.fileExists(atPath: databaseURL.path) }

    public func openLiveStore() throws -> WhoopStore? {
        guard exists else { return nil }
        return try WhoopStore(try Database(path: databaseURL.path))
    }

    public func openOrCreateLiveStore() throws -> WhoopStore {
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        return try WhoopStore(try Database(path: databaseURL.path))
    }

    public func validate(fileAt url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { throw ValidationError(Self.notWhoopDatabase) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: Self.sqliteHeader.count)) ?? Data()
        guard Array(header) == Self.sqliteHeader else { throw ValidationError(Self.notWhoopDatabase) }

        let probe = try Database(path: url.path, readOnly: true)
        let tables = Set(try probe.query("SELECT name FROM sqlite_master WHERE type = 'table'").map { $0.text("name") })
        guard Self.requiredTables.isSubset(of: tables) else { throw ValidationError(Self.notWhoopDatabase) }
    }

    public func importDatabase(from source: URL, today: ISODate? = nil) throws {
        try validate(fileAt: source)
        let fm = FileManager.default
        try fm.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let staged = location.directory.appendingPathComponent(".whoop-import-\(UUID().uuidString).tmp")
        do {
            try fm.copyItem(at: source, to: staged)
            try validate(fileAt: staged)
            _ = try WhoopStore(try Database(path: staged.path))
            if exists {
                if let today {
                    try fm.createDirectory(at: location.backupsDirectory, withIntermediateDirectories: true)
                    var n = 1
                    var backup: URL
                    repeat {
                        backup = location.backupsDirectory.appendingPathComponent("whoop-before-import-\(today)-\(n).sqlite")
                        n += 1
                    } while fm.fileExists(atPath: backup.path)
                    try fm.moveItem(at: databaseURL, to: backup)
                } else {
                    try fm.removeItem(at: databaseURL)
                }
                for suffix in ["-wal", "-shm", "-journal"] {
                    try? fm.removeItem(atPath: databaseURL.path + suffix)
                }
            }
            try fm.moveItem(at: staged, to: databaseURL)
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
    }

    public func export(from db: Database, today: ISODate, to directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var target = directory.appendingPathComponent("whoop-\(today).sqlite")
        var suffix = 2
        while fm.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("whoop-\(today)-\(suffix).sqlite")
            suffix += 1
        }
        do {
            try db.execute("VACUUM INTO ?", [.text(target.path)])
            try validate(fileAt: target)
        } catch {
            try? fm.removeItem(at: target)
            throw error
        }
        return target
    }

    public func filesInDocuments() -> [URL] {
        let fm = FileManager.default
        var candidates: [URL] = []
        for dir in [location.directory, location.inboxDirectory] {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                let ext = item.pathExtension.lowercased()
                let name = item.lastPathComponent.lowercased()
                guard ext == "sqlite" || ext == "db" else { continue }
                guard name != "fitness.sqlite" && name != "whoop.sqlite" && !name.hasPrefix("fitness-") else { continue }
                if (try? validate(fileAt: item)) != nil {
                    candidates.append(item)
                }
            }
        }
        return candidates.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
