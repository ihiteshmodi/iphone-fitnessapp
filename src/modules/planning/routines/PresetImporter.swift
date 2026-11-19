import Foundation

/// Loads coach routines and workouts from a presets file (kept outside the repository and bundled at build time).
/// Exercises missing from the library are created; timed items such as stretching have no sets and reps, so they are left out.
public final class PresetImporter {
    public struct Result: Equatable {
        public let routines: Int
        public let workouts: Int
    }

    private struct File: Decodable {
        let routines: [Group]
        let workouts: [Workout]
    }

    private struct Group: Decodable {
        let name: String
        let exercises: [Item]
    }

    private struct Workout: Decodable {
        let name: String
        let days: [Day]
    }

    private struct Day: Decodable {
        let title: String?
        let weekday: Int?
        let exercises: [Item]
    }

    private struct Item: Decodable {
        let name: String
        let muscle: String?
        let sets: Int?
        let min_reps: Int?
        let max_reps: Int?
    }

    private let db: Database

    public init(_ db: Database) throws { self.db = db }

    /// Presets whose name already exists are skipped, so loading twice adds nothing.
    public func load(_ data: Data) throws -> Result {
        let file: File
        do { file = try JSONDecoder().decode(File.self, from: data) } catch { throw ValidationError("The presets file could not be read") }
        let routines = RoutineService(db)
        let workouts = SavedWorkoutService(db)
        var added = (routines: 0, workouts: 0)
        for group in file.routines where try !exists("routines", group.name) {
            try routines.create(group.name, entries: try entries(group.exercises), isPreset: true)
            added.routines += 1
        }
        for workout in file.workouts where try !exists("saved_workouts", workout.name) {
            let days = try workout.days.map { SavedWorkoutDayDraft(title: $0.title, weekday: $0.weekday, entries: try entries($0.exercises)) }
            try workouts.addPreset(name: workout.name, days: days)
            added.workouts += 1
        }
        return Result(routines: added.routines, workouts: added.workouts)
    }

    private func exists(_ table: String, _ name: String) throws -> Bool {
        try !db.query("SELECT 1 FROM \(table) WHERE name = ? COLLATE NOCASE", [.text(name)]).isEmpty
    }

    private func entries(_ items: [Item]) throws -> [RoutineEntry] {
        let library = ExerciseRepository(db)
        return try items.compactMap { item in
            guard let sets = item.sets, let minReps = item.min_reps, let maxReps = item.max_reps else { return nil }
            let exercise = try library.exercise(named: item.name) ?? library.add(name: item.name, muscle: item.muscle, instructions: nil)
            return RoutineEntry(exerciseID: exercise.id, sets: sets, minReps: minReps, maxReps: maxReps)
        }
    }
}
