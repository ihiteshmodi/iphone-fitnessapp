import XCTest
@testable import FitnessCore

final class RecipeToolsTests: XCTestCase {
    private var db: Database!
    private var library: FoodLibrary!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        library = FoodLibrary(db)
    }

    private func recipe(_ name: String, makes: Double, _ items: [(String, Double)]) throws -> Int {
        let id = try library.add(FoodDraft(name: name, kind: .recipe, unit: "piece", baseQuantity: 1, recipeMakes: makes))
        let lines = try items.map { name, quantity in
            RecipeLine(foodID: try library.food(named: name)?.id ?? library.add(FoodDraft(name: name, protein: 10)), quantity: quantity)
        }
        try library.setIngredients(of: id, lines)
        return id
    }

    func testCookingForADifferentNumberOfPiecesScalesEveryIngredientAndSavesNothing() throws {
        let kokki = try recipe("Kokki", makes: 11, [("Wheat flour", 550), ("Onion", 99)])

        let scaled = try RecipeScaling.cook(try library.ingredients(of: kokki), makes: 11, for: 5)

        XCTAssertEqual(scaled.map(\.quantity), [250, 45])
        XCTAssertEqual(try library.ingredients(of: kokki).map(\.quantity), [550, 99])
    }

    func testCookForMustBeAboveZero() throws {
        XCTAssertThrowsError(try RecipeScaling.cook([], makes: 11, for: 0)) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Cook for an amount above 0"))
        }
    }

    func testADuplicateIsAnIndependentCopy() throws {
        let shake = try recipe("Maintenance shake", makes: 1, [("Soybeans", 40), ("Ashwagandha", 3), ("Gokhru", 3), ("Brahmi", 2), ("Milk powder", 30)])

        let soybean = try library.duplicate(shake, as: "Soybean shake")

        XCTAssertEqual(try library.ingredients(of: soybean), try library.ingredients(of: shake))
        XCTAssertEqual(try library.food(soybean)?.draft.recipeMakes, 1)
        let milk = try XCTUnwrap(try library.food(named: "Milk powder")).id
        try library.setIngredients(of: soybean, try library.ingredients(of: soybean).filter { $0.foodID != milk })
        XCTAssertEqual(try library.ingredients(of: shake).count, 5)
        XCTAssertEqual(try library.ingredients(of: soybean).count, 4)
    }

    func testTheCopyNeedsANameOfItsOwn() throws {
        let shake = try recipe("Maintenance shake", makes: 1, [("Soybeans", 40)])

        XCTAssertThrowsError(try library.duplicate(shake, as: "maintenance shake")) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("A food with that name already exists"))
        }
    }
}
