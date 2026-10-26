import XCTest
@testable import FitnessCore

final class EditPastDataTests: XCTestCase {
    private var db: Database!

    override func setUpWithError() throws {
        db = try Database.inMemory()
    }

    func testListsEverythingLoggedOnOneDayAndNothingFromOtherDays() throws {
        let legExtension = try db.addExercise("Leg Extension", muscle: "Quads")
        let legCurl = try db.addExercise("Leg Curl", muscle: "Hamstrings")
        try db.addSet(exercise: legExtension, on: "2026-10-10", weight: 55, reps: 10)
        try db.addSet(exercise: legCurl, on: "2026-10-10", weight: 40, reps: 12)
        try db.addSet(exercise: legCurl, on: "2026-10-11", weight: 40, reps: 12)
        try db.addBodyWeight(on: "2026-10-10", kg: 82.3)
        try db.addBodyWeight(on: "2026-10-11", kg: 82.0)
        try db.addMeasurement(on: "2026-10-10", site: "Waist", inches: 30.2)
        try db.addMeasurement(on: "2026-10-11", site: "Waist", inches: 30.0)
        let day = date("2026-10-10")

        XCTAssertEqual(try LogSets(db).sets(on: day).map(\.exerciseName), ["Leg Extension", "Leg Curl"])
        XCTAssertEqual(try LogBodyMetrics(db).weights(on: day).map(\.kg), [82.3])
        let readings = try MeasurementService(db).readings(on: day)
        XCTAssertEqual(readings.map(\.site), ["Waist"])
        XCTAssertEqual(readings.map(\.reading.inches), [30.2])
    }

    func testAnEmptyDayHasNothingLogged() throws {
        let day = date("2026-10-12")

        XCTAssertEqual(try LogSets(db).sets(on: day), [])
        XCTAssertEqual(try LogBodyMetrics(db).weights(on: day), [])
        XCTAssertEqual(try MeasurementService(db).readings(on: day), [])
    }

    func testTwoWeighInsOnTheSameDayAreBothListedInTheOrderTheyWereLogged() throws {
        try db.addBodyWeight(on: "2026-10-10", kg: 82.3)
        try db.addBodyWeight(on: "2026-10-10", kg: 82.1)

        XCTAssertEqual(try LogBodyMetrics(db).weights(on: date("2026-10-10")).map(\.kg), [82.3, 82.1])
    }
}
