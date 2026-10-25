import XCTest

/// Launches without any import hook, the way a fresh install starts, and saves what the first screen shows.
final class FirstLaunchUITests: XCTestCase {
    func testFirstScreenExplainsHowToGetData() {
        let app = XCUIApplication()
        app.launch()

        let useFound = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'use-found-'")).firstMatch
        let startEmpty = app.buttons["start-empty-button"]
        XCTAssertTrue(useFound.waitForExistence(timeout: 20) || startEmpty.waitForExistence(timeout: 5)
            || app.buttons["day-1"].waitForExistence(timeout: 5))

        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "first-screen"
        top.lifetime = .keepAlways
        add(top)

        app.swipeUp()
        let scrolled = XCTAttachment(screenshot: app.screenshot())
        scrolled.name = "first-screen-scrolled"
        scrolled.lifetime = .keepAlways
        add(scrolled)
    }
}
