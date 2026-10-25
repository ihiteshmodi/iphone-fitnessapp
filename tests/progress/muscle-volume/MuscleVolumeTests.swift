import XCTest
@testable import FitnessCore

final class MuscleVolumeTests: XCTestCase {
    private var db: Database!
    private var service: MuscleVolumeService!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        service = MuscleVolumeService(db)
    }

    func testOneLinePerExerciseWithinAMuscle() throws {
        let pushdown = try db.addExercise("Triceps Pushdown", muscle: "Triceps")
        let press = try db.addExercise("Triceps Press", muscle: "Triceps")
        try db.addSet(exercise: pushdown, on: "2026-10-09", weight: 40, reps: 10)
        try db.addSet(exercise: pushdown, on: "2026-10-16", weight: 45, reps: 10)
        try db.addSet(exercise: press, on: "2026-10-16", weight: 20, reps: 10)

        let series = try service.series(muscle: "Triceps")

        XCTAssertEqual(series.map(\.exerciseName), ["Triceps Press", "Triceps Pushdown"])
        XCTAssertEqual(series.last?.points, [VolumePoint(date: date("2026-10-09"), volume: 400), VolumePoint(date: date("2026-10-16"), volume: 450)])
        XCTAssertEqual(series.first?.points, [VolumePoint(date: date("2026-10-16"), volume: 200)])
    }

    func testVolumeIsTheSumOfWeightTimesRepsForTheSession() throws {
        let pushdown = try db.addExercise("Triceps Pushdown", muscle: "Triceps")
        try db.addSet(exercise: pushdown, on: "2026-10-16", weight: 45, reps: 10)
        try db.addSet(exercise: pushdown, on: "2026-10-16", weight: 40, reps: 12)

        let point = try XCTUnwrap(try service.series(muscle: "Triceps").first?.points.first)

        XCTAssertEqual(point, VolumePoint(date: date("2026-10-16"), volume: 930))
    }

    func testMusclesComeFromTheLibraryNotFromOldLogLabels() throws {
        let squats = try db.addExercise("Squats", muscle: "Quads")
        try db.addSet(exercise: squats, on: "2026-10-16", weight: 100, reps: 5)
        try db.execute("UPDATE set_logs SET logged_muscle = 'Legs'")

        XCTAssertEqual(try service.muscles(), ["Quads"])
        XCTAssertEqual(try service.series(muscle: "Quads").map(\.exerciseName), ["Squats"])
        XCTAssertEqual(try service.series(muscle: "Legs"), [])
    }

    func testAMuscleWithNoDataSinceTheBaselineIsNotListed() throws {
        let shins = try db.addExercise("Tibialis Raise", muscle: "Shins")
        let squats = try db.addExercise("Squats", muscle: "Quads")
        try db.addSet(exercise: shins, on: "2026-08-30", weight: 20, reps: 10)
        try db.addSet(exercise: squats, on: "2026-08-31", weight: 100, reps: 5)
        _ = try db.addExercise("Calf Raise", muscle: "Calves")

        XCTAssertEqual(try service.muscles(), ["Quads"])
        XCTAssertEqual(try service.series(muscle: "Shins"), [])
    }

    func testOnlySetsOnOrAfterTheHistoryStartDateCount() throws {
        let squats = try db.addExercise("Squats", muscle: "Quads")
        try db.addSet(exercise: squats, on: "2026-08-30", weight: 100, reps: 5)
        try db.addSet(exercise: squats, on: "2026-09-10", weight: 100, reps: 5)
        try SettingsRepository(db).setHistoryStartDate("2026-09-01")

        XCTAssertEqual(try service.series(muscle: "Quads").first?.points.map(\.date), [date("2026-09-10")])

        try SettingsRepository(db).setHistoryStartDate("2026-08-01")

        XCTAssertEqual(try service.series(muscle: "Quads").first?.points.count, 2)
    }

    func testExercisesWithoutAMuscleAreGroupedAsUnassignedOnlyWhenTheyHaveData() throws {
        let mystery = try db.addExercise("Mystery Move")
        _ = try db.addExercise("Unused Move")
        try db.addSet(exercise: mystery, on: "2026-10-16", weight: 10, reps: 10)
        let squats = try db.addExercise("Squats", muscle: "Quads")
        try db.addSet(exercise: squats, on: "2026-10-16", weight: 100, reps: 5)

        XCTAssertEqual(try service.muscles(), ["Quads", "Unassigned"])
        XCTAssertEqual(try service.series(muscle: "Unassigned").map(\.exerciseName), ["Mystery Move"])
    }

    func testMuscleNamesMatchIgnoringCase() throws {
        let pushdown = try db.addExercise("Triceps Pushdown", muscle: "Triceps")
        let press = try db.addExercise("Triceps Press", muscle: "triceps")
        try db.addSet(exercise: pushdown, on: "2026-10-16", weight: 40, reps: 10)
        try db.addSet(exercise: press, on: "2026-10-16", weight: 20, reps: 10)

        XCTAssertEqual(try service.muscles().count, 1)
        XCTAssertEqual(try service.series(muscle: "TRICEPS").count, 2)
    }

    func testBodyweightSetsContributeZeroVolumeButTheMuscleIsListed() throws {
        let pushUps = try db.addExercise("Push Ups", muscle: "Chest")
        try db.addSet(exercise: pushUps, on: "2026-10-16", weight: 0, reps: 20)

        XCTAssertEqual(try service.muscles(), ["Chest"])
        XCTAssertEqual(try service.series(muscle: "Chest").first?.points.map(\.volume), [0])
    }

    func testPureAggregationNeedsNoDatabase() {
        let rows = [
            SetVolumeRow(exerciseId: 1, exerciseName: "A", muscle: "Back", date: date("2026-10-02"), weightKg: 10, reps: 5),
            SetVolumeRow(exerciseId: 1, exerciseName: "A", muscle: "Back", date: date("2026-10-01"), weightKg: 10, reps: 5),
            SetVolumeRow(exerciseId: 1, exerciseName: "A", muscle: "Back", date: date("2026-10-02"), weightKg: 20, reps: 1),
        ]

        let series = MuscleVolume.series(muscle: "Back", from: rows)

        XCTAssertEqual(series.first?.points, [VolumePoint(date: date("2026-10-01"), volume: 50), VolumePoint(date: date("2026-10-02"), volume: 70)])
        XCTAssertEqual(MuscleVolume.muscles(from: rows), ["Back"])
    }
}
