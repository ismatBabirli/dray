import XCTest

/// A chat opens on its newest rows, in view, never scrolled past them onto
/// blank; and a bot's Tasks sheet lists its tasks on shared machines too.
/// Against a scratch server holding a bot (`WAIN_BOT`, opened from Bots) with a
/// task on a machine that server shares (`wain machine add` then `wain machine
/// share on`), and tasks (`WAIN_CHATS`, opened from Tasks) of tall turns with a
/// screenshot and a recording under `browser/recordings/<id>/`, all behind
/// `scripts/late_turns_proxy.py`; `scripts/open_at_bottom_seed.py` makes both homes. Each test's comment says what else it wants:
///   python3 scripts/late_turns_proxy.py <port> <server port> <WAIN_HOME> &
///   TEST_RUNNER_WAIN_URL=ws://127.0.0.1:<port> TEST_RUNNER_WAIN_TOKEN=… TEST_RUNNER_WAIN_BOT=Ops \
///   TEST_RUNNER_WAIN_CHATS='Media check|Ops' TEST_RUNNER_WAIN_LATE=http://127.0.0.1:<port>/late \
///   xcodebuild test -only-testing:WainUITests/OpenAtBottomTests/<test> …
final class OpenAtBottomTests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    func testChatsOpenAtTheBottom() throws {
        guard let name = env["WAIN_BOT"] else { throw XCTSkip("set TEST_RUNNER_WAIN_BOT") }
        let app = try connected()
        app.tab("Bots")
        let bot = app.buttons["bot.\(name)"]
        XCTAssertTrue(bot.waitForExistence(timeout: 20), "no bot row")
        // The shared machines connect after the paired server does.
        sleep(15)
        snap(app, "list")

        bot.tap()
        assertRowsInView(app, "bot chat")
        snap(app, "bot-chat")

        let tasks = app.navigationBars.buttons["Tasks"]
        tasks.tap()
        sleep(2)
        snap(app, "bot-tasks")
        let rows = app.buttons.matching(identifier: "botTask")
        let count = min(rows.count, 6)
        XCTAssertGreaterThan(count, 0, "the Tasks sheet is empty")
        app.buttons["Done"].tap()

        // Each task opened over the chat, and back: one drawing blank fails.
        for i in 0..<count {
            tasks.tap()
            sleep(1)
            let row = rows.element(boundBy: i)
            guard row.waitForExistence(timeout: 5) else { break }
            let title = row.label
            row.tap()
            assertRowsInView(app, "task \(i) \(title)")
            snap(app, "task-\(i)")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(tasks.waitForExistence(timeout: 5))
            assertRowsInView(app, "bot chat after task \(i)")
        }
    }

    /// The newest row sits whole just above the composer on every open: cold, then again from
    /// memory, checked once more after the chat's pictures and videos have loaded. Wants
    /// `WAIN_CHATS`, the chats to open, "|" between them: a bot's name, or the start of a task's
    /// title. Long ones with media, behind `scripts/late_turns_proxy.py`.
    func testNewestRowClearsTheDock() throws {
        let app = try connected()
        for round in 1...(Int(env["WAIN_ROUNDS"] ?? "") ?? 3) {
            for chat in try chats() {
                open(app, chat)
                assertAtEnd(app, "\(chat), open \(round)")
                back(app)
            }
        }
    }

    /// The same when a turn lands with the chat open, and when one lands with the reader back
    /// on the list. Wants `WAIN_LATE`, the proxy's `/late` URL.
    func testNewestRowClearsTheDockAfterATurnLands() throws {
        guard let late = env["WAIN_LATE"] else { throw XCTSkip("set TEST_RUNNER_WAIN_LATE") }
        let app = try connected()
        for chat in try chats() {
            open(app, chat)
            assertAtEnd(app, "\(chat), opened")
            try land(app, late, "\(chat), a turn landing in it")
            back(app)
            let tag = try land(late)
            // The reconnect and its read, with nothing on screen to wait on.
            sleep(8)
            open(app, chat)
            XCTAssertTrue(app.staticTexts["Last line of \(tag)."].waitForExistence(timeout: 20), "\(chat): the turn never landed")
            assertAtEnd(app, "\(chat), a turn landed while away")
            back(app)
        }
    }

    /// The same from the cache a relaunch reads, under a read bringing a turn the cache never
    /// held: run `testNewestRowClearsTheDock`, fetch the proxy's `/late`, then this.
    func testNewestRowClearsTheDockReopened() throws {
        guard env["WAIN_URL"] != nil else { throw XCTSkip("run after testNewestRowClearsTheDock, with TEST_RUNNER_WAIN_URL set") }
        let app = XCUIApplication()
        app.launch()
        for chat in try chats() {
            open(app, chat)
            assertAtEnd(app, "\(chat), reopened")
            back(app)
        }
    }

    private func chats() throws -> [String] {
        guard let chats = env["WAIN_CHATS"]?.split(separator: "|").map(String.init), !chats.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_WAIN_CHATS")
        }
        return chats
    }

    /// A bot by its name on Bots, else a task by its title on Tasks.
    private func open(_ app: XCUIApplication, _ chat: String) {
        app.tab("Bots")
        var row = app.buttons["bot.\(chat)"]
        if !row.waitForExistence(timeout: 5) {
            app.tab("Tasks")
            row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", chat)).firstMatch
        }
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no row for \(chat)")
        row.tap()
        XCTAssertTrue(app.composer.waitForExistence(timeout: 10), "\(chat) did not open")
    }

    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Has the proxy add a turn to every chat and drop the socket; answers the turn's tag.
    private func land(_ late: String) throws -> String {
        let tag = String(UUID().uuidString.prefix(6))
        _ = try Data(contentsOf: XCTUnwrap(URL(string: "\(late)?tag=\(tag)")))
        return tag
    }

    /// A turn landing in the open chat: its last line drawn, and the view at the end again.
    private func land(_ app: XCUIApplication, _ late: String, _ what: String) throws {
        let tag = try land(late)
        XCTAssertTrue(app.staticTexts["Last line of \(tag)."].waitForExistence(timeout: 20), "\(what): it never landed")
        assertAtEnd(app, what)
    }

    /// A beat in, once the read has landed, and once late media has: the lowest thing the
    /// transcript draws sits just above the composer each time, neither under it nor far up.
    private func assertAtEnd(_ app: XCUIApplication, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        for wait in [1, 3, 6] {
            sleep(UInt32(wait))
            let gap = gapAboveComposer(app)
            print("GAP \(what) +\(wait)s: \(gap)")
            snap(app, "\(what) +\(wait)s \(gap.rounded())")
            XCTAssertGreaterThanOrEqual(gap, 8, "\(what), +\(wait)s: the newest row is behind the composer", file: file, line: line)
            XCTAssertLessThanOrEqual(gap, 76, "\(what), +\(wait)s: the chat is not at its end", file: file, line: line)
        }
    }

    /// From the lowest thing the transcript draws down to the composer's field. At the end that is the
    /// stack's last spacing, the dock's padding and the field's own, 48pt, and a bot chat's 10 more,
    /// its bubble's; under 8 is a row behind the composer.
    private func gapAboveComposer(_ app: XCUIApplication) -> CGFloat {
        // A long chat mid-layout can time a snapshot out; the next one answers.
        guard let tree = (0..<3).lazy.compactMap({ _ in try? app.scrollViews.firstMatch.snapshot() }).first else { return .nan }
        // Leaves alone, a video's controls among them, none as thin as a scroll indicator, and none
        // the size of the view, which a bot chat keeps behind its rows and no row is.
        func drawn(_ n: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
            n.children.isEmpty ? (n.frame.width < 10 || n.frame.height >= tree.frame.height ? [] : [n]) : n.children.flatMap(drawn)
        }
        let lowest = drawn(tree).map(\.frame.maxY).max() ?? .nan
        return app.composer.frame.minY - lowest
    }

    /// What the cache draws, replaced by a read that holds less: run `testHeldShrinks1`, append
    /// short turns to the session's log on the server, then `testHeldShrinks2`. Wants a scratch
    /// server holding one session titled "Scroll check" of tall turns.
    func testHeldShrinks1() throws {
        let app = try connected()
        app.tab("Tasks")
        let row = app.staticTexts["Scroll check"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no session")
        row.tap()
        assertRowsInView(app, "first open")
        snap(app, "first-open")
    }

    func testHeldShrinks2() throws {
        guard env["WAIN_URL"] != nil else { throw XCTSkip("run after testHeldShrinks1, with TEST_RUNNER_WAIN_URL set") }
        let app = XCUIApplication()
        app.launch()
        app.tab("Tasks")
        let row = app.staticTexts["Scroll check"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no session")
        row.tap()
        assertRowsInView(app, "reopened")
        snap(app, "reopened")
    }

    /// A turn landing leaves a reader who scrolled up where they are; once they are back at the
    /// end, the next one is followed again. Wants `WAIN_LATE`, and opens the first of `WAIN_CHATS`.
    func testFollowsOnlyAtTheBottom() throws {
        guard let late = env["WAIN_LATE"] else { throw XCTSkip("set TEST_RUNNER_WAIN_LATE") }
        let app = try connected()
        let chat = try chats()[0]
        open(app, chat)
        // A row of this run's own to watch, the one label in the chat nothing else carries.
        let mark = "Last line of \(try land(late))."
        XCTAssertTrue(app.staticTexts[mark].waitForExistence(timeout: 20), "the first turn never landed")
        assertAtEnd(app, "\(chat), opened")

        let scroll = app.scrollViews.firstMatch
        scroll.swipeDown(velocity: .slow)
        // A picture still loading above the row would move it as surely as a turn pulling the view.
        var place = top(app, mark)
        for _ in 0..<20 {
            sleep(3)
            let now = top(app, mark)
            if now == place { break }
            place = now
        }
        snap(app, "scrolled up")
        let tag = try land(late)
        XCTAssertTrue(app.staticTexts["Last line of \(tag)."].waitForExistence(timeout: 20), "the turn never landed")
        // Its media too.
        sleep(8)
        snap(app, "left alone")
        XCTAssertEqual(top(app, mark), place, accuracy: 4, "a turn landing moved the reader off their place")

        for _ in 0..<40 where gapAboveComposer(app) < 8 { scroll.swipeUp(velocity: .fast) }
        sleep(2)
        try land(app, late, "\(chat), back at the end")
    }

    /// A turn landing under a finger is never scrolled to while it holds the view, so it is owed:
    /// the view takes the end once the finger lifts. Wants `WAIN_LATE`, and the first of `WAIN_CHATS`.
    func testATurnUnderAFingerIsFollowedOnRelease() throws {
        guard let late = env["WAIN_LATE"] else { throw XCTSkip("set TEST_RUNNER_WAIN_LATE") }
        let app = try connected()
        let chat = try chats()[0]
        open(app, chat)
        assertAtEnd(app, "\(chat), opened")

        let tag = try land(late)
        // Held through the reconnect, the read and its media. Pushed past the end, since a lift
        // with speed left on it coasts, and coasting away from the end is the reader leaving.
        // In the page's right margin: a video under the finger takes the touch for itself, and
        // the left edge belongs to the swipe back.
        let finger = app.scrollViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.4))
        finger.press(forDuration: 0.1, thenDragTo: finger.withOffset(CGVector(dx: 0, dy: -20)), withVelocity: .slow, thenHoldForDuration: 14)
        XCTAssertTrue(app.staticTexts["Last line of \(tag)."].exists, "the turn never landed")
        assertAtEnd(app, "\(chat), a turn landed under a finger")
    }

    /// Where a text sits, by its label, on screen or off: the stack is eager, so every row has a frame.
    private func top(_ app: XCUIApplication, _ label: String) -> CGFloat {
        guard let tree = try? app.scrollViews.firstMatch.snapshot() else { return .nan }
        func find(_ n: XCUIElementSnapshot) -> XCUIElementSnapshot? {
            n.elementType == .staticText && n.label == label ? n : n.children.lazy.compactMap(find).first
        }
        return find(tree)?.frame.minY ?? .nan
    }

    /// A bot's working line names its running tool on one line, however long the
    /// command. Wants the bot `WAIN_BOT` mid-way through a long Bash call: Claude Code
    /// refuses a long foreground `sleep`, so time it with `ping -c 110 127.0.0.1`.
    func testRunningToolIsOneLine() throws {
        guard let name = env["WAIN_BOT"] else { throw XCTSkip("set TEST_RUNNER_WAIN_BOT") }
        let app = try connected()
        app.tab("Bots")
        let bot = app.buttons["bot.\(name)"]
        XCTAssertTrue(bot.waitForExistence(timeout: 20), "no bot row")
        bot.tap()
        let line = app.descendants(matching: .any)
            .matching(NSPredicate(format: "(label BEGINSWITH 'Running' OR label BEGINSWITH 'Bash') AND label CONTAINS 'deliberately'")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 30), "no running tool line")
        sleep(1)
        snap(app, "running-tool")
        XCTAssertLessThan(line.frame.height, 30, "the running tool's line wraps")
    }

    /// Text inside the transcript's visible frame, a beat after opening and again once the read lands.
    private func assertRowsInView(_ app: XCUIApplication, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        for wait in [1, 4] {
            sleep(UInt32(wait))
            let scroll = app.scrollViews.firstMatch
            guard scroll.waitForExistence(timeout: 5) else { return XCTFail("\(what): no transcript", file: file, line: line) }
            // One snapshot, not a query per text: every row is drawn, so there are hundreds.
            guard let tree = try? scroll.snapshot() else { return XCTFail("\(what): no snapshot", file: file, line: line) }
            let frame = tree.frame
            func texts(_ n: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
                (n.elementType == .staticText ? [n] : []) + n.children.flatMap(texts)
            }
            let seen = texts(tree).contains { t in
                !t.label.isEmpty && frame.intersects(t.frame) && t.frame.minY < frame.maxY - 140
            }
            if !seen { snap(app, "blank-\(what)") }
            XCTAssertTrue(seen, "\(what): nothing in view after \(wait)s", file: file, line: line)
        }
    }

    private func connected() throws -> XCUIApplication {
        guard let url = env["WAIN_URL"], let token = env["WAIN_TOKEN"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_URL and TEST_RUNNER_WAIN_TOKEN")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-servers", ""]
        app.launch()
        var link = URLComponents(string: "wain://connect")!
        link.queryItems = [.init(name: "url", value: url), .init(name: "token", value: token), .init(name: "name", value: "Test Mac")]
        app.open(link.url!)
        let add = app.buttons["Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the link opened no add sheet")
        add.tap()
        // A first launch asks about notifications, over whatever is tapped next.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
