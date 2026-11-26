import XCTest

extension XCUIApplication {
    /// A reply from the session's composer: type into its field, then Send.
    func reply(_ text: String) {
        let field = composer
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no composer")
        field.tap()
        field.typeText(text)
        buttons["send"].tap()
    }

    /// The session's composer, drawn once the session is open.
    var composer: XCUIElement { descendants(matching: .any)["composer"] }
    var dock: XCUIElement { composer }

    /// One of the four tabs.
    func tab(_ name: String) {
        tabBars.buttons[name].firstMatch.tap()
    }
}

extension XCUIElement {
    /// Deletes whatever the field holds.
    func clearText() {
        guard let value = value as? String, !value.isEmpty else { return }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }
}
