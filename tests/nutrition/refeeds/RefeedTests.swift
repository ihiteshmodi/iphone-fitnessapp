import XCTest
@testable import FitnessCore

final class RefeedTests: XCTestCase {
    private var db: Database!
    private var refeeds: RefeedService!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        refeeds = RefeedService(db)
        try CalorieService(db).setDefault(calories: 2400, multiplier: 0.85, from: date("2026-10-01"))
    }

    func testRefeedDaysAreChosenByWeekdayOrByDate() throws {
        try refeeds.setWeekdays([7])
        try refeeds.addDate(date("2026-11-26"))

        XCTAssertTrue(try refeeds.isRefeedDay(date("2026-11-22")))
        XCTAssertTrue(try refeeds.isRefeedDay(date("2026-11-26")))
        XCTAssertFalse(try refeeds.isRefeedDay(date("2026-11-23")))
        XCTAssertEqual(try refeeds.weekdays(), [7])
    }

    func testOnARefeedDayTheTargetIsMaintenanceAndOnlyWhileCutting() throws {
        try refeeds.setWeekdays([7])
        XCTAssertEqual(RefeedService.target(maintenance: 2890), 2890)

        try CalorieService(db).setDefault(calories: 2900, multiplier: 1, from: date("2026-11-20"))
        XCTAssertFalse(try refeeds.isRefeedDay(date("2026-11-22")), "not cutting any more")
    }

    func testMarkingTheDay() throws {
        try refeeds.mark(.refeed, on: date("2026-11-22"))
        XCTAssertEqual(try refeeds.mark(on: date("2026-11-22")), .refeed)

        try refeeds.mark(.skipped, on: date("2026-11-22"))
        XCTAssertEqual(try refeeds.mark(on: date("2026-11-22")), .skipped)
    }

    func testADietBreakIsDueAfter6To12WeeksOfCutting() throws {
        let rule = DietBreakRule()

        let seven = try XCTUnwrap(try rule.evaluate(on: date("2026-11-19"), db: db).first)
        XCTAssertEqual(seven.severity, .tip)
        XCTAssertTrue(seven.detail.contains("1-2 weeks at maintenance"))
        XCTAssertEqual(try rule.evaluate(on: date("2026-12-24"), db: db).first?.severity, .improve)
        XCTAssertEqual(try rule.evaluate(on: date("2026-10-20"), db: db), [], "under 6 weeks")
    }

    func testTheCutRateCheckWaits3DaysAfterARefeed() throws {
        let today = date("2026-11-19")
        for offset in 0..<7 { try db.addBodyWeight(on: today.adding(days: -offset).string, kg: 66.5) }
        for offset in 7..<14 { try db.addBodyWeight(on: today.adding(days: -offset).string, kg: 66.0) }
        XCTAssertFalse(try CutBulkRateRule().evaluate(on: today, db: db).isEmpty, "gaining on a cut")

        try refeeds.mark(.refeed, on: date("2026-11-17"))

        XCTAssertEqual(try CutBulkRateRule().evaluate(on: today, db: db), [])
        XCTAssertFalse(try CutBulkRateRule().evaluate(on: date("2026-11-21"), db: db).isEmpty)
    }
}
