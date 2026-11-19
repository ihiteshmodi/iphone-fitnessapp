import XCTest
@testable import FitnessCore

final class TestFirstTests: XCTestCase {
    private let json = #"""
    {"markers": [
     {"id": "ferritin", "name": "Ferritin", "chapter": "Iron", "units": [{"unit": "ng/mL", "default": true}],
      "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 140, "unit": "ng/mL"}]},
     {"id": "b12", "name": "Vitamin B12", "aliases": ["B12"], "chapter": "Vitamins", "units": [{"unit": "pg/mL", "default": true}]},
     {"id": "mma", "name": "Methylmalonic acid", "aliases": ["MMA"], "chapter": "Vitamins", "units": [{"unit": "nmol/L", "default": true}]},
     {"id": "mcv", "name": "MCV", "chapter": "CBC", "units": [{"unit": "fL", "default": true}]}
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

    private var lookup: LabTestLookup { LabTestLookup(catalogue: catalogue, draws: draws, sex: .male) }

    private func result(_ marker: String, _ value: Double, _ unit: String, _ day: String) throws {
        try draws.addResult(drawID: try draws.addDraw(LabDrawDraft(date: date(day))), markerID: marker, value: value, unit: unit)
    }

    func testATestNameFindsItsMarkerAndMyLatestResult() throws {
        try result("ferritin", 40, "ng/mL", "2026-05-03")

        XCTAssertEqual(try lookup.summary(of: "Ferritin"), "Ferritin 40 ng/mL on 3 May 2026 (low)")
    }

    func testNotesInBracketsAreReadAsWell() {
        XCTAssertEqual(lookup.marker(forTest: "B12 (check first)")?.id, "b12")
        XCTAssertEqual(lookup.marker(forTest: "CBC (MCV)")?.id, "mcv")
    }

    func testSeveralTestsInOneNameAndASampleWordInFront() throws {
        XCTAssertEqual(lookup.markers(forTest: "Ferritin / B12").map(\.id), ["ferritin", "b12"])
        XCTAssertEqual(lookup.markers(forTest: "serum ferritin (on high dose)").map(\.id), ["ferritin"])
        XCTAssertEqual(try lookup.summary(of: "Ferritin, MMA"), "Ferritin not tested yet; MMA not tested yet")
    }

    func testATestNotDoneYetAndOneTheCatalogueDoesNotKnow() throws {
        XCTAssertEqual(try lookup.summary(of: "MMA"), "MMA not tested yet")
        XCTAssertEqual(try lookup.summary(of: "DEXA"), "DEXA")
    }

    func testTheSupplementCheckNamesMyResults() throws {
        let library = try SupplementLibrary(data: Data("""
        {"version": 1, "entries": [{"id": "b12", "name": "Vitamin B12", "aliases": ["b12"], "category": "Vitamins",
          "verdict": "conditional", "why": "Plant eaters.", "test_first": ["B12", "MMA"], "source": "05.07.02"}]}
        """.utf8))
        let food = try FoodLibrary(db).add(FoodDraft(name: "Vitamin B12 1500 mcg", kind: .supplement, unit: "unit", baseQuantity: 1))
        try DietPlanService(db).addItem(foodID: food, quantity: 1, meal: "Breakfast", from: date("2026-11-01"))
        try result("b12", 300, "pg/mL", "2026-05-03")

        let tip = try XCTUnwrap(try SupplementCheckRule(library: library, labs: catalogue).evaluate(on: date("2026-11-19"), db: db)
            .first { $0.title == "Test first" })

        XCTAssertTrue(tip.detail.contains("Vitamin B12 300 pg/mL on 3 May 2026"), tip.detail)
        XCTAssertTrue(tip.detail.contains("MMA not tested yet"), tip.detail)
    }
}
