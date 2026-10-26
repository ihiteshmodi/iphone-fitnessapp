import Foundation

/// Estimated one-rep max (Epley) and what it says about the next weight.
public enum OneRepMax {
    /// Smallest weight change on the machines and plates.
    public static let defaultStep = 2.5

    /// Epley: weight x (1 + reps / 30).
    public static func estimate(weightKg: Double, reps: Int) -> Double {
        SessionHistory.epleyEstimate(weightKg: weightKg, reps: reps)
    }

    /// The weight whose estimated 1RM equals the one just reached, at the minimum reps of the range, rounded to the
    /// nearest step. Always at least one step above the weight lifted.
    public static func nextWeight(afterWeightKg weight: Double, reps: Int, minReps: Int, step: Double = defaultStep) -> Double {
        let atMinimumReps = estimate(weightKg: weight, reps: reps) / (1 + Double(minReps) / 30)
        let rounded = (atMinimumReps / step).rounded() * step
        return max(rounded, weight + step)
    }
}
