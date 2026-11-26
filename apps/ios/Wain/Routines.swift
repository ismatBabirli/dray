import SwiftUI

/// One routine with the bot that runs it.
struct BotRoutine: Identifiable {
    let server: UUID
    let bot: Bot
    var routine: Routine
    var id: String { "\(server.uuidString)/\(routine.id)" }
}

/// Every routine of every bot on the shown machines, soonest next run first and
/// paused ones last. The switch pauses one, a long press deletes it, a tap opens
/// its bot. Making or changing one is asked of the bot, as on the desktop.
struct RoutinesView: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    @State private var routines: [BotRoutine] = []
    @State private var read = false
    @State private var error: String?
    @State private var deleting: BotRoutine?

    var body: some View {
        let shown = nav.shownIds(store)
        let rows = routineOrder(routines.filter { shown.contains($0.server) }, paused: \.routine.paused,
                                next: { $0.routine.nextRun.flatMap(parseDate) })
        TimelineView(.everyMinute) { tick in
            List {
                Text("Checks your bots run on a schedule. A run that finds something tells its bot, and the bot tells you.")
                    .font(Theme.Font.footnote).foregroundStyle(Theme.secondary)
                    .plainRow()
                    .padding(.bottom, Theme.Space.s)
                if let error {
                    Text(error).font(Theme.Font.footnote).foregroundStyle(Theme.destructive).plainRow()
                }
                ForEach(rows) { row($0, now: tick.date) }
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.bottom, Theme.Space.s)
                        Text("To add or change one, ask the bot in its chat, for example \u{201C}check the deploy every morning at nine\u{201D}.")
                            .font(Theme.Font.footnote).foregroundStyle(Theme.secondary)
                        askButton("Ask \(asked?.bot.name ?? "a bot")")
                    }
                    .padding(.top, Theme.Space.l)
                    .plainRow()
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .contentMargins(.top, Theme.Space.s, for: .scrollContent)
            .themedList()
            .refreshable { await load() }
        }
        .overlay {
            if let blocked = ConnectState(store: store, nav: nav) {
                blocked
            } else if read && rows.isEmpty {
                EmptyScreen(art: RingsArt(symbol: "clock.arrow.circlepath"), title: "No routines yet",
                            message: "A bot can check things for you on a schedule and only speak up when it finds something.") {
                    if asked != nil { askButton("Ask \(asked!.bot.name) to set one up") }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 80)
                .page()
            }
        }
        .tabBar("Routines")
        // On every `routines_changed`, on a machine coming up or a bot arriving, and once a minute as the desktop does.
        .task(id: "\(store.routinesRevision)|\(store.allBots.map(\.bot.id))|\(store.machines.filter { store.serverState[$0.id] == .connected }.count)") {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .confirmationDialog("Delete \u{201C}\(deleting?.routine.name ?? "")\u{201D}?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible, presenting: deleting) { r in
            Button("Delete", role: .destructive) { Task { await remove(r) } }
        } message: { r in
            Text("\(r.bot.name) stops running it.")
        }
    }

    /// The bot "Ask" goes to: Wain's own where it is shown, else the first.
    private var asked: (server: UUID, bot: Bot)? {
        let shown = nav.shownIds(store)
        let bots = store.allBots.filter { shown.contains($0.server) }
        return bots.first { $0.bot.welcome != nil } ?? bots.first
    }

    private func askButton(_ label: String) -> some View {
        Button {
            guard let b = asked else { return }
            nav.openBot(b.server, b.bot, in: store)
            nav.focus = store.botChat(b.server, b.bot).last ?? .newSession
        } label: {
            HStack(spacing: Theme.Space.s) {
                if let b = asked { BotFace(bot: b.bot, size: 24) }
                Text(label).font(Theme.Font.pill).foregroundStyle(Theme.text)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .frame(height: 36)
            .background(Theme.raised, in: Capsule())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityIdentifier("askBot")
    }

    private func row(_ r: BotRoutine, now: Date) -> some View {
        HStack(spacing: Theme.Space.m) {
            Button { nav.openBot(r.server, r.bot, in: store) } label: {
                HStack(spacing: Theme.Space.m) {
                    BotFace(bot: r.bot, size: 28).opacity(r.routine.paused ? 0.6 : 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.routine.name).font(Theme.Font.body.font.weight(.semibold))
                            .foregroundStyle(r.routine.paused ? Theme.secondary : Theme.text).lineLimit(1)
                        Text("\(r.routine.scheduleLabel) · \(r.routine.nextLabel(now))")
                            .font(Theme.Font.footnote).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(RowButtonStyle())
            PickSwitch(label: r.routine.paused ? "Turn on \(r.routine.name)" : "Turn off \(r.routine.name)",
                       isOn: Binding(get: { !r.routine.paused }, set: { on in Task { await setPaused(r, !on) } }))
        }
        .padding(.vertical, Theme.Space.s)
        .plainRow()
        .contextMenu {
            Button("Delete routine", systemImage: "trash", role: .destructive) { deleting = r }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("routineRow")
    }

    /// Each bot's routines, read on its own machine; a machine whose read fails keeps what it last said.
    private func load() async {
        var all: [BotRoutine] = []
        for b in store.allBots where store.serverState[b.server] == .connected {
            if let list = try? await store.call(b.server, "list_routines", ["botId": .string(b.bot.id)], as: [Routine].self) {
                all += list.map { BotRoutine(server: b.server, bot: b.bot, routine: $0) }
            } else {
                all += routines.filter { $0.server == b.server && $0.bot.id == b.bot.id }
            }
        }
        if Task.isCancelled { return }
        routines = all
        read = true
    }

    /// The switch moves at once and goes back where the server refused, or never answered.
    private func setPaused(_ r: BotRoutine, _ paused: Bool) async {
        let set = { (to: Bool) in if let i = routines.firstIndex(where: { $0.id == r.id }) { routines[i].routine.paused = to } }
        set(paused)
        if !(await act(r, "set_routine_paused", ["id": .string(r.routine.id), "paused": .bool(paused)],
                       paused ? "Couldn't pause it" : "Couldn't resume it")) {
            set(r.routine.paused)
        }
    }

    private func remove(_ r: BotRoutine) async {
        _ = await act(r, "delete_routine", ["id": .string(r.routine.id)], "Couldn't delete it")
    }

    private func act(_ r: BotRoutine, _ cmd: String, _ args: [String: JSON], _ failed: String) async -> Bool {
        do {
            let _: JSON = try await store.call(r.server, cmd, args)
            error = nil
            Haptic.tap()
            await load()
            return true
        } catch {
            self.error = "\(failed): \(sentence(error.localizedDescription))"
            Haptic.error()
            await load()
            return false
        }
    }
}
