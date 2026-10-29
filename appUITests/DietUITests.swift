import XCTest

/// The Diet tab against the seeded database plus the made-up demo diet (`tools/diet-import/demo_diet.py`).
final class DietUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Some simulator layouts (the iPhone Duo) mis-route taps on later tabs, so start on the Diet tab (index 2).
        app.launchArguments = UITestSeed.launchArguments + ["-UITestInitialTab", "2"]
        app.launch()
    }

    private var total: XCUIElement { app.staticTexts["diet-total-calories"] }

    private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }

    func testTodayAddsUpThePlanAndShowsTheProteinAndFatTargets() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        XCTAssertNotEqual(total.label, "–")
        XCTAssertTrue(element("diet-macro-protein").exists)
        XCTAssertTrue(element("diet-macro-fat").exists)
        XCTAssertTrue(element("diet-line-Rolled oats").exists, "the plan's items are listed under their meals")
    }

    func testUntickingAnItemTakesItsCaloriesOffTheDayAndTickingBringsThemBack() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        let before = total.label
        let oats = app.buttons["diet-line-Rolled oats"]
        XCTAssertTrue(oats.exists)

        oats.tap()

        XCTAssertEqual(app.buttons["diet-line-Rolled oats"].value as? String, "skipped")
        XCTAssertNotEqual(total.label, before, "the day has fewer calories without the oats")

        app.buttons["diet-line-Rolled oats"].tap()

        XCTAssertEqual(app.buttons["diet-line-Rolled oats"].value as? String, "eaten")
        XCTAssertEqual(total.label, before)
    }

    func testTheDayCanBeChangedWithTheArrows() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        let today = app.staticTexts["diet-date"].label

        app.buttons["diet-next-day"].tap()

        XCTAssertNotEqual(app.staticTexts["diet-date"].label, today)
        XCTAssertTrue(app.buttons["diet-back-to-today"].waitForExistence(timeout: 5))
        app.buttons["diet-back-to-today"].tap()
        XCTAssertEqual(app.staticTexts["diet-date"].label, today)
    }
}
