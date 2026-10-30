import XCTest
@testable import FitnessCore

final class DietCaloriesTests: XCTestCase {
    private var db: Database!
    private var library: FoodLibrary!
    private var plans: DietPlanService!
    private var diet: DietDayService!
    private var calories: CalorieService!
    private var main = 0
    private var snack = 0
    private var biscuit = 0

    override func setUpWithError() throws {
        db = try Database.inMemory()
        library = FoodLibrary(db)
        plans = DietPlanService(db)
        diet = DietDayService(db)
        calories = CalorieService(db)
        main = try library.add(FoodDraft(name: "Main meal", unit: "unit", baseQuantity: 1, labelCalories: 2400))
        snack = try library.add(FoodDraft(name: "Snack", unit: "unit", baseQuantity: 1, labelCalories: 400))
        biscuit = try library.add(FoodDraft(name: "Biscuit", unit: "unit", baseQuantity: 1, labelCalories: 150))
        try plans.addItem(foodID: main, quantity: 1, meal: "Day", from: date("2026-10-26"))
        try plans.addItem(foodID: snack, quantity: 1, meal: "Day", from: date("2026-10-26"))
        try calories.setDefault(calories: 2500, from: date("2026-10-01"))
    }

    private func day(_ text: String) throws -> CalorieDay { try calories.day(date(text)) }

    private func tickPlan(on text: String) throws { try diet.setMealEaten(true, meal: "Day", on: date(text)) }

    func testADayWithAPlanCountsWhatIsTicked() throws {
        try tickPlan(on: "2026-10-27")
        let d = try day("2026-10-27")

        XCTAssertEqual(d.calories, 2800)
        XCTAssertEqual(d.source, .plan)
        XCTAssertEqual([d.tickedCount, d.plannedCount], [2, 2])
    }

    func testAPlanDayWithNothingTickedCountsZeroNotTheDefault() throws {
        let d = try day("2026-10-27")

        XCTAssertEqual(d.calories, 0)
        XCTAssertEqual(d.source, .plan)
        XCTAssertEqual([d.tickedCount, d.plannedCount], [0, 2])
    }

    func testADayTypedByHandWinsOverTheDiet() throws {
        try tickPlan(on: "2026-10-27")
        try calories.saveCalories(on: date("2026-10-27"), calories: 3100)

        XCTAssertEqual(try day("2026-10-27").calories, 3100)
        XCTAssertEqual(try day("2026-10-27").source, .manual)

        try calories.deleteCalories(on: date("2026-10-27"))
        XCTAssertEqual(try day("2026-10-27").source, .plan)
    }

    func testADayBeforeAnyPlanKeepsTheDefault() throws {
        XCTAssertEqual(try day("2026-10-25").calories, 2500)
        XCTAssertEqual(try day("2026-10-25").source, .baseline)
    }

    func testOnlyTickedItemsAndExtrasCountAndTheDayShowsHowMany() throws {
        try diet.setEaten(true, meal: "Day", foodID: snack, on: date("2026-10-28"))
        try diet.addExtra(foodID: biscuit, .amount(1), on: date("2026-10-28"))

        let d = try day("2026-10-28")

        XCTAssertEqual(d.calories, 550)
        XCTAssertEqual(d.source, .plan)
        XCTAssertEqual([d.tickedCount, d.plannedCount], [1, 2])
        XCTAssertEqual(d.extraCount, 1)
    }

    func testExtrasAreAddedToADefaultDayToo() throws {
        try diet.addExtra(foodID: biscuit, .amount(1), on: date("2026-10-25"))

        let d = try day("2026-10-25")

        XCTAssertEqual(d.calories, 2650)
        XCTAssertEqual(d.source, .baseline)
        XCTAssertEqual(d.extraCount, 1)
    }

    func testExtrasOnATypedDayDoNotChangeWhatWasTyped() throws {
        try calories.saveCalories(on: date("2026-10-25"), calories: 2000)
        try diet.addExtra(foodID: biscuit, .amount(1), on: date("2026-10-25"))

        XCTAssertEqual(try day("2026-10-25").calories, 2000)
        XCTAssertEqual(try day("2026-10-25").extraCount, 0)
    }

    func testAFutureDayCountsWhatIsTickedWithItemsThatAreOffTheirCycleLeftOut() throws {
        let cycled = try library.add(FoodDraft(name: "Cycled", unit: "unit", baseQuantity: 1, labelCalories: 100))
        try plans.addItem(foodID: cycled, quantity: 1, meal: "Day", cycle: try .weeks(on: 1, off: 1, firstMonday: date("2026-10-26")), from: date("2026-10-26"))

        try tickPlan(on: "2026-11-02")
        try tickPlan(on: "2026-11-09")
        XCTAssertEqual(try day("2026-11-02").calories, 2800, "an off week")
        XCTAssertEqual(try day("2026-11-09").calories, 2900, "on again")
    }

    func testTheWeeklyAverageAndTheCalorieTargetUseTheDietDays() throws {
        for text in ["2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29"] { try tickPlan(on: text) }
        for offset in 0..<7 { try db.addBodyWeight(on: date("2026-10-29").adding(days: -offset).string, kg: 64) }
        for offset in 7..<14 { try db.addBodyWeight(on: date("2026-10-29").adding(days: -offset).string, kg: 64.2) }

        let average = try XCTUnwrap(try calories.averageCalories(endingOn: date("2026-10-29"), days: 7))
        let target = try calories.currentAdvice().target

        XCTAssertEqual(average, 2671.4286, accuracy: 0.001)
        XCTAssertEqual(target.caloriesEaten, 2671.4286, accuracy: 0.001)
    }

    func testADayWithNoPlanNoDefaultAndNothingTypedHasNoCalories() throws {
        let empty = CalorieService(try Database.inMemory())

        XCTAssertNil(try empty.day(date("2026-10-27")).calories)
        XCTAssertEqual(try empty.day(date("2026-10-27")).source, .none)
    }
}
