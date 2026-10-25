import Foundation

public struct VolumePoint: Equatable {
    public let date: ISODate
    public let volume: Double
}

public struct ExerciseVolumeSeries: Equatable, Identifiable {
    public var id: Int { exerciseId }
    public let exerciseId: Int
    public let exerciseName: String
    /// Oldest first; one point per day.
    public let points: [VolumePoint]
}

/// One logged set joined with its exercise's library muscle.
public struct SetVolumeRow: Equatable {
    public let exerciseId: Int
    public let exerciseName: String
    public let muscle: String?
    public let date: ISODate
    public let weightKg: Double
    public let reps: Int

    public init(exerciseId: Int, exerciseName: String, muscle: String?, date: ISODate, weightKg: Double, reps: Int) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.muscle = muscle
        self.date = date
        self.weightKg = weightKg
        self.reps = reps
    }
}

/// Pure grouping of set rows into per-muscle, per-exercise volume lines (volume = weight × reps).
public enum MuscleVolume {
    public static let unassigned = "Unassigned"

    public static func muscles(from rows: [SetVolumeRow]) -> [String] {
        var names: [String: String] = [:]
        for row in rows {
            let name = displayName(row.muscle)
            if names[name.lowercased()] == nil { names[name.lowercased()] = name }
        }
        return names.values.sorted { lhs, rhs in
            if (lhs == unassigned) != (rhs == unassigned) { return rhs == unassigned }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    public static func series(muscle: String, from rows: [SetVolumeRow]) -> [ExerciseVolumeSeries] {
        let wanted = displayName(muscle).lowercased()
        let inMuscle = rows.filter { displayName($0.muscle).lowercased() == wanted }
        return Dictionary(grouping: inMuscle, by: \.exerciseId).map { exerciseId, sets in
            let perDay = Dictionary(grouping: sets, by: \.date).map { day, daySets in
                VolumePoint(date: day, volume: daySets.reduce(0) { $0 + $1.weightKg * Double($1.reps) })
            }
            return ExerciseVolumeSeries(exerciseId: exerciseId, exerciseName: sets[0].exerciseName, points: perDay.sorted { $0.date < $1.date })
        }.sorted { $0.exerciseName.localizedCaseInsensitiveCompare($1.exerciseName) == .orderedAscending }
    }

    private static func displayName(_ muscle: String?) -> String {
        let trimmed = muscle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? unassigned : trimmed
    }
}

public final class MuscleVolumeService {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    /// Muscles with at least one set on or after the history start date.
    public func muscles() throws -> [String] { MuscleVolume.muscles(from: try rows()) }

    public func series(muscle: String) throws -> [ExerciseVolumeSeries] { MuscleVolume.series(muscle: muscle, from: try rows()) }

    /// The muscle always comes from the exercise library; `set_logs.logged_muscle` is old-sheet fidelity only.
    private func rows() throws -> [SetVolumeRow] {
        let settings = try SettingsRepository(db).load()
        return try db.query("""
            SELECT e.id, e.name, e.muscle, s.performed_on, s.weight_kg, s.reps
            FROM set_logs s JOIN exercises e ON e.id = s.exercise_id
            WHERE s.performed_on >= ? AND (? = 0 OR s.is_deload = 0)
            """, [.text(settings.historyStartDate.string), .int(settings.ignoreDeloadSessions ? 1 : 0)]).compactMap { row in
            guard let day = ISODate(row.text("performed_on")) else { return nil }
            return SetVolumeRow(exerciseId: row.int("id"), exerciseName: row.text("name"), muscle: row.optionalText("muscle"),
                                date: day, weightKg: row.double("weight_kg"), reps: row.int("reps"))
        }
    }
}
