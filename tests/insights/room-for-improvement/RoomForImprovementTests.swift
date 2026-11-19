import XCTest
@testable import FitnessCore

/// Daily rule stub: fires on the days listed, has no data on others listed.
private struct TransFatRule: DailyRule {
    let id = "trans-fat"
    let title = "Trans fat"
    let checksToday = true
    var fired: Set<String> = []
    var noData: Set<String> = []

    func evaluate(on day: ISODate, db: Database) throws -> RuleOutcome {
        if noData.contains(day.string) { return .noData }
        guard fired.contains(day.string) else { return .ok }
        return .fired(Insight(ruleID: id, kind: .today, severity: .fix, title: title, detail: "1.4 g on \(day)", why: "Keep trans fat near zero.", day: day))
    }
}

private struct TwoMealsRule: SetupRule {
    let id = "protein-meals"
    func evaluate(on day: ISODate, db: Database) throws -> [Insight] {
        [Insight(ruleID: id, kind: .setup, severity: .improve, title: "Two protein meals", detail: "Aim for 3-4", why: "Spread protein.")]
    }
}

final class RoomForImprovementTests: XCTestCase {
    private var db: Database!
    private let today = date("2026-11-19")

    override func setUpWithError() throws { db = try Database.inMemory() }

    private func service(_ rule: TransFatRule) -> InsightService {
        InsightService(db, daily: [rule], setup: [TwoMealsRule()])
    }

    func testTodayListsWhatFiredYesterdayAndTodayAndTheBadgeCountsSetupToo() throws {
        let rooms = service(TransFatRule(fired: ["2026-11-18"]))

        XCTAssertEqual(try rooms.today(on: today).map(\.day), [date("2026-11-18")])
        XCTAssertEqual(try rooms.badgeCount(on: today), 2)
    }

    func testDismissingHidesFromTodayButTrendsStillCount() throws {
        let rooms = service(TransFatRule(fired: ["2026-11-18"]))
        let item = try XCTUnwrap(try rooms.today(on: today).first)

        try rooms.dismiss(item)

        XCTAssertEqual(try rooms.today(on: today), [])
        XCTAssertEqual(try rooms.trends(endingOn: today, days: 7).first?.firedCount, 1)
    }

    func testTrendsMarkEachDayFiredFineOrWithoutData() throws {
        let rooms = service(TransFatRule(fired: ["2026-11-13", "2026-11-18"], noData: ["2026-11-15"]))

        let row = try XCTUnwrap(try rooms.trends(endingOn: date("2026-11-18"), days: 7).first)

        XCTAssertEqual(row.marks, [.ok, .fired, .ok, .noData, .ok, .ok, .fired])
        XCTAssertEqual(row.firedCount, 2)
        XCTAssertEqual(row.daysWithData, 6)
    }

    func testAcceptingASetupItemArchivesItUntilRestored() throws {
        let rooms = service(TransFatRule())
        let item = try XCTUnwrap(try rooms.setup(on: today).first)

        try rooms.accept(item, note: "I know")

        XCTAssertEqual(try rooms.setup(on: today), [])
        XCTAssertEqual(try rooms.archived(), [ArchivedRule(ruleID: "protein-meals", title: "Two protein meals", status: .accepted, note: "I know")])
        try rooms.restore("protein-meals")
        XCTAssertEqual(try rooms.setup(on: today).count, 1)
    }

    func testNotApplicableStopsTheRule() throws {
        let rooms = service(TransFatRule(fired: ["2026-11-18"]))

        try rooms.markNotApplicable("trans-fat", title: "Trans fat")

        XCTAssertEqual(try rooms.today(on: today), [])
        XCTAssertEqual(try rooms.trends(endingOn: today, days: 7), [])
        XCTAssertEqual(try rooms.archived().map(\.status), [.notApplicable])
    }
}
