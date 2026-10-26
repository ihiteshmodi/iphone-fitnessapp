import XCTest

/// Tab buttons live in a bottom bar on most iPhones, but some layouts (for example the iPhone Duo simulator) draw them
/// as a floating side bar with no `TabBar` element, so fall back to any button with that label.
extension XCUIApplication {
    func tabButton(_ name: String) -> XCUIElement {
        let inTabBar = tabBars.buttons[name]
        return inTabBar.exists ? inTabBar : buttons[name].firstMatch
    }
}

extension XCUIApplication {
    /// Back one screen. Some layouts (the iPhone Duo simulator) draw no back button, so fall back to the edge swipe.
    func goBack() {
        let back = navigationBars.buttons.element(boundBy: 0)
        if back.exists {
            back.tap()
        } else {
            coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        }
    }
}
