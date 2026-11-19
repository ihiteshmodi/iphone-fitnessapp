import XCTest
@testable import FitnessCore

/// Version 10 adds break mode; a version 9 file gets the table and keeps its data.
final class BreakSchemaTests: DatabaseFileTestCase {
    func testOpeningAVersion9DatabaseAddsBreakPeriodsAndKeepsItsData() throws {
        let url = try makeFitnessDatabase(named: "v9.sqlite")
        let raw = try Database(path: url.path)
        try raw.execute("DROP TABLE break_periods")
        try raw.execute("INSERT INTO body_weights (measured_on, weight_kg) VALUES ('2026-11-19', 64.85)")
        try raw.runScript("PRAGMA user_version = 9")
        try FileManager.default.copyItem(at: url, to: location.databaseURL)

        let db = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertGreaterThanOrEqual(db.userVersion, 10)
        XCTAssertEqual(try BreakModeService(db).periods(), [])
        XCTAssertEqual(try db.query("SELECT weight_kg FROM body_weights").map { $0.double("weight_kg") }, [64.85])
    }
}
