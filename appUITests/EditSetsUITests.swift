import XCTest

/// Correcting logged sets and the earlier-sessions list on the exercise screen.
final class EditSetsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func openChestDips() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestSeed.launchArguments
        app.launch()
        XCTAssertTrue(app.buttons["day-3"].waitForExistence(timeout: 30))
        app.buttons["day-3"].tap()
        let card = app.buttons["exercise-card-Chest Dips Machine"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        return app
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
    }

    func testEditsATodaySetInPlaceAndTheSheetOffersADate() {
        let app = openChestDips()
        let addSet = app.buttons["add-set-button"]
        scrollTo(addSet, in: app)
        addSet.tap()
        XCTAssertTrue(app.datePickers["date-picker"].waitForExistence(timeout: 5) || app.buttons["date-picker"].exists
                      || app.otherElements["date-picker"].exists, "the Add set sheet has a date")
        app.buttons["save-set-button"].tap()

        let edit = app.buttons["edit-set-1"]
        scrollTo(edit, in: app)
        edit.tap()
        let weight = app.textFields["weight-field"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        weight.tap()
        weight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (weight.value as? String ?? "").count))
        weight.typeText("47.5")
        app.buttons["save-set-button"].tap()

        let row = app.descendants(matching: .any)["today-set-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '47.5'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["edit-set-2"].exists, "editing must not add a second set")
    }

    func testEarlierSessionsExpandAndOfferEditAndDelete() {
        let app = openChestDips()
        let firstSession = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'session-'")).firstMatch
        scrollTo(firstSession, in: app)
        firstSession.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'edit-earlier-set-'")).firstMatch
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'delete-earlier-set-'")).firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "earlier-sessions"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
