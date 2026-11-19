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
}
