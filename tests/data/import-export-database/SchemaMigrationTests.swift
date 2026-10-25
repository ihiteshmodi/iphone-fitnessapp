import XCTest
@testable import FitnessCore

/// An existing database (schema version 1, no deload tagging) is upgraded in place when the app opens it.
final class SchemaMigrationTests: DatabaseFileTestCase {
    /// What the first seeded database looked like: no `is_deload` column, no ignore setting, version 1.
    private func installVersion1Database() throws {
        let url = try makeFitnessDatabase(named: "v1.sqlite")
        let db = try Database(path: url.path)
        try db.execute("ALTER TABLE set_logs DROP COLUMN is_deload")
        try db.execute("DELETE FROM settings WHERE key = 'ignore_deload_sessions'")
        try db.runScript("PRAGMA user_version = 1")
        try FileManager.default.copyItem(at: url, to: location.databaseURL)
    }

    private func columns(of table: String, in db: Database) throws -> [String] {
        try db.query("PRAGMA table_info(\(table))").map { $0.text("name") }
    }

    func testOpeningAVersion1DatabaseAddsTheDeloadTagAndSetting() throws {
        try installVersion1Database()

        let db = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertEqual(db.userVersion, 2)
        XCTAssertTrue(try columns(of: "set_logs", in: db).contains("is_deload"))
        XCTAssertTrue(try SettingsRepository(db).load().ignoreDeloadSessions)
    }

    func testOldSetsAreNotTaggedAsDeload() throws {
        try installVersion1Database()
        let raw = try Database(path: location.databaseURL.path)
        let exercise = try raw.addExerciseWithoutTag("Squats")
        try raw.execute("INSERT INTO set_logs (performed_on, exercise_id, weight_kg, reps) VALUES ('2026-10-01', ?, 100, 8)", [.int(Int64(exercise))])

        let db = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertEqual(try db.query("SELECT is_deload FROM set_logs").map { $0.int("is_deload") }, [0])
    }

    func testMigrationKeepsAUsersChoiceAndRunsOnlyOnce() throws {
        try installVersion1Database()
        _ = try service.openLiveDatabase()
        let reopened = try XCTUnwrap(try service.openLiveDatabase())
        try SettingsRepository(reopened).setIgnoreDeloadSessions(false)

        let again = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertFalse(try SettingsRepository(again).load().ignoreDeloadSessions)
        XCTAssertEqual(again.userVersion, 2)
    }

    func testAnOldVersionNumberOnAnAlreadyCurrentSchemaDoesNotFail() throws {
        let url = try makeFitnessDatabase(named: "marked-old.sqlite", userVersion: 0)
        try FileManager.default.copyItem(at: url, to: location.databaseURL)

        let db = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertEqual(db.userVersion, 2)
    }

    func testImportingAVersion1FileThenOpeningItWorks() throws {
        try installVersion1Database()
        let picked = scratchURL("picked-v1.sqlite")
        try FileManager.default.moveItem(at: location.databaseURL, to: picked)

        try service.importDatabase(from: picked, clock: clock)

        let db = try XCTUnwrap(try service.openLiveDatabase())
        XCTAssertEqual(db.userVersion, 2)
    }
}

private extension Database {
    /// The version-1 schema has no tag column, so tests insert without it.
    func addExerciseWithoutTag(_ name: String) throws -> Int {
        try execute("INSERT INTO exercises (name, source) VALUES (?, 'library')", [.text(name)])
        return lastInsertRowID
    }
}
