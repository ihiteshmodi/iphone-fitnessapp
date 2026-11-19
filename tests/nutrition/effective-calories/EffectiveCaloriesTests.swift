import XCTest
@testable import FitnessCore

final class EffectiveCaloriesTests: XCTestCase {
    func testDigestionCostOfADayByMacro() {
        let cost = DigestionCost(protein: 207, carbs: 392, fat: 49, alcohol: 0)

        XCTAssertEqual(cost.protein, 207, accuracy: 1e-9)
        XCTAssertEqual(cost.carbs, 117.6, accuracy: 1e-9)
        XCTAssertEqual(cost.fat, 6.615, accuracy: 1e-9)
        XCTAssertEqual(cost.alcohol, 0)
        XCTAssertEqual(cost.total, 331.215, accuracy: 1e-9)
        XCTAssertEqual(cost.effective(of: 2839), 2507.785, accuracy: 1e-9)
    }

    func testTheWeeklyEffectiveAverageUsesEachDaysOwnMacros() throws {
        let db = try Database.inMemory()
        let library = FoodLibrary(db)
        let diet = DietDayService(db)
        let calories = CalorieService(db)
        let shake = try library.add(FoodDraft(name: "Shake", unit: "unit", baseQuantity: 1, protein: 200, carbs: 500))
        let rice = try library.add(FoodDraft(name: "Rice", unit: "unit", baseQuantity: 1, carbs: 600))
        try DietPlanService(db).addItem(foodID: rice, quantity: 1, meal: "Day", from: date("2026-11-01"))
        try diet.addExtra(foodID: shake, .amount(1), on: date("2026-11-17"))
        try diet.addExtra(foodID: rice, .amount(1), on: date("2026-11-18"))

        let average = try XCTUnwrap(try calories.effectiveAverage(endingOn: date("2026-11-18"), days: 2))

        let day1 = 2800 - (0.25 * 800 + 0.075 * 2000)
        let day2 = 2400 - 0.075 * 2400
        XCTAssertEqual(average, (day1 + day2) / 2, accuracy: 1e-9)
    }

    func testATypedDayUsesTheDigestionShareOfTheDaysWithMacros() throws {
        let db = try Database.inMemory()
        let library = FoodLibrary(db)
        let calories = CalorieService(db)
        let mix = try library.add(FoodDraft(name: "Mix", unit: "unit", baseQuantity: 1, protein: 105, carbs: 245, fat: 76.7))
        try DietPlanService(db).addItem(foodID: mix, quantity: 1, meal: "Day", from: date("2026-11-01"))
        try DietDayService(db).addExtra(foodID: mix, .amount(1), on: date("2026-11-17"))
        try calories.saveCalories(on: date("2026-11-18"), calories: 3000)
        let known = DigestionCost(protein: 105, carbs: 245, fat: 76.7, alcohol: 0)
        let share = known.total / (4 * 105 + 4 * 245 + 9 * 76.7)

        let average = try XCTUnwrap(try calories.effectiveAverage(endingOn: date("2026-11-18"), days: 2))

        XCTAssertEqual(average, ((4 * 105 + 4 * 245 + 9 * 76.7) - known.total + 3000 * (1 - share)) / 2, accuracy: 1e-6)
    }

    func testTheTargetBasisChoiceIsKept() throws {
        let db = try Database.inMemory()
        let settings = SettingsRepository(db)
        XCTAssertEqual(try settings.load().calorieBasis, .total)

        try settings.setCalorieBasis(.effective)

        XCTAssertEqual(try settings.load().calorieBasis, .effective)
    }
}
