import SwiftUI

/// Every bot on the shown machines, one row each, its state on its face:
/// waiting, then unread, then working, then the rest, newest activity first.
struct BotsView: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav

    var body: some View {
        let shown = nav.shownIds(store)
        let bots = store.allBots.filter { shown.contains($0.server) }
        let facts = bots.map { b -> BotFact in
            let chat = store.botChat(b.server, b.bot).last
            let item = chat.flatMap { store.items[$0] }
            let waiting = (chat.map(store.isAsking) ?? false) || !store.hiddenAsks(store.botTasks(store.botChat(b.server, b.bot))).isEmpty
            return BotFact(id: ref(b), waiting: waiting, unread: item?.status == "completed", working: item?.busy == true,
                           active: item.flatMap { parseDate($0.modified) })
        }
        let byRef = Dictionary(bots.map { (ref($0), $0) }, uniquingKeysWith: { a, _ in a })
        let ordered = botOrder(facts).compactMap { byRef[$0] }
        List {
            ForEach(ordered, id: \.bot.id) { b in
                Button { nav.openBot(b.server, b.bot, in: store) } label: {
                    BotListRow(server: b.server, bot: b.bot, chat: store.botChat(b.server, b.bot).last)
                        .opacity(store.lost.contains(b.server) ? 0.45 : 1)
                }
                .buttonStyle(RowButtonStyle())
                .sessionRow(selected: false)
                .accessibilityIdentifier("bot.\(b.bot.name)")
            }
        }
        .listStyle(.plain)
        .contentMargins(.top, Theme.Space.s, for: .scrollContent)
        .themedList()
        .refreshable { await store.refresh() }
        .overlay {
            if let blocked = ConnectState(store: store, nav: nav) {
                blocked
            } else if ordered.isEmpty {
                EmptyScreen(art: RingsArt(symbol: "face.smiling"), title: "No bots yet",
                            message: "A bot keeps a chat, hands work out as tasks and checks things on a schedule.") {
                    Button { nav.sheet = .newBot } label: { Label("New bot", systemImage: "plus") }
                        .buttonStyle(EmptyCapsuleStyle(kind: .retry))
                        .background(Theme.raised, in: Capsule())
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 80)
                .page()
            }
        }
        .tabBar("Bots")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { nav.sheet = .newBot } label: { Image(systemName: "plus") }
                    .disabled(!store.machines.contains { store.serverState[$0.id] == .connected })
                    .accessibilityLabel("New bot")
            }
        }
    }

    private func ref(_ b: (server: UUID, bot: Bot)) -> String { "\(b.server.uuidString)/\(b.bot.id)" }
}

/// An iPad sidebar's bot: its chat as the tab's root, or its first page before it has one.
struct BotTabRoot: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    let ref: String

    var body: some View {
        if let b = store.botRef(ref) {
            if let chat = store.botChat(b.server, b.bot).last {
                TranscriptView(key: chat).id(chat)
            } else {
                BotStartView(server: b.server, bot: b.bot) { nav.push(.session($0), on: .bot(ref)) }
            }
        } else {
            EmptyState(title: "Bot not found", message: "Its machine may be off or out of reach.") {
                Image(systemName: "questionmark.circle").font(.largeTitle).foregroundStyle(Theme.tertiary)
            }
            .page()
        }
    }
}
