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

    private func sleepCard(_ snap: WhoopDashboardSnapshot) -> some View {
        let s = snap.sleep
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("4-stage sleep · \(s.scoredDayId)\(s.hasManualOverride ? " · manual span" : "")")
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
                }
                Spacer(minLength: 0)
            }

            stageBar(title: "Deep (SWS)", minutes: s.deepMinutes, total: max(1, s.totalSleepMinutes), color: Theme.greenDeep)
            stageBar(title: "REM", minutes: s.remMinutes, total: max(1, s.totalSleepMinutes), color: Theme.greenSoft)
            stageBar(title: "Light", minutes: s.lightMinutes, total: max(1, s.totalSleepMinutes), color: Theme.green)
            stageBar(title: "WASO (\(s.awakenings) awakening\(s.awakenings == 1 ? "" : "s"))", minutes: s.wasoMinutes, total: max(60, s.totalSleepMinutes), color: Theme.amber)
        }
        .card()
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
                HStack {
                    Text("\(hmString(nap.startTs)) – \(hmString(nap.endTs)) · \(nap.durationSec / 60) min (\(nap.source))")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(Theme.text)
                    Spacer()
                    Button("Edit") { editingNap = nap }
                        .font(.system(size: 12.5, weight: .semibold)).foregroundColor(Theme.green)
                }
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
                            minus: { speedKmh = max(4.0, speedKmh - 0.5) },
                            plus: { speedKmh = min(24.0, speedKmh + 0.5) })
                stepperTile("Incline", value: "\(Format.number(gradePct, maxDecimals: 1)) %",
                            minus: { gradePct = max(0.0, gradePct - 0.5) },
                            plus: { gradePct = min(20.0, gradePct + 0.5) })
            }

            HStack {
                Text("Steady HR (optional)").font(.system(size: 13)).foregroundColor(Theme.muted)
                Spacer()
                TextField("BPM", text: $steadyHrText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.text)
                    .frame(width: 72)
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
                            try WhoopAnalyticsStore(whoopDb).upsertSleepOverride(
                                dayId: dayId,
                                startTs: Int64(onsetDate.timeIntervalSince1970),
                                endTs: Int64(offsetDate.timeIntervalSince1970),
                                note: note.isEmpty ? nil : note,
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
