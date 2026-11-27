import FitnessCore
import SwiftUI

struct WhoopBandView: View {
    private struct WhoopShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    @EnvironmentObject private var whoop: WhoopBLEManager
    @EnvironmentObject private var session: AppSession

    @State private var shareItem: WhoopShareItem?
    @State private var isWhoopImporterPresented = false
    @State private var isWhoopMergePresented = false
    @State private var whoopImportedNotice = false
    @State private var mergeNoticeMessage: String?
    @State private var whoopFileToRestore: URL?
    @State private var liveHrEnabled = true
    @State private var confirmRestartStrap = false
    @State private var hardwareFeedbackNote: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                connectionCard
                if let warning = whoop.faultWarning {
                    faultCard(warning)
                }
                syncProgressCard
                syncProvenanceCard
                hardwareControlsCard
                WhoopSilentAlarmsSection()
                batteryHistoryChartCard
                liveTelemetryCard
                substrateSummaryCard
                whoopDatabaseCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .screenBackground()
        .navigationTitle("WHOOP Band")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { whoop.refreshSummaryAndFiles() }
        .onChange(of: whoop.autoDerivationRevision) { _ in
            session.didChange()
        }
        .confirmationDialog(
            "Restart WHOOP strap (0x1D)?",
            isPresented: $confirmRestartStrap,
            titleVisibility: .visible
        ) {
            Button("Restart Band Now (0x1D)", role: .destructive) {
                let sent = whoop.restartStrapConfirmed()
                hardwareFeedbackNote = sent
                    ? "Sent 0x1D reboot — strap will restart and reconnect automatically via StandingConnect."
                    : "Band not connected — pair or bring strap in range first."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sends user-gated 0x1D REBOOT_STRAP. Flash pages stay intact and StandingConnect re-attaches once reboot completes.")
        }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
        .whoopFileImporter(isPresented: $isWhoopImporterPresented, errorMessage: $errorMessage) {
            whoopImportedNotice = true
        }
        .whoopMergeFileImporter(isPresented: $isWhoopMergePresented, errorMessage: $errorMessage) { res in
            mergeNoticeMessage = "Merged +\(Format.grouped(Double(res.addedOneHzRows))) historical 1 Hz rows and +\(Format.grouped(Double(res.addedRrRows))) RR beats without overwriting your live BLE syncs."
        }
        .confirmationDialog(
            "Import or merge this WHOOP file?",
            isPresented: Binding(get: { whoopFileToRestore != nil }, set: { if !$0 { whoopFileToRestore = nil } }),
            titleVisibility: .visible,
            presenting: whoopFileToRestore
        ) { url in
            Button("Merge older history from \(url.lastPathComponent)") {
                run {
                    let res = try whoop.mergeWhoopDatabase(from: url)
                    mergeNoticeMessage = "Merged +\(Format.grouped(Double(res.addedOneHzRows))) historical 1 Hz rows and +\(Format.grouped(Double(res.addedRrRows))) RR beats."
                }
            }
            Button("Replace entire DB with \(url.lastPathComponent)", role: .destructive) {
                run {
                    try whoop.importWhoopDatabase(from: url)
                    whoopImportedNotice = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Merge keeps all newer BLE rows synced by this app and fills in older OpenStrap history. Replace swaps the whole whoop.sqlite file (saving a backup first).")
        }
        .alert("WHOOP database imported", isPresented: $whoopImportedNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("OpenStrap / WHOOP telemetry substrate loaded into whoop.sqlite.")
        }
        .alert("OpenStrap history merged", isPresented: Binding(get: { mergeNoticeMessage != nil }, set: { if !$0 { mergeNoticeMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mergeNoticeMessage ?? "")
        }
        .errorAlert($errorMessage)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("BLE Transport")
                Spacer()
                statusBadge
            }

            if let name = whoop.connectedName {
                HStack(spacing: 8) {
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .foregroundColor(Theme.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.text)
                        Text(deviceSubtitle)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.muted)
                    }
                }
            } else {
                Text("Supports WHOOP 4.0 (Harvard), WHOOP 5.0, and WHOOP MG (Maverick) with StandingConnect background sync.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.muted)
            }

            Text(whoop.lastSyncNote)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.muted)
                .accessibilityIdentifier("whoop-sync-note")

            HStack(spacing: 10) {
                if whoop.phase == .scanning {
                    Button("Stop scan") { whoop.stopScan() }
                        .buttonStyle(PrimaryButtonStyle(ghost: true))
                        .accessibilityIdentifier("whoop-stop-scan-button")
                } else {
                    Button("Scan for Band") { whoop.startScan() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("whoop-scan-button")
                }

                if whoop.phase == .listening {
                    Button("Sync Backfill") { whoop.triggerManualSync() }
                        .buttonStyle(PrimaryButtonStyle(ghost: true))
                        .accessibilityIdentifier("whoop-sync-backfill-button")
                }
            }

            if !whoop.discoveredDevices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Nearby Straps")
                    ForEach(whoop.discoveredDevices) { dev in
                        Button {
                            whoop.connect(to: dev)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dev.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Theme.text)
                                    Text("\(dev.profile.isGen5 ? "Gen 5 / MG" : "Gen 4") · \(dev.rssi) dBm")
                                        .font(.system(size: 12))
                                        .foregroundColor(Theme.muted)
                                }
                                Spacer()
                                Text("Connect")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.green)
                            }
                            .padding(10)
                            .background(Theme.background.cornerRadius(8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if whoop.connectedName != nil {
                Button("Disconnect & forget strap") { whoop.disconnectAndForget() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.amber)
                    .padding(.top, 2)
            }
        }
        .card()
    }

    private func faultCard(_ warning: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Radio / Bond Guard")
            Text(warning)
                .font(.system(size: 13))
                .foregroundColor(Theme.amber)
        }
        .card()
    }

    private var syncProgressCard: some View {
        let sp = whoop.syncProgress
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Historical Flash Sync Progress")
                Spacer()
                Pill(text: sp.isSyncing ? "Draining 0x2F" : "Auto-derive on wake", tone: sp.isSyncing ? .amber : .green)
            }

            Text(sp.statusText())
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(Theme.text)
                .accessibilityIdentifier("whoop-sync-progress-status")

            GeometryReader { proxy in
                let fillFrac = sp.isSyncing ? max(0.05, sp.progress) : (sp.frontierTs != nil ? 1.0 : 0.0)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule()
                        .fill(sp.isSyncing ? Theme.gold : Theme.green)
                        .frame(width: proxy.size.width * fillFrac)
                }
            }
            .frame(height: 8)

            HStack {
                Text("Sub-second ts_subsec + beat_ts_ms verified before 0x17 ACK")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
                Spacer()
                if sp.recordsSyncedThisSession > 0 {
                    Text("+\(sp.recordsSyncedThisSession) rows")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.green)
                }
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-sync-progress-card")
    }

    private var hardwareControlsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Hardware Controls & Haptic Test")
                Spacer()
                Pill(text: whoop.activeBandProfile.isGen5 ? "Gen5 0x13 / 0x1D" : "Gen4 0x4F / 0x1D", tone: .grey)
            }

            HStack(spacing: 10) {
                Button("Vibration Test") {
                    let sent = whoop.triggerVibrationTest(loops: 2)
                    hardwareFeedbackNote = sent
                        ? "Triggered wrist haptic motor test (\(whoop.activeBandProfile.isGen5 ? "0x13 Maverick" : "0x4F"))."
                        : "Band offline — connect strap above to feel haptic vibration."
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("whoop-vibration-test-button")

                Button("Restart Band") {
                    confirmRestartStrap = true
                }
                .buttonStyle(PrimaryButtonStyle(ghost: true))
                .accessibilityIdentifier("whoop-restart-band-button")
            }

            if let hardwareFeedbackNote {
                Text(hardwareFeedbackNote)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.green)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-hardware-controls-card")
    }

    private var batteryHistoryChartCard: some View {
        let rows = whoop.batteryHistoryRows
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Battery Drain & Charging History")
                Spacer()
                if let pct = whoop.batteryPct {
                    Pill(text: String(format: "%.0f%%%@", pct, whoop.charging == true ? " ⚡" : ""), tone: pct >= 25 ? .green : .amber)
                }
            }

            if rows.count >= 2 {
                let pts: [ChartPoint] = rows.suffix(20).map { r in
                    ChartPoint(label: Self.shortDate(r.ts), value: r.batteryPct ?? 0, series: "Battery %")
                }
                TrendChart(points: pts, height: 118, seriesColors: ["Battery %": Theme.green])
                let chgEvents = rows.filter { $0.charging == true }.count
                Text("\(rows.count) logged battery telemetry samples · \(chgEvents) charging event(s)")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.muted)
            } else if let single = rows.first, let pct = single.batteryPct {
                Text("Latest logged battery: \(String(format: "%.1f%%", pct)) (\(Self.dateTime(single.ts)))\(single.charging == true ? " · Charging ⚡" : ""). Drain curve populates as additional syncs/events arrive.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
            } else {
                Text("Battery percentage & charging events (Event 3 / 0x91 GET_HELLO) log automatically to band_battery on every connection.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-battery-chart-card")
    }

    private var syncProvenanceCard: some View {
        let s = whoop.substrateSummary
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Sync Freshness & Provenance")
                Spacer()
                if let syncSec = s?.lastAppSyncAtSec {
                    Pill(text: Self.isToday(syncSec) ? "Synced today" : "Synced", tone: .green)
                } else if (s?.oneHzCount ?? 0) > 0 {
                    Pill(text: "Imported DB", tone: .amber)
                } else {
                    Pill(text: "No data yet", tone: .grey)
                }
            }

            if let s, s.oneHzCount > 0 {
                VStack(spacing: 6) {
                    if let latest = s.latestRecTs {
                        summaryRow("Data through", "\(Self.dateTime(latest)) (\(Self.relativeAgo(latest)))")
                    }
                    if let syncSec = s.lastAppSyncAtSec {
                        summaryRow("Last BLE sync here", Self.dateTime(syncSec))
                    } else {
                        summaryRow("Last BLE sync here", "Not synced in this app yet")
                    }
                    summaryRow("Synced by this app", "+\(Format.grouped(Double(s.appSyncedOneHzCount))) 1 Hz rows (\(Self.durationText(seconds: s.appSyncedOneHzCount)))")
                    if s.importedBaselineOneHzCount > 0 {
                        let baseEnd = s.importedBaselineMaxRecTs.map { " · through \(Self.shortDate($0))" } ?? ""
                        summaryRow("Imported / merged history", "\(Format.grouped(Double(s.importedBaselineOneHzCount))) rows\(baseEnd)")
                    }
                }
            } else {
                Text("Connect your WHOOP band above — every 1 Hz burst synced by this app and any merged OpenStrap history are tracked separately here.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.muted)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-sync-provenance-card")
    }

    private var liveTelemetryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Strap Telemetry")
            HStack(spacing: 12) {
                metricPill(
                    label: "Live HR",
                    value: whoop.liveHrBpm.map { "\($0) bpm" } ?? "—",
                    accent: whoop.liveHrBpm != nil ? Theme.green : Theme.muted)
                metricPill(
                    label: "Battery",
                    value: whoop.batteryPct.map { String(format: "%.1f%%", $0) + (whoop.charging == true ? " ⚡" : "") } ?? "—",
                    accent: Theme.text)
                metricPill(
                    label: "Wrist",
                    value: whoop.wristOn.map { $0 ? "On-wrist" : "Off-wrist" } ?? "—",
                    accent: whoop.wristOn == true ? Theme.green : Theme.muted)
            }

            if whoop.phase == .listening {
                Toggle("Live Heart Rate stream (0x03)", isOn: $liveHrEnabled)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text)
                    .tint(Theme.green)
                    .onChange(of: liveHrEnabled) { enabled in
                        whoop.toggleLiveHeartRate(enabled)
                    }
            }
        }
        .card()
    }

    private var substrateSummaryCard: some View {
        let s = whoop.substrateSummary
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Local Substrate (whoop.sqlite)")
            if let s {
                VStack(spacing: 8) {
                    summaryRow("1 Hz records (decoded_onehz)", Format.grouped(Double(s.oneHzCount)))
                    summaryRow("RR intervals (decoded_rr)", Format.grouped(Double(s.rrCount)))
                    summaryRow("Raw archive frames", Format.grouped(Double(s.rawArchiveCount)))
                    summaryRow("Live step windows", Format.grouped(Double(s.liveCoverageCount)))
                    if let oldest = s.oldestRecTs, let newest = s.latestRecTs {
                        summaryRow("Recorded span", "\(Self.shortDate(oldest)) → \(Self.shortDate(newest))")
                    }
                    if let trim = s.strapTrimHex {
                        summaryRow("Trim cursor", trim)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("whoop-substrate-summary")
            } else {
                Text("No whoop.sqlite loaded yet. Sync a band or load your OpenStrap database below.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.muted)
                    .accessibilityIdentifier("whoop-substrate-empty")
            }
        }
        .card()
    }

    private var whoopDatabaseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("WHOOP Database Backup")
            Text("Stored separately from fitness.sqlite so 500k+ 1 Hz rows never slow down weekly workout/diet/labs backups.")
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)

            if whoop.hasBundledWhoopDatabase {
                Button("Load bundled OpenStrap data") {
                    run {
                        try whoop.loadBundledWhoopData()
                        whoopImportedNotice = true
                    }
                }
                .buttonStyle(PrimaryButtonStyle(ghost: whoop.hasWhoopDatabase))
                .accessibilityIdentifier("load-bundled-whoop-button")
            }

            if whoop.hasWhoopDatabase {
                Button("Export WHOOP database (.sqlite)") {
                    run { shareItem = WhoopShareItem(url: try whoop.exportWhoopDatabase()) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("export-whoop-database-button")

                Button("Merge older OpenStrap history (.db / .sqlite)") {
                    isWhoopMergePresented = true
                }
                .buttonStyle(PrimaryButtonStyle(ghost: true))
                .accessibilityIdentifier("merge-whoop-database-button")
            }

            Button(whoop.hasWhoopDatabase ? "Replace WHOOP database (.db / .sqlite)" : "Import OpenStrap / WHOOP database (.db / .sqlite)") {
                isWhoopImporterPresented = true
            }
            .buttonStyle(PrimaryButtonStyle(ghost: true))
            .accessibilityIdentifier("import-whoop-database-button")

            if !whoop.foundWhoopFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("WHOOP files in Documents")
                    ForEach(whoop.foundWhoopFiles, id: \.self) { url in
                        Button("Merge / Import \(url.lastPathComponent)") { whoopFileToRestore = url }
                            .buttonStyle(PrimaryButtonStyle(ghost: true))
                            .accessibilityIdentifier("restore-whoop-\(url.lastPathComponent)")
                    }
                }
            }
        }
        .card()
    }

    private var statusBadge: some View {
        let label = whoop.offloadActive ? "Syncing burst" : whoop.phase.rawValue.capitalized
        let color: Color = {
            switch whoop.phase {
            case .listening: return Theme.green
            case .scanning, .connecting, .discovering, .subscribing, .settingUp, .reconnecting: return Theme.amber
            case .idle, .error: return Theme.muted
            }
        }()
        return Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14).cornerRadius(6))
            .accessibilityIdentifier("whoop-phase-badge")
    }

    private var deviceSubtitle: String {
        var parts: [String] = []
        parts.append(whoop.isMaverick ? "WHOOP MG (Maverick)" : "WHOOP Strap")
        if let sn = whoop.serialNumber { parts.append(sn) }
        return parts.joined(separator: " · ")
    }

    private func metricPill(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(Theme.muted)
            Text(value).font(.system(size: 15, weight: .bold)).foregroundColor(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.background.cornerRadius(8))
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundColor(Theme.muted)
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundColor(Theme.text)
        }
    }


    static func dateTime(_ epochSec: Int) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(epochSec))
        let f = DateFormatter()
        f.dateFormat = "dd MMM, HH:mm"
        return f.string(from: d)
    }

    static func isToday(_ epochSec: Int) -> Bool {
        Calendar.current.isDateInToday(Date(timeIntervalSince1970: TimeInterval(epochSec)))
    }

    static func relativeAgo(_ epochSec: Int) -> String {
        let delta = max(0, Int(Date().timeIntervalSince1970) - epochSec)
        if delta < 90 { return "just now" }
        if delta < 3600 { return "\(delta / 60)m ago" }
        if delta < 86_400 { return "\(delta / 3600)h ago" }
        return "\(delta / 86_400)d ago"
    }

    static func durationText(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        let h = Double(seconds) / 3600.0
        if h < 48 { return String(format: "%.1fh", h) }
        return String(format: "%.1fd", h / 24.0)
    }
    private static func shortDate(_ epochSec: Int) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(epochSec))
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = MoreErrorText.message(for: error) }
    }
}
