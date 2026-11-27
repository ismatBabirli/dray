import XCTest

/// The #825 screens on the four tabs against a real server: pairs through a
/// `wain://connect` link, then walks Tasks, a session, New task and its pages, and
/// the empty states, attaching a screenshot of each. Export them with
/// `xcrun xcresulttool export attachments`. Against the homes
/// `scripts/redesign_seed.py` makes, `studio` first and `empty` second; its
/// docstring says which live sessions to start before which test.
///   TEST_RUNNER_WAIN_URL=ws://127.0.0.1:… TEST_RUNNER_WAIN_TOKEN=… \
///   TEST_RUNNER_WAIN_EMPTY_URL=ws://127.0.0.1:… TEST_RUNNER_WAIN_EMPTY_TOKEN=… \
///   xcodebuild test -only-testing:WainUITests/RedesignTests …
final class RedesignTests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    func testScreens() throws {
        let app = try pair()
        sleep(3)
        snap(app, "home")
        app.tab("Tasks")
        let row = labelled(app, "Check the Xcode version")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no session listed")
        sleep(2)
        snap(app, "list")
        view(app, "Drafts")
        XCTAssertTrue(labelled(app, "Add retry with backoff to the upload client").waitForExistence(timeout: 10), "no draft listed")
        snap(app, "list-drafts")
        view(app, "Settled")
        XCTAssertTrue(labelled(app, "Port tools.ts labels to Swift").waitForExistence(timeout: 10), "no settled session listed")
        snap(app, "list-settled")
        view(app, "Live")
        app.buttons["thinking-orbs"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "the strip narrowed nothing")
        sleep(1)
        snap(app, "list-project")
        // A project with no task: the strip shows only while some other project has one.
        app.buttons["notes"].tap()
        XCTAssertTrue(app.staticTexts["Nothing in notes"].waitForExistence(timeout: 10), "no empty project")
        snap(app, "list-project-empty")
        app.buttons["thinking-orbs"].tap()
        labelled(app, "Fix flaky reconnect test").tap()
        XCTAssertTrue(app.composer.waitForExistence(timeout: 15), "the session never opened")
        sleep(3)
        snap(app, "session")
    }

    /// Answers both cards in place: the permission under its row in Tasks, the question on
    /// Home. Wants `redesign_seed.py live allow question` just before, and spends both.
    func testAnswerInline() throws {
        let app = try pair()
        let allow = app.buttons["Allow once"]
        XCTAssertTrue(app.staticTexts["Waiting on you"].waitForExistence(timeout: 20), "nothing waits on Home")
        XCTAssertTrue(allow.waitForExistence(timeout: 20), "no permission card on Home")
        XCTAssertTrue(labelled(app, "iPhone SE").exists, "no question card on Home")
        sleep(2)
        snap(app, "home-cards")
        app.tab("Tasks")
        XCTAssertTrue(allow.waitForExistence(timeout: 10), "no permission card in the list")
        sleep(1)
        snap(app, "list-cards")
        allow.tap()
        XCTAssertTrue(allow.waitForNonExistence(timeout: 15), "the permission card stayed")
        app.tab("Home")
        labelled(app, "iPhone SE").tap()
        app.buttons["Next"].tap()
        XCTAssertTrue(labelled(app, "Should I post screenshots on the PR?").waitForExistence(timeout: 5))
        sleep(1)
        labelled(app, "Yes").tap()
        app.buttons["Send"].tap()
        XCTAssertTrue(app.buttons["Send"].waitForNonExistence(timeout: 15), "the question card stayed")
        sleep(3)
        snap(app, "answered")
    }

    /// A new task by voice: tap the mic to record, Cancel throws it away, record again and
    /// stop, edit the words, then start it. Wants the microphone granted; something saying
    /// words near the Mac's microphone gives words, and the simulator's Apple dictation,
    /// which cannot read audio, gives a note instead.
    func testVoiceTask() throws {
        let app = try pair()
        let compose = app.buttons["newTask"]
        XCTAssertTrue(compose.waitForExistence(timeout: 20), "no New task button")
        sleep(2)
        compose.tap()
        let mic = app.buttons["mic"]  // not its symbol, which carries the same identifier
        XCTAssertTrue(mic.waitForExistence(timeout: 10), "the new task has no mic")
        snap(app, "voice-rest")
        mic.tap()
        let done = app.buttons["dictationDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "tapping the mic started no recording")
        sleep(3)
        snap(app, "voice-recording")
        stripCancel(app).tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Cancel kept recording")
        XCTAssertFalse(app.staticTexts["Discard this recording?"].exists, "Cancel asked first")
        mic.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the second tap started no recording")
        sleep(4)
        done.tap()
        snap(app, "voice-transcribing")
        let start = app.buttons["startTask"]
        let spoke = heard(app, "voice") { start.isEnabled }
        app.composer.tap()
        app.composer.typeText(spoke ? " Reply with the single word: done." : "Reply with the single word: done.")
        snap(app, "voice-edit")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Keep this task?"].waitForExistence(timeout: 3), "Cancel with words asked nothing")
        snap(app, "voice-ready-confirm")
        // On a phone the dialog is a popover off Cancel, and its Keep editing is a tap outside it.
        let keep = app.buttons["Keep editing"]
        if keep.exists { keep.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.36)).tap() }
        XCTAssertTrue(app.staticTexts["Keep this task?"].waitForNonExistence(timeout: 3), "the dialog stayed")
        sleep(1)
        start.tap()
        XCTAssertTrue(start.waitForNonExistence(timeout: 60), "the task never started")
        XCTAssertTrue(app.composer.waitForExistence(timeout: 15), "the started task did not open")
        sleep(4)
        snap(app, "voice-started")
    }

    /// Opens a session from Tasks, scrolled clear of the tab bar first.
    func openRow(_ app: XCUIApplication, _ title: String) {
        app.tab("Tasks")
        let row = labelled(app, title)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no row \(title)")
        // The bar floats over the list, so a row behind it still reads as hittable and the tap lands on a tab.
        let bar = app.tabBars.firstMatch
        let clear = { row.exists && row.isHittable && row.frame.maxY < bar.frame.minY - 20 }
        for _ in 0..<8 where !clear() { app.swipeUp() }
        if !clear() { app.swipeDown(velocity: .slow) }
        XCTAssertTrue(clear(), "no row to open")
        row.tap()
        XCTAssertTrue(app.composer.waitForExistence(timeout: 20), "the session never opened")
    }

    /// A server going bad under an open session, then the list: reconnecting, can't reach,
    /// needs an update, token refused. Wants `/tmp/wain825-proxy.py` in front of the server:
    ///   TEST_RUNNER_WAIN_PROXY_URL=ws://127.0.0.1:… TEST_RUNNER_WAIN_PROXY_MODE=/tmp/…
    func testConnectionBanners() throws {
        guard let proxy = env["WAIN_PROXY_URL"], let modeFile = env["WAIN_PROXY_MODE"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_PROXY_URL and TEST_RUNNER_WAIN_PROXY_MODE")
        }
        let mode = { (m: String) in try? m.write(toFile: modeFile, atomically: true, encoding: .utf8) }
        mode("forward")
        defer { mode("forward") }
        let app = try pair(url: proxy)
        openRow(app, "Tighten session row spacing")
        sleep(2)
        snap(app, "conn-session-ok")

        mode("hang")
        XCTAssertTrue(app.staticTexts["Reconnecting to Studio Mac…"].waitForExistence(timeout: 30), "no reconnecting banner")
        sleep(1)
        snap(app, "conn-session-reconnecting")

        mode("down")
        let unreachable = app.staticTexts["Can't reach Studio Mac"]
        XCTAssertTrue(unreachable.waitForExistence(timeout: 60), "no can't-reach banner")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Trying again'")).firstMatch.exists)
        snap(app, "conn-session-unreachable")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        // With nothing reachable, the list gives its whole screen to saying so.
        XCTAssertTrue(unreachable.waitForExistence(timeout: 5), "the list says nothing of the server")
        sleep(1)
        snap(app, "conn-list-unreachable")

        mode("older")
        app.buttons["Retry now"].tap()
        XCTAssertTrue(app.staticTexts["Studio Mac needs an update"].waitForExistence(timeout: 30), "no needs-update screen")
        sleep(1)
        snap(app, "conn-list-older")

        mode("token")
        app.buttons["Retry now"].tap()
        XCTAssertTrue(app.staticTexts["Studio Mac refused the token"].waitForExistence(timeout: 30), "no token screen")
        sleep(1)
        snap(app, "conn-list-token")
        app.buttons["Fix"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Paste a new token"].waitForExistence(timeout: 10)
            || app.textFields["Token"].waitForExistence(timeout: 1), "Fix opened no settings")
    }

    /// No network: the session says its task keeps running, and Tasks says it once for all.
    /// The simulator follows the Mac's network, so `-offline` only tells the app it is
    /// offline, and the server has to go for real: the harness watches for the stop file,
    /// then stops it. Spends the server, so run it last.
    ///   TEST_RUNNER_WAIN_STOP_FILE=/tmp/…
    func testOfflineBanners() throws {
        guard let stopAt = env["WAIN_STOP_FILE"] else { throw XCTSkip("set TEST_RUNNER_WAIN_STOP_FILE") }
        let app = try pair(offline: true)
        openRow(app, "Tighten session row spacing")
        FileManager.default.createFile(atPath: stopAt, contents: nil)
        XCTAssertTrue(app.staticTexts["The task keeps running on Studio Mac."].waitForExistence(timeout: 60),
                      "the session says nothing of being offline")
        sleep(1)
        snap(app, "conn-session-offline")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["You're offline"].waitForExistence(timeout: 10), "Tasks says nothing of being offline")
        XCTAssertTrue(app.staticTexts["Tasks keep running on their machines."].exists)
        sleep(1)
        snap(app, "conn-list-offline")
    }

    /// A session's foot: the mic records and Cancel throws it away, a recording's words or
    /// note, typing, Send, Stop while the turn runs, and This task from the model chip.
    func testReplyDock() throws {
        let app = try pair()
        openRow(app, "Tighten session row spacing")
        let mic = app.buttons["mic"]  // not its symbol, which carries the same identifier
        XCTAssertTrue(mic.waitForExistence(timeout: 10), "no mic in the composer")
        sleep(3)
        snap(app, "reply-rest")

        mic.tap()
        let done = app.buttons["dictationDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "tapping the mic started no recording")
        sleep(2)
        snap(app, "reply-recording")
        stripCancel(app).tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Cancel kept recording")
        mic.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        sleep(3)
        done.tap()
        snap(app, "reply-transcribing")
        let spoke = heard(app, "reply") { app.buttons["send"].exists }

        app.composer.tap()
        if spoke { app.composer.clearText() }
        app.composer.typeText("Run `sleep 20` in the shell, then reply with the single word SLEPT.")
        snap(app, "reply-ready")
        app.buttons["send"].tap()

        let stop = app.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 60), "no Stop while the turn runs")
        sleep(2)
        snap(app, "reply-running")
        app.buttons["Model"].tap()
        XCTAssertTrue(app.staticTexts["This task"].waitForExistence(timeout: 5), "the model pick opened no sheet")
        sleep(1)
        snap(app, "reply-this-task")
        app.buttons["Done"].tap()
        XCTAssertTrue(stop.waitForNonExistence(timeout: 180), "the turn never ended")
        sleep(2)
        snap(app, "reply-answered")
    }

    /// New task's Agent and Project pages, and a branch switch over uncommitted files.
    /// Wants `thinking-orbs` on the server holding a `fix-reconnect` branch and dirty files.
    func testNewTaskPages() throws {
        let app = try pair()
        let compose = app.buttons["newTask"]
        XCTAssertTrue(compose.waitForExistence(timeout: 20))
        sleep(2)
        compose.tap()
        let agent = app.buttons["row.Agent"]
        XCTAssertTrue(agent.waitForExistence(timeout: 10), "New task has no Agent row")
        snap(app, "picks-new-task")
        app.openAgent()
        XCTAssertTrue(app.buttons["More models"].waitForExistence(timeout: 15), "no model chips")
        XCTAssertFalse(app.buttons["row.Machine"].exists, "the Agent page asks for the machine again")
        sleep(1)
        snap(app, "picks-agent")
        app.back()

        app.openProject()
        let orbs = app.buttons["thinking-orbs"]
        XCTAssertTrue(orbs.waitForExistence(timeout: 5), "no thinking-orbs on the Project page")
        XCTAssertTrue(app.buttons["Clone from GitHub"].exists, "no Clone from GitHub on the Project page")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Attach a folder")).firstMatch.exists)
        snap(app, "picks-project-page")
        orbs.tap()
        XCTAssertTrue(app.buttons["row.Project"].staticTexts["thinking-orbs"].waitForExistence(timeout: 5), "the pick never landed")

        let worktree = app.switches["Worktree"]
        if worktree.value as? String == "On" { worktree.tap() }
        let branch = app.buttons["row.Branch"]
        XCTAssertTrue(branch.waitForExistence(timeout: 10), "worktree off shows no branch row")
        snap(app, "picks-branch")
        branch.tap()
        menuItem(app, "fix-reconnect").tap()
        let bring = app.buttons["Bring changes"]
        XCTAssertTrue(bring.waitForExistence(timeout: 5), "uncommitted files asked nothing")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'uncommitted files'")).count > 0)
        snap(app, "picks-dirty")
        bring.tap()
        XCTAssertTrue(app.staticTexts["fix-reconnect"].waitForExistence(timeout: 15), "the checkout never landed")
        snap(app, "picks-switched")
        // Back as it was, for the next run.
        branch.tap()
        menuItem(app, "main").tap()
        app.buttons["Bring changes"].tap()
        XCTAssertTrue(app.staticTexts["main"].waitForExistence(timeout: 15))
        worktree.tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["startTask"].waitForNonExistence(timeout: 5))
    }

    /// An open menu's item: the last of its name, since the sheet under it can hold the same one.
    private func menuItem(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let all = app.buttons.matching(NSPredicate(format: "label == %@", label))
        _ = all.firstMatch.waitForExistence(timeout: 5)
        sleep(1)
        return last(all)
    }

    /// The last hittable match: the one on the sheet on top.
    private func last(_ query: XCUIElementQuery) -> XCUIElement {
        query.allElementsBoundByIndex.last { $0.isHittable } ?? query.firstMatch
    }

    /// Typing a task from scratch, then saving it as a draft from Cancel, and opening it again from Drafts.
    func testTypeAndSaveDraft() throws {
        let app = try pair()
        let compose = app.buttons["newTask"]
        XCTAssertTrue(compose.waitForExistence(timeout: 20))
        sleep(2)
        compose.tap()
        let editor = app.composer
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Add retry with backoff to the upload client")
        snap(app, "type-new")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Keep this task?"].waitForExistence(timeout: 3), "Cancel with words asked nothing")
        snap(app, "type-confirm")
        app.buttons["Save draft"].tap()
        XCTAssertTrue(app.buttons["startTask"].waitForNonExistence(timeout: 10), "saving left the sheet open")
        app.tab("Tasks")
        view(app, "Drafts")
        sleep(2)
        snap(app, "type-drafts")
        // Opening it brings its words back to the New task sheet, ready to start.
        labelled(app, "Add retry with backoff to the upload client").tap()
        XCTAssertTrue(app.buttons["startTask"].waitForExistence(timeout: 10), "the draft opened nothing")
        XCTAssertEqual(app.composer.value as? String, "Add retry with backoff to the upload client", "the draft's words did not come back")
        snap(app, "type-draft-opened")
    }

    /// Anything on screen by its label: a row's title is read off its button, not a static text.
    func labelled(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Tasks' title menu, then one of its views.
    private func view(_ app: XCUIApplication, _ name: String) {
        app.buttons["viewMenu"].tap()
        let item = app.buttons[name]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "no \(name) in the view menu")
        item.tap()
    }

    /// The dictation strip's Cancel, below a sheet's own Cancel where there is one.
    private func stripCancel(_ app: XCUIApplication) -> XCUIElement {
        let all = app.buttons.matching(NSPredicate(format: "label == 'Cancel'")).allElementsBoundByIndex
        return all.max { $0.frame.minY < $1.frame.minY } ?? app.buttons["Cancel"]
    }

    /// Waits on a recording's outcome: words (`words` holds), or a note in their place, whose
    /// kept recording is discarded once shot. The simulator's Apple dictation cannot read
    /// audio and notes "Couldn't transcribe"; a silent Mac microphone gives "No words heard.".
    private func heard(_ app: XCUIApplication, _ shot: String, words: () -> Bool) -> Bool {
        let note = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH 'Couldn' OR label == 'No words heard.' OR label == 'No sound reached the microphone.'"))
        for _ in 0..<90 where !words() && note.count == 0 { sleep(1) }
        let spoke = words()
        XCTAssertTrue(spoke || note.count > 0, "transcription never answered")
        sleep(1)
        snap(app, spoke ? "\(shot)-words" : "\(shot)-no-words")
        if !spoke, app.buttons["Discard"].exists { app.buttons["Discard"].tap() }
        return spoke
    }

    /// The Tasks list with nothing in it, from no server to a quiet one. Wants a second server
    /// with no sessions behind `/tmp/wain825-proxy.py`, and two projects on it, `thinking-orbs`
    /// one of them: redesign_seed.py's `empty` home with its index emptied.
    ///   TEST_RUNNER_WAIN_EMPTY_URL=ws://127.0.0.1:… TEST_RUNNER_WAIN_EMPTY_TOKEN=… TEST_RUNNER_WAIN_EMPTY_MODE=/tmp/…
    func testEmptyStates() throws {
        guard let url = env["WAIN_EMPTY_URL"], let token = env["WAIN_EMPTY_TOKEN"], let modeFile = env["WAIN_EMPTY_MODE"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_EMPTY_URL, TEST_RUNNER_WAIN_EMPTY_TOKEN and TEST_RUNNER_WAIN_EMPTY_MODE")
        }
        let mode = { (m: String) in try? m.write(toFile: modeFile, atomically: true, encoding: .utf8) }
        mode("hang")
        defer { mode("forward") }
        let app = XCUIApplication()
        app.launchArguments = ["-servers", ""]
        app.launch()
        XCTAssertTrue(app.staticTexts["Pair a machine"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Scan QR code"].exists && app.buttons["Enter an address"].exists)
        XCTAssertFalse(app.composer.exists, "a composer before any server")
        XCTAssertFalse(app.buttons["newTask"].isEnabled, "New task with no machine to run it")
        sleep(1)
        snap(app, "empty-01-connect")

        connect(app, url: url, token: token)
        XCTAssertTrue(app.staticTexts["Connecting"].waitForExistence(timeout: 15), "no connecting screen")
        sleep(1)
        snap(app, "empty-02-connecting")

        mode("down")
        XCTAssertTrue(app.staticTexts["Can't reach Studio Mac"].waitForExistence(timeout: 60), "no can't-reach screen")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Trying again'")).firstMatch.exists)
        snap(app, "empty-03-unreachable")

        // Gone while a try of its own is out, back once it fails.
        let retry = app.buttons["Retry now"]
        XCTAssertTrue(retry.waitForExistence(timeout: 30), "no Retry now")
        mode("forward")
        retry.tap()
        XCTAssertTrue(app.staticTexts["All clear"].waitForExistence(timeout: 30), "no quiet Home once connected")
        app.tab("Tasks")
        XCTAssertTrue(app.staticTexts["No tasks yet"].waitForExistence(timeout: 10), "no empty list once connected")
        // Nothing listed in any project, so nothing to narrow; testScreens draws "Nothing in notes".
        XCTAssertFalse(app.buttons["thinking-orbs"].exists, "a project strip over an empty list")
        sleep(1)
        snap(app, "empty-04-no-tasks")
    }

    /// The quiet server once a task was settled there today: Home and Tasks both say All clear.
    func testAllClear() throws {
        guard let url = env["WAIN_EMPTY_URL"], let token = env["WAIN_EMPTY_TOKEN"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_EMPTY_URL and TEST_RUNNER_WAIN_EMPTY_TOKEN")
        }
        let app = try pair(url: url, token: token)
        let settled = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'settled today.'")).firstMatch
        XCTAssertTrue(app.staticTexts["All clear"].waitForExistence(timeout: 30), "no all-clear Home")
        sleep(1)
        snap(app, "empty-06-all-clear-home")
        app.tab("Tasks")
        XCTAssertTrue(app.staticTexts["All clear"].waitForExistence(timeout: 10), "no all-clear Tasks")
        XCTAssertTrue(app.staticTexts["1 settled today."].waitForExistence(timeout: 10), "Tasks does not count today's settled task")
        sleep(1)
        snap(app, "empty-06-all-clear")
        app.tab("Home")
        XCTAssertTrue(settled.waitForExistence(timeout: 5), "Home does not count today's settled task")
    }

    /// Switching a server off on the phone: its tasks leave Tasks, Settings reads Off, and on brings them back.
    func testServerOff() throws {
        guard let url2 = env["WAIN_EMPTY_URL"], let token2 = env["WAIN_EMPTY_TOKEN"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_EMPTY_URL and TEST_RUNNER_WAIN_EMPTY_TOKEN")
        }
        let app = try pair()
        app.tab("Tasks")
        let row = app.staticTexts["Tighten session row spacing"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "no task from Studio Mac")
        // Through Settings, not a second link: opening one relaunches the app, and its launch
        // arguments clear the server just paired.
        settings(app)
        app.buttons["Add server"].tap()
        let address = app.textFields["Address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        address.typeText("\(url2) \(token2)")
        app.textFields["Name"].tap()
        app.textFields["Name"].typeText("Build Box")
        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Build Box"].waitForExistence(timeout: 10), "Build Box wasn't added")

        app.staticTexts["Studio Mac"].firstMatch.tap()
        let on = app.switches["server.on"]
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 10), "no live state in the switch row")
        sleep(1)
        snap(app, "server-08-on")

        on.tap()
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Off'")).firstMatch.waitForExistence(timeout: 5), "the switch row never read Off")
        XCTAssertTrue(app.staticTexts["Its tasks are hidden until you turn it back on. They keep running on Studio Mac."].exists)
        sleep(1)
        snap(app, "server-09-off")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Off · '")).firstMatch
            .waitForExistence(timeout: 5), "Settings doesn't say the server is off")
        sleep(1)
        snap(app, "settings-01d-off")

        app.buttons["Done"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10), "the off server's task stayed in Tasks")
        sleep(1)
        snap(app, "server-list-off")

        settings(app)
        app.staticTexts["Studio Mac"].firstMatch.tap()
        on.tap()
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Connected'")).firstMatch.waitForExistence(timeout: 30), "turning it on never reconnected")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the task didn't come back")
    }

    /// Settings, reached through Machines, settled before anything in it is tapped:
    /// a tap while Machines gives way to it opens nothing.
    private func settings(_ app: XCUIApplication) {
        app.buttons["machines"].firstMatch.tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Machines opened no Settings")
        sleep(1)
    }

    /// A fresh launch with no saved server, paired through the link a QR carries.
    func pair(url: String? = nil, token: String? = nil, offline: Bool = false) throws -> XCUIApplication {
        guard let url = url ?? env["WAIN_URL"], let token = token ?? env["WAIN_TOKEN"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_URL and TEST_RUNNER_WAIN_TOKEN")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-servers", ""] + (offline ? ["-offline"] : [])
        app.launch()
        connect(app, url: url, token: token)
        return app
    }

    /// Adds a server through the link a QR carries, then turns down the alerts prompt a fresh install raises.
    func connect(_ app: XCUIApplication, url: String, token: String, name: String = "Studio Mac") {
        var link = URLComponents(string: "wain://connect")!
        link.queryItems = [.init(name: "url", value: url), .init(name: "token", value: token), .init(name: "name", value: name)]
        app.open(link.url!)
        let add = app.buttons["Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the link opened no add sheet")
        add.tap()
        let deny = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Don’t Allow"]
        if deny.waitForExistence(timeout: 3) { deny.tap() }
    }

    func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
