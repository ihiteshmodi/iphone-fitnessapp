import Foundation

/// Builds the plan: days and the exercises on them. Never touches `set_logs`.
/// Positions stay unique and contiguous (1...n) after every change, so labels like "Day 3" never skip a number.
public final class PlanEditor {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    // MARK: Days

    @discardableResult
    public func addDay() throws -> Int {
        try db.execute("INSERT INTO plan_days (position) SELECT COALESCE(MAX(position), 0) + 1 FROM plan_days")
        return db.lastInsertRowID
    }

    public func deleteDay(id: Int) throws {
        try requireDay(id)
        try db.transaction {
            try db.execute("DELETE FROM plan_entries WHERE day_id = ?", [.int(Int64(id))])
            try db.execute("DELETE FROM plan_days WHERE id = ?", [.int(Int64(id))])
            try renumberDays()
        }
    }

    public func setWeekday(dayId: Int, weekday: Int?) throws {
        try requireDay(dayId)
        if let weekday, !(1...7).contains(weekday) { throw ValidationError("Weekday must be between 1 and 7") }
        try db.execute("UPDATE plan_days SET weekday = ? WHERE id = ?", [.optional(weekday), .int(Int64(dayId))])
    }

    public func setTitle(dayId: Int, title: String?) throws {
        try requireDay(dayId)
        let cleaned = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        try db.execute("UPDATE plan_days SET title = ? WHERE id = ?",
                       [.optional(cleaned?.isEmpty == false ? cleaned : nil), .int(Int64(dayId))])
    }

    // MARK: Entries

    /// Appends the library exercise as the last one of the day and returns the plan entry id.
    @discardableResult
    public func addExercise(dayId: Int, exerciseId: Int, sets: Int, minReps: Int, maxReps: Int) throws -> Int {
        try validate(sets: sets, minReps: minReps, maxReps: maxReps)
        try requireDay(dayId)
        guard try ExerciseRepository(db).exercise(id: exerciseId) != nil else { throw ValidationError("Exercise not found") }
        return try insertEntry(dayId: dayId, exerciseId: exerciseId, sets: sets, minReps: minReps, maxReps: maxReps)
    }

    /// Creates the library exercise (source "user") and adds it, all or nothing.
    @discardableResult
    public func createExerciseAndAdd(dayId: Int, name: String, muscle: String?, instructions: String?,
                                     sets: Int, minReps: Int, maxReps: Int) throws -> Int {
        try validate(sets: sets, minReps: minReps, maxReps: maxReps)
        try requireDay(dayId)
        return try db.transaction {
            let exercise = try ExerciseRepository(db).add(name: name, muscle: muscle, instructions: instructions)
            return try insertEntry(dayId: dayId, exerciseId: exercise.id, sets: sets, minReps: minReps, maxReps: maxReps)
        }
    }

    public func updateEntry(entryId: Int, sets: Int, minReps: Int, maxReps: Int) throws {
        try validate(sets: sets, minReps: minReps, maxReps: maxReps)
        _ = try dayOfEntry(entryId)
        try db.execute("UPDATE plan_entries SET sets = ?, min_reps = ?, max_reps = ? WHERE id = ?",
                       [.int(Int64(sets)), .int(Int64(minReps)), .int(Int64(maxReps)), .int(Int64(entryId))])
    }

    public func removeEntry(entryId: Int) throws {
        let dayId = try dayOfEntry(entryId)
        try db.transaction {
            try db.execute("DELETE FROM plan_entries WHERE id = ?", [.int(Int64(entryId))])
            try renumberEntries(dayId: dayId)
        }
    }

    /// `toPosition` is 1-based and clamped to the day's length.
    public func moveEntry(entryId: Int, toPosition: Int) throws {
        let dayId = try dayOfEntry(entryId)
        try db.transaction {
            var ids = try entryIds(dayId: dayId)
            ids.removeAll { $0 == entryId }
            ids.insert(entryId, at: min(max(toPosition, 1), ids.count + 1) - 1)
            try assignEntryPositions(ids)
        }
    }

    // MARK: Helpers

    private func validate(sets: Int, minReps: Int, maxReps: Int) throws {
        guard sets >= 1 else { throw ValidationError("Sets must be at least 1") }
        guard minReps >= 0 else { throw ValidationError("Min reps cannot be negative") }
        guard minReps <= maxReps else { throw ValidationError("Min reps cannot exceed max reps") }
    }

    private func requireDay(_ id: Int) throws {
        guard try !db.query("SELECT 1 AS found FROM plan_days WHERE id = ?", [.int(Int64(id))]).isEmpty else {
            throw ValidationError("Day not found")
        }
    }

    private func dayOfEntry(_ entryId: Int) throws -> Int {
        guard let row = try db.query("SELECT day_id FROM plan_entries WHERE id = ?", [.int(Int64(entryId))]).first else {
            throw ValidationError("Plan entry not found")
        }
        return row.int("day_id")
    }

    private func insertEntry(dayId: Int, exerciseId: Int, sets: Int, minReps: Int, maxReps: Int) throws -> Int {
        let duplicate = try db.query("SELECT 1 AS found FROM plan_entries WHERE day_id = ? AND exercise_id = ?",
                                     [.int(Int64(dayId)), .int(Int64(exerciseId))])
        guard duplicate.isEmpty else { throw ValidationError("Already on this day") }
        try db.execute("""
            INSERT INTO plan_entries (day_id, position, exercise_id, sets, min_reps, max_reps)
            VALUES (?1, (SELECT COALESCE(MAX(position), 0) + 1 FROM plan_entries WHERE day_id = ?1), ?2, ?3, ?4, ?5)
            """, [.int(Int64(dayId)), .int(Int64(exerciseId)), .int(Int64(sets)), .int(Int64(minReps)), .int(Int64(maxReps))])
        return db.lastInsertRowID
    }

    private func entryIds(dayId: Int) throws -> [Int] {
        try db.query("SELECT id FROM plan_entries WHERE day_id = ? ORDER BY position, id", [.int(Int64(dayId))]).map { $0.int("id") }
    }

    private func renumberEntries(dayId: Int) throws {
        try assignEntryPositions(try entryIds(dayId: dayId))
    }

    private func assignEntryPositions(_ orderedIds: [Int]) throws {
        for (index, id) in orderedIds.enumerated() {
            try db.execute("UPDATE plan_entries SET position = ? WHERE id = ?", [.int(Int64(index + 1)), .int(Int64(id))])
        }
    }

    /// plan_days.position is UNIQUE, so rows are first moved out of the way, then given their final numbers.
    private func renumberDays() throws {
        let rows = try db.query("SELECT id, position FROM plan_days ORDER BY position")
        guard let highest = rows.last?.int("position") else { return }
        let ids = rows.map { $0.int("id") }
        try db.execute("UPDATE plan_days SET position = position + ?", [.int(Int64(highest))])
        for (index, id) in ids.enumerated() {
            try db.execute("UPDATE plan_days SET position = ? WHERE id = ?", [.int(Int64(index + 1)), .int(Int64(id))])
        }
    }
}
