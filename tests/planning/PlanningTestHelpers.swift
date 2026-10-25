import XCTest
@testable import FitnessCore

let planningToday = date("2026-10-20")

func planningClock() -> FixedClock { FixedClock(planningToday) }

func setDeload(_ db: Database, enabled: Bool, weightMultiplier: Double = 1, repsMultiplier: Double = 0.75) throws {
    let settings = SettingsRepository(db)
    try settings.setDeloadWeightMultiplier(weightMultiplier)
    try settings.setDeloadRepsMultiplier(repsMultiplier)
    try settings.setDeloadEnabled(enabled)
}

func setDayLabelMode(_ db: Database, _ mode: DayLabelMode) throws {
    try SettingsRepository(db).setDayLabelMode(mode)
}

extension Database {
    func count(_ table: String) throws -> Int {
        try query("SELECT COUNT(*) AS n FROM \(table)").first?.int("n") ?? 0
    }

    func entryPositions(day: Int) throws -> [Int] {
        try query("SELECT position FROM plan_entries WHERE day_id = ? ORDER BY position", [.int(Int64(day))]).map { $0.int("position") }
    }

    func dayPositions() throws -> [Int] {
        try query("SELECT position FROM plan_days ORDER BY position").map { $0.int("position") }
    }
}

/// Convenience for the tests: one day with one planned exercise and its heaviest set.
struct PlannedExercise {
    let db: Database
    let dayId: Int
    let exerciseId: Int
    let entryId: Int

    @discardableResult
    static func make(_ db: Database, name: String = "Chest Dips Machine", muscle: String? = "Chest",
                     minReps: Int = 6, maxReps: Int = 10, sets: Int = 3, dayPosition: Int = 1) throws -> PlannedExercise {
        let day = try db.addDay(position: dayPosition)
        let exercise = try db.addExercise(name, muscle: muscle)
        let entry = try db.addEntry(day: day, exercise: exercise, sets: sets, minReps: minReps, maxReps: maxReps)
        return PlannedExercise(db: db, dayId: day, exerciseId: exercise, entryId: entry)
    }
}
