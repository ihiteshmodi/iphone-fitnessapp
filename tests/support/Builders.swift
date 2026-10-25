import Foundation
@testable import FitnessCore

/// Test-data builders. They write straight to the schema so tests read as "given ... when ... then".
extension Database {
    @discardableResult
    func addExercise(_ name: String, muscle: String? = nil, instructions: String? = nil, source: String = "library") throws -> Int {
        try execute("INSERT INTO exercises (name, muscle, instructions, source) VALUES (?, ?, ?, ?)",
                    [.text(name), .optional(muscle), .optional(instructions), .text(source)])
        return lastInsertRowID
    }

    @discardableResult
    func addDay(position: Int, weekday: Int? = nil, title: String? = nil) throws -> Int {
        try execute("INSERT INTO plan_days (position, weekday, title) VALUES (?, ?, ?)",
                    [.int(Int64(position)), .optional(weekday), .optional(title)])
        return lastInsertRowID
    }

    @discardableResult
    func addEntry(day: Int, exercise: Int, position: Int = 1, sets: Int = 3, minReps: Int = 6, maxReps: Int = 10) throws -> Int {
        try execute("INSERT INTO plan_entries (day_id, position, exercise_id, sets, min_reps, max_reps) VALUES (?, ?, ?, ?, ?, ?)",
                    [.int(Int64(day)), .int(Int64(position)), .int(Int64(exercise)), .int(Int64(sets)), .int(Int64(minReps)), .int(Int64(maxReps))])
        return lastInsertRowID
    }

    @discardableResult
    func addSet(exercise: Int, on date: String, weight: Double, reps: Int, deload: Bool = false) throws -> Int {
        try execute("INSERT INTO set_logs (performed_on, exercise_id, weight_kg, reps, is_deload) VALUES (?, ?, ?, ?, ?)",
                    [.text(date), .int(Int64(exercise)), .double(weight), .int(Int64(reps)), .int(deload ? 1 : 0)])
        return lastInsertRowID
    }

    func addBodyWeight(on date: String, kg: Double) throws {
        try execute("INSERT INTO body_weights (measured_on, weight_kg) VALUES (?, ?)", [.text(date), .double(kg)])
    }

    func addMeasurement(on date: String, site: String, inches: Double) throws {
        try execute("INSERT INTO body_measurements (measured_on, site, inches) VALUES (?, ?, ?)", [.text(date), .text(site), .double(inches)])
    }

    func addTarget(site: String, inches: Double) throws {
        try execute("INSERT INTO measurement_targets (site, inches) VALUES (?, ?)", [.text(site), .double(inches)])
    }
}

func date(_ string: String) -> ISODate {
    guard let value = ISODate(string) else { fatalError("Bad test date \(string)") }
    return value
}
