import XCTest
@testable import FitnessCore

final class DailyCaloriesTests: XCTestCase {
    private var db: Database!
    private var service: CalorieService!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        service = CalorieService(db)
    }

    private func calories(on day: String) throws -> Double? { try service.day(date(day)).calories }
    private func source(on day: String) throws -> CalorieSource { try service.day(date(day)).source }

    // MARK: Default from a date

    func testANewDefaultAppliesFromItsStartDateOnwardAndNeverRewritesEarlierDays() throws {
        try service.setDefault(calories: 2900, from: date("2026-10-01"))
        try service.setDefault(calories: 3000, from: date("2026-10-26"))

        XCTAssertEqual(try calories(on: "2026-10-25"), 2900)
        XCTAssertEqual(try calories(on: "2026-10-26"), 3000)
        XCTAssertEqual(try calories(on: "2026-10-30"), 3000)
        XCTAssertNil(try calories(on: "2026-09-30"))
        XCTAssertEqual(try source(on: "2026-10-25"), .baseline)
        XCTAssertEqual(try source(on: "2026-09-30"), .none)
    }

    func testANewDefaultCanStartInThePast() throws {
        try service.setDefault(calories: 2900, from: date("2026-10-01"))
        try service.setDefault(calories: 3000, from: date("2026-10-25"))

        XCTAssertEqual(try calories(on: "2026-10-24"), 2900)
        XCTAssertEqual(try calories(on: "2026-10-25"), 3000)
    }

    func testSettingTheDefaultAgainForTheSameStartDateReplacesIt() throws {
        try service.setDefault(calories: 2900, from: date("2026-10-26"))
        try service.setDefault(calories: 3100, multiplier: 0.9, from: date("2026-10-26"))

        XCTAssertEqual(try service.defaults(), [CalorieDefault(effectiveFrom: date("2026-10-26"), calories: 3100, multiplier: 0.9)])
    }

    func testListsDefaultsNewestFirstAndCanRemoveOne() throws {
        try service.setDefault(calories: 2900, from: date("2026-10-01"))
        try service.setDefault(calories: 3000, from: date("2026-10-26"))

        XCTAssertEqual(try service.defaults().map(\.calories), [3000, 2900])

        try service.deleteDefault(from: date("2026-10-26"))

        XCTAssertEqual(try calories(on: "2026-10-27"), 2900)
    }

    // MARK: Manual days

    func testADayChangedByHandWinsOverTheDefaultUntilItIsCleared() throws {
        try service.setDefault(calories: 2400, from: date("2026-10-01"))
        try service.saveCalories(on: date("2026-10-21"), calories: 3000)

        XCTAssertEqual(try calories(on: "2026-10-21"), 3000)
        XCTAssertEqual(try source(on: "2026-10-21"), .manual)

        try service.deleteCalories(on: date("2026-10-21"))

        XCTAssertEqual(try calories(on: "2026-10-21"), 2400)
        XCTAssertEqual(try source(on: "2026-10-21"), .baseline)
    }

    func testAManualDayKeepsItsValueWhenTheDefaultChanges() throws {
        try service.setDefault(calories: 2400, from: date("2026-10-01"))
        try service.saveCalories(on: date("2026-10-28"), calories: 3500)
        try service.setDefault(calories: 3000, from: date("2026-10-26"))

        XCTAssertEqual(try calories(on: "2026-10-28"), 3500)
        XCTAssertEqual(try calories(on: "2026-10-27"), 3000)
    }

    // MARK: Recent days

    func testListsTheLastDaysNewestFirstWithWhereEachValueComesFrom() throws {
        try service.setDefault(calories: 2400, from: date("2026-10-01"))
        try service.saveCalories(on: date("2026-10-24"), calories: 1800)

        let days = try service.days(endingOn: date("2026-10-26"), count: 7)

        XCTAssertEqual(days.map(\.date.string), ["2026-10-26", "2026-10-25", "2026-10-24", "2026-10-23", "2026-10-22", "2026-10-21", "2026-10-20"])
        XCTAssertEqual(days.map(\.calories), [2400, 2400, 1800, 2400, 2400, 2400, 2400])
        XCTAssertEqual(days.map(\.source), [.baseline, .baseline, .manual, .baseline, .baseline, .baseline, .baseline])
    }

    // MARK: Weekly average

    func testTheWeeklyAverageMixesTheOldAndNewDefaultDayByDay() throws {
        try service.setDefault(calories: 2900, from: date("2026-10-01"))
        try service.setDefault(calories: 3000, from: date("2026-10-23"))

        let average = try XCTUnwrap(try service.averageCalories(endingOn: date("2026-10-26"), days: 7))

        XCTAssertEqual(average, 2957.142857, accuracy: 1e-5)
    }

    func testManualDaysArePartOfTheWeeklyAverage() throws {
        try service.setDefault(calories: 2400, from: date("2026-10-01"))
        try service.saveCalories(on: date("2026-10-21"), calories: 3000)
        try service.saveCalories(on: date("2026-10-24"), calories: 1800)

        XCTAssertEqual(try service.averageCalories(endingOn: date("2026-10-26"), days: 7) ?? 0, 2400, accuracy: 1e-9)
    }

    func testDaysWithNoCaloriesAreLeftOutOfTheAverage() throws {
        try service.saveCalories(on: date("2026-10-25"), calories: 2948.5)

        XCTAssertEqual(try service.averageCalories(endingOn: date("2026-10-26"), days: 7), 2948.5)
        XCTAssertNil(try service.averageCalories(endingOn: date("2026-09-01"), days: 7))
    }

    // MARK: Calorie target

    func testTheTargetUsesTheWeeksAverageCaloriesAndTheDefaultsMultiplier() throws {
        let latest = date("2026-10-23")
        for offset in 0..<7 { try db.addBodyWeight(on: latest.adding(days: -offset).string, kg: 63.86) }
        for offset in 7..<14 { try db.addBodyWeight(on: latest.adding(days: -offset).string, kg: 63.94) }
        try service.setDefault(calories: 3000, multiplier: 0.8, from: date("2026-10-01"))
        try service.saveCalories(on: date("2026-10-20"), calories: 2400)

        let target = try service.currentAdvice().target

        XCTAssertEqual(target.caloriesEaten, 2914.2857142857, accuracy: 1e-6)
        XCTAssertEqual(target.multiplier, 0.8)
    }

    func testTheTargetFallsBackToTheNewestDefaultWhenTheWeekHasNoCaloriesYet() throws {
        let latest = date("2026-10-23")
        for offset in 0..<7 { try db.addBodyWeight(on: latest.adding(days: -offset).string, kg: 63.86) }
        for offset in 7..<14 { try db.addBodyWeight(on: latest.adding(days: -offset).string, kg: 63.94) }
        try service.setDefault(calories: 2948.5, multiplier: 0.8, from: date("2026-10-26"))

        let target = try service.currentAdvice().target

        XCTAssertEqual(target.caloriesEaten, 2948.5)
        XCTAssertEqual(target.multiplier, 0.8)
    }

    func testTheTargetNeedsCaloriesFromSomewhere() throws {
        try db.addBodyWeight(on: "2026-10-23", kg: 64)
        try db.addBodyWeight(on: "2026-10-16", kg: 64)

        XCTAssertThrowsError(try service.currentAdvice()) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Log the calories you ate per day"))
        }
    }

    // MARK: Validation

    func testRefusesAnInvalidDefault() throws {
        let examples: [(Double, Double, String, String)] = [
            (0, 1, "2026-10-26", "Calories must be above 0"),
            (3000, 0, "2026-10-26", "Multiplier must be above 0"),
            (3000, 1, "2026-02-30", "Date is not valid"),
        ]

        for (kcal, multiplier, day, message) in examples {
            XCTAssertThrowsError(try service.setDefault(calories: kcal, multiplier: multiplier, from: day), message) { error in
                XCTAssertEqual(error as? ValidationError, ValidationError(message))
            }
        }
        XCTAssertEqual(try service.defaults(), [])
    }

    // MARK: Balance (pure)

    func testKnowsAWeightDropOfHalfAKiloIsADeficitOf551CaloriesADay() {
        let target = CalorieTarget.calculate(currentAverageKg: 82.0, pastAverageKg: 82.5, caloriesEaten: 2400, rules: MacroRules(proteinGramsPerLb: 1.2, fatPercent: 25))

        XCTAssertEqual(target.balance, .deficit)
        XCTAssertEqual(target.dailyBalanceKcal, -551)
    }

    func testClassifiesTheWeightChangeWithAMaintenanceBandOf100CaloriesADay() {
        let examples: [(change: Double, balance: EnergyBalance)] = [
            (-0.5, .deficit), (-0.05, .maintenance), (0, .maintenance), (0.05, .maintenance), (0.5, .surplus),
        ]

        for example in examples {
            let target = CalorieTarget.calculate(currentAverageKg: 82 + example.change, pastAverageKg: 82, caloriesEaten: 2400,
                                                 rules: MacroRules(proteinGramsPerLb: 1.2, fatPercent: 25))
            XCTAssertEqual(target.balance, example.balance, "change \(example.change)")
        }
    }

    func testKnowsTheBalanceFromWeightAloneWithoutAnyCalories() {
        let balance = CalorieTarget.balance(currentAverageKg: 82.0, pastAverageKg: 82.5)

        XCTAssertEqual(balance, CalorieTarget.Balance(dailyKcal: -551, kind: .deficit))
    }

    func testReadsThePlannedModeFromTheMultiplier() {
        let examples: [(multiplier: Double, mode: PlannedMode)] = [(0.85, .cut), (1, .maintain), (1.1, .bulk)]

        for example in examples {
            let target = CalorieTarget.calculate(currentAverageKg: 82, pastAverageKg: 82, caloriesEaten: 2400, multiplier: example.multiplier,
                                                 rules: MacroRules(proteinGramsPerLb: 1.2, fatPercent: 25))
            XCTAssertEqual(target.plannedMode, example.mode, "multiplier \(example.multiplier)")
        }
    }
}
