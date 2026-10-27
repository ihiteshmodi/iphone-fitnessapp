import XCTest
@testable import FitnessCore

final class WarmupSetsTests: XCTestCase {
    private var db: Database!
    private var editor: PlanEditor!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        editor = PlanEditor(db)
    }

    // MARK: Which warm-ups, at what weight

    func testWarmupStepsDependOnHowManyWarmupSetsThereAre() {
        let examples: [(count: Int, steps: [WarmupStep])] = [
            (0, []),
            (1, [WarmupStep(percent: 75, weightKg: 45)]),
            (2, [WarmupStep(percent: 75, weightKg: 45), WarmupStep(percent: 90, weightKg: 54)]),
            (3, [WarmupStep(percent: 60, weightKg: 36), WarmupStep(percent: 75, weightKg: 45), WarmupStep(percent: 90, weightKg: 54)]),
        ]

        for example in examples {
            XCTAssertEqual(WarmupPlan.steps(count: example.count, workingWeight: 60), example.steps, "\(example.count) warm-ups")
        }
    }

    func testWarmupWeightsAreRoundedToTwoDecimals() {
        XCTAssertEqual(WarmupPlan.steps(count: 2, workingWeight: 72.5).map(\.weightKg), [54.38, 65.25])
    }

    func testNoWorkingWeightMeansNoWarmups() {
        XCTAssertEqual(WarmupPlan.steps(count: 2, workingWeight: nil), [])
    }

    // MARK: Plan storage

    func testAnExerciseIsSavedWithItsMainAndWarmupSets() throws {
        let day = try db.addDay(position: 1)
        let exercise = try db.addExercise("Leg Extensions", muscle: "Quads")

        let entry = try editor.addExercise(dayId: day, exerciseId: exercise, sets: 1, minReps: 8, maxReps: 16, warmupSets: 2)

        let row = try XCTUnwrap(try db.query("SELECT sets, warmup_sets FROM plan_entries WHERE id = ?", [.int(Int64(entry))]).first)
        XCTAssertEqual(row.int("sets"), 1)
        XCTAssertEqual(row.int("warmup_sets"), 2)
    }

    func testWarmupSetsDefaultToZero() throws {
        let day = try db.addDay(position: 1)
        let exercise = try db.addExercise("Leg Extensions")

        let entry = try editor.addExercise(dayId: day, exerciseId: exercise, sets: 3, minReps: 6, maxReps: 10)

        XCTAssertEqual(try db.query("SELECT warmup_sets FROM plan_entries WHERE id = ?", [.int(Int64(entry))]).first?.int("warmup_sets"), 0)
    }

    func testChangingAnEntryCanChangeItsWarmupSets() throws {
        let planned = try PlannedExercise.make(db, sets: 1)

        try editor.updateEntry(entryId: planned.entryId, sets: 1, minReps: 6, maxReps: 10, warmupSets: 3)

        XCTAssertEqual(try db.query("SELECT warmup_sets FROM plan_entries WHERE id = ?", [.int(Int64(planned.entryId))]).first?.int("warmup_sets"), 3)
    }

    func testANewExerciseCreatedWhileBuildingAWorkoutCanHaveWarmupSets() throws {
        let day = try db.addDay(position: 1)

        let entry = try editor.createExerciseAndAdd(dayId: day, name: "Cable Crunch", muscle: "Abs", instructions: nil,
                                                    sets: 1, minReps: 10, maxReps: 15, warmupSets: 1)

        XCTAssertEqual(try db.query("SELECT warmup_sets FROM plan_entries WHERE id = ?", [.int(Int64(entry))]).first?.int("warmup_sets"), 1)
    }

    func testWarmupSetsMustBeBetweenZeroAndThree() throws {
        let planned = try PlannedExercise.make(db)

        for count in [0, 3] {
            XCTAssertNoThrow(try editor.updateEntry(entryId: planned.entryId, sets: 1, minReps: 6, maxReps: 10, warmupSets: count))
        }
        for count in [-1, 4] {
            XCTAssertThrowsError(try editor.updateEntry(entryId: planned.entryId, sets: 1, minReps: 6, maxReps: 10, warmupSets: count)) { error in
                XCTAssertEqual(error as? ValidationError, ValidationError("Warm-up sets must be between 0 and 3"))
            }
        }
    }

    // MARK: What the screens get

    func testTheWorkoutCountsOnlyMainSetsAndExposesTheWarmupCount() throws {
        let planned = try PlannedExercise.make(db, sets: 1)
        try editor.updateEntry(entryId: planned.entryId, sets: 1, minReps: 6, maxReps: 10, warmupSets: 2)
        try db.addSet(exercise: planned.exerciseId, on: planningToday.string, weight: 50, reps: 10)

        let exercise = try XCTUnwrap(try WorkoutService(db, clock: planningClock()).workout(dayId: planned.dayId).exercises.first)

        XCTAssertEqual(exercise.sets, 1)
        XCTAssertEqual(exercise.warmupSets, 2)
        XCTAssertTrue(exercise.isDone, "the two warm-ups are not logged, so one logged main set finishes it")
    }

    func testTheExerciseScreenListsTheWarmupsForThePlannedCount() throws {
        let planned = try PlannedExercise.make(db, sets: 1)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: 54, reps: 8)
        try editor.updateEntry(entryId: planned.entryId, sets: 1, minReps: 6, maxReps: 10, warmupSets: 2)

        let target = try ExerciseDetailService(db, clock: planningClock()).detail(exerciseId: planned.exerciseId, dayId: planned.dayId).target

        XCTAssertEqual(target.warmups, [WarmupStep(percent: 75, weightKg: 40.5), WarmupStep(percent: 90, weightKg: 48.6)])
        XCTAssertEqual(target.warmupSets, 2)
    }

    func testAnExerciseWithNoWarmupSetsShowsNone() throws {
        let planned = try PlannedExercise.make(db, sets: 1)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: 54, reps: 8)

        let target = try ExerciseDetailService(db, clock: planningClock()).detail(exerciseId: planned.exerciseId, dayId: planned.dayId).target

        XCTAssertEqual(target.warmups, [])
    }
}
