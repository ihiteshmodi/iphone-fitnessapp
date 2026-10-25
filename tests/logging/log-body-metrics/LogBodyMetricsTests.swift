import XCTest
@testable import FitnessCore

final class LogBodyMetricsTests: XCTestCase {
    private var db: Database!
    private var log: LogBodyMetrics!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        log = LogBodyMetrics(db)
    }

    func testLogsBodyWeightAndTheCalorieTargetSeesIt() throws {
        try log.logWeight(kg: 64.0, on: "2026-10-14")
        try log.logWeight(kg: 63.9, on: "2026-10-23")

        let stored = try XCTUnwrap(try log.recentWeights().first)
        XCTAssertEqual(stored.kg, 63.9)
        XCTAssertEqual(stored.date, date("2026-10-23"))
        let averages = try CalorieService(db).weeklyAverages()
        XCTAssertEqual(averages.latestWeighIn, date("2026-10-23"))
        XCTAssertEqual(averages.currentAverageKg, 63.9, accuracy: 1e-9)
    }

    func testLogsAMeasurementForABodySite() throws {
        try MeasurementService(db).logReading(site: "Waist", inches: 30.2, on: "2026-10-23")

        let detail = try MeasurementService(db).detail(site: "Waist")
        XCTAssertEqual(detail.current, 30.2)
        XCTAssertEqual(detail.history.map(\.date), [date("2026-10-23")])
    }

    func testSettingATargetMeasuresProgressAgainstIt() throws {
        let measurements = MeasurementService(db)
        try measurements.logReading(site: "Left Calf", inches: 14.0, on: "2026-10-23")

        try measurements.setTarget(site: "Left Calf", inches: 15.31)

        XCTAssertEqual(try measurements.detail(site: "Left Calf").target, 15.31)
        XCTAssertEqual(try measurements.progress().first?.target, 15.31)
    }

    func testRejectsInvalidEntries() throws {
        XCTAssertThrowsError(try log.logWeight(kg: 0, on: "2026-10-23")) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Body weight must be above 0"))
        }
        XCTAssertThrowsError(try MeasurementService(db).logReading(site: "Waist", inches: -1, on: "2026-10-23")) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Measurement must be above 0"))
        }
        XCTAssertThrowsError(try log.logWeight(kg: 63.9, on: "2027-02-30")) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Date is not valid"))
        }
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM body_weights").first?.int("n"), 0)
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM body_measurements").first?.int("n"), 0)
    }

    func testRecentWeightsAreNewestFirstAndLimited() throws {
        try log.logWeight(kg: 64.0, on: "2026-10-21")
        try log.logWeight(kg: 63.8, on: "2026-10-23")
        try log.logWeight(kg: 63.9, on: "2026-10-22")

        XCTAssertEqual(try log.recentWeights(limit: 2).map(\.kg), [63.8, 63.9])
    }

    func testUpdatingAMissingEntryIsRejected() throws {
        XCTAssertThrowsError(try log.updateWeight(id: 42, kg: 70)) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Entry not found"))
        }
    }
}
