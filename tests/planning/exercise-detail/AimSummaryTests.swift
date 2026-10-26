import XCTest
@testable import FitnessCore

/// Scenario Outline "The aim sits inside the Do today card" from exercise-detail.feature.
final class AimSummaryTests: XCTestCase {
    private func aim(weight: Double, reps: Int, min: Int, max: Int) throws -> AimSummary {
        let db = try Database.inMemory()
        let planned = try PlannedExercise.make(db, name: "Chest Dips Machine", minReps: min, maxReps: max)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: weight, reps: reps)
        return try ExerciseDetailService(db, clock: planningClock()).detail(exerciseId: planned.exerciseId, dayId: planned.dayId).aimSummary
    }

    func testRepsAtTheTopOfTheRangeMeanIncreaseWeightWithNoHint() throws {
        XCTAssertEqual(try aim(weight: 45, reps: 10, min: 6, max: 10), AimSummary(pill: "Increase weight", hint: nil))
    }

    func testRepsInsideTheRangeMeanIncreaseReps() throws {
        XCTAssertEqual(try aim(weight: 54, reps: 8, min: 6, max: 10), AimSummary(pill: "Increase reps", hint: "Beat 8 reps at 54 kg"))
    }

    func testRepsBelowTheRangeMeanMaintain() throws {
        XCTAssertEqual(try aim(weight: 54, reps: 5, min: 6, max: 10), AimSummary(pill: "Maintain", hint: "Reach 6 reps at 54 kg"))
    }

    func testNoHistory() throws {
        let db = try Database.inMemory()
        let planned = try PlannedExercise.make(db)
        let detail = try ExerciseDetailService(db, clock: planningClock()).detail(exerciseId: planned.exerciseId, dayId: planned.dayId)
        XCTAssertEqual(detail.aimSummary, AimSummary(pill: "No history yet", hint: nil))
    }

    func testDeloadWeekShowsTheDeloadTarget() throws {
        let db = try Database.inMemory()
        let planned = try PlannedExercise.make(db, minReps: 6, maxReps: 10)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: 54, reps: 8)
        try setDeload(db, enabled: true, weightMultiplier: 0.8, repsMultiplier: 0.75)

        let detail = try ExerciseDetailService(db, clock: planningClock()).detail(exerciseId: planned.exerciseId, dayId: planned.dayId)

        XCTAssertEqual(detail.aimSummary, AimSummary(pill: "Deload", hint: "4.5 to 7.5 reps at 43.2 kg"))
    }

    func testSplittingTheAimText() {
        XCTAssertEqual(AimSummary.make(from: "Increase reps: beat 9 reps at 54 kg"), AimSummary(pill: "Increase reps", hint: "Beat 9 reps at 54 kg"))
        XCTAssertEqual(AimSummary.make(from: "Bring to maintenance: reach 6 reps at 54 kg"), AimSummary(pill: "Maintain", hint: "Reach 6 reps at 54 kg"))
        XCTAssertEqual(AimSummary.make(from: "Increase weight"), AimSummary(pill: "Increase weight", hint: nil))
    }

    func testTheWarmupPercentagesAreNamed() {
        XCTAssertEqual(WarmupLabels.percentages, [75, 90])
    }
}
