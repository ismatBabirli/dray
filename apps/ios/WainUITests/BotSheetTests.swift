import XCTest

/// #1093 against a real server: New bot from the Bots tab, its chat's glass chip,
/// and the chip's Edit bot sheet saying where it runs and saving a new name and colour.
/// Against the homes `scripts/redesign_seed.py` makes: `bots` as the first server,
/// `empty` as the second, and its bot `Ops` for the scrolled header.
///   TEST_RUNNER_WAIN_URL=ws://127.0.0.1:… TEST_RUNNER_WAIN_TOKEN=… \
///   TEST_RUNNER_WAIN_URL2=ws://127.0.0.1:… TEST_RUNNER_WAIN_TOKEN2=… TEST_RUNNER_WAIN_BOT=Ops \
///   xcodebuild test -only-testing:WainUITests/BotSheetTests …
final class BotSheetTests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    func testNewBotThenEdit() throws {
        guard let url = env["WAIN_URL"], let token = env["WAIN_TOKEN"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_URL and TEST_RUNNER_WAIN_TOKEN")
        }
        let app = launch()
        pair(app, url: url, token: token)

        app.tab("Bots")
        // The bar's +, not the empty Bots tab's button of the same name.
        let newBot = app.navigationBars.buttons["New bot"]
        XCTAssertTrue(newBot.waitForExistence(timeout: 20), "no New bot button")
        // Off until the server answers.
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newBot)
        waitForExpectations(timeout: 20)
        sleep(1)
        snap(app, "list")
        // Names must differ on a server, and runs against one leave their bots behind.
        let run = Int(Date().timeIntervalSince1970) % 100_000
        newBot.tap()
        let field = app.textFields["Bot name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no name field")
        field.tap()
        field.typeText("Scout \(run)")
        app.buttons["sun"].tap()
        app.buttons["Teal"].tap()
        snap(app, "new-bot")
        app.buttons["Create"].tap()

        let chip = app.buttons["botChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 60), "the new bot's chat did not open")
        sleep(8)
        snap(app, "bot-chat")
        // A tap opens the bot's Tasks; editing is the long-press menu's.
        edit(app, chip)
        XCTAssertTrue(app.staticTexts["Runs on"].waitForExistence(timeout: 5), "Edit bot opened no sheet")
        XCTAssertTrue(app.staticTexts["Test Mac"].exists, "the sheet does not say where the bot runs")
        snap(app, "edit-bot")
        let name = app.textFields["Bot name"]
        // At the field's far end, so the cursor lands after the centred name.
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "Ranger \(run)")
        app.buttons["Pink"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Ranger \(run)"].waitForExistence(timeout: 10), "the rename did not reach the chip")
        sleep(1)
        snap(app, "renamed")

        // The sheet's agent pick moves the chat on the next message, as the desktop's does.
        edit(app, chip)
        let codex = app.buttons["Codex"]
        guard codex.waitForExistence(timeout: 5) else { return } // this machine has no Codex
        codex.tap()
        XCTAssertTrue(app.staticTexts["Your next message goes to Codex."].waitForExistence(timeout: 5),
                      "the sheet does not say the chat moves")
        sleep(2)
        snap(app, "edit-agent")
        app.buttons["Save"].tap()
        let moving = app.staticTexts["Your next message goes to Codex"]
        XCTAssertTrue(moving.waitForExistence(timeout: 5), "the composer does not say the chat moves")
        snap(app, "moving")
        app.reply("Reply with just: hello from codex")
        // The switch draws no line in the chat; the composer's note goes once the reply carried it.
        XCTAssertTrue(moving.waitForNonExistence(timeout: 60), "the chat did not move to Codex")
        app.buttons["Model"].tap()
        XCTAssertTrue(app.staticTexts["This task"].waitForExistence(timeout: 5), "the model chip opened no sheet")
        XCTAssertTrue(app.buttons["Codex"].isSelected, "This task does not run on Codex")
        app.buttons["Done"].tap()
        sleep(15)
        snap(app, "switched")
    }

    /// Two servers paired: New bot's "Runs on" is a menu of both, and picking one reads its agents.
    func testNewBotPicksServer() throws {
        guard let url = env["WAIN_URL"], let token = env["WAIN_TOKEN"], let url2 = env["WAIN_URL2"], let token2 = env["WAIN_TOKEN2"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_URL, _TOKEN, _URL2 and _TOKEN2")
        }
        let app = launch()
        pair(app, url: url, token: token)
        // Typed in, not a second link: opening one relaunched the app, which drops the first server.
        app.buttons["machines"].firstMatch.tap()
        app.buttons["Settings"].tap()
        // Settled first: a tap while Machines gives way to Settings opens nothing.
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Machines opened no Settings")
        sleep(1)
        app.buttons["Add server"].tap()
        XCTAssertTrue(app.textFields["Address"].waitForExistence(timeout: 5), "Add server opened no sheet")
        for (field, text) in [("Address", url2), ("Token", token2), ("Name", "Second Box")] {
            app.textFields[field].tap()
            app.textFields[field].typeText(text)
        }
        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Second Box"].waitForExistence(timeout: 10), "the second server was not added")
        sleep(3)
        app.buttons["Done"].tap()
        sleep(1)
        app.tab("Bots")
        let newBot = app.navigationBars.buttons["New bot"]
        XCTAssertTrue(newBot.waitForExistence(timeout: 20), "no New bot button")
        newBot.tap()
        let server = app.buttons["Server"]
        XCTAssertTrue(server.waitForExistence(timeout: 5), "no server picker with two servers up")
        server.tap()
        let second = app.buttons["Second Box"]
        XCTAssertTrue(second.waitForExistence(timeout: 5), "the menu does not list the second server")
        snap(app, "server-menu")
        second.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts["Second Box"].exists, "the pick did not land")
        snap(app, "server-picked")
    }

    /// A bot (`WAIN_BOT`) whose chat runs longer than the screen: rows scroll under bare chips, no shade.
    func testHeaderOverScrolledChat() throws {
        guard let url = env["WAIN_URL"], let token = env["WAIN_TOKEN"], let bot = env["WAIN_BOT"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_URL, TEST_RUNNER_WAIN_TOKEN and TEST_RUNNER_WAIN_BOT")
        }
        let app = launch()
        pair(app, url: url, token: token)
        app.tab("Bots")
        let row = app.buttons["bot.\(bot)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no bot row")
        row.tap()
        XCTAssertTrue(app.buttons["botChip"].waitForExistence(timeout: 10), "no bot chip")
        sleep(3)
        app.swipeDown()
        sleep(1)
        snap(app, "scrolled")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-servers", ""]
        app.launch()
        return app
    }

    /// Pairs through the link a QR carries, then turns down the alerts prompt a fresh install raises.
    private func pair(_ app: XCUIApplication, url: String, token: String) {
        var link = URLComponents(string: "wain://connect")!
        link.queryItems = [.init(name: "url", value: url), .init(name: "token", value: token), .init(name: "name", value: "Test Mac")]
        app.open(link.url!)
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 10), "the link opened no add sheet")
        app.buttons["Add"].tap()
        let deny = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Don’t Allow"]
        if deny.waitForExistence(timeout: 5) { deny.tap() }
    }

    /// The chip's long-press menu, then Edit bot.
    private func edit(_ app: XCUIApplication, _ chip: XCUIElement) {
        chip.press(forDuration: 1)
        let item = app.buttons["Edit bot"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the chip's menu has no Edit bot")
        item.tap()
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
