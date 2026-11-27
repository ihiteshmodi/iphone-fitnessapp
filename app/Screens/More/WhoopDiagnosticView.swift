import FitnessCore
import SwiftUI

/// Standalone hardware verification console wired directly to `WhoopBLEManager` and `WhoopStore` (`whoop.sqlite`)
/// for verifying real WHOOP 4.0 / 5.0 / MG connectivity, burst/CRC/0x17 invariants, and WAL-checkpointed SQLite data inside LiveContainer.
struct WhoopDiagnosticView: View {
    private struct DiagnosticShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    @EnvironmentObject private var whoop: WhoopBLEManager
    @Environment(\.dismiss) private var dismiss

    var showsCloseButton = false

    @State private var shareItem: DiagnosticShareItem?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let warning = whoop.faultWarning {
                    faultBanner(warning)
                }
                connectionAndHandshakeCard
                liveAndBurstCountersCard
                sqliteInspectorAndExporterCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .screenBackground()
        .navigationTitle("WHOOP Diagnostic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("whoop-diag-done")
                }
            }
        }
        .onAppear {
            whoop.refreshDiagnosticInspection(createIfMissing: true)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .errorAlert($errorMessage)
    }

    // MARK: 1. Connection & Handshake Telemetry

    private var connectionAndHandshakeCard: some View {
        let hs = whoop.handshake
        let pct = hs.batteryPct ?? whoop.batteryPct
        let chg = hs.charging ?? whoop.charging
        let wrist = hs.wristOn ?? whoop.wristOn

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("1 · Connection & Handshake")
                Spacer()
                phaseBadge
            }

            VStack(spacing: 6) {
                kvRow("Central state", whoop.centralStateLabel, id: "whoop-diag-central-state")
                kvRow("Conn phase", whoop.phase.rawValue)
                kvRow("Peripheral name", whoop.connectedName ?? "—")
                kvRow("Peripheral UUID", whoop.peripheralUUID ?? "—", id: "whoop-diag-uuid")
                kvRow("Generation (0x91/0x23)", hs.detectedGeneration ?? "—", id: "whoop-diag-generation")
                kvRow("Firmware", firmwareText(hs), id: "whoop-diag-firmware")
                kvRow("Serial", hs.serialNumber ?? whoop.serialNumber ?? "—")
                kvRow("Battery", pct.map { String(format: "%.1f%%", $0) } ?? "—", id: "whoop-diag-battery")
                kvRow("Charging", boolText(chg, yes: "Yes ⚡", no: "No"))
                kvRow("Wrist", boolText(wrist, yes: "On-wrist", no: "Off-wrist"))
            }

            Text(whoop.lastSyncNote)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Theme.background.cornerRadius(6))
                .accessibilityIdentifier("whoop-diag-status-note")

            HStack(spacing: 8) {
                Button("Connect") {
                    whoop.connectButtonTapped()
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("whoop-diag-connect-button")

                Button("Disconnect") {
                    whoop.disconnectButtonTapped()
                }
                .buttonStyle(PrimaryButtonStyle(ghost: true))
                .accessibilityIdentifier("whoop-diag-disconnect-button")
            }

            Button("Force History Drain (0x16)") {
                whoop.forceHistoryDrain()
            }
            .buttonStyle(PrimaryButtonStyle(ghost: whoop.phase != .listening))
            .accessibilityIdentifier("whoop-diag-force-drain-button")

            if !whoop.discoveredDevices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Discovered WHOOP Peripherals")
                    ForEach(whoop.discoveredDevices) { dev in
                        Button {
                            whoop.connect(to: dev)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dev.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Theme.text)
                                    Text("\(dev.id.uuidString) · \(dev.rssi) dBm")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(Theme.muted)
                                }
                                Spacer()
                                Text("Pair")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Theme.green)
                            }
                            .padding(8)
                            .background(Theme.background.cornerRadius(8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if whoop.peripheralUUID != nil {
                Button("Forget saved strap UUID") {
                    whoop.disconnectAndForget()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.muted)
            }
        }
        .card()
    }

    // MARK: 2. Live & Burst Counters

    private var liveAndBurstCountersCard: some View {
        let b = whoop.burst
        let liveHr = b.liveHrBpm ?? whoop.liveHrBpm
        let rrText = b.liveRrMs.isEmpty ? "—" : b.liveRrMs.map(String.init).joined(separator: ", ") + " ms"
        let inFlightTotal = b.currentBurstDataPackets + b.currentBurstInlinePackets
        let burstCountSummary: String = {
            if b.offloadActive {
                return "in-flight: \(inFlightTotal) (\(b.currentBurstDataPackets) data + \(b.currentBurstInlinePackets) inline)"
            }
            if let exp = b.lastExpectedPacketCount, let act = b.lastActualPacketCount {
                return "expected \(exp) vs actual \(act)"
            }
            return "expected — vs actual 0"
        }()

        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("2 · Live & Burst Counters")

            VStack(spacing: 6) {
                kvRow("Live 0x28 HR", liveHr.map { "\($0) bpm" } ?? "—",
                      valueColor: liveHr != nil ? Theme.green : Theme.text,
                      id: "whoop-diag-live-hr")
                kvRow("Live 0x28 RR", rrText, id: "whoop-diag-live-rr")
                kvRow("Rolling CRC errors", "\(b.rollingCrcErrorCount) (hdr \(b.headerCrcErrors) · crc32 \(b.payloadCrc32Errors) · resync \(b.resyncCount))",
                      valueColor: b.rollingCrcErrorCount == 0 ? Theme.text : Theme.amber,
                      id: "whoop-diag-crc-errors")
                kvRow("BurstStats", burstCountSummary, id: "whoop-diag-burst-stats")
                kvRow("Last 0x17 verdict", verdictDisplay(b),
                      valueColor: verdictColor(b),
                      id: "whoop-diag-ack-verdict")
                kvRow("0x17 totals", "OK \(b.ackOkCount) · NACK \(b.nackCount)")
                if let tok = b.lastAckTokenHex {
                    kvRow("Last 0x17 token", tok)
                }
            }
        }
        .card()
    }

    // MARK: 3. SQLite Schema & Row Inspector + Exporter

    private var sqliteInspectorAndExporterCard: some View {
        let snap = whoop.sqliteInspection
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel("3 · SQLite Schema & Row Inspector")
                Spacer()
                Button("Refresh") {
                    whoop.refreshDiagnosticInspection(createIfMissing: true)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.green)
                .accessibilityIdentifier("whoop-diag-refresh-sqlite")
            }

            if let snap {
                VStack(spacing: 6) {
                    kvRow("Schema tables (\(snap.schemaTables.count))", snap.schemaTables.joined(separator: ", "))
                    kvRow("decoded_onehz rows", Format.grouped(Double(snap.oneHzCount)), id: "whoop-diag-onehz-count")
                    kvRow("decoded_rr rows", Format.grouped(Double(snap.rrCount)), id: "whoop-diag-rr-count")
                    kvRow("raw_archive_frames", Format.grouped(Double(snap.rawArchiveCount)))
                    kvRow("live_coverage", Format.grouped(Double(snap.liveCoverageCount)))
                    kvRow("band_battery / backlog", "\(snap.batteryCount) / \(snap.backlogCount)")
                    kvRow("band_events", "\(snap.eventsCount)")
                    kvRow("cursor rec_ts_hw", snap.recTsHw ?? "—")
                    kvRow("cursor counter_hw", snap.counterHw ?? "—")
                    kvRow("cursor strap_trim", snap.strapTrimHex ?? "—")
                }

                Divider().overlay(Theme.muted.opacity(0.25))

                Text("Latest 5 · decoded_onehz")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.text)

                if snap.latestOneHzRows.isEmpty {
                    Text("0 rows in decoded_onehz yet.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.muted)
                        .accessibilityIdentifier("whoop-diag-onehz-empty")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(snap.latestOneHzRows) { row in
                            oneHzRowCard(row)
                        }
                    }
                    .accessibilityIdentifier("whoop-diag-onehz-list")
                }

                Divider().overlay(Theme.muted.opacity(0.25))

                Text("Latest 5 · decoded_rr")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.text)

                if snap.latestRrRows.isEmpty {
                    Text("0 rows in decoded_rr yet.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.muted)
                        .accessibilityIdentifier("whoop-diag-rr-empty")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(snap.latestRrRows) { row in
                            rrRowCard(row)
                        }
                    }
                    .accessibilityIdentifier("whoop-diag-rr-list")
                }
            } else {
                Text("Initializing whoop.sqlite…")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
            }

            Button("Export whoop.sqlite (WAL Checkpointed)") {
                do {
                    let exported = try whoop.exportCheckpointedDiagnosticDatabase()
                    shareItem = DiagnosticShareItem(url: exported)
                } catch {
                    errorMessage = MoreErrorText.message(for: error)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("whoop-diag-export-sqlite-button")

            Text("Runs PRAGMA wal_checkpoint(TRUNCATE) before copying so all WAL frames are merged into a standalone SQLite file for Mac inspection.")
                .font(.system(size: 11))
                .foregroundColor(Theme.muted)
        }
        .card()
    }

    // MARK: Helpers

    private func faultBanner(_ warning: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("BLE / SQLite Alert")
            Text(warning)
                .font(.system(size: 12))
                .foregroundColor(Theme.amber)
        }
        .card()
    }

    private var phaseBadge: some View {
        let text = whoop.offloadActive ? "DRAINING" : whoop.phase.rawValue.uppercased()
        let color: Color = {
            switch whoop.phase {
            case .listening: return Theme.green
            case .scanning, .connecting, .discovering, .subscribing, .settingUp, .reconnecting: return Theme.amber
            case .idle, .error: return Theme.muted
            }
        }()
        return Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14).cornerRadius(6))
    }

    private func kvRow(_ key: String, _ value: String, valueColor: Color = Theme.text, id: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
            Spacer(minLength: 8)
            if let id {
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(valueColor)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                    .accessibilityIdentifier(id)
            } else {
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(valueColor)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }

    private func oneHzRowCard(_ r: WhoopOneHzInspectorRow) -> some View {
        let hrStr = r.hr.map { "\($0)" } ?? "NULL"
        let subStr = r.tsSubsec.map(String.init) ?? "NULL"
        let accelStr: String = {
            guard let x = r.ax, let y = r.ay, let z = r.az else { return "NULL" }
            return String(format: "%.3f / %.3f / %.3f", x, y, z)
        }()
        let tempCStr = r.skinTempC.map { String(format: "%.2f°C", $0) } ?? "NULL"
        let tempRawStr = r.skinTempRaw.map(String.init) ?? "NULL"

        return VStack(alignment: .leading, spacing: 3) {
            Text("ts_ms: \(r.tsMs) · subsec: \(subStr) · hr: \(hrStr)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.text)
            Text("ax/ay/az: \(accelStr)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.muted)
            Text("skin_temp: \(tempCStr) (raw: \(tempRawStr)) · ctr: \(r.counter)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Theme.background.cornerRadius(6))
    }

    private func rrRowCard(_ r: WhoopRrInspectorRow) -> some View {
        let beatStr = r.beatTsMs.map(String.init) ?? "NULL"
        return HStack {
            Text("rr_ms: \(r.rrMs)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.green)
            Spacer()
            Text("beat_ts_ms: \(beatStr) [#\(r.beatIndex)]")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.muted)
        }
        .padding(8)
        .background(Theme.background.cornerRadius(6))
    }

    private func firmwareText(_ hs: WhoopHandshakeTelemetry) -> String {
        guard let fw = hs.firmwareVersion else { return "—" }
        if let sp = hs.sigprocVersion {
            return "\(fw) (sp \(sp))"
        }
        return fw
    }

    private func boolText(_ value: Bool?, yes: String, no: String) -> String {
        guard let value else { return "—" }
        return value ? yes : no
    }

    private func verdictDisplay(_ b: WhoopBurstTelemetry) -> String {
        guard let wasNack = b.lastAckWasNack else { return "—" }
        return wasNack ? "\(b.lastAckVerdict) (NACK)" : "\(b.lastAckVerdict) (0x17 OK)"
    }

    private func verdictColor(_ b: WhoopBurstTelemetry) -> Color {
        guard let wasNack = b.lastAckWasNack else { return Theme.muted }
        return wasNack ? Theme.amber : Theme.green
    }
}
