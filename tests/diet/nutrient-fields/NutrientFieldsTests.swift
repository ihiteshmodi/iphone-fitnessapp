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
        XCTAssertNil(Nutrient.omega6.dailyTarget, "the vault gives no omega-6 amount, so it is tracked but not judged")
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

    func testTheDaysNutrientsAgainstTheirDailyTargets() throws {
        let soy = try library.add(FoodDraft(name: "Soy chunks", protein: 52, nutrients: [.leucine: 4.0, .iron: 9]))
        let profile = try library.book().profile(of: soy, quantity: 100)

        let rows = DailyTargetReport.rows(profile)

        let leucine = try XCTUnwrap(rows.first { $0.nutrient == .leucine })
        XCTAssertEqual([leucine.amount, leucine.target], [4.0, 2.9])
        XCTAssertTrue(leucine.isMet)
        XCTAssertEqual(try XCTUnwrap(rows.first { $0.nutrient == .iron }).share ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertNil(try XCTUnwrap(rows.first { $0.nutrient == .vitaminD }).amount)
    }

    func testVitaminD3InIUCombinesWithVitaminDInMcgAndFormatsDualUnits() throws {
        let multi = try library.add(FoodDraft(name: "Becadexamine", kind: .supplement, unit: "unit", baseQuantity: 1, nutrients: [.vitaminD: 10]))
        let d3Cap = try library.add(FoodDraft(name: "D3 5000IU capsule", kind: .supplement, unit: "unit", baseQuantity: 1, nutrients: [.vitaminD3: 5000]))
        let d3Spray = try library.add(FoodDraft(name: "D3 6000IU spray", kind: .supplement, unit: "ml", baseQuantity: 1, nutrients: [.vitaminD3: 12000]))

        let book = try library.book()
        let combined = try book.profile(of: multi, quantity: 1)
            + book.profile(of: d3Cap, quantity: 1)
            + book.profile(of: d3Spray, quantity: 0.5)

        XCTAssertEqual(Nutrient.vitaminD3.unit, "IU")
        XCTAssertTrue(Nutrient.vitaminD3.isFatSoluble)
        XCTAssertEqual(Nutrient.vitaminD3.upperLimit, 4000)
        XCTAssertEqual(combined.totalVitaminDMcg, 285.0, accuracy: 1e-6)
        XCTAssertEqual(combined.totalVitaminDIU, 11400.0, accuracy: 1e-6)

        let dailyRows = DailyTargetReport.dailyRows(combined)
        let vitDRow = try XCTUnwrap(dailyRows.first { $0.nutrient == .vitaminD })
        XCTAssertEqual(vitDRow.amount ?? 0, 285.0, accuracy: 1e-6)
        XCTAssertTrue(vitDRow.formattedProgress.contains("285") && vitDRow.formattedProgress.contains("11,400 IU"))
    }

    func testFunctionalCompoundsTrackCreatineGlycineAndPsylliumGramsAndRanges() throws {
        let gainer = try library.add(FoodDraft(name: "Post-workout gainer", protein: 30, carbs: 55, fat: 5,
                                               nutrients: [.creatine: 3.0, .glycine: 2.0, .psyllium: 5.0]))
        let profile = try library.book().profile(of: gainer, quantity: 100)

        XCTAssertEqual(Nutrient.creatine.group, .compounds)
        XCTAssertEqual(Nutrient.glycine.group, .compounds)
        XCTAssertEqual(Nutrient.psyllium.group, .compounds)
        XCTAssertEqual(profile[.creatine], 3.0)
        XCTAssertEqual(profile[.glycine], 2.0)
        XCTAssertEqual(profile[.psyllium], 5.0)
        XCTAssertEqual(Nutrient.creatine.recommendedRange, 3.0...5.0)
        XCTAssertEqual(Nutrient.glycine.recommendedRange, 3.0...5.0)
        XCTAssertEqual(Nutrient.psyllium.recommendedRange, 5.0...10.0)
    }
}
