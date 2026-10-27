import XCTest
@testable import FitnessCore

final class ProgressionTests: XCTestCase {
    private var db: Database!
    private var planned: PlannedExercise!
    private var forms: FormChecks!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        forms = FormChecks(db)
        planned = try PlannedExercise.make(db, name: "Leg Extensions", muscle: "Quads", minReps: 8, maxReps: 16, sets: 1)
    }

    private func log(_ day: String, _ weight: Double, _ reps: Int, clean: Bool? = nil) throws {
        try db.addSet(exercise: planned.exerciseId, on: day, weight: weight, reps: reps)
        if let clean { try forms.setClean(clean, exerciseId: planned.exerciseId, on: date(day)) }
    }

    private func detail() throws -> ExerciseDetail {
        try ExerciseDetailService(db, clock: planningClock()).detail(exerciseId: planned.exerciseId, dayId: planned.dayId)
    }

    private func listEntry() throws -> WorkoutExercise {
        try XCTUnwrap(try WorkoutService(db, clock: planningClock()).workout(dayId: planned.dayId).exercises.first)
    }

    // planningToday is 2026-10-20

    // MARK: Which sessions are PRs

    func testASessionAtTheTopOfTheRangeWithCleanFormIsAPR() throws {
        try log("2026-10-13", 60, 16, clean: true)

        XCTAssertEqual(try detail().sessionMarks, [date("2026-10-13"): .pr])
    }

    func testTopRepsWithoutCleanFormIsNotAPR() throws {
        try log("2026-10-13", 60, 16, clean: false)

        XCTAssertEqual(try detail().sessionMarks, [date("2026-10-13"): .notClean])
    }

    func testOlderSessionsThatWereNeverAskedCountAsClean() throws {
        try log("2026-10-13", 60, 16)

        XCTAssertEqual(try detail().sessionMarks, [date("2026-10-13"): .pr])
    }

    func testBelowTheTopOfTheRangeIsNotMarked() throws {
        try log("2026-10-13", 60, 15, clean: true)

        XCTAssertTrue(try detail().sessionMarks.isEmpty)
    }

    func testTodaysTopRepsAreNotMarkedUntilTheQuestionIsAnswered() throws {
        try log("2026-10-20", 60, 16)

        XCTAssertTrue(try detail().sessionMarks.isEmpty)
    }

    func testAnyOneOfSeveralSetsAtTheTopCountsForTheSession() throws {
        try log("2026-10-13", 60, 12)
        try log("2026-10-13", 60, 16, clean: true)

        XCTAssertEqual(try detail().sessionMarks[date("2026-10-13")], .pr)
    }

    // MARK: What to do next

    func testLastSessionWasAPRSoThePlanIsTheHeavierWeight() throws {
        try log("2026-10-13", 60, 16, clean: true)

        let result = try detail()

        XCTAssertEqual(result.progression, .pr(nextWeightKg: 72.5, oneRepMax: 92, fromWeightKg: 60, fromReps: 16, isToday: false))
        XCTAssertEqual(result.target.workingWeight, 72.5)
        XCTAssertEqual(result.prefill.weightKg, 72.5)
        XCTAssertEqual(result.target.warmups.map(\.weightKg), [], "no warm-up sets are planned")
        XCTAssertEqual(result.aim, "Increase weight: go to 72.5 kg")
    }

    func testWarmupsFollowTheNewWorkingWeight() throws {
        try PlanEditor(db).updateEntry(entryId: planned.entryId, sets: 1, minReps: 8, maxReps: 16, warmupSets: 2)
        try log("2026-10-13", 60, 16, clean: true)

        XCTAssertEqual(try detail().target.warmups, [WarmupStep(percent: 75, weightKg: 54.38), WarmupStep(percent: 90, weightKg: 65.25)])
    }

    func testTopRepsWithoutCleanFormMeansTheSameWeightAgain() throws {
        try log("2026-10-13", 60, 16, clean: false)

        let result = try detail()

        XCTAssertEqual(result.progression, .repeatForCleanReps(weightKg: 60))
        XCTAssertEqual(result.target.workingWeight, 60)
        XCTAssertEqual(result.aim, "Repeat: aim for clean reps at 60 kg")
    }

    func testTodaysCleanPRNamesTheNextWeightButKeepsTodaysWorkingWeight() throws {
        try log("2026-10-20", 60, 16, clean: true)

        let result = try detail()

        XCTAssertEqual(result.progression, .pr(nextWeightKg: 72.5, oneRepMax: 92, fromWeightKg: 60, fromReps: 16, isToday: true))
        XCTAssertEqual(result.target.workingWeight, 60)
    }

    func testTodaysTopRepsWithoutCleanFormMeanRepeat() throws {
        try log("2026-10-20", 60, 16, clean: false)

        XCTAssertEqual(try detail().progression, .repeatForCleanReps(weightKg: 60))
    }

    func testAHeavierSetTodayEndsTheBannerFromLastTimesPR() throws {
        try log("2026-10-13", 60, 16, clean: true)
        try log("2026-10-20", 72.5, 9)

        XCTAssertEqual(try detail().progression, .none)
    }

    func testALighterOrEqualSetTodayKeepsTheBanner() throws {
        try log("2026-10-13", 60, 16, clean: true)
        try log("2026-10-20", 60, 12)

        XCTAssertEqual(try detail().progression, .pr(nextWeightKg: 72.5, oneRepMax: 92, fromWeightKg: 60, fromReps: 16, isToday: false))
    }

    func testPendingTopRepsTodayFallBackToLastTimesSession() throws {
        try log("2026-10-13", 60, 16, clean: true)
        try log("2026-10-20", 60, 16)

        XCTAssertEqual(try detail().progression, .pr(nextWeightKg: 72.5, oneRepMax: 92, fromWeightKg: 60, fromReps: 16, isToday: false),
                       "today's question is still open and 60 kg is not above last time's 60 kg")
    }

    func testNoPRMeansNoBanner() throws {
        try log("2026-10-13", 60, 12, clean: true)

        XCTAssertEqual(try detail().progression, .none)
    }

    func testDeloadWeekHasNoBanner() throws {
        try log("2026-10-13", 60, 16, clean: true)
        try setDeload(db, enabled: true)

        XCTAssertEqual(try detail().progression, .none)
        XCTAssertEqual(try listEntry().progression, .none)
    }

    func testTheNextWeightFollowsTheMinimumRepsOfTheRange() throws {
        try PlanEditor(db).updateEntry(entryId: planned.entryId, sets: 1, minReps: 12, maxReps: 16)
        try log("2026-10-13", 50, 16, clean: true)

        XCTAssertEqual(try detail().progression, .pr(nextWeightKg: 55, oneRepMax: 76.67, fromWeightKg: 50, fromReps: 16, isToday: false))
    }

    // MARK: The workout list

    func testTheWorkoutListKnowsTheProgressionToo() throws {
        try log("2026-10-13", 60, 16, clean: true)

        let entry = try listEntry()

        XCTAssertEqual(entry.progression, .pr(nextWeightKg: 72.5, oneRepMax: 92, fromWeightKg: 60, fromReps: 16, isToday: false))
        XCTAssertEqual(entry.workingWeight, 60, "the list still shows the weight lifted last time")
        XCTAssertEqual(entry.recommendation, .increaseWeight, "the notebook's recommendation is unchanged")
    }
}
