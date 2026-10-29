import XCTest
@testable import FitnessCore

final class CyclePresentationTests: XCTestCase {
    private let twoOnOneOff = try! CycleRule.weeks(on: 2, off: 1, firstMonday: date("2026-10-26"))

    func testACycleIsDescribedInPlainWords() throws {
        let examples: [(CycleRule, String)] = [
            (.daily, "Every day"),
            (twoOnOneOff, "2 weeks on · 1 week off"),
            (try .weeks(on: 1, off: 1, firstMonday: date("2026-10-26")), "1 week on · 1 week off"),
            (try .days(on: 5, off: 2, start: date("2026-10-26")), "5 days on · 2 days off"),
            (try .days(on: 1, off: 1, start: date("2026-10-26")), "Every other day"),
            (.weekdays(try Weekdays([.monday, .wednesday, .friday])), "Mon, Wed, Fri"),
            (.weekdays(.workdays), "Weekdays"),
            (.weekdays(.weekend), "Weekends"),
            (.training, "Training days"),
        ]
        for (rule, text) in examples {
            XCTAssertEqual(CyclePresentation.summary(rule), text)
        }
    }

    func testWhereTheItemIsTodayIsSaidInWords() {
        XCTAssertEqual(CyclePresentation.status(twoOnOneOff.state(on: date("2026-10-29"), trainingWeekdays: [])), "Day 4 of 14 · off from 9 Nov")
        XCTAssertEqual(CyclePresentation.status(twoOnOneOff.state(on: date("2026-11-12"), trainingWeekdays: [])), "Off · back on 16 Nov")
        XCTAssertEqual(CyclePresentation.status(CycleRule.daily.state(on: date("2026-10-29"), trainingWeekdays: [])), "On")
        let weekend = CycleRule.weekdays(.weekend).state(on: date("2026-10-31"), trainingWeekdays: [])
        XCTAssertEqual(CyclePresentation.status(weekend), "On · off from 2 Nov")
    }

    func testACalendarStripStartsOnMondaysAndMarksToday() {
        let grid = CyclePresentation.grid(rule: twoOnOneOff, weeks: 4, weekOf: date("2026-10-29"), today: date("2026-10-29"), trainingWeekdays: [])

        XCTAssertEqual(grid.count, 4)
        XCTAssertTrue(grid.allSatisfy { $0.count == 7 })
        XCTAssertEqual(grid[0][0].date, date("2026-10-26"))
        XCTAssertEqual(grid[0][0].date.weekday, 1)
        XCTAssertTrue(grid[2].allSatisfy { !$0.isOn }, "9-15 Nov is the off week")
        XCTAssertEqual(grid.flatMap { $0 }.filter(\.isToday).map(\.date), [date("2026-10-29")])
        XCTAssertTrue(grid[3].allSatisfy(\.isOn))
    }

    func testAShortDateIsDayAndMonth() {
        XCTAssertEqual(date("2026-11-09").shortLabel, "9 Nov")
        XCTAssertEqual(date("2026-01-31").shortLabel, "31 Jan")
    }
}

final class CycleDraftTests: XCTestCase {
    func testTheWeeksCycleStartsOnTheMondayOfThePickedDate() throws {
        var draft = CycleDraft(today: date("2026-10-28"))
        draft.mode = .weeks
        draft.weeksOn = 2
        draft.weeksOff = 1
        draft.start = date("2026-10-28")

        XCTAssertEqual(try draft.rule(), try CycleRule.weeks(on: 2, off: 1, firstMonday: date("2026-10-26")))
        XCTAssertEqual(draft.firstMonday, date("2026-10-26"))
    }

    func testAPresetFillsInTheWeeksOnAndOff() {
        var draft = CycleDraft(today: date("2026-10-26"))

        draft.applyPreset(on: 4, off: 2)

        XCTAssertEqual(draft.mode, .weeks)
        XCTAssertEqual([draft.weeksOn, draft.weeksOff], [4, 2])
        XCTAssertTrue(draft.matchesPreset(on: 4, off: 2))
        XCTAssertFalse(draft.matchesPreset(on: 2, off: 1))
    }

    func testEachModeBuildsItsRule() throws {
        var draft = CycleDraft(today: date("2026-10-26"))
        XCTAssertEqual(try draft.rule(), .daily)

        draft.mode = .days
        draft.daysOn = 5
        draft.daysOff = 2
        draft.start = date("2026-10-27")
        XCTAssertEqual(try draft.rule(), try CycleRule.days(on: 5, off: 2, start: date("2026-10-27")))

        draft.mode = .weekdays
        draft.weekdays = [.tuesday, .sunday]
        XCTAssertEqual(try draft.rule(), .weekdays(try Weekdays([.tuesday, .sunday])))

        draft.mode = .training
        XCTAssertEqual(try draft.rule(), .training)
    }

    func testChoosingNoWeekdayIsRejected() {
        var draft = CycleDraft(today: date("2026-10-26"))
        draft.mode = .weekdays
        draft.weekdays = []

        XCTAssertThrowsError(try draft.rule()) { XCTAssertEqual($0 as? ValidationError, ValidationError("Choose at least one weekday")) }
    }

    func testTheDraftOfAnExistingRuleGivesBackTheSameRule() throws {
        let rules: [CycleRule] = [.daily, .training, .weekdays(.weekend),
                                  try .weeks(on: 3, off: 1, firstMonday: date("2026-10-26")),
                                  try .days(on: 5, off: 2, start: date("2026-10-28"))]
        for rule in rules {
            XCTAssertEqual(try CycleDraft(rule: rule, today: date("2026-11-03")).rule(), rule)
        }
    }

    func testAQuickPatternChoosesTheWeekdays() {
        var draft = CycleDraft(today: date("2026-10-26"))

        draft.selectWeekdays(.workdays)
        XCTAssertEqual(draft.mode, .weekdays)
        XCTAssertEqual(draft.weekdays, [.monday, .tuesday, .wednesday, .thursday, .friday])

        draft.selectEveryOtherDay()
        XCTAssertEqual(draft.mode, .days)
        XCTAssertEqual([draft.daysOn, draft.daysOff], [1, 1])
    }
}
