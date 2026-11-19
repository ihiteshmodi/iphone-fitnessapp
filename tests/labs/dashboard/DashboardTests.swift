import XCTest
@testable import FitnessCore

final class DashboardTests: XCTestCase {
    private let json = #"""
    {"markers": [
     {"id": "ferritin", "name": "Ferritin", "chapter": "Iron Panel", "units": [{"unit": "ng/mL", "default": true}],
      "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 140, "unit": "ng/mL"}]},
     {"id": "glucose", "name": "Glucose", "chapter": "Metabolic", "units": [{"unit": "mg/dL", "default": true}],
      "bands": [{"label": "Optimal", "kind": "optimal", "low": 70, "high": 90, "unit": "mg/dL"}]},
     {"id": "apob", "name": "ApoB", "chapter": "Lipids", "units": [{"unit": "mg/dL", "default": true}]},
     {"id": "lpa", "name": "Lp(a)", "chapter": "Lipids", "units": [{"unit": "nmol/L", "default": true}]},
     {"id": "total-testosterone", "name": "Total testosterone", "chapter": "Sex Hormones", "units": [{"unit": "ng/dL", "default": true}]}
    ]}
    """#
    private var db: Database!
    private var catalogue: LabCatalogue!
    private var draws: LabDrawService!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        catalogue = try LabCatalogue(data: Data(json.utf8))
        draws = LabDrawService(db, catalogue: catalogue)
    }

    private func dashboard() throws -> LabDashboard {
        try LabDashboard.build(catalogue: catalogue, db: db, today: date("2027-01-10"))
    }

    private func result(_ marker: String, _ value: Double, _ unit: String, _ day: String) throws {
        try draws.addResult(drawID: try draws.addDraw(LabDrawDraft(date: date(day))), markerID: marker, value: value, unit: unit)
    }

    func testOneTilePerChapterWithMyResults() throws {
        try result("ferritin", 30, "ng/mL", "2026-05-03")
        try result("ferritin", 40, "ng/mL", "2026-10-01")
        try result("glucose", 80, "mg/dL", "2026-10-01")

        let tiles = try dashboard().systems

        let iron = try XCTUnwrap(tiles.first { $0.chapter == "Iron Panel" })
        XCTAssertEqual([iron.optimal, iron.outside, iron.tested], [0, 1, 1])
        XCTAssertEqual(iron.keyMarker?.id, "ferritin")
        XCTAssertEqual(iron.trend.map(\.value), [30, 40])
        XCTAssertEqual(tiles.first { $0.chapter == "Metabolic" }?.optimal, 1)
        XCTAssertNil(tiles.first { $0.chapter == "Sex Hormones" }, "no tile without results")
    }

    func testHeartRiskListsTheVaultsHeartMarkers() throws {
        try result("apob", 80, "mg/dL", "2026-10-01")

        let heart = try dashboard().heart

        XCTAssertEqual(heart.first { $0.marker.id == "apob" }?.latest?.value, 80)
        XCTAssertNil(heart.first { $0.marker.id == "lpa" }?.latest, "Lp(a) not tested")
    }

    func testHormonesOverTimeOldestFirst() throws {
        for (day, value) in [("2023-05-27", 400.0), ("2022-11-27", 380.0), ("2026-10-02", 445.0)] {
            try result("total-testosterone", value, "ng/dL", day)
        }

        let series = try XCTUnwrap(try dashboard().hormones.first { $0.marker.id == "total-testosterone" })
        XCTAssertEqual(series.points.map(\.value), [380, 400, 445])
    }

    func testBiologicalAgeNamesWhatIsMissing() throws {
        try LabSettings(db).setBirthDate(date("1998-06-09"))
        try result("glucose", 80, "mg/dL", "2026-10-01")

        guard case .missing(let inputs) = try dashboard().biologicalAge else { return XCTFail("inputs are missing") }
        XCTAssertTrue(inputs.contains(.hsCRP))
    }
}
