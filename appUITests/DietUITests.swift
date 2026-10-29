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

    // MARK: Extras

    private func calories(_ element: XCUIElement) -> Int {
        Int(element.label.replacingOccurrences(of: ",", with: "").filter(\.isNumber)) ?? -1
    }

    private func scrollTo(_ element: XCUIElement) {
        var swipes = 0
        while !element.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
    }

    func testFourBiscuitsAreWorkedOutFromThePackAndAddedToTheDay() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        let before = calories(total)
        let add = app.buttons["diet-add-extra"]
        scrollTo(add)
        add.tap()

        let search = app.textFields["extra-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Tea")
        let result = app.buttons["extra-result-Tea biscuits"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()

        let plus = app.buttons["extra-plus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        for _ in 0..<3 { plus.tap() }
        XCTAssertEqual(app.textFields["extra-amount-field"].value as? String, "4")
        XCTAssertEqual(calories(app.staticTexts["extra-preview-calories"]), 137, "4 pieces of 250 g / 35 at 480 kcal per 100 g")

        app.buttons["extra-add-button"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["diet-extra-Tea biscuits"].waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(abs(calories(total) - (before + 137)), 1, "the totals are shown rounded")
    }

    func testANewFoodCanBeCreatedFromTheSheetAndAddedStraightAway() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        let add = app.buttons["diet-add-extra"]
        scrollTo(add)
        add.tap()
        let search = app.textFields["extra-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Rice cakes")
        let newFood = app.buttons["extra-new-food"]
        XCTAssertTrue(newFood.waitForExistence(timeout: 5))
        newFood.tap()

        let calories = app.textFields["food-calories-field"]
        XCTAssertTrue(calories.waitForExistence(timeout: 5))
        calories.tap()
        calories.typeText("400")
        app.buttons["food-save-button"].tap()

        // The new food is selected with 30 g, which is 120 kcal at 400 kcal per 100 g.
        XCTAssertTrue(app.staticTexts["extra-preview-calories"].waitForExistence(timeout: 5))
        XCTAssertEqual(self.calories(app.staticTexts["extra-preview-calories"]), 120)
    }
}
