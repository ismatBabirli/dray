import SwiftUI
import UIKit

/// The foot of a session: the composer, and under it the session's model and
/// stance, both opening This task. While a turn runs Stop sits beside the field
/// and a send queues.
struct ReplyDock: View {
    @Environment(Store.self) private var store
    @Environment(\.openSession) private var openSession
    let key: SessionKey
    @State private var models: [Model] = []
    /// The machine's agents, read when This task opens.
    @State private var agents: [AgentAvailability] = []
    /// Picks for the next reply; nil is the session's own.
    @State private var model: String?
    @State private var effort: String?
    @State private var stance: String?
    @State private var fast: Bool?
    @State private var picking = false
    @State private var sending = false
    /// Why the last send failed; the words stay to send again.
    @State private var failed: String?

    private var item: SessionItem? { store.items[key] }
    private var busy: Bool { item?.busy ?? false }
    private var dictation: Dictation { Dictations.shared.state(key) }
    private var text: String { (store.drafts[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private var connected: Bool { store.serverState[key.server] == .connected }
    /// Down long enough that its session says so; a quick reconnect dims nothing.
    private var away: Bool { store.lost.contains(key.server) }
    /// An agent and model picked here or in the bot sheet, waiting for this reply.
    private var pick: AgentPick? { store.unsent[key] }
    /// The reply moves the session to another agent (#1414).
    private var moving: Bool { pick.map { $0.harness != item?.harness } ?? false }
    private var harness: String { pick?.harness ?? item?.harness ?? "" }
    private var modelId: String { model ?? pick?.model ?? item?.model ?? "" }
    private var current: Model? { models.first { $0.id == modelId } }
    private var effortNow: String? { effort ?? (moving ? nil : item?.effort) }
    private var stanceNow: String { stance ?? item?.permissionMode ?? "" }
    private var fastNow: Bool { fast ?? item?.fast ?? false }
    /// This machine's reading for the agent, which the model chip's ring draws.
    private var reading: UsageReading? { store.usage[key.server]?.first { $0.harness == harness } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if moving {
                HStack(spacing: 6) {
                    AgentMark(harness: harness).frame(width: 13, height: 13)
                    Text("Your next message goes to \(Picks.agentLabels[harness] ?? harness)")
                        .font(Theme.Font.footnoteMedium).foregroundStyle(Theme.text).lineLimit(1)
                }
                .padding(.leading, Theme.Space.xs)
            }
            if let failed {
                Text("Couldn't send. \(sentence(failed))").font(Theme.Font.footnote).foregroundStyle(Theme.destructive)
                    .padding(.leading, Theme.Space.xs)
            }
            Composer(draft: key, placeholder: busy ? "Queue a message" : store.bot(key).map { "Message \($0.name)" } ?? "Message",
                     busy: busy, sending: sending, canSend: connected && dictation == .idle, send: send,
                     stop: { Task { await store.interrupt(key) } })
            .opacity(away ? 0.6 : 1)
            picks.opacity(away ? 0.4 : 1)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.s)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        // The chat fades out under the composer rather than stopping at a line.
        .background {
            LinearGradient(stops: [.init(color: Theme.page.opacity(0), location: 0), .init(color: Theme.page, location: 0.35)],
                           startPoint: .top, endPoint: .bottom)
                .padding(.top, -24)
                .ignoresSafeArea()
        }
        .animation(Theme.motion, value: connected)
        .animation(Theme.motion, value: failed)
        .onChange(of: text) { if !text.isEmpty { failed = nil } }
        // The bot sheet's pick is the newer word on model and effort; the dock's own would override it.
        .onChange(of: pick) {
            model = nil
            effort = nil
        }
        // A switch made elsewhere: the old agent's picks would go to the new one, which may not run them.
        .onChange(of: item?.harness) {
            model = nil
            effort = nil
            stance = nil
            fast = nil
        }
        // Never the old agent's models under the new one's name while its list is read.
        .onChange(of: harness) { models = [] }
        .task(id: "\(harness)|\(connected)") {
            guard connected, !harness.isEmpty else { return }
            let read: [Model]? = try? await store.call(key.server, "list_models", ["harness": .string(harness)])
            guard let read, !Task.isCancelled else { return }
            models = read
            // An agent picked onto a model its list lacks takes its default, never the old agent's model.
            if let pick, moving {
                let usable = Picks.usableModel(read, pick.model, pick.harness)
                if usable != pick.model { store.unsent[key] = AgentPick(harness: pick.harness, model: usable) }
            }
        }
        .sheet(isPresented: $picking) { thisTask }
        // Leaving mid-recording sends what was said into this session's draft, the desktop's rule.
        .onDisappear {
            if Dictations.shared.state(key) == .recording { Task { await Dictations.shared.stop(store, draft: key) } }
        }
    }

    /// The model with its effort, and the stance: each opens This task. The model's chip
    /// carries this machine's five-hour reading for the agent as a ring, once there is one.
    private var picks: some View {
        HStack(spacing: Theme.Space.s) {
            PickChipButton(action: { picking = true }) {
                HStack(spacing: 5) {
                    if let reading, let w = reading.fiveHour {
                        UsageRing(percent: reading.atLimit ? 100 : w.usedPercent, size: 13,
                                  tone: reading.atLimit ? Theme.destructive : Theme.text)
                    } else {
                        AgentMark(harness: harness).frame(width: 13, height: 13)
                    }
                    Text(current?.label ?? item?.model ?? "Model").font(Theme.Font.footnoteStrong).foregroundStyle(Theme.text)
                    if let effortNow, current?.efforts.isEmpty == false {
                        Text(Picks.effortLabels[effortNow] ?? effortNow).foregroundStyle(Theme.tertiary)
                    }
                }
            }
            .accessibilityLabel("Model")
            .accessibilityValue(current?.label ?? item?.model ?? "")
            if Picks.offersStances(harness) {
                PickChipButton(action: { picking = true }) {
                    Text(Picks.stances.first { $0.0 == Picks.stanceFor(harness, stanceNow) }?.1 ?? "Auto")
                        .font(Theme.Font.footnoteStrong).foregroundStyle(Theme.text)
                }
                .accessibilityLabel("Permissions")
            }
        }
        .padding(.leading, Theme.Space.xs)
    }

    /// The session's picks for the next reply, each locked mid-turn where the harness can't carry it
    /// onto a queued prompt (`liveControls.ts`).
    private var thisTask: some View {
        let locked = { (control: String) in Picks.lockedMidTurn(harness, control, busy) }
        let efforts = current?.efforts ?? []
        let offersFast = Picks.offersFast(harness, current)
        let offersStance = Picks.offersStances(harness)
        let effortLabel = current.flatMap { Picks.usableEffort($0, effortNow) }.map { Picks.effortLabels[$0] ?? $0 } ?? ""
        let stanceLabel = Picks.stances.first { $0.0 == Picks.stanceFor(harness, stanceNow) }?.1 ?? ""
        let choices = agentChoices
        return PickSheet(title: "This task") {
            // Another agent takes the session over at the next send, with the conversation.
            if choices.count > 1 {
                PickSection("Agent") {
                    ChipRow(focus: harness) {
                        ForEach(choices, id: \.harness) { a in
                            // Mid-turn the session's own agent stays open, so a pick made before the turn can be undone.
                            let held = locked("agent") && a.harness != item?.harness
                            PickChip(label: a.label, selected: a.harness == harness, harness: a.harness) { pickAgent(a.harness) }
                                .allowsHitTesting(!held)
                                .opacity(held ? 0.35 : 1)
                                .id(a.harness)
                        }
                    }
                }
            }
            PickSection("Model") {
                ModelChips(models: models, harness: harness, selected: modelId) { model = $0; effort = nil }
                    .allowsHitTesting(!locked("model"))
                    .opacity(locked("model") ? 0.35 : 1)
            }
            if !efforts.isEmpty || offersFast || offersStance {
                PickSection(nil, footer: lockNote) {
                    PickCard {
                        if let current, !efforts.isEmpty {
                            if locked("effort") {
                                PickRow("Effort") { MenuValue(effortLabel, locked: true) }
                            } else {
                                PickMenu("Effort", value: effortLabel) {
                                    Picker("Effort", selection: Binding(get: { Picks.usableEffort(current, effortNow) ?? "" }, set: { effort = $0 })) {
                                        ForEach(efforts, id: \.self) { Text(Picks.effortLabels[$0] ?? $0).tag($0) }
                                    }
                                }
                            }
                        }
                        if offersFast {
                            if !efforts.isEmpty { PickDivider() }
                            PickRow("Fast mode") {
                                PickSwitch(label: "Fast mode", isOn: Binding(get: { fastNow }, set: { fast = $0 }))
                                    .disabled(locked("fast"))
                            }
                        }
                        if offersStance {
                            if !efforts.isEmpty || offersFast { PickDivider() }
                            if locked("stance") {
                                PickRow("Permissions") { MenuValue(stanceLabel, locked: true) }
                            } else {
                                PickMenu("Permissions", value: stanceLabel) {
                                    Picker("Permissions", selection: Binding(get: { Picks.stanceFor(harness, stanceNow) }, set: { stance = $0 })) {
                                        ForEach(Picks.stances.filter { Picks.honours(harness, $0.0) }, id: \.0) { Text($0.1).tag($0.0) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            if let read: [AgentAvailability] = try? await store.call(key.server, "agent_availability") { agents = read }
        }
        .presentationDetents([.height(444), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        .presentationBackground(Theme.card)
    }

    /// What waits for the turn to end, said once under the card. Picks go out with the next reply,
    /// so "the rest" are the ones that reply carries into the running turn.
    private var lockNote: String? {
        let shown: [(String, String)] = (agentChoices.count > 1 ? [("agent", "agent")] : []) + [("model", "model")]
            + ((current?.efforts.isEmpty ?? true) ? [] : [("effort", "effort")])
            + (Picks.offersFast(harness, current) ? [("fast", "fast mode")] : [])
            + (Picks.offersStances(harness) ? [("stance", "permissions")] : [])
        let held = shown.filter { Picks.lockedMidTurn(harness, $0.0, busy) }.map(\.1)
        guard !held.isEmpty else { return nil }
        if held.count == shown.count { return "These can change once this turn ends." }
        let names = ListFormatter.localizedString(byJoining: held)
        return names.prefix(1).uppercased() + names.dropFirst() + " can change once this turn ends. The rest go with your next message."
    }

    /// The agents up on the machine, and always the session's own, so a pick can be taken back.
    private var agentChoices: [(harness: String, label: String)] {
        var list = agents.filter(\.available).map { (harness: $0.harness, label: $0.label) }
        if let own = item?.harness, !list.contains(where: { $0.harness == own }) {
            list.insert((harness: own, label: Picks.agentLabels[own] ?? own), at: 0)
        }
        return list
    }

    /// Another agent's pick waits for the next send; the session's own takes the pick back.
    /// Its model is the one last started a task on here, until its list says otherwise.
    private func pickAgent(_ agent: String) {
        guard let item, agent != harness else { return }
        store.unsent[key] = agent == item.harness ? nil
            : AgentPick(harness: agent, model: Prefs.map("models")[agent] ?? Picks.defaultModel[agent] ?? "")
    }

    private func send() {
        let words = text
        // Spoken words still on their way would land after this send, as a reply of their own.
        guard !words.isEmpty, !sending, dictation == .idle else { return }
        sending = true
        failed = nil
        Haptic.tap()
        // Only what the reader moved; a new model takes an effort it offers.
        let level = model != nil || effort != nil || pick != nil ? current.flatMap { Picks.usableEffort($0, effortNow) } ?? effortNow : nil
        Task {
            let to = await store.send(key, words, harness: pick?.harness, model: model ?? pick?.model, effort: level, stance: stance,
                                      fast: moving ? fastNow && Picks.offersFast(harness, current) : fast)
            if let to {
                // Only if untouched meanwhile: words added while the send was out were never sent.
                if store.drafts[key]?.trimmingCharacters(in: .whitespacesAndNewlines) == words { store.drafts[key] = nil }
                model = nil
                effort = nil
                stance = nil
                fast = nil
                // A switch is a new session: the chat follows it.
                if to != key { openSession?(to) }
            } else {
                failed = store.lastError ?? "The server didn't answer."
                store.lastError = nil
                Haptic.error()
            }
            sending = false
        }
    }
}

/// The end of a long reply, cut at a word with "…" before it: about three lines of the bubble.
/// Cut here rather than by `truncationMode(.head)`, which a multi-line `Text` ignores.
func spokenTail(_ text: String, limit: Int = 100) -> String {
    guard text.count > limit else { return text }
    let cut = text.suffix(limit)
    let word = cut.firstIndex(where: \.isWhitespace).map { cut.index(after: $0) } ?? cut.startIndex
    return "…" + cut[word...]
}
