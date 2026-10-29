import XCTest
@testable import FitnessCore

final class DailyDietTests: XCTestCase {
    private var db: Database!
    private var library: FoodLibrary!
    private var plans: DietPlanService!
    private var diet: DietDayService!
    private var oats = 0
    private var shake = 0
    private var supplement = 0
    private var biscuits = 0

    override func setUpWithError() throws {
        db = try Database.inMemory()
        library = FoodLibrary(db)
        plans = DietPlanService(db)
        diet = DietDayService(db)
        oats = try library.add(FoodDraft(name: "Oats", baseQuantity: 50, protein: 7, carbs: 30, fat: 4, labelCalories: 200, price: 5, packSize: 50))
        shake = try library.add(FoodDraft(name: "Shake", unit: "unit", baseQuantity: 1, protein: 60, carbs: 90, fat: 12, labelCalories: 800, price: 60, packSize: 1))
        supplement = try library.add(FoodDraft(name: "Supplement", kind: .supplement, unit: "capsule", baseQuantity: 1, labelCalories: 0, price: 2, packSize: 1))
        biscuits = try library.add(FoodDraft(name: "Tea biscuits", kind: .packaged, protein: 7, carbs: 70, fat: 18, labelCalories: 480,
                                             price: 26.25, packSize: 250, piecesPerPack: 35))
        let start = date("2026-10-01")
        try plans.addItem(foodID: oats, quantity: 50, meal: "Morning", from: start)
        try plans.addItem(foodID: shake, quantity: 1, meal: "Brunch", from: start)
        try plans.addItem(foodID: supplement, quantity: 1, meal: "Brunch", from: start)
    }

    private func day(_ text: String) throws -> DietDay { try diet.day(date(text)) }

    // MARK: Totals

    func testThePlanCountsAsEaten() throws {
        let d = try day("2026-10-05")

        XCTAssertEqual(d.total.calories, 1000, accuracy: 0.001)
        XCTAssertEqual(d.total.protein, 67, accuracy: 0.001)
        XCTAssertEqual(d.total.carbs, 120, accuracy: 0.001)
        XCTAssertEqual(d.total.fat, 16, accuracy: 0.001)
        XCTAssertTrue(d.meals.flatMap(\.lines).allSatisfy { $0.state == .eaten })
        XCTAssertEqual(d.meals.map(\.name), ["Morning", "Brunch"])
    }

    func testUntickingAnItemRemovesItForThatDayOnly() throws {
        try diet.setEaten(false, meal: "Brunch", foodID: shake, on: date("2026-10-05"))

        XCTAssertEqual(try day("2026-10-05").total.calories, 200, accuracy: 0.001)
        XCTAssertEqual(try day("2026-10-05").skippedCount, 1)
        XCTAssertEqual(try day("2026-10-06").total.calories, 1000, accuracy: 0.001)

        try diet.setEaten(true, meal: "Brunch", foodID: shake, on: date("2026-10-05"))
        XCTAssertEqual(try day("2026-10-05").total.calories, 1000, accuracy: 0.001)
    }

    func testUntickingSomethingNotInThePlanIsRejected() throws {
        XCTAssertThrowsError(try diet.setEaten(false, meal: "Dinner", foodID: shake, on: date("2026-10-05"))) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("That item is not in the plan"))
        }
    }

    func testAnItemThatIsOffItsCycleIsLeftOutWithoutATick() throws {
        try plans.changeItem(meal: "Brunch", foodID: supplement, from: date("2026-10-01"),
                             cycle: try .weeks(on: 1, off: 1, firstMonday: date("2026-10-05")))

        let off = try XCTUnwrap(try day("2026-10-12").meals.flatMap(\.lines).first { $0.foodID == supplement })

        XCTAssertEqual(off.state, .offCycle(backOn: date("2026-10-19")))
        XCTAssertEqual(try day("2026-10-12").cost, Cost(amount: 65, isComplete: true), "the supplement's 2 is not counted")
        XCTAssertEqual(try day("2026-10-12").skippedCount, 0, "off its cycle is not the same as unticked")
    }

    func testAnOnDayOfACycleShowsWhereItIsInTheCycle() throws {
        try plans.changeItem(meal: "Brunch", foodID: supplement, from: date("2026-10-01"),
                             cycle: try .weeks(on: 2, off: 1, firstMonday: date("2026-10-05")))

        let line = try XCTUnwrap(try day("2026-10-08").meals.flatMap(\.lines).first { $0.foodID == supplement })

        XCTAssertEqual(line.state, .eaten)
        XCTAssertEqual(line.cycle, CycleState(isOn: true, dayInPhase: 4, phaseLength: 14, nextChange: date("2026-10-19")))
    }

    func testPlannedTotalsLeaveOutItemsThatAreOffThatDay() throws {
        try plans.addItem(foodID: library.add(FoodDraft(name: "Cycled", labelCalories: 100)), quantity: 100, meal: "Dinner",
                          cycle: try .weeks(on: 1, off: 1, firstMonday: date("2026-10-05")), from: date("2026-10-01"))

        XCTAssertEqual(try day("2026-10-05").planned.calories, 1100, accuracy: 0.001)
        XCTAssertEqual(try day("2026-10-12").planned.calories, 1000, accuracy: 0.001)
    }

    // MARK: Extras

    func testExtrasAreAddedOnTopOfThePlan() throws {
        try diet.addExtra(foodID: biscuits, .pieces(4), on: date("2026-10-05"))

        let d = try day("2026-10-05")

        XCTAssertEqual(d.total.calories, 1137.14, accuracy: 0.01)
        XCTAssertEqual(d.extras.count, 1)
        XCTAssertEqual(d.extras[0].name, "Tea biscuits")
        XCTAssertEqual(d.extras[0].amount, 28.5714, accuracy: 0.001)
        XCTAssertEqual(d.extras[0].pieces ?? 0, 4, accuracy: 0.0001)
        XCTAssertEqual(d.extras[0].nutrition.protein, 2, accuracy: 0.01)
    }

    func testAnExtraCanBeChangedOrRemoved() throws {
        let id = try diet.addExtra(foodID: biscuits, .pieces(4), on: date("2026-10-05"))

        try diet.updateExtra(id, .pieces(2))
        XCTAssertEqual(try day("2026-10-05").extras[0].amount, 14.2857, accuracy: 0.001)

        try diet.removeExtra(id)
        XCTAssertEqual(try day("2026-10-05").total.calories, 1000, accuracy: 0.001)
        XCTAssertTrue(try day("2026-10-05").extras.isEmpty)
    }

    func testCostAddsUpTheEatenItemsAndTheExtras() throws {
        try diet.addExtra(foodID: biscuits, .pieces(4), on: date("2026-10-05"))

        XCTAssertEqual(try day("2026-10-05").cost.amount, 70, accuracy: 0.01)
        XCTAssertEqual(try day("2026-10-06").cost.amount, 67, accuracy: 0.01)
    }

    func testEditingAFoodRecalculatesTheDaysThatUsedIt() throws {
        XCTAssertEqual(try day("2026-10-05").total.calories, 1000, accuracy: 0.001)
        var draft = try XCTUnwrap(try library.food(oats)).draft
        draft.labelCalories = 300

        try library.update(oats, draft)

        XCTAssertEqual(try day("2026-10-05").total.calories, 1100, accuracy: 0.001)
    }

    func testADayBeforeThePlanHasNoPlanItemsButCanHaveExtras() throws {
        try diet.addExtra(foodID: biscuits, .pieces(4), on: date("2026-09-20"))

        let d = try day("2026-09-20")

        XCTAssertFalse(d.hasPlan)
        XCTAssertTrue(d.meals.isEmpty)
        XCTAssertEqual(d.total.calories, 137.14, accuracy: 0.01)
    }

    func testExtrasOverAWeek() throws {
        try diet.addExtra(foodID: biscuits, .amount(28.5714), on: date("2026-10-05"))
        try diet.addExtra(foodID: oats, .amount(25), on: date("2026-10-07"))
        try diet.addExtra(foodID: oats, .amount(25), on: date("2026-10-07"))
        try diet.addExtra(foodID: oats, .amount(25), on: date("2026-09-20"))

        let week = try diet.extrasSummary(endingOn: date("2026-10-08"), days: 7)

        XCTAssertEqual(week.days, 2)
        XCTAssertEqual(week.nutrition.calories, 137.14 + 200, accuracy: 0.01)
        XCTAssertEqual(week.cost.amount, 3 + 5, accuracy: 0.01)
    }

    func testRecentExtrasListTheLastAmountOfEachFoodNewestFirst() throws {
        try diet.addExtra(foodID: oats, .amount(25), on: date("2026-10-03"))
        try diet.addExtra(foodID: biscuits, .pieces(6), on: date("2026-10-04"))
        try diet.addExtra(foodID: biscuits, .pieces(4), on: date("2026-10-05"))

        let recent = try diet.recentExtras(limit: 5)

        XCTAssertEqual(recent.map(\.foodID), [biscuits, oats])
        XCTAssertEqual(recent[0].pieces, 4)
        XCTAssertEqual(recent[1].amount, 25)
    }

    func testAFoodWithNoPriceMakesTheDaysCostIncomplete() throws {
        let free = try library.add(FoodDraft(name: "Mystery"))
        try diet.addExtra(foodID: free, .amount(10), on: date("2026-10-05"))

        XCTAssertFalse(try day("2026-10-05").cost.isComplete)
        XCTAssertTrue(try day("2026-10-06").cost.isComplete)
    }

    // MARK: Targets

    func testProteinIsAMinimum() throws {
        try DietSettings(db).setProteinMinimum(60)

        XCTAssertTrue(try day("2026-10-05").targets.proteinMet)

        try diet.setEaten(false, meal: "Brunch", foodID: shake, on: date("2026-10-05"))
        XCTAssertFalse(try day("2026-10-05").targets.proteinMet)
        XCTAssertEqual(try day("2026-10-05").targets.proteinShortBy, 53, accuracy: 0.001)
    }

    func testTheFatLimitIsTheSmallerOfAShareOfCaloriesAndTheWeightCap() {
        let rules = DietRules(proteinMinimumGrams: 180, fatPercentOfCalories: 20, fatCeilingGramsPerPound: 0.4)

        let low = DietTargets.evaluate(calories: 1000, protein: 0, fat: 10, rules: rules, averageWeightKg: 64)
        let high = DietTargets.evaluate(calories: 3000, protein: 0, fat: 10, rules: rules, averageWeightKg: 64)

        XCTAssertEqual(try XCTUnwrap(low.weightCapGrams), 56.32, accuracy: 0.001)
        XCTAssertEqual(low.fatLimitGrams, 22.222, accuracy: 0.001)
        XCTAssertEqual(low.fatLimitSource, .shareOfCalories)
        XCTAssertEqual(high.fatLimitGrams, 56.32, accuracy: 0.001)
        XCTAssertEqual(high.fatLimitSource, .weightCap)
    }

    func testFatOverTheLimitIsFlagged() {
        let rules = DietRules(proteinMinimumGrams: 180, fatPercentOfCalories: 20, fatCeilingGramsPerPound: 0.4)

        XCTAssertFalse(DietTargets.evaluate(calories: 900, protein: 0, fat: 16, rules: rules, averageWeightKg: nil).fatOver)
        XCTAssertTrue(DietTargets.evaluate(calories: 900, protein: 0, fat: 24, rules: rules, averageWeightKg: nil).fatOver)
    }

    func testWithNoWeighInsThereIsOnlyTheShareOfCalories() {
        let rules = DietRules(proteinMinimumGrams: 180, fatPercentOfCalories: 20, fatCeilingGramsPerPound: 0.4)

        let targets = DietTargets.evaluate(calories: 3000, protein: 0, fat: 10, rules: rules, averageWeightKg: nil)

        XCTAssertNil(targets.weightCapGrams)
        XCTAssertEqual(targets.fatLimitGrams, 66.667, accuracy: 0.001)
    }

    func testTheWeightCapUsesTheSevenDayAverageWeighIn() throws {
        for offset in 0..<7 { try db.addBodyWeight(on: date("2026-10-05").adding(days: -offset).string, kg: offset == 0 ? 65 : 64) }
        try db.addBodyWeight(on: "2026-09-20", kg: 90)

        let cap = try XCTUnwrap(try day("2026-10-05").targets.weightCapGrams)

        XCTAssertEqual(cap, (64 * 6 + 65) / 7 * 2.2 * 0.4, accuracy: 0.001)
    }
}
