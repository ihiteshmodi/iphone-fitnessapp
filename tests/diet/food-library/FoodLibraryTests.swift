import XCTest
@testable import FitnessCore

final class FoodLibraryTests: XCTestCase {
    private var db: Database!
    private var library: FoodLibrary!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        library = FoodLibrary(db)
    }

    @discardableResult
    private func addFlatbread(flourPrice: Double = 10) throws -> (flatbread: Int, flour: Int, seeds: Int) {
        let flour = try library.add(FoodDraft(name: "Flour", protein: 0, carbs: 87.5, fat: 0, labelCalories: 350, price: flourPrice, packSize: 100))
        let seeds = try library.add(FoodDraft(name: "Seeds", protein: 0, carbs: 0, fat: 55.5, labelCalories: 500, price: 30, packSize: 100))
        let flatbread = try library.add(FoodDraft(name: "Flatbread", kind: .recipe, unit: "piece", baseQuantity: 1, recipeMakes: 2))
        try library.setIngredients(of: flatbread, [RecipeLine(foodID: flour, quantity: 40), RecipeLine(foodID: seeds, quantity: 10)])
        return (flatbread, flour, seeds)
    }

    // MARK: Nutrition

    func testNutritionIsScaledFromTheBaseQuantityToWhatIsEaten() throws {
        let oats = try library.add(FoodDraft(name: "Rolled oats", protein: 12, carbs: 68, fat: 8, fiber: 10))

        let nutrition = try library.nutrition(of: oats, quantity: 30)

        XCTAssertEqual(nutrition.protein, 3.6, accuracy: 0.0001)
        XCTAssertEqual(nutrition.carbs, 20.4, accuracy: 0.0001)
        XCTAssertEqual(nutrition.fat, 2.4, accuracy: 0.0001)
        XCTAssertEqual(nutrition.fiber, 3, accuracy: 0.0001)
        XCTAssertEqual(nutrition.calories, 117.6, accuracy: 0.0001)
    }

    func testCaloriesComeFromTheMacrosUnlessTheLabelIsTyped() throws {
        let plain = try library.add(FoodDraft(name: "Plain", protein: 10, carbs: 60, fat: 5))
        let labelled = try library.add(FoodDraft(name: "Labelled", protein: 10, carbs: 60, fat: 5, labelCalories: 340))

        XCTAssertEqual(try library.nutrition(of: plain, quantity: 100).calories, 325, accuracy: 0.0001)
        XCTAssertEqual(try library.nutrition(of: labelled, quantity: 100).calories, 340, accuracy: 0.0001)
    }

    func testANutritionLabelPerServingIsScaledByItsOwnBaseQuantity() throws {
        let bar = try library.add(FoodDraft(name: "Bar", baseQuantity: 30, protein: 3, labelCalories: 150))

        let nutrition = try library.nutrition(of: bar, quantity: 45)

        XCTAssertEqual(nutrition.calories, 225, accuracy: 0.0001)
        XCTAssertEqual(nutrition.protein, 4.5, accuracy: 0.0001)
    }

    // MARK: Cost

    func testCostComesFromThePackPrice() throws {
        let rice = try library.add(FoodDraft(name: "Rice", price: 80, packSize: 500))

        XCTAssertEqual(try library.cost(of: rice, quantity: 30), Cost(amount: 4.8, isComplete: true))
    }

    func testAFoodWithNoPriceCostsNothingAndSaysSo() throws {
        let rice = try library.add(FoodDraft(name: "Rice"))

        XCTAssertEqual(try library.cost(of: rice, quantity: 30), Cost(amount: 0, isComplete: false))
    }

    // MARK: Recipes

    func testARecipeIsWorkedOutFromItsIngredientsAndWhatItMakes() throws {
        let ids = try addFlatbread()

        let nutrition = try library.nutrition(of: ids.flatbread, quantity: 1)
        let cost = try library.cost(of: ids.flatbread, quantity: 1)

        XCTAssertEqual(nutrition.calories, 95, accuracy: 0.0001)
        XCTAssertEqual(cost.amount, 3.5, accuracy: 0.0001)
        XCTAssertTrue(cost.isComplete)
    }

    func testEditingAnIngredientChangesEveryRecipeThatUsesIt() throws {
        let ids = try addFlatbread()
        var flour = try XCTUnwrap(try library.food(ids.flour)).draft
        flour.price = 20

        try library.update(ids.flour, flour)

        XCTAssertEqual(try library.cost(of: ids.flatbread, quantity: 1).amount, 5.5, accuracy: 0.0001)
    }

    func testARecipeCanBeAWholeBatchMeasuredInGrams() throws {
        let stock = try library.add(FoodDraft(name: "Stock", labelCalories: 500))
        let sauce = try library.add(FoodDraft(name: "House sauce", kind: .recipe, unit: "g", baseQuantity: 1, recipeMakes: 1000))
        try library.setIngredients(of: sauce, [RecipeLine(foodID: stock, quantity: 100)])

        XCTAssertEqual(try library.nutrition(of: sauce, quantity: 40).calories, 20, accuracy: 0.0001)
    }

    func testARecipeCannotContainItselfDirectlyOrThroughAnotherRecipe() throws {
        let ids = try addFlatbread()
        let wrap = try library.add(FoodDraft(name: "Wrap", kind: .recipe, unit: "piece", baseQuantity: 1, recipeMakes: 1))
        try library.setIngredients(of: wrap, [RecipeLine(foodID: ids.flatbread, quantity: 1)])

        XCTAssertThrowsError(try library.setIngredients(of: ids.flatbread, [RecipeLine(foodID: ids.flatbread, quantity: 1)])) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("A recipe cannot contain itself"))
        }
        XCTAssertThrowsError(try library.setIngredients(of: ids.flatbread, [RecipeLine(foodID: wrap, quantity: 1)])) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("A recipe cannot contain itself"))
        }
    }

    func testIngredientsAreReadBackInTheOrderTheyWereGiven() throws {
        let ids = try addFlatbread()

        XCTAssertEqual(try library.ingredients(of: ids.flatbread).map(\.foodID), [ids.flour, ids.seeds])
    }

    func testARecipeWithAnIngredientThatHasNoPriceHasAnIncompleteCost() throws {
        let ids = try addFlatbread()
        var seeds = try XCTUnwrap(try library.food(ids.seeds)).draft
        seeds.price = nil
        try library.update(ids.seeds, seeds)

        XCTAssertFalse(try library.cost(of: ids.flatbread, quantity: 1).isComplete)
    }

    // MARK: Names, deleting and searching

    func testNamesAreUniqueIgnoringCase() throws {
        try library.add(FoodDraft(name: "Rolled oats"))

        XCTAssertThrowsError(try library.add(FoodDraft(name: "rolled OATS"))) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("A food with that name already exists"))
        }
    }

    func testAFoodUsedByARecipeCannotBeDeleted() throws {
        let ids = try addFlatbread()

        XCTAssertThrowsError(try library.delete(ids.flour)) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Flour is used by a recipe, a plan or a logged day"))
        }
    }

    func testAnUnusedFoodAndARecipeCanBeDeleted() throws {
        let ids = try addFlatbread()

        try library.delete(ids.flatbread)
        try library.delete(ids.flour)

        XCTAssertNil(try library.food(ids.flatbread))
        XCTAssertNil(try library.food(ids.flour))
    }

    func testSearchingFindsMatchingFoodsAndRecipesInNameOrder() throws {
        try library.add(FoodDraft(name: "Rolled oats"))
        try library.add(FoodDraft(name: "Oat milk", kind: .liquid))
        try library.add(FoodDraft(name: "Oat cookie", kind: .recipe, unit: "piece", baseQuantity: 1, recipeMakes: 1))
        try library.add(FoodDraft(name: "Rice"))

        XCTAssertEqual(try library.foods(matching: "oat").map(\.name), ["Oat cookie", "Oat milk", "Rolled oats"])
    }

    func testFilteringByKindReturnsOnlyThatKind() throws {
        try library.add(FoodDraft(name: "Rice"))
        try library.add(FoodDraft(name: "Creatine", kind: .supplement))
        try library.add(FoodDraft(name: "Zinc", kind: .supplement))

        XCTAssertEqual(try library.foods(kind: .supplement).map(\.name), ["Creatine", "Zinc"])
    }

    // MARK: Validation

    func testAFoodMustBeValid() throws {
        let cases: [(FoodDraft, String)] = [
            (FoodDraft(name: "  "), "Give the food a name"),
            (FoodDraft(name: "A", baseQuantity: 0), "Nutrition must be per a quantity above 0"),
            (FoodDraft(name: "B", protein: -1), "Nutrition cannot be negative"),
            (FoodDraft(name: "C", price: -5), "Price cannot be negative"),
        ]
        for (draft, message) in cases {
            XCTAssertThrowsError(try library.add(draft), message) { XCTAssertEqual($0 as? ValidationError, ValidationError(message)) }
        }
    }
}
