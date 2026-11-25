import XCTest

/// A bot chat's issue card: tiles, Work on it turning a tile to Started, a tile
/// opening its issue. Against a real server whose bot chat holds a card with
/// open issue `WAIN_ISSUE_START` on it:
///   TEST_RUNNER_WAIN_CARD_URL=ws://127.0.0.1:47231 TEST_RUNNER_WAIN_TOKEN=… TEST_RUNNER_WAIN_CARD_BOT=…
final class IssueCardTests: XCTestCase {
    func testWorkOnItStarts() throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["WAIN_CARD_URL"], let token = env["WAIN_TOKEN"] else { throw XCTSkip("no server") }
        let app = XCUIApplication()
        app.launchArguments = ["-servers", "", "-list.hideSessions", "NO", "-bot.dismissedStalls", ""]
        app.launch()
        XCTAssertTrue(app.buttons["Enter an address"].waitForExistence(timeout: 10), "no empty list")
        app.buttons["Enter an address"].tap()
        for (field, text) in [("Address", url), ("Token", token), ("Name", "Test Mac")] {
            XCTAssertTrue(app.textFields[field].waitForExistence(timeout: 5), "no \(field) field")
            app.textFields[field].tap()
            app.textFields[field].typeText(text)
        }
        app.buttons["Add"].tap()
        let bot = app.staticTexts[env["WAIN_CARD_BOT"] ?? "Issue Bot"].firstMatch
        XCTAssertTrue(bot.waitForExistence(timeout: 15), "no bot row after pairing")
        bot.tap()

        let number = env["WAIN_ISSUE_START"] ?? "1"
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "#\(number), open")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "no tile for #\(number)")
        sleep(1)
        attach(app, "card")

        let play = app.buttons.matching(identifier: "Work on it").firstMatch
        XCTAssertTrue(play.exists, "no Work on it button")
        play.tap()
        XCTAssertTrue(app.images["Started"].waitForExistence(timeout: 15), "tile never showed its check")
        sleep(1)
        attach(app, "started")

        tile.tap()
        XCTAssertTrue(app.navigationBars["#\(number)"].waitForExistence(timeout: 10), "the issue did not open")
        sleep(3)
        attach(app, "opened")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
