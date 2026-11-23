import XCTest
@testable import FitnessCore

final class SavedWorkoutsTests: XCTestCase {
    private var db: Database!
    private var editor: PlanEditor!
    private var saved: SavedWorkoutService!
    private var bench = 0
    private var row = 0
    private var squat = 0

    override func setUpWithError() throws {
        db = try Database.inMemory()
        editor = PlanEditor(db)
        saved = SavedWorkoutService(db)
        bench = try db.addExercise("Bench press", muscle: "Chest")
        row = try db.addExercise("Row", muscle: "Back")
        squat = try db.addExercise("Squat", muscle: "Quads")
        let push = try db.addDay(position: 1, weekday: 1, title: "Push")
        try db.addEntry(day: push, exercise: bench, sets: 3, minReps: 6, maxReps: 10)
        let pull = try db.addDay(position: 2, weekday: 3, title: "Pull")
        try db.addEntry(day: pull, exercise: row, sets: 3, minReps: 8, maxReps: 12)
    }

    private func planTitles() throws -> [String] {
        try db.query("SELECT title, weekday FROM plan_days ORDER BY position").map { "\($0.text("title"))@\($0.optionalInt("weekday") ?? 0)" }
    }

    func testSavingTheCurrentWorkoutListsItAsCurrent() throws {
        try saved.saveCurrent(as: "PPL Nov 2026", on: date("2026-11-19"))

        let workout = try XCTUnwrap(try saved.all().first)
        XCTAssertEqual(workout.name, "PPL Nov 2026")
        XCTAssertEqual([workout.days.count, workout.exerciseCount], [2, 2])
        XCTAssertTrue(workout.isCurrent)
    }

    func testSwitchingWorkoutsKeepsLoggedHistory() throws {
        let ppl = try saved.saveCurrent(as: "PPL Nov 2026", on: date("2026-11-19"))
        try db.addSet(exercise: bench, on: "2026-11-18", weight: 60, reps: 8)
        let fullBody = try saved.addPreset(name: "Full body", days: [SavedWorkoutDayDraft(title: "Full", weekday: nil, entries: [
            RoutineEntry(exerciseID: squat, sets: 3, minReps: 5, maxReps: 8)])])

        try saved.use(fullBody)
        XCTAssertEqual(try planTitles(), ["Full@0"])
        XCTAssertEqual(try db.count("set_logs"), 1)

        try saved.use(ppl)
        XCTAssertEqual(try planTitles(), ["Push@1", "Pull@3"])
        XCTAssertTrue(try XCTUnwrap(try saved.all().first { $0.id == ppl }).isCurrent)
    }

    func testSavedWorkoutsProvideDayByDayPreviewAndAllowRenamingAndDeletingPresets() throws {
        let preset = try saved.addPreset(name: "Meridian · Upper/Lower", days: [
            SavedWorkoutDayDraft(title: "Upper", weekday: 1, entries: [
                RoutineEntry(exerciseID: bench, sets: 4, minReps: 8, maxReps: 10, warmupSets: 2),
                RoutineEntry(exerciseID: row, sets: 3, minReps: 8, maxReps: 12),
            ]),
        ])

        let detail = try XCTUnwrap(try saved.detail(of: preset))
        XCTAssertEqual(detail.days.count, 1)
        XCTAssertEqual(detail.days[0].title, "Upper")
        XCTAssertEqual(detail.days[0].exercises.map(\.name), ["Bench press", "Row"])
        XCTAssertEqual(detail.days[0].exercises[0].warmupSets, 2)
        XCTAssertTrue(detail.days[0].muscleSummary.contains("Chest 4"))
        XCTAssertTrue(detail.days[0].muscleSummary.contains("Upper back 3"))

        let copy = try saved.copy(preset, as: "My Upper/Lower")
        XCTAssertFalse(try XCTUnwrap(try saved.all().first { $0.id == copy }).isPreset)

        XCTAssertNoThrow(try saved.rename(preset, to: "Meridian · Upper/Lower Edited"))
        XCTAssertEqual(try saved.all().first { $0.id == preset }?.name, "Meridian · Upper/Lower Edited")
        XCTAssertNoThrow(try saved.delete(preset))
        XCTAssertNil(try saved.all().first { $0.id == preset })
    }

    func testNamesAreUnique() throws {
        try saved.saveCurrent(as: "PPL Nov 2026", on: date("2026-11-19"))

        XCTAssertThrowsError(try saved.saveCurrent(as: "ppl nov 2026", on: date("2026-11-19"))) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("A saved workout with that name already exists"))
        }
    }
}
