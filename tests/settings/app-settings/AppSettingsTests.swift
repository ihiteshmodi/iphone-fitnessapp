import XCTest
@testable import FitnessCore

final class AppSettingsTests: XCTestCase {
    private var db: Database!
    private var settings: SettingsRepository!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        settings = SettingsRepository(db)
    }

    func testDefaultsMatchTheNotebook() throws {
        let loaded = try settings.load()
        XCTAssertEqual(loaded.historyStartDate, date("2026-08-31"))
        XCTAssertEqual(loaded.deload, DeloadSettings(enabled: false, weightMultiplier: 1, repsMultiplier: 0.75))
        XCTAssertEqual(loaded.dayLabelMode, .number)
        XCTAssertEqual(loaded.proteinGramsPerLb, 1.2)
        XCTAssertEqual(loaded.fatPercent, 25)
    }

    func testChangingDeloadDoesNotChangeHistoryStart() throws {
        try settings.setDeloadRepsMultiplier(0.6)
        try settings.setDeloadEnabled(true)
        let loaded = try settings.load()
        XCTAssertEqual(loaded.deload.repsMultiplier, 0.6)
        XCTAssertTrue(loaded.deload.enabled)
        XCTAssertEqual(loaded.historyStartDate, date("2026-08-31"))
    }

    func testChangingHistoryStartDoesNotChangeDeload() throws {
        try settings.setHistoryStartDate("2026-06-01")
        let loaded = try settings.load()
        XCTAssertEqual(loaded.historyStartDate, date("2026-06-01"))
        XCTAssertEqual(loaded.deload, DeloadSettings(enabled: false, weightMultiplier: 1, repsMultiplier: 0.75))
    }

    func testRejectsInvalidHistoryStart() {
        XCTAssertThrowsError(try settings.setHistoryStartDate("2027-02-30")) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Date is not valid"))
        }
    }

    func testRejectsNonPositiveMultipliers() {
        XCTAssertThrowsError(try settings.setDeloadRepsMultiplier(0)) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Multiplier must be greater than 0"))
        }
        XCTAssertThrowsError(try settings.setDeloadWeightMultiplier(-1))
    }

    func testFatShareMustLeaveRoomForCarbs() {
        XCTAssertThrowsError(try settings.setFatPercent(95)) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Fat share must be between 10% and 60%"))
        }
        XCTAssertNoThrow(try settings.setFatPercent(30))
    }

    func testProteinRuleMustBePositive() {
        XCTAssertThrowsError(try settings.setProteinGramsPerLb(0))
        XCTAssertNoThrow(try settings.setProteinGramsPerLb(1.0))
    }

    func testDayLabelModeRoundTrips() throws {
        try settings.setDayLabelMode(.weekday)
        XCTAssertEqual(try settings.load().dayLabelMode, .weekday)
    }

    func testIgnoreDeloadSessionsDefaultsToOnAndRoundTrips() throws {
        XCTAssertTrue(try settings.load().ignoreDeloadSessions)
        try settings.setIgnoreDeloadSessions(false)
        XCTAssertFalse(try settings.load().ignoreDeloadSessions)
    }
}
