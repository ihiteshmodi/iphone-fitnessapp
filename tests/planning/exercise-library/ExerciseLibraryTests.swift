import XCTest
@testable import FitnessCore

final class ExerciseLibraryTests: XCTestCase {
    private var db: Database!
    private var library: ExerciseRepository!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        library = ExerciseRepository(db)
    }

    func testAddExerciseAppearsInLibraryAndSearch() throws {
        let added = try library.add(name: "Landmine Press", muscle: "Shoulders", instructions: "Stand split stance, press up and across")
        XCTAssertEqual(added.source, "user")
        XCTAssertEqual(try library.all().map(\.name), ["Landmine Press"])
        XCTAssertEqual(try library.search("landmine", muscle: nil).map(\.name), ["Landmine Press"])
    }

    func testEditInstructionsIsVisibleEverywhereThroughTheSameRecord() throws {
        let id = try db.addExercise("Chest Dips Machine", muscle: "Chest", instructions: "handle inner, squeeze very hard")
        try library.update(id: id, name: "Chest Dips Machine", muscle: "Chest", instructions: "handle inner, pause at the bottom")
        XCTAssertEqual(try library.exercise(id: id)?.instructions, "handle inner, pause at the bottom")
    }

    func testSearchMatchesPartsOfNamesAndFiltersByMuscle() throws {
        try db.addExercise("Lat Pulldown", muscle: "Back")
        try db.addExercise("Reverse Lat Pulldown", muscle: "Back")
        try db.addExercise("Weighted Pull Ups", muscle: "Back")
        try db.addExercise("Preacher Curls", muscle: "Biceps")
        XCTAssertEqual(try library.search("pull", muscle: nil).map(\.name), ["Lat Pulldown", "Reverse Lat Pulldown", "Weighted Pull Ups"])
        XCTAssertEqual(try library.search("", muscle: "Biceps").map(\.name), ["Preacher Curls"])
    }

    func testNamesAreUniqueIgnoringCaseAndSpaces() throws {
        try db.addExercise("Lat Pulldown")
        XCTAssertThrowsError(try library.add(name: " lat pulldown ", muscle: nil, instructions: nil)) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Exercise already exists"))
        }
    }

    func testNameIsRequired() {
        XCTAssertThrowsError(try library.add(name: "   ", muscle: nil, instructions: nil)) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Name is required"))
        }
    }

    func testRenameKeepsHistory() throws {
        let id = try db.addExercise("Tricep Pushdown", muscle: "Triceps")
        try db.addSet(exercise: id, on: "2026-10-23", weight: 45, reps: 10)
        try library.update(id: id, name: "Triceps Pushdown", muscle: "Triceps", instructions: nil)
        let sets = try db.query("SELECT COUNT(*) AS n FROM set_logs WHERE exercise_id = ?", [.int(Int64(id))])
        XCTAssertEqual(sets.first?.int("n"), 1)
        XCTAssertEqual(try library.exercise(id: id)?.name, "Triceps Pushdown")
    }

    func testRenameToAnotherExistingNameIsRejected() throws {
        try db.addExercise("Lat Pulldown")
        let id = try db.addExercise("Seated Rows")
        XCTAssertThrowsError(try library.update(id: id, name: "lat pulldown", muscle: nil, instructions: nil))
    }

    func testExercisesWithHistoryCannotBeDeleted() throws {
        let id = try db.addExercise("Squats")
        try db.addSet(exercise: id, on: "2026-10-23", weight: 100, reps: 8)
        XCTAssertThrowsError(try library.delete(id: id)) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("This exercise has history. Remove it from days instead"))
        }
    }

    func testUnusedExerciseCanBeDeleted() throws {
        let id = try db.addExercise("Typo Exercise")
        try library.delete(id: id)
        XCTAssertNil(try library.exercise(id: id))
    }

    func testExerciseLookupByNameIgnoresCase() throws {
        let id = try db.addExercise("Machine Shoulder Press")
        XCTAssertEqual(try library.exercise(named: " machine shoulder press ")?.id, id)
    }

    func testBlankInstructionsAreStoredAsNil() throws {
        let added = try library.add(name: "Cable Crunch", muscle: "Abs", instructions: "  ")
        XCTAssertNil(added.instructions)
    }
}
