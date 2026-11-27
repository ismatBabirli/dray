import SwiftUI

/// A new task, opened from the compose button on Home and Tasks: the words, by
/// typing or the mic, then who runs it, where, and on what. "Run by" a bot sends
/// the words to that bot's folder instead, which is what starts its chat. Project
/// and Agent each push a page of their own; nothing is asked twice.
struct NewTaskSheet: View {
    @Environment(Store.self) private var store
    @Environment(NewTask.self) private var task
    @Environment(\.dismiss) private var dismiss
    let started: (SessionKey) -> Void
    @State private var confirming = false

    private var idle: Bool { Dictations.shared.state(.newSession) == .idle }

    var body: some View {
        @Bindable var task = task
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    // Locked while starting: a clone can take minutes, and the start runs on the picks it began with.
                    Composer(draft: .newSession, placeholder: task.bot.map { "Message \($0.bot.name)" } ?? "What should it do?",
                             form: true)
                        .disabled(task.sending)
                    if let failure = task.failure {
                        Text(sentence(failure)).font(Theme.Font.footnote).foregroundStyle(Theme.destructive)
                            .padding(.horizontal, Theme.Space.xs)
                    }
                    // Machine before Project: the Project page lists what the picked machine holds.
                    PickCard {
                        runBy
                        if !task.connected.isEmpty {
                            PickDivider()
                            PickMenu("Machine", value: task.server.map(store.name(of:)) ?? "") {
                                Picker("Machine", selection: Binding(get: { task.server }, set: task.pick(server:))) {
                                    ForEach(task.connected) { Text($0.name).tag(Optional($0.id)) }
                                }
                            }
                        }
                        if task.bot == nil {
                            PickDivider()
                            NavigationLink { ProjectPage(task: task) } label: {
                                PickRow("Project") {
                                    Text(task.cloning?.name ?? task.projectChoice?.label ?? "None").foregroundStyle(Theme.secondary)
                                    chevron
                                }
                            }
                            .disabled(task.server == nil)
                            .accessibilityIdentifier("row.Project")
                            if task.cloning != nil || !task.projectChoices.isEmpty {
                                PickDivider()
                                WorktreeRows(task: task)
                            }
                        }
                        PickDivider()
                        NavigationLink { AgentPage(task: task) } label: {
                            PickRow("Agent") {
                                Text([task.model?.label ?? "Default", task.effort.map { Picks.effortLabels[$0] ?? $0 }]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .foregroundStyle(Theme.secondary)
                                chevron
                            }
                        }
                        .accessibilityIdentifier("row.Agent")
                    }
                    .disabled(task.sending)
                    if let offer = task.cloning, let server = task.server {
                        Label {
                            Text("\(offer.name) isn't on \(store.name(of: server)) yet. Starting clones \(offer.slug) into ~/wain/\(offer.name) first, then the task runs there.")
                        } icon: {
                            Image(systemName: "arrow.down.to.line").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.link)
                        }
                        .font(Theme.Font.footnote).foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, Theme.Space.l)
                    }
                }
                .padding(Theme.Space.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    Task {
                        guard let key = await task.start() else { return }
                        dismiss()
                        started(key)
                    }
                } label: { startLabel }
                .buttonStyle(CapsuleButtonStyle(height: 52))
                .disabled(!task.ready || !idle)
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.s)
                .accessibilityIdentifier("startTask")
            }
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // No way out mid-start: a clone dropped half way would still start its task after a Discard.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { task.hasText ? confirming = true : dismiss() }
                        .disabled(task.sending)
                }
                // A bot's folder holds no drafts: its words are a message, not a task to start later.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { if await task.saveDraft() { dismiss() } } }
                        .disabled(!task.hasText || task.bot != nil || task.cloning != nil || task.sending || !idle)
                }
            }
            .background(Theme.card.ignoresSafeArea())
            .confirmationDialog("Keep this task?", isPresented: $confirming, titleVisibility: .visible) {
                if task.bot == nil && task.cloning == nil { Button("Save draft") { Task { if await task.saveDraft() { dismiss() } } } }
                Button("Discard", role: .destructive) {
                    Dictations.shared.cancel(.newSession)
                    task.discard()
                    dismiss()
                }
                Button("Keep editing", role: .cancel) {}
            }
        }
        .task(id: "\(task.server?.uuidString ?? "")|\(task.harness)") { await task.load() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
        .interactiveDismissDisabled(task.sending)
        // A recording left running would have no Done once the sheet goes: stopped and kept, its words here next time.
        .onDisappear {
            if Dictations.shared.state(.newSession) == .recording { Task { await Dictations.shared.stop(store, draft: .newSession) } }
        }
    }

    /// Me, or a bot on a machine that is up.
    private var runBy: some View {
        let bots = store.allBots.filter { b in task.connected.contains { $0.id == b.server } }
        let several = Set(bots.map(\.server)).count > 1
        return PickMenu("Run by", value: task.bot?.bot.name ?? "Me") {
            Picker("Run by", selection: Binding(
                get: { task.bot.map { "\($0.server.uuidString)/\($0.bot.id)" } ?? "" },
                set: { ref in
                    if let b = store.botRef(ref) { task.aim(at: b.bot, on: b.server) } else { task.bot = nil }
                })) {
                Text("Me").tag("")
                ForEach(bots, id: \.bot.id) { b in
                    Text(several ? "\(b.bot.name) · \(store.name(of: b.server))" : b.bot.name)
                        .tag("\(b.server.uuidString)/\(b.bot.id)")
                }
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.tertiary)
    }

    /// Start, or Clone and start where the project is still to be cloned; a clone in flight shows git's own line.
    @ViewBuilder private var startLabel: some View {
        if task.sending {
            HStack(spacing: Theme.Space.s) {
                ProgressView().tint(Theme.page)
                if let offer = task.cloning, let server = task.server {
                    Text(store.cloneProgress[server]?[offer.slug] ?? "Cloning \(offer.name)…").lineLimit(1)
                }
            }
        } else if let bot = task.bot {
            Text("Send to \(bot.bot.name)")
        } else {
            Text(task.cloning == nil ? "Start task" : "Clone and start")
        }
    }
}
