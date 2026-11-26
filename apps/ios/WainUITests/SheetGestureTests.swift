import XCTest

/// In a bot's chat a swipe in from the right edge opens Tasks, a swipe across a code block only
/// scrolls it, one up the right edge only scrolls the chat, and the left edge still goes back
/// (#1415); a task opened from the sheet opens no Tasks by that swipe, and its composer types.
/// The short typing sheet this also dragged went with the tabs (#27): every chat's foot is a
/// composer now. Against `scripts/sheet_gesture_seed.py`'s server, bot `Ops`:
///   python3 scripts/sheet_gesture_seed.py /private/tmp/wain-sheet-gesture
///   WAIN_HOME=/private/tmp/wain-sheet-gesture wain-serve --port <port> &
///   TEST_RUNNER_WAIN_URL=ws://127.0.0.1:<port> TEST_RUNNER_WAIN_TOKEN=<printed> TEST_RUNNER_WAIN_BOT=Ops \
///   xcodebuild test -only-testing:WainUITests/SheetGestureTests
final class SheetGestureTests: XCTestCase {
    func testEdgeSwipes() throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["WAIN_URL"], let token = env["WAIN_TOKEN"], let bot = env["WAIN_BOT"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_URL, _TOKEN and _BOT")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-servers", "", "-dictation.server", ""]
        app.launch()
        var link = URLComponents(string: "wain://connect")!
        link.queryItems = [.init(name: "url", value: url), .init(name: "token", value: token), .init(name: "name", value: "Test server")]
        app.open(link.url!)
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 10), "the link opened no add sheet")
        app.buttons["Add"].tap()
        // A first launch asks about notifications, over whatever is tapped next.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }

        let screen = app.windows.firstMatch.frame
        let tasksSheet = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Tasks, ")).firstMatch
        // The nav bar's, never the hidden tab bar's button of that name.
        let tasks = app.navigationBars.buttons["Tasks"]
        let at = { (x: CGFloat, y: CGFloat) in app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)) }

        app.tab("Bots")
        let row = app.buttons["bot.\(bot)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no bot row")
        row.tap()
        XCTAssertTrue(tasks.waitForExistence(timeout: 10), "no Tasks button")
        let code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "let WIDE")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 15), "no code block in the bot's chat")
        sleep(2)
        // A card under the reply can leave the code block up under the bar.
        for _ in 0..<4 where code.frame.midY < 180 {
            at(screen.midX, screen.height * 0.3).press(forDuration: 0.05, thenDragTo: at(screen.midX, screen.height * 0.55))
            sleep(1)
        }
        snap(app, "bot-chat")

        // Across the code block, from inside it and from its right end: it scrolls, nothing opens.
        let y = code.frame.midY, before = code.frame.minX
        at(screen.width * 0.8, y).press(forDuration: 0.05, thenDragTo: at(screen.width * 0.2, y))
        sleep(1)
        XCTAssertFalse(tasksSheet.exists, "a swipe across a code block opened Tasks")
        XCTAssertLessThan(code.frame.minX, before - 40, "the code block didn't scroll")
        snap(app, "code-scrolled")
        // Up the right edge: the chat scrolls, nothing opens.
        at(screen.width - 2, screen.height * 0.55).press(forDuration: 0.05, thenDragTo: at(screen.width - 2, screen.height * 0.3))
        sleep(1)
        XCTAssertFalse(tasksSheet.exists, "a swipe up the right edge opened Tasks")

        // In from the right edge: Tasks. At a finger's speed: the chat has just scrolled, and a slow
        // drag from under the scroll bar while it still shows is the system's grab of that bar.
        let edgeSwipe = {
            at(screen.width - 1, screen.height * 0.5).press(
                forDuration: 0.05, thenDragTo: at(screen.width * 0.4, screen.height * 0.5), withVelocity: 800, thenHoldForDuration: 0)
        }
        edgeSwipe()
        XCTAssertTrue(tasksSheet.waitForExistence(timeout: 5), "a swipe in from the right edge opened no Tasks sheet")
        sleep(1)
        snap(app, "tasks-by-swipe")
        let task = app.buttons.matching(identifier: "botTask").firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 5), "no task in the sheet")
        task.tap()
        XCTAssertTrue(tasksSheet.waitForNonExistence(timeout: 5), "the task left the sheet up")
        XCTAssertTrue(app.composer.waitForExistence(timeout: 15), "no composer in the task")
        sleep(1)
        // A task has no Tasks sheet to open.
        edgeSwipe()
        sleep(1)
        XCTAssertFalse(tasksSheet.exists, "the edge swipe opened Tasks in a task")

        // Its composer takes words, and Send comes in for the mic. Left unsent.
        app.composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "no keyboard in the task")
        // A new simulator's keyboard opens on its own tip.
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) { tip.tap() }
        app.composer.typeText("Typed in the task")
        XCTAssertEqual(app.composer.value as? String, "Typed in the task", "the composer lost the words")
        XCTAssertTrue(app.buttons["send"].exists, "no Send for the words")
        XCTAssertLessThan(app.composer.frame.maxY, app.keyboards.firstMatch.frame.minY + 1, "the keyboard covers the composer")
        snap(app, "task-typed")
        app.composer.clearText()

        // The left edge still goes back, keyboard up, to the bot's chat and then the list.
        at(0, screen.height * 0.5).press(forDuration: 0.05, thenDragTo: at(screen.width * 0.7, screen.height * 0.5))
        XCTAssertTrue(tasks.waitForExistence(timeout: 5), "the back swipe didn't return to the bot's chat")
        sleep(1)
        at(0, screen.height * 0.5).press(forDuration: 0.05, thenDragTo: at(screen.width * 0.7, screen.height * 0.5))
        XCTAssertTrue(tasks.waitForNonExistence(timeout: 5), "the back swipe didn't leave the bot's chat")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the back swipe didn't land on Bots")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
