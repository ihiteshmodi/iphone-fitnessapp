import XCTest
@testable import FitnessCore

/// Scenarios from deload-mode.feature.
final class DeloadModeTests: XCTestCase {
    private var db: Database!
    private var service: WorkoutService!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        service = WorkoutService(db, clock: planningClock())
    }

    private func chestDips(minReps: Int = 6, maxReps: Int = 10, heaviest: Double = 54, reps: Int = 8) throws -> PlannedExercise {
        let planned = try PlannedExercise.make(db, name: "Chest Dips Machine", minReps: minReps, maxReps: maxReps)
        try db.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: heaviest, reps: reps)
        return planned
    }

    private func firstExercise(_ planned: PlannedExercise) throws -> WorkoutExercise {
        try XCTUnwrap(try service.workout(dayId: planned.dayId).exercises.first)
    }

    func testDeloadAppliesMultipliersAndHidesRecommendation() throws {
        let planned = try chestDips()
        try setDeload(db, enabled: true, weightMultiplier: 0.8, repsMultiplier: 0.75)

        let workout = try service.workout(dayId: planned.dayId)
        let exercise = try XCTUnwrap(workout.exercises.first)

        XCTAssertTrue(workout.isDeload)
        XCTAssertEqual(exercise.workingWeight, 43.2)
        XCTAssertEqual(exercise.warmup75, 32.4)
        XCTAssertEqual(exercise.warmup90, 38.88)
        XCTAssertEqual(exercise.minReps, 4.5)
        XCTAssertEqual(exercise.maxReps, 10)
        XCTAssertNil(exercise.recommendation)
    }

    func testDefaultDeloadKeepsWeightAndLowersMinimumRepsTo75Percent() throws {
        let rows: [(planned: Int, shown: Double)] = [(6, 4.5), (8, 6), (10, 7.5)]
        for row in rows {
            let database = try Database.inMemory()
            let planned = try PlannedExercise.make(database, minReps: row.planned, maxReps: 12)
            try database.addSet(exercise: planned.exerciseId, on: "2026-10-01", weight: 54, reps: 8)
            try SettingsRepository(database).setDeloadEnabled(true)

            let exercise = try XCTUnwrap(try WorkoutService(database, clock: planningClock()).workout(dayId: planned.dayId).exercises.first)

            XCTAssertEqual(exercise.workingWeight, 54)
            XCTAssertEqual(exercise.minReps, row.shown, "planned \(row.planned)")
        }
    }

    func testLoggingTheDeloadWeightKeepsTheSameTargetInsteadOfScalingItAgain() throws {
        // Normally 100 kg. In deload week the app shows 70 kg and the user lifts exactly 70.
        let planned = try chestDips(heaviest: 100, reps: 8)
        try setDeload(db, enabled: true, weightMultiplier: 0.7)
        XCTAssertEqual(try firstExercise(planned).workingWeight, 70)

        try LogSets(db).logSet(.existing(id: planned.exerciseId), weightKg: 70, reps: 6, on: planningToday)

        XCTAssertEqual(try firstExercise(planned).workingWeight, 70, "70 stays 70, not 70 x 0.7")
        let stored = try db.query("SELECT weight_kg FROM set_logs WHERE performed_on = ?", [.text(planningToday.string)])
        XCTAssertEqual(stored.map { $0.double("weight_kg") }, [70], "the logged weight is saved exactly as typed")
        let detail = try ExerciseDetailService(db, clock: planningClock()).detail(exerciseId: planned.exerciseId, dayId: planned.dayId)
        XCTAssertEqual(detail.prefill.weightKg, 70)
    }

    func testTheWeekAfterDeloadGoesBackToTheNormalWeight() throws {
        let planned = try chestDips(heaviest: 100, reps: 8)
        try setDeload(db, enabled: true, weightMultiplier: 0.7)
        try LogSets(db).logSet(.existing(id: planned.exerciseId), weightKg: 70, reps: 6, on: planningToday)

        try SettingsRepository(db).setDeloadEnabled(false)

        let exercise = try firstExercise(planned)
        XCTAssertEqual(exercise.workingWeight, 100)
        XCTAssertEqual(exercise.minReps, 6)
    }

    func testStoredMinimumRepsAreExposedSoEditingNeverWritesScaledNumbers() throws {
        let planned = try chestDips(minReps: 6)
        try setDeload(db, enabled: true, repsMultiplier: 0.75)

        let exercise = try firstExercise(planned)

        XCTAssertEqual(exercise.minReps, 4.5, "what the screen shows during deload")
        XCTAssertEqual(exercise.plannedMinReps, 6, "what is stored in the plan")
    }

    func testSwitchingDeloadOffRestoresTargetsAndLeavesThePlanUntouched() throws {
        let planned = try chestDips(heaviest: 54, reps: 8)
        try setDeload(db, enabled: true, weightMultiplier: 0.8)
        _ = try firstExercise(planned)

        try SettingsRepository(db).setDeloadEnabled(false)
        let exercise = try firstExercise(planned)

        XCTAssertEqual(exercise.minReps, 6)
        XCTAssertEqual(exercise.workingWeight, 54)
        XCTAssertEqual(exercise.recommendation, .increaseReps)
        let stored = try XCTUnwrap(try db.query("SELECT min_reps, max_reps, sets FROM plan_entries WHERE id = ?", [.int(Int64(planned.entryId))]).first)
        XCTAssertEqual(stored.int("min_reps"), 6)
        XCTAssertEqual(stored.int("max_reps"), 10)
        XCTAssertEqual(stored.int("sets"), 3)
    }

    func testTurningDeloadOnNeverRewritesTheStoredPlan() throws {
        let planned = try chestDips()
        try setDeload(db, enabled: true, weightMultiplier: 0.5, repsMultiplier: 0.5)

        _ = try firstExercise(planned)

        let stored = try XCTUnwrap(try db.query("SELECT min_reps FROM plan_entries WHERE id = ?", [.int(Int64(planned.entryId))]).first)
        XCTAssertEqual(stored.int("min_reps"), 6)
    }

    func testMultiplierMustBePositive() throws {
        let settings = SettingsRepository(db)

        for zeroOrLess in [0.0, -0.5] {
            XCTAssertThrowsError(try settings.setDeloadRepsMultiplier(zeroOrLess)) {
                XCTAssertEqual($0 as? ValidationError, ValidationError("Multiplier must be greater than 0"))
            }
            XCTAssertThrowsError(try settings.setDeloadWeightMultiplier(zeroOrLess)) {
                XCTAssertEqual($0 as? ValidationError, ValidationError("Multiplier must be greater than 0"))
            }
        }
        XCTAssertEqual(try settings.load().deload.repsMultiplier, 0.75)
    }

    func testDeloadWithoutHistoryShowsNoWeightAndNoRecommendation() throws {
        let planned = try PlannedExercise.make(db, name: "Squats")
        try setDeload(db, enabled: true)

        let exercise = try firstExercise(planned)

        XCTAssertNil(exercise.workingWeight)
        XCTAssertNil(exercise.recommendation)
        XCTAssertEqual(exercise.minReps, 4.5)
    }

    func testRecommendationRuleStillUsesThePlannedRepsNotTheScaledOnes() {
        let heaviest = PerformedSet(id: 1, date: date("2026-10-01"), weightKg: 54, reps: 5)
        let normal = WorkoutTargetCalculator.target(heaviest: heaviest, minReps: 6, maxReps: 10,
                                                    deload: DeloadSettings(enabled: false, weightMultiplier: 1, repsMultiplier: 0.75))
        let deload = WorkoutTargetCalculator.target(heaviest: heaviest, minReps: 6, maxReps: 10,
                                                    deload: DeloadSettings(enabled: true, weightMultiplier: 1, repsMultiplier: 0.75))

        XCTAssertEqual(normal.recommendation, .bringToMaintenance)
        XCTAssertNil(deload.recommendation)
    }

    func testScalingIsIdentityWhenDeloadIsOff() {
        let scaling = DeloadScaling(DeloadSettings(enabled: false, weightMultiplier: 0.5, repsMultiplier: 0.5))

        XCTAssertFalse(scaling.isActive)
        XCTAssertEqual(scaling.workingWeight(heaviest: 54), 54)
        XCTAssertEqual(scaling.minReps(planned: 6), 6)
    }

    func testScalingMultipliesWhenDeloadIsOn() {
        let scaling = DeloadScaling(DeloadSettings(enabled: true, weightMultiplier: 0.8, repsMultiplier: 0.75))

        XCTAssertTrue(scaling.isActive)
        XCTAssertEqual(scaling.workingWeight(heaviest: 54), 54 * 0.8)
        XCTAssertEqual(scaling.minReps(planned: 6), 4.5)
    }
}
