import FitnessCore
import SwiftUI

/// 176pt concentric dual-hoop gauge: outer hoop = round progress, inner hoop = live BPM or interval timer.
struct ConcentricHoopView: View {
    let outerProgress: Double
    let innerProgress: Double
    let mainLabel: String
    let subLabel: String
    var innerColor: Color = Theme.green
    var size: CGFloat = 176

    var body: some View {
        let outerWidth: CGFloat = 10
        let innerWidth: CGFloat = 12
        let innerSize = size - 34

        ZStack {
            Circle().stroke(Theme.line, lineWidth: outerWidth)
                .frame(width: size, height: size)
            Circle()
                .trim(from: 0, to: max(0.01, min(1.0, outerProgress)))
                .stroke(Theme.greenSoft, style: StrokeStyle(lineWidth: outerWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)

            Circle().stroke(Theme.line, lineWidth: innerWidth)
                .frame(width: innerSize, height: innerSize)
            Circle()
                .trim(from: 0, to: max(0.01, min(1.0, innerProgress)))
                .stroke(innerColor, style: StrokeStyle(lineWidth: innerWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: innerSize, height: innerSize)

            VStack(spacing: 3) {
                Text(mainLabel)
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(Theme.text)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(subLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 26)
        }
        .frame(width: size, height: size)
    }
}

/// Compact Live WHOOP Session Hoop Strip + Pending Auto-Detected Workout Proposal Banner on WorkoutDayScreen.
struct WorkoutWhoopLiveBar: View {
    let today: ISODate
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager

    @State private var activeSession: WorkoutSessionRecord?
    @State private var completedToday: [WorkoutSessionRecord] = []
    @State private var weeklyZ2CompletedMin: Int = 0
    @State private var weeklyZ45CompletedMin: Int = 0
    @State private var liveZ2Sec: Int = 0
    @State private var liveZ45Sec: Int = 0
    @State private var recentHrSpark: [Double] = []
    @State private var zones = WhoopTrainingZones(source: "tanaka", boundsBpm: [100, 120, 140, 160, 175], maxHrBpm: 190)
    @State private var zoneThrottle = WorkoutZoneNotificationThrottle(minIntervalSec: 30)
    @State private var pendingProposals: [WhoopActivityProposal] = []
    @State private var showingHiit = false
    @State private var editingSession: WorkoutSessionRecord?
    @State private var hiitSummaryBadge: String?
    @State private var elapsedTick = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            liveStrip
            zoneTargetStrip
            if !completedToday.isEmpty {
                completedSessionsCard
            }
            ForEach(pendingProposals) { prop in
                proposalCard(prop)
            }
        }
        .task(id: "\(today.string)-\(session.revision)") { reload() }
        .onReceive(timer) { _ in
            if activeSession != nil { elapsedTick += 1 }
            if let bpm = whoop.liveHrBpm, bpm > 0 {
                recentHrSpark.append(Double(bpm))
                if recentHrSpark.count > 20 { recentHrSpark.removeFirst() }
                if activeSession != nil {
                    let z = WorkoutSessionService.zoneIndex(forBpm: bpm, zones: zones)
                    if z == 2 { liveZ2Sec += 1 }
                    if z >= 4 { liveZ45Sec += 1 }
                    if let ev = zoneThrottle.onBpmSample(tsSec: Int64(Date().timeIntervalSince1970), bpm: bpm, zones: zones) {
                        LiveWorkoutNotificationDispatcher.shared.postZoneEvent(ev)
                    }
                }
            }
        }
        .sheet(isPresented: $showingHiit) {
            WhoopHiitSheet(zones: zones, hiitSummaryBadge: $hiitSummaryBadge)
                .environmentObject(services)
                .environmentObject(whoop)
                .preferredColorScheme(.dark)
        }
        .sheet(item: $editingSession, onDismiss: {
            reload()
            session.didChange()
        }) { rec in
            WorkoutSessionEditorSheet(sessionRecord: rec, zones: zones)
                .environmentObject(services)
                .environmentObject(whoop)
                .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var liveStrip: some View {
        if let active = activeSession {
            let nowSec = Int64(Date().timeIntervalSince1970)
            let elapsed = max(0, Int(nowSec - active.startTs)) + (elapsedTick * 0)
            let bpm = whoop.liveHrBpm ?? Int(recentHrSpark.last ?? 0)
            let zIdx = bpm > 0 ? WorkoutSessionService.zoneIndex(forBpm: bpm, zones: zones) : 0
            let zProg = bpm > 0 ? min(1.0, max(0.1, Double(bpm) / Double(max(150, zones.maxHrBpm)))) : 0.15

            HStack(spacing: 12) {
                RingView(
                    progress: zProg,
                    size: 54,
                    lineWidth: 5,
                    label: bpm > 0 ? "\(bpm)" : "ON",
                    subLabel: bpm > 0 ? "Z\(zIdx)" : "0x03",
                    color: zIdx >= 4 ? Theme.gold : Theme.green
                )

                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Live 0x03 · \(formatElapsed(elapsed))\(hiitSummaryBadge.map { " · \($0)" } ?? "")")
                    SparklineView(values: recentHrSpark.count >= 2 ? recentHrSpark : [118, 124, 130, 128], width: 115, height: 18)
                }
                Spacer(minLength: 4)

                VStack(spacing: 5) {
                    Button("HIIT") { showingHiit = true }
                        .buttonStyle(CompactButtonStyle(ghost: true))
                        .accessibilityIdentifier("workout-open-hiit-button")
                    Button("Finish") { finishActiveSession(active) }
                        .buttonStyle(CompactButtonStyle())
                        .accessibilityIdentifier("workout-finish-session-button")
                }
            }
            .card(padding: 12, highlighted: true)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workout-live-session-bar")
        } else {
            HStack(spacing: 10) {
                let bpm = whoop.liveHrBpm
                RingView(
                    progress: bpm != nil ? 0.65 : 0.12,
                    size: 44,
                    lineWidth: 4.5,
                    label: bpm.map(String.init) ?? "HR",
                    color: Theme.green
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("WHOOP Session & HIIT")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                    Text(hiitSummaryBadge ?? "Live 0x03 zones, wrist haptics & set BPM")
                        .font(.system(size: 11.5)).foregroundColor(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button("HIIT") { showingHiit = true }
                    .buttonStyle(CompactButtonStyle(ghost: true))
                    .accessibilityIdentifier("workout-open-hiit-button")
                Button("Start") { startLiveSession() }
                    .buttonStyle(CompactButtonStyle())
                    .accessibilityIdentifier("workout-start-session-button")
            }
            .card(padding: 11)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workout-idle-session-bar")
        }
    }

    private func proposalCard(_ prop: WhoopActivityProposal) -> some View {
        let durMin = max(1, Int((prop.endTs - prop.startTs) / 60))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("Detected workout · reviewable")
                Spacer()
                Pill(text: "\(durMin) min", tone: .amber)
            }
            HStack {
                Text("\(prop.dayId) · \(hm(prop.startTs))–\(hm(prop.endTs))")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.text)
                Spacer()
                Button("Accept") { acceptProposal(prop) }
                    .buttonStyle(CompactButtonStyle())
                Button("✕") { dismissProposal(prop) }
                    .buttonStyle(CompactButtonStyle(ghost: true))
            }
        }
        .card(padding: 12, highlighted: true)
        .accessibilityIdentifier("workout-auto-proposal-\(prop.id)")
    }

    private var zoneTargetStrip: some View {
        let z2Done = weeklyZ2CompletedMin + (liveZ2Sec / 60)
        let z2Left = max(0, 150 - z2Done)
        let z45Done = weeklyZ45CompletedMin + (liveZ45Sec / 60)
        let z45Left = max(0, 50 - z45Done)

        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                RingView(
                    progress: min(1.0, max(0.06, Double(z2Done) / 150.0)),
                    size: 36,
                    lineWidth: 3.5,
                    label: "\(z2Done)m",
                    color: Theme.green
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Zone 2 Target").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text)
                    Text("\(z2Done)/150m · \(z2Left)m left").font(.system(size: 10.5)).foregroundColor(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 8) {
                RingView(
                    progress: min(1.0, max(0.06, Double(z45Done) / 50.0)),
                    size: 36,
                    lineWidth: 3.5,
                    label: "\(z45Done)m",
                    color: Theme.gold
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Zone 4–5 Target").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text)
                    Text("\(z45Done)/50m · \(z45Left)m left").font(.system(size: 10.5)).foregroundColor(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-zone-progress-strip")
    }

    private var completedSessionsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Logged sessions today (\(completedToday.count)) · tap for Timeline × HR")
            ForEach(completedToday) { rec in
                Button {
                    editingSession = rec
                } label: {
                    HStack {
                        Text("\(rec.sport) · \(hm(rec.startTs))–\(rec.endTs.map(hm) ?? "now")")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                        Spacer()
                        if let st = rec.strain {
                            Pill(text: String(format: "Strain %.1f", st), tone: .gold)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(Theme.muted)
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workout-completed-session-\(rec.id)")
            }
        }
        .card(padding: 11)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-completed-sessions-list")
    }

    private func reload() {
        let allOnDay = (try? services.workoutSessions.sessions(on: today)) ?? []
        activeSession = allOnDay.first(where: { $0.endTs == nil })
        completedToday = allOnDay.filter { $0.endTs != nil }

        let weekStart = today.adding(days: -6)
        let weekDone = ((try? services.workoutSessions.sessions()) ?? []).filter {
            $0.performedOn >= weekStart && $0.performedOn <= today && $0.endTs != nil
        }
        var z2Min = weekDone.reduce(0) { $0 + ($1.zoneSeconds[2] / 60) }
        let z45Min = weekDone.reduce(0) { $0 + (($1.zoneSeconds[4] + $1.zoneSeconds[5]) / 60) }

        if let snap = try? WhoopDashboardPresenter.build(whoopDb: whoop.db, fitnessDb: services.db, on: today) {
            zones = snap.zones
            pendingProposals = snap.pendingWorkoutProposals
            if z2Min == 0, let db = whoop.db {
                let active7d = (try? db.query(
                    "SELECT SUM(value) AS s FROM metric_series WHERE key = 'active_min' AND date BETWEEN ? AND ?",
                    [.text(weekStart.string), .text(today.string)]
                ).first?.optionalDouble("s")) ?? 0
                z2Min = Int((active7d * 0.65).rounded())
            }
        }
        weeklyZ2CompletedMin = z2Min
        weeklyZ45CompletedMin = z45Min
    }

    private func startLiveSession() {
        let nowSec = Int64(Date().timeIntervalSince1970)
        liveZ2Sec = 0
        liveZ45Sec = 0
        LiveWorkoutNotificationDispatcher.shared.requestAuthorizationIfNeeded()
        if let res = try? services.workoutSessions.startSession(
            performedOn: today, kind: .lifting, sport: "Strength", startTs: nowSec, profile: whoop.activeBandProfile
        ) {
            _ = whoop.sendRawCommandFrame(res.toggleHrFrame)
            whoop.toggleLiveHeartRate(true)
            activeSession = res.session
        }
    }

    private func finishActiveSession(_ rec: WorkoutSessionRecord) {
        let nowSec = Int64(Date().timeIntervalSince1970)
        let hrSamples = loadHrSamples(from: rec.startTs, to: nowSec)
        if let res = try? services.workoutSessions.finishSession(
            id: rec.id, endTs: nowSec, hrSamples: hrSamples, zones: zones, rhr: 52.0, isFemale: false, profile: whoop.activeBandProfile
        ) {
            _ = whoop.sendRawCommandFrame(res.toggleHrFrame)
            whoop.toggleLiveHeartRate(false)
            activeSession = nil
            reload()
            editingSession = res.session
        }
    }

    private func acceptProposal(_ prop: WhoopActivityProposal) {
        guard let db = whoop.db else { return }
        let store = WhoopAnalyticsStore(db)
        if let created = try? services.workoutSessions.acceptWorkoutProposal(
            proposalId: prop.id, analyticsStore: store, kind: .easyCardio, sport: "Detected Cardio"
        ) {
            reload()
            editingSession = created
        }
    }

    private func dismissProposal(_ prop: WhoopActivityProposal) {
        guard let db = whoop.db else { return }
        try? WhoopAnalyticsStore(db).updateProposalStatus(id: prop.id, status: "discarded")
        reload()
    }

    private func loadHrSamples(from startTs: Int64, to endTs: Int64) -> [(tsSec: Int64, bpm: Int)] {
        var samples: [(tsSec: Int64, bpm: Int)] = []
        if let db = whoop.db {
            let rows = (try? db.query(
                "SELECT rec_ts, hr FROM decoded_onehz WHERE rec_ts BETWEEN ? AND ? AND hr IS NOT NULL ORDER BY rec_ts ASC",
                [.int(startTs), .int(endTs)]
            )) ?? []
            samples = rows.compactMap { r in
                guard let ts = r.optionalInt64("rec_ts") else { return nil }
                let b = WhoopSubstrateGates.plausibleHrOrZero(r.optionalInt("hr"))
                return b > 0 ? (ts, b) : nil
            }
        }
        for live in whoop.liveSessionHrSamples where live.tsSec >= startTs && live.tsSec <= endTs {
            samples.append(live)
        }
        samples.sort { $0.tsSec < $1.tsSec }
        return samples
    }

    private func formatElapsed(_ sec: Int) -> String {
        String(format: "%02d:%02d", sec / 60, sec % 60)
    }

    private func hm(_ epochSec: Int64) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(epochSec)))
    }
}

// MARK: - Concentric Dual-Hoop HIIT Sheet (`0x13` / `0x4F` Strap Haptics)

struct WhoopHiitSheet: View {
    let zones: WhoopTrainingZones
    @Binding var hiitSummaryBadge: String?
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager
    @Environment(\.dismiss) private var dismiss

    @State private var mode: HiitTriggerMode = .hrThreshold
    @State private var workSec: Int = 240
    @State private var restSec: Int = 180
    @State private var rounds: Int = 4
    @State private var highBpm: Int = 172
    @State private var lowBpm: Int = 130
    @State private var presets: [HiitPreset] = []
    @State private var engine: DualModeHiitEngine?
    @State private var nowSec: Int64 = Int64(Date().timeIntervalSince1970)

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            SectionLabel("WHOOP Haptics · Opcode \(whoop.activeBandProfile.isGen5 ? "0x13" : "0x4F")")
                            Text("Dual-Mode HIIT").font(.system(size: 20, weight: .bold)).foregroundColor(Theme.text)
                        }
                        Spacer()
                        let curRound = engine?.currentRound ?? 1
                        Pill(text: "Round \(curRound) / \(rounds)", tone: .green)
                    }

                    modeSwitcher
                    presetBar
                    concentricDial
                    parameterSteppers

                    HStack(spacing: 10) {
                        if engine == nil {
                            Button("Start HIIT") { startEngine() }
                                .buttonStyle(PrimaryButtonStyle())
                                .accessibilityIdentifier("hiit-start-button")
                        } else {
                            Button("Keep in top bar") {
                                updateBadge()
                                dismiss()
                            }
                            .buttonStyle(PrimaryButtonStyle(ghost: true))
                            Button("End HIIT") {
                                engine = nil
                                hiitSummaryBadge = nil
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("HIIT Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        updateBadge()
                        dismiss()
                    }
                    .accessibilityIdentifier("hiit-done-button")
                }
            }
            .onAppear(perform: loadPresets)
            .onReceive(ticker) { d in
                nowSec = Int64(d.timeIntervalSince1970)
                guard var eng = engine else { return }
                let frames: [[UInt8]]
                if eng.preset.mode == .time {
                    frames = eng.tick(nowSec: nowSec)
                } else if let bpm = whoop.liveHrBpm {
                    frames = eng.ingestHeartRate(tsSec: nowSec, bpm: bpm)
                } else {
                    frames = []
                }
                for f in frames { _ = whoop.sendRawCommandFrame(f) }
                engine = eng
                updateBadge()
            }
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            modeOption("HR Threshold", .hrThreshold, id: "hiit-mode-hr")
            modeOption("Time Intervals", .time, id: "hiit-mode-time")
        }
        .padding(3)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func modeOption(_ title: String, _ target: HiitTriggerMode, id: String) -> some View {
        let on = (mode == target)
        return Button {
            mode = target
            engine = nil
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(on ? Theme.onGreen : Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(on ? Theme.green : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var presetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(presets) { p in
                    Button(p.name) {
                        mode = p.mode
                        workSec = p.workSec
                        restSec = p.restSec
                        rounds = p.rounds
                        highBpm = p.highBpm
                        lowBpm = p.lowBpm
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Theme.card)
                    .foregroundColor(Theme.green)
                    .overlay(Capsule().stroke(Theme.line))
                    .clipShape(Capsule())
                }
                Button("+ Save preset") { saveCurrentPreset() }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Theme.card2)
                    .foregroundColor(Theme.muted)
                    .clipShape(Capsule())
            }
        }
    }

    private var concentricDial: some View {
        let outerProg = Double(engine?.currentRound ?? 1) / Double(max(1, rounds))
        let bpm = whoop.liveHrBpm ?? 0

        if mode == .hrThreshold {
            let phase = engine?.phase ?? .workOrPushUpper
            let innerProg = bpm > 0 ? Double(bpm) / Double(max(1, highBpm)) : 0.75
            let mainTxt = bpm > 0 ? "\(bpm)" : "\(highBpm)"
            let subTxt = phase == .workOrPushUpper ? "push ≥\(highBpm) bpm" : "recover ≤\(lowBpm) bpm"
            return VStack(spacing: 8) {
                ConcentricHoopView(
                    outerProgress: outerProg,
                    innerProgress: innerProg,
                    mainLabel: mainTxt,
                    subLabel: subTxt,
                    innerColor: phase == .workOrPushUpper ? Theme.amber : Theme.green
                )
                Text("Fires wrist haptic when HR crosses ≥\(highBpm) or drops ≤\(lowBpm) bpm (10s hysteresis).")
                    .font(.system(size: 11.5)).foregroundColor(Theme.muted).multilineTextAlignment(.center)
            }
        } else {
            let phase = engine?.phase ?? .workOrPushUpper
            let targetDur = phase == .workOrPushUpper ? workSec : restSec
            let elapsed = engine.map { max(0, Int(nowSec - $0.phaseStartedSec)) } ?? 0
            let rem = max(0, targetDur - elapsed)
            let innerProg = Double(rem) / Double(max(1, targetDur))
            let mainTxt = String(format: "%02d:%02d", rem / 60, rem % 60)
            let subTxt = phase == .workOrPushUpper ? "WORK · \(bpm > 0 ? "\(bpm) bpm" : "go")" : "REST · recover"
            return VStack(spacing: 8) {
                ConcentricHoopView(
                    outerProgress: outerProg,
                    innerProgress: innerProg,
                    mainLabel: mainTxt,
                    subLabel: subTxt,
                    innerColor: phase == .workOrPushUpper ? Theme.green : Theme.amber
                )
                Text("Fires wrist haptic at the end of every work and rest interval.")
                    .font(.system(size: 11.5)).foregroundColor(Theme.muted).multilineTextAlignment(.center)
            }
        }
    }

    private var parameterSteppers: some View {
        VStack(spacing: 10) {
            if mode == .hrThreshold {
                HStack(spacing: 10) {
                    stepperCard("Upper Push", "\(highBpm) bpm",
                                minus: { highBpm = max(lowBpm + 10, highBpm - 2) },
                                plus: { highBpm = min(220, highBpm + 2) })
                    stepperCard("Recover To", "\(lowBpm) bpm",
                                minus: { lowBpm = max(60, lowBpm - 2) },
                                plus: { lowBpm = min(highBpm - 10, lowBpm + 2) })
                }
            } else {
                HStack(spacing: 10) {
                    stepperCard("Work", "\(workSec)s",
                                minus: { workSec = max(10, workSec - 10) },
                                plus: { workSec = min(1200, workSec + 10) })
                    stepperCard("Rest", "\(restSec)s",
                                minus: { restSec = max(10, restSec - 10) },
                                plus: { restSec = min(1200, restSec + 10) })
                }
            }
            stepperCard("Rounds", "\(rounds) rounds",
                        minus: { rounds = max(1, rounds - 1) },
                        plus: { rounds = min(30, rounds + 1) })
        }
    }

    private func stepperCard(_ title: String, _ value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            SectionLabel(title)
            HStack {
                Button("−", action: minus)
                    .font(.system(size: 20, weight: .bold)).foregroundColor(Theme.green)
                    .frame(width: 36, height: 36).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
                Spacer()
                Text(value).font(.system(size: 18, weight: .heavy)).foregroundColor(Theme.text)
                Spacer()
                Button("+", action: plus)
                    .font(.system(size: 20, weight: .bold)).foregroundColor(Theme.green)
                    .frame(width: 36, height: 36).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(10)
        .background(Theme.card2)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func loadPresets() {
        var loaded = (try? services.appDefaults.hiitPresets()) ?? []
        if loaded.isEmpty {
            let defaults: [HiitPreset] = [
                HiitPreset(id: "vo2-hr", name: "Peak 172 / Rec 130", mode: .hrThreshold, workSec: 60, restSec: 60, rounds: 4, highBpm: 172, lowBpm: 130, position: 1),
                HiitPreset(id: "norwegian-4x4", name: "Norwegian 4×4", mode: .time, workSec: 240, restSec: 180, rounds: 4, highBpm: 178, lowBpm: 132, position: 2),
                HiitPreset(id: "sprints-8x20", name: "Strides 8×20s", mode: .time, workSec: 20, restSec: 30, rounds: 8, highBpm: 170, lowBpm: 125, position: 3),
            ]
            for p in defaults { try? services.appDefaults.upsertHiitPreset(p) }
            loaded = defaults
        }
        presets = loaded
    }

    private func saveCurrentPreset() {
        let name = mode == .hrThreshold ? "HR \(highBpm)/\(lowBpm)" : "\(workSec)s/\(restSec)s ×\(rounds)"
        let p = HiitPreset(id: UUID().uuidString, name: name, mode: mode, workSec: workSec, restSec: restSec,
                           rounds: rounds, highBpm: highBpm, lowBpm: lowBpm, position: presets.count + 1)
        try? services.appDefaults.upsertHiitPreset(p)
        presets = (try? services.appDefaults.hiitPresets()) ?? presets
    }

    private func startEngine() {
        whoop.toggleLiveHeartRate(true)
        let preset = HiitPreset(id: "live", name: "Live", mode: mode, workSec: workSec, restSec: restSec,
                                rounds: rounds, highBpm: highBpm, lowBpm: lowBpm)
        engine = DualModeHiitEngine(preset: preset, profile: whoop.activeBandProfile, startSec: Int64(Date().timeIntervalSince1970))
        updateBadge()
    }

    private func updateBadge() {
        guard let eng = engine, eng.phase != .completed else {
            hiitSummaryBadge = nil
            return
        }
        hiitSummaryBadge = "HIIT R\(eng.currentRound)/\(eng.preset.rounds)"
    }
}

// MARK: - Post-Workout Session & Late-Stop Trim Sheet

struct WorkoutSessionEditorSheet: View {
    let sessionRecord: WorkoutSessionRecord
    let zones: WhoopTrainingZones
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager
    @Environment(\.dismiss) private var dismiss

    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var kind: WhoopCardioSessionKind = .lifting
    @State private var sport = "Strength"
    @State private var longExempt = false
    @State private var notes = ""
    @State private var suggestedTrimTs: Int64?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        let st = sessionRecord.strain ?? 0
                        RingView(
                            progress: min(1.0, max(0.05, st / 21.0)),
                            size: 54,
                            lineWidth: 5,
                            label: String(format: "%.1f", st),
                            subLabel: "of 21",
                            color: Theme.gold
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Session review & trim")
                                .font(.system(size: 16, weight: .bold))
                            Text("Editing start or end recomputes Avg HR, Zones, and Strain in place.")
                                .font(.system(size: 12)).foregroundColor(Theme.muted)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let trimTs = suggestedTrimTs, Int64(endDate.timeIntervalSince1970) > trimTs + 300 {
                    Section("Idle tail spotted after last logged set") {
                        Button("Trim end time to \(hm(trimTs))") {
                            endDate = Date(timeIntervalSince1970: TimeInterval(trimTs))
                        }
                        .foregroundColor(Theme.green)
                    }
                }

                Section("Timeline × Heart Rate & Exercise Pins (✓)") {
                    let sTs = Int64(startDate.timeIntervalSince1970)
                    let eTs = max(sTs + 60, Int64(endDate.timeIntervalSince1970))
                    let samples = loadHrSamples(from: sTs, to: eTs)
                    let sets = (try? services.logSets.sets(on: sessionRecord.performedOn)) ?? []
                    let pins = WorkoutSessionService.exerciseTimelinePins(sets: sets, hrSamples: samples, startTs: sTs, endTs: eTs)
                    let exSummaries = WorkoutSessionService.correlateExerciseHeartRates(sets: sets, hrSamples: samples, zones: zones)

                    WorkoutTimelineHrChartView(startTs: sTs, endTs: eTs, samples: samples, pins: pins)
                        .accessibilityIdentifier("workout-timeline-hr-chart")

                    if !pins.isEmpty {
                        ForEach(pins.prefix(8)) { pin in
                            HStack {
                                Text("✓ \(pin.exerciseName)")
                                    .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.green)
                                Text(pin.setSummary)
                                    .font(.system(size: 12)).foregroundColor(Theme.muted)
                                Spacer()
                                Text("\(pin.bpmAtPin) bpm @ \(hm(pin.tsSec))")
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(Theme.gold)
                            }
                        }
                    } else if !exSummaries.isEmpty {
                        ForEach(exSummaries) { ex in
                            HStack {
                                Text("✓ \(ex.exerciseName)").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.green)
                                Spacer()
                                Text("Avg \(ex.avgHr ?? 0) · Peak \(ex.peakHr ?? 0) bpm")
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(Theme.gold)
                            }
                        }
                    }
                }

                Section("Timing & modality (late-stop trim)") {
                    DatePicker("Start time", selection: $startDate)
                    DatePicker("End time", selection: $endDate)
                    HStack(spacing: 8) {
                        Text("Quick trim:")
                            .font(.system(size: 12)).foregroundColor(Theme.muted)
                        ForEach([5, 10, 15], id: \.self) { mins in
                            Button("−\(mins)m") {
                                let candidate = endDate.addingTimeInterval(TimeInterval(-mins * 60))
                                if candidate > startDate.addingTimeInterval(60) {
                                    endDate = candidate
                                }
                            }
                            .buttonStyle(CompactButtonStyle(ghost: true))
                        }
                    }
                    Picker("Kind", selection: $kind) {
                        Text("Lifting").tag(WhoopCardioSessionKind.lifting)
                        Text("Easy Cardio (Z1–2)").tag(WhoopCardioSessionKind.easyCardio)
                        Text("Intervals (Z4–5)").tag(WhoopCardioSessionKind.intervals)
                        Text("Tempo / Threshold").tag(WhoopCardioSessionKind.tempo)
                        Text("Long Endurance (1.5–3h)").tag(WhoopCardioSessionKind.longEndurance)
                    }
                    TextField("Sport label", text: $sport)
                    Toggle("Long run gray-zone exempt (Max HRV mode)", isOn: $longExempt)
                    TextField("Notes (optional)", text: $notes)
                }

                Section {
                    Button("Delete workout session", role: .destructive) {
                        try? services.workoutSessions.deleteSession(id: sessionRecord.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Review Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("workout-save-session-edits")
                }
            }
            .onAppear {
                startDate = Date(timeIntervalSince1970: TimeInterval(sessionRecord.startTs))
                endDate = Date(timeIntervalSince1970: TimeInterval(sessionRecord.endTs ?? Int64(Date().timeIntervalSince1970)))
                kind = sessionRecord.kind
                sport = sessionRecord.sport
                longExempt = sessionRecord.longEnduranceExempt
                notes = sessionRecord.notes ?? ""
                if let lastSetTs = (try? services.logSets.sets(on: sessionRecord.performedOn))?.compactMap(\.loggedAtTs).max() {
                    suggestedTrimTs = lastSetTs + 120
                }
            }
            .errorAlert($errorMessage)
        }
    }

    private func save() {
        do {
            let sTs = Int64(startDate.timeIntervalSince1970)
            let eTs = Int64(endDate.timeIntervalSince1970)
            let hrSamples = loadHrSamples(from: sTs, to: eTs)
            _ = try services.workoutSessions.updateSession(
                id: sessionRecord.id,
                performedOn: sessionRecord.performedOn,
                kind: kind,
                sport: sport,
                startTs: sTs,
                endTs: eTs,
                longEnduranceExempt: longExempt,
                notes: notes.isEmpty ? nil : notes,
                hrSamples: hrSamples,
                zones: zones,
                rhr: 52.0,
                isFemale: false
            )
            dismiss()
        } catch {
            errorMessage = (error as? ValidationError)?.message ?? error.localizedDescription
        }
    }

    private func loadHrSamples(from startTs: Int64, to endTs: Int64) -> [(tsSec: Int64, bpm: Int)] {
        var samples: [(tsSec: Int64, bpm: Int)] = []
        if let db = whoop.db {
            let rows = (try? db.query(
                "SELECT rec_ts, hr FROM decoded_onehz WHERE rec_ts BETWEEN ? AND ? AND hr IS NOT NULL ORDER BY rec_ts ASC",
                [.int(startTs), .int(endTs)]
            )) ?? []
            samples = rows.compactMap { r in
                guard let ts = r.optionalInt64("rec_ts") else { return nil }
                let b = WhoopSubstrateGates.plausibleHrOrZero(r.optionalInt("hr"))
                return b > 0 ? (ts, b) : nil
            }
        }
        for live in whoop.liveSessionHrSamples where live.tsSec >= startTs && live.tsSec <= endTs {
            samples.append(live)
        }
        samples.sort { $0.tsSec < $1.tsSec }
        return samples
    }

    private func hm(_ epochSec: Int64) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(epochSec)))
    }
}

/// Custom SwiftUI Timeline × Heart Rate Line Chart with overlaid `✓` Exercise Check-Mark Pins.
struct WorkoutTimelineHrChartView: View {
    let startTs: Int64
    let endTs: Int64
    let samples: [(tsSec: Int64, bpm: Int)]
    let pins: [WorkoutExerciseTimelinePin]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if samples.count >= 2 {
                let bpms = samples.map(\.bpm)
                let loBpm = Double(max(45, (bpms.min() ?? 90) - 8))
                let hiBpm = Double(min(220, (bpms.max() ?? 165) + 8))
                let spanSec = Double(max(60, endTs - startTs))

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    ZStack(alignment: .topLeading) {
                        // Horizontal reference lines
                        ForEach([0.25, 0.5, 0.75], id: \.self) { frac in
                            Path { p in
                                let y = h * frac
                                p.move(to: CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: w, y: y))
                            }
                            .stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }

                        // HR Line Path
                        Path { path in
                            let step = max(1, samples.count / 120)
                            var started = false
                            for idx in stride(from: 0, to: samples.count, by: step) {
                                let pt = samples[idx]
                                let x = min(w, max(0, CGFloat(Double(pt.tsSec - startTs) / spanSec) * w))
                                let yFrac = (Double(pt.bpm) - loBpm) / max(10.0, hiBpm - loBpm)
                                let y = h - CGFloat(min(1.0, max(0.0, yFrac))) * h
                                if !started {
                                    path.move(to: CGPoint(x: x, y: y))
                                    started = true
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(Theme.green, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                        // Overlaid ✓ Exercise Check-Mark Pins
                        ForEach(pins) { pin in
                            let x = min(w - 10, max(10, CGFloat(Double(pin.tsSec - startTs) / spanSec) * w))
                            let yFrac = (Double(pin.bpmAtPin) - loBpm) / max(10.0, hiBpm - loBpm)
                            let y = min(h - 10, max(10, h - CGFloat(min(1.0, max(0.0, yFrac))) * h))

                            ZStack {
                                Circle()
                                    .fill(Theme.gold)
                                    .frame(width: 18, height: 18)
                                Text("✓")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(Color.black)
                            }
                            .position(x: x, y: y)
                        }
                    }
                }
                .frame(height: 145)
                .padding(.vertical, 4)

                HStack {
                    Text("Min \(bpms.min() ?? 0) bpm").font(.system(size: 11)).foregroundColor(Theme.muted)
                    Spacer()
                    Text("\(pins.count) exercise set pin(s) ✓").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.gold)
                    Spacer()
                    Text("Peak \(bpms.max() ?? 0) bpm").font(.system(size: 11)).foregroundColor(Theme.muted)
                }
            } else {
                Text("Stream 0x28 live HR or sync 1 Hz strap data across this workout window to plot the HR timeline and overlaid ✓ exercise pins.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
                    .padding(.vertical, 4)
            }
        }
    }
}
