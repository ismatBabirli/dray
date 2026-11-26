import SwiftUI
import UIKit

/// The four tabs, always all four and in this order; on an iPad's sidebar also
/// each bot and each project. A tab never does an action.
enum AppTab: Hashable {
    case home, bots, tasks, routines
    /// An iPad sidebar's bot, by `server/bot id`, and its project by name.
    case bot(String), project(String)
}

/// What a tab's stack pushes: a chat, or a bot's page before its first message.
enum Route: Hashable {
    case session(SessionKey)
    case botStart(BotStart)
}

/// Where the reader is: the tab, each tab's stack, the one sheet, and which machine
/// the tabs show. Held by the root so a push alert, a link or Settings' launch bot
/// can land in it from anywhere.
@MainActor @Observable
final class Nav {
    var tab = AppTab.home
    var paths: [AppTab: [Route]] = [:]
    var sheet: RootSheet?
    /// A composer to focus once it is on screen: Routines' "Ask Wain" opens a bot's field ready to type.
    var focus: SessionKey?
    /// Shows tasks and bots from one machine alone; nil shows every one. Kept on this phone.
    var machine: UUID? = UserDefaults.standard.string(forKey: "nav.machine").flatMap(UUID.init(uuidString:)) {
        didSet { UserDefaults.standard.set(machine?.uuidString, forKey: "nav.machine") }
    }

    /// From a tab's own list: the chat on top of that tab, alone.
    func open(_ route: Route) { paths[tab] = [route] }

    /// From inside a chat: another one over it, so Back walks back.
    func push(_ route: Route, on tab: AppTab) { paths[tab, default: []].append(route) }

    /// The chat on top swapped for another: a bot's chip, an agent switch's new session.
    func replaceTop(_ route: Route, on tab: AppTab) {
        if paths[tab]?.isEmpty ?? true { paths[tab] = [route] } else { paths[tab]![paths[tab]!.count - 1] = route }
    }

    /// A bot's chat, or its first page where it has none yet.
    func openBot(_ server: UUID, _ bot: Bot, in store: Store) {
        open(store.botChat(server, bot).last.map(Route.session) ?? .botStart(BotStart(server: server, bot: bot)))
    }

    /// The machines the tabs draw from: every one switched on, once each, narrowed to the picked one while it is on.
    func shown(_ store: Store) -> [Server] {
        let all = store.machines
        guard let machine, all.contains(where: { $0.id == machine }) else { return all }
        return all.filter { $0.id == machine }
    }

    func shownIds(_ store: Store) -> Set<UUID> { Set(shown(store).map(\.id)) }

    /// The session on screen: the top of the tab's stack, else the bot an iPad's sidebar opened.
    func onScreen(_ store: Store) -> SessionKey? {
        if case .session(let k)? = paths[tab]?.last { return k }
        if (paths[tab] ?? []).isEmpty, case .bot(let ref) = tab, let b = store.botRef(ref) { return store.botChat(b.server, b.bot).last }
        return nil
    }
}

extension Store {
    /// Every machine switched on, a relayed copy left out where its direct twin stands in.
    var machines: [Server] { live.filter { !covered.contains($0.id) } }

    /// A bot named as an iPad sidebar names it.
    func botRef(_ ref: String) -> (server: UUID, bot: Bot)? {
        allBots.first { "\($0.server.uuidString)/\($0.bot.id)" == ref }
    }
}

/// One tab's stack: its list at the root, chats pushed over it with the tab bar hidden.
struct TabStack<Root: View>: View {
    @Environment(Nav.self) private var nav
    let tab: AppTab
    @ViewBuilder let root: Root

    var body: some View {
        NavigationStack(path: Binding(get: { nav.paths[tab] ?? [] }, set: { nav.paths[tab] = $0 })) {
            root.navigationDestination(for: Route.self) { route in
                Group {
                    switch route {
                    case .session(let key): TranscriptView(key: key).id(key)
                    case .botStart(let b): BotStartView(server: b.server, bot: b.bot) { nav.replaceTop(.session($0), on: tab) }
                    }
                }
                .hidesTabBarBefore18()
            }
        }
        .environment(\.openTask) { nav.push(.session($0), on: tab) }
        .environment(\.openSession) { nav.replaceTop(.session($0), on: tab) }
    }
}

extension View {
    /// The plain tab view of iOS 17 hides its bar for a chat as SwiftUI says; from iOS 18 the root does it
    /// (`TabBarTint.hide`), since the adaptable tab view read that setting from tabs not on screen.
    @ViewBuilder func hidesTabBarBefore18() -> some View {
        if #available(iOS 18.0, *) { self } else { toolbar(.hidden, for: .tabBar) }
    }

    /// A tab's top bar: Machines leading, the title beside it rather than centred.
    func tabBar(_ title: String) -> some View {
        tabBar(title) { Text(title) }
    }

    /// The same with a title of the caller's own, such as Tasks' view menu.
    func tabBar(_ title: String, @ViewBuilder label: () -> some View) -> some View {
        modifier(TabTitle(title: title, label: label()))
    }
}

private struct TabTitle<Label: View>: ViewModifier {
    let title: String
    let label: Label

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(removing: .title)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { MachinesButton() }
                    ToolbarItem(placement: .topBarLeading) {
                        label.font(Theme.Font.title).foregroundStyle(Theme.text).fixedSize()
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
        } else {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { MachinesButton() } }
        }
    }
}

// MARK: Machines

/// How the shown machines are, worst first: one waiting on the reader, one out of reach, or all fine.
enum MachinesHealth { case fine, needsYou, unreachable }

extension Store {
    func machinesHealth(_ servers: [Server]) -> MachinesHealth {
        let health = servers.compactMap { health($0.id) }
        if health.contains(where: \.needsYou) { return .needsYou }
        if servers.contains(where: { serverState[$0.id] != .connected }) { return .unreachable }
        return .fine
    }
}

/// The server glyph with the worst state's dot, leading every tab's bar; opens Machines.
struct MachinesButton: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav

    var body: some View {
        let shown = nav.shown(store)
        let health = store.machinesHealth(shown)
        Button { nav.sheet = .machines } label: {
            Image(systemName: "server.rack")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 28, height: 28)
                .overlay(alignment: .bottomTrailing) {
                    if !shown.isEmpty {
                        Circle().fill(health == .fine ? Theme.add : health == .needsYou ? Theme.accentFill : Theme.dim)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Theme.page, lineWidth: 2))
                            .offset(x: 3, y: 2)
                    }
                }
        }
        .accessibilityLabel("Machines")
        .accessibilityValue(health == .fine ? "All connected" : health == .needsYou ? "One needs you" : "One can't be reached")
        .accessibilityIdentifier("machines")
    }
}

/// Which machines the tabs show, each one's health with Retry, then Usage, pairing and Settings.
struct MachinesSheet: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let all = store.machines
        let limited = all.flatMap { store.usage[$0.id] ?? [] }.filter(\.atLimit).count
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Show tasks and bots from").font(Theme.Font.footnoteStrong).foregroundStyle(Theme.secondary)
                        .padding(.horizontal, Theme.Space.xs)
                    RowGroup {
                        row(icon: "server.rack", title: "All machines",
                            detail: all.count == 1 ? "1 paired" : "\(all.count) paired", on: nav.machine == nil) { nav.machine = nil }
                        ForEach(all) { s in
                            RowDivider()
                            machineRow(s)
                        }
                    }
                    RowGroup {
                        link(icon: AnyView(UsageRing(percent: 70, size: 18, tone: Theme.text)), title: "Usage",
                             trailing: limited > 0 ? "\(limited) at limit" : nil) { nav.sheet = .usage }
                        RowDivider()
                        link(icon: AnyView(Image(systemName: "qrcode.viewfinder")), title: "Pair a machine") { nav.sheet = .add(nil, scan: true) }
                        RowDivider()
                        link(icon: AnyView(Image(systemName: "gearshape")), title: "Settings") { nav.sheet = .settings(server: nil) }
                    }
                    .padding(.top, Theme.Space.l)
                    Text("Turning a machine off, or removing it, lives in Settings › Servers. Its tasks keep running there.")
                        .font(Theme.Font.footnote).foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, Theme.Space.xs).padding(.top, Theme.Space.s)
                }
                .padding(Theme.Space.l)
            }
            .navigationTitle("Machines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .background(Theme.card.ignoresSafeArea())
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }

    private func machineRow(_ s: Server) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let connected = store.serverState[s.id] == .connected
            let health = store.health(s.id)
            let mac = store.connection(s.id)?.welcome?.macApp == true
            let bots = store.bots[s.id] ?? []
            let tasks = store.items.filter { e in e.key.server == s.id && e.value.archived != true && e.value.hidden != true
                && !bots.contains { samePath($0.path, e.value.cwd) } }.count
            let detail: String = {
                if connected, health == nil {
                    return ([mac ? "This Mac" : nil, tasks == 1 ? "1 task" : "\(tasks) tasks", bots.isEmpty ? nil : bots.count == 1 ? "1 bot" : "\(bots.count) bots"]
                        .compactMap { $0 }).joined(separator: " · ")
                }
                if let until = health?.until {
                    let left = Int(until.timeIntervalSince(context.date).rounded(.up))
                    return left > 0 ? "Can't reach · retrying in \(left)s" : "Can't reach · retrying…"
                }
                return health?.title ?? store.stateLabel(s.id)
            }()
            HStack(spacing: Theme.Space.m) {
                Button { nav.machine = s.id } label: {
                    HStack(spacing: Theme.Space.m) {
                        tile(Image(systemName: mac ? "laptopcomputer" : "server.rack"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.name).font(Theme.Font.body).foregroundStyle(Theme.text).lineLimit(1)
                            HStack(spacing: 5) {
                                Circle().fill(connected && health == nil ? Theme.add : health?.needsYou == true ? Theme.accentFill : Theme.dim)
                                    .frame(width: 6, height: 6)
                                Text(detail).font(Theme.Font.footnote).foregroundStyle(Theme.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(RowButtonStyle())
                if let action = health?.action, !health!.working {
                    Button(action == .fix ? "Fix" : "Retry") {
                        Haptic.tap()
                        if action == .fix { nav.sheet = .settings(server: s.id) } else { Task { await store.retry(s.id) } }
                    }
                    .font(Theme.Font.pill).foregroundStyle(Theme.link)
                } else if nav.machine == s.id {
                    check
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: 56)
            .accessibilityIdentifier("machine.\(s.name)")
        }
    }

    private func row(icon: String, title: String, detail: String, on: Bool, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            HStack(spacing: Theme.Space.m) {
                tile(Image(systemName: icon))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.Font.body).foregroundStyle(Theme.text)
                    Text(detail).font(Theme.Font.footnote).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
                if on { check }
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(RowButtonStyle())
    }

    private func link(icon: AnyView, title: String, trailing: String? = nil, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: Theme.Space.m) {
                tile(icon)
                Text(title).font(Theme.Font.body).foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                if let trailing { Text(trailing).font(Theme.Font.subhead).foregroundStyle(Theme.destructive) }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(RowButtonStyle())
    }

    private func tile(_ icon: some View) -> some View {
        icon.font(.system(size: 15)).foregroundStyle(Theme.text)
            .frame(width: 30, height: 30)
            .background(Theme.tile, in: .rect(cornerRadius: Theme.Radius.sm, style: .continuous))
    }

    private var check: some View {
        Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            .accessibilityLabel("Shown")
    }
}

// MARK: Tab bar

/// The tab bar's badges in their own colours, which SwiftUI cannot say: Home's
/// yellow with dark ink, Bots' the unread red. Read off the window's tab bar
/// controller after each change, since SwiftUI rebuilds its items.
@MainActor enum TabBarTint {
    static func apply(home: Int, bots: Int) {
        guard let tabs = controller() else { return }
        if let items = tabs.tabBar.items, items.count >= 2 {
            items[0].badgeColor = UIColor(Theme.accentFill)
            items[0].setBadgeTextAttributes([.foregroundColor: UIColor(Theme.onPrimary.resolved(dark: true))], for: .normal)
            items[1].badgeColor = UIColor(Theme.unread)
        }
    }

    /// The bar out of a chat's way on a phone, and back once the chat is left.
    static func hide(_ hidden: Bool) {
        guard #available(iOS 18.0, *), let tabs = controller(), tabs.isTabBarHidden != hidden else { return }
        tabs.setTabBarHidden(hidden, animated: true)
    }

    private static func controller() -> UITabBarController? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        func find(_ vc: UIViewController?) -> UITabBarController? {
            guard let vc else { return nil }
            if let t = vc as? UITabBarController { return t }
            for child in vc.children { if let t = find(child) { return t } }
            return find(vc.presentedViewController)
        }
        return windows.lazy.compactMap { find($0.rootViewController) }.first
    }
}

private extension Color {
    /// The dark appearance's value, for ink drawn on a fill that never changes.
    func resolved(dark: Bool) -> Color {
        Color(UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)))
    }
}
