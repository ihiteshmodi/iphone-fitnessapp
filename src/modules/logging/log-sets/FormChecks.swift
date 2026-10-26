import Foundation

/// Whether the reps of an exercise were clean (a full contraction on every rep) on a day. Asked once, when the top of the
/// rep range is reached; it decides whether that session counts as a PR.
public final class FormChecks {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    /// Saves the answer; answering again for the same exercise and day replaces it.
    public func setClean(_ clean: Bool, exerciseId: Int, on date: ISODate) throws {
        guard try ExerciseRepository(db).exercise(id: exerciseId) != nil else { throw ValidationError("Exercise not found") }
        try db.execute("""
            INSERT INTO form_checks (exercise_id, performed_on, clean) VALUES (?, ?, ?)
            ON CONFLICT(exercise_id, performed_on) DO UPDATE SET clean = excluded.clean
            """, [.int(Int64(exerciseId)), .text(date.string), .int(clean ? 1 : 0)])
    }

    /// nil when it was never asked.
    public func answer(exerciseId: Int, on date: ISODate) throws -> Bool? {
        try db.query("SELECT clean FROM form_checks WHERE exercise_id = ? AND performed_on = ?",
                     [.int(Int64(exerciseId)), .text(date.string)]).first.map { $0.int("clean") == 1 }
    }

    public func answers(exerciseId: Int) throws -> [ISODate: Bool] {
        var result: [ISODate: Bool] = [:]
        for row in try db.query("SELECT performed_on, clean FROM form_checks WHERE exercise_id = ?", [.int(Int64(exerciseId))]) {
            if let day = ISODate(row.text("performed_on")) { result[day] = row.int("clean") == 1 }
        }
        return result
    }
}
