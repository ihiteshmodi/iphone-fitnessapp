import XCTest
@testable import FitnessCore

final class MeasurementToleranceTests: XCTestCase {
    private func attention(_ direction: MeasurementDirection, current: Double, target: Double, tolerance: Double = 3) -> MeasurementAttention? {
        MeasurementGoal.attention(current: current, target: target, direction: direction, tolerancePercent: tolerance)
    }

    func testKnowsThePercentFromTheTargetSignedByWhichSideOfTheTargetTheSiteIsOn() {
        let examples: [(current: Double, target: Double, percent: Double)] = [
            (14.0, 15.31, -8.6), (15.0, 15.31, -2.0), (40, 45, -11.1), (46.0, 45.3, 1.5), (30.2, 28, 7.9), (27, 28, -3.6), (28, 28, 0),
        ]

        for example in examples {
            XCTAssertEqual(MeasurementGoal.percentFromTarget(current: example.current, target: example.target), example.percent,
                           "\(example.current) against \(example.target)")
        }
        XCTAssertNil(MeasurementGoal.percentFromTarget(current: nil, target: 28))
        XCTAssertNil(MeasurementGoal.percentFromTarget(current: 28, target: nil))
    }

    func testColoursASiteByHowFarItIsInTheWrongDirection() {
        let examples: [(direction: MeasurementDirection, current: Double, target: Double, attention: MeasurementAttention)] = [
            (.grow, 14.0, 15.31, .watch),
            (.grow, 15.0, 15.31, .onTrack),
            (.grow, 40, 45, .off),
            (.grow, 46.0, 45.3, .onTrack),
            (.grow, 52.0, 45.3, .onTrack),
            (.reduce, 30.2, 28, .watch),
            (.reduce, 28.5, 28, .onTrack),
            (.reduce, 31.5, 28, .off),
            (.reduce, 27, 28, .onTrack),
        ]

        for example in examples {
            XCTAssertEqual(attention(example.direction, current: example.current, target: example.target), example.attention,
                           "\(example.direction) \(example.current) against \(example.target)")
        }
    }

    func testTheEdgesOfTheBands() {
        let examples: [(current: Double, attention: MeasurementAttention)] = [(97, .onTrack), (96.9, .watch), (90, .watch), (89.9, .off)]

        for example in examples {
            XCTAssertEqual(attention(.grow, current: example.current, target: 100), example.attention, "current \(example.current)")
        }
    }

    func testAWiderToleranceTurnsAmberIntoGreen() {
        XCTAssertEqual(attention(.grow, current: 14.8, target: 15.31, tolerance: 3), .watch)
        XCTAssertEqual(attention(.grow, current: 14.8, target: 15.31, tolerance: 5), .onTrack)
    }

    func testAToleranceOfZeroFlagsEveryMiss() {
        XCTAssertEqual(attention(.grow, current: 15.30, target: 15.31, tolerance: 0), .watch)
        XCTAssertEqual(attention(.grow, current: 15.31, target: 15.31, tolerance: 0), .onTrack)
    }

    func testNoReadingOrNoTargetMeansNoColour() {
        XCTAssertNil(MeasurementGoal.attention(current: nil, target: 15, direction: .grow, tolerancePercent: 3))
        XCTAssertNil(MeasurementGoal.attention(current: 15, target: nil, direction: .grow, tolerancePercent: 3))
    }

    // MARK: Service and setting

    func testProgressCarriesThePercentAndColourUsingTheSavedTolerance() throws {
        let db = try Database.inMemory()
        let service = MeasurementService(db, clock: FixedClock(date("2026-10-25")))
        try db.addMeasurement(on: "2026-10-01", site: "Left Calf", inches: 14.8)
        try db.addTarget(site: "Left Calf", inches: 15.31)
        try db.addTarget(site: "Neck", inches: 14)

        XCTAssertEqual(try service.progress().first { $0.site == "Left Calf" }?.attention, .watch)
        XCTAssertEqual(try service.progress().first { $0.site == "Left Calf" }?.percentFromTarget, -3.3)

        try SettingsRepository(db).setMeasurementTolerancePercent(5)

        XCTAssertEqual(try service.progress().first { $0.site == "Left Calf" }?.attention, .onTrack)
        XCTAssertEqual(try service.detail(site: "Left Calf").attention, .onTrack)
        XCTAssertNil(try service.progress().first { $0.site == "Neck" }?.attention)
        XCTAssertNil(try service.progress().first { $0.site == "Neck" }?.percentFromTarget)
    }

    func testToleranceDefaultsTo3PercentAndIsValidated() throws {
        let db = try Database.inMemory()
        let settings = SettingsRepository(db)
        XCTAssertEqual(try settings.load().measurementTolerancePercent, 3)

        try settings.setMeasurementTolerancePercent(5)
        XCTAssertEqual(try settings.load().measurementTolerancePercent, 5)
        try settings.setMeasurementTolerancePercent(0)
        XCTAssertEqual(try settings.load().measurementTolerancePercent, 0)

        for invalid in [-1.0, 60.0] {
            XCTAssertThrowsError(try settings.setMeasurementTolerancePercent(invalid)) { error in
                XCTAssertEqual(error as? ValidationError, ValidationError("Tolerance must be between 0% and 50%"))
            }
        }
        XCTAssertEqual(try settings.load().measurementTolerancePercent, 0, "a rejected value changes nothing")
    }

    func testAnOldDatabaseWithoutTheSettingBehavesLikeTheDefault() throws {
        let db = try Database.inMemory()
        try db.execute("DELETE FROM settings WHERE key = 'measurement_tolerance_percent'")

        XCTAssertEqual(try SettingsRepository(db).load().measurementTolerancePercent, 3)
    }
}
