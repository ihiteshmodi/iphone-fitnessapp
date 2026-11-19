import XCTest
@testable import FitnessCore

final class UnconfirmedMealsTests: XCTestCase {
    private var db: Database!
    private var diet: DietDayService!
    private let today = date("2026-11-19")

    override func setUpWithError() throws {
        db = try Database.inMemory()
        diet = DietDayService(db)
        let library = FoodLibrary(db)
        let plans = DietPlanService(db)
        let oats = try library.add(FoodDraft(name: "Oats", carbs: 60))
        let milk = try library.add(FoodDraft(name: "Milk", protein: 3))
        let lentils = try library.add(FoodDraft(name: "Lentils", protein: 9))
        try plans.addItem(foodID: oats, quantity: 100, meal: "Brunch", from: date("2026-11-10"))
        try plans.addItem(foodID: milk, quantity: 200, meal: "Brunch", from: date("2026-11-10"))
        try plans.addItem(foodID: lentils, quantity: 200, meal: "Dinner", from: date("2026-11-10"))
        var day = date("2026-11-10")
        while day < today {
            try diet.setMealEaten(true, meal: "Brunch", on: day)
            try diet.setMealEaten(true, meal: "Dinner", on: day)
            day = day.adding(days: 1)
        }
    }

    private func asked() throws -> [String] {
        try diet.unconfirmedMeals(before: today).map { "\($0.date) \($0.meal)" }
    }

    func testUntickedMealsOfTheLast7DaysAreListedNewestFirst() throws {
        try diet.setMealEaten(false, meal: "Dinner", on: date("2026-11-18"))
        try diet.setMealEaten(false, meal: "Brunch", on: date("2026-11-16"))
        try diet.setMealEaten(false, meal: "Dinner", on: date("2026-11-16"))

        XCTAssertEqual(try asked(), ["2026-11-18 Dinner", "2026-11-16 Brunch", "2026-11-16 Dinner"])
    }

    func testAteItTicksTheMealAndSkippedOnlyStopsTheQuestion() throws {
        try diet.setMealEaten(false, meal: "Dinner", on: date("2026-11-18"))
        try diet.setMealEaten(false, meal: "Dinner", on: date("2026-11-17"))

        try diet.setMealEaten(true, meal: "Dinner", on: date("2026-11-18"))
        try diet.markMealSkipped("Dinner", on: date("2026-11-17"))

        XCTAssertEqual(try asked(), [])
        XCTAssertEqual(try diet.day(date("2026-11-17")).meals.first { $0.name == "Dinner" }?.tickState, MealTickState.none)
    }

    func testBreaksTypedDaysHalfTickedMealsAndOldDaysAreNeverAsked() throws {
        for text in ["2026-11-17", "2026-11-15", "2026-11-11"] {
            try diet.setMealEaten(false, meal: "Brunch", on: date(text))
            try diet.setMealEaten(false, meal: "Dinner", on: date(text))
        }
        try BreakModeService(db).add(from: date("2026-11-17"), to: date("2026-11-17"))
        try CalorieService(db).saveCalories(on: date("2026-11-15"), calories: 2500)
        try db.execute("DELETE FROM diet_day_ticks WHERE day = '2026-11-14' AND food_id = (SELECT id FROM foods WHERE name = 'Milk')")

        XCTAssertEqual(try asked(), [], "2026-11-11 is more than 7 days back")
    }
}
