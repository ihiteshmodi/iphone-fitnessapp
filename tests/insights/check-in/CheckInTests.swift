import XCTest
@testable import FitnessCore

final class CheckInTests: XCTestCase {
    private var db: Database!
    private var checkIn: CheckInService!
    private let today = date("2026-11-19")

    override func setUpWithError() throws {
        db = try Database.inMemory()
        checkIn = CheckInService(db)
    }

    private func todayRules() throws -> [Insight] { try InsightService(db, daily: CheckInRules.daily, setup: []).today(on: today) }

    func testAnswersAreKeptPerDayAndCanBeCleared() throws {
        try checkIn.setUrine(.pale, on: today)
        try checkIn.setWalked(true, after: "Brunch", on: today)

        XCTAssertEqual(try checkIn.day(today), CheckInDay(urine: .pale, heavySweat: nil, walkedAfter: ["Brunch"]))
        try checkIn.setUrine(nil, on: today)
        XCTAssertNil(try checkIn.day(today).urine)
    }

    func testDarkUrineTwoDaysInARow() throws {
        try checkIn.setUrine(.dark, on: date("2026-11-18"))
        XCTAssertFalse(try todayRules().contains { $0.ruleID == "urine-dark" })

        try checkIn.setUrine(.dark, on: date("2026-11-17"))
        let item = try XCTUnwrap(try todayRules().first { $0.ruleID == "urine-dark" })
        XCTAssertEqual(item.severity, .improve)
        XCTAssertTrue(item.detail.contains("30-40 mL"))
    }

    func testClearUrineThreeDaysInARow() throws {
        for day in ["2026-11-16", "2026-11-17", "2026-11-18"] { try checkIn.setUrine(.clear, on: date(day)) }

        let item = try XCTUnwrap(try todayRules().first { $0.ruleID == "urine-clear" })
        XCTAssertEqual(item.severity, .tip)
    }

    func testWalksAreAWeeklyShareAndNeverAWarning() throws {
        let library = FoodLibrary(db)
        let plans = DietPlanService(db)
        try plans.addItem(foodID: try library.add(FoodDraft(name: "A")), quantity: 1, meal: "Brunch", from: date("2026-11-01"))
        try plans.addItem(foodID: try library.add(FoodDraft(name: "B")), quantity: 1, meal: "Dinner", from: date("2026-11-01"))
        for offset in 1...7 { try checkIn.setWalked(true, after: "Brunch", on: today.adding(days: -offset)) }

        XCTAssertEqual(try checkIn.walkShare(endingOn: today.adding(days: -1), days: 7) ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertFalse(try todayRules().contains { $0.ruleID.contains("walk") })
    }

    func testRecoverySignsAreFlaggedOnlyAsAPattern() throws {
        try checkIn.setSigns([.tiredness, .poorSleep, .lowMood, .lingeringSoreness], weekOf: date("2026-11-17"))
        XCTAssertFalse(try todayRules().contains { $0.ruleID == "under-recovered" })

        try checkIn.setSigns([.tiredness, .poorSleep, .worsePerformance], weekOf: date("2026-11-10"))
        let item = try XCTUnwrap(try todayRules().first { $0.ruleID == "under-recovered" })
        XCTAssertTrue(item.detail.contains("sleep 7-9 h"))
        XCTAssertEqual(try checkIn.signs(weekOf: date("2026-11-19")).count, 4, "any day of the week finds the week")
    }
}
