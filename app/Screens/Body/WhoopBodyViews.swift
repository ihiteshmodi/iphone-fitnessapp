import CoreLocation
import FitnessCore
import SwiftUI

extension WhoopHoopTone {
    var color: Color {
        switch self {
        case .green: return Theme.green
        case .greenSoft: return Theme.greenSoft
        case .gold: return Theme.gold
        case .amber: return Theme.amber
        case .red: return Theme.red
        case .muted: return Theme.muted
        }
    }

    var pillTone: Pill.Tone {
        switch self {
        case .green, .greenSoft: return .green
        case .gold: return .gold
        case .amber: return .amber
        case .red: return .red
        case .muted: return .grey
        }
    }
}

/// Top of Body tab: WHOOP 3-Hoop Triad (Recovery · Strain · Sleep) + Twin Weekly Longevity Rings (Fitness Age · Vitality),
/// sitting directly above Maintenance Calories and Bloodwork.
struct WhoopBodyEntrySection: View {
    let shownDay: ISODate
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager
    @State private var snapshot: WhoopDashboardSnapshot?

    var body: some View {
        VStack(spacing: 12) {
            if let snap = snapshot {
                NavigationLink {
                    WhoopRecoverySleepView(initialDay: shownDay)
                } label: {
                    triadCard(snap)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("whoop-body-triad-card")

                longevityGrid(snap)
            }
        }
        .task(id: "\(shownDay.string)-\(session.revision)-\(whoop.substrateSummary?.oneHzCount ?? 0)") {
            reload()
        }
    }

    private func reload() {
        snapshot = try? WhoopDashboardPresenter.build(whoopDb: whoop.db, fitnessDb: services.db, on: shownDay)
    }

    private func triadCard(_ snap: WhoopDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("WHOOP 5.0 · \(snap.scoredRecoveryDayId)")
                Spacer()
                Text("Recovery & sleep ›")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.green)
            }

            HStack(spacing: 8) {
                ForEach(snap.triad) { hoop in
                    VStack(spacing: 6) {
                        RingView(
                            progress: hoop.progress,
                            size: 76,
                            lineWidth: 7,
                            label: hoop.ringLabel,
                            subLabel: hoop.ringSubLabel,
                            color: hoop.tone.color
                        )
                        Text(hoop.title.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.5)
                            .foregroundColor(Theme.muted)
                        Text(hoop.footerText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                    .background(Theme.card2)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("whoop-triad-\(hoop.title.lowercased())")
                }
            }
        }
        .card()
    }

    private func longevityGrid(_ snap: WhoopDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                let rhrLabel = snap.longevity.fitnessAge.map { "\($0.readiness == .ready ? "Ready" : "Estimate")" } ?? "Weekly longevity"
                SectionLabel("Weekly longevity · \(rhrLabel)")
                Spacer()
                NavigationLink {
                    WhoopLongevityView(initialDay: shownDay)
                } label: {
                    Text("VO2 & treadmill ›")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.green)
                }
                .accessibilityIdentifier("whoop-open-longevity")
            }

            HStack(spacing: 10) {
                NavigationLink {
                    WhoopLongevityView(initialDay: shownDay)
                } label: {
                    HStack(spacing: 10) {
                        let fa = snap.longevity.fitnessAge
                        let faProgress = fa.map { min(1.0, max(0.15, (80.0 - $0.fitnessAge) / 60.0)) } ?? 0.05
                        let faLabel = fa.map { "\(Int($0.fitnessAge.rounded()))" } ?? "—"
                        RingView(progress: faProgress, size: 46, lineWidth: 5, label: faLabel, color: Theme.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fitness Age").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                            if let fa {
                                Text("VO2 \(Format.number(fa.vo2MaxMlKgMin, maxDecimals: 1)) · PAI \(Format.number(fa.pai, maxDecimals: 1))")
                                    .font(.system(size: 11)).foregroundColor(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
                                let diff = fa.deltaYearsYounger
                                Text(diff >= 0 ? "\(Format.number(diff, maxDecimals: 1)) yr younger" : "\(Format.number(abs(diff), maxDecimals: 1)) yr older")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(diff >= 0 ? Theme.green : Theme.amber)
                            } else {
                                Text("Needs 4+ RHR nights").font(.system(size: 11)).foregroundColor(Theme.muted)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .card(padding: 11)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("whoop-fitness-age-tile")

                NavigationLink {
                    WhoopLongevityView(initialDay: shownDay)
                } label: {
                    HStack(spacing: 10) {
                        let vit = snap.longevity.vitality
                        let vitProgress = vit.map { min(1.0, max(0.05, $0.vitalityScore / 100.0)) } ?? 0.05
                        let vitLabel = vit.map { "\(Int($0.vitalityScore.rounded()))" } ?? "—"
                        RingView(progress: vitProgress, size: 46, lineWidth: 5, label: vitLabel, color: Theme.greenSoft)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Vitality").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                            if let vit {
                                Text("Body Age \(Format.number(vit.bodyAge, maxDecimals: 1))")
                                    .font(.system(size: 11)).foregroundColor(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
                                let diff = vit.deltaYearsYounger
                                Text(diff >= 0 ? "\(Format.number(diff, maxDecimals: 1)) yr younger" : "\(Format.number(abs(diff), maxDecimals: 1)) yr older")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(diff >= 0 ? Theme.green : Theme.amber)
                            } else {
                                Text("Needs 3+ factors").font(.system(size: 11)).foregroundColor(Theme.muted)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .card(padding: 11)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("whoop-vitality-tile")
            }

            HStack(spacing: 10) {
                NavigationLink {
                    WhoopBreatheAndStressView(initialDay: shownDay)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wind.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Stress & Breathe")
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                            Text("24h Stress · Alertness · 23 Pacers")
                                .font(.system(size: 10.5)).foregroundColor(Theme.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .card(padding: 10)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("whoop-open-breathe-stress")

                NavigationLink {
                    WhoopMetricsExplorerView(initialDay: shownDay)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.gold)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("24-Metric Trends")
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                            Text("7d / 30d / Custom + Normal Bands")
                                .font(.system(size: 10.5)).foregroundColor(Theme.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .card(padding: 10)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("whoop-open-metrics-explorer")
            }
        }
    }
}

// MARK: - Recovery & 4-Stage Sleep Drill-Down Screen

struct WhoopRecoverySleepView: View {
    let initialDay: ISODate
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager
    @State private var snapshot: WhoopDashboardSnapshot?
    @State private var editingSleep = false
    @State private var addingNap = false
    @State private var editingNap: WhoopNapRecord?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let snap = snapshot {
                    heroCard(snap)
                    if !snap.contributors.isEmpty {
                        contributorsCard(snap)
                    }
                    skinTempAndIllnessCard(snap)
                    sleepCard(snap)
                    napsCard(snap)
                    energyAndStrainCard(snap)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Recovery & Sleep")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear(perform: reload)
        .sheet(isPresented: $editingSleep, onDismiss: reload) {
            if let snap = snapshot {
                WhoopSleepOverrideSheet(dayId: snap.sleep.scoredDayId, current: snap.sleep, whoopDb: whoop.db)
            }
        }
        .sheet(isPresented: $addingNap, onDismiss: reload) {
            WhoopNapEditorSheet(dayId: initialDay.string, existing: nil, whoopDb: whoop.db)
        }
        .sheet(isPresented: Binding(get: { editingNap != nil }, set: { if !$0 { editingNap = nil } }), onDismiss: reload) {
            if let nap = editingNap {
                WhoopNapEditorSheet(dayId: nap.dayId, existing: nap, whoopDb: whoop.db)
            }
        }
        .errorAlert($errorMessage)
    }

    private func reload() {
        snapshot = try? WhoopDashboardPresenter.build(whoopDb: whoop.db, fitnessDb: services.db, on: initialDay)
    }

    private func heroCard(_ snap: WhoopDashboardSnapshot) -> some View {
        HStack(spacing: 16) {
            let p = snap.readinessScore.map { Double($0) / 100.0 } ?? 0.05
            let lbl = snap.readinessScore.map { "\($0)%" } ?? "—"
            RingView(progress: p, size: 108, lineWidth: 10, label: lbl, subLabel: "readiness", color: snap.readinessTone.color)

            VStack(alignment: .leading, spacing: 6) {
                Pill(text: snap.readinessPill, tone: snap.readinessTone.pillTone)
                Text(snap.readinessHeadline)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.text)
                Text(snap.readinessDetail)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 16)
        .accessibilityIdentifier("whoop-recovery-hero")
    }

    private func contributorsCard(_ snap: WhoopDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("How recovery is calculated · 28d baseline")
                Spacer()
                SectionLabel("7d trend")
            }
            Text("Autonomic HRV + RHR share 70% weight against your self-excluded 28-day median; respiration (20%) and skin temp (10%) complete the score.")
                .font(.system(size: 11.5))
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(snap.contributors) { item in
                HStack(spacing: 10) {
                    RingView(progress: item.ringProgress, size: 40, lineWidth: 4, label: item.ringLabel, color: item.tone.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                        Text(item.subtitle).font(.system(size: 11.5)).foregroundColor(Theme.muted)
                    }
                    Spacer(minLength: 4)
                    SparklineView(values: item.sparkline, width: 56, height: 18)
                    Pill(text: item.badgeText, tone: item.tone.pillTone)
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("whoop-contributor-\(item.id)")
            }
        }
        .card()
    }

    private func skinTempAndIllnessCard(_ snap: WhoopDashboardSnapshot) -> some View {
        let unit = snap.temperatureUnit
        let illness = snap.illnessDay
        let flag = illness?.flag ?? .normal
        let zVal = illness?.z ?? 0.0

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Nightly Skin Temp & 21d Illness Early Warning")
                Spacer()
                HStack(spacing: 4) {
                    ForEach(TemperatureUnitPreference.allCases, id: \.rawValue) { u in
                        Button(u.label) {
                            if var def = try? services.appDefaults.load() {
                                def.temperatureUnit = u
                                try? services.appDefaults.save(def)
                                reload()
                                session.didChange()
                            }
                        }
                        .font(.system(size: 11.5, weight: unit == u ? .bold : .semibold))
                        .foregroundColor(unit == u ? Theme.onGreen : Theme.muted)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(unit == u ? Theme.green : Theme.card2)
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("whoop-temp-unit-\(u.rawValue)")
                    }
                }
            }

            HStack(spacing: 12) {
                RingView(
                    progress: flag == .elevated ? 0.35 : 0.90,
                    size: 54,
                    lineWidth: 5,
                    label: String(format: "%+.1fσ", zVal),
                    subLabel: unit.label,
                    color: flag == .elevated ? Theme.red : Theme.green
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(snap.skinTempCelsius.map { unit.format(celsius: $0) } ?? "Calibrating skin temp")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                    Text(flag == .elevated
                         ? "Elevated z ≥ 2.0 across ≥ 2 consecutive nights vs 21-day baseline — prioritize recovery."
                         : "Within 21-day modified z-score baseline (alerts only when z ≥ 2.0 for ≥ 2 nights).")
                        .font(.system(size: 11.5)).foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-skin-temp-illness-card")
    }

    private func sleepCard(_ snap: WhoopDashboardSnapshot) -> some View {
        let s = snap.sleep
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("4-stage sleep · \(s.scoredDayId)\(s.hasManualOverride ? " · manual re-staged" : "")")
                Spacer()
                Button("Edit span") { editingSleep = true }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Theme.green)
                    .accessibilityIdentifier("whoop-edit-sleep-span")
            }

            HStack(spacing: 14) {
                RingView(
                    progress: min(1.0, max(0.05, Double(s.efficiencyPct) / 100.0)),
                    size: 74,
                    lineWidth: 7,
                    label: s.efficiencyPct > 0 ? "\(s.efficiencyPct)%" : "—",
                    subLabel: "eff",
                    color: Theme.green
                )
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(WhoopDashboardPresenter.formatHoursMinutes(s.totalSleepMinutes))
                            .font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
                        Text("asleep").font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                    Text("Tonight target bedtime: \(s.targetBedtimeHm) (\(Format.number(s.dynamicSleepNeedHours, maxDecimals: 1))h need)")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.green)
                    if let trimSec = s.bandOffsetTrimSec, trimSec > 0 {
                        Text("Gen5 lie-in wake trim applied: −\(trimSec / 60)m morning wake tail")
                            .font(.system(size: 11)).foregroundColor(Theme.muted)
                    }
                }
                Spacer(minLength: 0)
            }

            stageBar(title: "Deep (SWS)", minutes: s.deepMinutes, total: max(1, s.totalSleepMinutes), color: Theme.greenDeep)
            stageBar(title: "REM", minutes: s.remMinutes, total: max(1, s.totalSleepMinutes), color: Theme.greenSoft)
            stageBar(title: "Light", minutes: s.lightMinutes, total: max(1, s.totalSleepMinutes), color: Theme.green)
            stageBar(title: "WASO (\(s.awakenings) awakening\(s.awakenings == 1 ? "" : "s"))", minutes: s.wasoMinutes, total: max(60, s.totalSleepMinutes), color: Theme.amber)

            HStack {
                Pill(
                    text: s.wakeConsistency.weekendJetLagFlagged ? "Jet Lag ≥2h" : (s.wakeConsistency.withinThirtyMinTarget ? "Wake ≤30m ✓" : "Wake ±\(s.wakeConsistency.wakeStdDevMinutes)m"),
                    tone: s.wakeConsistency.weekendJetLagFlagged ? .red : (s.wakeConsistency.withinThirtyMinTarget ? .green : .amber)
                )
                Text(s.wakeConsistency.summaryText)
                    .font(.system(size: 11.5)).foregroundColor(Theme.muted)
            }
            .padding(.top, 2)
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-sleep-card")
    }

    private func stageBar(title: String, minutes: Int, total: Int, color: Color) -> some View {
        let frac = min(1.0, max(0.04, Double(minutes) / Double(max(1, total))))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.text)
                Spacer()
                Text("\(minutes)m").font(.system(size: 12.5)).foregroundColor(Theme.muted)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(color).frame(width: proxy.size.width * frac)
                }
            }
            .frame(height: 7)
        }
    }

    private func napsCard(_ snap: WhoopDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Daytime naps · review-gated")
                Spacer()
                Button("+ Add nap") { addingNap = true }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Theme.green)
                    .accessibilityIdentifier("whoop-add-nap")
            }

            if snap.pendingNapProposals.isEmpty && snap.effectiveNaps.isEmpty {
                Text("No unreviewed or logged naps today. Naps under 20m before 14:00 (or 30–90m before 13:00 after short sleep) credit tonight's sleep need.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
            }

            ForEach(snap.pendingNapProposals) { prop in
                let durMin = max(1, Int((prop.endTs - prop.startTs) / 60))
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Pill(text: "Detected", tone: .amber)
                            Text("\(prop.dayId) · \(durMin) min").font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.text)
                        }
                        Text("\(hmString(prop.startTs)) – \(hmString(prop.endTs))").font(.system(size: 11.5)).foregroundColor(Theme.muted)
                    }
                    Spacer()
                    Button("Accept") { acceptNap(prop) }
                        .buttonStyle(CompactButtonStyle())
                    Button("Dismiss") { dismissProposal(prop) }
                        .buttonStyle(CompactButtonStyle(ghost: true))
                }
                .padding(.vertical, 4)
            }

            ForEach(snap.effectiveNaps, id: \.startTs) { nap in
                let durMin = nap.durationSec / 60
                let startDt = Date(timeIntervalSince1970: TimeInterval(nap.startTs))
                let startMinOfDay = Calendar.current.component(.hour, from: startDt) * 60 + Calendar.current.component(.minute, from: startDt)
                let sleepDeprived = Double(snap.sleep.totalSleepMinutes) / 60.0 < (snap.sleep.dynamicSleepNeedHours - 0.75)
                let compliance = WhoopWakeAndNapComplianceEngine.evaluateNap(
                    durationMin: durMin, startMinuteOfDay: startMinOfDay, sleepDeprived: sleepDeprived
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("\(hmString(nap.startTs)) – \(hmString(nap.endTs)) · \(durMin) min")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                        Pill(text: compliance.badgeText, tone: compliance.compliant ? .green : .amber)
                        Spacer()
                        Button("Edit") { editingNap = nap }
                            .font(.system(size: 12.5, weight: .semibold)).foregroundColor(Theme.green)
                    }
                    Text(compliance.guidanceText)
                        .font(.system(size: 11)).foregroundColor(Theme.muted)
                }
                .padding(.vertical, 3)
            }
        }
        .card()
    }

    private func energyAndStrainCard(_ snap: WhoopDashboardSnapshot) -> some View {
        HStack(spacing: 14) {
            RingView(
                progress: min(1.0, max(0.03, snap.strain / 21.0)),
                size: 64,
                lineWidth: 6,
                label: String(format: "%.1f", snap.strain),
                subLabel: "of 21",
                color: Theme.gold
            )
            VStack(alignment: .leading, spacing: 3) {
                SectionLabel("Exercise-protected strain & daily energy")
                Text("\(snap.steps) filtered Gen5 steps")
                    .font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                if let tot = snap.totalKcal {
                    let act = snap.activeKcal ?? 0
                    Text("\(Format.grouped(Double(tot))) kcal total (\(Format.grouped(Double(max(0, tot - act)))) basal + \(Format.grouped(Double(act))) active)")
                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private func acceptNap(_ prop: WhoopActivityProposal) {
        guard let db = whoop.db else { return }
        do {
            let store = WhoopAnalyticsStore(db)
            try store.upsertNap(dayId: prop.dayId, startTs: prop.startTs, endTs: prop.endTs, source: "accepted", payloadJson: prop.detailsJson)
            try store.updateProposalStatus(id: prop.id, status: "accepted")
            reload()
            session.didChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dismissProposal(_ prop: WhoopActivityProposal) {
        guard let db = whoop.db else { return }
        try? WhoopAnalyticsStore(db).updateProposalStatus(id: prop.id, status: "discarded")
        reload()
    }

    private func hmString(_ epochSec: Int64) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(epochSec)))
    }
}

// MARK: - Weekly Longevity & ACSM Treadmill VO2 Max Screen

struct WhoopLongevityView: View {
    let initialDay: ISODate
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager
    @State private var snapshot: WhoopDashboardSnapshot?
    @State private var speedKmh: Double = 10.8
    @State private var gradePct: Double = 2.0
    @State private var durationMin: Double = 20.0
    @State private var steadyHrText = "158"
    @State private var editingLog: TreadmillVo2Log?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let snap = snapshot {
                    heroTwinHoops(snap.longevity)
                    if let vit = snap.longevity.vitality {
                        vitalityDriversGrid(vit)
                    }
                    acsmCalculatorCard(snap)
                    OutdoorGpsVo2Card(
                        loggedOn: initialDay,
                        rhrBpm: snap.longevity.fitnessAge.map { Int($0.medianRhr.rounded()) } ?? 52,
                        maxHrBpm: snap.zones.maxHrBpm,
                        onLogged: {
                            reload()
                            session.didChange()
                        }
                    )
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Longevity & VO2")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear(perform: reload)
        .sheet(item: $editingLog, onDismiss: reload) { log in
            TreadmillVo2EditSheet(log: log, service: services.treadmillVo2)
        }
        .errorAlert($errorMessage)
    }

    private func reload() {
        snapshot = try? WhoopDashboardPresenter.build(whoopDb: whoop.db, fitnessDb: services.db, on: initialDay)
    }

    private func heroTwinHoops(_ lon: WhoopLongevityViewModel) -> some View {
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                let vo2 = lon.fitnessAge?.vo2MaxMlKgMin
                RingView(
                    progress: vo2.map { min(1.0, max(0.15, $0 / 65.0)) } ?? 0.05,
                    size: 90,
                    lineWidth: 8,
                    label: vo2.map { Format.number($0, maxDecimals: 1) } ?? "—",
                    subLabel: "mL/kg/m",
                    color: Theme.green
                )
                SectionLabel(lon.fitnessAge?.estimator == .nes ? "Nes 2011 · Waist" : "Uth 2004 · HR Ratio")
                if let fa = lon.fitnessAge {
                    Text("Fitness Age \(Format.number(fa.fitnessAge, maxDecimals: 1))")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text)
                    Text("PAI \(Format.number(fa.pai, maxDecimals: 1)) / 15 · ±\(Format.number(fa.see, maxDecimals: 1))")
                        .font(.system(size: 11)).foregroundColor(Theme.muted)
                } else {
                    Text("Needs 4+ RHR days").font(.system(size: 12)).foregroundColor(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .card(padding: 14)

            VStack(spacing: 6) {
                let vit = lon.vitality
                RingView(
                    progress: vit.map { min(1.0, max(0.05, $0.vitalityScore / 100.0)) } ?? 0.05,
                    size: 90,
                    lineWidth: 8,
                    label: vit.map { "\(Int($0.vitalityScore.rounded()))" } ?? "—",
                    subLabel: "vitality",
                    color: Theme.greenSoft
                )
                SectionLabel("Gompertz Hazard")
                if let vit {
                    Text("Body Age \(Format.number(vit.bodyAge, maxDecimals: 1))")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text)
                    Text("\(vit.factorsUsed) factors · \(Format.number(vit.deltaYearsYounger, maxDecimals: 1)) yr")
                        .font(.system(size: 11)).foregroundColor(Theme.muted)
                } else {
                    Text("Needs 3+ factors").font(.system(size: 12)).foregroundColor(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .card(padding: 14)
        }
        .accessibilityIdentifier("whoop-longevity-hero")
    }

    private func vitalityDriversGrid(_ vit: WhoopVitalityResult) -> some View {
        let items: [(String, String, Double)] = [
            ("rhr", "Resting HR", vit.factorHazards["rhr"] ?? 0),
            ("hrv", "HRV vs Age", vit.factorHazards["hrv"] ?? 0),
            ("sleep", "Sleep Hours", vit.factorHazards["sleep"] ?? 0),
            ("steps", "Daily Steps", vit.factorHazards["steps"] ?? 0),
        ]
        return VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Vitality log-hazard drivers")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(items, id: \.0) { _, title, lnH in
                    let protective = lnH <= 0
                    let yrs = -lnH * 0.75 / (log(2.0) / 8.0)
                    HStack(spacing: 10) {
                        RingView(progress: protective ? 0.85 : 0.45, size: 42, lineWidth: 4, color: protective ? Theme.green : Theme.amber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                            Text(yrs >= 0 ? "+\(Format.number(yrs, maxDecimals: 1)) yr younger" : "\(Format.number(yrs, maxDecimals: 1)) yr")
                                .font(.system(size: 11))
                                .foregroundColor(protective ? Theme.green : Theme.amber)
                        }
                        Spacer(minLength: 0)
                    }
                    .card(padding: 11)
                }
            }
        }
    }

    private func acsmCalculatorCard(_ snap: WhoopDashboardSnapshot) -> some View {
        let rhrInt = snap.longevity.fitnessAge.map { Int($0.medianRhr.rounded()) } ?? 52
        let maxHrInt = snap.zones.maxHrBpm
        let steadyInt = Int(steadyHrText.trimmingCharacters(in: .whitespaces))
        let calc = AcsmTreadmillVo2Service.calculate(
            speedKmh: speedKmh, gradePct: gradePct, steadyHr: steadyInt, restingHr: rhrInt, maxHr: maxHrInt
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("ACSM treadmill VO2 max (%HRR scaled)")
                Spacer()
                Pill(text: "Est \(Format.number(calc.estimatedVo2Max, maxDecimals: 1))", tone: .gold)
            }

            HStack(spacing: 10) {
                stepperTile("Speed", value: "\(Format.number(speedKmh, maxDecimals: 1)) km/h",
                            minus: { speedKmh = max(3.5, speedKmh - 0.5) },
                            plus: { speedKmh = min(24.0, speedKmh + 0.5) })
                stepperTile("Incline", value: "\(Format.number(gradePct, maxDecimals: 1)) %",
                            minus: { gradePct = max(0.0, gradePct - 0.5) },
                            plus: { gradePct = min(20.0, gradePct + 0.5) })
            }

            HStack(spacing: 10) {
                stepperTile("Duration", value: "\(Int(durationMin.rounded())) min",
                            minus: { durationMin = max(5.0, durationMin - 5.0) },
                            plus: { durationMin = min(180.0, durationMin + 5.0) })

                VStack(spacing: 6) {
                    SectionLabel("Steady HR")
                    HStack {
                        TextField("BPM", text: $steadyHrText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(10)
                .background(Theme.card2)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button("+ Log steady treadmill run") {
                do {
                    _ = try services.treadmillVo2.addLog(TreadmillVo2Draft(
                        loggedOn: initialDay, speedKmh: speedKmh, gradePct: gradePct, durationMin: durationMin,
                        steadyHr: steadyInt, restingHr: rhrInt, maxHr: maxHrInt
                    ))
                    reload()
                    session.didChange()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("whoop-log-treadmill-button")

            ForEach(snap.longevity.treadmillLogs.prefix(5)) { log in
                HStack {
                    Text("\(Format.shortDate(log.loggedOn)) · \(Format.number(log.speedKmh, maxDecimals: 1)) km/h @ \(Format.number(log.gradePct, maxDecimals: 1))%")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                    Spacer()
                    Button("\(Format.number(log.estimatedVo2Max, maxDecimals: 1)) ✎") {
                        editingLog = log
                    }
                    .font(.system(size: 13, weight: .bold)).foregroundColor(Theme.green)
                }
                .padding(.top, 4)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-acsm-card")
    }

    private func stepperTile(_ label: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            SectionLabel(label)
            HStack {
                Button("−", action: minus)
                    .font(.system(size: 20, weight: .bold)).foregroundColor(Theme.green)
                    .frame(width: 34, height: 36).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 2)
                Text(value).font(.system(size: 16, weight: .heavy)).foregroundColor(Theme.text)
                Spacer(minLength: 2)
                Button("+", action: plus)
                    .font(.system(size: 20, weight: .bold)).foregroundColor(Theme.green)
                    .frame(width: 34, height: 36).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(10)
        .background(Theme.card2)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Supporting Edit Sheets (Sleep Override, Nap Editor, Treadmill Log Editor)

struct WhoopSleepOverrideSheet: View {
    let dayId: String
    let current: WhoopSleepBreakdownViewModel
    let whoopDb: Database?
    @Environment(\.dismiss) private var dismiss
    @State private var onsetDate = Date()
    @State private var offsetDate = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Sleep span for \(dayId)") {
                    DatePicker("Fell asleep", selection: $onsetDate)
                    DatePicker("Woke up", selection: $offsetDate)
                    TextField("Note (optional)", text: $note)
                }
                if current.hasManualOverride {
                    Section {
                        Button("Clear manual override (revert to WHOOP auto)", role: .destructive) {
                            if let whoopDb { try? WhoopAnalyticsStore(whoopDb).deleteSleepOverride(dayId: dayId) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Edit Sleep Span")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let whoopDb else { dismiss(); return }
                        do {
                            let sTs = Int64(onsetDate.timeIntervalSince1970)
                            let eTs = Int64(offsetDate.timeIntervalSince1970)
                            let restaged: WhoopRecalculatedStages? = {
                                guard let store = try? WhoopStore(whoopDb),
                                      let seg = try? store.stageSleepFromSubstrate(onsetSec: sTs, offsetSec: eTs, sleepSource: "override") else {
                                    return nil
                                }
                                return WhoopRecalculatedStages(
                                    tstMin: seg.tstSec / 60,
                                    deepMin: seg.deepSec / 60,
                                    remMin: seg.remSec / 60,
                                    lightMin: seg.lightSec / 60,
                                    wasoMin: seg.wasoSec / 60,
                                    efficiencyPct: Int(seg.efficiencyPct.rounded()),
                                    awakenings: seg.sustainedAwakenings
                                )
                            }()
                            try WhoopAnalyticsStore(whoopDb).upsertSleepOverride(
                                dayId: dayId,
                                startTs: sTs,
                                endTs: eTs,
                                note: note.isEmpty ? nil : note,
                                recalculatedStages: restaged,
                                nowSec: Int64(Date().timeIntervalSince1970)
                            )
                            dismiss()
                        } catch {
                            errorMessage = (error as? ValidationError)?.message ?? error.localizedDescription
                        }
                    }
                }
            }
            .onAppear {
                if let on = current.onsetSec { onsetDate = Date(timeIntervalSince1970: TimeInterval(on)) }
                else { onsetDate = Date().addingTimeInterval(-8 * 3600) }
                if let off = current.offsetSec { offsetDate = Date(timeIntervalSince1970: TimeInterval(off)) }
                else { offsetDate = Date() }
            }
            .errorAlert($errorMessage)
        }
    }
}

struct WhoopNapEditorSheet: View {
    let dayId: String
    let existing: WhoopNapRecord?
    let whoopDb: Database?
    @Environment(\.dismiss) private var dismiss
    @State private var startDate = Date().addingTimeInterval(-1800)
    @State private var endDate = Date()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Nap window (5m – 3h)") {
                    DatePicker("Start", selection: $startDate)
                    DatePicker("End", selection: $endDate)
                }
                if let existing {
                    Section {
                        Button("Delete nap", role: .destructive) {
                            if let whoopDb { try? WhoopAnalyticsStore(whoopDb).deleteNap(dayId: dayId, startTs: existing.startTs) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Nap" : "Edit Nap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let whoopDb else { dismiss(); return }
                        do {
                            let store = WhoopAnalyticsStore(whoopDb)
                            let s = Int64(startDate.timeIntervalSince1970)
                            let e = Int64(endDate.timeIntervalSince1970)
                            if let existing {
                                try store.updateNapSpan(dayId: dayId, oldStartTs: existing.startTs, newStartTs: s, newEndTs: e)
                            } else {
                                try store.upsertNap(dayId: dayId, startTs: s, endTs: e, source: "manual")
                            }
                            dismiss()
                        } catch {
                            errorMessage = (error as? ValidationError)?.message ?? error.localizedDescription
                        }
                    }
                }
            }
            .onAppear {
                if let existing {
                    startDate = Date(timeIntervalSince1970: TimeInterval(existing.startTs))
                    endDate = Date(timeIntervalSince1970: TimeInterval(existing.endTs))
                }
            }
            .errorAlert($errorMessage)
        }
    }
}

struct TreadmillVo2EditSheet: View {
    let log: TreadmillVo2Log
    let service: AcsmTreadmillVo2Service
    @Environment(\.dismiss) private var dismiss
    @State private var speedText = ""
    @State private var gradeText = ""
    @State private var durText = ""
    @State private var hrText = ""
    @State private var notes = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Treadmill run (\(Format.longDate(log.loggedOn)))") {
                    TextField("Speed (km/h)", text: $speedText).keyboardType(.decimalPad)
                    TextField("Incline (%)", text: $gradeText).keyboardType(.decimalPad)
                    TextField("Duration (min)", text: $durText).keyboardType(.decimalPad)
                    TextField("Steady HR (optional)", text: $hrText).keyboardType(.numberPad)
                    TextField("Notes", text: $notes)
                }
                Section {
                    Button("Delete treadmill log", role: .destructive) {
                        try? service.deleteLog(id: log.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Treadmill Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            guard let sp = Format.decimal(speedText),
                                  let gr = Format.decimal(gradeText),
                                  let du = Format.decimal(durText) else {
                                throw ValidationError("Enter valid numbers for speed, incline, and duration")
                            }
                            try service.updateLog(id: log.id, TreadmillVo2Draft(
                                loggedOn: log.loggedOn, speedKmh: sp, gradePct: gr, durationMin: du,
                                steadyHr: Int(hrText.trimmingCharacters(in: .whitespaces)),
                                restingHr: log.restingHr, maxHr: log.maxHr, notes: notes
                            ))
                            dismiss()
                        } catch {
                            errorMessage = (error as? ValidationError)?.message ?? error.localizedDescription
                        }
                    }
                }
            }
            .onAppear {
                speedText = Format.number(log.speedKmh)
                gradeText = Format.number(log.gradePct)
                durText = Format.number(log.durationMin)
                hrText = log.steadyHr.map(String.init) ?? ""
                notes = log.notes ?? ""
            }
            .errorAlert($errorMessage)
        }
    }
}

// MARK: - Outdoor GPS 1-km Split Submaximal VO2 Max (`vo2maxSubmaxEstimate`)

@MainActor
final class OutdoorGpsSplitRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var currentSplitMeters: Double = 0
    @Published private(set) var completedSplits: [WhoopGpsSplit] = []

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var splitStartTime: Date?
    private var splitStartAlt: Double?
    private var splitHrSamples: [Int] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        completedSplits.removeAll()
        currentSplitMeters = 0
        lastLocation = nil
        splitStartTime = Date()
        splitStartAlt = nil
        splitHrSamples.removeAll()
        isRecording = true
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        isRecording = false
    }

    func recordHr(_ bpm: Int?) {
        guard isRecording, let bpm, bpm > 30 else { return }
        splitHrSamples.append(bpm)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard self.isRecording else { return }
            for loc in locations where loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= 50 {
                if self.splitStartAlt == nil { self.splitStartAlt = loc.altitude }
                if let prev = self.lastLocation {
                    let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
                    let dist = loc.distance(from: prev)
                    if dt > 0 && (dist / dt) <= 12.0 {
                        self.currentSplitMeters += dist
                    }
                }
                self.lastLocation = loc
                if self.currentSplitMeters >= 1000.0, let st = self.splitStartTime {
                    let dur = max(1.0, loc.timestamp.timeIntervalSince(st))
                    let avgHr = self.splitHrSamples.isEmpty ? 152 : (self.splitHrSamples.reduce(0, +) / self.splitHrSamples.count)
                    self.completedSplits.append(WhoopGpsSplit(
                        meters: self.currentSplitMeters,
                        durationSec: dur,
                        avgHrBpm: avgHr,
                        startAltM: self.splitStartAlt,
                        endAltM: loc.altitude
                    ))
                    self.currentSplitMeters = 0
                    self.splitStartTime = loc.timestamp
                    self.splitStartAlt = loc.altitude
                    self.splitHrSamples.removeAll()
                }
            }
        }
    }
}

struct OutdoorGpsVo2Card: View {
    let loggedOn: ISODate
    let rhrBpm: Int
    let maxHrBpm: Int
    let onLogged: () -> Void

    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager
    @StateObject private var gps = OutdoorGpsSplitRecorder()

    @State private var splitSecText = "330" // 5:30 / km (>= 300s steady gate)
    @State private var netElevMText = "4"
    @State private var avgHrText = "150"
    @State private var banner: String?

    var body: some View {
        let durSec = Double(splitSecText.trimmingCharacters(in: .whitespaces)) ?? 330
        let netElev = Double(netElevMText.trimmingCharacters(in: .whitespaces)) ?? 0
        let avgHr = Int(avgHrText.trimmingCharacters(in: .whitespaces)) ?? 150
        let manualSplit = WhoopGpsSplit(meters: 1000.0, durationSec: durSec, avgHrBpm: avgHr, startAltM: 0, endAltM: netElev)
        let activeSplits = gps.completedSplits.isEmpty ? [manualSplit] : gps.completedSplits
        let est = WhoopOutdoorGpsVo2Engine.fromOneKmSplits(activeSplits, restingHrBpm: rhrBpm, hrMaxBpm: maxHrBpm)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("GPS Outdoor Run · 1-km Split VO2 Max")
                Spacer()
                if let est {
                    Pill(text: "VO2 \(Format.number(est.vo2MaxMlKgMin, maxDecimals: 1))", tone: .green)
                } else {
                    Pill(text: "40–90% HRR gate", tone: .grey)
                }
            }

            Text("Uses CoreLocation 1-km splits (≥5 min steady bout, net elevation Δalt, Swain %HRR extrapolation) or manual 1-km outdoor split entry.")
                .font(.system(size: 11.5)).foregroundColor(Theme.muted)

            HStack(spacing: 8) {
                Button(gps.isRecording ? "Stop GPS (\(Int(gps.currentSplitMeters))m)" : "Start Live GPS Run") {
                    if gps.isRecording { gps.stop() } else {
                        whoop.toggleLiveHeartRate(true)
                        gps.start()
                    }
                }
                .buttonStyle(PrimaryButtonStyle(ghost: gps.isRecording))
                .accessibilityIdentifier("whoop-gps-toggle-button")
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel("1-km Split (sec)")
                    TextField("330", text: $splitSecText).keyboardType(.numberPad)
                        .font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text)
                }
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel("Net Elev (m)")
                    TextField("0", text: $netElevMText).keyboardType(.numbersAndPunctuation)
                        .font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text)
                }
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel("Avg HR")
                    TextField("150", text: $avgHrText).keyboardType(.numberPad)
                        .font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text)
                }
            }
            .padding(10)
            .background(Theme.card2)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let est {
                Button("+ Save Outdoor GPS VO2 Estimate (\(Format.number(est.vo2MaxMlKgMin, maxDecimals: 1)))") {
                    let speedKmh = (1000.0 / max(1.0, durSec)) * 3.6
                    let gradePct = (netElev / 1000.0) * 100.0
                    _ = try? services.treadmillVo2.addLog(TreadmillVo2Draft(
                        loggedOn: loggedOn, speedKmh: speedKmh, gradePct: max(0, gradePct),
                        durationMin: durSec / 60.0, steadyHr: avgHr, restingHr: rhrBpm, maxHr: maxHrBpm,
                        notes: "GPS 1-km outdoor split"
                    ))
                    banner = "Saved outdoor GPS VO2 max (\(Format.number(est.vo2MaxMlKgMin, maxDecimals: 1)) mL/kg/min)."
                    onLogged()
                }
                .buttonStyle(PrimaryButtonStyle(ghost: true))
                .accessibilityIdentifier("whoop-save-gps-vo2-button")
            }

            if let banner {
                Text(banner).font(.system(size: 12)).foregroundColor(Theme.green)
            }
        }
        .card()
        .onChange(of: whoop.liveHrBpm) { bpm in gps.recordHr(bpm) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-gps-vo2-card")
    }
}
