import XCTest
@testable import FitnessCore

final class NutrientFieldsTests: XCTestCase {
    private var db: Database!
    private var library: FoodLibrary!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        library = FoodLibrary(db)
    }

    func testAFoodKeepsItsExtraNutrientsAndTheRestAreUnknown() throws {
        let soy = try library.add(FoodDraft(name: "Soy chunks", protein: 52, nutrients: [.leucine: 4.0, .trans: 0]))

        let profile = try library.book().profile(of: soy, quantity: 100)

        XCTAssertEqual(profile[.leucine], 4.0)
        XCTAssertEqual(profile[.trans], 0)
        XCTAssertNil(profile[.lysine])
        XCTAssertTrue(profile.unknown.contains(.lysine))
        XCTAssertFalse(profile.unknown.contains(.leucine))
    }

    func testAmountsFollowTheQuantityAndRecipesAddUpTheirIngredients() throws {
        let soy = try library.add(FoodDraft(name: "Soy chunks", nutrients: [.leucine: 4.0]))
        let oats = try library.add(FoodDraft(name: "Oats", nutrients: [.leucine: 1.0]))
        let bowl = try library.add(FoodDraft(name: "Bowl", kind: .recipe, unit: "piece", baseQuantity: 1, recipeMakes: 2))
        try library.setIngredients(of: bowl, [RecipeLine(foodID: soy, quantity: 50), RecipeLine(foodID: oats, quantity: 100)])

        XCTAssertEqual(try library.book().profile(of: bowl, quantity: 1)[.leucine] ?? 0, 1.5, accuracy: 1e-9)
        XCTAssertFalse(try library.book().profile(of: bowl, quantity: 1).unknown.contains(.leucine))

        let salt = try library.add(FoodDraft(name: "Salt"))
        try library.setIngredients(of: bowl, [RecipeLine(foodID: soy, quantity: 50), RecipeLine(foodID: salt, quantity: 1)])
        XCTAssertTrue(try library.book().profile(of: bowl, quantity: 1).unknown.contains(.leucine))
    }

    func testAlcoholCountsSevenCaloriesAGram() throws {
        let beer = try library.add(FoodDraft(name: "Beer", unit: "ml", carbs: 4, nutrients: [.alcohol: 3.9]))

        XCTAssertEqual(try library.nutrition(of: beer, quantity: 100).calories, 4 * 4 + 7 * 3.9, accuracy: 1e-9)
    }

    func testTheOmega3FormIsKept() throws {
        let oil = try library.add(FoodDraft(name: "Algae oil", unit: "unit", baseQuantity: 1, nutrients: [.epa: 150, .dha: 300], omega3Form: .algae))

        XCTAssertEqual(try library.food(oil)?.draft.omega3Form, .algae)
        XCTAssertEqual(try library.food(oil)?.draft.nutrients[.dha], 300)
    }

    func testDailyTargetsForTheTrackedNutrients() {
        XCTAssertEqual(Nutrient.leucine.dailyTarget, 2.9)
        XCTAssertEqual(Nutrient.vitaminD.dailyTarget, 20)
        XCTAssertEqual(Nutrient.omega6.dailyTarget, 17)
        XCTAssertEqual(Nutrient.fiberDailyTarget, 28)
        XCTAssertEqual(Nutrient.vitaminD.unit, "mcg")
    }

    func testApprovedValuesAreAppliedFromAFileByFoodName() throws {
        let soy = try library.add(FoodDraft(name: "Soy chunks", protein: 52, nutrients: [.lysine: 3.2]))
        let csv = """
        name,key,amount
        Soy chunks,leucine,4.0
        soy chunks,omega3_form,algae
        Unknown food,leucine,1
        """

        let result = try NutrientImporter(db).apply(csv)

        let draft = try XCTUnwrap(try library.food(soy)?.draft)
        XCTAssertEqual(draft.nutrients, [.lysine: 3.2, .leucine: 4.0])
        XCTAssertEqual(draft.omega3Form, .algae)
        XCTAssertEqual(result, NutrientImporter.Result(applied: 2, missingFoods: ["Unknown food"]))
    }
}
