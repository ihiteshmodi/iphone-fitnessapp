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

    /// Your routines first, then presets, each by name. With a muscle, includes any routine whose exercises train that muscle group or anatomy region.
    public func all(muscle: String? = nil) throws -> [Routine] {
        let allRoutines = try db.query("SELECT id, name, is_preset FROM routines ORDER BY is_preset, name COLLATE NOCASE").map { row in
            Routine(id: row.int("id"), name: row.text("name"), isPreset: row.int("is_preset") == 1, entries: try entries(of: row.int("id")))
        }
        guard let muscle, !muscle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return allRoutines
        }
        let exercisesRepo = ExerciseRepository(db)
        let muscleService = ExerciseMuscleService(db)
        return try allRoutines.filter { routine in
            try routine.entries.contains { entry in
                guard let exercise = try exercisesRepo.exercise(id: entry.exerciseID) else { return false }
                return try Self.exerciseMatches(exercise: exercise, filter: muscle, muscleService: muscleService)
            }
        }
    }

    /// Filter chips shown in Routines: library muscle labels plus canonical group filters trained by existing routines.
    public func filterMuscles() throws -> [String] {
        var seen: [String: String] = [:]
        for label in ["Back", "Chest", "Shoulders", "Arms", "Legs"] + (try ExerciseRepository(db).muscles()) {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.uppercased() != "HIIT", trimmed.uppercased() != "HOLD" else { continue }
            let key = trimmed.lowercased()
            if seen[key] == nil { seen[key] = trimmed }
        }
        return seen.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @discardableResult
    public func create(_ name: String, entries: [RoutineEntry], isPreset: Bool = false) throws -> Int {
        guard !entries.isEmpty else { throw ValidationError("Add at least one exercise to the routine") }
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
        try requireExists(id)
        guard !entries.isEmpty else { throw ValidationError("Add at least one exercise to the routine") }
        try db.transaction {
            try db.execute("DELETE FROM routine_entries WHERE routine_id = ?", [.int(Int64(id))])
            try insert(entries, into: id)
        }
    }

    public func rename(_ id: Int, to name: String) throws {
        try requireExists(id)
        let name = try validName(name, except: id)
        try db.execute("UPDATE routines SET name = ? WHERE id = ?", [.text(name), .int(Int64(id))])
    }

    public func delete(_ id: Int) throws {
        try requireExists(id)
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

    private func requireExists(_ id: Int) throws {
        guard !(try db.query("SELECT 1 FROM routines WHERE id = ?", [.int(Int64(id))])).isEmpty else {
            throw ValidationError("That routine is no longer there")
        }
    }

    private static func exerciseMatches(exercise: Exercise, filter: String, muscleService: ExerciseMuscleService) throws -> Bool {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let raw = exercise.muscle {
            if raw.lowercased() == needle { return true }
            let parts = raw.lowercased().split(whereSeparator: { $0 == "&" || $0 == "/" || $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.contains(needle) { return true }
        }
        let assignments = try muscleService.muscles(exerciseId: exercise.id).assignments.filter { $0.role == .primary }
        let regions = Set(assignments.map(\.part.region))
        let primaryParts = Set(assignments.map(\.part))
        switch needle {
        case "chest": return regions.contains(.chest)
        case "shoulders": return regions.contains(.shoulders)
        case "back", "mid back", "upper back", "lower back": return regions.contains(.upperBack) || regions.contains(.lowerBack)
        case "lats": return primaryParts.contains(.lats)
        case "traps": return !primaryParts.isDisjoint(with: [.trapsUpper, .trapsMid, .trapsLower])
        case "arms": return !regions.isDisjoint(with: [.biceps, .triceps, .forearms])
        case "biceps": return regions.contains(.biceps)
        case "triceps": return regions.contains(.triceps)
        case "forearm", "forearms": return regions.contains(.forearms)
        case "abs", "core": return regions.contains(.core)
        case "legs": return !regions.isDisjoint(with: [.quads, .hamstrings, .glutes, .hips, .calves, .shins])
        case "quads": return regions.contains(.quads)
        case "hamstrings": return regions.contains(.hamstrings)
        case "glutes": return regions.contains(.glutes)
        case "hips", "abductors", "adductors": return regions.contains(.hips)
        case "calves": return regions.contains(.calves)
        case "shins": return regions.contains(.shins)
        default:
            return regions.contains { $0.displayName.lowercased() == needle }
        }
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
