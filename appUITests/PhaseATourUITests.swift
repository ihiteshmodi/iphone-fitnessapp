import XCTest

/// Screenshots of every screen added or changed in Phase A, for a layout review (overlaps, clipping, cut-off text).
/// It asserts almost nothing. Run against the real database on the iPhone 15 Pro Max:
///   UI_SEED_DB=output/fitness.sqlite scripts/run-ui-tests.sh PhaseATourUITests
/// then export with: xcrun xcresulttool export attachments --path .uitest-logs/PhaseATourUITests.xcresult --output-path .shots
final class PhaseATourUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(tab: Int) {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = UITestSeed.launchArguments + ["-UITestInitialTab", "\(tab)"]
        app.launch()
        sleep(2)
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// Scrolls until the element is on screen; false if it never appears.
    @discardableResult
    private func reveal(_ id: String, swipes: Int = 8) -> Bool {
        let target = element(id)
        for _ in 0..<swipes where !(target.exists && target.isHittable) { app.swipeUp() }
        return target.exists && target.isHittable
    }

    @discardableResult
    private func open(_ id: String, snap name: String, swipes: Int = 8) -> Bool {
        guard reveal(id, swipes: swipes) else { snap("\(name)-MISSING"); return false }
        element(id).tap()
        sleep(1)
        snap(name)
        return true
    }

    private func scrollSnaps(_ name: String, times: Int) {
        for index in 1...times { app.swipeUp(); snap("\(name)-scroll\(index)") }
    }

    private func closeSheet() {
        app.swipeDown(velocity: .fast)
        sleep(1)
    }

    func testDietToday() {
        launch(tab: 2)
        snap("d01-today")
        scrollSnaps("d01-today", times: 4)
        app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
        if open("room-for-improvement-link", snap: "d02-room") {
            for tab in ["Trends", "Setup", "Labs", "Archived"] where app.buttons[tab].exists {
                app.buttons[tab].tap(); sleep(1); snap("d02-room-\(tab.lowercased())")
                app.swipeUp(); snap("d02-room-\(tab.lowercased())-scroll")
                app.swipeDown()
            }
            app.goBack(); sleep(1)
        }
        app.swipeDown(); app.swipeDown()
        if open("recovery-signs-button", snap: "d04-recovery-signs", swipes: 12) { app.swipeUp(); snap("d04-recovery-signs-scroll"); closeSheet() }
        app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
        if open("daily-targets-link", snap: "d03-daily-targets") {
            scrollSnaps("d03-daily-targets", times: 4)
            app.goBack(); sleep(1)
        }
    }

    func testDietExtrasAndQuickAdd() {
        launch(tab: 2)
        if open("diet-add-extra", snap: "d04-add-extra") {
            let search = element("extra-search-field")
            if search.exists { search.tap(); search.typeText("Oreo"); sleep(1); snap("d05-add-extra-search") }
            closeSheet()
        }
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        if open("diet-quick-add", snap: "d06-quick-add") {
            app.swipeUp(); snap("d06-quick-add-scroll")
            closeSheet()
        }
    }

    func testDietPlanAndSavedDiets() {
        launch(tab: 2)
        guard reveal("diet-segment-plan", swipes: 0) || element("diet-segment-plan").exists else { snap("d06-plan-MISSING"); return }
        element("diet-segment-plan").tap(); sleep(1)
        snap("d06-plan")
        scrollSnaps("d06-plan", times: 3)
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        if open("plan-new-meal", snap: "d07-new-meal") { closeSheet() }
        app.swipeDown(); app.swipeDown()
        if open("plan-saved-diets", snap: "d08-saved-diets") { app.goBack(); sleep(1) }
    }

    func testDietRecipeTools() {
        launch(tab: 2)
        element("diet-segment-foods").tap(); sleep(1)
        snap("d09-foods")
        let search = element("foods-search-field")
        if search.exists { search.tap(); search.typeText("Maintenance"); sleep(1) }
        let shake = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'food-row-'")).firstMatch
        guard shake.waitForExistence(timeout: 5) else { snap("d10-recipe-MISSING"); return }
        shake.tap(); sleep(1)
        snap("d10-recipe")
        scrollSnaps("d10-recipe", times: 3)
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        if reveal("recipe-cook-plus") {
            element("recipe-cook-plus").tap(); sleep(1); snap("d11-cook-for-2")
        } else { snap("d11-cook-for-MISSING") }
        app.swipeDown(); app.swipeDown()
        if open("recipe-edit-button", snap: "d12-recipe-edit") {
            scrollSnaps("d12-recipe-edit", times: 4)
            closeSheet()
        }
    }

    func testBody() {
        launch(tab: 1)
        snap("b01-body")
        scrollSnaps("b01-body", times: 4)
        app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
        if open("body-previous-day", snap: "b02-previous-day", swipes: 2) {
            app.swipeUp(); snap("b02-previous-day-scroll")
            if element("body-back-to-today").exists { element("body-back-to-today").tap(); sleep(1) }
        }
        app.swipeDown(); app.swipeDown()
        if open("body-effective-details", snap: "b03-effective-details") { app.swipeUp(); snap("b03-effective-details-scroll") }
    }

    func testProgressAddReading() {
        launch(tab: 3)
        snap("p01-progress")
        let ring = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'measurement-ring-'")).firstMatch
        guard ring.waitForExistence(timeout: 10) else { snap("p02-MISSING"); return }
        ring.tap(); sleep(1)
        snap("p02-measurement")
        if open("add-reading-button", snap: "p03-add-reading") { closeSheet() }
    }

    func testMoreCardsAndTools() {
        launch(tab: 4)
        snap("m01-more")
        scrollSnaps("m01-more", times: 5)
        app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
        if open("plan-break-button", snap: "m02-plan-break", swipes: 3) { closeSheet() }
        if open("sweaty-activity-row", snap: "m03-sweaty") {
            app.swipeUp(); snap("m03-sweaty-scroll")
            app.goBack(); sleep(1)
        }
    }

    func testSupplements() {
        launch(tab: 4)
        guard open("supplements-row", snap: "s01-supplements") else { return }
        scrollSnaps("s01-supplements", times: 3)
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        if open("my-supplement-Gokhru", snap: "s02-gokhru-detail") {
            app.swipeUp(); snap("s02-gokhru-detail-scroll")
            app.goBack(); sleep(1)
        }
        app.swipeDown(); app.swipeDown()
        if open("my-supplement-Becadexamine", snap: "s03-multivitamin-whatif") {
            if app.buttons["3 tablets"].exists { app.buttons["3 tablets"].tap(); sleep(1); snap("s03-whatif-3") }
            app.swipeUp(); snap("s03-whatif-scroll")
            app.goBack(); sleep(1)
        }
        let search = element("supplement-search")
        if reveal("supplement-search") {
            search.tap(); search.typeText("tribulus"); sleep(1); snap("s04-search")
        }
    }

    func testWorkoutLibrary() {
        launch(tab: 0)
        snap("w01-workout")
        app.terminate()
        launch(tab: 4)
        if open("edit-plan-row", snap: "w02-edit-plan") {
            if open("plan-saved-workouts", snap: "w03-saved-workouts") { app.swipeUp(); snap("w03-saved-workouts-scroll"); app.goBack(); sleep(1) }
            if open("plan-routines", snap: "w04-routines") { app.swipeUp(); snap("w04-routines-scroll"); app.goBack(); sleep(1) }
        }
    }
}
