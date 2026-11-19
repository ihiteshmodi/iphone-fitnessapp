import XCTest
@testable import FitnessCore

final class LabsReviewTests: XCTestCase {
    private let json = #"""
    {"markers": [
     {"id": "ferritin", "name": "Ferritin", "chapter": "Iron", "units": [{"unit": "ng/mL", "default": true}],
      "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 140, "unit": "ng/mL"}]},
     {"id": "a", "name": "A", "chapter": "X", "units": [{"unit": "u", "default": true}]},
     {"id": "b", "name": "B", "chapter": "X", "units": [{"unit": "u", "default": true}]},
     {"id": "c", "name": "C", "chapter": "X", "computed": true, "units": [{"unit": "u", "default": true}],
      "formula": {"expr": "{a} - {b}", "inputs": {"a": "u", "b": "u"}}}
    ]}
    """#
    private var db: Database!
    private var catalogue: LabCatalogue!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        catalogue = try LabCatalogue(data: Data(json.utf8))
    }

    private func export(insights: [Insight] = []) throws -> String {
        try LabsReviewService(db, catalogue: catalogue).markdown(on: date("2026-11-19"), insights: insights)
    }

    func testEachDrawListsItsResultsReadAgainstTheVault() throws {
        let draws = LabDrawService(db, catalogue: catalogue)
        let id = try draws.addDraw(LabDrawDraft(date: date("2026-05-03"), fastedHours: 12))
        try draws.addResult(drawID: id, markerID: "ferritin", value: 40, unit: "ng/mL", labLow: 30, labHigh: 400)
        try draws.addResult(drawID: id, markerID: "a", value: 10, unit: "u")
        try draws.addResult(drawID: id, markerID: "b", value: 4, unit: "u")

        let text = try export()

        XCTAssertTrue(text.contains("## 3 May 2026"), text)
        XCTAssertTrue(text.contains("fasted 12 h"), text)
        XCTAssertTrue(text.contains("Ferritin: 40 ng/mL, low (lab range 30–400)"), text)
        XCTAssertTrue(text.contains("C: 6 u (calculated)"), text)
    }

    func testBiologicalAgeAndOpenItems() throws {
        try LabSettings(db).setBirthDate(date("1998-06-09"))
        let draws = LabDrawService(db, catalogue: PhenoAge.inputCatalogue)
        try draws.addResult(drawID: try draws.addDraw(LabDrawDraft(date: date("2026-05-03"))), markerID: "albumin", value: 4.5, unit: "g/dL")
        catalogue = PhenoAge.inputCatalogue
        let open = Insight(ruleID: "lab-band-ferritin", kind: .labs, severity: .improve, title: "Ferritin low", detail: "", why: "")

        let text = try export(insights: [open])

        XCTAssertTrue(text.contains("PhenoAge: missing"), text)
        XCTAssertTrue(text.contains("hs-crp"), text)
        XCTAssertTrue(text.contains("- Ferritin low"), text)
    }
}
