import Foundation

public struct DetailTarget: Equatable {
    public let sets: Int
    public let minReps: Double
    public let maxReps: Double
    public let workingWeight: Double?
    public let warmup75: Double?
    public let warmup90: Double?
    /// nil while deload is on.
    public let recommendation: TargetRecommendation?
}

public enum RepRange {
    /// Where the reps in the "Add set" form start: the average of the range, rounded up (8 to 16 gives 12, 10 to 15 gives 13).
    public static func middle(min: Double, max: Double) -> Int {
        Swift.max(1, Int(((min + max) / 2).rounded(.up)))
    }
}

/// What the "Add set" form starts with.
public struct SetFormPrefill: Equatable {
    public let weightKg: Double?
    public let reps: Int
}

public struct ExerciseDetail: Equatable {
    public let exercise: Exercise
    public let hasHistory: Bool
    public let isDeload: Bool
    public let target: DetailTarget
    /// Newest session strictly before today.
    public let lastSession: ExerciseSession?
    /// Today's aim, e.g. "Increase reps: beat 9 reps at 54 kg".
    public let aim: String
    /// Last 6 sessions (today included), oldest first, for the chart.
    public let sessions: [ExerciseSession]
    public let trend: ExerciseTrend
    /// Up to 10 sessions strictly before today, newest first.
    public let history: [ExerciseSession]
    public let todaySets: [PerformedSet]
    public let targetSets: Int
    public let prefill: SetFormPrefill
    /// The muscles this exercise trains (chosen by the user, or automatic).
    public let muscles: ExerciseMuscles

    /// The aim split for the "Do today" card: a short pill and an optional hint.
    public var aimSummary: AimSummary { AimSummary.make(from: aim) }
}

/// "Increase reps: beat 9 reps at 54 kg" as a pill ("Increase reps") and a hint ("Beat 9 reps at 54 kg").
public struct AimSummary: Equatable {
    public let pill: String
    public let hint: String?

    public init(pill: String, hint: String?) {
        self.pill = pill
        self.hint = hint
    }

    public static func make(from aim: String) -> AimSummary {
        guard let colon = aim.range(of: ": ") else { return AimSummary(pill: aim, hint: nil) }
        let pill = String(aim[..<colon.lowerBound])
        let hint = String(aim[colon.upperBound...])
        return AimSummary(pill: pill == "Bring to maintenance" ? "Maintain" : pill, hint: hint.prefix(1).uppercased() + hint.dropFirst())
    }
}

/// The warm-up steps shown next to the working weight, as percentages of it.
public enum WarmupLabels {
    public static let percentages = [75, 90]
}

public final class ExerciseDetailService {
    private let db: Database
    private let clock: AppClock

    public init(_ db: Database, clock: AppClock) {
        self.db = db
        self.clock = clock
    }

    public func detail(exerciseId: Int, dayId: Int) throws -> ExerciseDetail {
        let settings = try SettingsRepository(db).load()
        guard let entry = try PlanReader(db: db).entry(dayId: dayId, exerciseId: exerciseId) else {
            throw ValidationError("Exercise is not planned on this day")
        }

        let history = SetHistoryReader(db: db)
        let today = clock.today()
        let allSets = try history.sets(exerciseId: exerciseId, since: settings.historyStartDate)
        let sets = ProgressSets.filter(allSets, ignoreDeload: settings.ignoreDeloadSessions)
        let heaviest = HeaviestSet.of(sets)
        let target = WorkoutTargetCalculator.target(heaviest: heaviest, minReps: entry.minReps, maxReps: entry.maxReps,
                                                    deload: settings.deload)

        let sessions = SessionHistory.sessions(from: sets)
        let lastSession = sessions.filter { $0.date < today }.last
        // The history list is a log, so it keeps deload sessions (their sets carry the deload flag).
        let loggedBefore = SessionHistory.sessions(from: allSets).filter { $0.date < today }

        return ExerciseDetail(
            exercise: entry.exercise,
            hasHistory: heaviest != nil,
            isDeload: settings.deload.enabled,
            target: DetailTarget(sets: entry.sets, minReps: target.minReps, maxReps: target.maxReps,
                                 workingWeight: target.workingWeight, warmup75: target.warmup75, warmup90: target.warmup90,
                                 recommendation: target.recommendation),
            lastSession: lastSession,
            aim: Self.aim(target: target, lastSession: lastSession),
            sessions: Array(sessions.suffix(Self.chartSessions)),
            trend: ExerciseTrend.classify(sessions.map(\.estimatedOneRepMax)),
            history: Array(loggedBefore.reversed().prefix(Self.historySessions)),
            todaySets: try history.sets(exerciseId: exerciseId, on: today),
            targetSets: entry.sets,
            prefill: SetFormPrefill(weightKg: target.workingWeight, reps: RepRange.middle(min: target.minReps, max: target.maxReps)),
            muscles: try ExerciseMuscleService(db).muscles(exerciseId: exerciseId))
    }

    /// Saves the how-to text in the library, so every day that uses the exercise shows it.
    public func updateInstructions(exerciseId: Int, instructions: String?) throws {
        let library = ExerciseRepository(db)
        guard let existing = try library.exercise(id: exerciseId) else { throw ValidationError("Exercise not found") }
        try library.update(id: exerciseId, name: existing.name, muscle: existing.muscle, instructions: instructions)
    }

    static let chartSessions = 6
    static let historySessions = 10

    private static func aim(target: WorkoutTarget, lastSession: ExerciseSession?) -> String {
        guard let weight = target.workingWeight else { return "No history yet" }
        let kg = "\(format(weight)) kg"
        guard let recommendation = target.recommendation else {
            return "Deload: \(format(target.minReps)) to \(format(target.maxReps)) reps at \(kg)"
        }
        switch recommendation {
        case .noHistory:
            return "No history yet"
        case .increaseWeight:
            return "Increase weight"
        case .increaseReps:
            let lastReps = lastSession?.sets.filter { pyRound($0.weightKg, 2) == weight }.map(\.reps).max()
            return "Increase reps: beat \(lastReps ?? target.repsAtMax ?? 0) reps at \(kg)"
        case .bringToMaintenance:
            return "Bring to maintenance: reach \(format(target.minReps)) reps at \(kg)"
        }
    }

    /// 54.0 -> "54", 43.2 -> "43.2".
    private static func format(_ value: Double) -> String {
        String(format: "%g", value)
    }
}
