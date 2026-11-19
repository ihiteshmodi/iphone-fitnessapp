import XCTest
@testable import FitnessCore

final class BreakModeTests: XCTestCase {
    private var db: Database!
    private var breaks: BreakModeService!
    private var calories: CalorieService!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        breaks = BreakModeService(db)
        calories = CalorieService(db)
        try calories.setDefault(calories: 2600, from: date("2026-10-01"))
    }

    private func weighDaily(from first: String, to last: String, kg: Double = 65) throws {
        var day = date(first)
        while day <= date(last) {
            try db.addBodyWeight(on: day.string, kg: kg)
            day = day.adding(days: 1)
        }
    }

    func testABreakWithDatesCoversThoseDaysOnly() throws {
        try breaks.add(from: date("2026-11-15"), to: date("2026-11-21"))

        XCTAssertTrue(try breaks.isOnBreak(date("2026-11-15")))
        XCTAssertTrue(try breaks.isOnBreak(date("2026-11-21")))
        XCTAssertFalse(try breaks.isOnBreak(date("2026-11-14")))
        XCTAssertFalse(try breaks.isOnBreak(date("2026-11-22")))
    }

    func testAnOpenBreakLastsUntilItIsEnded() throws {
        try breaks.start(on: date("2026-11-15"))
        XCTAssertTrue(try breaks.isOnBreak(date("2026-11-20")))

        try breaks.end(on: date("2026-11-21"))

        XCTAssertEqual(try breaks.periods(), [BreakPeriod(id: 1, start: date("2026-11-15"), end: date("2026-11-21"))])
        XCTAssertFalse(try breaks.isOnBreak(date("2026-11-22")))
    }

    func testBreaksCannotOverlapOrEndBeforeTheyStart() throws {
        try breaks.add(from: date("2026-11-15"), to: date("2026-11-21"))

        XCTAssertThrowsError(try breaks.add(from: date("2026-11-20"), to: date("2026-11-25"))) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("That overlaps another break"))
        }
        XCTAssertThrowsError(try breaks.add(from: date("2026-11-25"), to: date("2026-11-24"))) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("A break ends on or after the day it starts"))
        }
    }

    func testTheMathsRecalibratesUntilTwoCleanWeeksFollowTheBreak() throws {
        try weighDaily(from: "2026-10-27", to: "2026-11-09", kg: 66)
        try breaks.add(from: date("2026-11-10"), to: date("2026-11-16"))
        try weighDaily(from: "2026-11-17", to: "2026-11-25", kg: 65)

        XCTAssertThrowsError(try calories.currentAdvice()) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Recalibrating after your break: 9 of 14 days"))
        }

        try weighDaily(from: "2026-11-26", to: "2026-11-30", kg: 65)
        let averages = try calories.weeklyAverages()
        XCTAssertEqual(averages.pastAverageKg, 65, accuracy: 1e-9, "only weigh-ins after the break")
    }

    func testBreakDaysNeverCountTowardCaloriesEaten() throws {
        try breaks.add(from: date("2026-11-15"), to: date("2026-11-16"))
        try calories.saveCalories(on: date("2026-11-15"), calories: 9000)

        XCTAssertEqual(try calories.averageCalories(endingOn: date("2026-11-16"), days: 7), 2600)
    }

    func testWhereIStoodBeforeTheBreak() throws {
        try weighDaily(from: "2026-11-01", to: "2026-11-09", kg: 66)
        try weighDaily(from: "2026-11-10", to: "2026-11-16", kg: 65.5)
        try breaks.add(from: date("2026-11-17"), to: date("2026-11-23"))
        try db.addBodyWeight(on: "2026-11-24", kg: 66.4)

        let before = try XCTUnwrap(try breaks.beforeBreak(BreakPeriod(id: 1, start: date("2026-11-17"), end: date("2026-11-23")), calories: calories))

        XCTAssertEqual(before.advice.averages.latestWeighIn, date("2026-11-16"))
        XCTAssertEqual(before.weightBeforeKg, 65.5)
        XCTAssertEqual(before.weightAfterKg, 66.4)
    }
}
