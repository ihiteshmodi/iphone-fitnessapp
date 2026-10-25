import XCTest
@testable import FitnessCore

final class ISODateTests: XCTestCase {
    func testRejectsImpossibleDates() {
        XCTAssertNil(ISODate("2027-02-30"))
        XCTAssertNil(ISODate("2026-13-01"))
        XCTAssertNil(ISODate("26-10-01"))
        XCTAssertNil(ISODate("not a date"))
    }

    func testAcceptsValidDates() {
        XCTAssertEqual(ISODate("2026-10-23")?.string, "2026-10-23")
        XCTAssertNotNil(ISODate("2028-02-29"))
    }

    func testAddingDaysCrossesMonthAndYear() {
        XCTAssertEqual(date("2026-12-30").adding(days: 3), date("2027-01-02"))
        XCTAssertEqual(date("2026-10-23").adding(days: -6), date("2026-10-17"))
    }

    func testDaysSince() {
        XCTAssertEqual(date("2026-10-23").days(since: date("2026-10-16")), 7)
    }

    func testIsoWeekday() {
        XCTAssertEqual(date("2026-10-25").weekday, 7)
        XCTAssertEqual(date("2026-10-26").weekday, 1)
    }

    func testPyRoundMatchesPythonOnTies() {
        XCTAssertEqual(pyRound(30.375), 30.38)
        XCTAssertEqual(pyRound(2.675), 2.67)
        XCTAssertEqual(pyRound(0.125), 0.12)
    }
}
