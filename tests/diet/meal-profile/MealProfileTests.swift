import XCTest
@testable import FitnessCore

final class MealProfileTests: XCTestCase {
    func testGlycemicIndexImporterRecipeGLRealMealFilterAndDescendingFoodDrillDown() throws {
        let db = try Database.inMemory()
        let foods = FoodLibrary(db)
        let plans = DietPlanService(db)
        let diet = DietDayService(db)
        let start = date("2026-11-20")

        let psyllium = try foods.add(FoodDraft(name: "Psyllium Husk", kind: .supplement, unit: "g", baseQuantity: 1))
        let salt = try foods.add(FoodDraft(name: "Himalayan Salt", kind: .supplement, unit: "g", baseQuantity: 1))
        let soy = try foods.add(FoodDraft(name: "Soy chunks", kind: .food, unit: "g", baseQuantity: 100,
                                          protein: 52, carbs: 33, fat: 1, fiber: 13,
                                          nutrients: [.leucine: 3.868, .histidine: 1.281, .methionine: 0.64],
                                          glycemicIndex: 15))
        let oats = try foods.add(FoodDraft(name: "Rolled Oats", kind: .food, unit: "g", baseQuantity: 100,
                                           protein: 12, carbs: 68.5, fat: 9.5, fiber: 10,
                                           nutrients: [.leucine: 0.98, .histidine: 0.27, .methionine: 0.22]))
        let malto = try foods.add(FoodDraft(name: "Maltodextrin", kind: .supplement, unit: "g", baseQuantity: 100,
                                            carbs: 95, glycemicIndex: 105))
        let dlMeth = try foods.add(FoodDraft(name: "DL-Methionine", kind: .supplement, unit: "g", baseQuantity: 1,
                                             nutrients: [.methionine: 1.0]))

        // Apply GI via NutrientImporter CSV
        let csvRes = try NutrientImporter(db).apply("name,key,amount\nRolled Oats,glycemic_index,55\n")
        XCTAssertEqual(csvRes.applied, 1)
        XCTAssertEqual(try foods.food(oats)?.draft.glycemicIndex, 55)

        // Recipe combining Soy (150g), Oats (30g), Maltodextrin (30g)
        let shake = try foods.add(FoodDraft(name: "Maintenance Shake", kind: .recipe, unit: "unit", baseQuantity: 1, recipeMakes: 1))
        try foods.setIngredients(of: shake, [
            RecipeLine(foodID: soy, quantity: 150),
            RecipeLine(foodID: oats, quantity: 30),
            RecipeLine(foodID: malto, quantity: 30)
        ])

        try plans.addItem(foodID: psyllium, quantity: 1.2, meal: "Morning", from: start)
        try plans.addItem(foodID: salt, quantity: 2.0, meal: "During workout", from: start)
        try plans.addItem(foodID: shake, quantity: 1.0, meal: "Brunch", from: start)
        try plans.addItem(foodID: dlMeth, quantity: 2.5, meal: "Brunch", from: start)

        try diet.setMealEaten(true, meal: "Brunch", on: start)
        let day = try diet.day(start)

        // 1. Only Brunch is a real meal; Morning & During workout are hidden
        let morning = try XCTUnwrap(day.meals.first { $0.name == "Morning" })
        let workout = try XCTUnwrap(day.meals.first { $0.name == "During workout" })
        let brunch = try XCTUnwrap(day.meals.first { $0.name == "Brunch" })
        XCTAssertFalse(morning.isRealMeal)
        XCTAssertFalse(workout.isRealMeal)
        XCTAssertTrue(brunch.isRealMeal)

        // 2. DailyTargetsView rows exclude amino acids and show 0 instead of nil
        let dailyRows = DailyTargetReport.dailyRows(day.eatenProfile)
        XCTAssertFalse(dailyRows.contains { $0.nutrient.group == .aminoAcids })
        let vitKRow = try XCTUnwrap(dailyRows.first { $0.nutrient == .vitaminK })
        XCTAssertEqual(vitKRow.amount, 0)

        // 3. MealProfileEvaluator computes total GL (Soy: 15 * 30 / 100 = 4.5; Oats: 55 * 17.55 / 100 = 9.6525; Malto: 105 * 28.5 / 100 = 29.925 -> 44.0775)
        let book = try foods.book()
        let report = try MealProfileEvaluator.evaluate(meal: brunch, book: book)
        XCTAssertEqual(report.totalGlycemicLoad, 44.0775, accuracy: 0.001)
        XCTAssertEqual(report.glycemicBand, .high)

        // 4. GL contributors sorted descending with % share
        XCTAssertEqual(report.glycemicContributors.map(\.foodName), ["Maltodextrin", "Rolled Oats", "Soy chunks"])
        XCTAssertEqual(report.glycemicContributors.first?.amount ?? 0, 29.925, accuracy: 0.001)
        XCTAssertEqual(report.glycemicContributors.reduce(0) { $0 + $1.percent }, 100.0, accuracy: 0.1)

        // 5. Per-meal amino acids & descending food drill-down
        let leucineRow = try XCTUnwrap(report.aminoRows.first { $0.nutrient == .leucine })
        XCTAssertEqual(leucineRow.target, 2.9)
        XCTAssertEqual(leucineRow.amount, 1.5 * 3.868 + 0.3 * 0.98, accuracy: 0.001)
        XCTAssertTrue(leucineRow.isMet)
        XCTAssertEqual(leucineRow.contributors.map(\.foodName), ["Soy chunks", "Rolled Oats"])
        XCTAssertGreaterThan(leucineRow.contributors[0].percent, leucineRow.contributors[1].percent)

        let methRow = try XCTUnwrap(report.aminoRows.first { $0.nutrient == .methionine })
        XCTAssertEqual(methRow.contributors.first?.foodName, "DL-Methionine")
    }
}
