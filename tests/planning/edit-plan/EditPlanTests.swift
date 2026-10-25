import XCTest
@testable import FitnessCore

/// Scenarios from edit-plan.feature.
final class EditPlanTests: XCTestCase {
    private var db: Database!
    private var editor: PlanEditor!
    private var workout: WorkoutService!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        editor = PlanEditor(db)
        workout = WorkoutService(db, clock: planningClock())
    }

    private func threeDays() throws -> [Int] {
        try (1...3).map { try db.addDay(position: $0) }
    }

    private func names(onDay day: Int) throws -> [String] {
        try workout.workout(dayId: day).exercises.map(\.name)
    }

    private func assertValidation(_ message: String, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? ValidationError, ValidationError(message), file: file, line: line)
        }
    }

    // MARK: Days

    func testAddANewTrainingDayGetsTheNextPositionAndNoWeekday() throws {
        _ = try threeDays()

        let id = try editor.addDay()

        let days = try workout.days()
        XCTAssertEqual(days.map(\.label), ["Day 1", "Day 2", "Day 3", "Day 4"])
        XCTAssertEqual(days.last?.id, id)
        XCTAssertEqual(days.last?.position, 4)
        XCTAssertNil(days.last?.weekday)
        XCTAssertEqual(days.last?.exerciseCount, 0)
    }

    func testFirstDayOfAnEmptyPlanIsDayOne() throws {
        _ = try editor.addDay()

        XCTAssertEqual(try workout.days().map(\.label), ["Day 1"])
    }

    func testDeleteADayRemovesItsEntriesButKeepsAllHistory() throws {
        let days = try threeDays()
        let day4 = try editor.addDay()
        let preacher = try db.addExercise("Preacher Curls")
        for index in 1...5 {
            let exercise = try db.addExercise("Exercise \(index)")
            try editor.addExercise(dayId: day4, exerciseId: exercise, sets: 3, minReps: 6, maxReps: 10)
            try db.addSet(exercise: exercise, on: "2026-10-01", weight: 20, reps: 10)
        }
        try db.addSet(exercise: preacher, on: "2026-10-01", weight: 20, reps: 10)
        try editor.addExercise(dayId: days[0], exerciseId: preacher, sets: 3, minReps: 6, maxReps: 10)
        let setsBefore = try db.count("set_logs")

        try editor.deleteDay(id: day4)

        XCTAssertEqual(try db.count("set_logs"), setsBefore)
        XCTAssertEqual(try workout.days().map(\.id), days)
        XCTAssertEqual(try db.count("plan_entries"), 1)
        XCTAssertEqual(try db.count("exercises"), 6)
    }

    func testDeletingAMiddleDayRenumbersTheRestSoLabelsStayContiguous() throws {
        let days = try threeDays()
        let fourth = try editor.addDay()

        try editor.deleteDay(id: days[1])

        let remaining = try workout.days()
        XCTAssertEqual(remaining.map(\.id), [days[0], days[2], fourth])
        XCTAssertEqual(remaining.map(\.label), ["Day 1", "Day 2", "Day 3"])
        XCTAssertEqual(try db.dayPositions(), [1, 2, 3])
    }

    func testDeletingAnUnknownDayIsRejected() throws {
        assertValidation("Day not found") { try editor.deleteDay(id: 42) }
    }

    func testAddingADayAfterADeletionContinuesTheNumbering() throws {
        let days = try threeDays()
        try editor.deleteDay(id: days[0])

        _ = try editor.addDay()

        XCTAssertEqual(try db.dayPositions(), [1, 2, 3])
    }

    // MARK: Build a workout

    func testAddFromTheLibraryAppendsLast() throws {
        let day = try editor.addDay()
        let crunch = try db.addExercise("Cable Crunch", muscle: "Abs")
        let curls = try db.addExercise("Preacher Curls", muscle: "Biceps")
        try editor.addExercise(dayId: day, exerciseId: curls, sets: 3, minReps: 8, maxReps: 12)

        try editor.addExercise(dayId: day, exerciseId: crunch, sets: 3, minReps: 12, maxReps: 20)

        let exercises = try workout.workout(dayId: day).exercises
        XCTAssertEqual(exercises.map(\.name), ["Preacher Curls", "Cable Crunch"])
        XCTAssertEqual(exercises.last?.sets, 3)
        XCTAssertEqual(exercises.last?.minReps, 12)
        XCTAssertEqual(exercises.last?.maxReps, 20)
        XCTAssertEqual(try db.entryPositions(day: day), [1, 2])
    }

    func testCreateANewExerciseWhileBuildingAWorkout() throws {
        let day = try editor.addDay()

        try editor.createExerciseAndAdd(dayId: day, name: "Landmine Press", muscle: "Shoulders",
                                        instructions: "Stand split stance, press up and across", sets: 3, minReps: 8, maxReps: 12)

        let library = try XCTUnwrap(try ExerciseRepository(db).exercise(named: "Landmine Press"))
        XCTAssertEqual(library.source, "user")
        XCTAssertEqual(library.muscle, "Shoulders")
        let onDay = try XCTUnwrap(try workout.workout(dayId: day).exercises.first)
        XCTAssertEqual(onDay.name, "Landmine Press")
        XCTAssertEqual(onDay.instructions, "Stand split stance, press up and across")
        XCTAssertEqual(onDay.muscle, "Shoulders")
    }

    func testCreatingAnExerciseWithAnInvalidRangeAddsNothingToTheLibrary() throws {
        let day = try editor.addDay()

        assertValidation("Min reps cannot exceed max reps") {
            try editor.createExerciseAndAdd(dayId: day, name: "Landmine Press", muscle: nil, instructions: nil, sets: 3, minReps: 12, maxReps: 8)
        }

        XCTAssertEqual(try db.count("exercises"), 0)
    }

    func testCreatingAnExerciseWithADuplicateNameIsRejectedByTheLibrary() throws {
        let day = try editor.addDay()
        try db.addExercise("Landmine Press")

        assertValidation("Exercise already exists") {
            try editor.createExerciseAndAdd(dayId: day, name: "landmine press", muscle: nil, instructions: nil, sets: 3, minReps: 8, maxReps: 12)
        }

        XCTAssertEqual(try db.count("plan_entries"), 0)
    }

    // MARK: Day names

    func testNameDaysByNumberOrByWeekday() throws {
        let days = try threeDays()
        try editor.setWeekday(dayId: days[0], weekday: 1)
        try editor.setWeekday(dayId: days[1], weekday: 3)
        try editor.setWeekday(dayId: days[2], weekday: 5)
        let modes: [(mode: DayLabelMode, labels: [String])] = [
            (.number, ["Day 1", "Day 2", "Day 3"]),
            (.weekday, ["Mon", "Wed", "Fri"]),
        ]

        for row in modes {
            try setDayLabelMode(db, row.mode)
            XCTAssertEqual(try workout.days().map(\.label), row.labels, "\(row.mode)")
            XCTAssertEqual(try workout.workout(dayId: days[0]).day.label, row.labels[0])
        }
    }

    func testAWeekdayNameNeedsAWeekdayAssigned() throws {
        _ = try threeDays()
        let fourth = try editor.addDay()
        try setDayLabelMode(db, .weekday)

        XCTAssertEqual(try workout.days().last?.label, "Day 4")
        XCTAssertEqual(try workout.workout(dayId: fourth).day.label, "Day 4")
    }

    func testEveryWeekdayHasAShortName() {
        let labels = (1...7).map { DayLabel.make(position: 1, weekday: $0, mode: .weekday) }

        XCTAssertEqual(labels, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        XCTAssertEqual(DayLabel.make(position: 2, weekday: nil, mode: .weekday), "Day 2")
        XCTAssertEqual(DayLabel.make(position: 2, weekday: 4, mode: .number), "Day 2")
    }

    func testClearingTheWeekdayFallsBackToTheNumber() throws {
        let day = try editor.addDay()
        try setDayLabelMode(db, .weekday)
        try editor.setWeekday(dayId: day, weekday: 2)
        XCTAssertEqual(try workout.days().first?.label, "Tue")

        try editor.setWeekday(dayId: day, weekday: nil)

        XCTAssertEqual(try workout.days().first?.label, "Day 1")
    }

    func testWeekdayMustBeBetweenOneAndSeven() throws {
        let day = try editor.addDay()

        for invalid in [0, 8] {
            assertValidation("Weekday must be between 1 and 7") { try editor.setWeekday(dayId: day, weekday: invalid) }
        }
    }

    func testTitleIsSeparateFromTheLabelAndBlankClearsIt() throws {
        let day = try editor.addDay()

        try editor.setTitle(dayId: day, title: "  Pull + Chest ")
        XCTAssertEqual(try workout.days().first?.title, "Pull + Chest")
        XCTAssertEqual(try workout.days().first?.label, "Day 1")
        XCTAssertEqual(try workout.workout(dayId: day).day.title, "Pull + Chest")

        try editor.setTitle(dayId: day, title: "   ")
        XCTAssertNil(try workout.days().first?.title)
    }

    // MARK: Change, reorder, remove

    func testChangeSetsAndRepRangeOfAPlannedExercise() throws {
        let day = try editor.addDay()
        let lat = try db.addExercise("Lat Pulldown")
        let entry = try editor.addExercise(dayId: day, exerciseId: lat, sets: 3, minReps: 6, maxReps: 10)

        try editor.updateEntry(entryId: entry, sets: 4, minReps: 8, maxReps: 12)

        let shown = try XCTUnwrap(try workout.workout(dayId: day).exercises.first)
        XCTAssertEqual(shown.name, "Lat Pulldown")
        XCTAssertEqual(shown.sets, 4)
        XCTAssertEqual(shown.minReps, 8)
        XCTAssertEqual(shown.maxReps, 12)
    }

    func testReorderMovesAnExerciseToTheTop() throws {
        let day = try editor.addDay()
        let lat = try db.addExercise("Lat Pulldown")
        let curls = try db.addExercise("Preacher Curls")
        try editor.addExercise(dayId: day, exerciseId: lat, sets: 3, minReps: 6, maxReps: 10)
        let curlsEntry = try editor.addExercise(dayId: day, exerciseId: curls, sets: 3, minReps: 6, maxReps: 10)

        try editor.moveEntry(entryId: curlsEntry, toPosition: 1)

        XCTAssertEqual(try names(onDay: day), ["Preacher Curls", "Lat Pulldown"])
        XCTAssertEqual(try db.entryPositions(day: day), [1, 2])
    }

    func testMoveInTheMiddleAndClampBeyondTheEnds() throws {
        let day = try editor.addDay()
        var entries: [Int] = []
        for name in ["A", "B", "C", "D"] {
            let exercise = try db.addExercise(name)
            entries.append(try editor.addExercise(dayId: day, exerciseId: exercise, sets: 3, minReps: 6, maxReps: 10))
        }

        try editor.moveEntry(entryId: entries[0], toPosition: 3)
        XCTAssertEqual(try names(onDay: day), ["B", "C", "A", "D"])

        try editor.moveEntry(entryId: entries[1], toPosition: 99)
        XCTAssertEqual(try names(onDay: day), ["C", "A", "D", "B"])

        try editor.moveEntry(entryId: entries[3], toPosition: 0)
        XCTAssertEqual(try names(onDay: day), ["D", "C", "A", "B"])
        XCTAssertEqual(try db.entryPositions(day: day), [1, 2, 3, 4])
    }

    func testMovingAnUnknownEntryIsRejected() throws {
        assertValidation("Plan entry not found") { try editor.moveEntry(entryId: 42, toPosition: 1) }
    }

    func testRemoveAnExerciseFromADayKeepsItsHistory() throws {
        let day = try editor.addDay()
        let curls = try db.addExercise("Preacher Curls")
        let lat = try db.addExercise("Lat Pulldown")
        let entry = try editor.addExercise(dayId: day, exerciseId: curls, sets: 3, minReps: 6, maxReps: 10)
        try editor.addExercise(dayId: day, exerciseId: lat, sets: 3, minReps: 6, maxReps: 10)
        try db.addSet(exercise: curls, on: "2026-10-01", weight: 20, reps: 10)

        try editor.removeEntry(entryId: entry)

        XCTAssertEqual(try names(onDay: day), ["Lat Pulldown"])
        XCTAssertEqual(try db.count("set_logs"), 1)
        XCTAssertEqual(try db.entryPositions(day: day), [1])
        XCTAssertEqual(try ExerciseDetailService(db, clock: planningClock()).detail(exerciseId: lat, dayId: day).exercise.name, "Lat Pulldown")
    }

    func testRemovedExerciseCanBeAddedBackToTheSameDay() throws {
        let day = try editor.addDay()
        let curls = try db.addExercise("Preacher Curls")
        let entry = try editor.addExercise(dayId: day, exerciseId: curls, sets: 3, minReps: 6, maxReps: 10)
        try editor.removeEntry(entryId: entry)

        try editor.addExercise(dayId: day, exerciseId: curls, sets: 3, minReps: 6, maxReps: 10)

        XCTAssertEqual(try names(onDay: day), ["Preacher Curls"])
    }

    // MARK: Validation

    func testInvalidRepRangeIsRejected() throws {
        let day = try editor.addDay()
        let lat = try db.addExercise("Lat Pulldown")
        let entry = try editor.addExercise(dayId: day, exerciseId: lat, sets: 3, minReps: 6, maxReps: 10)

        assertValidation("Min reps cannot exceed max reps") { try editor.updateEntry(entryId: entry, sets: 3, minReps: 12, maxReps: 8) }
        let other = try db.addExercise("Preacher Curls")
        assertValidation("Min reps cannot exceed max reps") { try editor.addExercise(dayId: day, exerciseId: other, sets: 3, minReps: 12, maxReps: 8) }

        let stored = try XCTUnwrap(try workout.workout(dayId: day).exercises.first)
        XCTAssertEqual(stored.minReps, 6)
        XCTAssertEqual(stored.maxReps, 10)
        XCTAssertEqual(try db.count("plan_entries"), 1)
    }

    func testTheSameExerciseCannotBeOnOneDayTwice() throws {
        let day = try editor.addDay()
        let lat = try db.addExercise("Lat Pulldown")
        try editor.addExercise(dayId: day, exerciseId: lat, sets: 3, minReps: 6, maxReps: 10)

        assertValidation("Already on this day") { try editor.addExercise(dayId: day, exerciseId: lat, sets: 3, minReps: 6, maxReps: 10) }
        XCTAssertEqual(try db.count("plan_entries"), 1)
    }

    func testTheSameExerciseCanBeOnTwoDifferentDays() throws {
        let first = try editor.addDay()
        let second = try editor.addDay()
        let lat = try db.addExercise("Lat Pulldown")

        try editor.addExercise(dayId: first, exerciseId: lat, sets: 3, minReps: 6, maxReps: 10)
        try editor.addExercise(dayId: second, exerciseId: lat, sets: 3, minReps: 6, maxReps: 10)

        XCTAssertEqual(try db.count("plan_entries"), 2)
    }

    func testSetsMustBeAtLeastOne() throws {
        let day = try editor.addDay()
        let lat = try db.addExercise("Lat Pulldown")

        assertValidation("Sets must be at least 1") { try editor.addExercise(dayId: day, exerciseId: lat, sets: 0, minReps: 6, maxReps: 10) }
        let entry = try editor.addExercise(dayId: day, exerciseId: lat, sets: 3, minReps: 6, maxReps: 10)
        assertValidation("Sets must be at least 1") { try editor.updateEntry(entryId: entry, sets: 0, minReps: 6, maxReps: 10) }
    }

    func testAddingToAnUnknownDayOrExerciseIsRejected() throws {
        let day = try editor.addDay()
        let lat = try db.addExercise("Lat Pulldown")

        assertValidation("Day not found") { try editor.addExercise(dayId: 42, exerciseId: lat, sets: 3, minReps: 6, maxReps: 10) }
        assertValidation("Exercise not found") { try editor.addExercise(dayId: day, exerciseId: 42, sets: 3, minReps: 6, maxReps: 10) }
    }

    func testNegativeMinimumRepsAreRejected() throws {
        let day = try editor.addDay()
        let lat = try db.addExercise("Lat Pulldown")

        assertValidation("Min reps cannot be negative") { try editor.addExercise(dayId: day, exerciseId: lat, sets: 3, minReps: -1, maxReps: 10) }
    }
}
