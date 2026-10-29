import XCTest
@testable import FitnessCore

final class PortionsTests: XCTestCase {
    private var library: FoodLibrary!
    private var biscuits: Food!

    override func setUpWithError() throws {
        library = FoodLibrary(try Database.inMemory())
        let id = try library.add(FoodDraft(name: "Tea biscuits", kind: .packaged, protein: 7, carbs: 70, fat: 18, labelCalories: 480,
                                           price: 40, packSize: 250, piecesPerPack: 35))
        biscuits = try XCTUnwrap(try library.food(id))
    }

    func testOnePieceWeighsThePackDividedByItsPieces() throws {
        XCTAssertEqual(try XCTUnwrap(Portions.pieceWeight(of: biscuits)), 7.142857, accuracy: 0.0001)
    }

    func testPiecesBecomeGramsAndThenNutrition() throws {
        let portion = try Portions.portion(of: biscuits, .pieces(4))
        let nutrition = try library.nutrition(of: biscuits.id, quantity: portion.amount)

        XCTAssertEqual(portion.amount, 28.5714, accuracy: 0.0001)
        XCTAssertEqual(portion.pieces, 4)
        XCTAssertEqual(nutrition.calories, 137.14, accuracy: 0.01)
        XCTAssertEqual(nutrition.protein, 2, accuracy: 0.01)
        XCTAssertEqual(nutrition.carbs, 20, accuracy: 0.01)
        XCTAssertEqual(nutrition.fat, 5.14, accuracy: 0.01)
    }

    func testGramsAreUsedAsTheyAre() throws {
        let portion = try Portions.portion(of: biscuits, .amount(30))

        XCTAssertEqual(portion.amount, 30)
        XCTAssertEqual(try library.nutrition(of: biscuits.id, quantity: portion.amount).calories, 144, accuracy: 0.0001)
    }

    func testAShareOfThePackIsAShareOfItsWeight() throws {
        let portion = try Portions.portion(of: biscuits, .shareOfPack(0.5))

        XCTAssertEqual(portion.amount, 125)
        XCTAssertEqual(try XCTUnwrap(portion.pieces), 17.5, accuracy: 0.0001)
    }

    func testAPieceWeighedByHandReplacesThePackMaths() throws {
        var draft = biscuits.draft
        draft.pieceWeight = 8.28
        try library.update(biscuits.id, draft)
        let weighed = try XCTUnwrap(try library.food(biscuits.id))

        XCTAssertEqual(try Portions.portion(of: weighed, .pieces(4)).amount, 33.12, accuracy: 0.0001)
    }

    func testAFoodWithNoPieceSizeCannotBeEnteredInPieces() throws {
        let rice = try XCTUnwrap(try library.food(try library.add(FoodDraft(name: "Loose rice"))))

        XCTAssertThrowsError(try Portions.portion(of: rice, .pieces(3))) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Loose rice has no piece size"))
        }
    }

    func testAFoodCountedInPiecesNeedsNoConversion() throws {
        let flatbread = try XCTUnwrap(try library.food(try library.add(FoodDraft(name: "Flatbread", kind: .recipe, unit: "piece", baseQuantity: 1, recipeMakes: 1))))

        let portion = try Portions.portion(of: flatbread, .pieces(3))

        XCTAssertEqual(portion.amount, 3)
        XCTAssertEqual(portion.pieces, 3)
    }

    func testAShareOfAPackNeedsAPackSize() throws {
        let rice = try XCTUnwrap(try library.food(try library.add(FoodDraft(name: "Loose rice"))))

        XCTAssertThrowsError(try Portions.portion(of: rice, .shareOfPack(0.5))) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Loose rice has no pack size"))
        }
    }

    func testAnAmountMustBeAboveZero() throws {
        for input in [PortionInput.pieces(0), .amount(-2), .shareOfPack(0)] {
            XCTAssertThrowsError(try Portions.portion(of: biscuits, input)) {
                XCTAssertEqual($0 as? ValidationError, ValidationError("Enter an amount above 0"))
            }
        }
    }

    func testAPieceCostsAPieceOfThePack() throws {
        let cost = try library.cost(of: biscuits.id, quantity: try XCTUnwrap(Portions.pieceWeight(of: biscuits)))

        XCTAssertEqual(cost.amount, 1.142857, accuracy: 0.0001)
    }
}
