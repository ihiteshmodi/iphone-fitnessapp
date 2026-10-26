import XCTest
@testable import FitnessCore

final class FormCheckTests: XCTestCase {
    private var db: Database!
    private var forms: FormChecks!
    private var planned: PlannedExercise!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        forms = FormChecks(db)
        planned = try PlannedExercise.make(db, name: "Leg Extensions", muscle: "Quads", minReps: 8, maxReps: 16, sets: 1)
    }

    private func detail() throws -> ExerciseDetail {
        try ExerciseDetailService(db, clock: planningClock()).detail(exerciseId: planned.exerciseId, dayId: planned.dayId)
    }

    private func logToday(reps: Int, weight: Double = 60) throws {
        try db.addSet(exercise: planned.exerciseId, on: planningToday.string, weight: weight, reps: reps)
    }

    // MARK: Storing the answer

    func testStoresYesOrNoPerExerciseAndDay() throws {
        try forms.setClean(true, exerciseId: planned.exerciseId, on: date("2026-10-20"))
        try forms.setClean(false, exerciseId: planned.exerciseId, on: date("2026-10-13"))

        XCTAssertEqual(try forms.answer(exerciseId: planned.exerciseId, on: date("2026-10-20")), true)
        XCTAssertEqual(try forms.answer(exerciseId: planned.exerciseId, on: date("2026-10-13")), false)
        XCTAssertNil(try forms.answer(exerciseId: planned.exerciseId, on: date("2026-10-06")))
    }

    func testAnsweringAgainChangesTheStoredAnswer() throws {
        try forms.setClean(true, exerciseId: planned.exerciseId, on: planningToday)
        try forms.setClean(false, exerciseId: planned.exerciseId, on: planningToday)

        XCTAssertEqual(try forms.answer(exerciseId: planned.exerciseId, on: planningToday), false)
        XCTAssertEqual(try db.count("form_checks"), 1)
    }

    func testListsEveryAnswerOfOneExercise() throws {
        let other = try db.addExercise("Leg Curl")
        try forms.setClean(true, exerciseId: planned.exerciseId, on: date("2026-10-13"))
        try forms.setClean(false, exerciseId: planned.exerciseId, on: date("2026-10-20"))
        try forms.setClean(true, exerciseId: other, on: date("2026-10-20"))

        XCTAssertEqual(try forms.answers(exerciseId: planned.exerciseId), [date("2026-10-13"): true, date("2026-10-20"): false])
    }

    func testRefusesAnExerciseThatDoesNotExist() {
        XCTAssertThrowsError(try forms.setClean(true, exerciseId: 999, on: planningToday)) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Exercise not found"))
        }
    }

    // MARK: When the question is due

    func testTheQuestionIsDueOnceTheTopOfTheRepRangeIsReached() throws {
        try logToday(reps: 16)

        XCTAssertTrue(try detail().needsFormAnswer)
        XCTAssertNil(try detail().todayCleanForm)
    }

    func testTheQuestionIsDueForRepsAboveTheTopToo() throws {
        try logToday(reps: 17)

        XCTAssertTrue(try detail().needsFormAnswer)
    }

    func testTheQuestionIsNotDueBelowTheTopOfTheRange() throws {
        try logToday(reps: 15)

        XCTAssertFalse(try detail().needsFormAnswer)
    }

    func testTheQuestionIsNotDueWithoutASetToday() throws {
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-13", weight: 60, reps: 16)

        XCTAssertFalse(try detail().needsFormAnswer)
    }

    func testTheQuestionIsNotDueDuringDeload() throws {
        try setDeload(db, enabled: true)
        try logToday(reps: 12)

        XCTAssertFalse(try detail().needsFormAnswer)
    }

    func testTheQuestionIsAskedOnlyOnceADay() throws {
        try logToday(reps: 16)
        try forms.setClean(false, exerciseId: planned.exerciseId, on: planningToday)
        try logToday(reps: 16)

        let result = try detail()

        XCTAssertFalse(result.needsFormAnswer)
        XCTAssertEqual(result.todayCleanForm, false)
    }
}
