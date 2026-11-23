import Foundation

public struct SavedWorkoutDayDraft: Equatable {
    public let title: String?
    public let weekday: Int?
    public let entries: [RoutineEntry]

    public init(title: String?, weekday: Int?, entries: [RoutineEntry]) {
        self.title = title
        self.weekday = weekday
        self.entries = entries
    }
}

public struct SavedWorkout: Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let savedOn: ISODate
    public let isPreset: Bool
    public let days: [SavedWorkoutDayDraft]
    /// True when the workout plan right now has exactly these days and exercises.
    public let isCurrent: Bool

    public var exerciseCount: Int { days.reduce(0) { $0 + $1.entries.count } }
}

public struct SavedWorkoutExerciseDetail: Equatable, Identifiable {
    public var id: Int { exerciseID }
    public let exerciseID: Int
    public let name: String
    public let sets: Int
    public let minReps: Int
    public let maxReps: Int
    public let warmupSets: Int
    public let primaryMuscles: [String]
}

public struct SavedWorkoutDayDetail: Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let weekday: Int?
    public let exercises: [SavedWorkoutExerciseDetail]
    public let muscleSummary: String
}

public struct SavedWorkoutDetail: Equatable {
    public let workout: SavedWorkout
    public let days: [SavedWorkoutDayDetail]
}

/// Whole workouts kept under a name. Using one replaces the workout plan; logged sets belong to exercises, so no
/// history is lost and working weights carry over.
public final class SavedWorkoutService {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    /// Your workouts first, then presets, each by name.
    public func all() throws -> [SavedWorkout] {
        let current = try currentDays()
        return try db.query("SELECT id, name, saved_on, is_preset FROM saved_workouts ORDER BY is_preset, name COLLATE NOCASE").compactMap { row in
            guard let savedOn = ISODate(row.text("saved_on")) else { return nil }
            let days = try self.days(of: row.int("id"))
            return SavedWorkout(id: row.int("id"), name: row.text("name"), savedOn: savedOn, isPreset: row.int("is_preset") == 1,
                                days: days, isCurrent: days == current)
        }
    }

    @discardableResult
    public func saveCurrent(as name: String, on day: ISODate) throws -> Int {
        let days = try currentDays()
        guard !days.isEmpty else { throw ValidationError("The workout plan has no days to save") }
        return try insert(name: name, days: days, savedOn: day, isPreset: false)
    }

    @discardableResult
    public func addPreset(name: String, days: [SavedWorkoutDayDraft], on day: ISODate = ISODate("2000-01-01")!) throws -> Int {
        try insert(name: name, days: days, savedOn: day, isPreset: true)
    }

    /// The workout plan becomes this workout.
    public func use(_ id: Int) throws {
        let days = try days(of: id)
        try db.transaction {
            try db.execute("DELETE FROM plan_days")
            for (index, day) in days.enumerated() {
                try db.execute("INSERT INTO plan_days (position, weekday, title) VALUES (?, ?, ?)",
                               [.int(Int64(index + 1)), .optional(day.weekday), .optional(day.title)])
                let dayID = db.lastInsertRowID
                for (position, entry) in day.entries.enumerated() {
                    try db.execute("""
                        INSERT INTO plan_entries (day_id, position, exercise_id, sets, min_reps, max_reps, warmup_sets) VALUES (?, ?, ?, ?, ?, ?, ?)
                        """, [.int(Int64(dayID)), .int(Int64(position + 1)), .int(Int64(entry.exerciseID)), .int(Int64(entry.sets)),
                              .int(Int64(entry.minReps)), .int(Int64(entry.maxReps)), .int(Int64(entry.warmupSets))])
                }
            }
        }
    }

    @discardableResult
    public func copy(_ id: Int, as name: String, on day: ISODate = ISODate("2000-01-01")!) throws -> Int {
        try insert(name: name, days: try days(of: id), savedOn: day, isPreset: false)
    }

    public func detail(of id: Int) throws -> SavedWorkoutDetail? {
        guard let workout = try all().first(where: { $0.id == id }) else { return nil }
        let exercisesRepo = ExerciseRepository(db)
        let muscleService = ExerciseMuscleService(db)
        let detailedDays: [SavedWorkoutDayDetail] = try workout.days.enumerated().map { index, day in
            var regionSets: [MuscleRegion: Int] = [:]
            let exDetails: [SavedWorkoutExerciseDetail] = try day.entries.map { entry in
                let exercise = try exercisesRepo.exercise(id: entry.exerciseID)
                let regions: [MuscleRegion]
                if let exercise {
                    let parts = try muscleService.muscles(exerciseId: exercise.id).assignments.filter { $0.role == .primary }.map(\.part.region)
                    regions = MuscleRegion.allCases.filter { parts.contains($0) }
                } else {
                    regions = []
                }
                for region in regions { regionSets[region, default: 0] += entry.sets }
                return SavedWorkoutExerciseDetail(
                    exerciseID: entry.exerciseID,
                    name: exercise?.name ?? "Exercise",
                    sets: entry.sets,
                    minReps: entry.minReps,
                    maxReps: entry.maxReps,
                    warmupSets: entry.warmupSets,
                    primaryMuscles: regions.map(\.displayName))
            }
            let summary = MuscleRegion.allCases
                .compactMap { region -> String? in
                    guard let n = regionSets[region], n > 0 else { return nil }
                    return "\(region.displayName) \(n)"
                }
                .joined(separator: " · ")
            return SavedWorkoutDayDetail(
                id: index + 1,
                title: day.title ?? "Day \(index + 1)",
                weekday: day.weekday,
                exercises: exDetails,
                muscleSummary: summary)
        }
        return SavedWorkoutDetail(workout: workout, days: detailedDays)
    }

    public func rename(_ id: Int, to name: String) throws {
        try requireExists(id)
        let name = try validName(name, except: id)
        try db.execute("UPDATE saved_workouts SET name = ? WHERE id = ?", [.text(name), .int(Int64(id))])
    }

    public func delete(_ id: Int) throws {
        try requireExists(id)
        try db.execute("DELETE FROM saved_workouts WHERE id = ?", [.int(Int64(id))])
    }

    // MARK: Private

    private func currentDays() throws -> [SavedWorkoutDayDraft] {
        try db.query("SELECT id, weekday, title FROM plan_days ORDER BY position").map { row in
            let entries = try db.query("SELECT exercise_id, sets, min_reps, max_reps, warmup_sets FROM plan_entries WHERE day_id = ? ORDER BY position, id",
                                       [.int(Int64(row.int("id")))]).map(RoutineService.entry)
            return SavedWorkoutDayDraft(title: row.optionalText("title"), weekday: row.optionalInt("weekday"), entries: entries)
        }
    }

    private func days(of id: Int) throws -> [SavedWorkoutDayDraft] {
        try db.query("SELECT id, weekday, title FROM saved_workout_days WHERE workout_id = ? ORDER BY position", [.int(Int64(id))]).map { row in
            let entries = try db.query("SELECT exercise_id, sets, min_reps, max_reps, warmup_sets FROM saved_workout_entries WHERE day_id = ? ORDER BY position",
                                       [.int(Int64(row.int("id")))]).map(RoutineService.entry)
            return SavedWorkoutDayDraft(title: row.optionalText("title"), weekday: row.optionalInt("weekday"), entries: entries)
        }
    }

    private func insert(name: String, days: [SavedWorkoutDayDraft], savedOn: ISODate, isPreset: Bool) throws -> Int {
        let name = try validName(name, except: nil)
        return try db.transaction {
            try db.execute("INSERT INTO saved_workouts (name, saved_on, is_preset) VALUES (?, ?, ?)",
                           [.text(name), .text(savedOn.string), .int(isPreset ? 1 : 0)])
            let id = db.lastInsertRowID
            for (index, day) in days.enumerated() {
                try db.execute("INSERT INTO saved_workout_days (workout_id, position, weekday, title) VALUES (?, ?, ?, ?)",
                               [.int(Int64(id)), .int(Int64(index + 1)), .optional(day.weekday), .optional(day.title)])
                let dayID = db.lastInsertRowID
                for (position, entry) in day.entries.enumerated() {
                    try RoutineService.validate(entry)
                    try db.execute("""
                        INSERT INTO saved_workout_entries (day_id, position, exercise_id, sets, min_reps, max_reps, warmup_sets) VALUES (?, ?, ?, ?, ?, ?, ?)
                        """, [.int(Int64(dayID)), .int(Int64(position + 1)), .int(Int64(entry.exerciseID)), .int(Int64(entry.sets)),
                              .int(Int64(entry.minReps)), .int(Int64(entry.maxReps)), .int(Int64(entry.warmupSets))])
                }
            }
            return id
        }
    }

    private func requireExists(_ id: Int) throws {
        guard !(try db.query("SELECT 1 FROM saved_workouts WHERE id = ?", [.int(Int64(id))])).isEmpty else {
            throw ValidationError("That saved workout is no longer there")
        }
    }

    private func validName(_ name: String, except id: Int?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError("Give the workout a name") }
        if let clash = try db.query("SELECT id FROM saved_workouts WHERE name = ? COLLATE NOCASE", [.text(trimmed)]).first, clash.int("id") != id {
            throw ValidationError("A saved workout with that name already exists")
        }
        return trimmed
    }
}
