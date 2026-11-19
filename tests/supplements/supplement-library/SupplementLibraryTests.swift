import XCTest
@testable import FitnessCore

final class SupplementLibraryTests: XCTestCase {
    private let json = """
    {"version": 1, "entries": [
      {"id": "creatine", "name": "Creatine monohydrate", "aliases": ["creatine"], "category": "Training", "verdict": "recommended",
       "verdict_text": "worth taking", "why": "Most studied.", "dose_text": "3-5 g a day", "dose_min": 3, "dose_max": 5, "dose_unit": "g",
       "test_first": [], "source": "05.09.01"},
      {"id": "fadogia", "name": "Fadogia agrestis", "aliases": ["fadogia"], "category": "Testosterone", "verdict": "not_recommended",
       "verdict_text": "avoid", "why": "Animal studies only and testicular toxicity.", "test_first": [], "source": "05.11.03"},
      {"id": "b12", "name": "Vitamin B12", "aliases": ["b12", "methylcobalamin"], "category": "Vitamins", "verdict": "conditional",
       "verdict_text": "test first", "why": "Plant eaters.", "test_first": ["B12", "MMA"], "source": "05.07.02"}
    ]}
    """
    private var library: SupplementLibrary!
    private var db: Database!

    override func setUpWithError() throws {
        library = try SupplementLibrary(data: Data(json.utf8))
        db = try Database.inMemory()
    }

    func testSearchFindsByNameOrAliasWithVerdictAndReason() {
        let found = library.search("fadogia agrestis")

        XCTAssertEqual(found.map(\.id), ["fadogia"])
        XCTAssertEqual(found.first?.verdict, .notRecommended)
        XCTAssertEqual(found.first?.why, "Animal studies only and testicular toxicity.")
    }

    func testMySupplementsAreMatchedToTheLibrary() {
        XCTAssertEqual(library.match("Creatine - ASES")?.id, "creatine")
        XCTAssertNil(library.match("Himalayan Salt"))
    }

    private func planSupplement(_ name: String, unit: String, quantity: Double, from day: String = "2026-11-01") throws {
        let id = try FoodLibrary(db).add(FoodDraft(name: name, kind: .supplement, unit: unit, baseQuantity: 1))
        try DietPlanService(db).addItem(foodID: id, quantity: quantity, meal: "Brunch", from: date(day))
    }

    func testADoseOutsideTheRangeOrANotRecommendedProductIsFlagged() throws {
        try planSupplement("Creatine - ASES", unit: "g", quantity: 12)
        try planSupplement("Fadogia 600", unit: "unit", quantity: 1)

        let items = try SupplementCheckRule(library: library).evaluate(on: date("2026-11-19"), db: db)

        let checks = try XCTUnwrap(items.first { $0.title == "Supplement checks" })
        XCTAssertTrue(checks.detail.contains("Creatine - ASES 12 g is above 3-5 g"), checks.detail)
        XCTAssertTrue(checks.detail.contains("Fadogia 600 is not recommended"), checks.detail)
    }

    func testTestFirstSupplementsArePointedToBloodwork() throws {
        try planSupplement("Vitamin B12 1500 mcg", unit: "unit", quantity: 1)

        let tip = try XCTUnwrap(try SupplementCheckRule(library: library).evaluate(on: date("2026-11-19"), db: db).first { $0.title == "Test first" })
        XCTAssertEqual(tip.severity, .tip)
        XCTAssertTrue(tip.detail.contains("B12, MMA"))
    }

    func testOneNewSupplementAtATime() throws {
        try planSupplement("Glycine - ASES", unit: "g", quantity: 3, from: "2026-11-10")
        try planSupplement("Boron", unit: "unit", quantity: 1, from: "2026-11-17")

        let tip = try XCTUnwrap(try SupplementOnRampRule().evaluate(on: date("2026-11-19"), db: db).first)
        XCTAssertEqual(tip.severity, .tip)
        XCTAssertTrue(tip.detail.contains("Boron"))
        XCTAssertTrue(tip.detail.contains("2-4 weeks"))
    }

    func testMultivitaminWhatIf() throws {
        let tablet = NutrientProfile(values: [.vitaminD: 25, .zinc: 15], unknown: [])
        let food = NutrientProfile(values: [.zinc: 10], unknown: [])

        let two = MultivitaminWhatIf.rows(perTablet: tablet, tablets: 2, rest: food)
        let three = MultivitaminWhatIf.rows(perTablet: tablet, tablets: 3, rest: food)

        let d = try XCTUnwrap(two.first { $0.nutrient == .vitaminD })
        XCTAssertEqual([d.amount, d.target], [50, 20])
        XCTAssertTrue(d.isFatSoluble)
        let zinc2 = try XCTUnwrap(two.first { $0.nutrient == .zinc })
        XCTAssertEqual(zinc2.amount, 40)
        XCTAssertFalse(zinc2.isOverLimit)
        XCTAssertTrue(try XCTUnwrap(three.first { $0.nutrient == .zinc }).isOverLimit)
        XCTAssertEqual(Nutrient.b6.upperLimit, nil, "two limits, settled in Labs")
        XCTAssertEqual(Nutrient.b6.upperLimitNote, "100 mg (US) or 12 mg (EU)")
    }
}
