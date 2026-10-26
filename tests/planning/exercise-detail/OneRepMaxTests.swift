import XCTest
@testable import FitnessCore

final class OneRepMaxTests: XCTestCase {
    func testEstimatesTheOneRepMaxWithEpley() {
        XCTAssertEqual(OneRepMax.estimate(weightKg: 60, reps: 16), 92, accuracy: 1e-9)
        XCTAssertEqual(OneRepMax.estimate(weightKg: 50, reps: 16), 76.6667, accuracy: 1e-3)
        XCTAssertEqual(OneRepMax.estimate(weightKg: 100, reps: 1), 103.3333, accuracy: 1e-3)
    }

    func testTheNextWeightIsTheOneRepMaxAtTheMinimumRepsRoundedToTheStep() {
        let examples: [(weight: Double, reps: Int, min: Int, next: Double)] = [
            (60, 16, 8, 72.5), (50, 16, 8, 60), (40, 16, 8, 47.5), (60, 16, 14, 62.5),
        ]

        for example in examples {
            XCTAssertEqual(OneRepMax.nextWeight(afterWeightKg: example.weight, reps: example.reps, minReps: example.min), example.next,
                           "\(example.weight) kg × \(example.reps), min \(example.min)")
        }
    }

    func testTheNextWeightRoundsToTheNearestStepNotDown() {
        // 54.0 × 16 = 82.8 at 8 reps gives 65.37, which is nearer 65 than 67.5.
        XCTAssertEqual(OneRepMax.nextWeight(afterWeightKg: 54, reps: 16, minReps: 8), 65)
        XCTAssertEqual(OneRepMax.nextWeight(afterWeightKg: 55, reps: 16, minReps: 8), 67.5)
    }

    func testTheNextWeightIsAlwaysAboveTheWeightJustLifted() {
        // Min reps equal to the reps done: the formula returns the same weight.
        XCTAssertEqual(OneRepMax.nextWeight(afterWeightKg: 60, reps: 10, minReps: 10), 62.5)
        XCTAssertEqual(OneRepMax.nextWeight(afterWeightKg: 60, reps: 8, minReps: 12), 62.5)
    }

    func testAnotherStepSizeCanBeUsed() {
        XCTAssertEqual(OneRepMax.nextWeight(afterWeightKg: 60, reps: 16, minReps: 8, step: 5), 75)
    }

    // MARK: On the exercise screen

    func testTheExerciseScreenKnowsTheBestEstimatedOneRepMaxOfTodaysSets() throws {
        let db = try Database.inMemory()
        let planned = try PlannedExercise.make(db, minReps: 8, maxReps: 16)
        try db.addSet(exercise: planned.exerciseId, on: planningToday.string, weight: 60, reps: 12)
        try db.addSet(exercise: planned.exerciseId, on: planningToday.string, weight: 60, reps: 16)

        let detail = try ExerciseDetailService(db, clock: planningClock()).detail(exerciseId: planned.exerciseId, dayId: planned.dayId)

        XCTAssertEqual(try XCTUnwrap(detail.todayOneRepMax), 92, accuracy: 1e-9)
    }

    func testNoSetsTodayMeansNoEstimate() throws {
        let db = try Database.inMemory()
        let planned = try PlannedExercise.make(db)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: 60, reps: 12)

        let detail = try ExerciseDetailService(db, clock: planningClock()).detail(exerciseId: planned.exerciseId, dayId: planned.dayId)

        XCTAssertNil(detail.todayOneRepMax)
    }
}
