import XCTest
@testable import FitnessCore

/// Scenarios from exercise-detail.feature. Baseline 2026-08-31, today 2026-10-20.
final class ExerciseDetailTests: XCTestCase {
    private var db: Database!
    private var service: ExerciseDetailService!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        service = ExerciseDetailService(db, clock: planningClock())
    }

    @discardableResult
    private func chestDipsWithLastSession() throws -> PlannedExercise {
        let planned = try PlannedExercise.make(db, name: "Chest Dips Machine", muscle: "Chest", minReps: 6, maxReps: 10, sets: 3)
        try db.execute("UPDATE exercises SET instructions = ? WHERE id = ?",
                       [.text("handle inner, squeeze very hard ..."), .int(Int64(planned.exerciseId))])
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-18", weight: 54, reps: 9)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-18", weight: 54, reps: 8)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-18", weight: 54, reps: 8)
        return planned
    }

    private func detail(_ planned: PlannedExercise) throws -> ExerciseDetail {
        try service.detail(exerciseId: planned.exerciseId, dayId: planned.dayId)
    }

    // MARK: Open an exercise and see everything needed to train

    func testTargetShowsWorkingWeightWarmupsRepRangeAndSets() throws {
        let result = try detail(try chestDipsWithLastSession())

        XCTAssertEqual(result.target.workingWeight, 54)
        XCTAssertEqual(result.target.warmup75, 40.5)
        XCTAssertEqual(result.target.warmup90, 48.6)
        XCTAssertEqual(result.target.minReps, 6)
        XCTAssertEqual(result.target.maxReps, 10)
        XCTAssertEqual(result.target.sets, 3)
        XCTAssertEqual(result.targetSets, 3)
        XCTAssertEqual(result.target.recommendation, .increaseReps)
        XCTAssertTrue(result.hasHistory)
    }

    func testLastSessionShowsItsDateAndSets() throws {
        let result = try detail(try chestDipsWithLastSession())

        let last = try XCTUnwrap(result.lastSession)
        XCTAssertEqual(last.date, date("2026-10-18"))
        XCTAssertEqual(last.sets.map(\.weightKg), [54, 54, 54])
        XCTAssertEqual(last.sets.map(\.reps), [9, 8, 8])
    }

    func testAimTellsToBeatTheRepsOfTheLastSessionAtTheWorkingWeight() throws {
        let result = try detail(try chestDipsWithLastSession())

        XCTAssertEqual(result.aim, "Increase reps: beat 9 reps at 54 kg")
    }

    func testAimFallsBackToTheBestRepsAtTheWorkingWeightWhenLastSessionWasLighter() throws {
        let planned = try PlannedExercise.make(db)
        try db.addSet(exercise: planned.exerciseId, on: "2026-09-10", weight: 54, reps: 9)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-18", weight: 50, reps: 12)

        XCTAssertEqual(try detail(planned).aim, "Increase reps: beat 9 reps at 54 kg")
    }

    func testAimAtTheTopOfTheRangeIsIncreaseWeightWithTheNextWeight() throws {
        let planned = try PlannedExercise.make(db)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-18", weight: 54, reps: 10)

        // 54 x 10 gives a 1RM of 72; at the minimum 6 reps that is 60 kg.
        XCTAssertEqual(try detail(planned).aim, "Increase weight: go to 60 kg")
    }

    func testAimBelowTheRangeIsBringToMaintenance() throws {
        let planned = try PlannedExercise.make(db)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-18", weight: 54, reps: 5)

        XCTAssertEqual(try detail(planned).aim, "Bring to maintenance: reach 6 reps at 54 kg")
    }

    func testAimUsesTheDeloadTargetAndHidesTheRecommendation() throws {
        let planned = try chestDipsWithLastSession()
        try setDeload(db, enabled: true, weightMultiplier: 0.8, repsMultiplier: 0.75)

        let result = try detail(planned)

        XCTAssertTrue(result.isDeload)
        XCTAssertNil(result.target.recommendation)
        XCTAssertEqual(result.target.workingWeight, 43.2)
        XCTAssertEqual(result.target.minReps, 4.5)
        XCTAssertEqual(result.target.maxReps, 7.5)
        XCTAssertEqual(result.aim, "Deload: 4.5 to 7.5 reps at 43.2 kg")
    }

    func testHowToInstructionsComeFromTheLibrary() throws {
        let result = try detail(try chestDipsWithLastSession())

        XCTAssertEqual(result.exercise.instructions, "handle inner, squeeze very hard ...")
        XCTAssertEqual(result.exercise.muscle, "Chest")
    }

    func testProgressChartListsSessionsOldestFirstWithBestSetAndEstimate() throws {
        let planned = try chestDipsWithLastSession()
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-11", weight: 52, reps: 10)

        let sessions = try detail(planned).sessions

        XCTAssertEqual(sessions.map(\.date), [date("2026-10-11"), date("2026-10-18")])
        XCTAssertEqual(sessions[1].best.weightKg, 54)
        XCTAssertEqual(sessions[1].best.reps, 9)
        XCTAssertEqual(sessions[1].estimatedOneRepMax, 54 * (1 + 9.0 / 30), accuracy: 0.0001)
    }

    func testChartKeepsOnlyTheLastSixSessionsAndHistoryIsNewestFirst() throws {
        let planned = try PlannedExercise.make(db)
        for day in 1...12 {
            try db.addSet(exercise: planned.exerciseId, on: String(format: "2026-10-%02d", day), weight: Double(40 + day), reps: 8)
        }

        let result = try detail(planned)

        XCTAssertEqual(result.sessions.map(\.date.string), (7...12).map { String(format: "2026-10-%02d", $0) })
        XCTAssertEqual(result.history.first?.date, date("2026-10-12"))
        XCTAssertEqual(result.history.map(\.date), result.history.map(\.date).sorted(by: >))
        XCTAssertEqual(result.history.count, 10)
    }

    // MARK: Trend

    func testTrendOfTheLastSessionsFollowsEstimatedOneRepMax() throws {
        let rows: [(series: [Double], trend: String)] = [
            ([60, 62, 64, 66], "Improving"),
            ([60, 60.5, 59.8, 60.2], "Flat"),
            ([66, 64, 62, 60], "Declining"),
            ([60], "Not enough data"),
            ([], "Not enough data"),
        ]
        for row in rows {
            let database = try Database.inMemory()
            let planned = try PlannedExercise.make(database)
            // 30 reps doubles the weight in the Epley formula, so the estimate is exactly the series value.
            for (index, estimate) in row.series.enumerated() {
                try database.addSet(exercise: planned.exerciseId, on: String(format: "2026-10-%02d", index + 1), weight: estimate / 2, reps: 30)
            }

            let result = try ExerciseDetailService(database, clock: planningClock()).detail(exerciseId: planned.exerciseId, dayId: planned.dayId)

            XCTAssertEqual(result.trend.label, row.trend, "series \(row.series)")
        }
    }

    // MARK: Logging from inside the exercise

    func testSetLoggedTodayShowsInTodaySetsAndAddsAChartPoint() throws {
        let planned = try chestDipsWithLastSession()
        let before = try detail(planned)

        let setId = try db.addSet(exercise: planned.exerciseId, on: "2026-10-20", weight: 54, reps: 9)
        let after = try detail(planned)

        XCTAssertEqual(before.todaySets, [])
        XCTAssertEqual(after.todaySets, [PerformedSet(id: setId, date: planningToday, weightKg: 54, reps: 9)])
        XCTAssertEqual(after.sessions.count, before.sessions.count + 1)
        XCTAssertEqual(after.sessions.last?.date, planningToday)
        XCTAssertEqual(after.sessions.last?.best.reps, 9)
        XCTAssertEqual(after.targetSets, 3)
    }

    func testLastSessionIsTheNewestBeforeTodayEvenWhenSetsExistToday() throws {
        let planned = try chestDipsWithLastSession()
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-20", weight: 55, reps: 6)

        let result = try detail(planned)

        XCTAssertEqual(result.lastSession?.date, date("2026-10-18"))
        XCTAssertEqual(result.history.map(\.date), [date("2026-10-18")])
    }

    func testSetFormIsPrefilledWithWorkingWeightAndTheMiddleOfTheRepRange() throws {
        let result = try detail(try chestDipsWithLastSession())

        XCTAssertEqual(result.prefill, SetFormPrefill(weightKg: 54, reps: 8))
    }

    func testTheMiddleRepsFollowTheRepRangeShownDuringDeload() throws {
        let planned = try PlannedExercise.make(db, minReps: 8, maxReps: 16)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: 60, reps: 12)
        try setDeload(db, enabled: true, repsMultiplier: 0.75)

        XCTAssertEqual(try detail(planned).prefill.reps, 9, "6 to 12 reps are shown, so the middle is 9")
    }

    func testDeletingAMistakenSetRemovesItFromTheCardAndChart() throws {
        let planned = try chestDipsWithLastSession()
        let mistake = try db.addSet(exercise: planned.exerciseId, on: "2026-10-20", weight: 540, reps: 9)
        XCTAssertEqual(try detail(planned).target.workingWeight, 540)

        try db.execute("DELETE FROM set_logs WHERE id = ?", [.int(Int64(mistake))])
        let result = try detail(planned)

        XCTAssertEqual(result.todaySets, [])
        XCTAssertEqual(result.target.workingWeight, 54)
        XCTAssertEqual(result.sessions.map(\.date), [date("2026-10-18")])
    }

    // MARK: No history, edge cases

    func testExerciseWithNoHistoryShowsNoHistoryYetAndCanStillLogAFirstSet() throws {
        let planned = try PlannedExercise.make(db, name: "Squats", muscle: "Legs", minReps: 6, maxReps: 10)
        try db.addSet(exercise: planned.exerciseId, on: "2026-08-30", weight: 100, reps: 5)

        let result = try detail(planned)

        XCTAssertFalse(result.hasHistory)
        XCTAssertEqual(result.aim, "No history yet")
        XCTAssertEqual(result.trend.label, "Not enough data")
        XCTAssertNil(result.lastSession)
        XCTAssertNil(result.target.workingWeight)
        XCTAssertEqual(result.sessions, [])
        XCTAssertEqual(result.prefill, SetFormPrefill(weightKg: nil, reps: 8))
    }

    func testAnExerciseThatIsNotOnTheDayIsRejected() throws {
        let planned = try PlannedExercise.make(db)
        let other = try db.addExercise("Squats")

        XCTAssertThrowsError(try service.detail(exerciseId: other, dayId: planned.dayId)) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Exercise is not planned on this day"))
        }
    }

    // MARK: Edit the instructions from the exercise screen

    func testEditedInstructionsShowEverywhereTheExerciseIsUsed() throws {
        let planned = try chestDipsWithLastSession()
        let secondDay = try db.addDay(position: 2)
        try db.addEntry(day: secondDay, exercise: planned.exerciseId)

        try service.updateInstructions(exerciseId: planned.exerciseId, instructions: "handle inner, pause at the bottom")

        let workout = WorkoutService(db, clock: planningClock())
        XCTAssertEqual(try detail(planned).exercise.instructions, "handle inner, pause at the bottom")
        XCTAssertEqual(try workout.workout(dayId: planned.dayId).exercises.first?.instructions, "handle inner, pause at the bottom")
        XCTAssertEqual(try workout.workout(dayId: secondDay).exercises.first?.instructions, "handle inner, pause at the bottom")
        XCTAssertEqual(try ExerciseRepository(db).exercise(id: planned.exerciseId)?.name, "Chest Dips Machine")
    }

    func testClearingInstructionsLeavesNameAndMuscleAlone() throws {
        let planned = try chestDipsWithLastSession()

        try service.updateInstructions(exerciseId: planned.exerciseId, instructions: "  ")

        let result = try detail(planned).exercise
        XCTAssertNil(result.instructions)
        XCTAssertEqual(result.muscle, "Chest")
    }

    func testEditingInstructionsOfAnUnknownExerciseIsRejected() throws {
        XCTAssertThrowsError(try service.updateInstructions(exerciseId: 999, instructions: "x")) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Exercise not found"))
        }
    }
}
