import XCTest

/// New task's branch picks against a scratch `wain-serve` and a repo holding a
/// branch in every place the worktree picker sorts by: main behind its remote,
/// `feature/remote-only`, `local-only`, `shared` in both and just behind, and
/// `local-two` for the checkout switch, with an untracked file to make it ask.
/// `scripts/worktree_branch_seed.sh <dir>` makes it at `<dir>/repo`. The trees
/// each start made are checked on the server's side afterwards (`git worktree list`).
///   TEST_RUNNER_WAIN_URL=… TEST_RUNNER_WAIN_TOKEN=… TEST_RUNNER_WAIN_PROJECT=<dir>/repo \
///   xcodebuild test -only-testing:WainUITests/WorktreeBranchTests …
/// Runs in name order: the last start needs `local-two` checked out by the one before.
/// Every start runs a real turn on Haiku.
final class WorktreeBranchTests: XCTestCase {
    func test1RemoteOnly() throws { try start(from: "feature/remote-only", search: "rem") }
    func test2LocalOnly() throws { try start(from: "local-only") }
    func test3Shared() throws { try start(from: "shared") }
    func test4Main() throws { try start(from: "main") }

    /// Worktree off: the branch row switches the checkout, asking first about the untracked file.
    func test5SwitchCheckout() throws {
        let app = try openNewTask()
        setWorktree(app, on: false)
        let row = app.buttons[top: "row.Branch"]
        row.tap()
        let item = app.buttons["local-two"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        let bring = app.buttons["Bring changes"]
        XCTAssertTrue(bring.waitForExistence(timeout: 10), "no uncommitted-changes question")
        snap(app, "5-dirty-question")
        bring.tap()
        XCTAssertTrue(row.staticTexts["local-two"].waitForExistence(timeout: 15), "checkout never switched")
        snap(app, "5-switched")
    }

    /// `local-two` is now the project folder's own branch, so its tree is detached.
    func test6HeldElsewhere() throws { try start(from: "local-two") }

    /// Back from the branch list, the sheet's title sits where it was, not under an empty bar.
    func test0BackKeepsSheet() throws {
        let app = try openNewTask()
        setWorktree(app, on: true)
        let bar = app.navigationBars["New task"]
        let top = bar.frame.minY
        app.buttons["row.Start from"].tap()
        XCTAssertTrue(app.navigationBars["Start from"].waitForExistence(timeout: 5))
        // Picked from a search, which is what left the bar behind.
        let field = app.searchFields["Filter branches"]
        field.tap()
        field.typeText("ma")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "main")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Start from"].waitForNonExistence(timeout: 5))
        sleep(1)
        snap(app, "0-back")
        XCTAssertEqual(bar.frame.minY, top, accuracy: 2, "sheet moved down after the page")
    }

    private func start(from branch: String, search: String? = nil) throws {
        let app = try openNewTask()
        setWorktree(app, on: true)
        let row = app.buttons["row.Start from"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no Start from row")
        row.tap()
        XCTAssertTrue(app.navigationBars["Start from"].waitForExistence(timeout: 5))
        snap(app, "\(branch)-list")
        if let search {
            let field = app.searchFields["Filter branches"]
            field.tap()
            field.typeText(search)
            snap(app, "\(branch)-search")
        }
        let pick = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", branch)).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 5), "\(branch) not listed")
        pick.tap()
        XCTAssertTrue(row.staticTexts[branch].waitForExistence(timeout: 5), "row does not say \(branch)")
        snap(app, "\(branch)-picked")
        app.openAgent()
        app.useHaiku()
        app.back()

        let prompt = app.composer
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("Reply OK. case=\(branch)")
        app.buttons["startTask"].tap()
        let sent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "case=\(branch)")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 60), "task never started")
        snap(app, "\(branch)-started")
    }

    /// Launches with only the server under test, and opens New task on the
    /// project, attaching it by path the first time.
    private func openNewTask() throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["WAIN_URL"], let token = env["WAIN_TOKEN"], let project = env["WAIN_PROJECT"] else {
            throw XCTSkip("set TEST_RUNNER_WAIN_URL, TEST_RUNNER_WAIN_TOKEN and TEST_RUNNER_WAIN_PROJECT")
        }
        let app = XCUIApplication.openNewTask(url: url, token: token)
        let name = (project as NSString).lastPathComponent
        if !app.buttons["row.Project"].staticTexts[name].waitForExistence(timeout: 5) {
            app.openProject()
            let row = app.buttons[name]
            if row.waitForExistence(timeout: 5) { row.tap() } else { app.attach(path: project) }
        }
        return app
    }

    private func setWorktree(_ app: XCUIApplication, on: Bool) {
        let toggle = app.switches[top: "Worktree"]
        let isOn = ["On", "1"].contains(toggle.value as? String ?? "")
        if isOn != on { toggle.tap() }
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
