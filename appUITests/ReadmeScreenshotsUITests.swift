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
}
