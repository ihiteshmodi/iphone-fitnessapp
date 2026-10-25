import XCTest

/// Visits every screen and saves a screenshot of each (plus the element tree where useful) as test attachments.
/// It asserts almost nothing: it exists so a person can look at the screens without a window on the Mac.
///   scripts/run-ui-tests.sh ScreenTourUITests
/// then export with: xcrun xcresulttool export attachments --path .uitest-logs/ScreenTourUITests.xcresult --output-path .shots
final class ScreenTourUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
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

    private func dumpTree(_ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollAndSnap(_ prefix: String, times: Int = 3) {
        for index in 1...times {
            app.swipeUp()
            snap("\(prefix)-scroll\(index)")
        }
    }

    func testTourWorkoutAndExerciseDetail() {
        XCTAssertTrue(app.buttons["day-3"].waitForExistence(timeout: 30))
        app.buttons["day-3"].tap()
        snap("01-workout-day3")

        let card = app.buttons["exercise-card-Chest Dips Machine"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        _ = app.buttons["add-set-button"].waitForExistence(timeout: 10)
        snap("02-detail-top")
        scrollAndSnap("02-detail")
    }

    func testTourBody() {
        XCTAssertTrue(app.buttons["day-1"].waitForExistence(timeout: 30))
        app.tabButton("Body").tap()
        sleep(1)
        snap("03-body")
        dumpTree("03-body-tree")
        scrollAndSnap("03-body", times: 2)
    }

    func testTourProgress() {
        XCTAssertTrue(app.buttons["day-1"].waitForExistence(timeout: 30))
        app.tabButton("Progress").tap()
        sleep(1)
        snap("04-progress")
        dumpTree("04-progress-tree")
        scrollAndSnap("04-progress", times: 2)
    }

    func testTourMorePlanAndLibrary() {
        XCTAssertTrue(app.buttons["day-1"].waitForExistence(timeout: 30))
        app.tabButton("More").tap()
        sleep(1)
        snap("05-more")
        scrollAndSnap("05-more", times: 2)
        dumpTree("05-more-tree")

        app.swipeDown()
        app.swipeDown()
        let editPlan = app.buttons["edit-plan-row"]
        if editPlan.waitForExistence(timeout: 5) {
            editPlan.tap()
            sleep(1)
            snap("06-edit-plan")
            let dayThree = app.buttons["plan-day-3"]
            if dayThree.waitForExistence(timeout: 5) {
                dayThree.tap()
                sleep(1)
                snap("07-edit-plan-day3")
                dumpTree("07-edit-plan-tree")
            }
            let add = app.buttons["add-exercise-button"]
            for _ in 0..<10 where !(add.exists && add.isHittable) { app.swipeUp() }
            if add.exists {
                add.tap()
                sleep(1)
                snap("08-add-exercise-sheet")
                let create = app.buttons["create-exercise-row"]
                if create.waitForExistence(timeout: 5) {
                    create.tap()
                    sleep(1)
                    snap("09-new-exercise-form")
                    dumpTree("09-new-exercise-form-tree")
                }
            }
        }
    }

    func testTourLibrary() {
        XCTAssertTrue(app.buttons["day-1"].waitForExistence(timeout: 30))
        app.tabButton("More").tap()
        let library = app.buttons["library-row"]
        for _ in 0..<4 where !(library.exists && library.isHittable) { app.swipeUp() }
        if library.exists {
            library.tap()
            sleep(1)
            snap("10-library")
        }
    }
}
