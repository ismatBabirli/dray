import SwiftUI
import ThinkingOrbs

/// Which sessions the list shows: the live ones, saved drafts, or settled ones.
enum ListMode { case live, drafts, settled }

/// A page opened over the list from its top bar.
enum ListPage: Identifiable { case pulls, issues; var id: Self { self } }

/// A task saved for later, as `drafts.json` holds it. Only what a row draws.
struct DraftItem: Decodable, Identifiable {
    let id: String
    let prompt: String
    let projectPath: String?
    let created: String?
    let harness: String?
    let model: String?
    let effort: String?
    let permissionMode: String?
    let fast: Bool?
    let useWorktree: Bool?
    /// Where the worktree starts: a picked branch, or `wain draft new --base`'s.
    let base: String?

    var title: String { prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt }
    var project: String? { projectPath.map { ($0 as NSString).lastPathComponent } }
}

struct SessionList: View {
    @Environment(Store.self) private var store
    @Environment(NewTask.self) private var task
    @Environment(Nav.self) private var nav
    /// An iPad sidebar's project: the list held to it, with no strip.
    var only: String? = nil
    @State private var project: String?
    @State private var mode = ListMode.live
    @State private var drafts: [(server: UUID, draft: DraftItem)] = []
    @State private var shown = Self.pageSize
    /// The pull requests or issues page, opened over the list.
    @State private var listPage: ListPage?
    /// The row whose Delete is waiting on its confirm.
    @State private var deleting: ListRow?

    private static let pageSize = 40

    /// The row on top of this tab's stack, which the list draws as the open one.
    private var selection: Binding<SessionKey?> {
        Binding(get: { if case .session(let k)? = nav.paths[nav.tab]?.first { k } else { nil } },
                set: { key in if let key { nav.open(.session(key)) } })
    }

    /// The runs cut to their first `limit` rows, a nest never split across the cut.
    private func page(_ runs: [(stage: Stage, rows: [ListRow])], _ limit: Int) -> [(stage: Stage, rows: [ListRow])] {
        var left = limit
        var out: [(stage: Stage, rows: [ListRow])] = []
        for run in runs where left > 0 {
            var end = min(left, run.rows.count)
            while end < run.rows.count && run.rows[end].depth > 0 { end += 1 }
            out.append((run.stage, Array(run.rows[..<end])))
            left -= end
        }
        return out
    }

    var body: some View {
        let machines = nav.shownIds(store)
        // One entry per name: the same repo on two machines is one project here.
        var seen = Set<String>()
        let names = nav.shown(store).flatMap { store.projects[$0.id] ?? [] }.map(\.name).filter { seen.insert($0).inserted }
        // A picked project that left the list narrows nothing.
        let filter = only ?? (names.contains { $0 == project } ? project : nil)
        let all = mode == .drafts ? [] : store.runs(project: filter, settled: mode == .settled, servers: machines)
        // Paged: only the first `shown` rows are drawn, more as the last one comes on screen.
        let runs = page(all, shown)
        let more = runs.reduce(0) { $0 + $1.rows.count } < all.reduce(0) { $0 + $1.rows.count }
        // Nested where its parent is listed anywhere: a pinned child draws at depth 0 still holding the link.
        let listed = Set(all.flatMap { $0.rows.map(\.key) })
        let blank = mode == .live && runs.isEmpty
        // A picked filter keeps its strip, or there would be no way back to All.
        let strip = only == nil && names.count > 1 && (filter != nil || !(mode == .drafts ? drafts.isEmpty : all.isEmpty))
        List(selection: selection) {
            // Quiet about reconnects, never about a read that failed or a server waiting on the reader.
            ForEach(nav.shown(store).filter { s in store.health(s.id).map { store.serverState[s.id] == .connected || $0.needsYou } ?? false }) { s in
                if let health = store.health(s.id) {
                    HealthBanner(health: health,
                                 retry: { Task { await store.retry(s.id) } },
                                 fix: { nav.sheet = .settings(server: s.id) })
                        .bannerRow()
                }
            }
            if strip {
                ProjectStrip(names: names, picked: filter) { project = $0 }
                    .padding(.bottom, Theme.Space.m)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .selectionDisabled()
            }
            if mode == .drafts {
                draftRows(filter)
            } else if runs.isEmpty && mode == .settled {
                Text("Nothing settled.").font(Theme.Font.subhead).foregroundStyle(Theme.tertiary)
                    .padding(.leading, 14).frame(height: 44, alignment: .leading)
                    .plainRow()
            }
            // One block per run: the gap between them is the whole signal, never a heading.
            ForEach(Array(runs.enumerated()), id: \.element.stage) { i, run in
                if i > 0 { Color.clear.frame(height: Theme.Space.l).plainRow() }
                // The one run with a heading: nothing else on the rows says why they lead.
                if run.stage == .pinned {
                    // In line with the titles: the rows' 6pt inset and 14pt rail, past this row's own 16.
                    Text("Pinned").font(Theme.Font.footnote).foregroundStyle(Theme.secondary)
                        .padding(.leading, Theme.Space.xs).padding(.bottom, Theme.Space.xs)
                        .plainRow()
                }
                ForEach(Array(run.rows.enumerated()), id: \.element.id) { j, row in
                    // Set aside fades as the desktop sidebar's does, back to full once it is the open one.
                    SessionRow(key: row.key, item: row.item, lines: elbows(run.rows, j))
                        .opacity(run.stage == .aside && selection.wrappedValue != row.key ? 0.3 : 1)
                        .tag(row.key)
                        .sessionRow(selected: selection.wrappedValue == row.key)
                        .contextMenu {
                            RowMenu(row: row, aside: run.stage == .aside || row.item.aside == true,
                                    inheritsPin: run.stage == .pinned && row.depth > 0 && row.item.pinned != true,
                                    nested: row.item.parentSessionId.map { listed.contains(SessionKey(server: row.key.server, id: $0)) } ?? false,
                                    opened: { nav.open(.session($0)) }, delete: { deleting = row })
                        }
                    if mode == .live, let ask = store.asks[row.key]?.first {
                        AskCard(key: row.key, event: ask)
                            .padding(EdgeInsets(top: 2, leading: 14, bottom: Theme.Space.m, trailing: Theme.Space.m))
                            .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 8))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .selectionDisabled()
                    }
                }
            }
            if more {
                // Comes on screen as the reader nears the end, and draws the next page.
                Color.clear.frame(height: 1).plainRow()
                    .onAppear { shown += Self.pageSize }
            }
        }
        .listStyle(.plain)
        // With a hardware keyboard a tap focused the row, and its focus ring drew a white box round it.
        .focusable(false)
        .contentMargins(.top, Theme.Space.m, for: .scrollContent)
        // The breaks between runs are 16pt, under the 44pt a list row otherwise takes.
        .environment(\.defaultMinListRowHeight, 1)
        .themedList()
        .animation(Theme.motion, value: runs.map { $0.rows.map(\.id) })
        .refreshable {
            await store.refresh()
            // Both, whatever the view: a failed read hides a button, and this is the way to retry it.
            await loadDrafts()
            await store.loadSettled()
        }
        .overlay {
            if let blocked = ConnectState(store: store, nav: nav) { blocked } else if blank { empty(filter) }
        }
        // A new view or filter starts on its first page.
        .onChange(of: "\(mode)\(filter ?? "")") { shown = Self.pageSize }
        .page()
        .tabBar(only ?? title) {
            Menu {
                Picker("View", selection: $mode) {
                    Label("Live", systemImage: "circle.fill").tag(ListMode.live)
                    Label("Drafts", systemImage: "circle.dashed").tag(ListMode.drafts)
                    Label("Settled", systemImage: "checkmark").tag(ListMode.settled)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(only ?? title)
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
                }
                .foregroundStyle(Theme.text)
            }
            .accessibilityIdentifier("viewMenu")
        }
        .toolbar { header }
        // Its own stack in a sheet, so a page's own pushes never tangle with the tab's.
        .sheet(item: $listPage) { p in
            NavigationStack {
                switch p {
                case .pulls: PullsView()
                case .issues: IssuesView()
                }
            }
            .presentationBackground(Theme.page)
        }
        // Confirmed apart from the menu, which closes on any pick: the desktop asks in place.
        .confirmationDialog("Delete \u{201C}\(deleting?.item.title ?? "")\u{201D}?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible, presenting: deleting) { row in
            Button("Delete", role: .destructive) {
                Task {
                    guard await store.delete(row.key) else { return Haptic.error() }
                    // Deleting the open one falls back to the list, never a neighbour: the desktop's rule.
                    if selection.wrappedValue == row.key { nav.paths[nav.tab] = [] }
                }
            }
        } message: { _ in
            Text("Its conversation goes for good.")
        }
        // Again once a server comes up: a view opened before it connected read nothing from it.
        // Drafts and settled are read whatever the view, and an empty live list counts what was settled today.
        .task(id: "\(mode) \(store.live.filter { store.serverState[$0.id] == .connected }.count) \(store.draftsRevision)") {
            await loadDrafts()
            await store.loadSettled()
        }
    }

    private var title: String {
        switch mode {
        case .live: "Tasks"
        case .drafts: "Drafts"
        case .settled: "Settled"
        }
    }

    /// The desktop's two pages and New task on the right. The pages show whenever
    /// a machine is on, up or not: both draw their kept lists while one reconnects.
    @ToolbarContentBuilder private var header: some ToolbarContent {
        if !store.machines.isEmpty {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { listPage = .pulls } label: { Image(systemName: "arrow.triangle.pull") }
                    .accessibilityLabel("Pull requests")
                Button { listPage = .issues } label: { Image(systemName: "smallcircle.circle") }
                    .accessibilityLabel("Issues")
            }
        }
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        ToolbarItem(placement: .topBarTrailing) { ComposeButton() }
    }

    @ViewBuilder private func draftRows(_ filter: String?) -> some View {
        let shown = drafts.filter { (filter == nil || $0.draft.project == filter) && nav.shownIds(store).contains($0.server) }
        if shown.isEmpty {
            Text("No drafts.").font(Theme.Font.subhead).foregroundStyle(Theme.tertiary)
                .padding(.leading, 14).frame(height: 44).plainRow()
        }
        ForEach(shown, id: \.draft.id) { entry in
            Button {
                task.open(entry.draft, on: entry.server)
                nav.sheet = .newTask
            } label: {
                RowLine(title: entry.draft.title, time: entry.draft.created.flatMap(parseDate))
            }
            .buttonStyle(RowButtonStyle())
            .sessionRow(selected: false)
        }
    }

    /// Every connected server's drafts, newest first. A server whose read fails keeps what it last
    /// said, so a dropped reply never reads as no drafts.
    private func loadDrafts() async {
        var all: [(server: UUID, draft: DraftItem)] = []
        for s in store.live where store.serverState[s.id] == .connected {
            if let list: [DraftItem] = try? await store.call(s.id, "list_drafts") {
                all += list.map { (s.id, $0) }
            } else {
                all += drafts.filter { $0.server == s.id }
            }
        }
        // A newer read replaced this task, and its reply may land before this one.
        if Task.isCancelled { return }
        drafts = all.sorted { ($0.draft.created ?? "") > ($1.draft.created ?? "") }
    }

    /// The live list with nothing in it: all clear with today's settled work, or nothing started yet.
    @ViewBuilder private func empty(_ filter: String?) -> some View {
        let today = store.runs(project: filter, settled: true, servers: nav.shownIds(store)).flatMap(\.rows)
            .compactMap { r in parseDate(r.item.modified).map { (row: r, at: $0) } }
            .filter { Calendar.current.isDateInToday($0.at) }
        Group {
            if let last = today.max(by: { $0.at < $1.at }) {
                EmptyScreen(art: SettledStack(title: last.row.item.title, time: shortAge(last.at)),
                            title: "All clear", message: today.count == 1 ? "1 settled today." : "\(today.count) settled today.")
            } else if let filter {
                EmptyScreen(art: EmptyArt(kind: .project), title: "Nothing in \(filter)", message: "Tap the compose button to start one.")
            } else {
                EmptyScreen(art: EmptyArt(kind: .tasks), title: "No tasks yet", message: "Tap the compose button to start one.")
            }
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 140)
    }
}

/// For row `i` of a run, whether the connector at each of its depths runs on
/// below it: at its own depth that is a sibling still to come, so the elbow
/// keeps its stem; above it, an ancestor's sibling, so a line passes through.
// ponytail: scans forward per row, O(n²) in a run; runs are tens of rows.
func elbows(_ rows: [ListRow], _ i: Int) -> [Bool] {
    let depth = rows[i].depth
    return (0..<depth).map { level in
        for row in rows[(i + 1)...] {
            if row.depth <= level { return false }
            if row.depth == level + 1 { return true }
        }
        return false
    }
}

extension View {
    /// A list row that is not a session: no inset, no separator, no fill.
    func plainRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Theme.Space.l, bottom: 0, trailing: Theme.Space.l))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .selectionDisabled()
    }

    /// A list banner: the session rows' insets, set in from them as the frames have it.
    func bannerRow() -> some View {
        padding(EdgeInsets(top: 0, leading: 14, bottom: 14, trailing: Theme.Space.xs))
            .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .selectionDisabled()
    }

    /// A session's or a draft's row: the list's own insets, and a fill only where it is the open one.
    func sessionRow(selected: Bool) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(selected ? Theme.selected : .clear)
                    .padding(.horizontal, Theme.Space.xs))
    }
}

/// Every project by name as a chip, All first, the picked one filled. Fades out
/// at the right edge, where a long list runs off.
struct ProjectStrip: View {
    let names: [String]
    let picked: String?
    let pick: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) {
                chip("All", nil)
                ForEach(names, id: \.self) { chip($0, $0) }
            }
            .padding(.horizontal, Theme.Space.l)
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .padding(.top, Theme.Space.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Project filter")
    }

    private func chip(_ label: String, _ value: String?) -> some View {
        Button {
            Haptic.select()
            pick(value)
        } label: {
            Text(label)
                .font(Theme.Font.footnoteStrong)
                .foregroundStyle(picked == value ? Theme.onPrimary : Theme.text)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(picked == value ? Theme.primary : Theme.raised, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked == value ? .isSelected : [])
    }
}

/// A task row's long-press menu: the desktop sidebar's `RowMenu`, each item
/// shown where it shows there. Settle lives here, since a phone row has no
/// hover button to carry it.
private struct RowMenu: View {
    @Environment(Store.self) private var store
    @Environment(\.displayScale) private var scale
    let row: ListRow
    /// Drawn in the set-aside run or flagged aside, so the item turns to Bring back.
    let aside: Bool
    /// In Pinned only through an ancestor: a pin here would move nothing and leave a flag behind.
    let inheritsPin: Bool
    /// Its parent is in the list, so there is a link to cut — the desktop's `isNested`.
    let nested: Bool
    let opened: (SessionKey) -> Void
    let delete: () -> Void

    var body: some View {
        let key = row.key, item = row.item
        let settled = item.archived == true
        // Two because they differ in where the copy runs, not what it copies.
        // Off mid-turn: the copy would inherit half a turn, and the server refuses it too.
        Menu {
            Button("Fork in new worktree") { fork(worktree: true) }
            Button("Fork here") { fork(worktree: false) }
        } label: { Label("Fork", systemImage: "arrow.triangle.branch") }
            .disabled(item.busy)
        // A settled list draws no Pinned run and no aside run, so neither verb would move anything there.
        if !settled && !inheritsPin {
            let pinned = item.pinned == true
            Button(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin") {
                // Pinning an aside row brings it back, or it would stay faded below.
                set(item.aside == true && !pinned ? ["pinned": true, "aside": false] : ["pinned": .bool(!pinned)])
            }
        }
        if !settled {
            Button(aside ? "Bring back" : "Set aside", systemImage: aside ? "tray.and.arrow.up" : "archivebox") {
                // Setting aside unpins, or the row would stay up in Pinned.
                set(aside ? ["aside": false] : ["aside": true, "pinned": false])
            }
        }
        // Only a read, finished session; a lazy fork has run nothing to read.
        if item.status == "idle" && !settled && item.forkFrom == nil {
            Button("Mark unread", systemImage: "circle.fill") { Task { await store.markUnread(key) } }
        }
        // Never mid-turn: settling stops the child, and the turn would die with nothing saying so.
        if settled {
            Button("Unsettle", systemImage: "arrow.uturn.backward") { set(["archived": false]) }
        } else if !item.busy {
            Button("Settle", systemImage: "checkmark") {
                Haptic.success()
                set(["archived": true])
            }
        }
        if nested {
            Button("Detach from parent", systemImage: "scissors") { Task { await store.detach(key) } }
        }
        // One bot is named on the item itself; a submenu only where there is a choice.
        let bots = store.attachTargets(key, item)
        if bots.count == 1, let bot = bots.first {
            Button { attach(bot) } label: { Label { Text("Attach to \(bot.name)") } icon: { face(bot) } }
        } else if !bots.isEmpty {
            Menu {
                ForEach(bots, id: \.id) { bot in
                    Button { attach(bot) } label: { Label { Text(bot.name) } icon: { face(bot) } }
                }
            } label: { Label("Attach to bot", systemImage: "link") }
        }
        Button("Delete", systemImage: "trash", role: .destructive, action: delete)
    }

    private func set(_ flags: [String: JSON]) { Task { await store.setFlags(row.key, flags) } }

    private func attach(_ bot: Bot) { Task { await store.attach(row.key, to: bot) } }

    private func face(_ bot: Bot) -> Image { faceImage(bot, size: 22, scale: scale) }

    private func fork(worktree: Bool) {
        Task { if let key = await store.fork(row.key, worktree: worktree) { opened(key) } }
    }
}

/// One line of the list: rail, elbows, title, and the trailing slot.
struct SessionRow: View {
    @Environment(Store.self) private var store
    let key: SessionKey
    let item: SessionItem
    /// Per depth, whether the connector runs on below this row (`elbows`).
    let lines: [Bool]

    var body: some View {
        let pr = store.prMark(key, item)
        RowLine(title: item.title.isEmpty ? "Untitled" : item.title, time: parseDate(item.modified),
                rail: store.isAsking(key) ? Theme.accent : item.status == "completed" ? Theme.add : nil,
                lines: lines, pr: pr,
                checks: pr?.state == "OPEN" && pr?.checksState == "RUNNING", working: item.busy,
                offline: store.lost.contains(key.server))
    }
}

/// The row's drawing, shared by sessions and drafts. The trailing slot holds
/// what outranks the time — running checks, then the orb — since "last
/// activity" is the least useful thing to say of a row with anything in flight.
struct RowLine: View {
    let title: String
    let time: Date?
    var rail: Color? = nil
    var lines: [Bool] = []
    var pr: PrMark? = nil
    var checks = false
    var working = false
    /// Its server has been down a while: the row is what it last answered, so nothing on it is live.
    var offline = false

    var body: some View {
        HStack(spacing: 0) {
            // The desktop rail's marks: yellow waits on the reader, green is finished and unread.
            ZStack {
                if let rail { RoundedRectangle(cornerRadius: 1.5).fill(rail).frame(width: 2.5, height: 12) }
            }
            .frame(width: 14)
            ForEach(Array(lines.enumerated()), id: \.offset) { level, runsOn in
                Elbow(own: level == lines.count - 1, runsOn: runsOn)
            }
            if let pr { PrGlyph(mark: pr, size: 15).padding(.trailing, 6) }
            Text(title)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.text.opacity(0.88))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if offline {
                    // The desktop's offline mark, never the orb: nobody can say it is still working.
                    Image(systemName: "wifi.slash").font(Theme.Font.footnote.font).foregroundStyle(Theme.tertiary)
                        .accessibilityLabel("Server unreachable")
                } else if checks {
                    ChecksSpinner().frame(width: 15, height: 15)
                } else if working {
                    Orb(.working, label: "Working")
                } else if let time {
                    Text(shortAge(time))
                        .font(Theme.Font.footnote.font.monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(minWidth: 36, alignment: .trailing)
        }
        .frame(height: 44)
        .padding(.trailing, Theme.Space.m)
        .contentShape(.rect)
    }
}

/// One depth of a child's connector, solid #404040: the elbow into the row at
/// its own depth, a straight line where an ancestor's sibling is still to come.
private struct Elbow: View {
    /// This row's own depth, which draws the curve into the title.
    let own: Bool
    let runsOn: Bool

    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            if runsOn {
                p.move(to: CGPoint(x: 6, y: 0))
                p.addLine(to: CGPoint(x: 6, y: size.height))
            }
            if own {
                p.move(to: CGPoint(x: 6, y: runsOn ? 12 : 0))
                if !runsOn { p.addLine(to: CGPoint(x: 6, y: 12)) }
                p.addQuadCurve(to: CGPoint(x: 16, y: 22), control: CGPoint(x: 6, y: 22))
                p.addLine(to: CGPoint(x: 20, y: 22))
            }
            ctx.stroke(p, with: .color(Theme.connector), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        .frame(width: 24, height: 44)
        .accessibilityHidden(true)
    }
}
