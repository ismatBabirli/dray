import Foundation

// The rules the four tabs and the usage chips file things by, kept apart from
// any view so `WainTests` can hold them to the rules both phone apps follow.

// MARK: Home

/// What Home knows of one session, read off the store: enough to file it.
struct HomeFact {
    let key: SessionKey
    let modified: Date
    /// A bot's chat rather than a task.
    var bot = false
    /// A bot's task the lists leave out: it counts only while it waits on the reader.
    var hidden = false
    var asking = false
    /// An open PR GitHub calls ready, the Tasks sheet's rule.
    var readyPr = false
    /// A bot's task gone quiet on the reader (its bot's stall card).
    var stalled = false
    var busy = false
    /// Finished and not yet looked at.
    var unread = false
}

/// One row on Home and why it is there.
enum HomeRow: Hashable, Identifiable {
    case ask(SessionKey), merge(SessionKey), stall(SessionKey), working(SessionKey), new(SessionKey)
    var id: Self { self }
    var key: SessionKey {
        switch self { case .ask(let k), .merge(let k), .stall(let k), .working(let k), .new(let k): k }
    }
}

struct HomeSections: Equatable {
    var waiting: [HomeRow] = []
    var working: [HomeRow] = []
    var new: [HomeRow] = []
    var isEmpty: Bool { waiting.isEmpty && working.isEmpty && new.isEmpty }
}

/// Home's three sections, newest first in each: what waits on the reader (a card,
/// a PR ready to merge, a bot's task gone quiet), what is mid-turn, and what
/// finished unread. A session is filed once, the first section that holds it.
func homeSections(_ facts: [HomeFact]) -> HomeSections {
    var out = HomeSections()
    for f in facts.sorted(by: { $0.modified > $1.modified }) {
        if f.asking { out.waiting.append(.ask(f.key)) }
        else if f.readyPr && !f.bot { out.waiting.append(.merge(f.key)) }
        else if f.stalled { out.waiting.append(.stall(f.key)) }
        else if f.hidden { continue }
        else if f.busy { out.working.append(.working(f.key)) }
        else if f.unread { out.new.append(.new(f.key)) }
    }
    return out
}

// MARK: Bots

/// One bot as the roster orders it.
struct BotFact {
    let id: String
    var waiting = false
    var unread = false
    var working = false
    var active: Date?
}

/// The roster's order: waiting on the reader, unread, working, the rest; newest activity first within each.
func botOrder(_ bots: [BotFact]) -> [String] {
    func rank(_ b: BotFact) -> Int { b.waiting ? 0 : b.unread ? 1 : b.working ? 2 : 3 }
    return bots.enumerated().sorted { a, b in
        let (ra, rb) = (rank(a.element), rank(b.element))
        if ra != rb { return ra < rb }
        let (ta, tb) = (a.element.active ?? .distantPast, b.element.active ?? .distantPast)
        return ta != tb ? ta > tb : a.offset < b.offset
    }.map(\.element.id)
}

// MARK: Routines

/// Every bot's routines in one list: soonest next run first, one with no run
/// scheduled after those, paused ones last; ties keep the order they came in.
func routineOrder<T>(_ rows: [T], paused: (T) -> Bool, next: (T) -> Date?) -> [T] {
    rows.enumerated().sorted { a, b in
        let (pa, pb) = (paused(a.element), paused(b.element))
        if pa != pb { return !pa }
        let (na, nb) = (next(a.element) ?? .distantFuture, next(b.element) ?? .distantFuture)
        return na != nb ? na < nb : a.offset < b.offset
    }.map(\.element)
}

// MARK: Usage

extension UsageReading {
    /// A window's figure: as sent, or spent where a limited reading sent none.
    func used(_ w: Window) -> Double? { w.usedPercent ?? (limited == true ? 100 : nil) }
    var fiveHour: Window? { windows.first { $0.kind == "five_hour" } }
    /// The window the reading speaks by: five-hour, else its fullest. Never one with no figure.
    var headline: Window? {
        if let f = fiveHour, used(f) != nil { return f }
        return windows.filter { used($0) != nil }.max { used($0)! < used($1)! }
    }
    var percent: Double { headline.flatMap(used) ?? 0 }
    var spent: [Window] { windows.filter { (used($0) ?? 0) >= 100 } }
    /// Spent: the server says so, or a window is full.
    var atLimit: Bool { limited == true || !spent.isEmpty }
    /// When it is back: the latest reset of its spent windows, else its headline's.
    var back: Date? {
        spent.compactMap { $0.resetsAt.flatMap(parseDate) }.max() ?? headline?.resetsAt.flatMap(parseDate)
    }
}

/// One agent's chip on Home.
struct UsageChip: Equatable, Identifiable {
    let harness: String
    let percent: Double
    let limited: Bool
    let back: Date?
    var id: String { harness }
}

/// One chip per agent with a reading, spoken for by its worst reading across the shown
/// machines: one at its limit first, then the highest headline percent. Nothing is mixed
/// across machines. Limited chips lead, then the fullest.
func usageChips(_ readings: [UsageReading]) -> [UsageChip] {
    let worse = { (a: UsageReading, b: UsageReading) in a.atLimit != b.atLimit ? a.atLimit : a.percent > b.percent }
    let chips = Dictionary(grouping: readings, by: \.harness).compactMap { harness, list -> UsageChip? in
        guard let r = list.sorted(by: worse).first else { return nil }
        return UsageChip(harness: harness, percent: r.percent, limited: r.atLimit, back: r.back)
    }
    return chips.sorted { a, b in
        if a.limited != b.limited { return a.limited }
        return a.percent != b.percent ? a.percent > b.percent : a.harness < b.harness
    }
}

/// A window's name in the Usage sheet: "5-hour", "Weekly", else its length in days.
func windowLabel(_ w: UsageReading.Window) -> String {
    switch w.kind {
    case "five_hour": return "5-hour"
    case "weekly": return "Weekly"
    default:
        guard let m = w.minutes, m > 0 else { return "Other" }
        return m % 1440 == 0 ? "\(m / 1440)-day" : m % 60 == 0 ? "\(m / 60)-hour" : "\(m)-minute"
    }
}
