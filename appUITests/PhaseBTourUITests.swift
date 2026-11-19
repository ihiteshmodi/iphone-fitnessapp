import XCTest

/// Screenshots of every Blood Labs screen, for a layout review (overlaps, clipping, cut-off text). It asserts almost nothing.
/// Run against the real database (with output/lab-history.csv bundled) on the iPhone 15 Pro Max:
///   UI_SEED_DB=output/fitness.sqlite scripts/run-ui-tests.sh PhaseBTourUITests
/// then export with: xcrun xcresulttool export attachments --path .uitest-logs/PhaseBTourUITests.xcresult --output-path .shots
final class PhaseBTourUITests: XCTestCase {
    private var app: XCUIApplication!

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    @discardableResult
    private func reveal(_ id: String, swipes: Int = 10) -> Bool {
        let target = element(id)
        for _ in 0..<swipes where !(target.exists && target.isHittable) { app.swipeUp() }
        return target.exists && target.isHittable
    }

    @discardableResult
    private func open(_ id: String, snap name: String, swipes: Int = 10) -> Bool {
        guard reveal(id, swipes: swipes) else { snap("\(name)-MISSING"); return false }
        element(id).tap()
        sleep(1)
        snap(name)
        return true
    }

    private func scrollSnaps(_ name: String, times: Int) {
        for index in 1...times { app.swipeUp(); snap("\(name)-scroll\(index)") }
    }

    private func top() { for _ in 0..<6 { app.swipeDown() } }

    /// Applies the bundled lab history (adds nothing the second time) and opens Body → Bloodwork.
    @discardableResult
    private func openLabs(snapMore: Bool = false) -> Bool {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = UITestSeed.launchArguments + ["-UITestInitialTab", "4"]
        app.launch()
        sleep(2)
        if reveal("apply-lab-history") {
            if snapMore { snap("b00-more-lab-history") }
            element("apply-lab-history").tap(); sleep(2)
            if snapMore { snap("b00-more-lab-history-applied") }
        }
        app.tabBars.buttons.element(boundBy: 1).tap()
        sleep(1)
        return open("labs-entry", snap: "labs-open")
    }

    func testA_LabsHub() {
        guard openLabs(snapMore: true) else { return }
        snap("b01-labs")
        scrollSnaps("b01-labs", times: 5)
        top()
        if open("labs-settings-button", snap: "b02-settings") { app.swipeDown(velocity: .fast); sleep(1) }
    }

    func testB_AddDraw() {
        guard openLabs(), open("labs-add-draw", snap: "b03-add-draw") else { return }
        app.swipeUp(); snap("b03-add-draw-scroll")
        if open("labs-add-result", snap: "b04-marker-picker") {
            app.searchFields.firstMatch.tap(); app.searchFields.firstMatch.typeText("ferritin"); sleep(1)
            snap("b04-marker-picker-search")
            app.staticTexts["Ferritin"].firstMatch.tap(); sleep(1)
            snap("b05-add-draw-with-result")
        }
    }

    func testC_PlanDraw() {
        guard openLabs(), open("labs-plan-draw", snap: "b06-plan") else { return }
        scrollSnaps("b06-plan", times: 6)
    }

    func testD_Markers() {
        guard openLabs(), open("labs-marker-library", snap: "b07-markers") else { return }
        app.swipeUp(); snap("b07-markers-scroll")
        app.cells.element(boundBy: 2).tap(); sleep(1); snap("b08-marker-detail")
        scrollSnaps("b08-marker-detail", times: 5)
    }

    func testE_Genetics() {
        guard openLabs(), open("labs-genetics", snap: "b09-genetics") else { return }
        app.swipeUp(); snap("b09-genetics-scroll")
        app.swipeDown()
        app.cells.element(boundBy: 1).tap()
        sleep(1); snap("b10-gene")
    }

    func testF_Draw() {
        guard openLabs(), open("labs-draw-row", snap: "b11-draw", swipes: 14) else { return }
        scrollSnaps("b11-draw", times: 2)
        let result = app.cells.element(boundBy: 6)
        if result.exists { result.tap(); sleep(1); snap("b12-marker-from-draw"); scrollSnaps("b12-marker-from-draw", times: 3) }
    }

    func testG_RoomForImprovementLabsTab() {
        guard openLabs() else { return }
        app.tabBars.buttons.element(boundBy: 2).tap()
        sleep(1)
        if open("room-for-improvement-link", snap: "b13-room") {
            app.buttons["Labs"].tap(); sleep(1); snap("b13-room-labs")
            scrollSnaps("b13-room-labs", times: 3)
        }
    }

    /// L12 (no blank title band on More, Edit plan, Library) and L9 (test-first lines show lab results).
    func testH_MoreTitlesAndTestFirst() {
        guard openLabs() else { return }
        app.tabBars.buttons.element(boundBy: 4).tap()
        sleep(1)
        top()
        snap("b14-more-top")
        if open("edit-plan-row", snap: "b15-edit-plan") { app.goBack(); sleep(1) }
        if open("library-row", snap: "b16-library") { app.goBack(); sleep(1) }
        top()
        if open("supplements-row", snap: "b17-supplements") {
            let search = element("supplement-search")
            if search.exists { search.tap(); search.typeText("B12"); sleep(1) }
            if open("supplement-vitamin-b12", snap: "b18-supplement-b12", swipes: 3) { app.swipeUp(); snap("b18-supplement-b12-scroll") }
        }
    }
}
