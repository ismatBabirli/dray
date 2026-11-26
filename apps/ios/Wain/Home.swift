import SwiftUI
import ThinkingOrbs

/// "What wants me?" across every bot and task on the shown machines: usage,
/// then what waits on the reader, what is working, and what is new since they
/// looked. Each section hides when empty; all empty is All clear.
struct HomeView: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    @AppStorage(StallDismissals.key) private var dismissedRaw = ""

    var body: some View {
        // Stalls ripen with time alone, so Home files again each minute.
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            let sections = homeSections(store.homeFacts(nav.shownIds(store), now: tick.date, dismissed: dismissed))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    UsageChips().padding(.bottom, Theme.Space.s)
                    ForEach(nav.shown(store).filter { s in store.health(s.id).map { store.serverState[s.id] == .connected || $0.needsYou } ?? false }) { s in
                        if let health = store.health(s.id) {
                            HealthBanner(health: health, retry: { Task { await store.retry(s.id) } },
                                         fix: { nav.sheet = .settings(server: s.id) })
                                .padding(.horizontal, Theme.Space.l).padding(.bottom, Theme.Space.m)
                        }
                    }
                    if !sections.waiting.isEmpty {
                        heading("Waiting on you", count: sections.waiting.count, tone: Theme.accent)
                        VStack(spacing: Theme.Space.s) { ForEach(sections.waiting) { WaitingRow(row: $0) } }
                            .padding(.horizontal, Theme.Space.l)
                    }
                    if !sections.working.isEmpty {
                        heading("Working")
                        VStack(spacing: 0) { ForEach(sections.working) { HomeLine(key: $0.key, working: true) } }
                            .padding(.horizontal, Theme.Space.s)
                    }
                    if !sections.new.isEmpty {
                        heading("New since you looked")
                        VStack(spacing: 0) { ForEach(sections.new) { HomeLine(key: $0.key, working: false) } }
                            .padding(.horizontal, Theme.Space.s)
                    }
                }
                .padding(.top, Theme.Space.xs)
                .padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .animation(Theme.motion, value: sections)
            }
            .refreshable { await store.refresh() }
            .overlay {
                if let blocked = ConnectState(store: store, nav: nav) {
                    blocked
                } else if sections.isEmpty {
                    AllClear()
                }
            }
        }
        .page()
        .tabBar("Home")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ComposeButton() } }
        // Bots' tasks are hidden, so no list reads their repos' marks, and a ready PR would never show.
        .task(id: store.allBots.count) {
            let tasks = store.allBots.flatMap { store.botTasks(store.botChat($0.server, $0.bot)) }
            let repos = Set(tasks.compactMap { key in store.items[key].map { ProjectKey(server: key.server, path: $0.projectPath) } })
            for repo in repos { await store.ensureMarks(repo.server, repo.path) }
        }
    }

    private var dismissed: Set<String> { StallDismissals.parse(dismissedRaw) }

    private func heading(_ title: String, count: Int? = nil, tone: Color = Theme.secondary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.Font.footnoteStrong).foregroundStyle(tone)
            Spacer()
            if let count { Text("\(count)").font(Theme.Font.footnote.font.monospacedDigit()).foregroundStyle(Theme.tertiary) }
        }
        .padding(.horizontal, 20)
        .padding(.top, Theme.Space.l)
        .padding(.bottom, Theme.Space.s)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The stall card's X: rows the reader put away, which Home and its badge leave out too.
enum StallDismissals {
    static let key = "bot.dismissedStalls"
    static func parse(_ raw: String) -> Set<String> { Set(raw.split(separator: "\n").map(String.init)) }
}

extension Store {
    /// Every session Home could file, on the shown machines: the visible tasks, each bot's
    /// chat, and the bots' hidden tasks for what they wait on.
    func homeFacts(_ shown: Set<UUID>, now: Date = .now, dismissed: Set<String> = []) -> [HomeFact] {
        func ready(_ key: SessionKey, _ item: SessionItem) -> Bool {
            guard let pr = prMark(key, item), pr.state == "OPEN", !pr.isDraft else { return false }
            return verdictOf(pr) == .ready
        }
        func at(_ item: SessionItem) -> Date { parseDate(item.modified) ?? .distantPast }
        var facts: [SessionKey: HomeFact] = [:]
        let bots = allBots.filter { shown.contains($0.server) }
        let chats = Set(bots.flatMap { botChat($0.server, $0.bot) })
        for (key, item) in items where shown.contains(key.server) && !covered.contains(key.server) && known(key.server)
            && item.archived != true && item.hidden != true && item.routineRun == nil && !chats.contains(key) {
            facts[key] = HomeFact(key: key, modified: at(item), asking: isAsking(key), readyPr: ready(key, item),
                                  busy: item.busy, unread: item.status == "completed")
        }
        for b in bots {
            let chat = botChat(b.server, b.bot)
            if let key = chat.last, let item = items[key] {
                facts[key] = HomeFact(key: key, modified: at(item), bot: true, asking: isAsking(key), busy: item.busy,
                                      unread: item.status == "completed")
            }
            let tasks = botTasks(chat)
            let stalls = (judgedStalls(b.server, botId: b.bot.id, tasks: tasks, now: now) ?? self.stalls(tasks, now: now))
                .filter { $0.held && !dismissed.contains($0.id) }
            let quiet = Set(stalls.filter { !$0.ready }.map(\.task))
            for key in tasks where facts[key] == nil {
                guard let item = items[key], item.archived != true, item.aside != true else { continue }
                facts[key] = HomeFact(key: key, modified: at(item), hidden: true, asking: isAsking(key),
                                      readyPr: ready(key, item), stalled: quiet.contains(key))
            }
        }
        return Array(facts.values)
    }

    /// Home's badge: its Waiting on you rows, one per session, read as Home reads them.
    func waitingCount(_ shown: Set<UUID>, dismissed: Set<String>) -> Int {
        homeSections(homeFacts(shown, dismissed: dismissed)).waiting.count
    }

    /// Bots' badge: bots with a reply the reader has not read.
    func unreadBots(_ shown: Set<UUID>) -> Int {
        allBots.filter { shown.contains($0.server) }.filter { b in
            botChat(b.server, b.bot).last.flatMap { items[$0] }?.status == "completed"
        }.count
    }
}

/// A card waiting on the reader: its question answered in place, a PR merged from it,
/// or a bot's task gone quiet. Its head opens the task.
private struct WaitingRow: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    let row: HomeRow

    var body: some View {
        let key = row.key
        let item = store.items[key]
        let bot = store.bot(key)
        let title = bot?.name ?? (item?.title.isEmpty == false ? item!.title : "Untitled")
        VStack(alignment: .leading, spacing: 10) {
            switch row {
            case .ask:
                Button { nav.open(.session(key)) } label: { head(title, item, dot: true) }.buttonStyle(RowButtonStyle())
                // Every card the session holds, in the one row it has.
                ForEach(store.asks[key] ?? []) { AskCard(key: key, event: $0, bare: true) }
            case .merge:
                mergeRow(key, item, title)
            default:
                Button { nav.open(.session(key)) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        head(title, item, dot: true)
                        Text(item?.need?.text ?? "Waiting for your reply").font(Theme.Font.subhead).foregroundStyle(Theme.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(RowButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.tile, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("waiting")
    }

    private func head(_ title: String, _ item: SessionItem?, dot: Bool) -> some View {
        HStack(spacing: Theme.Space.s) {
            if dot { Circle().fill(Theme.accent).frame(width: 8, height: 8) }
            Text(title).font(Theme.Font.pill).foregroundStyle(Theme.text).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let item {
                Text([store.bot(row.key) == nil ? item.project : nil, parseDate(item.modified).map { shortAge($0) }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.Font.footnote).foregroundStyle(Theme.tertiary).lineLimit(1)
            }
        }
        .contentShape(.rect)
    }

    @ViewBuilder private func mergeRow(_ key: SessionKey, _ item: SessionItem?, _ title: String) -> some View {
        if let item, let pr = store.prMark(key, item) {
            HStack(spacing: 10) {
                Button { nav.open(.session(key)) } label: {
                    HStack(spacing: 10) {
                        BotFace(seed: key.id, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title).font(Theme.Font.pill).foregroundStyle(Theme.text).lineLimit(1)
                            HStack(spacing: 5) {
                                PrGlyph(mark: pr, size: 13)
                                Text("#\(String(pr.number)) · Ready to merge").font(Theme.Font.footnote).foregroundStyle(Theme.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(RowButtonStyle())
                MergeTaskButton(server: key.server, taskId: key.id, cwd: item.projectPath, number: pr.number, branch: pr.headRefName)
                    .fixedSize()
            }
            .padding(.vertical, -2)
        }
    }
}

/// A working or newly finished row: a bot's face and its line, or a task's title.
private struct HomeLine: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    let key: SessionKey
    let working: Bool

    var body: some View {
        let item = store.items[key]
        Button { nav.open(.session(key)) } label: {
            HStack(spacing: Theme.Space.m) {
                if let bot = store.bot(key) {
                    let preview = store.previews[key]
                    BotFace(bot: bot, size: 32)
                        .overlay(alignment: .topTrailing) {
                            if !working, let n = preview?.replies, n > 0 {
                                Text("\(n)").font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.onBadge)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(Theme.unread, in: Capsule())
                                    .overlay(Capsule().stroke(Theme.page, lineWidth: 2))
                                    .offset(x: 3, y: -3)
                            }
                        }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(bot.name).font(Theme.Font.body.font.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        let line = preview.flatMap { $0.plain == true ? $0.text : nil } ?? previewLine(preview?.text ?? "")
                        if working && line.isEmpty {
                            TypingDots().frame(height: 18)
                        } else if !line.isEmpty {
                            Text(line).font(Theme.Font.footnote).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                    }
                } else {
                    Group {
                        if working { Orb(.working) } else { Color.clear }
                    }
                    .frame(width: 20, height: 20)
                    Text(item?.title.isEmpty == false ? item!.title : "Untitled")
                        .font(working ? Theme.Font.body.font : Theme.Font.body.font.weight(.semibold))
                        .foregroundStyle(Theme.text).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let at = item.flatMap({ parseDate($0.modified) }) {
                    Text(shortAge(at)).font(Theme.Font.footnote.font.monospacedDigit()).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: store.bot(key) == nil ? 48 : 52)
            .contentShape(.rect)
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityIdentifier(working ? "working" : "new")
    }
}

/// Home with nothing on it: nothing waits, nothing runs.
private struct AllClear: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav

    var body: some View {
        let settled = store.runs(project: nil, settled: true, servers: nav.shownIds(store)).flatMap(\.rows)
            .filter { parseDate($0.item.modified).map(Calendar.current.isDateInToday) ?? false }.count
        EmptyScreen(art: RingsArt(symbol: "checkmark", tone: Theme.add), title: "All clear",
                    message: "Nothing waits on you and nothing is running."
                        + (settled == 0 ? "" : settled == 1 ? " 1 task settled today." : " \(settled) tasks settled today.")) {
            Button { nav.sheet = .newTask } label: {
                Label("New task", systemImage: "square.and.pencil")
            }
            .buttonStyle(EmptyCapsuleStyle(kind: .retry))
            .background(Theme.raised, in: Capsule())
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 80)
    }
}

/// The compose button at the top right of Home and Tasks.
struct ComposeButton: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav

    var body: some View {
        Button { nav.sheet = .newTask } label: { Image(systemName: "square.and.pencil") }
            .disabled(store.machines.isEmpty)
            .accessibilityLabel("New task")
            .accessibilityIdentifier("newTask")
    }
}

/// An empty tab's mark: two faint rings round a tile holding the tab's symbol.
struct RingsArt: View {
    let symbol: String
    var tone = Theme.text

    var body: some View {
        ZStack {
            Circle().stroke(Theme.hairline, lineWidth: 1).frame(width: 180, height: 180)
            Circle().stroke(Theme.hairline, lineWidth: 1).frame(width: 120, height: 120)
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(tone)
                .frame(width: 64, height: 64)
                .background(Theme.card, in: .rect(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
        }
        .frame(width: 180, height: 180)
        .accessibilityHidden(true)
    }
}

/// A tab's whole body while nothing it shows can be reached: no machine paired, every one
/// off, connecting, offline, or one that can't be reached with its countdown. Nil once
/// any shown machine has answered.
struct ConnectState: View {
    let store: Store
    let nav: Nav

    init?(store: Store, nav: Nav) {
        let shown = nav.shown(store)
        guard shown.isEmpty || !shown.contains(where: { store.serverState[$0.id] == .connected && store.read($0.id) }) else { return nil }
        self.store = store
        self.nav = nav
    }

    var body: some View {
        let shown = nav.shown(store)
        Group {
            if shown.isEmpty && !store.servers.isEmpty {
                EmptyScreen(art: EmptyArt(kind: .connect), title: "Every machine is off",
                            message: "Turn one back on in Settings to see its tasks.") {
                    Button("Open Settings") { nav.sheet = .settings(server: nil) }
                        .buttonStyle(EmptyCapsuleStyle(kind: .dark))
                        .padding(.top, Theme.Space.xs)
                }
            } else if shown.isEmpty {
                EmptyScreen(art: EmptyArt(kind: .connect), title: "Pair a machine",
                            message: "Your agents run on a Mac or a server. Pair one to start.") {
                    VStack(spacing: 10) {
                        Button { nav.sheet = .add(nil, scan: true) } label: {
                            HStack(spacing: Theme.Space.s) { QRCodeIcon(); Text("Scan QR code") }
                        }
                        .buttonStyle(EmptyCapsuleStyle(kind: .light))
                        Button("Enter an address") { nav.sheet = .add(nil, scan: false) }
                            .buttonStyle(EmptyCapsuleStyle(kind: .dark))
                        Text("On your Mac: Settings → Servers → Pair a phone. On a server, run `wain server pair`.")
                            .font(Theme.Font.footnote).foregroundStyle(Theme.tertiary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Theme.Space.s)
                    }
                    .padding(.top, Theme.Space.xs)
                }
            } else if shown.allSatisfy({ if case .connecting(0)? = store.serverState[$0.id] { true } else { false } }) {
                EmptyScreen(art: EmptyArt(kind: .connecting), title: "Connecting", message: shown.map(\.name).joined(separator: ", "))
            } else if !store.online {
                EmptyScreen(art: EmptyArt(kind: .unreachable), title: "You're offline", message: "Tasks keep running on their machines.")
            } else if let p = shown.lazy.compactMap({ s in store.health(s.id).map { (s, $0) } }).first(where: { !$0.1.working }) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    EmptyScreen(art: EmptyArt(kind: .unreachable), title: p.1.title, message: message(p.1, at: context.date)) {
                        if let action = p.1.action {
                            Button(action == .fix ? "Fix" : "Retry now") {
                                Haptic.tap()
                                if action == .fix { nav.sheet = .settings(server: p.0.id) } else { Task { await store.retry(p.0.id) } }
                            }
                            .buttonStyle(EmptyCapsuleStyle(kind: .retry))
                        }
                    }
                }
            } else {
                EmptyScreen(art: EmptyArt(kind: .connecting), title: "Connecting", message: shown.map(\.name).joined(separator: ", "))
            }
        }
        .padding(.horizontal, Theme.Space.xxl)
        .padding(.bottom, 80)
        .page()
    }

    private func message(_ health: Health, at now: Date) -> String {
        guard let until = health.until else { return health.detail ?? "Check that it's awake and online." }
        let left = Int(until.timeIntervalSince(now).rounded(.up))
        return (left > 0 ? "Trying again in \(left)s." : "Trying again…") + " Check that it's awake and online."
    }
}
