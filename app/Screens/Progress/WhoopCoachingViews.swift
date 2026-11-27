import FitnessCore
import SwiftUI

/// 4-Mode WHOOP Coaching Ring Hub on ProgressTabView + CTL/ATL TrendChart + Layer 1 Principles & Limiter drill-down.
struct WhoopCoachingSection: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager
    @State private var snapshot: WhoopDashboardSnapshot?
    @State private var previewMode: WhoopCoachingMode?
    @State private var blockDaysElapsed: Int = 0
    @State private var showSeasonalPrompt = false

    private func displayedEvaluation(_ snap: WhoopDashboardSnapshot) -> WhoopCoachingEvaluation {
        let target = previewMode ?? snap.coaching.evaluation.activeMode
        return snap.coaching.evaluationsByMode[target] ?? snap.coaching.evaluation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snap = snapshot {
                let activeMode = snap.coaching.evaluation.activeMode
                let shownMode = previewMode ?? activeMode
                let shownEval = displayedEvaluation(snap)

                HStack {
                    SectionLabel("WHOOP Coaching · 4-Mode Block")
                    Spacer()
                    Button("90d Check") { showSeasonalPrompt.toggle() }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Theme.muted)
                        .accessibilityIdentifier("coaching-seasonal-check-button")
                    NavigationLink {
                        WhoopPrinciplesAndLimiterView()
                    } label: {
                        Text("Principles & Max HR ›")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.green)
                    }
                    .accessibilityIdentifier("progress-open-principles")
                }

                if blockDaysElapsed >= 90 || showSeasonalPrompt {
                    seasonalReviewBanner(activeMode)
                }

                modeBar(active: activeMode, viewing: shownMode)
                heroModeCard(snap, activeMode: activeMode, eval: shownEval)
                twinCoachingRings(snap)
                modeRulesChecklistCard(snap, activeMode: activeMode, eval: shownEval)

                if snap.coaching.ctlSeries.count >= 2 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            SectionLabel("CTL (42d fitness) vs ATL (7d fatigue) load")
                            Spacer()
                            Text("Drag to scrub")
                                .font(.system(size: 10.5))
                                .foregroundColor(Theme.muted)
                        }
                        let pts: [ChartPoint] = snap.coaching.ctlSeries.flatMap { p in
                            [
                                ChartPoint(label: p.label, value: p.ctl, series: "CTL"),
                                ChartPoint(label: p.label, value: p.atl, series: "ATL"),
                            ]
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            TrendChart(
                                points: pts,
                                height: 128,
                                seriesColors: ["CTL": Theme.green, "ATL": Theme.greenSoft]
                            )
                            let firstLbl = snap.coaching.ctlSeries.first?.label ?? ""
                            let lastLbl = snap.coaching.ctlSeries.last?.label ?? ""
                            Text("Live from WHOOP daily Strain (\(snap.coaching.ctlSeries.count)d: \(firstLbl) → \(lastLbl)) · TSB = CTL − ATL")
                                .font(.system(size: 10.5))
                                .foregroundColor(Theme.muted)
                                .accessibilityIdentifier("coaching-ctl-provenance-label")
                        }
                        .card(padding: 12)
                    }
                }
            }
        }
        .task(id: "\(session.revision)-\(whoop.substrateSummary?.oneHzCount ?? 0)") {
            reload()
        }
    }

    private func reload() {
        let today = services.clock.today()
        snapshot = try? WhoopDashboardPresenter.build(whoopDb: whoop.db, fitnessDb: services.db, on: today)
        if let def = try? services.appDefaults.load(),
           let actStr = def.coachingModeActivatedOn,
           let actIso = ISODate(actStr) {
            blockDaysElapsed = max(0, today.days(since: actIso))
        } else {
            blockDaysElapsed = 0
        }
    }

    private func activateMode(_ mode: WhoopCoachingMode) {
        if var def = try? services.appDefaults.load() {
            def.whoopCoachingMode = mode
            def.coachingModeActivatedOn = services.clock.today().string
            try? services.appDefaults.save(def)
            previewMode = nil
            reload()
            session.didChange()
        }
    }

    private func seasonalReviewBanner(_ mode: WhoopCoachingMode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("90-Day Seasonal Focus Review")
                Spacer()
                Pill(text: "Day \(max(90, blockDaysElapsed))", tone: .gold)
            }
            Text("You have completed a seasonal training block on \(mode.title). Keep this focus for another 90 days or preview and activate another mode below.")
                .font(.system(size: 12)).foregroundColor(Theme.muted)
            HStack {
                Button("Keep Focus for Next 90d") {
                    if var def = try? services.appDefaults.load() {
                        def.coachingModeActivatedOn = services.clock.today().string
                        try? services.appDefaults.save(def)
                        showSeasonalPrompt = false
                        reload()
                    }
                }
                .buttonStyle(CompactButtonStyle())
                Button("Dismiss") { showSeasonalPrompt = false }
                    .buttonStyle(CompactButtonStyle(ghost: true))
            }
        }
        .card(padding: 12, highlighted: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coaching-seasonal-review-banner")
    }

    private func modeRulesChecklistCard(_ snap: WhoopDashboardSnapshot, activeMode: WhoopCoachingMode, eval ev: WhoopCoachingEvaluation) -> some View {
        let isPreview = (ev.activeMode != activeMode)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(isPreview ? "Previewing \(ev.activeMode.title) Rules" : "Active Mode Rules & Guardrails")
                Spacer()
                Pill(text: isPreview ? "Preview" : "Active ✓", tone: isPreview ? .amber : .green)
            }
            switch ev.activeMode {
            case .generalHealth:
                ruleLine("Zone 2 (\(ev.zone2FloorBpm)–\(ev.zone2CeilingBpm) bpm)", value: "\(snap.coaching.weeklyZone2Minutes)/150m (\(snap.coaching.weeklyZoneWindowLabel))", ok: ev.zone2WeeklyMinimumMet)
                ruleLine("Gray-zone drift (>\(ev.zone2CeilingBpm) bpm)", value: "\(ev.grayZoneSessionCount) session(s)", ok: ev.grayZoneSessionCount == 0)
                ruleLine("Split & +5% weekly cap", value: "80/20 · \(ev.weeklyProgressionExceeded ? ">+5% warn" : "≤+5% ✓")", ok: !ev.weeklyProgressionExceeded)
                ruleLine("Order & 1:2 load spacing", value: ev.sameDayInterferenceWarning ? "<3h gap warn" : "Lift 1st / ≥3–6h gap · 1:2 ✓", ok: !ev.sameDayInterferenceWarning && !ev.spacingViolation)
                ruleLine("Red Recovery Override", value: ev.keepNormalStrainOverride ? "1 Red + sleep/meal → Normal targets" : (ev.deloadTriggered ? "3+ Red / 4–6wk → Deload" : "Standby (<3 Red)"), ok: !ev.deloadTriggered)
            case .maximizingVo2Max:
                let sp = ev.intensitySplitTarget
                ruleLine(">85% HRmax (3×/wk)", value: "\(snap.coaching.weeklyZone4And5Minutes)/50m (\(snap.coaching.weeklyZoneWindowLabel))", ok: ev.vo2WeeklyHighIntensityMet)
                ruleLine("Aerobic ceiling", value: ev.weeklyCardioCeilingExceeded ? ">7.0 h/wk exceeded" : "≤7.0 h/wk respected ✓", ok: !ev.weeklyCardioCeilingExceeded)
                ruleLine("10K (<180−age) limiter split", value: "\(sp.easyPct)% Z2 / \(sp.moderateOrAnaerobicPct)% Threshold / \(sp.hardOrSprintPct)% VO2", ok: true)
            case .maximizingHrv:
                ruleLine("Weekly 1.5–3h Z3–5 long run", value: "1.5×→2×→3× ramp (gray-zone exempt)", ok: true)
                ruleLine("4-day HRV rebound stage", value: ev.reboundStage.rawValue.replacingOccurrences(of: "_", with: " "), ok: ev.reboundStage != .day2TooEasyFlatStress)
                ruleLine("Plasma volume guard", value: ev.plasmaVolumeDropWarning ? ">2 rest days — add flush" : "≤2 cardio-rest days ✓", ok: !ev.plasmaVolumeDropWarning)
            case .reducingRhr:
                let stepMin = ev.stepAdjustedEasyCardioMin ?? 25
                ruleLine("Step-scaled 110–130 bpm", value: "\(snap.steps) steps → \(stepMin)m\(ev.secondaryEasyDayBonusMin > 0 ? " (+\(ev.secondaryEasyDayBonusMin)m 2nd day)" : "")", ok: true)
                ruleLine("Caffeine ≤100mg before 12:00", value: ev.strictCaffeineViolation ? "Late/excess flagged" : "Compliant ✓", ok: !ev.strictCaffeineViolation)
                ruleLine("3-Week Microcycle", value: String(format: "%.2f× volume (Wk3 = 0.5× deload)", ev.microcycleVolumeMultiplier), ok: true)
            }

            ForEach(ev.coachingNotes, id: \.self) { note in
                Text("• \(note)")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.amber)
                    .padding(.top, 2)
            }
        }
        .card(padding: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coaching-rules-checklist-card")
    }

    private func ruleLine(_ label: String, value: String, ok: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.muted)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ok ? Theme.green : Theme.amber)
                .multilineTextAlignment(.trailing)
        }
    }

    private func modeBar(active: WhoopCoachingMode, viewing: WhoopCoachingMode) -> some View {
        let items: [(String, WhoopCoachingMode)] = [
            ("Health", .generalHealth),
            ("VO2 Max", .maximizingVo2Max),
            ("Max HRV", .maximizingHrv),
            ("Reduce RHR", .reducingRhr),
        ]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                ForEach(items, id: \.1.rawValue) { label, mode in
                    let isViewing = (viewing == mode)
                    let isActive = (active == mode)
                    let displayLabel = isActive ? "\(label) ✓" : label
                    Button(displayLabel) {
                        previewMode = (mode == active) ? nil : mode
                    }
                    .font(.system(size: 11.5, weight: isViewing ? .bold : .semibold))
                    .foregroundColor(isViewing ? Theme.onGreen : (isActive ? Theme.green : Theme.muted))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(isViewing ? Theme.green : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(isActive && !isViewing ? Theme.green.opacity(0.6) : Color.clear, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coaching-mode-\(mode.rawValue)")
                }
            }
            .padding(3)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Tap any mode above to preview its live rules · Active focus has ✓")
                .font(.system(size: 10.5))
                .foregroundColor(Theme.muted)
        }
    }

    private func heroModeCard(_ snap: WhoopDashboardSnapshot, activeMode: WhoopCoachingMode, eval ev: WhoopCoachingEvaluation) -> some View {
        let spec = modePresentation(ev: ev, steps: snap.steps, z2Min: snap.coaching.weeklyZone2Minutes, z45Min: snap.coaching.weeklyZone4And5Minutes)
        let isPreview = (ev.activeMode != activeMode)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                RingView(
                    progress: spec.progress,
                    size: 84,
                    lineWidth: 8,
                    label: spec.ringLabel,
                    subLabel: spec.ringSub,
                    color: spec.color
                )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Pill(
                            text: isPreview ? "PREVIEWING" : "ACTIVE FOCUS ✓",
                            tone: isPreview ? .amber : .green
                        )
                        if isPreview {
                            Text("Active: \(activeMode.title)")
                                .font(.system(size: 10.5))
                                .foregroundColor(Theme.muted)
                        }
                    }
                    SectionLabel(spec.kicker)
                    Text(spec.title)
                        .font(.system(size: 16.5, weight: .bold))
                        .foregroundColor(Theme.text)
                        .lineLimit(2)
                    Text(spec.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if isPreview {
                HStack(spacing: 8) {
                    Button("Set \(ev.activeMode.title) as Active Focus") {
                        activateMode(ev.activeMode)
                    }
                    .buttonStyle(CompactButtonStyle())
                    .accessibilityIdentifier("coaching-activate-previewed-mode")

                    Button("Back to Active") {
                        previewMode = nil
                    }
                    .buttonStyle(CompactButtonStyle(ghost: true))
                    .accessibilityIdentifier("coaching-cancel-preview-button")
                }
            }
        }
        .card(padding: 14, highlighted: isPreview)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coaching-hero-card")
    }

    private func twinCoachingRings(_ snap: WhoopDashboardSnapshot) -> some View {
        let liftHrs = snap.coaching.weeklyLiftingHours
        let liftFrac = min(1.0, max(0.05, liftHrs / 3.0))
        let tsb = snap.coaching.ctlAtlTsb?.tsb ?? 0.0
        let ctl = snap.coaching.ctlAtlTsb?.ctl ?? 0.0
        let atl = snap.coaching.ctlAtlTsb?.atl ?? 0.0

        return HStack(spacing: 10) {
            HStack(spacing: 10) {
                RingView(progress: liftFrac, size: 46, lineWidth: 5, label: "\(Format.number(liftHrs, maxDecimals: 1))h", color: liftHrs >= 3.0 ? Theme.green : Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lifting Goal").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                    Text("\(Format.number(liftHrs, maxDecimals: 1)) → 3.0 h/wk").font(.system(size: 11)).foregroundColor(Theme.muted)
                    Text(liftHrs >= 3.0 ? "Benchmark met" : "Build toward 3h")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(liftHrs >= 3.0 ? Theme.green : Theme.amber)
                }
                Spacer(minLength: 0)
            }
            .card(padding: 11)

            HStack(spacing: 10) {
                RingView(progress: 0.75, size: 46, lineWidth: 5, label: String(format: "%+.0f", tsb), color: tsb >= -10 ? Theme.greenSoft : Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Load (TSB)").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                    Text("CTL \(Int(ctl.rounded())) · ATL \(Int(atl.rounded()))").font(.system(size: 11)).foregroundColor(Theme.muted)
                    Text(snap.coaching.evaluation.spacingViolation ? "Back-to-back hard" : "1:2 spacing ✓")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(snap.coaching.evaluation.spacingViolation ? Theme.amber : Theme.green)
                }
                Spacer(minLength: 0)
            }
            .card(padding: 11)
        }
    }

    private struct ModeSpec {
        let progress: Double
        let ringLabel: String
        let ringSub: String
        let color: Color
        let kicker: String
        let title: String
        let subtitle: String
    }

    private func modePresentation(ev: WhoopCoachingEvaluation, steps: Int, z2Min: Int, z45Min: Int) -> ModeSpec {
        switch ev.activeMode {
        case .generalHealth:
            return ModeSpec(
                progress: min(1.0, max(0.08, Double(z2Min) / 150.0)),
                ringLabel: "\(z2Min)m",
                ringSub: "/150m Z2",
                color: Theme.green,
                kicker: "General Health · \(ev.zone2FloorBpm)–\(ev.zone2CeilingBpm) bpm",
                title: ev.zone2WeeklyMinimumMet ? "150m+ Zone 2 floor met ✓" : "Build to 150m/wk Zone 2",
                subtitle: "\(ev.grayZoneSessionCount) gray-zone drifts · Target bedtime \(ev.targetBedtimeHm)"
            )
        case .maximizingVo2Max:
            let s = ev.intensitySplitTarget
            return ModeSpec(
                progress: min(1.0, max(0.08, Double(z45Min) / 50.0)),
                ringLabel: "\(z45Min)m",
                ringSub: "/50m Z4–5",
                color: Theme.gold,
                kicker: "Maximizing VO2 Max · \(s.easyPct)/\(s.moderateOrAnaerobicPct)/\(s.hardOrSprintPct)",
                title: ev.vo2WeeklyHighIntensityMet ? "50m/wk >85% HRmax met ✓" : "Aim: 50m/wk >85% HRmax",
                subtitle: ev.weeklyCardioCeilingExceeded ? "Above 7h/wk aerobic cap — protect lean mass" : "7.0 h/wk aerobic ceiling respected ✓"
            )
        case .maximizingHrv:
            return ModeSpec(
                progress: 0.75,
                ringLabel: "Z3–5",
                ringSub: "exempt",
                color: Theme.greenSoft,
                kicker: "Maximizing HRV · Gray-Zone Exempt",
                title: "Weekly 1.5–3h Long Run Mode",
                subtitle: ev.plasmaVolumeDropWarning ? ">2 cardio-rest days — add light flush" : "4-day post-endurance HRV rebound tracker active"
            )
        case .reducingRhr:
            let easyMin = ev.stepAdjustedEasyCardioMin ?? 25
            return ModeSpec(
                progress: min(1.0, max(0.15, Double(40 - easyMin + 10) / 50.0)),
                ringLabel: "\(easyMin)m",
                ringSub: "today",
                color: Theme.green,
                kicker: "Reducing RHR · \(String(format: "%.2fx", ev.microcycleVolumeMultiplier)) microcycle",
                title: "\(steps) steps → \(easyMin)m @ 110–130 bpm",
                subtitle: ev.strictCaffeineViolation ? "Caffeine >100mg or past 12:00 flagged" : "Strict 110–130 bpm Zone 2 & noon caffeine ✓"
            )
        }
    }
}

/// Layer 1 Non-Graded Execution Guardrails + Live WHOOP Peak-HR Calibration Test & 10K Limiter screen.
struct WhoopPrinciplesAndLimiterView: View {
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var whoop: WhoopBLEManager
    @State private var maxHr: Int = 190
    @State private var limiter: Vo2LimiterMode = .aerobicPower
    @State private var testStartSec: Int64?
    @State private var testElapsedSec: Int = 0
    @State private var observedPeakBpm: Int = 0
    @State private var recent30dPeakBpm: Int?
    @State private var calibrationBanner: String?

    private let drillTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var previewZones: WhoopTrainingZones {
        WhoopReadinessAndStrainEngine.trainingZones(ageYears: 30.0, manualBounds: nil, oneMileMaxHr: maxHr)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("VO2 Max 1-Mile Max HR & 10K Limiter")
                    HStack {
                        Text("Calibrated Max HR").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                        Spacer()
                        HStack(spacing: 10) {
                            Button("−") { updateMaxHr(max(140, maxHr - 1)) }.foregroundColor(Theme.green)
                            Text("\(maxHr) bpm").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                            Button("+") { updateMaxHr(min(225, maxHr + 1)) }.foregroundColor(Theme.green)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    let z = previewZones
                    Text("Resulting Zones: Z1 ≥\(z.boundsBpm[0]) · Z2 ≥\(z.boundsBpm[1]) · Z3 ≥\(z.boundsBpm[2]) · Z4 ≥\(z.boundsBpm[3]) · Z5 ≥\(z.boundsBpm[4]) bpm")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Theme.green)

                    Picker("10K Limiter", selection: $limiter) {
                        ForEach(Vo2LimiterMode.allCases, id: \.rawValue) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .onChange(of: limiter) { newVal in
                        if var snap = try? services.appDefaults.load() {
                            snap.vo2LimiterMode = newVal
                            try? services.appDefaults.save(snap)
                            session.didChange()
                        }
                    }
                }
                .card()

                livePeakHrCalibrationCard

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Layer 1 · Static daily execution principles")
                    ForEach(WhoopCoachingEngine.layer1Principles) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                            Text(item.detail).font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .card()
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Principles & Max HR")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadInitial)
        .onReceive(drillTicker) { now in
            guard let start = testStartSec else { return }
            testElapsedSec = max(1, Int(Int64(now.timeIntervalSince1970) - start))
            if let bpm = whoop.liveHrBpm, bpm >= 60, bpm <= 225 {
                if bpm > observedPeakBpm {
                    observedPeakBpm = bpm
                }
            }
        }
    }

    private var livePeakHrCalibrationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Live WHOOP Peak-HR Calibration Test (0x03)")
                Spacer()
                if testStartSec != nil {
                    Pill(text: String(format: "%02d:%02d", testElapsedSec / 60, testElapsedSec % 60), tone: .green)
                } else {
                    Pill(text: "1-Mile / Hill Sprint", tone: .gold)
                }
            }

            Text("Warm up 10 min, then run an all-out 1-mile time trial or final 60s hill sprint while streaming WHOOP 0x03 HR to capture your true physiological Max HR.")
                .font(.system(size: 11.5))
                .foregroundColor(Theme.muted)

            if testStartSec != nil {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(whoop.liveHrBpm.map { "\($0) bpm" } ?? "Waiting for strap…")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundColor(Theme.text)
                        Text("Live 0x03 HR")
                            .font(.system(size: 11)).foregroundColor(Theme.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(observedPeakBpm > 0 ? "\(observedPeakBpm) bpm" : "—")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundColor(Theme.green)
                        Text("Observed Peak HR")
                            .font(.system(size: 11)).foregroundColor(Theme.muted)
                    }
                }
                .padding(10)
                .background(Theme.card2)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 8) {
                    if observedPeakBpm >= 140 {
                        Button("Apply \(observedPeakBpm) bpm as Max HR") {
                            updateMaxHr(observedPeakBpm)
                            stopDrill()
                            calibrationBanner = "Saved \(observedPeakBpm) bpm as your calibrated Max HR ✓"
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("principles-apply-peak-hr")
                    }
                    Button("Stop Test") {
                        stopDrill()
                    }
                    .buttonStyle(PrimaryButtonStyle(ghost: true))
                    .accessibilityIdentifier("principles-stop-maxhr-test")
                }
            } else {
                Button("▶ Start Live WHOOP Peak-HR Test") {
                    observedPeakBpm = whoop.liveHrBpm ?? 0
                    testElapsedSec = 0
                    testStartSec = Int64(Date().timeIntervalSince1970)
                    whoop.toggleLiveHeartRate(true)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("principles-start-maxhr-test")
            }

            if let p30 = recent30dPeakBpm, p30 >= 145 {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("30-Day WHOOP 1 Hz Peak Observed: \(p30) bpm")
                            .font(.system(size: 12.5, weight: .semibold)).foregroundColor(Theme.text)
                        Text("Highest plausible 1 Hz BPM recorded in your strap history")
                            .font(.system(size: 10.5)).foregroundColor(Theme.muted)
                    }
                    Spacer()
                    Button("Use \(p30) bpm") {
                        updateMaxHr(p30)
                        calibrationBanner = "Applied 30-day observed peak (\(p30) bpm) ✓"
                    }
                    .buttonStyle(CompactButtonStyle(ghost: true))
                    .accessibilityIdentifier("principles-use-30d-peak-button")
                }
                .padding(.top, 4)
            }

            if let calibrationBanner {
                Text(calibrationBanner)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.green)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("principles-maxhr-calibration-card")
    }

    private func loadInitial() {
        if let snap = try? services.appDefaults.load() {
            maxHr = snap.oneMileTrialMaxHr ?? 190
            limiter = snap.vo2LimiterMode
        }
        if let db = whoop.db,
           let maxTs = try? db.query("SELECT MAX(rec_ts) AS mt FROM decoded_onehz").first?.optionalInt64("mt"),
           maxTs > 0 {
            let floorTs = maxTs - 30 * 86_400
            if let peak = try? db.query(
                "SELECT MAX(hr) AS mh FROM decoded_onehz WHERE rec_ts >= ? AND hr BETWEEN 140 AND 220",
                [.int(floorTs)]
            ).first?.optionalInt("mh") {
                recent30dPeakBpm = peak
            }
        }
    }

    private func stopDrill() {
        testStartSec = nil
        whoop.toggleLiveHeartRate(false)
    }

    private func updateMaxHr(_ newHr: Int) {
        maxHr = newHr
        if var snap = try? services.appDefaults.load() {
            snap.oneMileTrialMaxHr = newHr
            try? services.appDefaults.save(snap)
            session.didChange()
        }
    }
}
