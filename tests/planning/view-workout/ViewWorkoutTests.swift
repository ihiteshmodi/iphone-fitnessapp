import XCTest
@testable import FitnessCore

/// Scenarios from view-workout.feature. Baseline date is 2026-08-31 (the default setting), "today" is 2026-10-20.
final class ViewWorkoutTests: XCTestCase {
    private var db: Database!
    private var service: WorkoutService!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        service = WorkoutService(db, clock: planningClock())
    }

    private func openOnlyExercise(_ planned: PlannedExercise) throws -> WorkoutExercise {
        let workout = try service.workout(dayId: planned.dayId)
        return try XCTUnwrap(workout.exercises.first)
    }

    // MARK: Heaviest logged set becomes the working weight and warm-ups

    func testHeaviestSetBecomesWorkingWeightAndWarmups() throws {
        let planned = try PlannedExercise.make(db, name: "Triceps Pushdown", muscle: "Triceps", minReps: 6, maxReps: 10)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: 45, reps: 10)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: 40, reps: 12)

        let exercise = try openOnlyExercise(planned)

        XCTAssertEqual(exercise.workingWeight, 45)
        XCTAssertEqual(exercise.warmup75, 33.75)
        XCTAssertEqual(exercise.warmup90, 40.5)
        XCTAssertEqual(exercise.recommendation, .increaseWeight)
        XCTAssertEqual(exercise.repsAtMax, 10)
        XCTAssertEqual(exercise.dateOfMax, date("2026-10-01"))
    }

    // MARK: Recommendation compares reps at the heaviest weight with the plan range

    func testRecommendationComparesRepsAtHeaviestWeightWithPlanRange() throws {
        let rows: [(name: String, min: Int, max: Int, weight: Double, reps: Int, expected: TargetRecommendation)] = [
            ("Triceps Pushdown", 6, 10, 45, 10, .increaseWeight),
            ("Triceps Press", 6, 10, 45, 8, .increaseReps),
            ("Triceps Press", 6, 10, 45, 5, .bringToMaintenance),
        ]
        for (index, row) in rows.enumerated() {
            let database = try Database.inMemory()
            let planned = try PlannedExercise.make(database, name: row.name, minReps: row.min, maxReps: row.max)
            try database.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: row.weight, reps: row.reps)

            let exercise = try XCTUnwrap(try WorkoutService(database, clock: planningClock()).workout(dayId: planned.dayId).exercises.first)

            XCTAssertEqual(exercise.recommendation, row.expected, "row \(index)")
        }
    }

    func testRecommendationRuleOnBoundaries() {
        XCTAssertEqual(TargetRecommendation.judge(repsAtHeaviest: 10, minReps: 6, maxReps: 10), .increaseWeight)
        XCTAssertEqual(TargetRecommendation.judge(repsAtHeaviest: 12, minReps: 6, maxReps: 10), .increaseWeight)
        XCTAssertEqual(TargetRecommendation.judge(repsAtHeaviest: 6, minReps: 6, maxReps: 10), .increaseReps)
        XCTAssertEqual(TargetRecommendation.judge(repsAtHeaviest: 5, minReps: 6, maxReps: 10), .bringToMaintenance)
        XCTAssertEqual(TargetRecommendation.judge(repsAtHeaviest: nil, minReps: 6, maxReps: 10), .noHistory)
    }

    // MARK: A planned exercise with no history since the baseline

    func testNoHistorySinceBaselineHasNoWeightNoWarmupsAndNoHistoryRecommendation() throws {
        let planned = try PlannedExercise.make(db, name: "Squats", muscle: "Legs")
        try db.addSet(exercise: planned.exerciseId, on: "2026-08-30", weight: 100, reps: 5)

        let exercise = try openOnlyExercise(planned)

        XCTAssertNil(exercise.workingWeight)
        XCTAssertNil(exercise.warmup75)
        XCTAssertNil(exercise.warmup90)
        XCTAssertEqual(exercise.recommendation, .noHistory)
        XCTAssertNil(exercise.repsAtMax)
        XCTAssertEqual(exercise.sparkline, [])
    }

    func testSetOnTheBaselineDateCounts() throws {
        let planned = try PlannedExercise.make(db, name: "Squats")
        try db.addSet(exercise: planned.exerciseId, on: "2026-08-31", weight: 100, reps: 5)

        XCTAssertEqual(try openOnlyExercise(planned).workingWeight, 100)
    }

    func testChangingTheBaselineChangesWhichSetsCount() throws {
        let planned = try PlannedExercise.make(db, name: "Squats")
        try db.addSet(exercise: planned.exerciseId, on: "2026-09-10", weight: 100, reps: 5)
        try SettingsRepository(db).setHistoryStartDate("2026-09-11")

        XCTAssertNil(try openOnlyExercise(planned).workingWeight)
    }

    // MARK: Ties are resolved by the heaviest weight, then most reps

    func testHeaviestWeightThenMostRepsWins() throws {
        let planned = try PlannedExercise.make(db, name: "Lat Pulldown", muscle: "Back")
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: 36, reps: 8)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: 36, reps: 10)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: 30, reps: 15)

        let exercise = try openOnlyExercise(planned)

        XCTAssertEqual(exercise.workingWeight, 36)
        XCTAssertEqual(exercise.repsAtMax, 10)
    }

    func testIdenticalWeightAndRepsPicksTheMostRecentDate() {
        let older = PerformedSet(id: 1, date: date("2026-09-01"), weightKg: 36, reps: 10)
        let newer = PerformedSet(id: 2, date: date("2026-10-01"), weightKg: 36, reps: 10)

        XCTAssertEqual(HeaviestSet.of([older, newer]), newer)
        XCTAssertEqual(HeaviestSet.of([newer, older]), newer)
    }

    func testHeaviestSetOfNothingIsNil() {
        XCTAssertNil(HeaviestSet.of([]))
    }

    // MARK: Instructions and muscle come from the exercise library

    func testInstructionsAndMuscleComeFromLibraryNotFromLoggedMuscle() throws {
        let planned = try PlannedExercise.make(db, name: "Chest Dips Machine", muscle: "Chest")
        try db.execute("UPDATE exercises SET instructions = ? WHERE id = ?",
                       [.text("handle inner, squeeze very hard ..."), .int(Int64(planned.exerciseId))])
        try db.execute("INSERT INTO set_logs (performed_on, exercise_id, weight_kg, reps, logged_muscle) VALUES (?, ?, ?, ?, ?)",
                       [.text("2026-10-01"), .int(Int64(planned.exerciseId)), .double(54), .int(8), .text("Wrong Muscle")])

        let exercise = try openOnlyExercise(planned)

        XCTAssertEqual(exercise.muscle, "Chest")
        XCTAssertEqual(exercise.instructions, "handle inner, squeeze very hard ...")
    }

    // MARK: Rounding and working-weight rules ported from the notebook

    func testWorkingWeightIsRoundedLikePythonAndWarmupsDeriveFromTheRoundedValue() throws {
        let planned = try PlannedExercise.make(db, name: "Cable Row")
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: 22.125, reps: 8)

        let exercise = try openOnlyExercise(planned)

        XCTAssertEqual(exercise.workingWeight, 22.12)
        XCTAssertEqual(exercise.warmup75, pyRound(22.12 * 0.75, 2))
        XCTAssertEqual(exercise.warmup90, pyRound(22.12 * 0.90, 2))
    }

    func testTargetCalculatorMatchesNotebookValues() {
        let heaviest = PerformedSet(id: 1, date: date("2026-10-01"), weightKg: 54, reps: 9)
        let target = WorkoutTargetCalculator.target(heaviest: heaviest, minReps: 6, maxReps: 10,
                                                    deload: DeloadSettings(enabled: false, weightMultiplier: 1, repsMultiplier: 0.75))

        XCTAssertEqual(target.workingWeight, 54)
        XCTAssertEqual(target.warmup75, 40.5)
        XCTAssertEqual(target.warmup90, 48.6)
        XCTAssertEqual(target.minReps, 6)
        XCTAssertEqual(target.maxReps, 10)
        XCTAssertEqual(target.recommendation, .increaseReps)
    }

    // MARK: Day picker and day cards (exercise-detail.feature "Pick a day and see its exercises")

    func testDayShowsACardPerExerciseInPlanOrderWithSetsLoggedToday() throws {
        let day = try db.addDay(position: 1)
        var ids: [Int] = []
        for index in 1...16 {
            let exercise = try db.addExercise("Exercise \(index)", muscle: "Chest")
            ids.append(exercise)
            // Inserted in reverse so plan order is positions, not row ids.
            try db.addEntry(day: day, exercise: exercise, position: 17 - index, sets: 3, minReps: 6, maxReps: 10)
        }
        try db.addSet(exercise: ids[15], on: "2026-10-20", weight: 20, reps: 10)
        try db.addSet(exercise: ids[15], on: "2026-10-19", weight: 20, reps: 10)

        let workout = try service.workout(dayId: day)

        XCTAssertEqual(workout.exercises.count, 16)
        XCTAssertEqual(workout.exercises.map(\.name), (1...16).reversed().map { "Exercise \($0)" })
        let first = try XCTUnwrap(workout.exercises.first)
        XCTAssertEqual(first.setsLoggedToday, 1)
        XCTAssertEqual(first.sets, 3)
        XCTAssertEqual(first.muscle, "Chest")
        XCTAssertEqual(workout.exercises.dropFirst().map(\.setsLoggedToday), Array(repeating: 0, count: 15))
    }

    func testSparklineIsBestSetWeightOfTheLastSixSessionsOldestFirst() throws {
        let planned = try PlannedExercise.make(db)
        let weights: [Double] = [40, 42, 44, 46, 48, 50, 52]
        for (index, weight) in weights.enumerated() {
            try db.addSet(exercise: planned.exerciseId, on: "2026-09-\(String(format: "%02d", index + 1))", weight: weight, reps: 8)
            try db.addSet(exercise: planned.exerciseId, on: "2026-09-\(String(format: "%02d", index + 1))", weight: weight - 10, reps: 8)
        }
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-20", weight: 53, reps: 8)

        let exercise = try openOnlyExercise(planned)

        XCTAssertEqual(exercise.sparkline, [44, 46, 48, 50, 52, 53])
    }

    func testDaysListsPlanDaysInOrderWithExerciseCounts() throws {
        let one = try db.addDay(position: 1)
        let two = try db.addDay(position: 2, title: "Pull + Chest")
        _ = try db.addDay(position: 3)
        let exercise = try db.addExercise("Lat Pulldown")
        try db.addEntry(day: two, exercise: exercise)

        let days = try service.days()

        XCTAssertEqual(days.map(\.label), ["Day 1", "Day 2", "Day 3"])
        XCTAssertEqual(days.map(\.exerciseCount), [0, 1, 0])
        XCTAssertEqual(days[1].title, "Pull + Chest")
        XCTAssertNil(days[0].title)
        XCTAssertEqual(days.map(\.id).first, one)
    }

    func testWorkoutOfAnEmptyDayHasNoExercises() throws {
        let day = try db.addDay(position: 1)

        let workout = try service.workout(dayId: day)

        XCTAssertEqual(workout.exercises, [])
        XCTAssertEqual(workout.day.label, "Day 1")
        XCTAssertFalse(workout.isDeload)
    }

    func testOpeningAMissingDayIsRejected() throws {
        XCTAssertThrowsError(try service.workout(dayId: 999)) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Day not found"))
        }
    }

    func testOpeningADayNeverChangesTheDatabase() throws {
        let planned = try PlannedExercise.make(db)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: 54, reps: 8)
        let before = try db.count("set_logs") + db.count("plan_entries")

        _ = try service.workout(dayId: planned.dayId)

        XCTAssertEqual(try db.count("set_logs") + db.count("plan_entries"), before)
    }
}
