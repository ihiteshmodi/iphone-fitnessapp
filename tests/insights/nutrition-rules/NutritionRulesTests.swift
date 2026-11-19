import XCTest
@testable import FitnessCore

final class NutritionRulesTests: XCTestCase {
    private var db: Database!
    private var library: FoodLibrary!
    private var plans: DietPlanService!
    private var diet: DietDayService!
    private let today = date("2026-11-19")
    private let yesterday = date("2026-11-18")
    private var shake = 0
    private var dal = 0

    override func setUpWithError() throws {
        db = try Database.inMemory()
        library = FoodLibrary(db)
        plans = DietPlanService(db)
        diet = DietDayService(db)
        shake = try library.add(FoodDraft(name: "Shake", unit: "unit", baseQuantity: 1, protein: 40, carbs: 30, fat: 5, fiber: 1,
                                           nutrients: [.leucine: 3.4, .trans: 0, .epa: 0, .dha: 0]))
        dal = try library.add(FoodDraft(name: "Dal", unit: "unit", baseQuantity: 1, protein: 30, carbs: 60, fat: 6, fiber: 2,
                                         nutrients: [.leucine: 2.4, .trans: 0, .epa: 0, .dha: 0]))
        try plans.addItem(foodID: shake, quantity: 1, meal: "Brunch", from: date("2026-11-01"))
        try plans.addItem(foodID: dal, quantity: 1, meal: "Dinner", from: date("2026-11-01"))
    }

    private func service() -> InsightService { InsightService(db, daily: NutritionRules.daily, setup: NutritionRules.setup) }

    private func todayTitles() throws -> [String] { try service().today(on: today).map(\.title) }

    private func eatAll(on day: ISODate) throws {
        try diet.setMealEaten(true, meal: "Brunch", on: day)
        try diet.setMealEaten(true, meal: "Dinner", on: day)
    }

    func testTransFatIsFlaggedOnTheDayItIsEaten() throws {
        let oreo = try library.add(FoodDraft(name: "Oreo biscuit", unit: "unit", baseQuantity: 1, carbs: 7, fat: 2.3, nutrients: [.trans: 0.225]))
        try diet.addExtra(foodID: oreo, .amount(4), on: today)

        let item = try XCTUnwrap(try service().today(on: today).first { $0.ruleID == "trans-fat" })
        XCTAssertEqual(item.severity, .fix)
        XCTAssertTrue(item.detail.contains("Oreo biscuit"))
        XCTAssertTrue(item.detail.contains("0.9 g"))
    }

    func testLeucineUnder3gInAProteinMealAndNoDataWhenUnknown() throws {
        try eatAll(on: yesterday)

        let item = try XCTUnwrap(try service().today(on: today).first { $0.ruleID == "leucine-per-meal" })
        XCTAssertTrue(item.detail.contains("Dinner 2.4 g"))

        var draft = try XCTUnwrap(try library.food(dal)).draft
        draft.nutrients[.leucine] = nil
        try library.update(dal, draft)
        let rule = try XCTUnwrap(NutritionRules.daily.first { $0.id == "leucine-per-meal" })
        XCTAssertEqual(try rule.evaluate(on: yesterday, db: db), .noData)
    }

    func testFiberUnder14gPer1000Calories() throws {
        try eatAll(on: yesterday)

        let item = try XCTUnwrap(try service().today(on: today).first { $0.ruleID == "fiber" })
        let calories = try diet.day(yesterday).total.calories
        XCTAssertTrue(item.detail.contains("3 g of \(Format1.one(calories / 1000 * 14)) g"), item.detail)
        XCTAssertTrue(item.detail.contains("psyllium"))
    }

    func testFatUnderTheRange() throws {
        for offset in 0..<7 { try db.addBodyWeight(on: yesterday.adding(days: -offset).string, kg: 64.74) }
        try eatAll(on: yesterday)

        let item = try XCTUnwrap(try service().today(on: today).first { $0.ruleID == "fat-range" })
        XCTAssertEqual(item.title, "Fat under the range")
        XCTAssertTrue(item.why.contains("fat-soluble"))
    }

    func testEPAPlusDHAUnder250mgAndNoDataWhenUnknown() throws {
        try eatAll(on: yesterday)
        XCTAssertTrue(try todayTitles().contains("EPA + DHA"))

        let rule = try XCTUnwrap(NutritionRules.daily.first { $0.id == "epa-dha" })
        let unknown = try library.add(FoodDraft(name: "Mystery", unit: "unit", baseQuantity: 1, protein: 1))
        try diet.addExtra(foodID: unknown, .amount(1), on: date("2026-11-10"))
        XCTAssertEqual(try rule.evaluate(on: date("2026-11-10"), db: db), .noData)
    }

    func testCaffeineLateInTheDay() throws {
        let coffee = try library.add(FoodDraft(name: "Coffee", unit: "unit", baseQuantity: 1, nutrients: [.caffeine: 95]))
        try diet.addExtra(foodID: coffee, .amount(1), on: today, details: ExtraDetails(time: .evening))

        let item = try XCTUnwrap(try service().today(on: today).first { $0.ruleID == "late-caffeine" })
        XCTAssertEqual(item.severity, .tip)
        XCTAssertTrue(item.detail.contains("8-10 hours"))
    }

    func testFlaxAndChiaAreNotRecommendedForMe() throws {
        let chia = try library.add(FoodDraft(name: "Chia seeds", fat: 31))
        try diet.addExtra(foodID: chia, .amount(10), on: today)

        let item = try XCTUnwrap(try service().today(on: today).first { $0.ruleID == "flax-chia" })
        XCTAssertTrue(item.why.contains("your own rule"))
    }

    func testFewerThan3ProteinMealsInThePlan() throws {
        let item = try XCTUnwrap(try service().setup(on: today).first { $0.ruleID == "protein-meals" })
        XCTAssertEqual(item.title, "2 protein meals")
        XCTAssertTrue(item.detail.contains("3-4"))
    }

    func testFishOilFormNotRTGOrAlgae() throws {
        let fishOil = try library.add(FoodDraft(name: "Fish oil", unit: "unit", baseQuantity: 1, nutrients: [.epa: 495, .dha: 330], omega3Form: .unknown))
        try plans.addItem(foodID: fishOil, quantity: 1, meal: "Brunch", from: date("2026-11-01"))

        let item = try XCTUnwrap(try service().setup(on: today).first { $0.ruleID == "omega3-form" })
        XCTAssertEqual(item.severity, .tip)
    }
}

enum Format1 {
    static func one(_ value: Double) -> String { String(format: "%.1f", value) }
}
