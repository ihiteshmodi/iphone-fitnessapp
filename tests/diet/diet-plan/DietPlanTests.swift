import XCTest
@testable import FitnessCore

final class DietPlanTests: XCTestCase {
    private var db: Database!
    private var library: FoodLibrary!
    private var plans: DietPlanService!
    private var oats = 0
    private var rice = 0
    private var lentils = 0

    override func setUpWithError() throws {
        db = try Database.inMemory()
        library = FoodLibrary(db)
        plans = DietPlanService(db)
        oats = try library.add(FoodDraft(name: "Oats"))
        rice = try library.add(FoodDraft(name: "Rice"))
        lentils = try library.add(FoodDraft(name: "Lentils"))
    }

    private func start(_ day: String, items: [(meal: String, food: Int, quantity: Double)]) throws {
        for item in items { try plans.addItem(foodID: item.food, quantity: item.quantity, meal: item.meal, from: date(day)) }
    }

    private func summary(_ plan: DietPlan?) -> [String] {
        (plan?.meals ?? []).flatMap { meal in meal.items.map { "\(meal.name): \($0.foodID) x \($0.quantity)" } }
    }

    // MARK: What a plan is

    func testAPlanIsAListOfFoodsInMealsInOrder() throws {
        try start("2026-10-01", items: [("Morning", oats, 50), ("Dinner", rice, 150), ("Dinner", lentils, 60)])

        let plan = try XCTUnwrap(try plans.plan(inForceOn: date("2026-10-05")))

        XCTAssertEqual(plan.meals.map(\.name), ["Morning", "Dinner"])
        XCTAssertEqual(summary(plan), ["Morning: \(oats) x 50.0", "Dinner: \(rice) x 150.0", "Dinner: \(lentils) x 60.0"])
    }

    func testThePlanInForceIsTheNewestOneThatStartedOnOrBeforeTheDay() throws {
        try start("2026-10-01", items: [("Morning", oats, 50)])
        try plans.changeItem(meal: "Morning", foodID: oats, from: date("2026-10-20"), quantity: 80)

        XCTAssertEqual(try plans.plan(inForceOn: date("2026-10-19"))?.effectiveFrom, date("2026-10-01"))
        XCTAssertEqual(try plans.plan(inForceOn: date("2026-10-20"))?.effectiveFrom, date("2026-10-20"))
        XCTAssertEqual(try plans.plan(inForceOn: date("2026-10-30"))?.effectiveFrom, date("2026-10-20"))
        XCTAssertNil(try plans.plan(inForceOn: date("2026-09-30")))
    }

    // MARK: Changing from a date

    func testChangingThePlanFromADateNeverRewritesEarlierDays() throws {
        try start("2026-10-01", items: [("Morning", oats, 50)])

        try plans.changeItem(meal: "Morning", foodID: oats, from: date("2026-10-26"), quantity: 80)

        XCTAssertEqual(summary(try plans.plan(inForceOn: date("2026-10-25"))), ["Morning: \(oats) x 50.0"])
        XCTAssertEqual(summary(try plans.plan(inForceOn: date("2026-10-26"))), ["Morning: \(oats) x 80.0"])
    }

    func testAChangeOnTheDateAPlanStartsEditsThatPlanInPlace() throws {
        try start("2026-10-26", items: [("Morning", oats, 50), ("Dinner", rice, 100)])

        try plans.changeItem(meal: "Morning", foodID: oats, from: date("2026-10-26"), quantity: 60)
        try plans.changeItem(meal: "Dinner", foodID: rice, from: date("2026-10-26"), quantity: 120)

        XCTAssertEqual(try plans.startDates(), [date("2026-10-26")])
        XCTAssertEqual(summary(try plans.plan(inForceOn: date("2026-10-26"))), ["Morning: \(oats) x 60.0", "Dinner: \(rice) x 120.0"])
    }

    func testAddingRemovingAndMovingItems() throws {
        try start("2026-10-26", items: [("Morning", oats, 50), ("Dinner", rice, 100)])

        try plans.addItem(foodID: lentils, quantity: 60, meal: "Dinner", from: date("2026-10-26"))
        XCTAssertTrue(summary(try plans.plan(inForceOn: date("2026-10-26"))).contains("Dinner: \(lentils) x 60.0"))

        try plans.removeItem(meal: "Dinner", foodID: lentils, from: date("2026-10-26"))
        XCTAssertFalse(summary(try plans.plan(inForceOn: date("2026-10-26"))).contains("Dinner: \(lentils) x 60.0"))

        try plans.changeItem(meal: "Morning", foodID: oats, from: date("2026-10-26"), moveTo: "Brunch")
        XCTAssertEqual(try XCTUnwrap(try plans.plan(inForceOn: date("2026-10-26"))).meals.map(\.name), ["Dinner", "Brunch"])
    }

    func testAnItemKeepsItsCycleAndACopiedPlanKeepsItToo() throws {
        let cycle = try CycleRule.weeks(on: 2, off: 1, firstMonday: date("2026-10-26"))
        try plans.addItem(foodID: oats, quantity: 1, meal: "Brunch", cycle: cycle, from: date("2026-10-26"))

        try plans.changeItem(meal: "Brunch", foodID: oats, from: date("2026-11-02"), quantity: 2)

        XCTAssertEqual(try plans.plan(inForceOn: date("2026-10-26"))?.items.first?.cycle, cycle)
        XCTAssertEqual(try plans.plan(inForceOn: date("2026-11-02"))?.items.first?.cycle, cycle)
    }

    func testAnItemsCycleCanBeChanged() throws {
        try plans.addItem(foodID: oats, quantity: 1, meal: "Brunch", from: date("2026-10-26"))
        let cycle = CycleRule.weekdays(.weekend)

        try plans.changeItem(meal: "Brunch", foodID: oats, from: date("2026-10-26"), cycle: cycle)

        XCTAssertEqual(try plans.plan(inForceOn: date("2026-10-26"))?.items.first?.cycle, cycle)
    }

    // MARK: Rules

    func testTheSameFoodCannotAppearTwiceInOneMeal() throws {
        try start("2026-10-26", items: [("Morning", oats, 50)])

        XCTAssertThrowsError(try plans.addItem(foodID: oats, quantity: 10, meal: "Morning", from: date("2026-10-26"))) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Oats is already in Morning"))
        }
        XCTAssertNoThrow(try plans.addItem(foodID: oats, quantity: 10, meal: "Dinner", from: date("2026-10-26")))
    }

    func testRemovingThePlanThatStartsOnADateLetsTheEarlierPlanApplyAgain() throws {
        try start("2026-10-01", items: [("Morning", oats, 50)])
        try plans.changeItem(meal: "Morning", foodID: oats, from: date("2026-10-20"), quantity: 80)

        try plans.removePlan(startingOn: date("2026-10-20"))

        XCTAssertEqual(try plans.plan(inForceOn: date("2026-10-25"))?.effectiveFrom, date("2026-10-01"))
    }

    func testAPlanItemMustBeValid() throws {
        let cases: [(Double, String, Int, String)] = [
            (0, "Morning", oats, "Enter a quantity above 0"),
            (5, "  ", oats, "Give the meal a name"),
            (5, "Morning", 9999, "That food is not in the library"),
        ]
        for (quantity, meal, food, message) in cases {
            XCTAssertThrowsError(try plans.addItem(foodID: food, quantity: quantity, meal: meal, from: date("2026-10-26")), message) {
                XCTAssertEqual($0 as? ValidationError, ValidationError(message))
            }
        }
        XCTAssertEqual(try plans.startDates(), [], "a rejected item leaves no empty plan behind")
    }

    func testChangingAnItemThatIsNotInThePlanIsRejected() throws {
        try start("2026-10-01", items: [("Morning", oats, 50)])

        XCTAssertThrowsError(try plans.changeItem(meal: "Dinner", foodID: oats, from: date("2026-10-26"), quantity: 1)) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("That item is not in the plan"))
        }
        XCTAssertEqual(try plans.startDates(), [date("2026-10-01")], "a rejected change leaves no new plan behind")
    }
}
