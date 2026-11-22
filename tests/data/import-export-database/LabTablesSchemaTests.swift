import XCTest
@testable import FitnessCore

/// Version 20: blood draws and their results.
final class LabTablesSchemaTests: DatabaseFileTestCase {
    func testAVersion19DatabaseGainsTheLabTables() throws {
        let url = try makeFitnessDatabase(named: "v19.sqlite")
        let raw = try Database(path: url.path)
        try raw.runScript("DROP TABLE lab_results; DROP TABLE lab_draws; PRAGMA user_version = 19;")
        try FileManager.default.copyItem(at: url, to: location.databaseURL)

        let db = try XCTUnwrap(try service.openLiveDatabase())

        let draws = LabDrawService(db, catalogue: try LabCatalogue(data: Data(fixtureCatalogueJSON.utf8)))
        let id = try draws.addDraw(LabDrawDraft(date: date("2026-12-02")))
        try draws.addResult(drawID: id, markerID: "ferritin", value: 48, unit: "ng/mL")
        XCTAssertEqual(try draws.history(of: "ferritin").count, 1)
    }

    func testAVersion20DatabaseMigratesToVersion21KeepingExistingLabResultsAndAllowingQualitativeRows() throws {
        let url = try makeFitnessDatabase(named: "v20.sqlite")
        let raw = try Database(path: url.path)
        try raw.runScript("""
            DROP TABLE IF EXISTS lab_results;
            DROP TABLE IF EXISTS lab_draws;
            CREATE TABLE lab_draws (
                id INTEGER PRIMARY KEY, draw_date TEXT NOT NULL, draw_time TEXT, lab TEXT, fasted_hours REAL,
                trained_72h INTEGER, alcohol_5d INTEGER, biotin_stopped INTEGER, iron_stopped INTEGER, ill_recently INTEGER, note TEXT
            );
            CREATE TABLE lab_results (
                id INTEGER PRIMARY KEY, draw_id INTEGER NOT NULL REFERENCES lab_draws(id) ON DELETE CASCADE,
                marker_id TEXT NOT NULL, value REAL NOT NULL, unit TEXT NOT NULL, lab_low REAL, lab_high REAL
            );
            INSERT INTO lab_draws (id, draw_date, lab) VALUES (1, '2026-09-01', 'Fixture Lab');
            INSERT INTO lab_results (id, draw_id, marker_id, value, unit, lab_low, lab_high) VALUES (1, 1, 'ferritin', 85, 'ng/mL', 30, 400);
            PRAGMA user_version = 20;
            """)
        try FileManager.default.copyItem(at: url, to: location.databaseURL)

        let db = try XCTUnwrap(try service.openLiveDatabase())
        XCTAssertEqual(db.userVersion, Schema.currentVersion)

        let cat = try LabCatalogue(data: Data(#"{"markers":[{"id":"ferritin","name":"Ferritin","units":[{"unit":"ng/mL","default":true}]},{"id":"ua","name":"UA"}]}"#.utf8))
        let draws = LabDrawService(db, catalogue: cat)
        XCTAssertEqual(try draws.history(of: "ferritin").map(\.value), [85])
        try draws.addQualitativeResult(drawID: 1, markerID: "ua", textValue: "Negative")
        XCTAssertEqual(try draws.history(of: "ua").first?.textValue, "Negative")
    }

    func testRealOwnerDatabaseCopyMigratesCleanlyWhenPresent() throws {
        let realURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("output/fitness.sqlite")
        guard FileManager.default.fileExists(atPath: realURL.path) else { throw XCTSkip("output/fitness.sqlite not present") }
        try FileManager.default.copyItem(at: realURL, to: location.databaseURL)

        let db = try XCTUnwrap(try service.openLiveDatabase())
        XCTAssertEqual(db.userVersion, Schema.currentVersion)
    }
}
