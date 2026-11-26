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

    /// The worst five-hour reading per agent across machines; limited agents lead, then the fullest.
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
        XCTAssertEqual(chips[0].back, parseDate("2026-11-26T15:30:00Z"))
    }

    /// A full window is a limit whatever `limited` says, and its own reset is the way back.
    func testFullWindowIsALimit() {
        let r = reading("claude_code", five: 20, weekly: 100)
        XCTAssertTrue(r.atLimit)
        XCTAssertEqual(r.back, parseDate("2026-12-01T09:00:00Z"))
        let chip = usageChips([r])[0]
        XCTAssertTrue(chip.limited)
        XCTAssertEqual(chip.percent, 100)
    }

    /// With no five-hour window the fullest window stands in.
    func testNoFiveHourWindow() {
        XCTAssertEqual(usageChips([reading("claude_code", five: nil, weekly: 75)])[0].percent, 75)
    }

    func testWindowLabels() {
        XCTAssertEqual(windowLabel(.init(kind: "five_hour", usedPercent: 1, resetsAt: nil, minutes: 300)), "5-hour")
        XCTAssertEqual(windowLabel(.init(kind: "weekly", usedPercent: 1, resetsAt: nil, minutes: 10080)), "Weekly")
        XCTAssertEqual(windowLabel(.init(kind: "other", usedPercent: 1, resetsAt: nil, minutes: 43200)), "30-day")
    }

    /// The contract's shape, an unknown field, a window missing its percent and a reading missing its harness:
    /// each costs itself alone.
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
        XCTAssertEqual(usage[0].windows.count, 1)
        XCTAssertEqual(usage[0].plan, "max")
        XCTAssertEqual(usage[0].overage, "rejected")
        XCTAssertNil(usage[1].limited)
        let older = try JSONDecoder().decode(LiveState.self, from: Data(#"{"asks":[],"tasks":[]}"#.utf8))
        XCTAssertNil(older.usage)
    }
}
