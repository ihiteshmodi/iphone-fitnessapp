import Foundation

/// Reads and saves the muscles of one exercise. No saved rows means "automatic": the muscles are worked out
/// from the exercise's current name and group every time, so renaming or regrouping an exercise updates them.
public final class ExerciseMuscleService {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    public func muscles(exerciseId: Int) throws -> ExerciseMuscles {
        let exercise = try existing(exerciseId)
        let chosen = try db.query("SELECT part, role FROM exercise_muscles WHERE exercise_id = ?", [.int(Int64(exerciseId))])
            .compactMap { row -> MuscleAssignment? in
                // A part or role this version does not know (from a newer app) is skipped.
                guard let part = MusclePart(rawValue: row.text("part")), let role = MuscleRole(rawValue: row.text("role")) else { return nil }
                return MuscleAssignment(part: part, role: role)
            }
        if chosen.isEmpty {
            return ExerciseMuscles(assignments: MuscleDefaults.assignments(exerciseName: exercise.name, group: exercise.muscle), isCustom: false)
        }
        return ExerciseMuscles(assignments: chosen, isCustom: true)
    }

    /// Replaces the chosen muscles. Choosing nothing is the same as resetting to automatic.
    public func save(exerciseId: Int, assignments: [MuscleAssignment]) throws {
        _ = try existing(exerciseId)
        let selection = MuscleSelection(assignments: assignments).assignments
        try db.transaction {
            try db.execute("DELETE FROM exercise_muscles WHERE exercise_id = ?", [.int(Int64(exerciseId))])
            for assignment in selection {
                try db.execute("INSERT INTO exercise_muscles (exercise_id, part, role) VALUES (?, ?, ?)",
                               [.int(Int64(exerciseId)), .text(assignment.part.rawValue), .text(assignment.role.rawValue)])
            }
        }
    }

    public func reset(exerciseId: Int) throws {
        _ = try existing(exerciseId)
        try db.execute("DELETE FROM exercise_muscles WHERE exercise_id = ?", [.int(Int64(exerciseId))])
    }

    private func existing(_ exerciseId: Int) throws -> Exercise {
        guard let exercise = try ExerciseRepository(db).exercise(id: exerciseId) else { throw ValidationError("Exercise not found") }
        return exercise
    }
}
