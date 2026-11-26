import SwiftUI
import ThinkingOrbs

@main
struct WainApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var store: Store
    @State private var task: NewTask
    @State private var nav = Nav()
    /// Settings' Open bot at launch, read off the cached list before the first frame so the
    /// list never shows first; a bot with no cached chat opens later, once its server answers.
    private let launch: SessionKey?

    init() {
        let store = Store()
        _store = State(initialValue: store)
        _task = State(initialValue: NewTask(store: store))
        launch = LaunchBot.bot(store).flatMap { store.botChat($0.server, $0.bot).last }
        // Before launch ends, so a tapped or answered alert that launched the app reaches it.
        Push.shared.start(store)
    }
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView(launch: launch)
                .environment(store)
                .environment(task)
                .environment(nav)
                // Text no screen styles still sits on the scale.
                .font(Theme.Font.body)
                // Neutral, so yellow stays the one colour that means "this is for you".
                .tint(Theme.text)
                // Before the composers decide whether to offer the mic.
                .task { await AppleSpeech.shared.refresh() }
                // Off, a server's kept issues and PRs go, so none draws and it is read afresh once back on.
                .onChange(of: store.servers.filter { !$0.on }.map(\.id), initial: true) { _, off in
                    IssuesModel.shared.forget(Set(off))
                    PullsModel.shared.forget(Set(off))
                }
        }
        .onChange(of: phase) { _, now in
            if now == .active { store.resume() }
        }
    }
}

/// The one sheet the root can show. A single slot, so a pairing link can
/// replace whatever is up rather than stacking on it.
enum RootSheet: Identifiable {
    /// Settings, opened on one server's page where a banner's Fix asked for it.
    case settings(server: UUID?)
    case add(PairLink?, scan: Bool)
    case machines, usage, newTask, newBot

    var id: String {
        switch self {
        case .settings(let s): "settings\(s?.uuidString ?? "")"
        case .add(let link, let scan): "add\(link?.id ?? "")\(scan)"
        case .machines: "machines"
        case .usage: "usage"
        case .newTask: "newTask"
        case .newBot: "newBot"
        }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    @Environment(\.scenePhase) private var phase
    @Environment(\.horizontalSizeClass) private var width
    @Environment(\.displayScale) private var scale
    @AppStorage(LaunchBot.key) private var launchBot = ""
    /// This launch's one chance to open Settings' launch bot; anything the reader does first spends it.
    @State private var autoOpen: Bool
    private let launch: SessionKey?

    init(launch: SessionKey?) {
        self.launch = launch
        // Opened already: it must not open again once Back leaves it.
        _autoOpen = State(initialValue: launch == nil)
    }

    var body: some View {
        @Bindable var nav = nav
        let shown = nav.shownIds(store)
        let waiting = store.waitingCount(shown)
        let unread = store.unreadBots(shown)
        tabs(waiting: waiting, unread: unread)
            .onAppear {
                guard let launch else { return }
                nav.tab = .bots
                nav.paths[.bots] = [.session(launch)]
            }
            .onChange(of: "\(waiting)|\(unread)|\(nav.tab)", initial: true) {
                Task { TabBarTint.apply(home: waiting, bots: unread) }
            }
            // A phone's chat has the screen to itself; an iPad's sidebar stays beside it.
            .onChange(of: width != .regular && !(nav.paths[nav.tab] ?? []).isEmpty, initial: true) { _, hidden in
                Task { TabBarTint.hide(hidden) }
            }
            .sheet(item: $nav.sheet) { s in
                switch s {
                case .settings(let server): SettingsView(focus: server)
                // Filled in, not added: a link from anywhere should not add a server unasked.
                case .add(let link, let scan): AddServerView(link: link, scanFirst: scan)
                case .machines: MachinesSheet()
                case .usage: UsageSheet()
                case .newTask: NewTaskSheet { nav.open(.session($0)) }
                case .newBot: BotSheet(editing: nil) { key in nav.tab = .bots; nav.open(.session(key)) }
                }
            }
            .onChange(of: nav.onScreen(store), initial: true) { _, now in Push.shared.viewing = now }
            .onChange(of: Push.shared.opening, initial: true) { _, key in
                guard let key else { return }
                Push.shared.opening = nil
                nav.sheet = nil
                if case .bot = nav.tab { nav.tab = .home }
                nav.open(.session(key))
            }
            // Removed, a machine no longer narrows the tabs.
            .onChange(of: store.servers.map(\.id)) { _, ids in
                if let m = nav.machine, !ids.contains(m) { nav.machine = nil }
            }
            .onOpenURL { url in
                #if DEBUG
                if url.host == "debug-push", let file = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "file" })?.value {
                    Task { await Push.shared.showDressed(file) }
                    return
                }
                #endif
                if let link = PairLink(url.absoluteString) { nav.sheet = .add(link, scan: false) }
            }
            .overlay(alignment: .top) { ErrorToast() }
            .scrollDismissesKeyboard(.interactively)
            // The desktop's 30s open-PR poll, and none while the app is away.
            .task(id: phase) {
                guard phase == .active else { return }
                while !Task.isCancelled {
                    await store.pollMarks()
                    try? await Task.sleep(for: .seconds(30))
                }
            }
            // Settings' launch bot with no chat cached: opened once its server has answered,
            // unless the reader did anything first.
            .onChange(of: loneBot, initial: true) { _, b in openLaunchBot(b) }
            .onChange(of: "\(nav.tab)|\(nav.paths.values.map(\.count))|\(nav.sheet?.id ?? "")") { autoOpen = false }
            .onChange(of: phase) { if phase == .background { autoOpen = false } }
            // ponytail: a server that takes longer than this to answer never opens its bot; a read-progress signal if that bites.
            .task { try? await Task.sleep(for: .seconds(10)); autoOpen = false }
    }

    @ViewBuilder private func tabs(waiting: Int, unread: Int) -> some View {
        @Bindable var nav = nav
        if #available(iOS 18.0, *) {
            TabView(selection: $nav.tab) {
                Tab("Home", systemImage: "house", value: AppTab.home) { TabStack(tab: .home) { HomeView() } }
                    .badge(waiting)
                Tab("Bots", image: "tab-bots", value: AppTab.bots) { TabStack(tab: .bots) { BotsView() } }
                    .badge(unread)
                // An iPad's sidebar alone: a phone's tab bar, and the iPad's floating one, keep the four tabs.
                if width == .regular {
                    TabSection("Bots") {
                        ForEach(store.allBots.filter { nav.shownIds(store).contains($0.server) }, id: \.bot.id) { b in
                            let ref = "\(b.server.uuidString)/\(b.bot.id)"
                            Tab(value: AppTab.bot(ref)) {
                                TabStack(tab: .bot(ref)) { BotTabRoot(ref: ref) }
                            } label: {
                                Label { Text(b.bot.name) } icon: { faceImage(b.bot, size: 22, scale: scale) }
                            }
                            .tabPlacement(.sidebarOnly)
                            .defaultVisibility(.hidden, for: .tabBar)
                        }
                    }
                    .defaultVisibility(.hidden, for: .tabBar)
                }
                Tab("Tasks", systemImage: "rectangle.stack", value: AppTab.tasks) { TabStack(tab: .tasks) { SessionList() } }
                if width == .regular {
                    TabSection("Projects") {
                        ForEach(projectNames, id: \.self) { name in
                            Tab(name, systemImage: "folder", value: AppTab.project(name)) {
                                TabStack(tab: .project(name)) { SessionList(only: name) }
                            }
                            .tabPlacement(.sidebarOnly)
                            .defaultVisibility(.hidden, for: .tabBar)
                        }
                    }
                    .defaultVisibility(.hidden, for: .tabBar)
                }
                Tab("Routines", systemImage: "clock.arrow.circlepath", value: AppTab.routines) {
                    TabStack(tab: .routines) { RoutinesView() }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: $nav.tab) {
                TabStack(tab: .home) { HomeView() }
                    .tabItem { Label("Home", systemImage: "house") }.tag(AppTab.home).badge(waiting)
                TabStack(tab: .bots) { BotsView() }
                    .tabItem { Label("Bots", image: "tab-bots") }.tag(AppTab.bots).badge(unread)
                TabStack(tab: .tasks) { SessionList() }
                    .tabItem { Label("Tasks", systemImage: "rectangle.stack") }.tag(AppTab.tasks)
                TabStack(tab: .routines) { RoutinesView() }
                    .tabItem { Label("Routines", systemImage: "clock.arrow.circlepath") }.tag(AppTab.routines)
            }
        }
    }

    /// Every shown machine's projects by name, once each: the sidebar's Projects.
    private var projectNames: [String] {
        var seen = Set<String>()
        return nav.shown(store).flatMap { store.projects[$0.id] ?? [] }.map(\.name).filter { seen.insert($0).inserted }
    }

    /// Settings' launch bot once every server has answered: the late path, for a bot with no
    /// chat cached. A cached chat is the root's first screen already (`WainApp.launch`).
    private var loneBot: BotStart? {
        guard autoOpen, !launchBot.isEmpty, !store.live.isEmpty,
              store.live.allSatisfy({ store.known($0.id) }), store.awaitingShares.isEmpty,
              let b = LaunchBot.bot(store) else { return nil }
        return BotStart(server: b.server, bot: b.bot)
    }

    /// Opens the launch bot as a tap on its row would, unanimated. A recording must not be carried off under the reader.
    private func openLaunchBot(_ b: BotStart?) {
        guard let b, nav.sheet == nil, nav.paths.values.allSatisfy(\.isEmpty),
              Dictations.shared.state(.newSession) == .idle else { return }
        autoOpen = false
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            nav.tab = .bots
            nav.openBot(b.server, b.bot, in: store)
        }
    }
}
