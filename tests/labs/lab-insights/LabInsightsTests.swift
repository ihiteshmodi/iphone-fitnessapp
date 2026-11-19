import XCTest
@testable import FitnessCore

final class LabInsightsTests: XCTestCase {
    private let json = #"""
    {"markers": [
     {"id": "ferritin", "name": "Ferritin", "units": [{"unit": "ng/mL", "default": true}],
      "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 140, "unit": "ng/mL"}],
      "doctor": [{"op": ">", "value": 1500, "unit": "ng/mL", "urgency": "sameDay", "text": "Fixture: get seen today", "source": "T9"}],
      "whatToDo": [{"text": "Low-side fixture action", "when": "low"}, {"text": "High-side fixture action", "when": "high"},
                   {"text": "Drug fixture action", "when": "low", "tag": "drug"}]},
     {"id": "tsat", "name": "Transferrin saturation", "units": [{"unit": "%", "default": true}]},
     {"id": "glucose", "name": "Glucose", "units": [{"unit": "mg/dL", "default": true}],
      "bands": [{"label": "Optimal", "kind": "optimal", "low": 70, "high": 90, "unit": "mg/dL"}],
      "retest": [{"text": "Routine fixture", "minWeeks": 26, "maxWeeks": 52, "after": "routine"}]}
    ],
     "patterns": [{"id": "fixture-overload", "name": "Fixture overload", "computable": true, "needed": "all",
       "conditions": [{"marker": "ferritin", "op": ">", "value": 300, "unit": "ng/mL"}, {"marker": "tsat", "op": ">", "value": 45, "unit": "%"}],
       "meaning": "Fixture meaning", "whatToDo": ["Fixture step"], "source": "T14"}]}
    """#
    private var db: Database!
    private var catalogue: LabCatalogue!
    private var draws: LabDrawService!
    private let today = date("2027-03-02")

    override func setUpWithError() throws {
        db = try Database.inMemory()
        catalogue = try LabCatalogue(data: Data(json.utf8))
        draws = LabDrawService(db, catalogue: catalogue)
    }

    private func service(showDrug: Bool = false) -> InsightService {
        InsightService(db, daily: [], setup: [], labs: [LabInsightsRule(catalogue: catalogue, sex: .male, showDrugNotes: showDrug)])
    }

    private func results(_ day: String, _ values: [(String, Double, String)]) throws {
        let id = try draws.addDraw(LabDrawDraft(date: date(day)))
        for (marker, value, unit) in values { try draws.addResult(drawID: id, markerID: marker, value: value, unit: unit) }
    }

    func testADoctorLineIsAFixWithTheVaultsUrgency() throws {
        try results("2027-03-01", [("ferritin", 1600, "ng/mL")])

        let item = try XCTUnwrap(try service().labs(on: today).first)
        XCTAssertEqual(item.title, "Same day: Ferritin")
        XCTAssertEqual(item.severity, .fix)
        XCTAssertEqual(item.kind, .labs)
        XCTAssertTrue(item.detail.contains("Fixture: get seen today"), item.detail)
    }

    func testOutOfTheOptimalBandShowsThatSidesActionsAndHidesDrugNotes() throws {
        try results("2027-03-01", [("ferritin", 40, "ng/mL")])

        let item = try XCTUnwrap(try service().labs(on: today).first { $0.title == "Ferritin low" })
        XCTAssertTrue(item.detail.contains("Low-side fixture action"))
        XCTAssertFalse(item.detail.contains("High-side fixture action"))
        XCTAssertFalse(item.detail.contains("Drug fixture action"))
        XCTAssertTrue(try service(showDrug: true).labs(on: today).first { $0.title == "Ferritin low" }!.detail.contains("Drug fixture action"))
    }

    func testAPatternFiresOnlyWhenItsConditionsHold() throws {
        try results("2027-03-01", [("ferritin", 350, "ng/mL"), ("tsat", 50, "%")])
        XCTAssertTrue(try service().labs(on: today).contains { $0.title == "Fixture overload" })

        try results("2027-03-02", [("ferritin", 350, "ng/mL"), ("tsat", 30, "%")])
        XCTAssertFalse(try service().labs(on: today).contains { $0.title == "Fixture overload" })
    }

    func testDismissingHidesItUntilANewerResult() throws {
        try results("2027-02-01", [("ferritin", 40, "ng/mL")])
        let labs = service()
        try labs.dismiss(try XCTUnwrap(try labs.labs(on: today).first { $0.title == "Ferritin low" }))
        XCTAssertFalse(try labs.labs(on: today).contains { $0.title == "Ferritin low" })

        try results("2027-03-01", [("ferritin", 45, "ng/mL")])
        XCTAssertTrue(try labs.labs(on: today).contains { $0.title == "Ferritin low" })
    }

    func testValuesKeepTheirDecimals() {
        XCTAssertEqual([123.4, 4.85, 1600].map(LabInsightsRule.number), ["123.4", "4.85", "1600"])
    }

    func testARetestThatIsDueIsATip() throws {
        try results("2026-09-01", [("glucose", 80, "mg/dL")])

        let item = try XCTUnwrap(try service().labs(on: today).first { $0.title == "Retest Glucose" })
        XCTAssertEqual(item.severity, .tip)
        XCTAssertFalse(try service().labs(on: date("2027-01-01")).contains { $0.title == "Retest Glucose" })
    }
}
