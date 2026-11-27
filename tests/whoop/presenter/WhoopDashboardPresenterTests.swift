import XCTest
@testable import FitnessCore

final class WhoopDashboardPresenterTests: XCTestCase {
    func testTriadOrderRecoveryLeftStrainMiddleSleepRightAndLongevityCoaching() throws {
        let fitnessDb = try Database.inMemory()
        let whoopDb = try Database(path: ":memory:")
        try WhoopSubstrateSchema.apply(to: whoopDb)

        // Seed birth_date & sex + Waist measurement (30.5 in -> 77.47 cm) in fitnessDb
        let labSettings = LabSettings(fitnessDb)
        try labSettings.setSex(.male)
        try labSettings.setBirthDate(try XCTUnwrap(ISODate("1996-05-15")))
        let bodyMetrics = LogBodyMetrics(fitnessDb)
        try bodyMetrics.logWeight(kg: 74.8, on: "2026-11-26")
        try fitnessDb.execute("INSERT INTO body_measurements (measured_on, site, inches) VALUES ('2026-11-25', 'Waist', 30.5)")

        // Seed 20 days of metric_series in whoopDb
        let store = WhoopAnalyticsStore(whoopDb)
        for d in 7...26 {
            let day = String(format: "2026-11-%02d", d)
            try store.writeMetric(date: day, key: "readiness", value: 78.0 + Double(d % 5))
            try store.writeMetric(date: day, key: "rmssd", value: 62.0 + Double(d % 6))
            try store.writeMetric(date: day, key: "ln_rmssd", value: log(62.0 + Double(d % 6)))
            try store.writeMetric(date: day, key: "rhr", value: 50.0 - Double(d % 3))
            try store.writeMetric(date: day, key: "resp_rate", value: 14.3)
            try store.writeMetric(date: day, key: "skin_temp_adc", value: 3450.0)
            try store.writeMetric(date: day, key: "strain", value: 12.6)
            try store.writeMetric(date: day, key: "trimp", value: 95.0 + Double(d))
            try store.writeMetric(date: day, key: "tst_min", value: 462.0)
            try store.writeMetric(date: day, key: "deep_min", value: 94.0)
            try store.writeMetric(date: day, key: "rem_min", value: 112.0)
            try store.writeMetric(date: day, key: "light_min", value: 256.0)
            try store.writeMetric(date: day, key: "efficiency", value: 92.0)
            try store.writeMetric(date: day, key: "awakenings", value: 1.0)
            try store.writeMetric(date: day, key: "steps", value: 8900.0)
            try store.writeMetric(date: day, key: "calories_total", value: 2640.0)
            try store.writeMetric(date: day, key: "calories", value: 860.0)
        }

        let targetDay = try XCTUnwrap(ISODate("2026-11-26"))
        let snap = try WhoopDashboardPresenter.build(whoopDb: whoopDb, fitnessDb: fitnessDb, on: targetDay)

        // Strict triad order requested by owner: Recovery (0-100%, left) · Strain (0-21, middle) · Sleep (hours/%, right)
        XCTAssertEqual(snap.triad.map(\.title), ["Recovery", "Strain", "Sleep"])
        XCTAssertTrue(snap.triad[0].ringLabel.hasSuffix("%"))
        XCTAssertEqual(snap.triad[1].ringLabel, "12.6")
        XCTAssertEqual(snap.triad[1].ringSubLabel, "of 21")
        XCTAssertEqual(snap.triad[2].ringLabel, "7h42")

        XCTAssertEqual(snap.contributors.count, 4)
        XCTAssertNotNil(snap.longevity.fitnessAge)
        XCTAssertEqual(snap.longevity.fitnessAge?.estimator, .nes)
        XCTAssertNotNil(snap.longevity.vitality)
        XCTAssertGreaterThanOrEqual(snap.coaching.ctlSeries.count, 6)
    }
}
