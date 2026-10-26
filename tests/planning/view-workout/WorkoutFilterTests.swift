import XCTest
@testable import FitnessCore

/// Scenarios from view-workout.feature about the All / Remaining filter.
final class WorkoutFilterTests: XCTestCase {
    private var db: Database!
    private var dayId = 0

    override func setUpWithError() throws {
        db = try Database.inMemory()
        dayId = try db.addDay(position: 1)
    }

    private func plan(_ name: String, sets: Int, loggedToday: Int, position: Int) throws {
        let exercise = try db.addExercise(name, muscle: "Legs")
        try db.addEntry(day: dayId, exercise: exercise, position: position, sets: sets)
        for _ in 0..<loggedToday {
            try db.addSet(exercise: exercise, on: planningToday.string, weight: 50, reps: 10)
        }
    }

    private func workout() throws -> Workout { try WorkoutService(db, clock: planningClock()).workout(dayId: dayId) }

    func testAnExerciseIsDoneWhenAllItsMainSetsAreLoggedToday() throws {
        try plan("Leg Extensions", sets: 1, loggedToday: 1, position: 1)
        try plan("Seated Cable Row", sets: 2, loggedToday: 1, position: 2)

        let byName = Dictionary(uniqueKeysWithValues: try workout().exercises.map { ($0.name, $0.isDone) })

        XCTAssertEqual(byName, ["Leg Extensions": true, "Seated Cable Row": false])
    }

    func testRemainingKeepsOnlyTheUnfinishedExercisesInTheirNormalOrder() throws {
        for (index, done) in [true, false, true, false, false, true].enumerated() {
            try plan("Exercise \(index + 1)", sets: 1, loggedToday: done ? 1 : 0, position: index + 1)
        }

        let day = try workout()

        XCTAssertEqual(day.exercises(.remaining).map(\.name), ["Exercise 2", "Exercise 4", "Exercise 5"])
        XCTAssertEqual(day.exercises(.all).count, 6)
        XCTAssertEqual(day.remainingCount, 3)
    }

    func testRemainingIsEmptyWhenEverythingIsDone() throws {
        try plan("Leg Extensions", sets: 1, loggedToday: 1, position: 1)
        try plan("Lat Pulldown", sets: 1, loggedToday: 1, position: 2)

        let day = try workout()

        XCTAssertEqual(day.exercises(.remaining), [])
        XCTAssertTrue(day.isAllDone)
    }

    func testADayWithNoExercisesIsNotAllDone() throws {
        XCTAssertFalse(try workout().isAllDone)
    }
}
