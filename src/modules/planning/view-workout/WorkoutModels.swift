import Foundation

/// A day of the plan as shown in the day picker.
public struct PlanDay: Equatable, Identifiable {
    public let id: Int
    public let position: Int
    /// "Day 3" or "Wed", depending on the day-label setting.
    public let label: String
    public let title: String?
    /// ISO weekday, 1 = Monday ... 7 = Sunday.
    public let weekday: Int?
    public let exerciseCount: Int
}

/// One logged set, as read from `set_logs`.
public struct PerformedSet: Equatable, Identifiable {
    public let id: Int
    public let date: ISODate
    public let weightKg: Double
    public let reps: Int
    /// True when the set was logged while deload mode was on.
    public let isDeload: Bool

    public init(id: Int, date: ISODate, weightKg: Double, reps: Int, isDeload: Bool = false) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.reps = reps
        self.isDeload = isDeload
    }
}

public enum TargetRecommendation: String, Equatable {
    case noHistory = "No history"
    case increaseWeight = "Increase Weight"
    case increaseReps = "Increase Reps"
    case bringToMaintenance = "Bring to maintenance"
}

public struct WorkoutExercise: Equatable, Identifiable {
    public var id: Int { planEntryId }
    public let planEntryId: Int
    public let exerciseId: Int
    public let name: String
    public let muscle: String?
    public let instructions: String?
    /// Main sets: logged and counted.
    public let sets: Int
    /// Warm-up sets: reference only, never logged.
    public let warmupSets: Int
    /// Double because deload scales it (6 becomes 4.5). Display only.
    public let minReps: Double
    /// The value stored in the plan. The plan editor edits this, never the scaled `minReps`.
    public let plannedMinReps: Int
    /// Scaled by deload like `minReps` (16 becomes 12). Display only.
    public let maxReps: Double
    /// The value stored in the plan, for the plan editor.
    public let plannedMaxReps: Int
    public let workingWeight: Double?
    public let warmup75: Double?
    public let warmup90: Double?
    /// nil while deload is on.
    public let recommendation: TargetRecommendation?
    public let repsAtMax: Int?
    public let dateOfMax: ISODate?
    public let setsLoggedToday: Int
    /// Best-set weight of up to the last 6 sessions, oldest first.
    public let sparkline: [Double]
    /// PR to act on, or repeat for clean reps. `.none` during deload.
    public let progression: Progression

    /// All its main sets are logged today.
    public var isDone: Bool { setsLoggedToday >= sets }
}

/// Which exercises of a day the workout screen lists.
public enum WorkoutFilter: Equatable {
    case all
    case remaining
}

public struct Workout: Equatable {
    public let day: PlanDay
    public let isDeload: Bool
    public let exercises: [WorkoutExercise]

    public func exercises(_ filter: WorkoutFilter) -> [WorkoutExercise] {
        filter == .all ? exercises : exercises.filter { !$0.isDone }
    }

    public var remainingCount: Int { exercises.filter { !$0.isDone }.count }

    /// False for a day with no exercises, which has nothing to be done.
    public var isAllDone: Bool { !exercises.isEmpty && remainingCount == 0 }
}
