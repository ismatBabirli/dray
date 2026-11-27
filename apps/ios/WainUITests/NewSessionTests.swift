import XCTest

/// Starts a task from New task and sees its first reply, against a scratch
/// `wain-serve`. Attaches the project by path first, so the server needs
/// nothing but a git repo on disk:
///   TEST_RUNNER_WAIN_URL=ws://127.0.0.1:7399 TEST_RUNNER_WAIN_TOKEN=…
///   TEST_RUNNER_WAIN_PROJECT=/tmp/…/repo xcodebuild test -only-testing:WainUITests/NewSessionTests …
///
/// Runs before `SmokeTests`, and leaves it what it wants: a newest session in
/// `manual` stance.
final class NewSessionTests: XCTestCase {
    func testStartSessionAndSeeReply() throws {
        guard let project = ProcessInfo.processInfo.environment["WAIN_PROJECT"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_PROJECT")
        }
        let app = try openNewTask()
        app.openProject()
        snap(app, "1-project")
        app.attach(path: project)

        app.openAgent()
        app.useHaiku()
        app.pick("row.Permissions", "Ask every time")
        snap(app, "2-agent")
        app.back()

        let prompt = app.composer
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("Reply with the single word HELLO and nothing else.")
        snap(app, "2-new-task")
        app.buttons["startTask"].tap()

        let reply = app.staticTexts["HELLO"]
        XCTAssertTrue(reply.waitForExistence(timeout: 120), "reply never landed")
        snap(app, "3-reply")
    }

    /// Clones a repo from the server's GitHub account into `~/wain` — the real
    /// home, not `WAIN_HOME` — so it only runs when handed a small one to clone:
    ///   TEST_RUNNER_WAIN_CLONE=owner/repo
    func testCloneFromGithub() throws {
        guard let slug = ProcessInfo.processInfo.environment["WAIN_CLONE"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_CLONE to a small repo of the server's GitHub account")
        }
        let app = try openNewTask()
        app.openProject()
        app.buttons["Clone from GitHub"].tap()

        // Rows are lazy: one below the fold does not exist until searched for.
        let search = app.searchFields["Search repositories"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText(slug)
        snap(app, "1-searched")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", slug)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 60), "\(slug) not listed")
        snap(app, "1-repos")
        row.tap()
        app.buttons["Clone into ~/wain"].tap()
        snap(app, "2-cloning")

        let name = String(slug.split(separator: "/").last ?? "")
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 120), "clone never attached")
        snap(app, "3-attached")
    }

    private func openNewTask() throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["WAIN_URL"], let token = env["WAIN_TOKEN"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_URL and TEST_RUNNER_WAIN_TOKEN")
        }
        return .openNewTask(url: url, token: token)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

/// New task's steps, shared with `WorktreeBranchTests`.
extension XCUIApplication {
    /// Launches with no saved servers, adds the one under test, and opens New task from Home,
    /// so servers left over from earlier runs cannot change the answer.
    static func openNewTask(url: String, token: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-servers", ""]
        app.launch()
        app.buttons["Enter an address"].tap()
        for (field, text) in [("Address", url), ("Token", token), ("Name", "test")] {
            let f = app.textFields[field]
            XCTAssertTrue(f.waitForExistence(timeout: 5))
            f.tap()
            f.typeText(text)
        }
        app.buttons["Add"].tap()
        // A fresh install asks about notifications once a server is added.
        let deny = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Don’t Allow"]
        if deny.waitForExistence(timeout: 5) { deny.tap() }
        let compose = app.buttons["newTask"]
        XCTAssertTrue(compose.waitForExistence(timeout: 30))
        compose.tap()
        // The Machine row is drawn once the server is connected, which every pick waits on.
        XCTAssertTrue(app.buttons["row.Machine"].waitForExistence(timeout: 30), "server never connected")
        return app
    }

    /// New task's Project row pushes its page.
    func openProject() {
        buttons["row.Project"].tap()
        XCTAssertTrue(navigationBars["Project"].waitForExistence(timeout: 5), "no Project page")
    }

    /// New task's Agent row pushes its page.
    func openAgent() {
        buttons["row.Agent"].tap()
        XCTAssertTrue(navigationBars["Agent"].waitForExistence(timeout: 5), "no Agent page")
    }

    /// Back to New task from a page it pushed.
    func back() {
        navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(buttons["startTask"].waitForExistence(timeout: 5), "not back on New task")
    }

    /// From the Project page: types the folder in, and lands back on New task with it picked.
    func attach(path: String) {
        let row = buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Attach a folder")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no Attach a folder row")
        row.tap()
        let field = alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(path)
        alerts.buttons["Attach"].tap()
        let name = (path as NSString).lastPathComponent
        XCTAssertTrue(buttons["row.Project"].staticTexts[name].waitForExistence(timeout: 15), "project never attached")
    }

    /// A fresh install lists Haiku under More models only, so it is switched on there first.
    func useHaiku() {
        let more = buttons["More models"]
        XCTAssertTrue(more.waitForExistence(timeout: 15), "no model chips")
        let haiku = buttons["Haiku 5.5"]
        if !haiku.exists {
            more.tap()
            let on = switches["Haiku 5.5"]
            XCTAssertTrue(on.waitForExistence(timeout: 5), "no Haiku under More models")
            on.tap()
            buttons[top: "Done"].tap()
        }
        XCTAssertTrue(haiku.waitForExistence(timeout: 5), "no Haiku chip")
        haiku.tap()
    }

    /// Opens a pick menu on the front sheet and walks down it, submenu by submenu.
    func pick(_ menu: String, _ path: String...) {
        buttons[top: menu].tap()
        for option in path {
            let item = buttons[option].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "no \(option) in \(menu)")
            item.tap()
        }
    }
}

extension XCUIElementQuery {
    /// The match on the front sheet: a sheet over New task can hold a row or button of the same name, out of reach.
    subscript(top key: String) -> XCUIElement {
        let all = matching(NSPredicate(format: "identifier == %@ OR label == %@", key, key))
        XCTAssertTrue(all.firstMatch.waitForExistence(timeout: 15), "no \(key)")
        return all.allElementsBoundByIndex.last { $0.isHittable } ?? all.firstMatch
    }
}
