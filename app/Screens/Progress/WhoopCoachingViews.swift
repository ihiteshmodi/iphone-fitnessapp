import FitnessCore
import SwiftUI

/// 4-Mode WHOOP Coaching Ring Hub on ProgressTabView + CTL/ATL TrendChart + Layer 1 Principles & Limiter drill-down.
struct WhoopCoachingSection: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager
    @State private var snapshot: WhoopDashboardSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snap = snapshot {
                HStack {
                    SectionLabel("WHOOP Coaching · 4-Mode Block")
                    Spacer()
                    NavigationLink {
                        WhoopPrinciplesAndLimiterView()
                    } label: {
                        Text("Principles ›")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.green)
                    }
                    .accessibilityIdentifier("progress-open-principles")
                }

                modeBar(active: snap.coaching.evaluation.activeMode)
                heroModeCard(snap)
                twinCoachingRings(snap)

                if snap.coaching.ctlSeries.count >= 2 {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("CTL (fitness) vs ATL (fatigue) load trend")
                        let pts: [ChartPoint] = snap.coaching.ctlSeries.flatMap { p in
                            [
                                ChartPoint(label: p.label, value: p.ctl, series: "CTL"),
                                ChartPoint(label: p.label, value: p.atl, series: "ATL"),
                            ]
                        }
                        TrendChart(
                            points: pts,
                            height: 128,
                            seriesColors: ["CTL": Theme.green, "ATL": Theme.greenSoft]
                        )
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
    }

    private func modeBar(active: WhoopCoachingMode) -> some View {
        let items: [(String, WhoopCoachingMode)] = [
            ("Health", .generalHealth),
            ("VO2 Max", .maximizingVo2Max),
            ("Max HRV", .maximizingHrv),
            ("Reduce RHR", .reducingRhr),
        ]
        return HStack(spacing: 2) {
            ForEach(items, id: \.1.rawValue) { label, mode in
                let isSelected = (active == mode)
                Button(label) {
                    if var def = try? services.appDefaults.load() {
                        def.whoopCoachingMode = mode
                        try? services.appDefaults.save(def)
                        reload()
                        session.didChange()
                    }
                }
                .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                .foregroundColor(isSelected ? Theme.onGreen : Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(isSelected ? Theme.green : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .buttonStyle(.plain)
                .accessibilityIdentifier("coaching-mode-\(mode.rawValue)")
            }
        }
        .padding(3)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func heroModeCard(_ snap: WhoopDashboardSnapshot) -> some View {
        let ev = snap.coaching.evaluation
        let spec = modePresentation(ev: ev, steps: snap.steps)

        return HStack(spacing: 14) {
            RingView(
                progress: spec.progress,
                size: 84,
                lineWidth: 8,
                label: spec.ringLabel,
                subLabel: spec.ringSub,
                color: spec.color
            )
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(spec.kicker)
                Text(spec.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                Text(spec.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 14)
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

    private func modePresentation(ev: WhoopCoachingEvaluation, steps: Int) -> ModeSpec {
        switch ev.activeMode {
        case .generalHealth:
            return ModeSpec(
                progress: ev.zone2WeeklyMinimumMet ? 1.0 : 0.65,
                ringLabel: "80/20",
                ringSub: "split",
                color: Theme.green,
                kicker: "General Health · \(ev.zone2FloorBpm)–\(ev.zone2CeilingBpm) bpm",
                title: ev.zone2WeeklyMinimumMet ? "150m+ Zone 2 floor met ✓" : "Build to 150m/wk Zone 2",
                subtitle: "\(ev.grayZoneSessionCount) gray-zone drifts · Target bedtime \(ev.targetBedtimeHm)"
            )
        case .maximizingVo2Max:
            let s = ev.intensitySplitTarget
            return ModeSpec(
                progress: ev.vo2WeeklyHighIntensityMet ? 1.0 : 0.6,
                ringLabel: "50m",
                ringSub: ">85%",
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

/// Layer 1 Non-Graded Execution Guardrails + VO2 Max 1-Mile / 10K Limiter Calibration screen.
struct WhoopPrinciplesAndLimiterView: View {
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @State private var maxHr: Int = 190
    @State private var limiter: Vo2LimiterMode = .aerobicPower

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("VO2 Max 1-Mile Max HR & 10K Limiter")
                    HStack {
                        Text("1-Mile Time Trial Peak HR").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                        Spacer()
                        HStack(spacing: 10) {
                            Button("−") { updateMaxHr(max(140, maxHr - 1)) }.foregroundColor(Theme.green)
                            Text("\(maxHr) bpm").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                            Button("+") { updateMaxHr(min(225, maxHr + 1)) }.foregroundColor(Theme.green)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 10))
                    }

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
        .navigationTitle("Principles & Limiter")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let snap = try? services.appDefaults.load() {
                maxHr = snap.oneMileTrialMaxHr ?? 190
                limiter = snap.vo2LimiterMode
            }
        }
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
