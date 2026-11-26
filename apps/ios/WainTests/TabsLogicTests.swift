import XCTest
@testable import Wain

/// The four tabs' filing rules and the usage chips, as the phone apps' shared rules state them.
final class TabsLogicTests: XCTestCase {
    private let server = UUID()
    private func key(_ id: String) -> SessionKey { SessionKey(server: server, id: id) }
    private func at(_ minutes: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60) }

    // MARK: Home

    func testHomeFilesEachSessionOnceNewestFirst() {
        let s = homeSections([
            HomeFact(key: key("old-ask"), modified: at(1), asking: true),
            HomeFact(key: key("new-ask"), modified: at(9), asking: true, busy: true),
            HomeFact(key: key("merge"), modified: at(5), readyPr: true, busy: true),
            HomeFact(key: key("quiet"), modified: at(4), hidden: true, stalled: true),
            HomeFact(key: key("working"), modified: at(3), busy: true),
            HomeFact(key: key("bot"), modified: at(8), bot: true, busy: true),
            HomeFact(key: key("done"), modified: at(2), unread: true),
            HomeFact(key: key("read"), modified: at(7)),
        ])
        XCTAssertEqual(s.waiting, [.ask(key("new-ask")), .merge(key("merge")), .stall(key("quiet")), .ask(key("old-ask"))])
        XCTAssertEqual(s.working, [.working(key("bot")), .working(key("working"))])
        XCTAssertEqual(s.new, [.new(key("done"))])
    }

    /// A bot's hidden task shows only while it waits on the reader; its bot's own row says the rest.
    func testHiddenTasksOnlyWait() {
        let s = homeSections([
            HomeFact(key: key("a"), modified: at(1), hidden: true, busy: true),
            HomeFact(key: key("b"), modified: at(2), hidden: true, unread: true),
            HomeFact(key: key("c"), modified: at(3), hidden: true, readyPr: true),
        ])
        XCTAssertEqual(s.waiting, [.merge(key("c"))])
        XCTAssertTrue(s.working.isEmpty)
        XCTAssertTrue(s.new.isEmpty)
    }

    /// A bot's chat has no PR of its own to merge.
    func testBotChatNeverMerges() {
        let s = homeSections([HomeFact(key: key("chat"), modified: at(1), bot: true, readyPr: true, unread: true)])
        XCTAssertEqual(s.new, [.new(key("chat"))])
        XCTAssertTrue(s.waiting.isEmpty)
    }

    func testAllClear() {
        XCTAssertTrue(homeSections([HomeFact(key: key("idle"), modified: at(1))]).isEmpty)
    }

    // MARK: Bots

    func testBotOrder() {
        let order = botOrder([
            BotFact(id: "rest-old", active: at(1)),
            BotFact(id: "working", working: true, active: at(2)),
            BotFact(id: "unread", unread: true, working: true, active: at(3)),
            BotFact(id: "waiting", waiting: true, unread: true, active: at(0)),
            BotFact(id: "rest-new", active: at(5)),
            BotFact(id: "never"),
        ])
        XCTAssertEqual(order, ["waiting", "unread", "working", "rest-new", "rest-old", "never"])
    }

    // MARK: Routines

    func testRoutineOrder() {
        struct R { let id: String; let paused: Bool; let next: Date? }
        let rows = [
            R(id: "paused-soon", paused: true, next: at(1)),
            R(id: "later", paused: false, next: at(60)),
            R(id: "unscheduled", paused: false, next: nil),
            R(id: "soon", paused: false, next: at(5)),
            R(id: "paused-late", paused: true, next: at(90)),
        ]
        let ordered = routineOrder(rows, paused: \.paused, next: \.next).map(\.id)
        XCTAssertEqual(ordered, ["soon", "later", "unscheduled", "paused-soon", "paused-late"])
    }

    // MARK: Usage

    private func reading(_ harness: String, five: Double?, weekly: Double? = nil, limited: Bool? = nil, resets: String = "2026-11-26T14:00:00Z") -> UsageReading {
        var windows: [UsageReading.Window] = []
        if let five { windows.append(.init(kind: "five_hour", usedPercent: five, resetsAt: resets, minutes: 300)) }
        if let weekly { windows.append(.init(kind: "weekly", usedPercent: weekly, resetsAt: "2026-12-01T09:00:00Z", minutes: 10080)) }
        return UsageReading(harness: harness, limited: limited, at: "2026-11-26T12:00:00Z", windows: windows)
    }

    /// One reading speaks for each agent: its worst across machines. Limited agents lead, then the fullest.
    func testChipsTakeTheWorstReading() {
        let chips = usageChips([
            reading("codex", five: 49),
            reading("claude_code", five: 30),
            reading("claude_code", five: 84),
            reading("pi", five: 60, limited: true, resets: "2026-11-26T15:30:00Z"),
        ])
        XCTAssertEqual(chips.map(\.harness), ["pi", "claude_code", "codex"])
        XCTAssertEqual(chips[1].percent, 84)
        XCTAssertFalse(chips[1].limited)
        XCTAssertTrue(chips[0].limited)
        XCTAssertEqual(chips[0].percent, 60, "the limited reading's own headline, not 100")
        XCTAssertEqual(chips[0].back, parseDate("2026-11-26T15:30:00Z"))
    }

    /// A limited reading outranks a fuller one elsewhere, and nothing from the other machine is mixed in.
    func testLimitedReadingSpeaksAlone() {
        let chips = usageChips([
            reading("claude_code", five: 95, resets: "2026-11-26T13:00:00Z"),
            reading("claude_code", five: 40, limited: true, resets: "2026-11-26T16:00:00Z"),
        ])
        XCTAssertEqual(chips.count, 1)
        XCTAssertTrue(chips[0].limited)
        XCTAssertEqual(chips[0].percent, 40)
        XCTAssertEqual(chips[0].back, parseDate("2026-11-26T16:00:00Z"))
    }

    /// A full window is a limit whatever `limited` says; "back" is the latest of the spent windows' resets.
    func testBackIsTheLatestSpentReset() {
        let r = reading("claude_code", five: 100, weekly: 100, resets: "2026-11-26T14:00:00Z")
        XCTAssertTrue(r.atLimit)
        XCTAssertEqual(r.back, parseDate("2026-12-01T09:00:00Z"))
        let chip = usageChips([r])[0]
        XCTAssertTrue(chip.limited)
        XCTAssertEqual(chip.percent, 100)
    }

    /// Not at a limit, "back" is the headline window's reset.
    func testBackFallsToTheHeadline() {
        XCTAssertEqual(reading("claude_code", five: 20, weekly: 60).back, parseDate("2026-11-26T14:00:00Z"))
    }

    /// With no five-hour window the fullest window stands in.
    func testNoFiveHourWindow() {
        XCTAssertEqual(usageChips([reading("claude_code", five: nil, weekly: 75)])[0].percent, 75)
    }

    /// A window with no figure: spent on a limited reading, never the headline on any other.
    func testWindowWithNoFigure() throws {
        let json = """
        [{"harness":"claude_code","limited":true,"at":"2026-11-26T12:00:00Z",
          "windows":[{"kind":"five_hour","resetsAt":"2026-11-26T15:30:00Z","minutes":300}]},
         {"harness":"codex","at":"2026-11-26T12:00:00Z",
          "windows":[{"kind":"five_hour","resetsAt":"2026-11-26T15:00:00Z","minutes":300},
                     {"kind":"weekly","usedPercent":12,"resetsAt":"2026-12-01T09:00:00Z","minutes":10080}]}]
        """
        let list = try JSONDecoder().decode([UsageReading].self, from: Data(json.utf8))
        let rejected = list[0]
        XCTAssertEqual(rejected.windows.count, 1, "a window with no figure still decodes")
        XCTAssertEqual(rejected.used(rejected.windows[0]), 100)
        XCTAssertTrue(rejected.atLimit)
        XCTAssertEqual(rejected.back, parseDate("2026-11-26T15:30:00Z"))
        let codex = list[1]
        XCTAssertNil(codex.used(codex.windows[0]))
        XCTAssertEqual(codex.headline?.kind, "weekly")
        XCTAssertEqual(codex.percent, 12)
        XCTAssertFalse(codex.atLimit)
        let chips = usageChips(list)
        XCTAssertEqual(chips.map(\.harness), ["claude_code", "codex"])
        XCTAssertEqual(chips[0].back, parseDate("2026-11-26T15:30:00Z"))
    }

    func testWindowLabels() {
        XCTAssertEqual(windowLabel(.init(kind: "five_hour", usedPercent: 1, resetsAt: nil, minutes: 300)), "5-hour")
        XCTAssertEqual(windowLabel(.init(kind: "weekly", usedPercent: 1, resetsAt: nil, minutes: 10080)), "Weekly")
        XCTAssertEqual(windowLabel(.init(kind: "other", usedPercent: 1, resetsAt: nil, minutes: 43200)), "30-day")
    }

    /// The contract's shape, an unknown field, a window missing its percent (kept, with no figure) and a
    /// reading missing its harness (dropped alone).
    func testUsageDecodesLeniently() throws {
        let json = """
        {"asks":[],"tasks":[],"usage":[
          {"harness":"claude_code","plan":"max","limited":false,"overage":"rejected","usingOverage":false,
           "at":"2026-11-26T12:04:00Z","future":1,
           "windows":[{"kind":"five_hour","usedPercent":84.0,"resetsAt":"2026-11-26T14:00:00Z","minutes":300},
                      {"kind":"weekly","resetsAt":"2026-12-01T09:00:00Z","minutes":10080}]},
          {"plan":"plus","at":"2026-11-26T12:04:00Z","windows":[]},
          {"harness":"codex","at":"2026-11-26T11:00:00Z","windows":[{"kind":"other","usedPercent":3,"minutes":43200}]}
        ]}
        """
        let live = try JSONDecoder().decode(LiveState.self, from: Data(json.utf8))
        let usage = (live.usage ?? []).compactMap(\.value)
        XCTAssertEqual(usage.map(\.harness), ["claude_code", "codex"])
        XCTAssertEqual(usage[0].windows.count, 2)
        XCTAssertNil(usage[0].windows[1].usedPercent)
        XCTAssertEqual(usage[0].plan, "max")
        XCTAssertEqual(usage[0].overage, "rejected")
        XCTAssertNil(usage[1].limited)
        let older = try JSONDecoder().decode(LiveState.self, from: Data(#"{"asks":[],"tasks":[]}"#.utf8))
        XCTAssertNil(older.usage)
    }
}

/// A routine's report-back heads the bot's reply with its routine's name; a task's draws nothing, as before.
final class RoutineLabelTests: XCTestCase {
    private func events(_ lines: [(String, String)]) throws -> [AgentEvent] {
        try lines.map { id, payload in
            try JSONDecoder().decode(AgentEvent.self, from: Data(#"{"id":"\#(id)","sessionId":"s","ts":"2026-11-27T09:01:00Z","subagent":null,"payload":\#(payload)}"#.utf8))
        }
    }

    func testRoutineReportDrawsItsLabel() throws {
        let lines = [
            ("r", #"{"type":"user_message","text":"[from Morning PR sweep] two PRs","from":{"title":"Morning PR sweep","sessionId":"RUN-1","machine":null,"routine":true}}"#),
            ("a", #"{"type":"assistant_text","text":"Two PRs wait on your review."}"#),
            ("t", #"{"type":"user_message","text":"[from Fix login] done","from":{"title":"Fix login","sessionId":"task-1"}}"#),
            ("b", #"{"type":"assistant_text","text":"The login fix is in."}"#),
        ]
        let items = botItems(try events(lines), routines: ["run-1"])
        XCTAssertEqual(items.map(\.id), ["r", "a", "b"])
        guard case .routine(_, let name, let ts) = items[0] else { return XCTFail("no routine label") }
        XCTAssertEqual(name, "Morning PR sweep")
        XCTAssertEqual(ts, "2026-11-27T09:01:00Z")
        XCTAssertEqual(botItems(try events(lines)).map(\.id), ["a", "b"], "with no routine runs held, no label")
    }
}
