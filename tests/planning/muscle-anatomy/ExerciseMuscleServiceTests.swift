import XCTest
@testable import FitnessCore

/// Scenarios from muscle-anatomy.feature about saving chosen muscles per exercise.
final class ExerciseMuscleServiceTests: XCTestCase {
    private var db: Database!
    private var service: ExerciseMuscleService!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        service = ExerciseMuscleService(db)
    }

    private func exercise(_ name: String, group: String?) throws -> Int {
        try db.addExercise(name, muscle: group)
    }

    private func chosen(_ exerciseId: Int) throws -> Int {
        try db.query("SELECT COUNT(*) AS n FROM exercise_muscles WHERE exercise_id = ?", [.int(Int64(exerciseId))]).first?.int("n") ?? 0
    }

    // Scenario: See the trained muscles highlighted
    func testWithNothingChosenTheMusclesAreAutomatic() throws {
        let id = try exercise("Triceps Press", group: "Triceps")

        let muscles = try service.muscles(exerciseId: id)

        XCTAssertFalse(muscles.isCustom)
        XCTAssertEqual(Set(muscles.primary), [.tricepsLong, .tricepsLateral])
        XCTAssertTrue(muscles.secondary.isEmpty)
    }

    func testRolesAreSplitIntoPrimaryAndSecondary() throws {
        let id = try exercise("Champagne Press", group: "Chest")

        let muscles = try service.muscles(exerciseId: id)

        XCTAssertEqual(Set(muscles.primary), [.chestUpper, .chestMid, .chestLower])
        XCTAssertEqual(Set(muscles.secondary), [.deltFront, .tricepsLong, .tricepsLateral])
        XCTAssertEqual(muscles.role(of: .deltFront), .secondary)
        XCTAssertNil(muscles.role(of: .biceps))
    }

    func testAnExerciseWithNoClueHasNoMuscles() throws {
        let id = try exercise("Mystery Move", group: nil)

        let muscles = try service.muscles(exerciseId: id)

        XCTAssertTrue(muscles.assignments.isEmpty)
        XCTAssertFalse(muscles.isCustom)
    }

    // Scenario: Choose specific parts only
    func testSavedMusclesReplaceTheAutomaticOnes() throws {
        let id = try exercise("Seated rows mid back", group: "Back")

        try service.save(exerciseId: id, assignments: [
            MuscleAssignment(part: .rhomboids, role: .primary),
            MuscleAssignment(part: .lats, role: .secondary),
        ])

        let muscles = try service.muscles(exerciseId: id)
        XCTAssertTrue(muscles.isCustom)
        XCTAssertEqual(muscles.primary, [.rhomboids])
        XCTAssertEqual(muscles.secondary, [.lats])
    }

    // Scenario: Choose the entire upper back
    func testChoosingTheEntireUpperBack() throws {
        let id = try exercise("Seated rows mid back", group: "Back")
        var selection = MuscleSelection()
        selection.selectEntire(.upperBack)

        try service.save(exerciseId: id, assignments: selection.assignments)

        XCTAssertEqual(Set(try service.muscles(exerciseId: id).primary), Set(MuscleRegion.upperBack.parts))
    }

    func testSavingAgainReplacesThePreviousChoice() throws {
        let id = try exercise("Preacher Curls", group: "Biceps")
        try service.save(exerciseId: id, assignments: [MuscleAssignment(part: .biceps, role: .primary), MuscleAssignment(part: .brachialis, role: .primary)])

        try service.save(exerciseId: id, assignments: [MuscleAssignment(part: .forearmFlexors, role: .secondary)])

        XCTAssertEqual(try service.muscles(exerciseId: id).assignments, [MuscleAssignment(part: .forearmFlexors, role: .secondary)])
        XCTAssertEqual(try chosen(id), 1)
    }

    func testARepeatedPartKeepsTheLastRole() throws {
        let id = try exercise("Preacher Curls", group: "Biceps")

        try service.save(exerciseId: id, assignments: [MuscleAssignment(part: .biceps, role: .primary), MuscleAssignment(part: .biceps, role: .secondary)])

        XCTAssertEqual(try service.muscles(exerciseId: id).assignments, [MuscleAssignment(part: .biceps, role: .secondary)])
    }

    // Scenario: Reset to automatic
    func testResetReturnsToAutomatic() throws {
        let id = try exercise("Seated rows mid back", group: "Back")
        try service.save(exerciseId: id, assignments: [MuscleAssignment(part: .rhomboids, role: .primary)])

        try service.reset(exerciseId: id)

        let muscles = try service.muscles(exerciseId: id)
        XCTAssertFalse(muscles.isCustom)
        XCTAssertEqual(Set(muscles.primary), [.trapsMid, .rhomboids, .lats])
        XCTAssertEqual(try chosen(id), 0)
    }

    // Scenario: Selecting nothing equals automatic
    func testSavingNothingEqualsReset() throws {
        let id = try exercise("Preacher Curls", group: "Biceps")
        try service.save(exerciseId: id, assignments: [MuscleAssignment(part: .biceps, role: .primary)])

        try service.save(exerciseId: id, assignments: [])

        XCTAssertFalse(try service.muscles(exerciseId: id).isCustom)
        XCTAssertEqual(try chosen(id), 0)
    }

    func testChoicesForOneExerciseDoNotTouchAnother() throws {
        let rows = try exercise("Seated rows mid back", group: "Back")
        let curls = try exercise("Preacher Curls", group: "Biceps")

        try service.save(exerciseId: rows, assignments: [MuscleAssignment(part: .rhomboids, role: .primary)])

        XCTAssertFalse(try service.muscles(exerciseId: curls).isCustom)
        XCTAssertEqual(try chosen(curls), 0)
    }

    func testUnknownExerciseIsRejected() {
        XCTAssertThrowsError(try service.muscles(exerciseId: 999)) { XCTAssertEqual($0 as? ValidationError, ValidationError("Exercise not found")) }
        XCTAssertThrowsError(try service.save(exerciseId: 999, assignments: [MuscleAssignment(part: .lats, role: .primary)])) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Exercise not found"))
        }
    }

    // Scenario: Chosen muscles survive renaming and go away with the exercise
    func testRenamingKeepsTheChosenMuscles() throws {
        let id = try exercise("Tricep Pushdown", group: "Triceps")
        try service.save(exerciseId: id, assignments: [MuscleAssignment(part: .tricepsLong, role: .primary)])

        try ExerciseRepository(db).update(id: id, name: "Triceps Pushdown", muscle: "Triceps", instructions: nil)

        XCTAssertEqual(try service.muscles(exerciseId: id).assignments, [MuscleAssignment(part: .tricepsLong, role: .primary)])
    }

    func testDeletingAnUnusedExerciseDeletesItsChosenMuscles() throws {
        let id = try exercise("Typo Exercise", group: "Chest")
        try service.save(exerciseId: id, assignments: [MuscleAssignment(part: .chestUpper, role: .primary)])

        try ExerciseRepository(db).delete(id: id)

        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM exercise_muscles").first?.int("n"), 0)
    }

    func testChangingTheMuscleGroupChangesTheAutomaticMuscles() throws {
        let id = try exercise("Bicep Station", group: "Biceps")
        XCTAssertEqual(Set(try service.muscles(exerciseId: id).primary), [.biceps, .brachialis])

        try ExerciseRepository(db).update(id: id, name: "Bicep Station", muscle: "Triceps", instructions: nil)

        XCTAssertEqual(Set(try service.muscles(exerciseId: id).primary), [.tricepsLong, .tricepsLateral])
    }

    // Scenario: Edit muscles from the exercise screen
    func testTheExerciseScreenIncludesTheMuscles() throws {
        let planned = try PlannedExercise.make(db, name: "Triceps Pushdown", muscle: "Triceps")

        let detail = try ExerciseDetailService(db, clock: planningClock()).detail(exerciseId: planned.exerciseId, dayId: planned.dayId)

        XCTAssertFalse(detail.muscles.isCustom)
        XCTAssertEqual(detail.muscles.primary, [.tricepsLateral])
        XCTAssertEqual(detail.muscles.secondary, [.tricepsLong])
    }

    func testTheExerciseScreenShowsChosenMusclesAfterSaving() throws {
        let planned = try PlannedExercise.make(db, name: "Triceps Pushdown", muscle: "Triceps")
        try service.save(exerciseId: planned.exerciseId, assignments: [MuscleAssignment(part: .tricepsLong, role: .primary)])

        let detail = try ExerciseDetailService(db, clock: planningClock()).detail(exerciseId: planned.exerciseId, dayId: planned.dayId)

        XCTAssertTrue(detail.muscles.isCustom)
        XCTAssertEqual(detail.muscles.primary, [.tricepsLong])
    }
}
