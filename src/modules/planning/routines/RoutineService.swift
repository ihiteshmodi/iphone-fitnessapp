import Foundation

/// One exercise of a routine or a saved workout day, with what is prescribed for it.
public struct RoutineEntry: Equatable {
    public let exerciseID: Int
    public let sets: Int
    public let minReps: Int
    public let maxReps: Int
    public let warmupSets: Int

    public init(exerciseID: Int, sets: Int, minReps: Int, maxReps: Int, warmupSets: Int = 0) {
        self.exerciseID = exerciseID
        self.sets = sets
        self.minReps = minReps
        self.maxReps = maxReps
        self.warmupSets = warmupSets
    }
}

public struct Routine: Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let isPreset: Bool
    public let entries: [RoutineEntry]
}

/// Ready groups of exercises, like recipes for food: coach presets or your own, pulled into a workout day as a copy.
public final class RoutineService {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    /// Your routines first, then presets, each by name. With a muscle, only routines that train it.
    public func all(muscle: String? = nil) throws -> [Routine] {
        var sql = "SELECT id, name, is_preset FROM routines r"
        var params: [SQLValue] = []
        if let muscle {
            sql += """
                 WHERE EXISTS (SELECT 1 FROM routine_entries x JOIN exercises e ON e.id = x.exercise_id
                               WHERE x.routine_id = r.id AND e.muscle = ? COLLATE NOCASE)
                """
            params.append(.text(muscle))
        }
        sql += " ORDER BY is_preset, name COLLATE NOCASE"
        return try db.query(sql, params).map { row in
            Routine(id: row.int("id"), name: row.text("name"), isPreset: row.int("is_preset") == 1, entries: try entries(of: row.int("id")))
        }
    }

    @discardableResult
    public func create(_ name: String, entries: [RoutineEntry], isPreset: Bool = false) throws -> Int {
        let name = try validName(name, except: nil)
        return try db.transaction {
            try db.execute("INSERT INTO routines (name, is_preset) VALUES (?, ?)", [.text(name), .int(isPreset ? 1 : 0)])
            let id = db.lastInsertRowID
            try insert(entries, into: id)
            return id
        }
    }

    @discardableResult
    public func saveDay(_ dayID: Int, as name: String) throws -> Int {
        let entries = try db.query("SELECT exercise_id, sets, min_reps, max_reps, warmup_sets FROM plan_entries WHERE day_id = ? ORDER BY position, id",
                                   [.int(Int64(dayID))]).map(Self.entry)
        guard !entries.isEmpty else { throw ValidationError("That day has no exercises") }
        return try create(name, entries: entries)
    }

    public func setEntries(_ id: Int, _ entries: [RoutineEntry]) throws {
        try requireEditable(id)
        try db.transaction {
            try db.execute("DELETE FROM routine_entries WHERE routine_id = ?", [.int(Int64(id))])
            try insert(entries, into: id)
        }
    }

    public func rename(_ id: Int, to name: String) throws {
        try requireEditable(id)
        let name = try validName(name, except: id)
        try db.execute("UPDATE routines SET name = ? WHERE id = ?", [.text(name), .int(Int64(id))])
    }

    public func delete(_ id: Int) throws {
        try requireEditable(id)
        try db.execute("DELETE FROM routines WHERE id = ?", [.int(Int64(id))])
    }

    @discardableResult
    public func copy(_ id: Int, as name: String) throws -> Int { try create(name, entries: try entries(of: id)) }

    /// Appends the routine's exercises to the day as a copy, skipping exercises already on it. Returns the skipped names.
    @discardableResult
    public func add(_ id: Int, toDay dayID: Int) throws -> [String] {
        let editor = PlanEditor(db)
        let existing = Set(try db.query("SELECT exercise_id FROM plan_entries WHERE day_id = ?", [.int(Int64(dayID))]).map { $0.int("exercise_id") })
        var skipped: [String] = []
        try db.transaction {
            for entry in try entries(of: id) {
                guard !existing.contains(entry.exerciseID) else {
                    skipped.append(try ExerciseRepository(db).exercise(id: entry.exerciseID)?.name ?? "")
                    continue
                }
                try editor.addExercise(dayId: dayID, exerciseId: entry.exerciseID, sets: entry.sets, minReps: entry.minReps,
                                       maxReps: entry.maxReps, warmupSets: entry.warmupSets)
            }
        }
        return skipped
    }

    // MARK: Private

    private func entries(of id: Int) throws -> [RoutineEntry] {
        try db.query("SELECT exercise_id, sets, min_reps, max_reps, warmup_sets FROM routine_entries WHERE routine_id = ? ORDER BY position",
                     [.int(Int64(id))]).map(Self.entry)
    }

    static func entry(_ row: Row) -> RoutineEntry {
        RoutineEntry(exerciseID: row.int("exercise_id"), sets: row.int("sets"), minReps: row.int("min_reps"), maxReps: row.int("max_reps"),
                     warmupSets: row.int("warmup_sets"))
    }

    private func insert(_ entries: [RoutineEntry], into id: Int) throws {
        for (index, entry) in entries.enumerated() {
            try Self.validate(entry)
            try db.execute("""
                INSERT INTO routine_entries (routine_id, position, exercise_id, sets, min_reps, max_reps, warmup_sets) VALUES (?, ?, ?, ?, ?, ?, ?)
                """, [.int(Int64(id)), .int(Int64(index + 1)), .int(Int64(entry.exerciseID)), .int(Int64(entry.sets)),
                      .int(Int64(entry.minReps)), .int(Int64(entry.maxReps)), .int(Int64(entry.warmupSets))])
        }
    }

    static func validate(_ entry: RoutineEntry) throws {
        guard entry.sets >= 1 else { throw ValidationError("Sets must be at least 1") }
        guard entry.minReps >= 0, entry.minReps <= entry.maxReps else { throw ValidationError("Min reps cannot exceed max reps") }
        guard (0...3).contains(entry.warmupSets) else { throw ValidationError("Warm-up sets must be between 0 and 3") }
    }

    private func requireEditable(_ id: Int) throws {
        guard let row = try db.query("SELECT is_preset FROM routines WHERE id = ?", [.int(Int64(id))]).first else {
            throw ValidationError("That routine is no longer there")
        }
        guard row.int("is_preset") == 0 else { throw ValidationError("Presets cannot be changed; use it or copy it") }
    }

    private func validName(_ name: String, except id: Int?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError("Give the routine a name") }
        if let clash = try db.query("SELECT id FROM routines WHERE name = ? COLLATE NOCASE", [.text(trimmed)]).first, clash.int("id") != id {
            throw ValidationError("A routine with that name already exists")
        }
        return trimmed
    }
}
