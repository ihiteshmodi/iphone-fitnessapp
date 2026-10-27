import XCTest
@testable import FitnessCore

final class MeasurementProgressTests: XCTestCase {
    private var db: Database!
    private var service: MeasurementService!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        service = MeasurementService(db, clock: FixedClock(date("2026-10-25")))
    }

    private func progress(for site: String) throws -> MeasurementProgress {
        try XCTUnwrap(try service.progress().first { $0.site == site }, "no progress for \(site)")
    }

    func testGrowthGoalShowsInchesLeftToGain() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Left Calf", inches: 14.00)
        try db.addTarget(site: "Left Calf", inches: 15.31)

        let calf = try progress(for: "Left Calf")

        XCTAssertEqual(calf.status, .toGain(1.31))
        XCTAssertEqual(calf.current, 14.00)
        XCTAssertEqual(calf.target, 15.31)
    }

    func testShrinkGoalShowsInchesLeftToLoseNotANegativeGain() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Waist", inches: 30.20)
        try db.addTarget(site: "Waist", inches: 28.00, direction: "reduce")

        XCTAssertEqual(try progress(for: "Waist").status, .toLose(2.20))
    }

    func testAGrowSiteAboveItsTargetIsAheadNotToLose() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Shoulders", inches: 46.0)
        try db.addTarget(site: "Shoulders", inches: 45.3)

        let shoulders = try progress(for: "Shoulders")

        XCTAssertEqual(shoulders.status, .ahead(0.70))
        XCTAssertEqual(shoulders.direction, .grow)
        XCTAssertEqual(shoulders.fraction, 1)
    }

    func testAReduceSiteBelowItsTargetIsAhead() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Waist", inches: 27.0)
        try db.addTarget(site: "Waist", inches: 28.0, direction: "reduce")

        XCTAssertEqual(try progress(for: "Waist").status, .ahead(1.00))
        XCTAssertEqual(try progress(for: "Waist").fraction, 1)
    }

    func testStatusFollowsTheDirectionOfTheGoal() {
        let examples: [(direction: MeasurementDirection, current: Double, target: Double, status: MeasurementStatus)] = [
            (.grow, 14.0, 15.31, .toGain(1.31)),
            (.grow, 46.0, 45.3, .ahead(0.70)),
            (.grow, 45.3, 45.3, .atTarget),
            (.reduce, 30.2, 28.0, .toLose(2.20)),
            (.reduce, 27.0, 28.0, .ahead(1.00)),
            (.reduce, 28.0, 28.0, .atTarget),
        ]

        for example in examples {
            XCTAssertEqual(MeasurementGoal.status(current: example.current, target: example.target, direction: example.direction), example.status,
                           "\(example.direction) \(example.current) -> \(example.target)")
        }
    }

    func testChangingTheDirectionOfASite() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Hips", inches: 38)
        try db.addTarget(site: "Hips", inches: 36)
        XCTAssertEqual(try progress(for: "Hips").status, .ahead(2.00), "grow is the default")

        try service.setDirection(site: "hips", .reduce)

        XCTAssertEqual(try progress(for: "Hips").status, .toLose(2.00))
        XCTAssertEqual(try service.detail(site: "Hips").direction, .reduce)
    }

    func testChangingTheDirectionNeedsATarget() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Hips", inches: 38)

        XCTAssertThrowsError(try service.setDirection(site: "Hips", .reduce)) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Set a target for this site first"))
        }
    }

    func testANewSiteWithATargetBelowItsFirstReadingStartsAsReduce() throws {
        try service.addSite(name: "Hips", firstReading: 38, target: 36)
        try service.addSite(name: "Left Shin", firstReading: 11, target: 11.5)

        XCTAssertEqual(try progress(for: "Hips").direction, .reduce)
        XCTAssertEqual(try progress(for: "Left Shin").direction, .grow)
    }

    func testTargetReached() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Neck", inches: 13.80)
        try db.addTarget(site: "Neck", inches: 13.80)

        XCTAssertEqual(try progress(for: "Neck").status, .atTarget)
    }

    func testDifferencesUnderHalfAHundredthCountAsAtTarget() {
        XCTAssertEqual(MeasurementGoal.status(current: 13.804, target: 13.80, direction: .grow), .atTarget)
        XCTAssertEqual(MeasurementGoal.status(current: 13.796, target: 13.80, direction: .grow), .atTarget)
        XCTAssertEqual(MeasurementGoal.status(current: 13.79, target: 13.80, direction: .grow), .toGain(0.01))
        XCTAssertEqual(MeasurementGoal.status(current: 13.81, target: 13.80, direction: .reduce), .toLose(0.01))
    }

    func testOnlyTheNewestReadingPerSiteCounts() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Chest", inches: 39.8)
        try db.addMeasurement(on: "2026-09-01", site: "Chest", inches: 39.0)
        try db.addTarget(site: "Chest", inches: 42)

        XCTAssertEqual(try progress(for: "Chest").current, 39.8)
    }

    func testTwoReadingsOnTheSameDayUseTheLatestEntered() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Chest", inches: 39.0)
        try db.addMeasurement(on: "2026-10-01", site: "Chest", inches: 39.5)
        try db.addTarget(site: "Chest", inches: 42)

        XCTAssertEqual(try progress(for: "Chest").current, 39.5)
    }

    func testSitesAreMatchedIgnoringCase() throws {
        try db.addMeasurement(on: "2026-10-01", site: "left calf", inches: 14.0)
        try db.addTarget(site: "Left Calf", inches: 15.31)

        let calf = try progress(for: "Left Calf")

        XCTAssertEqual(calf.current, 14.0)
        XCTAssertEqual(try service.progress().count, 1)
    }

    func testASiteWithATargetButNoReading() throws {
        try db.addTarget(site: "Neck", inches: 15)

        let neck = try progress(for: "Neck")

        XCTAssertEqual(neck.status, .noReading)
        XCTAssertNil(neck.current)
        XCTAssertEqual(neck.fraction, 0)
    }

    func testSitesWithoutATargetAreNotOnTheProgressList() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Hips", inches: 38)

        XCTAssertEqual(try service.progress(), [])
        XCTAssertEqual(try service.sites(), ["Hips"])
        XCTAssertEqual(try service.detail(site: "Hips").status, .noTarget)
    }

    func testLargestRemainingDistanceComesFirstAndSitesWithoutReadingsLast() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Left Calf", inches: 14.0)
        try db.addTarget(site: "Left Calf", inches: 15.31)
        try db.addMeasurement(on: "2026-10-01", site: "Waist", inches: 30.2)
        try db.addTarget(site: "Waist", inches: 28.0, direction: "reduce")
        try db.addMeasurement(on: "2026-10-01", site: "Neck", inches: 13.8)
        try db.addTarget(site: "Neck", inches: 13.8)
        try db.addTarget(site: "Arm", inches: 16)

        XCTAssertEqual(try service.progress().map(\.site), ["Waist", "Left Calf", "Neck", "Arm"])
    }

    func testSitesAheadOfTheirTargetHaveNothingLeftSoTheyComeAfterOnesStillToDo() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Shoulders", inches: 46.0)
        try db.addTarget(site: "Shoulders", inches: 45.3)
        try db.addMeasurement(on: "2026-10-01", site: "Left Calf", inches: 15.0)
        try db.addTarget(site: "Left Calf", inches: 15.31)

        XCTAssertEqual(try service.progress().map(\.site), ["Left Calf", "Shoulders"])
    }

    func testProgressFractionForTheRing() {
        XCTAssertEqual(MeasurementGoal.fraction(current: 14, target: 16, direction: .grow), 0.875, accuracy: 1e-9)
        XCTAssertEqual(MeasurementGoal.fraction(current: 28, target: 30, direction: .grow), 28.0 / 30, accuracy: 1e-9)
        XCTAssertEqual(MeasurementGoal.fraction(current: 30.2, target: 28, direction: .reduce), 28 / 30.2, accuracy: 1e-9)
        XCTAssertEqual(MeasurementGoal.fraction(current: 13.8, target: 13.8, direction: .grow), 1)
        XCTAssertEqual(MeasurementGoal.fraction(current: nil, target: 13.8, direction: .grow), 0)
        XCTAssertEqual(MeasurementGoal.fraction(current: 14, target: nil, direction: .grow), 0)
    }

    func testChangingATargetFromTheMeasurementScreen() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Left Calf", inches: 14.00)
        try db.addTarget(site: "Left Calf", inches: 15.31)

        try service.setTarget(site: "left calf", inches: 15.5)

        XCTAssertEqual(try progress(for: "Left Calf").status, .toGain(1.50))
        XCTAssertEqual(try service.progress().count, 1)
    }

    func testSettingATargetForANewSiteStampsToday() throws {
        try service.setTarget(site: "Neck", inches: 15)

        let row = try XCTUnwrap(try db.query("SELECT inches, set_on FROM measurement_targets WHERE site = 'Neck'").first)
        XCTAssertEqual(row.double("inches"), 15)
        XCTAssertEqual(row.optionalText("set_on"), "2026-10-25")
    }

    func testAddingAReadingFromTheMeasurementScreen() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Left Calf", inches: 14.00)
        try db.addTarget(site: "Left Calf", inches: 15.31)

        try service.logReading(site: "Left Calf", inches: 14.3, on: date("2026-10-25"))

        let detail = try service.detail(site: "Left Calf")
        XCTAssertEqual(detail.current, 14.30)
        XCTAssertEqual(detail.history.map(\.inches), [14.0, 14.3])
        XCTAssertEqual(detail.history.map(\.date), [date("2026-10-01"), date("2026-10-25")])
    }

    func testHistoryIsOldestFirstWithReadingIds() throws {
        let late = try service.logReading(site: "Waist", inches: 30.0, on: "2026-10-20")
        let early = try service.logReading(site: "Waist", inches: 31.0, on: "2026-09-20")

        XCTAssertEqual(try service.detail(site: "Waist").history.map(\.id), [early, late])
    }

    func testCorrectingAWrongReading() throws {
        try db.addTarget(site: "Left Calf", inches: 15.31)
        try db.addMeasurement(on: "2026-10-01", site: "Left Calf", inches: 14.0)
        let mistake = try service.logReading(site: "Left Calf", inches: 41.0, on: "2026-10-10")

        try service.updateReading(id: mistake, inches: 14.1)

        XCTAssertEqual(try service.detail(site: "Left Calf").current, 14.1)
    }

    func testCorrectingAReadingCanAlsoMoveItsDate() throws {
        let id = try service.logReading(site: "Left Calf", inches: 14.1, on: "2026-10-10")

        try service.updateReading(id: id, inches: 14.1, on: "2026-10-11")

        XCTAssertEqual(try service.detail(site: "Left Calf").history.map(\.date), [date("2026-10-11")])
        XCTAssertThrowsError(try service.updateReading(id: id, inches: 14.1, on: "2026-10-31x")) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Date is not valid"))
        }
        XCTAssertThrowsError(try service.updateReading(id: 999, inches: 14.1)) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Entry not found"))
        }
    }

    func testDeletingAWrongReadingFallsBackToThePreviousOne() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Left Calf", inches: 14.0)
        let mistake = try service.logReading(site: "Left Calf", inches: 41.0, on: "2026-10-10")

        try service.deleteReading(id: mistake)

        XCTAssertEqual(try service.detail(site: "Left Calf").current, 14.0)
    }

    func testAddingANewSiteToTrack() throws {
        try service.addSite(name: "Left Shin", firstReading: 11.0, target: 11.5)

        let shin = try progress(for: "Left Shin")
        XCTAssertEqual(shin.status, .toGain(0.50))
        XCTAssertEqual(try service.detail(site: "Left Shin").history.map(\.date), [date("2026-10-25")])
    }

    func testAddingASiteThatIsAlreadyTrackedIsRejected() throws {
        try db.addTarget(site: "Waist", inches: 28)

        XCTAssertThrowsError(try service.addSite(name: "waist", firstReading: 30, target: 28)) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Site is already tracked"))
        }
    }

    func testRemovingASiteKeepsItsReadingsByDefault() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Waist", inches: 30)
        try db.addTarget(site: "Waist", inches: 28)

        try service.removeSite("Waist")

        XCTAssertEqual(try service.progress(), [])
        XCTAssertEqual(try service.detail(site: "Waist").history.count, 1)
    }

    func testRemovingASiteCanAlsoDeleteItsReadings() throws {
        try db.addMeasurement(on: "2026-10-01", site: "Waist", inches: 30)
        try db.addMeasurement(on: "2026-10-01", site: "Chest", inches: 40)
        try db.addTarget(site: "Waist", inches: 28)

        try service.removeSite("Waist", deleteAllReadings: true)

        XCTAssertEqual(try service.sites(), ["Chest"])
    }

    func testRejectsInvalidMeasurementsAndDates() throws {
        XCTAssertThrowsError(try service.logReading(site: "Waist", inches: 0, on: "2026-10-23")) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Measurement must be above 0"))
        }
        XCTAssertThrowsError(try service.logReading(site: "Waist", inches: 30, on: "2027-02-30")) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Date is not valid"))
        }
        XCTAssertThrowsError(try service.setTarget(site: "Waist", inches: -2)) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Measurement must be above 0"))
        }
        XCTAssertThrowsError(try service.addSite(name: "Shin", firstReading: 11, target: 0)) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Measurement must be above 0"))
        }
        XCTAssertThrowsError(try service.logReading(site: "  ", inches: 30, on: "2026-10-23")) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Site name is required"))
        }
        XCTAssertEqual(try service.sites(), [])
    }
}
