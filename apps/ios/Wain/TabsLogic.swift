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
    var fiveHour: Window? { windows.first { $0.kind == "five_hour" } }
    /// The window that says how close the agent is: five-hour, else the fullest it sent.
    var headline: Window? { fiveHour ?? windows.max { $0.usedPercent < $1.usedPercent } }
    /// Spent: the server says so, or a window is full.
    var atLimit: Bool { limited == true || windows.contains { $0.usedPercent >= 100 } }
    /// When a spent reading comes back: the full window's reset, else five-hour's.
    var back: Date? {
        (windows.first { $0.usedPercent >= 100 } ?? fiveHour)?.resetsAt.flatMap(parseDate)
    }
}

/// One agent's chip on Home: its worst reading across the machines shown.
struct UsageChip: Equatable, Identifiable {
    let harness: String
    let percent: Double
    let limited: Bool
    /// When a limited agent is back: the soonest any of its machines is.
    let back: Date?
    var id: String { harness }
}

/// One chip per agent with a reading: the highest five-hour percent across the
/// machines, red with its way back once any machine is at its limit. Limited
/// ones lead, then the fullest.
func usageChips(_ readings: [UsageReading]) -> [UsageChip] {
    let byAgent = Dictionary(grouping: readings, by: \.harness)
    let chips = byAgent.map { harness, list -> UsageChip in
        let spent = list.filter(\.atLimit)
        let percent = list.compactMap { $0.headline?.usedPercent }.max() ?? 0
        return UsageChip(harness: harness, percent: spent.isEmpty ? percent : max(percent, 100), limited: !spent.isEmpty,
                         back: spent.compactMap(\.back).min())
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
