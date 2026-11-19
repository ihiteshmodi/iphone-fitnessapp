import XCTest
@testable import FitnessCore

final class SavedDietsTests: XCTestCase {
    private var db: Database!
    private var plans: DietPlanService!
    private var saved: SavedDietService!
    private var oats = 0
    private var lentils = 0
    private var rice = 0

    override func setUpWithError() throws {
        db = try Database.inMemory()
        let library = FoodLibrary(db)
        plans = DietPlanService(db)
        saved = SavedDietService(db)
        oats = try library.add(FoodDraft(name: "Oats", protein: 13, carbs: 68, fat: 7))
        lentils = try library.add(FoodDraft(name: "Lentils", protein: 9, carbs: 20, fat: 0.4))
        rice = try library.add(FoodDraft(name: "Rice", protein: 2.7, carbs: 28, fat: 0.3))
        try plans.addItem(foodID: oats, quantity: 100, meal: "Brunch", from: date("2026-10-26"))
        try plans.addItem(foodID: lentils, quantity: 200, meal: "Dinner", from: date("2026-10-26"))
    }

    private func summary(on day: String) throws -> [String] {
        (try plans.plan(inForceOn: date(day))?.items ?? []).map { "\($0.meal): \($0.foodID) x \($0.quantity)" }
    }

    func testSavingTheCurrentDietListsItWithItsTotalsAndMarksItInForce() throws {
        try saved.saveCurrent(as: "High-protein 2-meal", on: date("2026-11-19"))

        let diet = try XCTUnwrap(try saved.all(inForceOn: date("2026-11-19")).first)
        XCTAssertEqual(diet.name, "High-protein 2-meal")
        XCTAssertEqual([diet.mealCount, diet.itemCount], [2, 2])
        XCTAssertEqual(diet.nutrition.protein, 31, accuracy: 1e-9)
        XCTAssertEqual(diet.nutrition.calories, 4 * 31 + 4 * 108 + 9 * 7.8, accuracy: 1e-9)
        XCTAssertTrue(diet.isInForce)
    }

    func testUsingASavedDietFromADateNeverRewritesEarlierDays() throws {
        let id = try saved.saveCurrent(as: "High-protein 2-meal", on: date("2026-11-19"))
        try plans.removeItem(meal: "Brunch", foodID: oats, from: date("2026-11-25"))
        try plans.removeItem(meal: "Dinner", foodID: lentils, from: date("2026-11-25"))
        try plans.addItem(foodID: rice, quantity: 150, meal: "Day", from: date("2026-11-25"))

        try saved.use(id, from: date("2026-12-01"))

        XCTAssertEqual(try summary(on: "2026-12-01"), ["Brunch: \(oats) x 100.0", "Dinner: \(lentils) x 200.0"])
        XCTAssertEqual(try summary(on: "2026-11-30"), ["Day: \(rice) x 150.0"])
        XCTAssertFalse(try XCTUnwrap(try saved.all(inForceOn: date("2026-11-30")).first).isInForce)
    }

    func testNamesAreUniqueAndAnEmptyDayCannotBeSaved() throws {
        try saved.saveCurrent(as: "High-protein 2-meal", on: date("2026-11-19"))

        XCTAssertThrowsError(try saved.saveCurrent(as: "high-protein 2-meal", on: date("2026-11-19"))) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("A saved diet with that name already exists"))
        }
        XCTAssertThrowsError(try saved.saveCurrent(as: "Old", on: date("2026-10-01"))) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("There is no diet plan on that day to save"))
        }
    }

    func testDeletingASavedDietLeavesThePlanAlone() throws {
        let id = try saved.saveCurrent(as: "High-protein 2-meal", on: date("2026-11-19"))

        try saved.delete(id)

        XCTAssertEqual(try saved.all(inForceOn: date("2026-11-19")), [])
        XCTAssertEqual(try summary(on: "2026-11-19").count, 2)
    }
}
