import XCTest

/// Drives the Workout tab against a copy of the real database (see `UITestSeed` for why the file lives in /Users/Shared).
final class WorkoutFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Day list

    func testDay1ListsItsExercises() throws {
        let app = try launchApp()

        app.buttons["day-1"].tap()

        XCTAssertTrue(app.buttons["exercise-card-Leg Extensions"].waitForExistence(timeout: 10))
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'exercise-card-'"))
        XCTAssertEqual(cards.count, 17)
        attach(app, named: "day-list")
    }

    // MARK: Exercise detail and logging

    func testOpenExerciseAndLogPrefilledSet() throws {
        let app = try launchApp()

        app.buttons["day-3"].tap()
        let card = app.buttons["exercise-card-Chest Dips Machine"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        XCTAssertTrue(app.staticTexts["54"].waitForExistence(timeout: 10), "working weight")
        let howTo = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] 'handle inner'")).firstMatch
        XCTAssertTrue(howTo.exists, "how-to text")
        attach(app, named: "detail-top")

        let addSet = app.buttons["add-set-button"]
        for _ in 0..<6 where !addSet.isHittable { app.swipeUp() }
        attach(app, named: "detail-bottom")
        addSet.tap()

        let weight = app.textFields["weight-field"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertEqual(weight.value as? String, "54")
        XCTAssertEqual(app.textFields["reps-field"].value as? String, "8", "the middle of 6 to 10")
        attach(app, named: "add-set-sheet")
        app.buttons["save-set-button"].tap()

        let row = app.descendants(matching: .any)["today-set-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        attach(app, named: "detail-after-save")
    }

    func testArrowsChangeWeightAndRepsAndTheKeyboardStillWorks() throws {
        let app = try launchApp()
        app.buttons["day-3"].tap()
        app.buttons["exercise-card-Chest Dips Machine"].tap()
        let addSet = app.buttons["add-set-button"]
        XCTAssertTrue(addSet.waitForExistence(timeout: 10))
        for _ in 0..<6 where !addSet.isHittable { app.swipeUp() }
        addSet.tap()

        let weight = app.textFields["weight-field"]
        let reps = app.textFields["reps-field"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        app.buttons["weight-field-plus"].tap()
        XCTAssertEqual(weight.value as? String, "56.5")
        app.buttons["weight-field-minus"].tap()
        app.buttons["weight-field-minus"].tap()
        XCTAssertEqual(weight.value as? String, "51.5")
        app.buttons["reps-field-plus"].tap()
        XCTAssertEqual(reps.value as? String, "9")
        app.buttons["reps-field-minus"].tap()
        app.buttons["reps-field-minus"].tap()
        XCTAssertEqual(reps.value as? String, "7")

        reps.tap()
        reps.typeText("12")
        XCTAssertEqual(reps.value as? String, "12", "tapping selects the number, so typing replaces it")
    }

    func testRemainingHidesFinishedExercises() throws {
        let app = try launchApp()
        app.buttons["day-3"].tap()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'exercise-card-'"))
        XCTAssertTrue(app.buttons["filter-remaining"].waitForExistence(timeout: 10))
        let all = cards.count

        let card = app.buttons["exercise-card-Chest Dips Machine"]
        card.tap()
        let addSet = app.buttons["add-set-button"]
        XCTAssertTrue(addSet.waitForExistence(timeout: 10))
        for _ in 0..<6 where !addSet.isHittable { app.swipeUp() }
        // Chest Dips Machine has several main sets in the seed: log until its ring is full.
        for _ in 0..<3 {
            guard addSet.exists, addSet.isHittable else { break }
            addSet.tap()
            app.buttons["save-set-button"].tap()
            _ = app.descendants(matching: .any)["today-set-1"].waitForExistence(timeout: 5)
            for _ in 0..<6 where !addSet.isHittable { app.swipeUp() }
        }
        app.goBack()

        app.buttons["filter-remaining"].tap()
        XCTAssertFalse(app.buttons["exercise-card-Chest Dips Machine"].waitForExistence(timeout: 3), "a finished exercise is hidden")
        XCTAssertLessThan(cards.count, all)
        app.buttons["filter-all"].tap()
        XCTAssertTrue(app.buttons["exercise-card-Chest Dips Machine"].waitForExistence(timeout: 5))
    }

    func testRejectsZeroRepsWithoutSaving() throws {
        let app = try launchApp()
        app.buttons["day-3"].tap()
        app.buttons["exercise-card-Chest Dips Machine"].tap()
        let addSet = app.buttons["add-set-button"]
        XCTAssertTrue(addSet.waitForExistence(timeout: 10))
        for _ in 0..<6 where !addSet.isHittable { app.swipeUp() }
        addSet.tap()

        let reps = app.textFields["reps-field"]
        XCTAssertTrue(reps.waitForExistence(timeout: 5))
        reps.tap()
        reps.clearText()
        reps.typeText("0")
        app.buttons["save-set-button"].tap()

        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["today-set-1"].exists)
    }

    // MARK: Helpers

    private func launchApp() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestSeed.launchArguments
        app.launch()
        XCTAssertTrue(app.buttons["day-1"].waitForExistence(timeout: 30), "day picker did not appear")
        return app
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    func clearText() {
        guard let text = value as? String, !text.isEmpty else { return }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
    }
}
