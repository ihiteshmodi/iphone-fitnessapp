import XCTest
@testable import FitnessCore

/// Pure trend rules from exercise-detail.feature (Epley estimate, 2% band, window of 5 sessions).
final class ExerciseTrendTests: XCTestCase {
    func testScenarioOutlineSeries() {
        let rows: [(series: [Double], status: ExerciseTrend.Status)] = [
            ([60, 62, 64, 66], .improving),
            ([60, 60.5, 59.8, 60.2], .flat),
            ([66, 64, 62, 60], .declining),
            ([60], .notEnoughData),
            ([], .notEnoughData),
        ]
        for row in rows {
            XCTAssertEqual(ExerciseTrend.classify(row.series).status, row.status, "series \(row.series)")
        }
    }

    func testLabelsMatchTheSpecWording() {
        XCTAssertEqual(ExerciseTrend.classify([60, 62, 64, 66]).label, "Improving")
        XCTAssertEqual(ExerciseTrend.classify([60, 60.5, 59.8, 60.2]).label, "Flat")
        XCTAssertEqual(ExerciseTrend.classify([66, 64, 62, 60]).label, "Declining")
        XCTAssertEqual(ExerciseTrend.classify([60]).label, "Not enough data")
    }

    func testPercentChangeIsNewestVersusMeanOfEarlierOnes() throws {
        let trend = ExerciseTrend.classify([60, 62, 64, 66])

        XCTAssertEqual(try XCTUnwrap(trend.percentChange), 6.5)
        XCTAssertNil(ExerciseTrend.classify([60]).percentChange)
    }

    func testOnlyTheLastFiveSessionsCount() {
        XCTAssertEqual(ExerciseTrend.classify([200, 10, 10, 10, 10, 10]).status, .flat)
        XCTAssertEqual(ExerciseTrend.classify([1, 10, 10, 10, 10, 12]).status, .improving)
    }

    func testChangeInsideTheTwoPercentBandIsFlat() {
        XCTAssertEqual(ExerciseTrend.classify([100, 102]).status, .flat)
        XCTAssertEqual(ExerciseTrend.classify([100, 98]).status, .flat)
        XCTAssertEqual(ExerciseTrend.classify([100, 102.5]).status, .improving)
        XCTAssertEqual(ExerciseTrend.classify([100, 97.5]).status, .declining)
    }

    func testTwoSessionsAreEnoughToJudge() {
        XCTAssertEqual(ExerciseTrend.classify([60, 66]).status, .improving)
    }

    func testEpleyEstimate() {
        XCTAssertEqual(SessionHistory.epleyEstimate(weightKg: 54, reps: 9), 70.2, accuracy: 0.0001)
        XCTAssertEqual(SessionHistory.epleyEstimate(weightKg: 60, reps: 0), 60, accuracy: 0.0001)
        XCTAssertEqual(SessionHistory.epleyEstimate(weightKg: 30, reps: 30), 60, accuracy: 0.0001)
    }

    func testSessionBestSetIsTheHighestEstimateNotJustTheHeaviest() {
        let light = PerformedSet(id: 1, date: date("2026-10-01"), weightKg: 50, reps: 15)
        let heavy = PerformedSet(id: 2, date: date("2026-10-01"), weightKg: 54, reps: 5)

        let sessions = SessionHistory.sessions(from: [heavy, light])

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].best, light)
        XCTAssertEqual(sessions[0].estimatedOneRepMax, 75, accuracy: 0.0001)
    }

    func testSessionsAreGroupedByDateOldestFirstWithSetsInLogOrder() {
        let sets = [
            PerformedSet(id: 3, date: date("2026-10-08"), weightKg: 50, reps: 8),
            PerformedSet(id: 1, date: date("2026-10-01"), weightKg: 50, reps: 8),
            PerformedSet(id: 2, date: date("2026-10-01"), weightKg: 50, reps: 9),
        ]

        let sessions = SessionHistory.sessions(from: sets)

        XCTAssertEqual(sessions.map(\.date), [date("2026-10-01"), date("2026-10-08")])
        XCTAssertEqual(sessions[0].sets.map(\.id), [1, 2])
    }
}
