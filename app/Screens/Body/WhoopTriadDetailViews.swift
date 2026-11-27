import FitnessCore
import SwiftUI

// MARK: - Top-Level Banner on Body Tab When Unreviewed Naps or Workouts Exist

struct WhoopPendingReviewBanner: View {
    let workouts: [WhoopActivityProposal]
    let naps: [WhoopActivityProposal]
    let onChanged: () -> Void

    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager
    @EnvironmentObject private var session: AppSession

    var body: some View {
        let total = workouts.count + naps.count
        if total > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(Theme.amber)
                    SectionLabel("Activities require your review (\(total))")
                    Spacer()
                    Pill(text: "\(total) pending", tone: .amber)
                }

                ForEach(naps) { prop in
                    let mins = max(1, Int((prop.endTs - prop.startTs) / 60))
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daytime Nap · \(mins) min")
                                .font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.text)
                            Text("\(prop.dayId) · \(hm(prop.startTs))–\(hm(prop.endTs))")
                                .font(.system(size: 11.5)).foregroundColor(Theme.muted)
                        }
                        Spacer()
                        Button("Accept") { acceptNap(prop) }
                            .buttonStyle(CompactButtonStyle())
                        Button("Decline") { decline(prop) }
                            .buttonStyle(CompactButtonStyle(ghost: true))
                    }
                }

                ForEach(workouts) { prop in
                    let mins = max(1, Int((prop.endTs - prop.startTs) / 60))
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Detected Workout · \(mins) min")
                                .font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.text)
                            Text("\(prop.dayId) · \(hm(prop.startTs))–\(hm(prop.endTs))")
                                .font(.system(size: 11.5)).foregroundColor(Theme.muted)
                        }
                        Spacer()
                        Button("Accept") { acceptWorkout(prop) }
                            .buttonStyle(CompactButtonStyle())
                        Button("Decline") { decline(prop) }
                            .buttonStyle(CompactButtonStyle(ghost: true))
                    }
                }
            }
            .card(padding: 12, highlighted: true)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("whoop-pending-review-banner")
        }
    }

    private func acceptNap(_ prop: WhoopActivityProposal) {
        guard let db = whoop.db else { return }
        let store = WhoopAnalyticsStore(db)
        try? store.upsertNap(dayId: prop.dayId, startTs: prop.startTs, endTs: prop.endTs, source: "accepted", payloadJson: prop.detailsJson)
        try? store.updateProposalStatus(id: prop.id, status: "accepted")
        onChanged()
        session.didChange()
    }

    private func acceptWorkout(_ prop: WhoopActivityProposal) {
        guard let db = whoop.db else { return }
        let store = WhoopAnalyticsStore(db)
        _ = try? services.workoutSessions.acceptWorkoutProposal(
            proposalId: prop.id, analyticsStore: store, kind: .easyCardio, sport: "Detected Cardio"
        )
        onChanged()
        session.didChange()
    }

    private func decline(_ prop: WhoopActivityProposal) {
        guard let db = whoop.db else { return }
        try? WhoopAnalyticsStore(db).updateProposalStatus(id: prop.id, status: "discarded")
        onChanged()
        session.didChange()
    }

    private func hm(_ epochSec: Int64) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(epochSec)))
    }
}

// MARK: - Shared Day Switcher Bar for Recovery / Strain / Sleep / Steps Detail Views

private struct WhoopDetailDaySwitcher: View {
    @Binding var day: ISODate
    let maxDay: ISODate

    var body: some View {
        HStack {
            Button {
                day = day.adding(days: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.green)
                    .frame(width: 32, height: 32)
                    .background(Theme.card)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("whoop-detail-prev-day")

            Spacer()
            Text(Format.longDate(day))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.text)
            Spacer()

            Button {
                if day < maxDay { day = day.adding(days: 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(day < maxDay ? Theme.green : Theme.muted.opacity(0.4))
                    .frame(width: 32, height: 32)
                    .background(Theme.card)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(day >= maxDay)
            .accessibilityIdentifier("whoop-detail-next-day")
        }
    }
}

// MARK: - 1. Dedicated Recovery Detail Screen (31-Day Rated Draggable Bar Chart + Contributors + Temp)

struct WhoopRecoveryDetailView: View {
    let initialDay: ISODate
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager

    @State private var currentDay: ISODate
    @State private var snapshot: WhoopDashboardSnapshot?
    @State private var detail: WhoopRecoveryDetailModel?
    @State private var selectedBar: WhoopRecoveryDayBar?

    init(initialDay: ISODate) {
        self.initialDay = initialDay
        _currentDay = State(initialValue: initialDay)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                WhoopDetailDaySwitcher(day: $currentDay, maxDay: services.clock.today())
                if let snap = snapshot {
                    heroCard(snap)
                    if !snap.contributors.isEmpty {
                        contributorsCard(snap)
                    }
                    if let det = detail, !det.bars31d.isEmpty {
                        rated31DayCard(det)
                    }
                    skinTempCard(snap)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear(perform: reload)
        .onChange(of: currentDay) { _ in reload() }
        .accessibilityIdentifier("whoop-recovery-detail-screen")
    }

    private func reload() {
        let snap = try? WhoopDashboardPresenter.build(whoopDb: whoop.db, fitnessDb: services.db, on: currentDay)
        snapshot = snap
        let anchor = snap.flatMap { ISODate($0.scoredRecoveryDayId) } ?? currentDay
        detail = try? WhoopDetailPresenters.buildRecoveryDetail(whoopDb: whoop.db, upTo: anchor)
        selectedBar = detail?.bars31d.last
    }

    private func heroCard(_ snap: WhoopDashboardSnapshot) -> some View {
        HStack(spacing: 16) {
            let p = snap.readinessScore.map { Double($0) / 100.0 } ?? 0.05
            let lbl = snap.readinessScore.map { "\($0)%" } ?? "—"
            RingView(progress: p, size: 106, lineWidth: 10, label: lbl, subLabel: "recovery", color: snap.readinessTone.color)
            VStack(alignment: .leading, spacing: 6) {
                Pill(text: snap.readinessPill, tone: snap.readinessTone.pillTone)
                Text(snap.readinessHeadline)
                    .font(.system(size: 19, weight: .bold)).foregroundColor(Theme.text)
                Text(snap.readinessDetail)
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
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
                SectionLabel("What went into recovery · 28d baseline")
                Spacer()
                SectionLabel("7d trend")
            }
            ForEach(snap.contributors) { item in
                HStack(spacing: 10) {
                    RingView(progress: item.ringProgress, size: 40, lineWidth: 4, label: item.ringLabel, color: item.tone.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                        Text(item.subtitle).font(.system(size: 11.5)).foregroundColor(Theme.muted)
                    }
                    Spacer(minLength: 4)
                    SparklineView(values: item.sparkline, width: 54, height: 18)
                    Pill(text: item.badgeText, tone: item.tone.pillTone)
                }
                .padding(.vertical, 3)
                .accessibilityIdentifier("whoop-contributor-\(item.id)")
            }
        }
        .card()
    }

    private func rated31DayCard(_ det: WhoopRecoveryDetailModel) -> some View {
        let active = selectedBar ?? det.bars31d.last
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Last \(det.bars31d.count) days rated")
                Spacer()
                Pill(text: "Usual \(det.usualLow)–\(det.usualHigh)%", tone: .grey)
            }

            if let a = active {
                HStack(spacing: 8) {
                    Text(a.date)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.text)
                    Text("\(a.score)%")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(a.tone.color)
                    Pill(text: a.rating, tone: a.tone.pillTone)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.card2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let n = max(1, det.bars31d.count)
                let step = w / CGFloat(n)
                let barW = max(3.5, step - 2.5)
                let yHi = h * CGFloat(1.0 - Double(det.usualHigh) / 100.0)
                let yLo = h * CGFloat(1.0 - Double(det.usualLow) / 100.0)

                ZStack(alignment: .bottomLeading) {
                    // Usual range shaded band
                    Rectangle()
                        .fill(Theme.muted.opacity(0.12))
                        .frame(width: w, height: max(4, yLo - yHi))
                        .position(x: w / 2, y: (yHi + yLo) / 2)

                    HStack(alignment: .bottom, spacing: max(1.5, step - barW)) {
                        ForEach(det.bars31d) { bar in
                            let isSel = (bar.id == active?.id)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(bar.tone.color.opacity(isSel ? 1.0 : 0.68))
                                .frame(width: barW, height: max(6, h * CGFloat(Double(bar.score) / 100.0)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(isSel ? Color.white : Color.clear, lineWidth: 1.2)
                                )
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let idx = min(n - 1, max(0, Int((drag.location.x / max(1, w)) * CGFloat(n))))
                            selectedBar = det.bars31d[idx]
                        }
                )
            }
            .frame(height: 126)

            HStack {
                Text(det.bars31d.first?.shortLabel ?? "")
                    .font(.system(size: 11)).foregroundColor(Theme.muted)
                Spacer()
                Text("Drag or tap any bar for daily score & rating")
                    .font(.system(size: 10.5)).foregroundColor(Theme.muted)
                Spacer()
                Text(det.bars31d.last?.shortLabel ?? "")
                    .font(.system(size: 11)).foregroundColor(Theme.muted)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-recovery-31d-bars-card")
    }

    private func skinTempCard(_ snap: WhoopDashboardSnapshot) -> some View {
        let unit = snap.temperatureUnit
        let flag = snap.illnessDay?.flag ?? .normal
        let zVal = snap.illnessDay?.z ?? 0.0
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
                RingView(progress: flag == .elevated ? 0.35 : 0.90, size: 52, lineWidth: 5,
                         label: String(format: "%+.1fσ", zVal), subLabel: unit.label,
                         color: flag == .elevated ? Theme.red : Theme.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snap.skinTempCelsius.map { unit.format(celsius: $0) } ?? "Calibrating skin temp")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                    Text(flag == .elevated ? "Elevated ≥2 consecutive nights vs 21d baseline." : "Within 21d baseline (alerts at z ≥ 2.0 for ≥2 nights).")
                        .font(.system(size: 11.5)).foregroundColor(Theme.muted)
                }
                Spacer(minLength: 0)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-skin-temp-illness-card")
    }
}

// MARK: - 2. Dedicated Strain Detail Screen (Intraday Strain Graph + Cardio Zone Time Breakdown + Steps Link)

struct WhoopStrainDetailView: View {
    let initialDay: ISODate
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager

    @State private var currentDay: ISODate
    @State private var snapshot: WhoopDashboardSnapshot?
    @State private var strainDetail: WhoopStrainDetailModel?

    init(initialDay: ISODate) {
        self.initialDay = initialDay
        _currentDay = State(initialValue: initialDay)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                WhoopDetailDaySwitcher(day: $currentDay, maxDay: services.clock.today())
                if let snap = snapshot {
                    heroCard(snap)
                    if let det = strainDetail {
                        intradayStrainCard(det)
                        zonesCard(det)
                    }
                    NavigationLink {
                        WhoopStepsDetailView(initialDay: currentDay)
                    } label: {
                        HStack {
                            Image(systemName: "figure.walk.circle.fill")
                                .font(.system(size: 22)).foregroundColor(Theme.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Steps & Zone 0–5 Calculator")
                                    .font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text)
                                Text("\(snap.steps) steps · View hourly timeline & select counted HR zones")
                                    .font(.system(size: 11.5)).foregroundColor(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(Theme.muted)
                        }
                        .card(padding: 13)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("whoop-strain-open-steps")
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Day Strain")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear(perform: reload)
        .onChange(of: currentDay) { _ in reload() }
        .accessibilityIdentifier("whoop-strain-detail-screen")
    }

    private func reload() {
        let snap = try? WhoopDashboardPresenter.build(whoopDb: whoop.db, fitnessDb: services.db, on: currentDay)
        snapshot = snap
        if let snap {
            let targetIso = (snap.strain > 0 ? currentDay : (ISODate(snap.scoredRecoveryDayId) ?? currentDay))
            let rhr = snap.longevity.fitnessAge?.medianRhr ?? 53.0
            strainDetail = try? WhoopDetailPresenters.buildStrainDetail(
                whoopDb: whoop.db, on: targetIso, zones: snap.zones, rhr: rhr
            )
        }
    }

    private func heroCard(_ snap: WhoopDashboardSnapshot) -> some View {
        let st = max(snap.strain, strainDetail?.finalStrain ?? 0)
        return HStack(spacing: 16) {
            RingView(
                progress: min(1.0, max(0.04, st / 21.0)),
                size: 104,
                lineWidth: 10,
                label: String(format: "%.1f", st),
                subLabel: "of 21",
                color: Theme.gold
            )
            VStack(alignment: .leading, spacing: 5) {
                Pill(text: st >= 14 ? "High load" : (st >= 10 ? "Moderate load" : "Light / Restorative"), tone: .gold)
                Text("Exercise-Protected Strain")
                    .font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
                if let tot = snap.totalKcal {
                    let act = snap.activeKcal ?? 0
                    Text("\(Format.grouped(Double(tot))) kcal (\(Format.grouped(Double(max(0, tot - act)))) basal + \(Format.grouped(Double(act))) active)")
                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                } else {
                    Text("Net Banister TRIMP above your 28-day personal quiet-waking HRR baseline.")
                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 16)
    }

    private func intradayStrainCard(_ det: WhoopStrainDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Intraday Cumulative Strain · \(det.date.string)")
                Spacer()
                Text("\(det.totalTrackedWakeMinutes) wake min")
                    .font(.system(size: 11.5)).foregroundColor(Theme.muted)
            }
            if det.cumulativeCurve.count >= 2 {
                let pts = det.cumulativeCurve.map {
                    ChartPoint(label: $0.label, value: $0.value, series: "Strain")
                }
                TrendChart(points: pts, height: 146, seriesColors: ["Strain": Theme.gold])
                Text("Slide finger across curve to inspect cumulative 0–21 Strain at any 15-min interval.")
                    .font(.system(size: 11)).foregroundColor(Theme.muted)
            } else {
                Text("No waking 1 Hz heart-rate samples on \(det.date.string) yet.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-strain-intraday-card")
    }

    private func zonesCard(_ det: WhoopStrainDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Time in Heart Rate Zones")
            ForEach(det.zoneRows) { row in
                let barColor: Color = row.id >= 4 ? Theme.gold : (row.id == 2 ? Theme.green : (row.id == 3 ? Theme.amber : Theme.greenSoft))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.title).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                        Text(row.bpmRangeText).font(.system(size: 11)).foregroundColor(Theme.muted)
                        Spacer()
                        Text("\(row.minutes)m (\(row.pctOfTracked)%)")
                            .font(.system(size: 12.5, weight: .bold)).foregroundColor(Theme.text)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            Capsule()
                                .fill(barColor)
                                .frame(width: geo.size.width * CGFloat(min(1.0, max(0.02, Double(row.pctOfTracked) / 100.0))))
                        }
                    }
                    .frame(height: 7)
                }
                .padding(.vertical, 2)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-strain-zones-card")
    }
}

// MARK: - 3. Dedicated Sleep Detail Screen (OpenStrap-Style Hypnogram, Confidence Ranges, Concrete Usual Bars & 4 Overnight Signals)

struct WhoopSleepDetailView: View {
    let initialDay: ISODate
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager

    @State private var currentDay: ISODate
    @State private var snapshot: WhoopDashboardSnapshot?
    @State private var detail: WhoopSleepDetailModel?
    @State private var selectedHypnoBlock: WhoopHypnogramBlock?
    @State private var editingSleep = false
    @State private var addingNap = false
    @State private var editingNap: WhoopNapRecord?

    init(initialDay: ISODate) {
        self.initialDay = initialDay
        _currentDay = State(initialValue: initialDay)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                WhoopDetailDaySwitcher(day: $currentDay, maxDay: services.clock.today())
                if let snap = snapshot, let det = detail {
                    asleepHeroHeader(snap: snap, det: det)
                    hypnogramCard(det)
                    stageSummaryAndRangesCard(snap: snap, det: det)
                    if !det.usualComparisons.isEmpty {
                        againstYourUsualCard(det.usualComparisons)
                    }
                    overnightSignalsCard(det: det, unit: snap.temperatureUnit)
                    napsSection(snap)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear(perform: reload)
        .onChange(of: currentDay) { _ in reload() }
        .sheet(isPresented: $editingSleep, onDismiss: reload) {
            if let snap = snapshot {
                WhoopSleepOverrideSheet(dayId: snap.sleep.scoredDayId, current: snap.sleep, whoopDb: whoop.db)
            }
        }
        .sheet(isPresented: $addingNap, onDismiss: reload) {
            WhoopNapEditorSheet(dayId: currentDay.string, existing: nil, whoopDb: whoop.db)
        }
        .sheet(isPresented: Binding(get: { editingNap != nil }, set: { if !$0 { editingNap = nil } }), onDismiss: reload) {
            if let nap = editingNap {
                WhoopNapEditorSheet(dayId: nap.dayId, existing: nap, whoopDb: whoop.db)
            }
        }
        .accessibilityIdentifier("whoop-sleep-detail-screen")
    }

    private func reload() {
        let snap = try? WhoopDashboardPresenter.build(whoopDb: whoop.db, fitnessDb: services.db, on: currentDay)
        snapshot = snap
        if let snap {
            detail = try? WhoopDetailPresenters.buildSleepDetail(
                whoopDb: whoop.db, dayId: snap.sleep.scoredDayId, tempUnit: snap.temperatureUnit
            )
            selectedHypnoBlock = nil
        }
    }

    private func asleepHeroHeader(snap: WhoopDashboardSnapshot, det: WhoopSleepDetailModel) -> some View {
        let s = snap.sleep
        let bedSpanText: String = {
            guard let on = det.onsetSec, let off = det.offsetSec else { return "Auto window" }
            return "\(hm(on)) → \(hm(off)) · \(WhoopDashboardPresenter.formatHoursMinutes(det.inBedMinutes)) in bed"
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("ASLEEP · \(s.scoredDayId)\(s.hasManualOverride ? " · EDITED" : "")")
                    Text(WhoopDashboardPresenter.formatHoursMinutes(s.totalSleepMinutes))
                        .font(.system(size: 32, weight: .bold)).foregroundColor(Theme.text)
                    Text(bedSpanText)
                        .font(.system(size: 13, weight: .medium)).foregroundColor(Theme.muted)
                }
                Spacer()
                Button("Edit span") { editingSleep = true }
                    .buttonStyle(CompactButtonStyle(ghost: true))
                    .accessibilityIdentifier("whoop-edit-sleep-span")
            }

            HStack(spacing: 10) {
                statTile("EFFICIENCY", value: s.efficiencyPct > 0 ? "\(s.efficiencyPct)%" : "—", accent: Theme.green)
                statTile("TONIGHT NEED", value: "\(Format.number(s.dynamicSleepNeedHours, maxDecimals: 1))h", accent: Theme.greenSoft)
                statTile("TARGET BED", value: s.targetBedtimeHm, accent: Theme.gold)
            }

            HStack {
                Pill(
                    text: s.wakeConsistency.weekendJetLagFlagged ? "Jet Lag ≥2h" : (s.wakeConsistency.withinThirtyMinTarget ? "Wake ≤30m ✓" : "Wake ±\(s.wakeConsistency.wakeStdDevMinutes)m"),
                    tone: s.wakeConsistency.weekendJetLagFlagged ? .red : (s.wakeConsistency.withinThirtyMinTarget ? .green : .amber)
                )
                Text(s.wakeConsistency.summaryText)
                    .font(.system(size: 11.5)).foregroundColor(Theme.muted)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-sleep-card")
    }

    private func statTile(_ label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9.5, weight: .bold)).foregroundColor(Theme.muted)
            Text(value).font(.system(size: 16, weight: .bold)).foregroundColor(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func hypnogramCard(_ det: WhoopSleepDetailModel) -> some View {
        let lanes: [(WhoopSleepStage4, String, Color)] = [
            (.wake, "Awake", Theme.amber),
            (.rem, "REM", Color.cyan),
            (.light, "Light", Theme.green),
            (.deep, "Deep", Theme.greenDeep),
        ]

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Sleep Stages Hypnogram")
                Spacer()
                if let sel = selectedHypnoBlock {
                    Pill(text: "\(sel.timeLabel) · \(sel.stage.rawValue.uppercased())", tone: .green)
                }
            }

            if !det.hypnogramBlocks.isEmpty {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(lanes, id: \.1) { _, name, _ in
                            Text(name).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.muted)
                        }
                    }
                    .frame(width: 42, alignment: .leading)

                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        let laneH = h / 4.0
                        let n = max(1, det.hypnogramBlocks.count)
                        let stepW = w / CGFloat(n)

                        ZStack(alignment: .topLeading) {
                            // Subtle lane dividers
                            ForEach(0..<4, id: \.self) { r in
                                Path { p in
                                    let y = CGFloat(r) * laneH + laneH * 0.5
                                    p.move(to: CGPoint(x: 0, y: y))
                                    p.addLine(to: CGPoint(x: w, y: y))
                                }
                                .stroke(Theme.line.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            }

                            // Stage blocks + vertical connectors
                            ForEach(Array(det.hypnogramBlocks.enumerated()), id: \.element.id) { idx, blk in
                                let rowIdx = laneIndex(for: blk.stage)
                                let color = laneColor(for: blk.stage)
                                let x = CGFloat(idx) * stepW
                                let y = CGFloat(rowIdx) * laneH + laneH * 0.2

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color)
                                    .frame(width: max(2.5, stepW + 0.6), height: laneH * 0.6)
                                    .position(x: x + stepW * 0.5, y: y + laneH * 0.3)

                                if idx > 0 {
                                    let prevRow = laneIndex(for: det.hypnogramBlocks[idx - 1].stage)
                                    if prevRow != rowIdx {
                                        let y0 = CGFloat(min(prevRow, rowIdx)) * laneH + laneH * 0.5
                                        let y1 = CGFloat(max(prevRow, rowIdx)) * laneH + laneH * 0.5
                                        Path { p in
                                            p.move(to: CGPoint(x: x, y: y0))
                                            p.addLine(to: CGPoint(x: x, y: y1))
                                        }
                                        .stroke(Theme.muted.opacity(0.45), lineWidth: 1)
                                    }
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    let i = min(n - 1, max(0, Int((drag.location.x / max(1, w)) * CGFloat(n))))
                                    selectedHypnoBlock = det.hypnogramBlocks[i]
                                }
                        )
                    }
                    .frame(height: 128)
                }

                HStack {
                    Text(det.onsetSec.map(hm) ?? "")
                        .font(.system(size: 11)).foregroundColor(Theme.muted)
                    Spacer()
                    Text("Slide across night to inspect stage blocks")
                        .font(.system(size: 10.5)).foregroundColor(Theme.muted)
                    Spacer()
                    Text(det.offsetSec.map(hm) ?? "")
                        .font(.system(size: 11)).foregroundColor(Theme.muted)
                }
            } else {
                Text("No 1 Hz sleep window samples recorded on \(det.dayId).")
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-sleep-hypnogram-card")
    }

    private func laneIndex(for st: WhoopSleepStage4) -> Int {
        switch st {
        case .wake: return 0
        case .rem: return 1
        case .light, .unobserved: return 2
        case .deep: return 3
        }
    }

    private func laneColor(for st: WhoopSleepStage4) -> Color {
        switch st {
        case .wake: return Theme.amber
        case .rem: return Color.cyan
        case .light, .unobserved: return Theme.green
        case .deep: return Theme.greenDeep
        }
    }

    private func stageSummaryAndRangesCard(snap: WhoopDashboardSnapshot, det: WhoopSleepDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Stage Breakdown & Optical Confidence Ranges")
            Text("Wrist PPG + motion staging infers sleep states from autonomic heart-rate/HRV rhythms rather than brain EEG, so each stage shows both its point total and physiological 1σ range.")
                .font(.system(size: 11.5)).foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(det.stageRanges) { r in
                let color: Color = r.id == "deep" ? Theme.greenDeep : (r.id == "rem" ? Color.cyan : (r.id == "awake" ? Theme.amber : Theme.green))
                let maxDenom = Double(max(60, det.inBedMinutes))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(r.title).font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.text)
                        Text("(\(WhoopDashboardPresenter.formatHoursMinutes(r.lowMinutes)) – \(WhoopDashboardPresenter.formatHoursMinutes(r.highMinutes)))")
                            .font(.system(size: 11.5)).foregroundColor(Theme.muted)
                        Spacer()
                        Text("\(WhoopDashboardPresenter.formatHoursMinutes(r.pointMinutes)) · \(r.pctText)")
                            .font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text)
                    }
                    GeometryReader { geo in
                        let w = geo.size.width
                        let loX = w * CGFloat(min(1.0, Double(r.lowMinutes) / maxDenom))
                        let hiX = w * CGFloat(min(1.0, Double(r.highMinutes) / maxDenom))
                        let ptW = w * CGFloat(min(1.0, max(0.03, Double(r.pointMinutes) / maxDenom)))
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            Capsule()
                                .fill(color.opacity(0.30))
                                .frame(width: max(6, hiX - loX))
                                .offset(x: loX)
                            Capsule()
                                .fill(color)
                                .frame(width: ptW)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(.vertical, 2)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-sleep-stage-ranges-card")
    }

    private func againstYourUsualCard(_ rows: [WhoopUsualComparisonRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Against Your Usual (28d Personal Band)")
                Spacer()
                Text("Shaded = Usual p20–p80").font(.system(size: 10.5)).foregroundColor(Theme.muted)
            }

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(row.title).font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.text)
                        Spacer()
                        Text(row.tonightText).font(.system(size: 13.5, weight: .bold)).foregroundColor(Theme.text)
                        Pill(text: row.deltaBadge, tone: row.inUsualBand ? .green : .amber)
                    }
                    GeometryReader { geo in
                        let w = geo.size.width
                        let uStart = w * CGFloat(row.usualStartFrac)
                        let uWidth = max(16, w * CGFloat(row.usualEndFrac - row.usualStartFrac))
                        let pinX = min(w - 6, max(6, w * CGFloat(row.pinPosition)))
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line).frame(height: 8)
                            Capsule()
                                .fill(Theme.green.opacity(0.28))
                                .frame(width: uWidth, height: 10)
                                .offset(x: uStart)
                            Circle()
                                .fill(row.inUsualBand ? Theme.green : Theme.gold)
                                .frame(width: 12, height: 12)
                                .position(x: pinX, y: 6)
                        }
                    }
                    .frame(height: 12)
                    Text("Usual 28d range: \(row.usualRangeText)")
                        .font(.system(size: 11)).foregroundColor(Theme.muted)
                }
                .padding(.vertical, 3)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-sleep-against-usual-card")
    }

    private func overnightSignalsCard(det: WhoopSleepDetailModel, unit: TemperatureUnitPreference) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Overnight Signals (Bedtime → Wake)")

            signalSubChart(title: "Heart rate", summary: det.hrSummary, points: det.hrSignal, color: Theme.red)
            Divider().background(Theme.line)
            signalSubChart(title: "HRV (rMSSD)", summary: det.hrvSummary, points: det.hrvSignal, color: Theme.green)
            Divider().background(Theme.line)
            signalSubChart(title: "Breathing", summary: det.respSummary, points: det.respSignal, color: Color.cyan)
            Divider().background(Theme.line)
            signalSubChart(title: "Skin temp (\(unit.label))", summary: det.tempSummary, points: det.tempSignal, color: Theme.amber)
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-sleep-overnight-signals-card")
    }

    @ViewBuilder
    private func signalSubChart(title: String, summary: String, points: [WhoopIntradayPoint], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                Spacer()
                Text(summary).font(.system(size: 12.5, weight: .bold)).foregroundColor(Theme.muted)
            }
            if points.count >= 2 {
                let cPts = points.map { ChartPoint(label: $0.label, value: $0.value, series: title) }
                TrendChart(points: cPts, height: 92, seriesColors: [title: color])
            } else {
                Text("Insufficient overnight samples for \(title.lowercased()).")
                    .font(.system(size: 11.5)).foregroundColor(Theme.muted)
            }
        }
    }

    private func napsSection(_ snap: WhoopDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Naps")
                Spacer()
                Button("+ Log a nap") { addingNap = true }
                    .font(.system(size: 12.5, weight: .semibold)).foregroundColor(Theme.green)
                    .accessibilityIdentifier("whoop-add-nap")
            }
            if snap.effectiveNaps.isEmpty {
                Text("No naps logged on this day.")
                    .font(.system(size: 12.5)).foregroundColor(Theme.muted)
            } else {
                ForEach(snap.effectiveNaps, id: \.startTs) { nap in
                    let durMin = nap.durationSec / 60
                    let startDt = Date(timeIntervalSince1970: TimeInterval(nap.startTs))
                    let startMin = Calendar.current.component(.hour, from: startDt) * 60 + Calendar.current.component(.minute, from: startDt)
                    let sleepDep = Double(snap.sleep.totalSleepMinutes) / 60.0 < (snap.sleep.dynamicSleepNeedHours - 0.75)
                    let comp = WhoopWakeAndNapComplianceEngine.evaluateNap(durationMin: durMin, startMinuteOfDay: startMin, sleepDeprived: sleepDep)
                    HStack {
                        Text("\(hm(nap.startTs)) – \(hm(nap.endTs)) · \(durMin)m")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                        Pill(text: comp.badgeText, tone: comp.compliant ? .green : .amber)
                        Spacer()
                        Button("Edit") { editingNap = nap }
                            .font(.system(size: 12.5, weight: .semibold)).foregroundColor(Theme.green)
                    }
                }
            }
        }
        .card()
    }

    private func hm(_ epochSec: Int64) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(epochSec)))
    }
}

// MARK: - 4. Dedicated Steps & Zone 0..5 Checkmark Calculator + Hourly Timeline Screen

struct WhoopStepsDetailView: View {
    let initialDay: ISODate
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager

    @State private var currentDay: ISODate
    @State private var detail: WhoopStepsDetailModel?
    @State private var selectedZones: Set<Int> = [1, 2] // Default: Zone 1 & Zone 2 per owner preference, with checkmarks for all 0..5
    @State private var selectedHourSlot: WhoopHourlyStepsSlot?
    @State private var stepDivisor: Double = 1.0

    init(initialDay: ISODate) {
        self.initialDay = initialDay
        _currentDay = State(initialValue: initialDay)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                WhoopDetailDaySwitcher(day: $currentDay, maxDay: services.clock.today())
                if let det = detail {
                    countedTotalHero(det)
                    hourlyTimelineCard(det)
                    zoneCheckmarkCalculatorCard(det)
                    stepDivisorExplainerCard(det)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Steps & Zones")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear(perform: reload)
        .onChange(of: currentDay) { _ in reload() }
        .accessibilityIdentifier("whoop-steps-detail-screen")
    }

    private func reload() {
        let def = (try? services.appDefaults.load()) ?? AppDefaultsSnapshot()
        stepDivisor = def.stepTicksPerStep
        let snap = try? WhoopDashboardPresenter.build(whoopDb: whoop.db, fitnessDb: services.db, on: currentDay)
        let zones = snap?.zones ?? WhoopReadinessAndStrainEngine.trainingZones(ageYears: 30)
        let targetDay = (snap?.steps ?? 0) > 0 ? currentDay : (snap.flatMap { ISODate($0.scoredRecoveryDayId) } ?? currentDay)
        detail = try? WhoopDetailPresenters.buildStepsDetail(
            whoopDb: whoop.db, on: targetDay, zones: zones,
            stepTicksPerStep: def.stepTicksPerStep, filterGaitOnly: def.stepFilterGaitOnly
        )
        selectedHourSlot = detail?.hourlySlots.max(by: { $0.steps(selectedZones: selectedZones) < $1.steps(selectedZones: selectedZones) })
    }

    private func countedTotalHero(_ det: WhoopStepsDetailModel) -> some View {
        let counted = selectedZones.reduce(0) { acc, z in
            acc + (z >= 0 && z < det.zoneTotals.count ? det.zoneTotals[z] : 0)
        }
        let allDetected = det.zoneTotals.reduce(0, +)
        let excluded = max(0, allDetected - counted)

        return HStack(spacing: 16) {
            RingView(
                progress: min(1.0, max(0.05, Double(counted) / 10_000.0)),
                size: 96,
                lineWidth: 9,
                label: Format.grouped(Double(counted)),
                subLabel: "counted",
                color: Theme.green
            )
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Selected Zones Step Total · \(det.date.string)")
                Text("\(Format.grouped(Double(counted))) steps counted")
                    .font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
                Text("Excluded HR zones produced \(Format.grouped(Double(excluded))) steps (shown below, not added to your counted total).")
                    .font(.system(size: 11.5)).foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 15)
    }

    private func hourlyTimelineCard(_ det: WhoopStepsDetailModel) -> some View {
        let maxHourSteps = max(1, det.hourlySlots.map { $0.steps(selectedZones: Set(0...5)) }.max() ?? 1)
        let activeSlot = selectedHourSlot

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Hourly Step Timeline (00:00 → 23:00)")
                Spacer()
                Button("Select Z1+Z2 Only") { selectedZones = [1, 2] }
                    .font(.system(size: 11, weight: .bold)).foregroundColor(Theme.green)
                    .buttonStyle(.plain)
            }

            if let s = activeSlot {
                let selCnt = s.steps(selectedZones: selectedZones)
                let allCnt = s.steps(selectedZones: Set(0...5))
                HStack {
                    Text("\(s.label)–\(String(format: "%02d:59", s.hour))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(Theme.green)
                    Text("\(selCnt) counted (\(allCnt) all zones · Walk \(s.walkSteps) / Run \(s.runSteps))")
                        .font(.system(size: 11.5, weight: .semibold)).foregroundColor(Theme.text)
                    Spacer()
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 8))
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let step = w / 24.0
                let barW = max(4, step - 3)

                HStack(alignment: .bottom, spacing: max(1.5, step - barW)) {
                    ForEach(det.hourlySlots) { slot in
                        let allVal = slot.steps(selectedZones: Set(0...5))
                        let selVal = slot.steps(selectedZones: selectedZones)
                        let isSel = (slot.hour == activeSlot?.hour)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.muted.opacity(0.22))
                                .frame(width: barW, height: max(3, h * CGFloat(Double(allVal) / Double(maxHourSteps))))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isSel ? Theme.gold : Theme.green)
                                .frame(width: barW, height: max(2, h * CGFloat(Double(selVal) / Double(maxHourSteps))))
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let idx = min(23, max(0, Int((drag.location.x / max(1, w)) * 24.0)))
                            selectedHourSlot = det.hourlySlots[idx]
                        }
                )
            }
            .frame(height: 118)

            HStack {
                Text("00:00").font(.system(size: 10.5)).foregroundColor(Theme.muted)
                Spacer()
                Text("Green = checked zones · Grey = excluded zones · Drag to inspect hour")
                    .font(.system(size: 10)).foregroundColor(Theme.muted)
                Spacer()
                Text("23:00").font(.system(size: 10.5)).foregroundColor(Theme.muted)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-steps-hourly-card")
    }

    private func zoneCheckmarkCalculatorCard(_ det: WhoopStepsDetailModel) -> some View {
        let labels = [
            (0, "Zone 0 (Below Z1 / Casual indoor)"),
            (1, "Zone 1 (Light walk)"),
            (2, "Zone 2 (Brisk aerobic walk/jog)"),
            (3, "Zone 3 (Tempo run)"),
            (4, "Zone 4 (Threshold)"),
            (5, "Zone 5 (Max sprint / high HR)"),
        ]

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Zone 0–5 Step Calculator (Tap ✓ to Include / Exclude)")
                Spacer()
                Button(selectedZones.count == 6 ? "Z1+Z2 Only" : "All Zones") {
                    selectedZones = selectedZones.count == 6 ? [1, 2] : Set(0...5)
                }
                .font(.system(size: 11.5, weight: .semibold)).foregroundColor(Theme.green)
                .buttonStyle(.plain)
            }

            ForEach(labels, id: \.0) { z, title in
                let on = selectedZones.contains(z)
                let cnt = det.zoneTotals[z]
                Button {
                    if on { selectedZones.remove(z) } else { selectedZones.insert(z) }
                } label: {
                    HStack {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(on ? Theme.green : Theme.muted)
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(on ? Theme.text : Theme.muted)
                        Spacer()
                        Text("\(Format.grouped(Double(cnt))) steps")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(on ? Theme.green : Theme.muted)
                        Pill(text: on ? "Counted" : "Excluded", tone: on ? .green : .grey)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("whoop-steps-zone-toggle-\(z)")
            }

            Divider().background(Theme.line)
            Text("Firmware gait classes: Walk (class 1) = \(Format.grouped(Double(det.walkSteps))) · Run (class 2) = \(Format.grouped(Double(det.runSteps))) · Rejected non-gait arm motion (class 0) = \(Format.grouped(Double(det.rejectedNonGaitTicks))) raw ticks.")
                .font(.system(size: 11.5)).foregroundColor(Theme.muted)
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-steps-zone-calculator-card")
    }

    private func stepDivisorExplainerCard(_ det: WhoopStepsDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("How stepTicksPerStep Works")
            Text("Formula: Final Steps = Raw Strap Gait Ticks ÷ stepTicksPerStep.\n• 1.00 = 1 strap tick counts as 1 step (1:1 default).\n• 2.00 = 2 strap ticks count as 1 step (halves step count if wrist movement over-counts).\n• 0.50 = 1 strap tick counts as 2 steps.")
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("stepTicksPerStep divisor")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.text)
                Spacer()
                HStack(spacing: 10) {
                    Button("−") { updateDivisor(max(0.50, stepDivisor - 0.25)) }.foregroundColor(Theme.green)
                    Text(String(format: "%.2f", stepDivisor)).font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text)
                    Button("+") { updateDivisor(min(30.0, stepDivisor + 0.25)) }.foregroundColor(Theme.green)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whoop-steps-divisor-explainer-card")
    }

    private func updateDivisor(_ v: Double) {
        stepDivisor = v
        if var def = try? services.appDefaults.load() {
            def.stepTicksPerStep = v
            try? services.appDefaults.save(def)
            reload()
            session.didChange()
        }
    }
}
