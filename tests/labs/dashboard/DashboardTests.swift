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

    func testWithNoCompleteDrawTheClosestOneIsShown() throws {
        catalogue = PhenoAge.inputCatalogue
        draws = LabDrawService(db, catalogue: catalogue)
        try LabSettings(db).setBirthDate(date("1998-06-09"))
        let may = try draws.addDraw(LabDrawDraft(date: date("2026-05-03")))
        for input in PhenoAgeInput.allCases where input != .hsCRP {
            guard let (id, unit) = input.marker else { continue }
            try draws.addResult(drawID: may, markerID: id, value: 5, unit: unit)
        }
        try result("glucose", 80, "mg/dL", "2026-10-01")

        let board = try dashboard()

        XCTAssertEqual(board.biologicalAge, .missing([.hsCRP]))
        XCTAssertEqual(board.biologicalAgeDraw, date("2026-05-03"))
    }

    func testLatestSnapshotCombinesSplitDrawsIgnoresSupersededValuesAndClassifiesTestedMarkers() throws {
        let splitJSON = #"""
        {
          "markers": [
            {"id": "mpv", "name": "MPV", "chapter": "CBC", "units": [{"unit": "fL", "default": true}],
             "bands": [{"label": "Lab", "kind": "lab", "low": 7.5, "high": 11.5, "unit": "fL"},
                       {"label": "Optimal", "kind": "optimal", "low": 8.5, "high": 11.0, "unit": "fL"}]},
            {"id": "platelets", "name": "Platelets", "chapter": "CBC",
             "units": [{"unit": "per µL", "default": true}, {"unit": "x10^3/uL", "toDefault": 1000}],
             "bands": [{"label": "Lab", "kind": "lab", "low": 150000, "high": 400000, "unit": "per µL"},
                       {"label": "Optimal", "kind": "optimal", "low": 175000, "high": 300000, "unit": "per µL"}]},
            {"id": "total-testosterone", "name": "Total Testosterone", "chapter": "Hormones",
             "units": [{"unit": "ng/dL", "default": true}],
             "bands": [{"label": "Lab", "kind": "lab", "low": 264, "high": 916, "unit": "ng/dL"},
                       {"label": "Optimal", "kind": "optimal", "low": 600, "high": 900, "unit": "ng/dL"}]},
            {"id": "free-testosterone", "name": "Free Testosterone", "chapter": "Hormones",
             "units": [{"unit": "pg/mL", "default": true}],
             "bands": [{"label": "Optimal", "kind": "optimal", "low": 12, "high": 25, "unit": "pg/mL"}]},
            {"id": "shbg", "name": "SHBG", "chapter": "Hormones",
             "units": [{"unit": "nmol/L", "default": true}],
             "bands": [{"label": "Optimal", "kind": "optimal", "low": 20, "high": 45, "unit": "nmol/L"}]}
          ],
          "panels": [{"id": "core", "name": "Core", "markers": ["total-testosterone", "shbg"], "when": "first"}],
          "patterns": [
            {"id": "mpv-underproduction", "name": "Low MPV + low platelets (underproduction)", "computable": true, "needed": "all",
             "markers": ["mpv", "platelets"],
             "conditions": [{"marker": "mpv", "op": "<", "value": 7.5, "unit": "fL"},
                            {"marker": "platelets", "op": "<", "value": 150000, "unit": "per µL"}],
             "meaning": "Underproduction."}
          ]
        }
        """#
        let cat = try LabCatalogue(data: Data(splitJSON.utf8))
        let localDraws = LabDrawService(db, catalogue: cat)

        // Superseded 2025 draw with low MPV + low Platelets
        let d1 = try localDraws.addDraw(LabDrawDraft(date: date("2025-09-27"), lab: "Vardhaman Jain Trust"))
        try localDraws.addResult(drawID: d1, markerID: "mpv", value: 7.2, unit: "fL")
        try localDraws.addResult(drawID: d1, markerID: "platelets", value: 140000, unit: "per µL")

        // Newer 2026-05-03 draw with healthy MPV + Platelets
        let d2 = try localDraws.addDraw(LabDrawDraft(date: date("2026-05-03"), lab: "Healthians Labs"))
        try localDraws.addResult(drawID: d2, markerID: "mpv", value: 8.8, unit: "fL")
        try localDraws.addResult(drawID: d2, markerID: "platelets", value: 203, unit: "x10^3/uL")

        // Split same-day draws across two labs
        let d3 = try localDraws.addDraw(LabDrawDraft(date: date("2026-10-02"), lab: "Orange Health Labs"))
        try localDraws.addResult(drawID: d3, markerID: "total-testosterone", value: 445, unit: "ng/dL")
        try localDraws.addResult(drawID: d3, markerID: "free-testosterone", value: 10.5, unit: "pg/mL")

        let d4 = try localDraws.addDraw(LabDrawDraft(date: date("2026-10-02"), lab: "Thyrocare"))
        try localDraws.addResult(drawID: d4, markerID: "shbg", value: 58, unit: "nmol/L")

        let board = try LabDashboard.build(catalogue: cat, db: db, today: date("2026-11-26"))
        let snap = board.snapshot

        XCTAssertFalse(snap.simplePatterns.contains { $0.id == "mpv-underproduction" }, "Old superseded MPV/Platelets ignored")
        XCTAssertTrue(snap.cleanCompanionChecks.contains { $0.markerIDs.contains("mpv") && $0.markerIDs.contains("platelets") })
        XCTAssertTrue(snap.discordances.contains { $0.id == "discordance-shbg-free-t" }, "Split draws combine latest Total T, Free T, and SHBG")

        let ttRow = try XCTUnwrap(snap.testedRows.first { $0.marker.id == "total-testosterone" })
        XCTAssertTrue(ttRow.isCore)
        XCTAssertEqual(ttRow.rangeClassification, .withinLabBelowOptimal)
        XCTAssertTrue(ttRow.interpretations.contains { $0.contains("SHBG") })

        let mpvRow = try XCTUnwrap(snap.testedRows.first { $0.marker.id == "mpv" })
        XCTAssertFalse(mpvRow.isCore)
        XCTAssertEqual(mpvRow.rangeClassification, .optimal)
        XCTAssertEqual(mpvRow.result.date, date("2026-05-03"))
    }
}
