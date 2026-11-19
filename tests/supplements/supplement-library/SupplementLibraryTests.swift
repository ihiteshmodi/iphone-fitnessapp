import XCTest
@testable import FitnessCore

final class SupplementLibraryTests: XCTestCase {
    private let json = """
    {"version": 1, "entries": [
      {"id": "creatine", "name": "Creatine monohydrate", "aliases": ["creatine"], "category": "Training", "verdict": "recommended",
       "verdict_text": "worth taking", "why": "Most studied.", "dose_text": "3-5 g a day", "dose_min": 3, "dose_max": 5, "dose_unit": "g",
       "test_first": [], "source": "05.09.01"},
      {"id": "eca", "name": "ECA stack", "aliases": ["eca"], "category": "Fat loss", "verdict": "not_recommended", "why": "Heart risk.", "source": "05.13"},
      {"id": "d3", "name": "Vitamin D3", "aliases": ["d3"], "category": "Vitamins", "verdict": "recommended", "why": "Common gap.", "source": "05.07"},
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

    func testAliasesMatchWholeWordsOnly() {
        XCTAssertEqual(library.match("D3 5000IU and K2 capsule")?.id, "d3")
        XCTAssertNil(library.match("Becadexamine"))
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

    func testTheDoseIsTheDayTotalAndSupplementsInsideRecipesAreChecked() throws {
        try planSupplement("Creatine - ASES", unit: "g", quantity: 1)
        let plans = DietPlanService(db)
        let creatine = try XCTUnwrap(try FoodLibrary(db).food(named: "Creatine - ASES")).id
        try plans.addItem(foodID: creatine, quantity: 1, meal: "Dinner", from: date("2026-11-01"))
        let foods = FoodLibrary(db)
        let fadogia = try foods.add(FoodDraft(name: "Fadogia powder", kind: .supplement, unit: "g", baseQuantity: 1))
        let shake = try foods.add(FoodDraft(name: "Shake", kind: .recipe, unit: "glass", baseQuantity: 1, recipeMakes: 2))
        try foods.setIngredients(of: shake, [RecipeLine(foodID: fadogia, quantity: 4)])
        try plans.addItem(foodID: shake, quantity: 1, meal: "Dinner", from: date("2026-11-01"))

        let checks = try XCTUnwrap(try SupplementCheckRule(library: library).evaluate(on: date("2026-11-19"), db: db).first { $0.title == "Supplement checks" })

        XCTAssertTrue(checks.detail.contains("Creatine - ASES 2 g is below 3-5 g"), checks.detail)
        XCTAssertTrue(checks.detail.contains("Fadogia powder (in Shake) is not recommended"), checks.detail)
    }

    func testSupplementsInTheFirstPlanAreTheStartingPointNotNew() throws {
        try planSupplement("Glycine - ASES", unit: "g", quantity: 3, from: "2026-11-10")
        try planSupplement("Boron", unit: "unit", quantity: 1, from: "2026-11-10")

        XCTAssertTrue(try SupplementOnRampRule().evaluate(on: date("2026-11-19"), db: db).isEmpty)
    }

    func testTestFirstSupplementsArePointedToBloodwork() throws {
        try planSupplement("Vitamin B12 1500 mcg", unit: "unit", quantity: 1)
        try planSupplement("B12 spray", unit: "unit", quantity: 1)

        let tip = try XCTUnwrap(try SupplementCheckRule(library: library).evaluate(on: date("2026-11-19"), db: db).first { $0.title == "Test first" })
        XCTAssertEqual(tip.severity, .tip)
        XCTAssertTrue(tip.detail.contains("B12, MMA"))
        XCTAssertEqual(tip.detail.components(separatedBy: "B12, MMA").count, 2, "each library entry is listed once")
    }

    func testOneNewSupplementAtATime() throws {
        try planSupplement("Creatine - ASES", unit: "g", quantity: 3, from: "2026-10-26")
        try planSupplement("Glycine - ASES", unit: "g", quantity: 3, from: "2026-11-10")
        try planSupplement("Boron", unit: "unit", quantity: 1, from: "2026-11-17")

        let tip = try XCTUnwrap(try SupplementOnRampRule().evaluate(on: date("2026-11-19"), db: db).first)
        XCTAssertEqual(tip.severity, .tip)
        XCTAssertTrue(tip.detail.contains("Boron"))
        XCTAssertTrue(tip.detail.contains("2-4 weeks"))
    }

    func testAMultivitaminHasSeveralVitaminsAndAlmostNoCalories() {
        let multi = FoodDraft(name: "Becadexamine", kind: .supplement, unit: "unit", baseQuantity: 1,
                              nutrients: [.vitaminA: 1500, .b1: 5, .b3: 45, .folate: 1500, .zinc: 10])
        let salt = FoodDraft(name: "Himalayan Salt", kind: .supplement, baseQuantity: 100,
                             sodium: 38000, nutrients: [.vitaminA: 0, .b1: 0, .b3: 0, .folate: 0])
        let milk = FoodDraft(name: "Milk powder", kind: .supplement, baseQuantity: 100, protein: 35, carbs: 52, fat: 1,
                             nutrients: [.vitaminA: 6, .b2: 1.5, .b12: 4, .vitaminD: 0.1])

        XCTAssertEqual([multi, salt, milk].map(MultivitaminWhatIf.isMultivitamin), [true, false, false])
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
