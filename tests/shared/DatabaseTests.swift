import XCTest
@testable import FitnessCore

final class DatabaseTests: XCTestCase {
    func testSchemaLoadsWithVersionAndDefaultSettings() throws {
        let db = try Database.inMemory()
        XCTAssertEqual(db.userVersion, Schema.currentVersion)
        let rows = try db.query("SELECT value FROM settings WHERE key = 'history_start_date'")
        XCTAssertEqual(rows.first?.text("value"), "2026-08-31")
    }

    func testForeignKeysAreEnforced() throws {
        let db = try Database.inMemory()
        XCTAssertThrowsError(try db.addSet(exercise: 999, on: "2026-10-23", weight: 45, reps: 10))
    }

    func testTransactionRollsBackOnError() throws {
        let db = try Database.inMemory()
        _ = try? db.transaction {
            try db.addExercise("Squats")
            throw ValidationError("boom")
        }
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM exercises").first?.int("n"), 0)
    }

    func testExerciseNamesAreUniqueIgnoringCase() throws {
        let db = try Database.inMemory()
        try db.addExercise("Lat Pulldown")
        XCTAssertThrowsError(try db.addExercise("lat pulldown"))
    }

    func testDeletingADayRemovesItsEntriesButKeepsSets() throws {
        let db = try Database.inMemory()
        let exercise = try db.addExercise("Squats")
        let day = try db.addDay(position: 1)
        try db.addEntry(day: day, exercise: exercise)
        try db.addSet(exercise: exercise, on: "2026-10-23", weight: 100, reps: 8)

        try db.execute("DELETE FROM plan_days WHERE id = ?", [.int(Int64(day))])

        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM plan_entries").first?.int("n"), 0)
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM set_logs").first?.int("n"), 1)
    }
}
