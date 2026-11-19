import XCTest
@testable import FitnessCore

/// Made-up catalogue values: the real catalogue is a bundled vault file that never enters the repository.
let fixtureCatalogueJSON = #"""
{"markers": [
 {"id": "ferritin", "name": "Ferritin", "aliases": ["serum ferritin"], "chapter": "Iron Panel", "lesson": "02.10.02",
  "units": [{"unit": "ng/mL", "default": true}, {"unit": "µg/L", "toDefault": 1}], "needsLabRange": false,
  "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 140, "unit": "ng/mL", "sex": "male", "source": "T1"}],
  "doctor": [{"op": ">", "value": 900, "unit": "ng/mL", "sex": "any", "urgency": "soon", "text": "Fixture doctor line", "source": "T1"}],
  "retest": [{"text": "Fixture retest", "minWeeks": 8, "maxWeeks": 12, "after": "change", "source": "T1"}],
  "prep": ["iron-pills"]},
 {"id": "glucose", "name": "Glucose", "aliases": ["fasting glucose"], "chapter": "Metabolic", "lesson": "02.05.01",
  "units": [{"unit": "mg/dL", "default": true}, {"unit": "mmol/L", "toDefault": 18}]}
],
 "prep": [{"id": "iron-pills", "text": "Stop iron pills", "hoursBefore": 96, "markers": ["ferritin"], "source": "T0"}],
 "panels": [{"id": "iron", "name": "Iron panel", "markers": ["ferritin"], "when": "first", "source": "T0"}]
}
"""#

final class LabDrawTests: XCTestCase {
    private var db: Database!
    private var draws: LabDrawService!
    private var catalogue: LabCatalogue!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        catalogue = try LabCatalogue(data: Data(fixtureCatalogueJSON.utf8))
        draws = LabDrawService(db, catalogue: catalogue)
    }

    private func draw(_ day: String) throws -> Int {
        try draws.addDraw(LabDrawDraft(date: date(day)))
    }

    func testADrawKeepsItsPrepState() throws {
        let id = try draws.addDraw(LabDrawDraft(date: date("2026-12-02"), time: "08:10", lab: "Fixture lab", fastedHours: 11,
                                                trainedHard72h: true, alcohol5d: false, biotinStopped: true, ironStopped: nil, illRecently: false))

        let saved = try XCTUnwrap(try draws.draws().first { $0.id == id })
        XCTAssertEqual(saved.draft.time, "08:10")
        XCTAssertEqual(saved.draft.fastedHours, 11)
        XCTAssertEqual(saved.draft.trainedHard72h, true)
        XCTAssertEqual(saved.draft.biotinStopped, true)
        XCTAssertNil(saved.draft.ironStopped, "an unanswered question stays unanswered")
    }

    func testResultsKeepTheTypedUnitAndTheDefaultUnit() throws {
        let id = try draw("2026-12-02")

        try draws.addResult(drawID: id, markerID: "glucose", value: 5.0, unit: "mmol/L")

        let result = try XCTUnwrap(try draws.history(of: "glucose").first)
        XCTAssertEqual(result.value, 5.0)
        XCTAssertEqual(result.unit, "mmol/L")
        XCTAssertEqual(result.defaultValue ?? 0, 90, accuracy: 1e-9)
        XCTAssertEqual(result.defaultUnit, "mg/dL")
    }

    func testAnUnknownUnitIsRefused() throws {
        let id = try draw("2026-12-02")

        XCTAssertThrowsError(try draws.addResult(drawID: id, markerID: "ferritin", value: 48, unit: "pmol/L")) { error in
            XCTAssertTrue("\(error)".contains("pmol/L is not a unit the catalogue gives for Ferritin"), "\(error)")
        }
    }

    func testHistoryIsNewestFirstAndKeepsTheLabRange() throws {
        try draws.addResult(drawID: try draw("2026-06-01"), markerID: "ferritin", value: 40, unit: "ng/mL")
        try draws.addResult(drawID: try draw("2026-12-02"), markerID: "ferritin", value: 48, unit: "ng/mL", labLow: 30, labHigh: 400)

        let history = try draws.history(of: "ferritin")

        XCTAssertEqual(history.map(\.date.string), ["2026-12-02", "2026-06-01"])
        XCTAssertEqual(history.first?.labLow, 30)
        XCTAssertEqual(history.first?.labHigh, 400)
    }

    func testDeletingADrawRemovesItsResults() throws {
        let id = try draw("2026-12-02")
        try draws.addResult(drawID: id, markerID: "ferritin", value: 48, unit: "ng/mL")
        try draws.addResult(drawID: id, markerID: "glucose", value: 88, unit: "mg/dL")

        try draws.deleteDraw(id)

        XCTAssertTrue(try draws.history(of: "ferritin").isEmpty)
        XCTAssertTrue(try draws.history(of: "glucose").isEmpty)
    }

    func testTheCatalogueFindsMarkersByNameOrAlias() {
        XCTAssertEqual(catalogue.search("serum").map(\.id), ["ferritin"])
        XCTAssertEqual(catalogue.marker("glucose")?.defaultUnit, "mg/dL")
        XCTAssertEqual(catalogue.panel("iron")?.markers, ["ferritin"])
    }
}
