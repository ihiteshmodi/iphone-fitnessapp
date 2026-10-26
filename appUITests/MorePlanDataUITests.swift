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

    func testEditPlanHasMainSetsAndWarmupSetsAndWarmupsAppearOnTheExerciseScreen() {
        let app = launchApp()
        openMoreTab(app)
        app.buttons["edit-plan-row"].tap()
        let day3 = app.buttons["plan-day-3"]
        XCTAssertTrue(day3.waitForExistence(timeout: 10))
        day3.tap()
        let edit = app.buttons["edit-entry-button"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        XCTAssertTrue(app.staticTexts["Main sets"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Warm-up sets"].exists)
        XCTAssertEqual(app.staticTexts["stepper-value-Warm-up sets"].label, "0", "existing exercises start with no warm-ups")
        app.buttons["Increase Warm-up sets"].tap()
        app.buttons["Increase Warm-up sets"].tap()
        XCTAssertEqual(app.staticTexts["stepper-value-Warm-up sets"].label, "2")
        app.buttons["save-entry-button"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '2 warm-up'")).firstMatch.waitForExistence(timeout: 5))

        // Put the shared test database back.
        app.buttons["edit-entry-button"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Decrease Warm-up sets"].waitForExistence(timeout: 5))
        app.buttons["Decrease Warm-up sets"].tap()
        app.buttons["Decrease Warm-up sets"].tap()
        app.buttons["save-entry-button"].tap()
    }

    func testWeekdayNamingShowsTheChosenWeekdayOnTheWorkoutTab() {
        let app = launchApp()
        openMoreTab(app)
        app.buttons["edit-plan-row"].tap()

        let mode = app.segmentedControls["plan-day-label-mode-picker"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.buttons["Name by weekdays"].tap()
        let weekday = app.buttons["weekday-picker-1"]
        XCTAssertTrue(weekday.waitForExistence(timeout: 5), "the weekday picker is visible without opening the day")
        weekday.tap()
        app.buttons["Monday"].tap()

        app.tabButton("Workout").tap()
        XCTAssertTrue(app.buttons["day-1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["day-1"].label.contains("Mon"), "day 1 is named by its weekday")

        // The More tab keeps Edit plan open; put the shared test database back.
        openMoreTab(app)
        let mode2 = app.segmentedControls["plan-day-label-mode-picker"]
        if !mode2.waitForExistence(timeout: 3) { app.buttons["edit-plan-row"].tap() }
        mode2.buttons["Name by numbers"].tap()
    }

    func testEditPastDataLetsMeAddAWeighInForAChosenDay() {
        let app = launchApp()
        openMoreTab(app)
        let row = app.buttons["edit-past-data-row"]
        scrollUntilHittable(row, in: app)
        row.tap()

        XCTAssertTrue(app.descendants(matching: .any)["past-day-picker"].waitForExistence(timeout: 10))
        let add = app.buttons["past-add-weight"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let field = app.textFields["value-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("81.9")
        app.buttons["sheet-save-button"].tap()

        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'past-weight-'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "the new weigh-in is listed for the chosen day")
        XCTAssertTrue(saved.label.contains("81.9"))
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
        // A Shoulders button also exists behind the sheet; the sheet's is the last one.
        app.buttons.matching(identifier: "Shoulders").allElementsBoundByIndex.last?.tap()
        app.buttons["save-exercise-button"].tap()

        let addedRow = app.staticTexts["Landmine Press"]
        scrollUntilHittable(addedRow, in: app)
        XCTAssertTrue(addedRow.exists)

        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists {
            back.tap()
        } else {
            // Some layouts (the iPhone Duo simulator) draw no back button; the edge swipe goes back too.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        }
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
