import XCTest
@testable import FitnessCore

final class EditSetsTests: XCTestCase {
    private var db: Database!
    private var log: LogSets!
    private var legExtension = 0

    override func setUpWithError() throws {
        db = try Database.inMemory()
        log = LogSets(db, clock: FixedClock(date("2026-10-25")))
        legExtension = try db.addExercise("Leg Extension", muscle: "Quads")
    }

    private func stored(on day: String) throws -> [LoggedSet] { try log.sets(on: date(day)) }

    // MARK: Logging on another day

    func testKnowsASetCanBeLoggedForYesterday() throws {
        try log.logSet(.existing(id: legExtension), weightKg: 55, reps: 10, on: "2026-10-24")

        XCTAssertEqual(try stored(on: "2026-10-24").map(\.weightKg), [55])
        XCTAssertEqual(try stored(on: "2026-10-25"), [])
    }

    func testKnowsASetCanBeLoggedForToday() throws {
        try log.logSet(.existing(id: legExtension), weightKg: 55, reps: 10, on: "2026-10-25")

        XCTAssertEqual(try stored(on: "2026-10-25").count, 1)
    }

    func testRefusesASetDatedInTheFutureAndStoresNothing() throws {
        XCTAssertThrowsError(try log.logSet(.existing(id: legExtension), weightKg: 55, reps: 10, on: "2026-10-26")) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Pick today or an earlier date"))
        }
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM set_logs").first?.int("n"), 0)
    }

    // MARK: Correcting a set

    func testCorrectsASetInPlace() throws {
        let id = try db.addSet(exercise: legExtension, on: "2026-10-24", weight: 55, reps: 10)

        try log.updateSet(id: id, weightKg: 52.5, reps: 12, on: date("2026-10-24"))

        let sets = try stored(on: "2026-10-24")
        XCTAssertEqual(sets.map(\.id), [id])
        XCTAssertEqual(sets.map(\.weightKg), [52.5])
        XCTAssertEqual(sets.map(\.reps), [12])
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM set_logs").first?.int("n"), 1)
    }

    func testMovesASetToTheDayItReallyHappened() throws {
        let id = try db.addSet(exercise: legExtension, on: "2026-10-25", weight: 55, reps: 10)

        try log.updateSet(id: id, weightKg: 55, reps: 10, on: date("2026-10-24"))

        XCTAssertEqual(try stored(on: "2026-10-25"), [])
        XCTAssertEqual(try stored(on: "2026-10-24").map(\.id), [id])
    }

    func testKeepsTheDeloadFlagOfACorrectedSet() throws {
        let id = try db.addSet(exercise: legExtension, on: "2026-10-24", weight: 55, reps: 10, deload: true)

        try log.updateSet(id: id, weightKg: 50, reps: 10, on: date("2026-10-24"))

        XCTAssertEqual(try db.query("SELECT is_deload FROM set_logs WHERE id = ?", [.int(Int64(id))]).first?.int("is_deload"), 1)
    }

    func testRefusesInvalidCorrectionsAndLeavesTheSetAlone() throws {
        let id = try db.addSet(exercise: legExtension, on: "2026-10-24", weight: 55, reps: 10)
        let examples: [(weight: Double, reps: Int, day: String, message: String)] = [
            (-5, 10, "2026-10-24", "Weight cannot be negative"),
            (55, 0, "2026-10-24", "Reps must be at least 1"),
            (55, 10, "2026-10-26", "Pick today or an earlier date"),
        ]

        for example in examples {
            XCTAssertThrowsError(try log.updateSet(id: id, weightKg: example.weight, reps: example.reps, on: date(example.day)),
                                 example.message) { error in
                XCTAssertEqual(error as? ValidationError, ValidationError(example.message))
            }
        }
        let unchanged = try XCTUnwrap(try stored(on: "2026-10-24").first)
        XCTAssertEqual(unchanged.weightKg, 55)
        XCTAssertEqual(unchanged.reps, 10)
    }

    func testRefusesToCorrectASetThatDoesNotExist() throws {
        XCTAssertThrowsError(try log.updateSet(id: 999, weightKg: 55, reps: 10, on: date("2026-10-24"))) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Set not found"))
        }
    }

    // MARK: Earlier sessions

    func testListsEarlierSessionsOfOneExerciseNewestFirstLeavingOutTheGivenDay() throws {
        let other = try db.addExercise("Leg Curl", muscle: "Hamstrings")
        try db.addSet(exercise: legExtension, on: "2026-10-18", weight: 50, reps: 10)
        try db.addSet(exercise: legExtension, on: "2026-10-21", weight: 52.5, reps: 10)
        try db.addSet(exercise: legExtension, on: "2026-10-21", weight: 52.5, reps: 9)
        try db.addSet(exercise: legExtension, on: "2026-10-24", weight: 55, reps: 10)
        try db.addSet(exercise: legExtension, on: "2026-10-25", weight: 55, reps: 11)
        try db.addSet(exercise: other, on: "2026-10-24", weight: 30, reps: 12)

        let sessions = try log.sessions(exerciseId: legExtension, excluding: date("2026-10-25"))

        XCTAssertEqual(sessions.map(\.date.string), ["2026-10-24", "2026-10-21", "2026-10-18"])
        XCTAssertEqual(sessions[1].sets.map(\.reps), [10, 9])
        XCTAssertEqual(sessions.flatMap(\.sets).map(\.exerciseId), Array(repeating: legExtension, count: 4))
    }

    func testLimitsEarlierSessionsToTheMostRecent() throws {
        for day in ["2026-10-18", "2026-10-21", "2026-10-24"] {
            try db.addSet(exercise: legExtension, on: day, weight: 50, reps: 10)
        }

        let sessions = try log.sessions(exerciseId: legExtension, excluding: date("2026-10-25"), limit: 2)

        XCTAssertEqual(sessions.map(\.date.string), ["2026-10-24", "2026-10-21"])
    }
}
