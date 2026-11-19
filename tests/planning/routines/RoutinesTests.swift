import XCTest
@testable import FitnessCore

final class RoutinesTests: XCTestCase {
    private var db: Database!
    private var routines: RoutineService!
    private var bench = 0
    private var fly = 0
    private var squat = 0
    private var push = 0
    private var day2 = 0

    override func setUpWithError() throws {
        db = try Database.inMemory()
        routines = RoutineService(db)
        bench = try db.addExercise("Bench press", muscle: "Chest")
        fly = try db.addExercise("Fly", muscle: "Chest")
        squat = try db.addExercise("Squat", muscle: "Quads")
        push = try db.addDay(position: 1, title: "Push")
        try db.addEntry(day: push, exercise: bench, position: 1, sets: 3, minReps: 6, maxReps: 10)
        try db.addEntry(day: push, exercise: fly, position: 2, sets: 2, minReps: 10, maxReps: 15)
        day2 = try db.addDay(position: 2, title: "Day 2")
        try db.addEntry(day: day2, exercise: fly, position: 1, sets: 3, minReps: 12, maxReps: 15)
    }

    private func entries(day: Int) throws -> [String] {
        try db.query("SELECT e.name, p.sets, p.min_reps, p.max_reps FROM plan_entries p JOIN exercises e ON e.id = p.exercise_id WHERE day_id = ? ORDER BY position",
                     [.int(Int64(day))]).map { "\($0.text("name")) \($0.int("sets"))x\($0.int("min_reps"))-\($0.int("max_reps"))" }
    }

    func testADayCanBeSavedAsARoutine() throws {
        let id = try routines.saveDay(push, as: "Chest finisher")

        let routine = try XCTUnwrap(try routines.all().first { $0.id == id })
        XCTAssertEqual(routine.entries.map(\.exerciseID), [bench, fly])
        XCTAssertEqual(routine.entries.map(\.sets), [3, 2])
    }

    func testPullingARoutineIntoADaySkipsExercisesAlreadyThereAndStaysIndependent() throws {
        let id = try routines.saveDay(push, as: "Chest finisher")

        let skipped = try routines.add(id, toDay: day2)

        XCTAssertEqual(try entries(day: day2), ["Fly 3x12-15", "Bench press 3x6-10"])
        XCTAssertEqual(skipped, ["Fly"])
        try routines.setEntries(id, [RoutineEntry(exerciseID: squat, sets: 5, minReps: 5, maxReps: 5)])
        XCTAssertEqual(try entries(day: day2), ["Fly 3x12-15", "Bench press 3x6-10"])
    }

    func testRoutinesCanBeBrowsedByMuscle() throws {
        try routines.saveDay(push, as: "Chest finisher")
        try routines.create("Leg day", entries: [RoutineEntry(exerciseID: squat, sets: 3, minReps: 5, maxReps: 8)])

        XCTAssertEqual(try routines.all(muscle: "Chest").map(\.name), ["Chest finisher"])
        XCTAssertEqual(try routines.all().map(\.name), ["Chest finisher", "Leg day"])
    }

    func testCoachPresetsLoadOnceFromThePresetsFile() throws {
        let json = """
        {"routines": [{"name": "Push", "exercises": [
            {"name": "Chest Press (Machine)", "sets": 4, "min_reps": 10, "max_reps": 10},
            {"name": "Stretching (Upper)", "duration": "10 min"}]}],
         "workouts": [{"name": "4-Day Upper/Lower", "days": [{"title": "Upper", "weekday": 1, "exercises": [
            {"name": "Chest Press (Machine)", "sets": 4, "min_reps": 10, "max_reps": 10}]}]}]}
        """
        let presets = try PresetImporter(db)

        let first = try presets.load(Data(json.utf8))
        let again = try presets.load(Data(json.utf8))

        XCTAssertEqual([first.routines, first.workouts], [1, 1])
        XCTAssertEqual([again.routines, again.workouts], [0, 0])
        let routine = try XCTUnwrap(try routines.all().first { $0.name == "Push" })
        XCTAssertTrue(routine.isPreset)
        XCTAssertEqual(routine.entries.count, 1, "timed stretching is left out")
        XCTAssertEqual([routine.entries[0].sets, routine.entries[0].minReps, routine.entries[0].maxReps], [4, 10, 10])
        XCTAssertNotNil(try ExerciseRepository(db).exercise(named: "Chest Press (Machine)"))
        XCTAssertEqual(try SavedWorkoutService(db).all().filter(\.isPreset).map(\.name), ["4-Day Upper/Lower"])
    }
}
