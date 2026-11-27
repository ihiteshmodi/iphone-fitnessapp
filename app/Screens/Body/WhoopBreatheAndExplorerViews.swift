import FitnessCore
import SwiftUI

/// Guided Breathing & Biofeedback Hoop Studio (Physiological Sigh, 4-7-8, Box, Resonance 5.5, L2 Calm Me)
/// + 24-Hour Baevsky Stress Curve + Three-Process Alertness Forecast.
struct WhoopBreatheAndStressView: View {
    let initialDay: ISODate
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager

    @State private var selectedProtocolId = "physiological_sigh"
    @State private var calmMeMode = false
    @State private var targetMinutes = 5
    @State private var wristHapticsEnabled = true
    @State private var isRunning = false
    @State private var sessionStartMs: Int64?
    @State private var elapsedMs = 0
    @State private var lastPhaseIndex = -1
    @State private var lastCycleNum = 0
    @State private var stressPoints: [WhoopHourlyStressPoint] = []
    @State private var alertness: WhoopAlertnessForecast?
    @State private var rsaRespRateText: String?
    @State private var savedBanner: String?

    private let tickTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var activeProtocol: WhoopBreathProtocol {
        WhoopBreathProtocolCatalog.all.first { $0.id == selectedProtocolId } ?? WhoopBreathProtocolCatalog.all[0]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                breathingStudioCard
                stressCurveCard
                alertnessForecastCard
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Stress & Breathe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear(perform: reloadCurves)
        .onReceive(tickTimer) { _ in
            guard isRunning, let start = sessionStartMs else { return }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            elapsedMs = max(0, Int(nowMs - start))

            if calmMeMode {
                let curHr = Double(whoop.liveHrBpm ?? 76)
                if curHr <= WhoopHrDownPacer.calmTargetBpm || elapsedMs >= WhoopHrDownPacer.maxDurationSec * 1000 {
                    finishBreathingSession()
                    return
                }
                let ivMs = WhoopHrDownPacer.intervalMs(currentHr: curHr, elapsedSec: Double(elapsedMs) / 1000.0)
                let beatCycle = elapsedMs / max(500, ivMs)
                if beatCycle != lastCycleNum {
                    lastCycleNum = beatCycle
                    if wristHapticsEnabled {
                        _ = whoop.triggerVibrationTest(loops: 1)
                    }
                }
            } else {
                if elapsedMs >= targetMinutes * 60 * 1000 {
                    finishBreathingSession()
                    return
                }
                let snap = activeProtocol.phaseAt(elapsedMs: elapsedMs)
                if snap.stageIndex != lastPhaseIndex || snap.cycleNumber != lastCycleNum {
                    lastPhaseIndex = snap.stageIndex
                    lastCycleNum = snap.cycleNumber
                    if wristHapticsEnabled && snap.hapticLoops > 0 {
                        _ = whoop.triggerVibrationTest(loops: snap.hapticLoops)
                    }
                }
            }
        }
    }

    private var breathingStudioCard: some View {
        let phaseSnap = activeProtocol.phaseAt(elapsedMs: elapsedMs)
        let totalTargetMs = max(1, (calmMeMode ? 180 : targetMinutes * 60) * 1000)
        let sessionFrac = isRunning ? min(1.0, Double(elapsedMs) / Double(totalTargetMs)) : 0.15
        let outerProg: Double = {
            guard isRunning else { return 0.72 }
            if calmMeMode {
                let cur = Double(whoop.liveHrBpm ?? 76)
                let tgt = WhoopHrDownPacer.targetBpm(currentHr: cur, elapsedSec: Double(elapsedMs) / 1000.0)
                return min(1.0, max(0.15, tgt / 100.0))
            }
            return phaseSnap.kind == .exhale ? max(0.08, 1.0 - phaseSnap.stageProgress) : max(0.08, phaseSnap.stageProgress)
        }()

        let centerTitle: String = {
            if !isRunning { return calmMeMode ? "Calm Me" : activeProtocol.title }
            if calmMeMode {
                let cur = Double(whoop.liveHrBpm ?? 76)
                let tgt = Int(WhoopHrDownPacer.targetBpm(currentHr: cur, elapsedSec: Double(elapsedMs) / 1000.0).rounded())
                return "\(tgt) bpm"
            }
            return phaseSnap.label
        }()

        let centerSub: String = {
            if !isRunning {
                if let brpm = activeProtocol.breathsPerMinute {
                    return String(format: "%.1f br/min", brpm)
                }
                return "Guided timer"
            }
            let remSec = max(0, (totalTargetMs - elapsedMs) / 1000)
            return String(format: "%d:%02d left", remSec / 60, remSec % 60)
        }()

        let liveProxy = WhoopCardiacCoherenceEngine.liveRmssdProxy(rrMs: whoop.liveRrMs)

        return VStack(spacing: 12) {
            HStack {
                SectionLabel("Guided Breathing & Wrist Haptic Pacer")
                Spacer()
                if let rsaRespRateText {
                    Pill(text: "Sleep RSA \(rsaRespRateText)", tone: .green)
                }
            }

            // Quick chips for Huberman Physiological Sigh, 4-7-8, Box, Resonance 5.5, and L2 Calm Me
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    quickChip("Physio Sigh", id: "physiological_sigh", isCalm: false)
                    quickChip("4-7-8", id: "four_seven_eight", isCalm: false)
                    quickChip("Box 4-4-4-4", id: "box_4_4_4_4", isCalm: false)
                    quickChip("Resonance 5.5", id: "coherence_5_5", isCalm: false)
                    quickChip("Calm Me (L2)", id: "coherence_5_5", isCalm: true)
                }
            }

            if !calmMeMode {
                HStack {
                    Text("All 23 protocols").font(.system(size: 12.5)).foregroundColor(Theme.muted)
                    Spacer()
                    Picker("Protocol", selection: $selectedProtocolId) {
                        ForEach(WhoopBreathProtocolCatalog.all) { p in
                            Text(p.title).tag(p.id)
                        }
                    }
                    .tint(Theme.green)
                    .accessibilityIdentifier("whoop-breath-protocol-picker")
                }
            }

            ConcentricHoopView(
                outerProgress: sessionFrac,
                innerProgress: outerProg,
                mainLabel: centerTitle,
                subLabel: centerSub,
                innerColor: phaseSnap.kind == .exhale ? Theme.greenSoft : Theme.green,
                size: 172
            )

            Text(calmMeMode ? "Paces 3→8 bpm below your live HR using 1-pulse wrist haptics until HR settles ≤60 bpm." : activeProtocol.subtitle)
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                ForEach([2, 5, 10, 15], id: \.self) { mins in
                    Button("\(mins)m") { targetMinutes = mins }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(targetMinutes == mins ? Theme.onGreen : Theme.muted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(targetMinutes == mins ? Theme.green : Theme.card2)
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                }
                Spacer()
                Toggle("Wrist buzz", isOn: $wristHapticsEnabled)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .tint(Theme.green)
                    .fixedSize()
            }

            if let proxy = liveProxy {
                HStack {
                    Pill(text: proxy.label, tone: .green)
                    Text("Live RMSSD \(Int(proxy.rmssd.rounded())) ms")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text)
                    Spacer()
                }
            }

            Button(isRunning ? "Finish Breathing Session" : "Start Guided Breathing") {
                if isRunning {
                    finishBreathingSession()
                } else {
                    startBreathingSession()
                }
            }
            .buttonStyle(PrimaryButtonStyle(ghost: isRunning))
            .accessibilityIdentifier("whoop-start-breathing-button")

            if let savedBanner {
                Text(savedBanner).font(.system(size: 12)).foregroundColor(Theme.green)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-breathing-studio-card")
    }

    private func quickChip(_ label: String, id: String, isCalm: Bool) -> some View {
        let selected = (isCalm && calmMeMode) || (!isCalm && !calmMeMode && selectedProtocolId == id)
        return Button(label) {
            calmMeMode = isCalm
            selectedProtocolId = id
        }
        .font(.system(size: 12, weight: selected ? .bold : .semibold))
        .foregroundColor(selected ? Theme.onGreen : Theme.text)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(selected ? Theme.green : Theme.card2)
        .clipShape(Capsule())
        .buttonStyle(.plain)
        .accessibilityIdentifier("whoop-breath-chip-\(isCalm ? "calm_me" : id)")
    }

    private var stressCurveCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("24-Hour Baevsky Stress Curve · \(initialDay.string)")
                Spacer()
                Pill(text: "Morning peak → Night taper", tone: .amber)
            }

            if stressPoints.count >= 2 {
                let pts = stressPoints.map {
                    ChartPoint(label: $0.label, value: $0.score, series: "Stress")
                }
                TrendChart(points: pts, height: 132, seriesColors: ["Stress": Theme.amber])
                let wakeAvg = WhoopMath.mean(stressPoints.filter { !$0.isAsleep }.map(\.score)).map { Int($0.rounded()) } ?? 0
                let sleepAvg = WhoopMath.mean(stressPoints.filter(\.isAsleep).map(\.score)).map { Int($0.rounded()) } ?? 0
                Text("Waking mean \(wakeAvg)/100 vs nocturnal sleep mean \(sleepAvg)/100 (Baevsky SI from R-R intervals).")
                    .font(.system(size: 11.5)).foregroundColor(Theme.muted)
            } else {
                Text("No 1 Hz / R-R timeline recorded on \(initialDay.string) yet — wear WHOOP across waking & sleep hours to populate the 24h Baevsky curve.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-stress-curve-card")
    }

    private var alertnessForecastCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Three-Process Circadian Alertness Forecast")
                Spacer()
                if let al = alertness {
                    Pill(text: "Dip \(al.troughLabel)", tone: .green)
                }
            }

            if let al = alertness, al.points.count >= 4 {
                let sampled = stride(from: 0, to: al.points.count, by: max(1, al.points.count / 10)).map { al.points[$0] }
                let pts = sampled.map { ChartPoint(label: $0.clockLabel, value: $0.value * 100.0, series: "Alertness") }
                TrendChart(points: pts, height: 120, seriesColors: ["Alertness": Theme.greenSoft])
                Text("Åkerstedt & Folkard S + C + U − W shape · Lowest 2-hour alertness trough: \(al.troughLabel).")
                    .font(.system(size: 11.5)).foregroundColor(Theme.muted)
            } else {
                Text("Alertness curve populates once last night's wake time and sleep duration are scored.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-alertness-forecast-card")
    }

    private func startBreathingSession() {
        whoop.toggleLiveHeartRate(true)
        sessionStartMs = Int64(Date().timeIntervalSince1970 * 1000)
        elapsedMs = 0
        lastPhaseIndex = -1
        lastCycleNum = -1
        savedBanner = nil
        isRunning = true
    }

    private func finishBreathingSession() {
        isRunning = false
        let secs = max(1, elapsedMs / 1000)
        if let db = whoop.db, let startMs = sessionStartMs {
            let startSec = startMs / 1000
            let endSec = startSec + Int64(secs)
            let rr = whoop.liveRrMs.map(Double.init)
            var tAcc: Int64 = startMs
            let ts = whoop.liveRrMs.map { v -> Int64 in tAcc += Int64(v); return tAcc }
            let coh = WhoopCardiacCoherenceEngine.compute(rrMs: rr, rrTsMs: ts, pacedHz: activeProtocol.pacedHz)
            try? db.execute("""
                INSERT OR REPLACE INTO breathing_session (started_at, ended_at, pattern, seconds, coherence, confidence)
                VALUES (?, ?, ?, ?, ?, ?)
                """, [
                    .int(startSec), .int(endSec), .text(calmMeMode ? "calm_me" : activeProtocol.id),
                    .int(Int64(secs)), .optional(coh?.score), .optional(coh?.confidence),
                ])
            let cohText = coh.map { String(format: " · Coherence %.0f/100", $0.score) } ?? ""
            savedBanner = "Saved \(secs)s \(calmMeMode ? "Calm Me" : activeProtocol.title) session\(cohText)."
        }
        if wristHapticsEnabled {
            _ = whoop.sendRawCommandFrame(WhoopCommands.cmdStopHaptics(seq: 1, profile: whoop.activeBandProfile))
        }
    }

    private func reloadCurves() {
        guard let db = whoop.db,
              let snap = try? WhoopDashboardPresenter.build(whoopDb: db, fitnessDb: services.db, on: initialDay) else {
            return
        }
        let targetDay = ISODate(snap.scoredRecoveryDayId) ?? initialDay
        let rhr = snap.longevity.fitnessAge?.medianRhr ?? 54.0
        let maxHr = Double(snap.zones.maxHrBpm)
        let span: (Int64, Int64)? = {
            guard let on = snap.sleep.onsetSec, let off = snap.sleep.offsetSec else { return nil }
            return (on, off)
        }()
        stressPoints = (try? WhoopStressCurveEngine.build24HourCurve(
            whoopDb: db, day: targetDay, rhr: rhr, maxHr: maxHr, sleepSpan: span
        )) ?? []

        if let respRow = snap.contributors.first(where: { $0.id == "resp" }) {
            rsaRespRateText = "\(respRow.ringLabel) br/m"
        }

        let wakeHour: Double = {
            if let off = snap.sleep.offsetSec {
                let dt = Date(timeIntervalSince1970: TimeInterval(off))
                let c = Calendar.current.dateComponents([.hour, .minute], from: dt)
                return Double(c.hour ?? 7) + Double(c.minute ?? 0) / 60.0
            }
            return 7.0
        }()
        let sleepHrs = snap.sleep.totalSleepMinutes > 0 ? Double(snap.sleep.totalSleepMinutes) / 60.0 : 7.5
        alertness = WhoopAlertnessForecastEngine.compute(wakeLocalHour: wakeHour, sleepDurationHours: sleepHrs)
    }
}

/// Complete 24-Variable Physiological Trend Explorer (`7d` / `30d` / `Custom Date Range`) with 28d Personal Normal Bands.
struct WhoopMetricsExplorerView: View {
    let initialDay: ISODate
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager

    enum RangeWindow: String, CaseIterable {
        case d7 = "7d"
        case d30 = "30d"
        case custom = "Custom"
    }

    @State private var selectedMetricId = "rmssd"
    @State private var rangeWindow: RangeWindow = .d30
    @State private var customStart = Date().addingTimeInterval(-30 * 86_400)
    @State private var customEnd = Date()
    @State private var bundle: WhoopMetricTrendBundle?
    @State private var tempUnit: TemperatureUnitPreference = .celsius

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controlsCard
                chartCard
                allVariablesGrid
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("24-Metric Trends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear {
            tempUnit = (try? services.appDefaults.load().temperatureUnit) ?? .celsius
            if let db = whoop.db,
               let maxDateStr = try? db.query("SELECT MAX(date) AS md FROM metric_series").first?.optionalText("md"),
               let iso = ISODate(maxDateStr) {
                let parts = iso.string.split(separator: "-").compactMap { Int($0) }
                if parts.count == 3, let endDt = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) {
                    customEnd = endDt
                    customStart = endDt.addingTimeInterval(-29 * 86_400)
                }
            }
            reload()
        }
        .onChange(of: selectedMetricId) { _ in reload() }
        .onChange(of: rangeWindow) { _ in reload() }
        .onChange(of: customStart) { _ in reload() }
        .onChange(of: customEnd) { _ in reload() }
        .accessibilityIdentifier("whoop-metrics-explorer-view")
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Physiological Variable (\(WhoopMetricsExplorerService.catalogue.count) tracked)")
            Picker("Variable", selection: $selectedMetricId) {
                ForEach(WhoopMetricsExplorerService.catalogue) { item in
                    Text("\(item.title) (\(item.unit))").tag(item.id)
                }
            }
            .tint(Theme.green)
            .accessibilityIdentifier("whoop-explorer-metric-picker")

            Picker("Range", selection: $rangeWindow) {
                ForEach(RangeWindow.allCases, id: \.rawValue) { w in
                    Text(w.rawValue).tag(w)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("whoop-explorer-range-picker")

            if rangeWindow == .custom {
                HStack {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                        .font(.system(size: 12.5))
                    DatePicker("To", selection: $customEnd, displayedComponents: .date)
                        .font(.system(size: 12.5))
                }
            }
        }
        .card()
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let b = bundle {
                HStack {
                    SectionLabel("\(b.definition.title) · \(rangeWindow.rawValue)")
                    Spacer()
                    if let med = b.median28d {
                        Pill(text: "28d Med \(Format.number(med, maxDecimals: 1)) \(b.definition.unit)", tone: .green)
                    }
                }

                if b.points.count >= 2 {
                    let pts: [ChartPoint] = b.points.flatMap { p -> [ChartPoint] in
                        let shortLbl = String(p.date.suffix(5))
                        var rows = [ChartPoint(label: shortLbl, value: p.value, series: b.definition.title)]
                        if let lo = b.bandLow, let hi = b.bandHigh {
                            rows.append(ChartPoint(label: shortLbl, value: lo, series: "Normal Low"))
                            rows.append(ChartPoint(label: shortLbl, value: hi, series: "Normal High"))
                        }
                        return rows
                    }
                    TrendChart(
                        points: pts,
                        height: 158,
                        seriesColors: [
                            b.definition.title: Theme.green,
                            "Normal Low": Theme.muted.opacity(0.45),
                            "Normal High": Theme.muted.opacity(0.45),
                        ]
                    )
                    if let lo = b.bandLow, let hi = b.bandHigh {
                        Text("Personal normal band (28d median ± 1.48×MAD): \(Format.number(lo, maxDecimals: 1)) – \(Format.number(hi, maxDecimals: 1)) \(b.definition.unit) · \(b.points.count) days plotted.")
                            .font(.system(size: 11.5)).foregroundColor(Theme.muted)
                    }
                } else {
                    Text("Not enough scored days in this date window for \(b.definition.title) yet.")
                        .font(.system(size: 12.5)).foregroundColor(Theme.muted)
                }
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-explorer-chart-card")
    }

    private var allVariablesGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Quick Jump — All \(WhoopMetricsExplorerService.catalogue.count) Physiological Variables")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(WhoopMetricsExplorerService.catalogue) { item in
                    let active = (item.id == selectedMetricId)
                    Button {
                        selectedMetricId = item.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(active ? Theme.onGreen : Theme.text)
                                    .lineLimit(1)
                                Text("\(item.category) · \(item.unit)")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(active ? Theme.onGreen.opacity(0.8) : Theme.muted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(active ? Theme.green : Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("whoop-metric-tile-\(item.id)")
                }
            }
        }
    }

    private func reload() {
        guard let db = whoop.db else { return }
        let anchorStr = (try? db.query("SELECT MAX(date) AS md FROM metric_series WHERE date <= ?", [.text(initialDay.string)]).first?.optionalText("md")) ?? initialDay.string
        let anchorIso = ISODate(anchorStr) ?? initialDay

        let startIso: ISODate
        let endIso: ISODate
        switch rangeWindow {
        case .d7:
            endIso = anchorIso
            startIso = anchorIso.adding(days: -6)
        case .d30:
            endIso = anchorIso
            startIso = anchorIso.adding(days: -29)
        case .custom:
            startIso = isoFromDate(customStart)
            endIso = max(startIso, isoFromDate(customEnd))
        }
        bundle = try? WhoopMetricsExplorerService.loadTrend(
            whoopDb: db, metricId: selectedMetricId, startDate: startIso, endDate: endIso, tempUnit: tempUnit
        )
    }

    private func isoFromDate(_ d: Date) -> ISODate {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        let s = String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
        return ISODate(s) ?? initialDay
    }
}
