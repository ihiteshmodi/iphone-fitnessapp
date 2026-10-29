import XCTest
@testable import FitnessCore

final class SupplementCyclesTests: XCTestCase {
    private let twoOnOneOff = try! CycleRule.weeks(on: 2, off: 1, firstMonday: date("2026-10-26"))

    private func isOn(_ rule: CycleRule, _ day: String, training: Set<Int> = []) -> Bool {
        rule.isOn(on: date(day), trainingWeekdays: training)
    }

    func testAnItemWithNoCycleIsOnEveryDay() {
        XCTAssertTrue(isOn(.daily, "2026-10-26"))
        XCTAssertTrue(isOn(.daily, "2027-03-01"))
    }

    func testWeeksOnAndOffCountFromTheMondayTheFirstOnWeekBegins() {
        XCTAssertEqual(["2026-10-26", "2026-11-01", "2026-11-08"].map { isOn(twoOnOneOff, $0) }, [true, true, true])
        XCTAssertEqual(["2026-11-09", "2026-11-12", "2026-11-15"].map { isOn(twoOnOneOff, $0) }, [false, false, false])
        XCTAssertEqual(["2026-11-16", "2026-11-29"].map { isOn(twoOnOneOff, $0) }, [true, true])
        XCTAssertFalse(isOn(twoOnOneOff, "2026-11-30"), "the cycle repeats: 2 on, 1 off, 2 on, 1 off")
        XCTAssertTrue(isOn(twoOnOneOff, "2026-12-07"))
    }

    func testTheCycleRepeatsBackwardsBeforeItsStart() {
        XCTAssertFalse(isOn(twoOnOneOff, "2026-10-19"))
        XCTAssertFalse(isOn(twoOnOneOff, "2026-10-25"))
        XCTAssertTrue(isOn(twoOnOneOff, "2026-10-18"))
    }

    func testItKnowsTheDayOfTheCycleAndTheNextChange() {
        let on = twoOnOneOff.state(on: date("2026-10-29"), trainingWeekdays: [])
        XCTAssertEqual(on, CycleState(isOn: true, dayInPhase: 4, phaseLength: 14, nextChange: date("2026-11-09")))

        let off = twoOnOneOff.state(on: date("2026-11-12"), trainingWeekdays: [])
        XCTAssertEqual(off, CycleState(isOn: false, dayInPhase: 4, phaseLength: 7, nextChange: date("2026-11-16")))
    }

    func testDaysOnAndDaysOffCountFromAnyDate() throws {
        let rule = try CycleRule.days(on: 5, off: 2, start: date("2026-10-26"))

        XCTAssertEqual(["2026-10-26", "2026-10-30"].map { isOn(rule, $0) }, [true, true])
        XCTAssertEqual(["2026-10-31", "2026-11-01"].map { isOn(rule, $0) }, [false, false])
        XCTAssertTrue(isOn(rule, "2026-11-02"))
    }

    func testChosenWeekdays() throws {
        let rule = CycleRule.weekdays(try Weekdays([.monday, .wednesday, .friday]))

        XCTAssertEqual(["2026-10-26", "2026-10-27", "2026-10-28", "2026-10-30", "2026-10-31"].map { isOn(rule, $0) },
                       [true, false, true, true, false])
    }

    func testQuickPatterns() {
        let weekdays = CycleRule.weekdays(.workdays)
        let weekend = CycleRule.weekdays(.weekend)

        XCTAssertEqual(["2026-10-26", "2026-10-30", "2026-10-31", "2026-11-01"].map { isOn(weekdays, $0) }, [true, true, false, false])
        XCTAssertEqual(["2026-10-26", "2026-10-30", "2026-10-31", "2026-11-01"].map { isOn(weekend, $0) }, [false, false, true, true])
    }

    func testEveryOtherDayIsOneDayOnAndOneDayOff() throws {
        let rule = try CycleRule.days(on: 1, off: 1, start: date("2026-10-26"))

        XCTAssertEqual(["2026-10-26", "2026-10-27", "2026-10-28"].map { isOn(rule, $0) }, [true, false, true])
    }

    func testTrainingDaysFollowTheWeekdaysOfTheWorkoutPlan() {
        XCTAssertTrue(isOn(.training, "2026-10-26", training: [1, 3, 5]))
        XCTAssertFalse(isOn(.training, "2026-10-27", training: [1, 3, 5]))
    }

    func testTrainingDaysWithNoWorkoutWeekdaysAreOnEveryDay() {
        XCTAssertTrue(isOn(.training, "2026-10-27", training: []))
    }

    func testTheNextChangeOfWeekdaysIsTheNextDayThatDiffers() throws {
        let rule = CycleRule.weekdays(try Weekdays([.monday, .wednesday]))

        XCTAssertEqual(rule.state(on: date("2026-10-26"), trainingWeekdays: []).nextChange, date("2026-10-27"))
        XCTAssertEqual(CycleRule.daily.state(on: date("2026-10-26"), trainingWeekdays: []).nextChange, nil)
    }

    func testACycleSurvivesBeingStoredAndReadBack() throws {
        let rules: [CycleRule] = [.daily, twoOnOneOff, try .days(on: 5, off: 2, start: date("2026-10-26")),
                                  .weekdays(try Weekdays([.tuesday, .sunday])), .training]
        for rule in rules {
            XCTAssertEqual(try CycleRule(columns: rule.columns), rule)
        }
    }

    func testACycleMustBeValid() {
        XCTAssertThrowsError(try CycleRule.weeks(on: 0, off: 1, firstMonday: date("2026-10-26"))) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Days or weeks on must be at least 1"))
        }
        XCTAssertThrowsError(try CycleRule.weeks(on: 1, off: 1, firstMonday: date("2026-10-27"))) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("A weekly cycle starts on a Monday"))
        }
        XCTAssertThrowsError(try CycleRule.days(on: 1, off: 0, start: date("2026-10-26"))) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Days or weeks off must be at least 1"))
        }
        XCTAssertThrowsError(try Weekdays([])) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Choose at least one weekday"))
        }
    }
}
