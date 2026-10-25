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
    public let sets: Int
    /// Double because deload scales it (6 becomes 4.5). Display only.
    public let minReps: Double
    /// The value stored in the plan. The plan editor edits this, never the scaled `minReps`.
    public let plannedMinReps: Int
    public let maxReps: Int
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
}

public struct Workout: Equatable {
    public let day: PlanDay
    public let isDeload: Bool
    public let exercises: [WorkoutExercise]
}
