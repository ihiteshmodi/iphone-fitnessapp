import XCTest

/// Acceptance UI tests for Phase D on the test fixture database:
///   scripts/run-ui-tests.sh PhaseDUITests
final class PhaseDUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(tab: Int) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = UITestSeed.launchArguments + ["-UITestInitialTab", "\(tab)"]
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(id)
        XCTAssertTrue(target.waitForExistence(timeout: 10) || scrollUntilExists(target), "missing \(id)", file: file, line: line)
        for _ in 0..<10 where !(target.isHittable && target.frame.maxY < app.frame.maxY - 110) { app.swipeUp() }
        target.tap()
    }

    private func scrollUntilExists(_ target: XCUIElement) -> Bool {
        for _ in 0..<10 where !target.exists { app.swipeUp() }
        return target.exists
    }

    func testEditPlanShowsMuscleCoverageConfiguresTargetsAndCreatesRoutine() {
        launch(tab: 4)
        tap("edit-plan-row")
        XCTAssertTrue(element("plan-weekly-muscle-coverage").waitForExistence(timeout: 5))

        tap("plan-configure-muscle-targets")
        XCTAssertTrue(app.navigationBars["Weekly set targets"].waitForExistence(timeout: 5))
        tap("muscle-min-calves-minus")
        tap("muscle-targets-done")

        tap("plan-routines")
        XCTAssertTrue(element("create-routine-button").waitForExistence(timeout: 5))
        tap("create-routine-button")
        let nameField = app.textFields["routine-editor-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Quick Arms\n")
        tap("routine-editor-add-exercise")
        let firstEx = app.cells.firstMatch
        XCTAssertTrue(firstEx.waitForExistence(timeout: 5))
        firstEx.tap()
        tap("confirm-routine-exercise")
        tap("routine-editor-top-save")
        XCTAssertTrue(app.staticTexts["Quick Arms"].waitForExistence(timeout: 5))
    }

    func testDietPlanLiveTargetsFoodTopSaveRecipeProfileAndSavedDietPreview() {
        launch(tab: 2)
        tap("diet-segment-plan")
        XCTAssertTrue(element("plan-daily-targets-link").waitForExistence(timeout: 5))
        tap("plan-daily-targets-link")
        XCTAssertTrue(app.navigationBars["Planned daily targets"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        tap("plan-saved-diets")
        tap("save-current-diet")
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Phase D Diet")
        app.alerts.buttons["Save"].tap()
        tap("preview-diet-Phase D Diet")
        XCTAssertTrue(element("preview-use-diet").waitForExistence(timeout: 5))
        tap("saved-diet-preview-done")
        app.navigationBars.buttons.firstMatch.tap()

        for _ in 0..<4 { app.swipeDown() }
        tap("diet-segment-foods")
        tap("foods-new-food")
        XCTAssertTrue(app.buttons["food-top-save-button"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()

        tap("food-row-Flatbread")
        XCTAssertTrue(element("recipe-nutrition-profile-section").waitForExistence(timeout: 5) || scrollUntilExists(element("recipe-nutrition-profile-section")))
    }
}
