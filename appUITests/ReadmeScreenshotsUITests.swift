import XCTest

/// Takes the workout-flow screenshots used in the README (the other screens come from `ScreenTourUITests`).
/// It expects a sample database, not real data: copy one to /Users/Shared/fitness-ui-seed.sqlite and run
///   xcodebuild test ... -only-testing:FitnessAppUITests/ReadmeScreenshotsUITests
/// then export the attachments with: xcrun xcresulttool export attachments --path <bundle>.xcresult --output-path <dir>
final class ReadmeScreenshotsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = UITestSeed.launchArguments
        app.launch()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testWorkoutFlowScreens() {
        XCTAssertTrue(app.buttons["day-3"].waitForExistence(timeout: 30))
        app.buttons["day-3"].tap()
        XCTAssertTrue(app.buttons["filter-remaining"].waitForExistence(timeout: 10))
        sleep(1)
        snap("r01-workout-all")

        app.buttons["filter-remaining"].tap()
        sleep(1)
        snap("r02-workout-remaining")
        app.buttons["filter-all"].tap()

        let card = app.buttons["exercise-card-Triceps Pushdown"]
        for _ in 0..<4 where !(card.exists && card.isHittable) { app.swipeUp() }
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any)["pr-banner"].waitForExistence(timeout: 10))
        sleep(1)
        snap("r03-exercise-pr")

        let addSet = app.buttons["add-set-button"]
        for _ in 0..<8 where !addSet.isHittable { app.swipeUp() }
        app.swipeUp()
        snap("r04-exercise-log")

        for _ in 0..<4 where !addSet.isHittable { app.swipeDown() }
        addSet.tap()
        XCTAssertTrue(app.textFields["weight-field"].waitForExistence(timeout: 5))
        sleep(1)
        snap("r05-add-set")

        // The plan is 10 to 15 reps and the form starts at 13: two arrows reach the top of the range.
        app.buttons["reps-field-plus"].tap()
        app.buttons["reps-field-plus"].tap()
        app.buttons["save-set-button"].tap()
        XCTAssertTrue(app.buttons["form-yes"].waitForExistence(timeout: 10))
        sleep(1)
        snap("r06-form-question")
        app.buttons["form-yes"].tap()
        sleep(1)
    }

    // MARK: Diet screens (expects the demo database from tools/diet-import/demo_diet.py)

    private func relaunch(onTab tab: Int) {
        app.terminate()
        app.launchArguments = UITestSeed.launchArguments + ["-UITestInitialTab", "\(tab)"]
        app.launch()
    }

    private func scrollTo(_ element: XCUIElement) {
        var swipes = 0
        while !element.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
    }

    func testDietToday() {
        relaunch(onTab: 2)
        XCTAssertTrue(app.staticTexts["diet-total-calories"].waitForExistence(timeout: 20))
        sleep(1)
        snap("d01-diet-today")
    }

    func testDietAddExtra() {
        relaunch(onTab: 2)
        XCTAssertTrue(app.staticTexts["diet-total-calories"].waitForExistence(timeout: 20))
        let add = app.buttons["diet-add-extra"]
        scrollTo(add)
        add.tap()
        let search = app.textFields["extra-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Tea\n")
        app.buttons["extra-result-Tea biscuits"].tap()
        let plus = app.buttons["extra-plus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        for _ in 0..<3 { plus.tap() }
        sleep(1)
        snap("d02-diet-add-extra")
    }

    func testDietPlanAndCycle() {
        relaunch(onTab: 2)
        XCTAssertTrue(app.staticTexts["diet-total-calories"].waitForExistence(timeout: 20))
        app.buttons["diet-segment-plan"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["plan-item-Lunch-Mineral"].waitForExistence(timeout: 5))
        sleep(1)
        snap("d03-diet-plan")
        app.descendants(matching: .any)["plan-item-Lunch-Mineral"].tap()
        XCTAssertTrue(app.staticTexts["cycle-summary"].waitForExistence(timeout: 5))
        app.swipeUp()
        sleep(1)
        snap("d04-diet-cycle")
    }

    func testDietFoodsAndRecipe() {
        relaunch(onTab: 2)
        XCTAssertTrue(app.staticTexts["diet-total-calories"].waitForExistence(timeout: 20))
        app.buttons["diet-segment-foods"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["food-row-Flatbread"].waitForExistence(timeout: 5))
        sleep(1)
        snap("d05-diet-foods")
        app.descendants(matching: .any)["food-row-Flatbread"].tap()
        XCTAssertTrue(app.staticTexts["recipe-calories"].waitForExistence(timeout: 5))
        sleep(1)
        snap("d06-diet-recipe")
    }

    func testBodyWithDiet() {
        relaunch(onTab: 1)
        XCTAssertTrue(app.buttons["open-todays-diet-button"].waitForExistence(timeout: 20))
        sleep(1)
        snap("d07-body")
    }
}
