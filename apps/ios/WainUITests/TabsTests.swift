import UIKit
import XCTest

/// The four tabs (#27) against a scratch server holding a bot named `TEST_RUNNER_WAIN_BOT`: each
/// tab's screen, a bot's chat with the tab bar gone, Machines and Usage; on an iPad, the sidebar
/// with each bot under its heading. Export the shots with `xcrun xcresulttool export attachments`.
///   TEST_RUNNER_WAIN_URL=ws://127.0.0.1:… TEST_RUNNER_WAIN_TOKEN=… TEST_RUNNER_WAIN_BOT=Ops \
///   xcodebuild test -only-testing:WainUITests/TabsTests …
final class TabsTests: XCTestCase {
    func testTabs() throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["WAIN_URL"], let token = env["WAIN_TOKEN"], let bot = env["WAIN_BOT"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_URL, TEST_RUNNER_WAIN_TOKEN and TEST_RUNNER_WAIN_BOT")
        }
        // The alerts prompt a fresh install raises once a server is added.
        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            guard alert.buttons["Don’t Allow"].exists else { return false }
            alert.buttons["Don’t Allow"].tap()
            return true
        }
        let app = XCUIApplication()
        app.launchArguments = ["-servers", ""]
        app.launch()
        app.buttons["Enter an address"].tap()
        for (field, text) in [("Address", url), ("Token", token), ("Name", "studio")] {
            let f = app.textFields[field]
            XCTAssertTrue(f.waitForExistence(timeout: 5))
            f.tap()
            f.typeText(text)
        }
        app.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["machines"].waitForExistence(timeout: 15))
        sleep(3)
        app.tap()  // lets the interruption monitor answer
        sleep(1)
        snap(app, "tabs-01-home")

        let iPad = UIDevice.current.userInterfaceIdiom == .pad
        let botRow = app.descendants(matching: .any)[bot].firstMatch
        if iPad {
            // The sidebar names each bot under Bots; picking one opens its chat beside it.
            let toggle = app.buttons["ToggleSideBar"]
            if toggle.exists && !botRow.exists { toggle.tap() }
            XCTAssertTrue(botRow.waitForExistence(timeout: 10), "no bot in the sidebar")
            snap(app, "tabs-02-ipad-sidebar")
            botRow.tap()
            sleep(3)
            snap(app, "tabs-03-ipad-bot")
            for tab in ["Tasks", "Routines", "Home"] {
                app.descendants(matching: .any)[tab].firstMatch.tap()
                sleep(2)
                snap(app, "tabs-ipad-\(tab.lowercased())")
            }
        } else {
            for tab in ["Bots", "Tasks", "Routines"] {
                app.tabBars.buttons[tab].tap()
                sleep(2)
                snap(app, "tabs-\(tab.lowercased())")
            }
            app.tabBars.buttons["Bots"].tap()
            app.buttons["bot.\(bot)"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["composer"].waitForExistence(timeout: 15))
            sleep(1)
            XCTAssertFalse(app.tabBars.buttons["Home"].isHittable, "the tab bar stays over a chat")
            snap(app, "tabs-bot-chat")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        app.buttons["machines"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Show tasks and bots from"].waitForExistence(timeout: 10))
        snap(app, "tabs-machines")
        app.buttons["Usage"].tap()
        sleep(1)
        snap(app, "tabs-usage")
        app.buttons["Done"].tap()
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
