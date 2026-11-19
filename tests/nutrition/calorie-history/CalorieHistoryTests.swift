import XCTest
@testable import FitnessCore

final class CalorieHistoryTests: XCTestCase {
    private var db: Database!
    private var service: CalorieService!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        service = CalorieService(db)
        let first = date("2026-11-01")
        for offset in 0..<20 {
            let day = first.adding(days: offset)
            try db.addBodyWeight(on: day.string, kg: day < date("2026-11-11") ? 65.0 : 64.8)
        }
        try service.setDefault(calories: 2600, multiplier: 1, from: date("2026-10-01"))
    }

    func testAPastDayUsesOnlyTheWeighInsUpToThatDay() throws {
        let advice = try service.advice(asOf: date("2026-11-17"))

        XCTAssertEqual(advice.averages.latestWeighIn, date("2026-11-17"))
        XCTAssertEqual(advice.averages.currentAverageKg, 64.8, accuracy: 1e-9)
        XCTAssertEqual(advice.averages.pastAverageKg, 65.0, accuracy: 1e-9)
    }

    func testFoodTypedAfterThatDayDoesNotChangeIt() throws {
        try service.saveCalories(on: date("2026-11-18"), calories: 4000)
        try service.saveCalories(on: date("2026-11-17"), calories: 4000)

        XCTAssertEqual(try service.advice(asOf: date("2026-11-17")).target.caloriesEaten, 2600, "food counts up to the day before")
    }

    func testTheGoalMultiplierIsTheOneInForceOnThatDay() throws {
        try service.setDefault(calories: 2400, multiplier: 0.8, from: date("2026-11-19"))

        let monday = try service.advice(asOf: date("2026-11-17")).target
        XCTAssertEqual(monday.multiplier, 1)
        XCTAssertNil(monday.macros)
        XCTAssertEqual(try service.advice(asOf: date("2026-11-20")).target.multiplier, 0.8)
    }

    func testADayWithoutAWeighInUsesTheLatestWeighInBeforeIt() throws {
        try db.execute("DELETE FROM body_weights WHERE measured_on = '2026-11-20'")

        XCTAssertEqual(try service.advice(asOf: date("2026-11-21")).averages.latestWeighIn, date("2026-11-19"))
    }

    func testTooFarBackForTwoWeeksOfWeighIns() throws {
        XCTAssertThrowsError(try service.advice(asOf: date("2026-11-05"))) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Log body weight for both of the last two weeks"))
        }
    }
}
