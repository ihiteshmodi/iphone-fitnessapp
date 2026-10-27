import Foundation

public enum ExerciseChoice: Equatable {
    case existing(id: Int)
    /// Looked up by name (ignoring case); created in the library with this muscle when it is new.
    case named(String, muscle: String?)
}

public struct SetEntry: Equatable {
    public let weightKg: Double
    public let reps: Int

    public init(weightKg: Double, reps: Int) {
        self.weightKg = weightKg
        self.reps = reps
    }
}

public struct LoggedSet: Equatable, Identifiable {
    public let id: Int
    public let exerciseId: Int
    public let exerciseName: String
    public let date: ISODate
    public let weightKg: Double
    public let reps: Int
}

/// All sets of one exercise on one day.
public struct SetSession: Equatable {
    public let date: ISODate
    public let sets: [LoggedSet]
}

/// Records sets. New sets need at least 1 rep (old imported rows may have 0) and a weight of 0 or more (0 = bodyweight).
public final class LogSets {
    private let db: Database

    private let clock: AppClock?

    public init(_ db: Database, clock: AppClock? = nil) {
        self.db = db
        self.clock = clock
    }

    @discardableResult
    public func logSet(_ exercise: ExerciseChoice, weightKg: Double, reps: Int, on date: String) throws -> Int {
        try logSets(exercise, on: date, sets: [SetEntry(weightKg: weightKg, reps: reps)])[0]
    }

    @discardableResult
    public func logSet(_ exercise: ExerciseChoice, weightKg: Double, reps: Int, on date: ISODate) throws -> Int {
        try logSet(exercise, weightKg: weightKg, reps: reps, on: date.string)
    }

    /// All sets are stored, or none (and no new exercise is created) if any set is invalid.
    @discardableResult
    public func logSets(_ exercise: ExerciseChoice, on date: String, sets: [SetEntry]) throws -> [Int] {
        guard !sets.isEmpty else { throw ValidationError("Log at least one set") }
        for set in sets { try validate(set) }
        let day = try validDay(date)

        return try db.transaction {
            let exerciseId = try resolve(exercise)
            // Remembered per set, so switching deload off later never changes how an old set is treated.
            let duringDeload = try SettingsRepository(db).load().deload.enabled ? 1 : 0
            return try sets.map { set in
                try db.execute("INSERT INTO set_logs (performed_on, exercise_id, weight_kg, reps, is_deload) VALUES (?, ?, ?, ?, ?)",
                               [.text(day.string), .int(Int64(exerciseId)), .double(set.weightKg), .int(Int64(set.reps)), .int(Int64(duringDeload))])
                return db.lastInsertRowID
            }
        }
    }

    @discardableResult
    public func logSets(_ exercise: ExerciseChoice, on date: ISODate, sets: [SetEntry]) throws -> [Int] {
        try logSets(exercise, on: date.string, sets: sets)
    }

    public func deleteSet(id: Int) throws {
        try db.execute("DELETE FROM set_logs WHERE id = ?", [.int(Int64(id))])
    }

    /// Sets logged on one day, in the order they were entered.
    public func sets(on date: ISODate) throws -> [LoggedSet] {
        try db.query("""
            SELECT s.id, s.exercise_id, e.name, s.performed_on, s.weight_kg, s.reps
            FROM set_logs s JOIN exercises e ON e.id = s.exercise_id
            WHERE s.performed_on = ? ORDER BY s.id
            """, [.text(date.string)]).compactMap { row in
            guard let day = ISODate(row.text("performed_on")) else { return nil }
            return LoggedSet(id: row.int("id"), exerciseId: row.int("exercise_id"), exerciseName: row.text("name"),
                             date: day, weightKg: row.double("weight_kg"), reps: row.int("reps"))
        }
    }

    /// Corrects a set in place. Whether it was logged during deload stays as it was.
    public func updateSet(id: Int, weightKg: Double, reps: Int, on date: ISODate) throws {
        try validate(SetEntry(weightKg: weightKg, reps: reps))
        let day = try validDay(date.string)
        guard try db.query("SELECT id FROM set_logs WHERE id = ?", [.int(Int64(id))]).first != nil else {
            throw ValidationError("Set not found")
        }
        try db.execute("UPDATE set_logs SET performed_on = ?, weight_kg = ?, reps = ? WHERE id = ?",
                       [.text(day.string), .double(weightKg), .int(Int64(reps)), .int(Int64(id))])
    }

    /// The most recent training days of one exercise, newest first, leaving out one day (normally today).
    public func sessions(exerciseId: Int, excluding day: ISODate, limit: Int = 20) throws -> [SetSession] {
        let days = try db.query("""
            SELECT DISTINCT performed_on FROM set_logs WHERE exercise_id = ? AND performed_on <> ?
            ORDER BY performed_on DESC LIMIT ?
            """, [.int(Int64(exerciseId)), .text(day.string), .int(Int64(limit))]).compactMap { ISODate($0.text("performed_on")) }
        return try days.map { SetSession(date: $0, sets: try sets(on: $0).filter { $0.exerciseId == exerciseId }) }
    }

    private func validate(_ set: SetEntry) throws {
        guard set.weightKg.isFinite, set.weightKg >= 0 else { throw ValidationError("Weight cannot be negative") }
        guard set.reps >= 1 else { throw ValidationError("Reps must be at least 1") }
    }

    private func validDay(_ text: String) throws -> ISODate {
        guard let day = ISODate(text) else { throw ValidationError("Date is not valid") }
        if let today = clock?.today(), day > today { throw ValidationError("Pick today or an earlier date") }
        return day
    }

    private func resolve(_ choice: ExerciseChoice) throws -> Int {
        let library = ExerciseRepository(db)
        switch choice {
        case .existing(let id):
            guard try library.exercise(id: id) != nil else { throw ValidationError("Exercise not found") }
            return id
        case .named(let name, let muscle):
            if let known = try library.exercise(named: name) { return known.id }
            return try library.add(name: name, muscle: muscle, instructions: nil, source: "user").id
        }
    }
}
