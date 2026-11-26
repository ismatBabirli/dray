import SwiftUI

/// A new task, opened from the compose button on Home and Tasks: the words, by
/// typing or the mic, then who runs it, where, and on what. "Run by" a bot sends
/// the words to that bot's folder instead, which is what starts its chat. Every
/// other pick lives in Run with, behind the Agent row.
struct NewTaskSheet: View {
    @Environment(Store.self) private var store
    @Environment(NewTask.self) private var task
    @Environment(\.dismiss) private var dismiss
    let started: (SessionKey) -> Void
    @State private var picking = false
    @State private var confirming = false

    private var idle: Bool { Dictations.shared.state(.newSession) == .idle }

    var body: some View {
        @Bindable var task = task
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Composer(draft: .newSession, placeholder: task.bot.map { "Message \($0.bot.name)" } ?? "What should it do?",
                             form: true)
                    if let failure = task.failure {
                        Text(sentence(failure)).font(Theme.Font.footnote).foregroundStyle(Theme.destructive)
                            .padding(.horizontal, Theme.Space.xs)
                    }
                    PickCard {
                        runBy
                        PickDivider()
                        if task.bot == nil {
                            project
                            PickDivider()
                        }
                        Button { picking = true } label: {
                            PickRow("Agent") {
                                Text([task.model?.label ?? "Default", task.effort.map { Picks.effortLabels[$0] ?? $0 }]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .foregroundStyle(Theme.secondary)
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.tertiary)
                            }
                        }
                        .accessibilityIdentifier("row.Agent")
                        if !task.connected.isEmpty {
                            PickDivider()
                            PickMenu("Machine", value: task.server.map(store.name(of:)) ?? "") {
                                Picker("Machine", selection: Binding(get: { task.server }, set: task.pick(server:))) {
                                    ForEach(task.connected) { Text($0.name).tag(Optional($0.id)) }
                                }
                            }
                        }
                        if task.bot == nil, !task.projectChoices.isEmpty {
                            PickDivider()
                            PickRow("Worktree") { PickSwitch(label: "Worktree", isOn: $task.worktree) }
                        }
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
                } label: {
                    if task.sending { ProgressView().tint(Theme.page) } else { Text(task.bot.map { "Send to \($0.bot.name)" } ?? "Start task") }
                }
                .buttonStyle(CapsuleButtonStyle(height: 52))
                .disabled(!task.ready || !idle)
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.s)
                .accessibilityIdentifier("startTask")
            }
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { task.hasText ? confirming = true : dismiss() }
                }
                // A bot's folder holds no drafts: its words are a message, not a task to start later.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { if await task.saveDraft() { dismiss() } } }
                        .disabled(!task.hasText || task.bot != nil || task.sending || !idle)
                }
            }
            .background(Theme.card.ignoresSafeArea())
            .confirmationDialog("Keep this task?", isPresented: $confirming, titleVisibility: .visible) {
                if task.bot == nil { Button("Save draft") { Task { if await task.saveDraft() { dismiss() } } } }
                Button("Discard", role: .destructive) {
                    Dictations.shared.cancel(.newSession)
                    task.discard()
                    dismiss()
                }
                Button("Keep editing", role: .cancel) {}
            }
        }
        .task(id: "\(task.server?.uuidString ?? "")|\(task.harness)") { await task.load() }
        .sheet(isPresented: $picking) { RunWithSheet(task: task) }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
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

    @ViewBuilder private var project: some View {
        if task.projectChoices.isEmpty {
            Button { picking = true } label: {
                PickRow("Project") {
                    Text("Attach one").foregroundStyle(Theme.secondary)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.tertiary)
                }
            }
            .disabled(task.server == nil)
        } else {
            PickMenu("Project", value: task.projectChoice?.label ?? "") {
                Picker("Project", selection: Binding(get: { task.projectChoice }, set: task.pick)) {
                    ForEach(task.projectChoices, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
            }
        }
    }
}
