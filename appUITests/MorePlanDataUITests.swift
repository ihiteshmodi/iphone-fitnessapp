import XCTest

final class MorePlanDataUITests: XCTestCase {
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestSeed.launchArguments
        app.launch()
        return app
    }

    private func openMoreTab(_ app: XCUIApplication) {
        let tab = app.tabButton("More")
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
    }

    /// The plan is a lazy list, so rows far down only exist after scrolling to them.
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 12) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not scroll to \(element)")
    }

    func testMoreTabShowsExportAndSettings() {
        let app = launchApp()
        openMoreTab(app)

        XCTAssertTrue(app.buttons["export-database-button"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.switches["deload-toggle"].exists)
        XCTAssertTrue(app.segmentedControls["day-label-mode-picker"].exists)
        XCTAssertTrue(app.buttons["edit-plan-row"].exists)
    }

    func testDeloadToggleAndDayNames() {
        let app = launchApp()
        openMoreTab(app)

        let toggle = app.switches["deload-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let before = toggle.value as? String
        toggle.tap()
        XCTAssertNotEqual(toggle.value as? String, before)
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, before)

        let ignore = app.switches["ignore-deload-toggle"]
        scrollUntilHittable(ignore, in: app)
        XCTAssertEqual(ignore.value as? String, "1", "ignoring deload sessions is on by default")
        ignore.tap()
        XCTAssertEqual(ignore.value as? String, "0")
        ignore.tap()
        XCTAssertEqual(ignore.value as? String, "1")

        let picker = app.segmentedControls["day-label-mode-picker"]
        picker.buttons["Weekdays"].tap()
        XCTAssertTrue(picker.buttons["Weekdays"].isSelected)
        picker.buttons["Numbers"].tap()
        XCTAssertTrue(picker.buttons["Numbers"].isSelected)
    }

    func testCreateExerciseFromPlanAndFindItInLibrary() {
        let app = launchApp()
        openMoreTab(app)

        app.buttons["edit-plan-row"].tap()
        let dayThree = app.buttons["plan-day-3"]
        XCTAssertTrue(dayThree.waitForExistence(timeout: 10))
        dayThree.tap()

        let addExercise = app.buttons["add-exercise-button"]
        scrollUntilHittable(addExercise, in: app)
        addExercise.tap()

        let createRow = app.buttons["create-exercise-row"]
        XCTAssertTrue(createRow.waitForExistence(timeout: 5))
        createRow.tap()

        let nameField = app.textFields["exercise-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Landmine Press\n")
        app.buttons["Shoulders"].tap()
        app.buttons["save-exercise-button"].tap()

        let addedRow = app.staticTexts["Landmine Press"]
        scrollUntilHittable(addedRow, in: app)
        XCTAssertTrue(addedRow.exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["library-row"].tap()
        let search = app.textFields["library-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Landmine")
        XCTAssertTrue(app.buttons["library-exercise-row"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Landmine Press"].exists)
    }

    func testExportButtonExists() {
        let app = launchApp()
        openMoreTab(app)
        XCTAssertTrue(app.buttons["export-database-button"].waitForExistence(timeout: 10))
    }
}
