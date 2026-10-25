import XCTest

/// Tab buttons live in a bottom bar on most iPhones, but some layouts (for example the iPhone Duo simulator) draw them
/// as a floating side bar with no `TabBar` element, so fall back to any button with that label.
extension XCUIApplication {
    func tabButton(_ name: String) -> XCUIElement {
        let inTabBar = tabBars.buttons[name]
        return inTabBar.exists ? inTabBar : buttons[name].firstMatch
    }
}
