import XCTest
@testable import FitnessCore

final class DrawPlanningTests: XCTestCase {
    private let json = #"""
    {"markers": [
     {"id": "ferritin", "name": "Ferritin", "aliases": ["serum ferritin"], "units": [{"unit": "ng/mL", "default": true}],
      "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 140, "unit": "ng/mL"}],
      "retest": [{"text": "Out-of-band fixture", "minWeeks": 8, "maxWeeks": 12, "after": "abnormal"},
                 {"text": "Routine fixture", "minWeeks": 26, "maxWeeks": 52, "after": "routine"}]},
     {"id": "glucose", "name": "Glucose", "units": [{"unit": "mg/dL", "default": true}],
      "bands": [{"label": "Optimal", "kind": "optimal", "low": 70, "high": 90, "unit": "mg/dL"}],
      "retest": [{"text": "Routine fixture", "minWeeks": 26, "maxWeeks": 52, "after": "routine"}]},
     {"id": "uric-acid", "name": "Uric acid", "units": [{"unit": "mg/dL", "default": true}]},
     {"id": "tsh", "name": "TSH", "units": [{"unit": "mIU/L", "default": true}]},
     {"id": "tsat", "name": "Transferrin saturation", "units": [{"unit": "%", "default": true}]}
    ],
     "panels": [
      {"id": "sugar", "name": "Sugar", "markers": ["glucose"], "askFor": "fasting", "when": "first"},
      {"id": "iron", "name": "Iron panel", "markers": ["ferritin"], "when": "first"},
      {"id": "chem", "name": "Chemistry", "markers": ["uric-acid"], "askFor": "order uric acid by name", "when": "first"},
      {"id": "ferritin-off", "name": "If ferritin is off", "markers": ["tsat"], "when": "conditional", "trigger": "Odd ferritin: add TSAT", "triggerMarkers": ["ferritin"]},
      {"id": "thyroid-extra", "name": "Thyroid add-on", "markers": ["tsh"], "when": "conditional", "triggerMarkers": ["glucose"]},
      {"id": "rare", "name": "Rare tests", "markers": ["sugar", "anti-ccp", "serum ferritin"], "when": "conditional", "triggerMarkers": ["ferritin"]}
     ],
     "prep": [
      {"id": "biotin", "text": "Stop biotin", "hoursBefore": 72},
      {"id": "iron-pills", "text": "Stop iron pills", "hoursBefore": 96, "markers": ["ferritin"]},
      {"id": "thyroid-only", "text": "Thyroid-only step", "hoursBefore": 24, "markers": ["tsh"]},
      {"id": "fast", "text": "Fast, water only", "hoursBefore": 12}
     ]}
    """#
    private var catalogue: LabCatalogue!
    private var db: Database!
    private var draws: LabDrawService!

    override func setUpWithError() throws {
        catalogue = try LabCatalogue(data: Data(json.utf8))
        db = try Database.inMemory()
        draws = LabDrawService(db, catalogue: catalogue)
    }

    private func planner() -> DrawPlanner { DrawPlanner(catalogue: catalogue, draws: draws, sex: .male) }

    private func result(_ marker: String, _ value: Double, _ unit: String, on day: String) throws {
        try draws.addResult(drawID: try draws.addDraw(LabDrawDraft(date: date(day))), markerID: marker, value: value, unit: unit)
    }

    func testTheFirstOrderIsTheBaselineWithEveryTestNamed() throws {
        let order = try planner().order()

        XCTAssertEqual(order.map(\.panel.id), ["sugar", "iron", "chem"])
        XCTAssertEqual(order.flatMap(\.tests).map(\.name), ["Glucose", "Ferritin", "Uric acid"])
        XCTAssertEqual(order.last?.panel.askFor, "order uric acid by name")
    }

    func testAnOffResultAddsItsConditionalPanel() throws {
        try result("ferritin", 40, "ng/mL", on: "2026-09-01")
        try result("glucose", 80, "mg/dL", on: "2026-09-01")

        let order = try planner().order()

        XCTAssertEqual(order.map(\.panel.id), ["sugar", "iron", "chem", "ferritin-off", "rare"])
        XCTAssertEqual(order[3].reason, "Odd ferritin: add TSAT")
    }

    func testPanelNamesExpandAliasesResolveAndUnknownTestsAreStillNamed() throws {
        try result("ferritin", 40, "ng/mL", on: "2026-09-01")

        let rare = try XCTUnwrap(try planner().order().first { $0.panel.id == "rare" })

        XCTAssertEqual(rare.tests.map(\.name), ["Glucose", "Anti ccp", "Ferritin"])
        XCTAssertEqual(rare.tests.map(\.markerID), ["glucose", nil, "ferritin"])
    }

    func testThePrepTimelineCountsBackFromTheDrawAndSkipsTestsNotOrdered() throws {
        let steps = planner().prepTimeline(drawDate: date("2026-12-10"), drawHour: 8, ordered: ["glucose", "ferritin", "uric-acid"])

        XCTAssertEqual(steps.map(\.step.id), ["iron-pills", "biotin", "fast"])
        XCTAssertEqual(steps.map(\.date.string), ["2026-12-06", "2026-12-07", "2026-12-09"])
    }

    func testRetestTiming() throws {
        try result("ferritin", 40, "ng/mL", on: "2026-09-01")
        try result("glucose", 80, "mg/dL", on: "2026-09-01")

        let due = try planner().retests()

        let ferritin = try XCTUnwrap(due.first { $0.marker.id == "ferritin" })
        XCTAssertEqual(ferritin.from?.string, "2026-10-27")
        XCTAssertEqual(ferritin.until?.string, "2026-11-24")
        XCTAssertEqual(ferritin.rule?.text, "Out-of-band fixture")
        XCTAssertEqual(due.first { $0.marker.id == "glucose" }?.from?.string, "2027-03-02")
        let uric = try XCTUnwrap(due.first { $0.marker.id == "uric-acid" })
        XCTAssertNil(uric.lastDate)
        XCTAssertEqual(uric.note, "Baseline: not tested yet")
    }
}
