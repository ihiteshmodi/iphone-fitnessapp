import Foundation

/// Heaviest set: weight desc, then reps desc, then most recent date (notebook: Max Weight / Reps at Max Weight).
public enum HeaviestSet {
    public static func of(_ sets: [PerformedSet]) -> PerformedSet? {
        sets.max { lhs, rhs in
            if lhs.weightKg != rhs.weightKg { return lhs.weightKg < rhs.weightKg }
            if lhs.reps != rhs.reps { return lhs.reps < rhs.reps }
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.id < rhs.id
        }
    }
}

extension TargetRecommendation {
    /// Always judged against the planned (unscaled) rep range.
    public static func judge(repsAtHeaviest: Int?, minReps: Int, maxReps: Int) -> TargetRecommendation {
        guard let reps = repsAtHeaviest else { return .noHistory }
        if reps >= maxReps { return .increaseWeight }
        if reps >= minReps { return .increaseReps }
        return .bringToMaintenance
    }
}

public struct WorkoutTarget: Equatable {
    public let workingWeight: Double?
    public let warmup75: Double?
    public let warmup90: Double?
    public let minReps: Double
    public let maxReps: Double
    public let recommendation: TargetRecommendation?
    public let repsAtMax: Int?
    public let dateOfMax: ISODate?
}

public enum WorkoutTargetCalculator {
    public static func target(heaviest: PerformedSet?, minReps: Int, maxReps: Int, deload: DeloadSettings) -> WorkoutTarget {
        let scaling = DeloadScaling(deload)
        let shownMinReps = scaling.minReps(planned: minReps)
        let shownMaxReps = scaling.maxReps(planned: maxReps)
        let recommendation: TargetRecommendation? = scaling.isActive
            ? nil
            : .judge(repsAtHeaviest: heaviest?.reps, minReps: minReps, maxReps: maxReps)

        guard let heaviest else {
            return WorkoutTarget(workingWeight: nil, warmup75: nil, warmup90: nil, minReps: shownMinReps, maxReps: shownMaxReps,
                                 recommendation: recommendation, repsAtMax: nil, dateOfMax: nil)
        }
        // Warm-ups come from the rounded working weight, exactly like the notebook.
        let working = pyRound(scaling.workingWeight(heaviest: heaviest.weightKg), 2)
        return WorkoutTarget(workingWeight: working, warmup75: pyRound(working * 0.75, 2), warmup90: pyRound(working * 0.90, 2),
                             minReps: shownMinReps, maxReps: shownMaxReps, recommendation: recommendation,
                             repsAtMax: heaviest.reps, dateOfMax: heaviest.date)
    }
}

public enum DayLabel {
    public static func make(position: Int, weekday: Int?, mode: DayLabelMode) -> String {
        let shortNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        if mode == .weekday, let weekday, (1...7).contains(weekday) { return shortNames[weekday - 1] }
        return "Day \(position)"
    }
}

/// All sets of one training day for one exercise.
public struct ExerciseSession: Equatable {
    public let date: ISODate
    public let sets: [PerformedSet]
    /// Set with the highest estimated one-rep max.
    public let best: PerformedSet
    public let estimatedOneRepMax: Double
}

public enum SessionHistory {
    /// Epley: weight x (1 + reps / 30). See `OneRepMax` for what it is used for.
    public static func epleyEstimate(weightKg: Double, reps: Int) -> Double {
        weightKg * (1 + Double(reps) / 30)
    }

    /// Sessions ordered oldest first.
    public static func sessions(from sets: [PerformedSet]) -> [ExerciseSession] {
        Dictionary(grouping: sets, by: \.date).map { date, daySets in
            let ordered = daySets.sorted { $0.id < $1.id }
            let best = ordered.max { lhs, rhs in
                let left = epleyEstimate(weightKg: lhs.weightKg, reps: lhs.reps)
                let right = epleyEstimate(weightKg: rhs.weightKg, reps: rhs.reps)
                if left != right { return left < right }
                if lhs.weightKg != rhs.weightKg { return lhs.weightKg < rhs.weightKg }
                return lhs.reps < rhs.reps
            } ?? ordered[0]
            return ExerciseSession(date: date, sets: ordered, best: best,
                                   estimatedOneRepMax: epleyEstimate(weightKg: best.weightKg, reps: best.reps))
        }.sorted { $0.date < $1.date }
    }
}
