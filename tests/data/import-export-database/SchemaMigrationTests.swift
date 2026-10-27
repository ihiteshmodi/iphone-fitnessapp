import XCTest
@testable import FitnessCore

/// An existing database (an older schema version) is upgraded in place when the app opens it.
final class SchemaMigrationTests: DatabaseFileTestCase {
    /// What the first seeded database looked like: no `is_deload` column, no ignore setting, no chosen-muscles table, version 1.
    private func installVersion1Database() throws {
        let url = try makeFitnessDatabase(named: "v1.sqlite")
        let db = try Database(path: url.path)
        try db.execute("ALTER TABLE set_logs DROP COLUMN is_deload")
        try db.execute("DELETE FROM settings WHERE key = 'ignore_deload_sessions'")
        try db.execute("DROP TABLE exercise_muscles")
        try db.execute("DROP TABLE calorie_defaults")
        try db.execute("ALTER TABLE measurement_targets DROP COLUMN direction")
        try db.execute("ALTER TABLE plan_entries DROP COLUMN warmup_sets")
        try db.execute("DROP TABLE form_checks")
        try db.runScript("PRAGMA user_version = 1")
        try FileManager.default.copyItem(at: url, to: location.databaseURL)
    }

    /// The database before chosen muscles existed: version 2.
    private func installVersion2Database() throws {
        let url = try makeFitnessDatabase(named: "v2.sqlite")
        let db = try Database(path: url.path)
        try db.execute("DROP TABLE exercise_muscles")
        try db.execute("DROP TABLE calorie_defaults")
        try db.execute("ALTER TABLE measurement_targets DROP COLUMN direction")
        try db.execute("ALTER TABLE plan_entries DROP COLUMN warmup_sets")
        try db.execute("DROP TABLE form_checks")
        try db.runScript("PRAGMA user_version = 2")
        try FileManager.default.copyItem(at: url, to: location.databaseURL)
    }

    /// The database before calorie defaults existed: version 3, with calories the user had typed.
    private func installVersion3Database(calories: [(day: String, kcal: Double, multiplier: Double)] = []) throws {
        let url = try makeFitnessDatabase(named: "v3.sqlite")
        let db = try Database(path: url.path)
        try db.execute("DROP TABLE calorie_defaults")
        try db.execute("ALTER TABLE measurement_targets DROP COLUMN direction")
        try db.execute("ALTER TABLE plan_entries DROP COLUMN warmup_sets")
        try db.execute("DROP TABLE form_checks")
        for entry in calories {
            try db.execute("INSERT INTO calorie_entries (logged_on, calories, multiplier) VALUES (?, ?, ?)",
                           [.text(entry.day), .double(entry.kcal), .double(entry.multiplier)])
        }
        try db.runScript("PRAGMA user_version = 3")
        try FileManager.default.copyItem(at: url, to: location.databaseURL)
    }

    /// The database before measurement directions existed: version 4, with some targets.
    private func installVersion4Database(targets: [(site: String, inches: Double)]) throws {
        let url = try makeFitnessDatabase(named: "v4.sqlite")
        let db = try Database(path: url.path)
        try db.execute("ALTER TABLE measurement_targets DROP COLUMN direction")
        try db.execute("ALTER TABLE plan_entries DROP COLUMN warmup_sets")
        try db.execute("DROP TABLE form_checks")
        for target in targets {
            try db.execute("INSERT INTO measurement_targets (site, inches) VALUES (?, ?)", [.text(target.site), .double(target.inches)])
        }
        try db.runScript("PRAGMA user_version = 4")
        try FileManager.default.copyItem(at: url, to: location.databaseURL)
    }

    /// The database before warm-up sets existed: version 5, with planned exercises.
    private func installVersion5Database() throws {
        let url = try makeFitnessDatabase(named: "v5.sqlite")
        let db = try Database(path: url.path)
        let day = try db.addDay(position: 1)
        let exercise = try db.addExercise("Leg Extensions")
        try db.addEntry(day: day, exercise: exercise, sets: 3, minReps: 8, maxReps: 16)
        try db.execute("ALTER TABLE plan_entries DROP COLUMN warmup_sets")
        try db.execute("DROP TABLE form_checks")
        try db.runScript("PRAGMA user_version = 5")
        try FileManager.default.copyItem(at: url, to: location.databaseURL)
    }

    /// The database before the clean-form question existed: version 6.
    func testOpeningAVersion6DatabaseAddsTheFormChecksTable() throws {
        let url = try makeFitnessDatabase(named: "v6.sqlite")
        let raw = try Database(path: url.path)
        try raw.execute("DROP TABLE form_checks")
        try raw.runScript("PRAGMA user_version = 6")
        try FileManager.default.copyItem(at: url, to: location.databaseURL)

        let db = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertEqual(db.userVersion, Schema.currentVersion)
        XCTAssertEqual(try db.count("form_checks"), 0)
    }

    func testOpeningAVersion5DatabaseKeepsEverySetCountAsMainSetsWithNoWarmups() throws {
        try installVersion5Database()

        let db = try XCTUnwrap(try service.openLiveDatabase())

        let row = try XCTUnwrap(try db.query("SELECT sets, min_reps, max_reps, warmup_sets FROM plan_entries").first)
        XCTAssertEqual(row.int("sets"), 3)
        XCTAssertEqual(row.int("warmup_sets"), 0)
        XCTAssertEqual(row.int("min_reps"), 8)
        XCTAssertEqual(row.int("max_reps"), 16)
    }

    func testOpeningAVersion4DatabaseMarksTheWaistSitesAsReduceAndTheRestAsGrow() throws {
        try installVersion4Database(targets: [("Waist", 28), ("waist (belly button)", 30), ("Body Fat (belly Button)", 4.9),
                                              ("Shoulders", 45.3), ("Left Calf", 15.31)])

        let db = try XCTUnwrap(try service.openLiveDatabase())

        let directions = Dictionary(uniqueKeysWithValues: try db.query("SELECT site, direction FROM measurement_targets").map { ($0.text("site"), $0.text("direction")) })
        XCTAssertEqual(directions["Waist"], "reduce")
        XCTAssertEqual(directions["waist (belly button)"], "reduce")
        XCTAssertEqual(directions["Body Fat (belly Button)"], "reduce")
        XCTAssertEqual(directions["Shoulders"], "grow")
        XCTAssertEqual(directions["Left Calf"], "grow")
        XCTAssertEqual(db.userVersion, Schema.currentVersion)
    }

    func testOpeningAVersion3DatabaseTurnsTheNewestTypedCaloriesIntoTheFirstDefault() throws {
        try installVersion3Database(calories: [("2026-10-20", 2800, 1), ("2026-10-23", 2948.5, 0.9)])

        let db = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertEqual(db.userVersion, Schema.currentVersion)
        XCTAssertEqual(try CalorieService(db).defaults(), [CalorieDefault(effectiveFrom: date("2026-10-23"), calories: 2948.5, multiplier: 0.9)])
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM calorie_entries").first?.int("n"), 2, "typed days are kept")
    }

    func testOpeningAVersion3DatabaseWithoutCaloriesStartsWithNoDefault() throws {
        try installVersion3Database()

        let db = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertEqual(try CalorieService(db).defaults(), [])
    }

    private func columns(of table: String, in db: Database) throws -> [String] {
        try db.query("PRAGMA table_info(\(table))").map { $0.text("name") }
    }

    func testOpeningAVersion2DatabaseAddsTheChosenMusclesTable() throws {
        try installVersion2Database()

        let db = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertEqual(db.userVersion, Schema.currentVersion)
        XCTAssertEqual(try columns(of: "exercise_muscles", in: db), ["exercise_id", "part", "role"])
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM exercise_muscles").first?.int("n"), 0)
        XCTAssertEqual(try db.query("SELECT name FROM exercises").map { $0.text("name") }, ["Squat"], "existing data is untouched")
    }

    func testTheChosenMusclesTableRejectsBadRolesAndKeepsOneRowPerPart() throws {
        let db = try Database.inMemory()
        let id = try db.addExercise("Squats")
        XCTAssertThrowsError(try db.execute("INSERT INTO exercise_muscles (exercise_id, part, role) VALUES (?, 'lats', 'main')", [.int(Int64(id))]))
        try db.execute("INSERT INTO exercise_muscles (exercise_id, part, role) VALUES (?, 'lats', 'primary')", [.int(Int64(id))])
        XCTAssertThrowsError(try db.execute("INSERT INTO exercise_muscles (exercise_id, part, role) VALUES (?, 'lats', 'secondary')", [.int(Int64(id))]))
    }

    func testOpeningAVersion1DatabaseAddsTheDeloadTagAndSetting() throws {
        try installVersion1Database()

        let db = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertEqual(db.userVersion, Schema.currentVersion)
        XCTAssertTrue(try columns(of: "set_logs", in: db).contains("is_deload"))
        XCTAssertTrue(try SettingsRepository(db).load().ignoreDeloadSessions)
        XCTAssertFalse(try columns(of: "exercise_muscles", in: db).isEmpty, "a version 1 file gets every later step too")
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
        XCTAssertEqual(again.userVersion, Schema.currentVersion)
    }

    func testAnOldVersionNumberOnAnAlreadyCurrentSchemaDoesNotFail() throws {
        let url = try makeFitnessDatabase(named: "marked-old.sqlite", userVersion: 0)
        try FileManager.default.copyItem(at: url, to: location.databaseURL)

        let db = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertEqual(db.userVersion, Schema.currentVersion)
    }

    func testImportingAVersion1FileThenOpeningItWorks() throws {
        try installVersion1Database()
        let picked = scratchURL("picked-v1.sqlite")
        try FileManager.default.moveItem(at: location.databaseURL, to: picked)

        try service.importDatabase(from: picked, clock: clock)

        let db = try XCTUnwrap(try service.openLiveDatabase())
        XCTAssertEqual(db.userVersion, Schema.currentVersion)
    }
}

private extension Database {
    /// The version-1 schema has no tag column, so tests insert without it.
    func addExerciseWithoutTag(_ name: String) throws -> Int {
        try execute("INSERT INTO exercises (name, source) VALUES (?, 'library')", [.text(name)])
        return lastInsertRowID
    }
}
