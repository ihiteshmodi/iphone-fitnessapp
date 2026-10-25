import Foundation

/// Sets and rep range with the stepper rules shared by every screen that edits them.
struct PlanRepScheme: Equatable {
    static let maxSets = 20
    static let maxReps = 100

    var sets = 3
    var minReps = 6
    var maxReps = 10

    var rangeText: String { "\(sets) sets · \(minReps)–\(maxReps) reps" }

    mutating func changeSets(by delta: Int) { sets = min(max(sets + delta, 1), Self.maxSets) }

    /// Raising min past max pushes max up, so the range stays valid.
    mutating func changeMinReps(by delta: Int) {
        minReps = min(max(minReps + delta, 0), Self.maxReps)
        if maxReps < minReps { maxReps = minReps }
    }

    /// Lowering max below min pulls min down.
    mutating func changeMaxReps(by delta: Int) {
        maxReps = min(max(maxReps + delta, 1), Self.maxReps)
        if minReps > maxReps { minReps = maxReps }
    }
}
