import Foundation

/// A plan entry joined with its library exercise.
struct PlanEntryRow {
    let planEntryId: Int
    let exercise: Exercise
    let sets: Int
    let warmupSets: Int
    let minReps: Int
    let maxReps: Int
}

struct PlanDayRow {
    let id: Int
    let position: Int
    let weekday: Int?
    let title: String?
    let exerciseCount: Int
}

/// Read-only SQL for the plan (days, entries, library data).
struct PlanReader {
    let db: Database

    func days() throws -> [PlanDayRow] {
        try db.query("""
            SELECT d.id, d.position, d.weekday, d.title,
                   (SELECT COUNT(*) FROM plan_entries e WHERE e.day_id = d.id) AS entry_count
            FROM plan_days d ORDER BY d.position
            """).map(Self.day)
    }

    func day(id: Int) throws -> PlanDayRow? {
        try db.query("""
            SELECT d.id, d.position, d.weekday, d.title,
                   (SELECT COUNT(*) FROM plan_entries e WHERE e.day_id = d.id) AS entry_count
            FROM plan_days d WHERE d.id = ?
            """, [.int(Int64(id))]).first.map(Self.day)
    }

    func entries(dayId: Int) throws -> [PlanEntryRow] {
        try db.query(Self.entrySQL + " WHERE e.day_id = ? ORDER BY e.position, e.id", [.int(Int64(dayId))]).map(Self.entry)
    }

    func entry(dayId: Int, exerciseId: Int) throws -> PlanEntryRow? {
        try db.query(Self.entrySQL + " WHERE e.day_id = ? AND e.exercise_id = ?",
                     [.int(Int64(dayId)), .int(Int64(exerciseId))]).first.map(Self.entry)
    }

    private static let entrySQL = """
        SELECT e.id AS entry_id, e.sets, e.warmup_sets, e.min_reps, e.max_reps,
               x.id AS exercise_id, x.name, x.muscle, x.instructions, x.source
        FROM plan_entries e JOIN exercises x ON x.id = e.exercise_id
        """

    private static func day(_ row: Row) -> PlanDayRow {
        PlanDayRow(id: row.int("id"), position: row.int("position"), weekday: row.optionalInt("weekday"),
                   title: row.optionalText("title"), exerciseCount: row.int("entry_count"))
    }

    private static func entry(_ row: Row) -> PlanEntryRow {
        PlanEntryRow(
            planEntryId: row.int("entry_id"),
            exercise: Exercise(id: row.int("exercise_id"), name: row.text("name"), muscle: row.optionalText("muscle"),
                               instructions: row.optionalText("instructions"), source: row.text("source")),
            sets: row.int("sets"), warmupSets: row.int("warmup_sets"), minReps: row.int("min_reps"), maxReps: row.int("max_reps"))
    }
}

/// Read-only SQL for logged sets of one exercise.
struct SetHistoryReader {
    let db: Database

    /// Sets on or after the history start date, oldest first. Includes deload sets; use `ProgressSets.filter`
    /// for anything that measures progress.
    func sets(exerciseId: Int, since: ISODate) throws -> [PerformedSet] {
        try db.query("""
            SELECT id, performed_on, weight_kg, reps, is_deload FROM set_logs
            WHERE exercise_id = ? AND performed_on >= ? ORDER BY performed_on, id
            """, [.int(Int64(exerciseId)), .text(since.string)]).compactMap(Self.set)
    }

    func sets(exerciseId: Int, on day: ISODate) throws -> [PerformedSet] {
        try db.query("""
            SELECT id, performed_on, weight_kg, reps, is_deload FROM set_logs
            WHERE exercise_id = ? AND performed_on = ? ORDER BY id
            """, [.int(Int64(exerciseId)), .text(day.string)]).compactMap(Self.set)
    }

    private static func set(_ row: Row) -> PerformedSet? {
        // The schema only checks the text shape, so an impossible date such as 2026-13-45 is skipped rather than crashing.
        guard let date = ISODate(row.text("performed_on")) else { return nil }
        return PerformedSet(id: row.int("id"), date: date, weightKg: row.double("weight_kg"), reps: row.int("reps"),
                            isDeload: row.int("is_deload") == 1)
    }
}

/// Which sets count when measuring progress (working weight, trend, last session, sparkline).
enum ProgressSets {
    static func filter(_ sets: [PerformedSet], ignoreDeload: Bool) -> [PerformedSet] {
        ignoreDeload ? sets.filter { !$0.isDeload } : sets
    }
}
