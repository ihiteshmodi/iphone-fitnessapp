import XCTest

/// Body and Progress tabs against the real exported database (`output/fitness.sqlite`).
final class BodyProgressUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = UITestSeed.launchArguments
        app.launch()
    }

    func testProgressRingsShowGainAndLose() {
        openTab("Progress")

        let calf = app.buttons["measurement-ring-Left Calf"]
        XCTAssertTrue(calf.waitForExistence(timeout: 10))
        XCTAssertTrue(calf.label.contains("1.31"), "Left Calf label was: \(calf.label)")
        XCTAssertTrue(calf.label.contains("to gain"), "Left Calf label was: \(calf.label)")

        let waist = app.buttons["measurement-ring-Waist"]
        XCTAssertTrue(waist.exists)
        XCTAssertTrue(waist.label.contains("to lose"), "Waist label was: \(waist.label)")
    }

    func testChangingTargetUpdatesWhatIsLeftToGain() {
        openTab("Progress")
        let calf = app.buttons["measurement-ring-Left Calf"]
        XCTAssertTrue(calf.waitForExistence(timeout: 10))
        calf.tap()

        let editTarget = app.buttons["measurement-target-edit-button"]
        XCTAssertTrue(editTarget.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1.31"].exists)
        editTarget.tap()

        let field = app.textFields["value-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(in: field, with: "15.5")
        app.buttons["sheet-save-button"].tap()

        XCTAssertTrue(app.staticTexts["1.50"].waitForExistence(timeout: 5))
    }

    func testVolumeChipSelectsMuscle() {
        openTab("Progress")
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'volume-chip-'"))
        app.swipeUp()
        XCTAssertTrue(chips.firstMatch.waitForExistence(timeout: 10))
        let chip = chips.element(boundBy: chips.count > 1 ? 1 : 0)
        chip.tap()
        XCTAssertTrue(chip.isSelected)
    }

    func testBodyShowsTargetAfterEnteringCalories() {
        openTab("Body")

        let edit = app.buttons["calories-edit-button"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()

        let calories = app.textFields["calories-field"]
        XCTAssertTrue(calories.waitForExistence(timeout: 5))
        replaceText(in: calories, with: "2948.5")
        app.buttons["sheet-save-button"].tap()

        XCTAssertTrue(app.staticTexts["Cut"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3,027"].exists)
        XCTAssertTrue(app.buttons["log-weight-button"].exists)
    }

    func testEditingOneCalorieDayMarksItEditedAndTheBalanceCardShows() {
        openTab("Body")
        let edit = app.buttons["calories-edit-button"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        let calories = app.textFields["calories-field"]
        XCTAssertTrue(calories.waitForExistence(timeout: 5))
        XCTAssertTrue(app.datePickers["default-start-date"].exists || app.buttons["default-start-date"].exists
                      || app.otherElements["default-start-date"].exists, "the default has a start date")
        replaceText(in: calories, with: "3000")
        app.buttons["sheet-save-button"].tap()

        let balance = app.staticTexts["balance-headline"]
        for _ in 0..<4 where !balance.exists { app.swipeUp() }
        XCTAssertTrue(balance.exists, "the 'what your weight says' card is on the Body screen")

        let day = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calorie-day-'")).firstMatch
        for _ in 0..<6 where !(day.exists && day.isHittable) { app.swipeUp() }
        XCTAssertTrue(day.exists)
        day.tap()
        let field = app.textFields["value-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(in: field, with: "3200")
        app.buttons["sheet-save-button"].tap()

        let edited = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calorie-day-' AND label CONTAINS 'Edited'")).firstMatch
        XCTAssertTrue(edited.waitForExistence(timeout: 5), "the changed day is marked Edited")
        XCTAssertTrue(edited.label.contains("3,200"))
    }

    private func openTab(_ name: String) {
        let tab = app.tabButton(name)
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        field.typeText(text)
    }
}
