import XCTest

/// Screenshot tour for Phase E (Bloodwork Dashboard/Edit/Filters/Bidirectional Genetics, 5 Multivitamins, WHOOP Band & Dual-DB Backup):
///   UI_SEED_DB=output/fitness.sqlite UI_WHOOP_SEED_DB=output/whoop.sqlite scripts/run-ui-tests.sh PhaseETourUITests
final class PhaseETourUITests: XCTestCase {
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

    @discardableResult
    private func reveal(_ id: String, swipes: Int = 8) -> Bool {
        let target = element(id)
        for _ in 0..<swipes where !(target.exists && target.isHittable && target.frame.maxY < app.frame.maxY - 110) {
            app.swipeUp()
        }
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

    func testA1_BloodworkDashboardCombinedSnapshot() {
        launch(tab: 1)
        guard open("labs-entry", snap: "e01-labs-overview") else { return }
        if element("labs-confirm-male").exists {
            element("labs-confirm-male").tap(); sleep(1)
        }
        if open("labs-open-dashboard", snap: "e02-labs-dashboard-combined", swipes: 3) {
            app.swipeUp(); snap("e03-labs-dashboard-markers-list")
        }
    }

    func testA2_DrawEditSavedLabChipsAndEditResult() {
        launch(tab: 1)
        guard open("labs-entry", snap: "e04a-labs-draws", swipes: 4) else { return }
        if open("labs-draw-row", snap: "e04-draw-detail-edit-controls", swipes: 6) {
            if element("labs-edit-draw").exists {
                element("labs-edit-draw").tap(); sleep(1)
                snap("e05-edit-draw-sheet-saved-lab-chips")
                if app.buttons["Cancel"].exists { app.buttons["Cancel"].firstMatch.tap(); sleep(1) }
            }
            let editResultBtn = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'labs-edit-result-'")).firstMatch
            if editResultBtn.waitForExistence(timeout: 3) {
                editResultBtn.tap(); sleep(1)
                snap("e06-edit-result-sheet")
                if app.buttons["Cancel"].exists { app.buttons["Cancel"].firstMatch.tap(); sleep(1) }
            }
        }
    }

    func testB_MarkersQuickChipsAndCustomFilterSheet() {
        launch(tab: 1)
        guard open("labs-entry", snap: "e07-labs-before-markers") else { return }
        if open("labs-marker-library", snap: "e08-markers-all-chips", swipes: 4) {
            if element("labs-marker-chip-coreNotDone").exists {
                element("labs-marker-chip-coreNotDone").tap(); sleep(1)
                snap("e09-markers-chip-core-not-done")
            }
            if element("labs-marker-chip-coreDone").exists {
                element("labs-marker-chip-coreDone").tap(); sleep(1)
                snap("e10-markers-chip-core-done")
            }
            if element("labs-markers-custom-filter-button").exists {
                element("labs-markers-custom-filter-button").tap(); sleep(1)
                snap("e11-markers-custom-filter-sheet")
                app.swipeUp(); snap("e12-markers-custom-filter-chapters")
                if app.buttons["Cancel"].exists { app.buttons["Cancel"].firstMatch.tap(); sleep(1) }
            }
        }
    }

    func testC_BidirectionalGeneticsTrtContextAndPlanDrawGuardrails() {
        launch(tab: 1)
        guard open("labs-entry", snap: "e13-labs-before-genetics") else { return }
        if open("labs-open-context-sheet", snap: "e14-trt-rx-reverse-genetics-sheet", swipes: 5) {
            app.swipeUp(); snap("e14b-trt-rx-clinical-toggles")
            if app.buttons["Cancel"].exists { app.buttons["Cancel"].firstMatch.tap(); sleep(1) }
            else if element("labs-context-save").exists { element("labs-context-save").tap(); sleep(1) }
        }
        for _ in 0..<3 { app.swipeDown() }
        if open("labs-genetics", snap: "e15-genetics-bidirectional-top", swipes: 5) {
            app.swipeUp(); snap("e16-genetics-conditional-and-do-not-buy")
            app.swipeUp(); snap("e17-genetics-catalog-scroll")
            app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }
        for _ in 0..<3 { app.swipeDown() }
        if open("labs-plan-draw", snap: "e18-plan-draw-top", swipes: 4) {
            app.swipeUp(); snap("e19-plan-draw-genetics-and-guardrails")
            app.swipeUp(); snap("e19b-plan-draw-bottom")
        }
    }

    func testD_FiveMultivitaminsWhoopBandAndMoreDualBackup() {
        launch(tab: 4)
        snap("e20-more-dual-db-backup")
        app.swipeUp(); snap("e21-more-tools-with-whoop")
        if open("whoop-band-row", snap: "e22-whoop-band-top", swipes: 4) {
            app.swipeUp(); snap("e23-whoop-band-substrate-and-backup")
            app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }
        for _ in 0..<3 { app.swipeDown() }
        if open("supplements-row", snap: "e24-supplements-overview", swipes: 4) {
            if open("open-multivitamin-stack", snap: "e25-mvi-five-multivitamins", swipes: 3) {
                app.swipeUp(); snap("e26-mvi-vitamins-coverage")
            }
        }
    }
}
