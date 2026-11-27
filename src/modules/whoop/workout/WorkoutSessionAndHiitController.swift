import Foundation

public struct WorkoutSessionRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public var performedOn: ISODate
    public var kind: WhoopCardioSessionKind
    public var sport: String
    public var startTs: Int64
    public var endTs: Int64?
    public var activeKcal: Double?
    public var avgHr: Int?
    public var maxHr: Int?
    public var strain: Double?
    public var zoneSeconds: [Int] // [zone0, zone1, zone2, zone3, zone4, zone5]
    public var longEnduranceExempt: Bool
    public var notes: String?
}

public struct ExerciseHeartRateSummary: Identifiable, Equatable, Sendable {
    public var id: Int { exerciseId }
    public let exerciseId: Int
    public let exerciseName: String
    public let windowStartTs: Int64
    public let windowEndTs: Int64
    public let setCount: Int
    public let avgHr: Int?
    public let peakHr: Int?
    public let zoneSeconds: [Int]
}

public struct WorkoutExerciseTimelinePin: Identifiable, Equatable, Sendable {
    public let id: Int
    public let exerciseId: Int
    public let exerciseName: String
    public let tsSec: Int64
    public let setSummary: String
    public let bpmAtPin: Int
}

public struct WorkoutZoneNotificationEvent: Equatable, Sendable {
    public let tsSec: Int64
    public let zoneIndex: Int // 0..5
    public let bpm: Int
    public let title: String
    public let body: String
}

/// LiveContainer-safe local notification throttle (no ActivityKit / Live Activities entitlement required).
public struct WorkoutZoneNotificationThrottle: Equatable, Sendable {
    public let minIntervalSec: Int64
    public private(set) var lastSentSec: Int64?
    public private(set) var lastZone: Int?

    public init(minIntervalSec: Int64 = 30) {
        self.minIntervalSec = max(5, minIntervalSec)
    }

    public mutating func onBpmSample(tsSec: Int64, bpm: Int, zones: WhoopTrainingZones) -> WorkoutZoneNotificationEvent? {
        guard bpm >= WhoopCoreConstants.minPlausibleHr && bpm <= WhoopCoreConstants.maxPlausibleHr else {
            return nil
        }
        let z = WorkoutSessionService.zoneIndex(forBpm: bpm, zones: zones)
        if let lz = lastZone, lz == z { return nil }
        if let ls = lastSentSec, (tsSec - ls) < minIntervalSec { return nil }

        lastZone = z
        lastSentSec = tsSec
        return WorkoutZoneNotificationEvent(
            tsSec: tsSec,
            zoneIndex: z,
            bpm: bpm,
            title: "Zone \(z) · \(bpm) BPM",
            body: z == 0 ? "Below Zone 1 (\(bpm) bpm)" : "Entered Heart Rate Zone \(z) (\(bpm) bpm)"
        )
    }
}

/// Persistent Live Workout Session Service (`0x03` realtime HR toggle, editable `start_ts`/`end_ts`, per-exercise set HR correlation).
public final class WorkoutSessionService {
    private let fitnessDb: Database

    public init(fitnessDb: Database) {
        self.fitnessDb = fitnessDb
    }

    public static func zoneIndex(forBpm bpm: Int, zones: WhoopTrainingZones) -> Int {
        guard zones.boundsBpm.count == 5 else { return 0 }
        if bpm < zones.boundsBpm[0] { return 0 }
        if bpm < zones.boundsBpm[1] { return 1 }
        if bpm < zones.boundsBpm[2] { return 2 }
        if bpm < zones.boundsBpm[3] { return 3 }
        if bpm < zones.boundsBpm[4] { return 4 }
        return 5
    }

    @discardableResult
    public func startSession(
        id: String = UUID().uuidString,
        performedOn: ISODate,
        kind: WhoopCardioSessionKind = .lifting,
        sport: String = "Strength",
        startTs: Int64,
        notes: String? = nil,
        seq: UInt8 = 1,
        profile: WhoopBandProfile = .gen5
    ) throws -> (session: WorkoutSessionRecord, toggleHrFrame: [UInt8]) {
        try fitnessDb.execute("""
            INSERT INTO workout_sessions (id, performed_on, kind, sport, start_ts, notes)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                performed_on = excluded.performed_on,
                kind = excluded.kind,
                sport = excluded.sport,
                start_ts = excluded.start_ts,
                notes = excluded.notes
            """, [.text(id), .text(performedOn.string), .text(kind.rawValue), .text(sport), .int(startTs), .optional(notes)])
        let rec = try requireSession(id: id)
        let frame = WhoopCommands.cmdToggleRealtimeHr(seq: seq, on: true, profile: profile)
        return (rec, frame)
    }

    @discardableResult
    public func finishSession(
        id: String,
        endTs: Int64,
        hrSamples: [(tsSec: Int64, bpm: Int)] = [],
        zones: WhoopTrainingZones? = nil,
        rhr: Double? = nil,
        isFemale: Bool = false,
        seq: UInt8 = 2,
        profile: WhoopBandProfile = .gen5
    ) throws -> (session: WorkoutSessionRecord, toggleHrFrame: [UInt8]) {
        let existing = try requireSession(id: id)
        guard endTs >= existing.startTs else {
            throw ValidationError("Workout end time cannot precede start time")
        }
        let updated = try updateSession(
            id: id,
            performedOn: existing.performedOn,
            kind: existing.kind,
            sport: existing.sport,
            startTs: existing.startTs,
            endTs: endTs,
            longEnduranceExempt: existing.longEnduranceExempt,
            notes: existing.notes,
            hrSamples: hrSamples,
            zones: zones,
            rhr: rhr,
            isFemale: isFemale
        )
        let frame = WhoopCommands.cmdToggleRealtimeHr(seq: seq, on: false, profile: profile)
        return (updated, frame)
    }

    /// Full in-place edit of any workout session (including trimming `endTs` when the user forgot to stop the session!).
    @discardableResult
    public func updateSession(
        id: String,
        performedOn: ISODate,
        kind: WhoopCardioSessionKind,
        sport: String,
        startTs: Int64,
        endTs: Int64?,
        longEnduranceExempt: Bool = false,
        notes: String? = nil,
        hrSamples: [(tsSec: Int64, bpm: Int)] = [],
        zones: WhoopTrainingZones? = nil,
        rhr: Double? = nil,
        isFemale: Bool = false
    ) throws -> WorkoutSessionRecord {
        if let endTs, endTs < startTs {
            throw ValidationError("Workout end time cannot precede start time")
        }
        _ = try requireSession(id: id)

        var avgHr: Int?
        var maxHrVal: Int?
        var zSecs = [0, 0, 0, 0, 0, 0]
        var strainVal: Double?

        if let endTs, !hrSamples.isEmpty {
            let sliced = hrSamples.filter {
                $0.tsSec >= startTs && $0.tsSec <= endTs
                    && WhoopSubstrateGates.plausibleHrOrZero($0.bpm) > 0
            }
            if !sliced.isEmpty {
                let sum = sliced.reduce(0) { $0 + $1.bpm }
                avgHr = Int((Double(sum) / Double(sliced.count)).rounded())
                maxHrVal = sliced.map(\.bpm).max()
                if let zones {
                    for s in sliced {
                        let z = Self.zoneIndex(forBpm: s.bpm, zones: zones)
                        zSecs[z] += 1
                    }
                    if let rhr, Double(zones.maxHrBpm) > rhr + 10.0 {
                        // Minute-mean Banister session TRIMP -> 0..21 Strain
                        var byMin: [Int64: [Int]] = [:]
                        for s in sliced { byMin[s.tsSec / 60, default: []].append(s.bpm) }
                        var trimp = 0.0
                        for (_, bpms) in byMin {
                            let mBpm = Double(bpms.reduce(0, +)) / Double(bpms.count)
                            let x = min(1.0, max(0.0, (mBpm - rhr) / (Double(zones.maxHrBpm) - rhr)))
                            trimp += x * WhoopReadinessAndStrainEngine.banisterY(x, isFemale: isFemale)
                        }
                        strainVal = WhoopReadinessAndStrainEngine.strainFromNetTrimp(trimp)
                    }
                }
            }
        }

        try fitnessDb.execute("""
            UPDATE workout_sessions SET
                performed_on = ?, kind = ?, sport = ?, start_ts = ?, end_ts = ?,
                avg_hr = COALESCE(?, avg_hr), max_hr = COALESCE(?, max_hr), strain = COALESCE(?, strain),
                zone0_sec = ?, zone1_sec = ?, zone2_sec = ?, zone3_sec = ?, zone4_sec = ?, zone5_sec = ?,
                long_endurance_exempt = ?, notes = ?
            WHERE id = ?
            """, [
                .text(performedOn.string), .text(kind.rawValue), .text(sport), .int(startTs), .optional(endTs),
                .optional(avgHr), .optional(maxHrVal), .optional(strainVal),
                .int(Int64(zSecs[0])), .int(Int64(zSecs[1])), .int(Int64(zSecs[2])),
                .int(Int64(zSecs[3])), .int(Int64(zSecs[4])), .int(Int64(zSecs[5])),
                .int(longEnduranceExempt ? 1 : 0), .optional(notes), .text(id),
            ])
        return try requireSession(id: id)
    }

    public func deleteSession(id: String) throws {
        try fitnessDb.execute("DELETE FROM workout_sessions WHERE id = ?", [.text(id)])
    }

    public func sessions(on date: ISODate? = nil) throws -> [WorkoutSessionRecord] {
        let rows: [Row]
        if let date {
            rows = try fitnessDb.query("SELECT * FROM workout_sessions WHERE performed_on = ? ORDER BY start_ts DESC", [.text(date.string)])
        } else {
            rows = try fitnessDb.query("SELECT * FROM workout_sessions ORDER BY start_ts DESC")
        }
        return rows.compactMap(Self.decodeRow)
    }

    /// Accepts (and optionally edits start/end/sport/notes of) a pending `AutoWorkoutDetector` proposal.
    @discardableResult
    public func acceptWorkoutProposal(
        proposalId: String,
        analyticsStore: WhoopAnalyticsStore,
        editedStartTs: Int64? = nil,
        editedEndTs: Int64? = nil,
        kind: WhoopCardioSessionKind = .easyCardio,
        sport: String = "Cardio",
        notes: String? = nil,
        nowSec: Int64 = 0
    ) throws -> WorkoutSessionRecord {
        guard let prop = try analyticsStore.activityProposals().first(where: { $0.id == proposalId }) else {
            throw ValidationError("Proposal not found")
        }
        let sTs = editedStartTs ?? prop.startTs
        let eTs = editedEndTs ?? prop.endTs
        guard let day = ISODate(prop.dayId) else {
            throw ValidationError("Invalid proposal day_id")
        }
        let sessionId = "auto-\(proposalId)"
        _ = try startSession(id: sessionId, performedOn: day, kind: kind, sport: sport, startTs: sTs, notes: notes)
        let updated = try updateSession(id: sessionId, performedOn: day, kind: kind, sport: sport, startTs: sTs, endTs: eTs, notes: notes)
        try analyticsStore.updateProposalStatus(id: proposalId, status: "accepted", editedStartTs: sTs, editedEndTs: eTs, nowSec: nowSec)
        return updated
    }

    /// Correlates stamped `LoggedSet.loggedAtTs` rows against 1 Hz HR (`[firstSetTs - 30s, lastSetTs + 60s]`) per exercise.
    public static func correlateExerciseHeartRates(
        sets: [LoggedSet],
        hrSamples: [(tsSec: Int64, bpm: Int)],
        zones: WhoopTrainingZones
    ) -> [ExerciseHeartRateSummary] {
        var grouped: [Int: (name: String, tsList: [Int64], count: Int)] = [:]
        var order: [Int] = []
        for s in sets {
            guard let ts = s.loggedAtTs else { continue }
            if grouped[s.exerciseId] == nil {
                order.append(s.exerciseId)
                grouped[s.exerciseId] = (s.exerciseName, [ts], 1)
            } else {
                grouped[s.exerciseId]?.tsList.append(ts)
                grouped[s.exerciseId]?.count += 1
            }
        }

        return order.compactMap { exId -> ExerciseHeartRateSummary? in
            guard let g = grouped[exId], let minTs = g.tsList.min(), let maxTs = g.tsList.max() else { return nil }
            let winStart = minTs - 30
            let winEnd = maxTs + 60
            let pts = hrSamples.filter {
                $0.tsSec >= winStart && $0.tsSec <= winEnd && WhoopSubstrateGates.plausibleHrOrZero($0.bpm) > 0
            }
            var zSecs = [0, 0, 0, 0, 0, 0]
            for p in pts {
                zSecs[zoneIndex(forBpm: p.bpm, zones: zones)] += 1
            }
            let avg = pts.isEmpty ? nil : Int((Double(pts.reduce(0) { $0 + $1.bpm }) / Double(pts.count)).rounded())
            let peak = pts.map(\.bpm).max()
            return ExerciseHeartRateSummary(
                exerciseId: exId,
                exerciseName: g.name,
                windowStartTs: winStart,
                windowEndTs: winEnd,
                setCount: g.count,
                avgHr: avg,
                peakHr: peak,
                zoneSeconds: zSecs
            )
        }
    }

    /// Builds overlaid exercise check-mark pins (`✓`) along a workout's `[startTs, endTs]` HR timeline.
    public static func exerciseTimelinePins(
        sets: [LoggedSet],
        hrSamples: [(tsSec: Int64, bpm: Int)],
        startTs: Int64,
        endTs: Int64
    ) -> [WorkoutExerciseTimelinePin] {
        let validSamples = hrSamples.filter { WhoopSubstrateGates.plausibleHrOrZero($0.bpm) > 0 }
        guard !validSamples.isEmpty else { return [] }
        let sortedSets = sets
            .filter { ($0.loggedAtTs ?? 0) >= (startTs - 300) && ($0.loggedAtTs ?? 0) <= (endTs + 300) }
            .sorted { ($0.loggedAtTs ?? 0) < ($1.loggedAtTs ?? 0) }

        return sortedSets.compactMap { s -> WorkoutExerciseTimelinePin? in
            guard let ts = s.loggedAtTs else { return nil }
            let near = validSamples.filter { abs($0.tsSec - ts) <= 45 }
            let bpm: Int
            if let peakNear = near.map(\.bpm).max() {
                bpm = peakNear
            } else if let closest = validSamples.min(by: { abs($0.tsSec - ts) < abs($1.tsSec - ts) }) {
                bpm = closest.bpm
            } else {
                return nil
            }
            let summary = "\(Int(s.weightKg.rounded()))kg × \(s.reps)"
            return WorkoutExerciseTimelinePin(
                id: s.id,
                exerciseId: s.exerciseId,
                exerciseName: s.exerciseName,
                tsSec: ts,
                setSummary: summary,
                bpmAtPin: bpm
            )
        }
    }

    private func requireSession(id: String) throws -> WorkoutSessionRecord {
        guard let row = try fitnessDb.query("SELECT * FROM workout_sessions WHERE id = ?", [.text(id)]).first,
              let rec = Self.decodeRow(row) else {
            throw ValidationError("Workout session not found")
        }
        return rec
    }

    private static func decodeRow(_ row: Row) -> WorkoutSessionRecord? {
        guard let day = ISODate(row.text("performed_on")) else { return nil }
        return WorkoutSessionRecord(
            id: row.text("id"),
            performedOn: day,
            kind: WhoopCardioSessionKind(rawValue: row.text("kind")) ?? .lifting,
            sport: row.text("sport"),
            startTs: row.optionalInt64("start_ts") ?? 0,
            endTs: row.optionalInt64("end_ts"),
            activeKcal: row.optionalDouble("active_kcal"),
            avgHr: row.optionalInt("avg_hr"),
            maxHr: row.optionalInt("max_hr"),
            strain: row.optionalDouble("strain"),
            zoneSeconds: [
                row.int("zone0_sec"), row.int("zone1_sec"), row.int("zone2_sec"),
                row.int("zone3_sec"), row.int("zone4_sec"), row.int("zone5_sec"),
            ],
            longEnduranceExempt: row.int("long_endurance_exempt") == 1,
            notes: row.optionalText("notes")
        )
    }
}

// MARK: - Non-Blocking Dual-Mode HIIT Engine (`0x13` Gen5 / `0x4F` Gen4 Haptics + `10 s` Hysteresis)

public enum DualModeHiitPhase: String, Equatable, Sendable {
    case workOrPushUpper = "work_or_push_upper"
    case restOrRecoverLower = "rest_or_recover_lower"
    case completed = "completed"
}

public struct DualModeHiitEngine: Equatable, Sendable {
    public static let hysteresisCooldownSec: Int64 = 10

    public let preset: HiitPreset
    public let profile: WhoopBandProfile
    public private(set) var phase: DualModeHiitPhase
    public private(set) var currentRound: Int
    public private(set) var phaseStartedSec: Int64
    public private(set) var lastBuzzSec: Int64?
    private var seq: UInt8 = 10

    public init(preset: HiitPreset, profile: WhoopBandProfile = .gen5, startSec: Int64) {
        self.preset = preset
        self.profile = profile
        self.phase = .workOrPushUpper
        self.currentRound = 1
        self.phaseStartedSec = startSec
        self.lastBuzzSec = nil
    }

    /// Time-interval tick (`mode == .time`): transitions work <-> rest and returns haptic frame(s) (`0x13` Gen5 / `0x4F` Gen4).
    public mutating func tick(nowSec: Int64) -> [[UInt8]] {
        guard preset.mode == .time, phase != .completed else { return [] }
        let elapsed = nowSec - phaseStartedSec
        switch phase {
        case .workOrPushUpper:
            guard elapsed >= Int64(preset.workSec) else { return [] }
            phase = .restOrRecoverLower
            phaseStartedSec = nowSec
            return [emitBuzz(pattern: 2, loop: 2, nowSec: nowSec)]
        case .restOrRecoverLower:
            guard elapsed >= Int64(preset.restSec) else { return [] }
            if currentRound >= preset.rounds {
                phase = .completed
                return [emitBuzz(pattern: 3, loop: 3, nowSec: nowSec)]
            } else {
                currentRound += 1
                phase = .workOrPushUpper
                phaseStartedSec = nowSec
                return [emitBuzz(pattern: 1, loop: 1, nowSec: nowSec)]
            }
        case .completed:
            return []
        }
    }

    /// HR-Threshold trigger (`mode == .hrThreshold`) with strict `10 s` hysteresis cooldown to prevent rapid-buzz chatter.
    public mutating func ingestHeartRate(tsSec: Int64, bpm: Int) -> [[UInt8]] {
        guard preset.mode == .hrThreshold, phase != .completed else { return [] }
        guard WhoopSubstrateGates.plausibleHrOrZero(bpm) > 0 else { return [] }
        if let last = lastBuzzSec, (tsSec - last) < Self.hysteresisCooldownSec {
            return []
        }

        switch phase {
        case .workOrPushUpper:
            guard bpm >= preset.highBpm else { return [] }
            phase = .restOrRecoverLower
            phaseStartedSec = tsSec
            return [emitBuzz(pattern: 2, loop: 2, nowSec: tsSec)]
        case .restOrRecoverLower:
            guard bpm <= preset.lowBpm else { return [] }
            if currentRound >= preset.rounds {
                phase = .completed
                return [emitBuzz(pattern: 3, loop: 3, nowSec: tsSec)]
            } else {
                currentRound += 1
                phase = .workOrPushUpper
                phaseStartedSec = tsSec
                return [emitBuzz(pattern: 1, loop: 1, nowSec: tsSec)]
            }
        case .completed:
            return []
        }
    }

    private mutating func emitBuzz(pattern: UInt8, loop: UInt8, nowSec: Int64) -> [UInt8] {
        seq = seq &+ 1
        lastBuzzSec = nowSec
        return WhoopCommands.cmdBuzz(seq: seq, pattern: pattern, overallLoop: loop, profile: profile)
    }
}
