import XCTest
@testable import FitnessCore

final class DietReviewTests: XCTestCase {
    private var db: Database!
    private var library: FoodLibrary!
    private var diet: DietDayService!
    private let today = date("2026-11-19")

    override func setUpWithError() throws {
        db = try Database.inMemory()
        library = FoodLibrary(db)
        diet = DietDayService(db)
        let plans = DietPlanService(db)
        let shake = try library.add(FoodDraft(name: "Shake", unit: "unit", baseQuantity: 1, protein: 40, carbs: 30, fat: 5, fiber: 1, nutrients: [.leucine: 3.4]))
        let dal = try library.add(FoodDraft(name: "Dal", unit: "unit", baseQuantity: 1, protein: 30, carbs: 60, fat: 6, fiber: 2, nutrients: [.leucine: 2.4]))
        try plans.addItem(foodID: shake, quantity: 1, meal: "Brunch", from: date("2026-11-01"))
        try plans.addItem(foodID: dal, quantity: 1, meal: "Dinner", from: date("2026-11-01"))
    }

    private func report(insights: [Insight] = [], supplementLibrary: SupplementLibrary? = nil) throws -> String {
        try DietReviewService(db, library: supplementLibrary).markdown(on: today, insights: insights)
    }

    func testThePlannedDayIsListedMealByMeal() throws {
        let text = try report()

        XCTAssertTrue(text.contains("### Brunch"), text)
        XCTAssertTrue(text.contains("- Shake: 1 unit"), text)
        XCTAssertTrue(text.contains("### Dinner"), text)
        XCTAssertTrue(text.contains("leucine 2.4 g"), text)
    }

    func testTheAverageCountsOnlyLoggedDaysAndMarksUnknownNutrients() throws {
        try diet.setMealEaten(true, meal: "Brunch", on: date("2026-11-18"))
        try diet.setMealEaten(true, meal: "Dinner", on: date("2026-11-18"))

        let text = try report()

        XCTAssertTrue(text.contains("over 1 logged day"), text)
        XCTAssertTrue(text.contains("Leucine: 5.8 g"), text)
        XCTAssertTrue(text.contains("Unknown (no data in some foods):"), text)
        XCTAssertFalse(text.contains("Vitamin C: 0"), text)
    }

    func testSupplementsCarryTheirLibraryVerdict() throws {
        try library.add(FoodDraft(name: "Fish oil", kind: .supplement, unit: "capsule", baseQuantity: 1))
        let json = #"{"entries":[{"id":"omega-3","name":"Omega-3 fish oil","aliases":["fish oil"],"category":"Heart","verdict":"recommended","source":"Vol 05"}]}"#
        let supplements = try SupplementLibrary(data: Data(json.utf8))

        let text = try report(supplementLibrary: supplements)

        XCTAssertTrue(text.contains("- Fish oil → Omega-3 fish oil (Worth taking)"), text)
    }

    func testOpenInsightsAreIncludedOrNone() throws {
        let item = Insight(ruleID: "fiber", kind: .today, severity: .improve, title: "Fibre short", detail: "40 g of 56 g", why: "14 g per 1000 kcal")

        XCTAssertTrue(try report(insights: [item]).contains("- Fibre short: 40 g of 56 g"))
        XCTAssertTrue(try report().contains("## Open Room for improvement items\nNone"))
    }
}
