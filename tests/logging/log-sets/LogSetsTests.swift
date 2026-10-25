import XCTest
@testable import FitnessCore

final class LogSetsTests: XCTestCase {
    private var db: Database!
    private var log: LogSets!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        log = LogSets(db)
    }

    func testLogsAWeekOfSetsFromNotes() throws {
        let pushdown = try db.addExercise("Triceps Pushdown", muscle: "Triceps")

        try log.logSets(.existing(id: pushdown), on: "2026-10-23", sets: [
            SetEntry(weightKg: 45, reps: 10), SetEntry(weightKg: 45, reps: 9), SetEntry(weightKg: 40, reps: 12),
        ])

        let stored = try log.sets(on: date("2026-10-23"))
        XCTAssertEqual(stored.map(\.exerciseName), ["Triceps Pushdown", "Triceps Pushdown", "Triceps Pushdown"])
        XCTAssertEqual(stored.map(\.weightKg), [45, 45, 40])
        XCTAssertEqual(stored.map(\.reps), [10, 9, 12])
    }

    func testLoggingAnExerciseMissingFromTheLibraryAddsIt() throws {
        try log.logSet(.named("Cable Crunch", muscle: "Abs"), weightKg: 30, reps: 15, on: "2026-10-23")

        let exercise = try XCTUnwrap(ExerciseRepository(db).exercise(named: "Cable Crunch"))
        XCTAssertEqual(exercise.muscle, "Abs")
        XCTAssertEqual(exercise.source, "user")
        let stored = try log.sets(on: date("2026-10-23"))
        XCTAssertEqual(stored.map(\.exerciseId), [exercise.id])
        XCTAssertEqual(stored.first?.weightKg, 30)
        XCTAssertEqual(stored.first?.reps, 15)
    }

    func testLoggingByNameReusesAnExistingExerciseIgnoringCase() throws {
        let pushdown = try db.addExercise("Triceps Pushdown", muscle: "Triceps")

        try log.logSet(.named("  triceps pushdown ", muscle: "Chest"), weightKg: 45, reps: 10, on: "2026-10-23")

        XCTAssertEqual(try ExerciseRepository(db).all().count, 1)
        XCTAssertEqual(try log.sets(on: date("2026-10-23")).map(\.exerciseId), [pushdown])
        XCTAssertEqual(try ExerciseRepository(db).exercise(id: pushdown)?.muscle, "Triceps")
    }

    func testRejectsInvalidSets() throws {
        let pushdown = try db.addExercise("Triceps Pushdown", muscle: "Triceps")
        let examples: [(weight: Double, reps: Int, date: String, message: String)] = [
            (-5, 10, "2026-10-23", "Weight cannot be negative"),
            (45, 0, "2026-10-23", "Reps must be at least 1"),
            (45, 10, "2027-02-30", "Date is not valid"),
        ]

        for example in examples {
            XCTAssertThrowsError(try log.logSet(.existing(id: pushdown), weightKg: example.weight, reps: example.reps, on: example.date),
                                 example.message) { error in
                XCTAssertEqual(error as? ValidationError, ValidationError(example.message))
            }
        }
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM set_logs").first?.int("n"), 0)
    }

    func testBodyweightExercisesAcceptZeroKg() throws {
        let pushUps = try db.addExercise("Push Ups", muscle: "Chest")

        try log.logSet(.existing(id: pushUps), weightKg: 0, reps: 20, on: "2026-10-23")

        let stored = try XCTUnwrap(try log.sets(on: date("2026-10-23")).first)
        XCTAssertEqual(stored.weightKg, 0)
        XCTAssertEqual(stored.reps, 20)
    }

    func testDeletingAMistakenSetRemovesIt() throws {
        let pushdown = try db.addExercise("Triceps Pushdown", muscle: "Triceps")
        let good = try db.addSet(exercise: pushdown, on: "2026-10-23", weight: 45, reps: 10)
        let mistake = try db.addSet(exercise: pushdown, on: "2026-10-23", weight: 450, reps: 10)

        try log.deleteSet(id: mistake)

        XCTAssertEqual(try log.sets(on: date("2026-10-23")).map(\.id), [good])
        XCTAssertEqual(try db.query("SELECT MAX(weight_kg) AS heaviest FROM set_logs").first?.double("heaviest"), 45)
    }

    func testABatchWithOneInvalidSetStoresNothingAndCreatesNoExercise() throws {
        XCTAssertThrowsError(try log.logSets(.named("Cable Crunch", muscle: "Abs"), on: "2026-10-23", sets: [
            SetEntry(weightKg: 30, reps: 15), SetEntry(weightKg: 30, reps: 0),
        ])) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Reps must be at least 1"))
        }

        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM set_logs").first?.int("n"), 0)
        XCTAssertNil(try ExerciseRepository(db).exercise(named: "Cable Crunch"))
    }

    func testRejectsAnExerciseThatDoesNotExist() throws {
        XCTAssertThrowsError(try log.logSet(.existing(id: 999), weightKg: 10, reps: 5, on: "2026-10-23")) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Exercise not found"))
        }
    }

    func testRejectsAnEmptyBatchAndABlankName() throws {
        let pushdown = try db.addExercise("Triceps Pushdown", muscle: "Triceps")
        XCTAssertThrowsError(try log.logSets(.existing(id: pushdown), on: "2026-10-23", sets: [])) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Log at least one set"))
        }
        XCTAssertThrowsError(try log.logSet(.named("  ", muscle: nil), weightKg: 10, reps: 5, on: "2026-10-23")) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Name is required"))
        }
    }
}
