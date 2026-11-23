import XCTest

/// One acceptance test per Phase A feature, on the seeded database plus the made-up demo diet
/// (tools/diet-import/demo_diet.py). The class shares one database, so every test uses its own names and data.
///   scripts/run-ui-tests.sh PhaseAUITests
final class PhaseAUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(tab: Int) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = UITestSeed.launchArguments + ["-UITestInitialTab", "\(tab)"]
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// Scrolls until the element can be tapped; the floating tab bar covers the bottom of the screen.
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10) || scrollUntilExists(element), "missing \(element)", file: file, line: line)
        for _ in 0..<10 where !(element.isHittable && element.frame.maxY < app.frame.maxY - 110) { app.swipeUp() }
    }

    private func scrollUntilExists(_ element: XCUIElement) -> Bool {
        for _ in 0..<10 where !element.exists { app.swipeUp() }
        return element.exists
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(id)
        reveal(target, file: file, line: line)
        target.tap()
    }

    private func type(_ text: String, into id: String) {
        let field = element(id)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    private func diet(_ segment: String) {
        launch(tab: 2)
        XCTAssertTrue(element("diet-total-calories").waitForExistence(timeout: 15))
        if segment != "today" { app.buttons["diet-segment-\(segment)"].tap() }
    }

    // MARK: Diet

    func testAnExtraKeepsItsTimeAndNote() {
        diet("today")
        tap("diet-add-extra")
        type("Tea\n", into: "extra-search-field")
        let result = element("extra-result-Tea biscuits")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        // The chip defaults to the current time of day and a second tap clears it, so pick one that is not the default.
        let late = Calendar.current.component(.hour, from: Date()) >= 20
        let chosen = late ? "Morning" : "Night"
        tap("extra-time-\(chosen.lowercased())")
        type("with chai\n", into: "extra-note-field")
        tap("extra-add-button")

        let extra = element("diet-extra-Tea biscuits")
        reveal(extra)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'with chai'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts[chosen].exists, "extras are grouped by time")
    }

    func testANewMealCanBeAddedAndMovedUp() {
        diet("plan")
        tap("plan-new-meal")
        type("Snack", into: "plan-meal-field")
        type("Peanuts", into: "plan-search-field")
        tap("plan-result-Peanuts")
        tap("plan-item-save")

        let snack = element("plan-item-Snack-Peanuts")
        reveal(snack)
        tap("plan-move-up-Snack")
        let snackY = element("plan-item-Snack-Peanuts").frame.minY
        let dinnerY = element("plan-item-Dinner-Soy chunks").frame.minY
        XCTAssertLessThan(snackY, dinnerY, "Snack moved above Dinner")
    }

    func testTheDietCanBeSavedUnderAName() {
        diet("plan")
        tap("plan-saved-diets")
        tap("save-current-diet")
        // Alerts drop text field identifiers, so the alert's only field is used.
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Demo maintenance")
        app.alerts.buttons["Save"].tap()

        XCTAssertTrue(element("use-diet-Demo maintenance").waitForExistence(timeout: 5))
    }

    func testCookForShowsTheRecipeForMorePieces() {
        diet("foods")
        tap("food-row-Flatbread")
        XCTAssertTrue(element("recipe-cook-card").waitForExistence(timeout: 5))
        tap("recipe-cook-plus")

        XCTAssertEqual(element("recipe-cook-for").label, "3 pieces", "the demo Flatbread makes 2 pieces")
        XCTAssertTrue(app.staticTexts["90 g"].exists, "60 g rice flour for 2 pieces is 90 g for 3")
    }

    func testARecipeCanBeDuplicated() {
        diet("foods")
        tap("food-row-Flatbread")
        tap("recipe-duplicate-button")
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(" small")
        app.alerts.buttons["Duplicate"].tap()

        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'small'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testRoomForImprovementHasItsTabs() {
        diet("today")
        tap("room-for-improvement-link")

        for tab in ["Today", "Trends", "Setup", "Labs", "Archived"] { XCTAssertTrue(app.buttons[tab].waitForExistence(timeout: 5), tab) }
        app.buttons["Labs"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Nothing from your bloodwork'")).firstMatch
            .waitForExistence(timeout: 5), "the seed has no draws, so the Labs tab says so")
    }

    func testTheCheckInRecordsAWalkAfterAMeal() {
        diet("today")
        tap("checkin-walk-Lunch")

        XCTAssertTrue(element("checkin-walk-Lunch").label.contains("✓"))
    }

    func testDailyTargetsExcludesAminoAcidsAndMealProfileListsThem() {
        diet("today")
        tap("daily-targets-link")

        XCTAssertTrue(app.staticTexts["Fiber"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Leucine"].exists, "Amino acids moved to per-meal Meal Profile")

        app.navigationBars.buttons.firstMatch.tap()
        tap("diet-meal-profile-Lunch")
        XCTAssertTrue(app.staticTexts["Leucine"].waitForExistence(timeout: 5))
    }

    // MARK: Body and Progress

    func testCalorieHistoryShowsAnEarlierDay() {
        launch(tab: 1)
        tap("body-previous-day")

        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'As of'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(element("body-back-to-today").exists)
    }

    func testAMeasurementCanBeAddedFromItsScreen() {
        launch(tab: 3)
        let ring = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'measurement-ring-'")).firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 15))
        ring.tap()
        tap("add-reading-button")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("33.3")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '33.3'")).firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: More

    func testBreakModeShowsOnTheBodyTab() {
        launch(tab: 4)
        tap("start-break-button")
        XCTAssertTrue(element("end-break-button").waitForExistence(timeout: 5))

        app.tabButton("Body").tap()
        XCTAssertTrue(element("body-on-break").waitForExistence(timeout: 5))

        // Ending today still counts today as a break day, so the break is removed to leave the other tests a normal day.
        app.tabButton("More").tap()
        let remove = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'remove-break-'")).firstMatch
        reveal(remove)
        remove.tap()
        XCTAssertTrue(element("start-break-button").waitForExistence(timeout: 5))
    }

    func testTheSupplementLibraryFindsANotRecommendedProduct() {
        launch(tab: 4)
        tap("supplements-row")
        type("collagen", into: "supplement-search")
        tap("supplement-collagen")

        XCTAssertTrue(app.staticTexts["Not recommended"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["WHY"].exists || app.staticTexts["Why"].exists)
    }

    func testTheSweatyActivityToolGivesABottle() {
        launch(tab: 4)
        tap("sweaty-activity-row")

        XCTAssertTrue(element("sweat-plan").waitForExistence(timeout: 5))
    }

    func testTheDietCanBeExportedForReview() {
        launch(tab: 4)
        tap("diet-review-export")

        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10) || app.navigationBars["UIActivityContentView"].exists
                      || app.buttons["Copy"].waitForExistence(timeout: 5), "the share sheet opens")
    }

    func testTheWorkoutCanBeSavedAndRoutinesOpen() {
        launch(tab: 4)
        tap("edit-plan-row")
        tap("plan-saved-workouts")
        tap("save-current-workout")
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Demo split")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Demo split"].waitForExistence(timeout: 5))

        app.goBack()
        tap("plan-routines")
        XCTAssertTrue(element("add-routine-button").waitForExistence(timeout: 5) || app.staticTexts["Routines"].exists)
    }
}
