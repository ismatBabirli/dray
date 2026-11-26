import SwiftUI

/// Every composer's field: words typed or spoken into one draft, a mic at the
/// trailing edge that becomes Send once there are words, and Stop beside it
/// while a turn runs. A tap on the mic dictates hands-free until Done or
/// Cancel; holding it talks while held. The words land in the field to edit.
/// Where nothing can transcribe, the mic is hidden.
struct Composer: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    let draft: SessionKey
    var placeholder = "Message"
    /// A turn runs: Stop sits beside the field and a send queues.
    var busy = false
    var sending = false
    /// The send can go: its server is up and nothing else holds it.
    var canSend = true
    /// The new task form: a tall field whose mic stays with words in it, Start being the send.
    var form = false
    var send: () -> Void = {}
    var stop: () -> Void = {}
    @AppStorage(Dictations.serverKey) private var dictationPick = ""
    @FocusState private var focused: Bool
    @State private var hint: String?
    /// The mic is held down: it stays where it is until let go, or its release is never heard.
    @State private var holding = false

    private var text: Binding<String> {
        Binding(get: { store.drafts[draft] ?? "" }, set: { store.drafts[draft] = $0.isEmpty ? nil : $0 })
    }
    private var words: String { (store.drafts[draft] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private var dictation: Dictation { Dictations.shared.state(draft) }
    private var listening: Bool { dictation != .idle }
    /// Nothing can transcribe, and nothing is mid-recording that would lose its Done.
    private var mic: Bool { !store.typesOnly || listening }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let line = hint ?? Dictations.shared.notes[draft], !listening {
                KeptNote(line: line, draft: draft).frame(maxWidth: .infinity)
            }
            HStack(alignment: .bottom, spacing: 10) {
                field
                if busy && !form && !listening {
                    Button {
                        Haptic.firm()
                        stop()
                    } label: {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.onPrimary).frame(width: 13, height: 13)
                            .frame(width: 44, height: 44)
                            .background(Theme.primary, in: Circle())
                    }
                    .buttonStyle(RowButtonStyle())
                    .accessibilityLabel("Stop")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
        }
        .animation(Theme.motion, value: listening)
        .animation(Theme.motion, value: busy)
        .animation(Theme.motion, value: words.isEmpty)
        .onChange(of: nav.focus, initial: true) {
            if nav.focus == draft {
                focused = true
                nav.focus = nil
            }
        }
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .bottom, spacing: Theme.Space.s) {
                TextField(placeholder, text: text, prompt: Text(listening && words.isEmpty ? "Listening…" : placeholder)
                    .foregroundStyle(Theme.tertiary), axis: .vertical)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.text)
                    .tint(Theme.link)
                    .lineLimit(form ? 6...12 : 1...6)
                    .focused($focused)
                    .padding(.vertical, 11)
                    // The whole field takes the tap that focuses it: a tap gesture round it swallowed Send's.
                    .frame(maxWidth: .infinity, minHeight: form ? 150 : 44, alignment: form ? .topLeading : .leading)
                    .contentShape(.rect)
                    .accessibilityIdentifier("composer")
                if (!listening || holding) && !form { trailing.padding(.bottom, 6) }
            }
            .padding(.leading, Theme.Space.l)
            .padding(.trailing, 6)
            if listening {
                DictationStrip(draft: draft).padding(.horizontal, 6).padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if form && mic && (!listening || holding) {
                HStack { Spacer(); micButton(filled: true) }.padding([.trailing, .bottom], Theme.Space.m)
            }
        }
        .background(Theme.card, in: .rect(cornerRadius: form || listening ? Theme.Radius.xl : 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: form || listening ? Theme.Radius.xl : 22, style: .continuous)
            .strokeBorder(Theme.hairline))
    }

    /// Send once there are words, else the mic; nothing where neither can go.
    @ViewBuilder private var trailing: some View {
        if !words.isEmpty && !holding {
            Button(action: send) {
                Group {
                    if sending { ProgressView().tint(Theme.onPrimary) }
                    else { Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)) }
                }
                .foregroundStyle(Theme.onPrimary)
                .frame(width: 32, height: 32)
                .background(Theme.primary, in: Circle())
            }
            .disabled(!canSend || sending)
            .opacity(canSend ? 1 : 0.35)
            .accessibilityLabel(busy ? "Queue" : "Send")
            .accessibilityIdentifier("send")
        } else if mic {
            micButton(filled: false)
        }
    }

    /// Tap for hands-free, hold to talk while held.
    private func micButton(filled: Bool) -> some View {
        MicButton(filled: filled, holding: $holding, start: { startDictation() }) {
            Task {
                // Let go before the recorder is up: it stops the moment it is.
                while Dictations.shared.state(draft) == .starting { try? await Task.sleep(for: .milliseconds(50)) }
                await Dictations.shared.stop(store, draft: draft)
            }
        }
    }

    private func startDictation() {
        guard dictation == .idle else { return }
        guard let engine = store.dictationEngine(dictationPick) else { return flash("Nothing can transcribe right now. Type instead.") }
        // A kept recording is the only copy of what was said; it goes by Retry or Discard, never by a new tap.
        guard Dictations.shared.kept[draft] == nil else { return }
        Dictations.shared.dismiss(draft)
        focused = false
        Task { await Dictations.shared.start(store, engine: engine, draft: draft) }
    }

    private func flash(_ line: String) {
        hint = line
        Task {
            try? await Task.sleep(for: .seconds(2))
            if hint == line { hint = nil }
        }
    }
}

/// The mic: a tap starts hands-free dictation, a hold past a moment talks until let go.
private struct MicButton: View {
    let filled: Bool
    @Binding var holding: Bool
    let start: () -> Void
    /// The end of a hold.
    let release: () -> Void
    @State private var pressed: Task<Void, Never>?

    var body: some View {
        Image(systemName: "mic")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(filled ? Theme.text : Theme.secondary)
            .frame(width: filled ? 40 : 32, height: filled ? 40 : 32)
            .background { if filled { Circle().fill(Theme.raised) } }
            .scaleEffect(holding ? 1.15 : 1)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard pressed == nil else { return }
                    pressed = Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        holding = true
                        Haptic.firm()
                        start()
                    }
                }
                .onEnded { _ in
                    pressed?.cancel()
                    pressed = nil
                    if holding {
                        holding = false
                        release()
                    } else {
                        start()
                    }
                })
            .animation(.snappy(duration: 0.18), value: holding)
            .accessibilityElement()
            .accessibilityLabel("Dictate")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { start() }
            .accessibilityIdentifier("mic")
    }
}

/// Under the words while dictation runs: Cancel, the microphone's level, the
/// time so far and Done; a spinner while the words are read.
struct DictationStrip: View {
    @Environment(Store.self) private var store
    let draft: SessionKey
    @State private var levels = Array(repeating: Float(0), count: 18)

    var body: some View {
        let state = Dictations.shared.state(draft)
        let reading = state == .transcribing
        HStack(spacing: Theme.Space.m) {
            Button {
                Dictations.shared.cancel(draft)
                Haptic.tap()
            } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text)
                    .frame(width: 32, height: 32).background(Theme.raised, in: Circle())
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityLabel("Cancel")
            if reading {
                ProgressView().controlSize(.small).tint(Theme.secondary)
                Text("Transcribing…").font(Theme.Font.footnote).foregroundStyle(Theme.secondary)
            } else {
                LevelMeter(levels: levels)
            }
            Spacer(minLength: 0)
            if !reading {
                TimelineView(.periodic(from: Dictations.shared.since[draft] ?? .now, by: 1)) { context in
                    let s = Dictations.shared.since[draft].map { max(0, Int(context.date.timeIntervalSince($0))) } ?? 0
                    Text(String(format: "%d:%02d", s / 60, s % 60))
                        .font(Theme.Font.footnote.font.monospacedDigit()).foregroundStyle(Theme.secondary)
                }
            }
            Button { Task { await Dictations.shared.stop(store, draft: draft) } } label: {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 32, height: 32).background(Theme.primary, in: Circle())
            }
            .buttonStyle(RowButtonStyle())
            .disabled(state != .recording)
            .opacity(state == .recording ? 1 : 0.35)
            .accessibilityLabel("Done")
            .accessibilityIdentifier("dictationDone")
        }
        // The level, sampled as the orb used to read it.
        .task(id: state == .recording) {
            guard state == .recording else { return }
            while !Task.isCancelled {
                levels = Array(levels.dropFirst()) + [Dictations.shared.level(draft)]
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
    }
}

/// The last moments of the microphone's level as bars, newest at the trailing end.
private struct LevelMeter: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                // The meter's linear peak sits low for speech, so it is lifted before it is drawn.
                let h = 3 + 17 * CGFloat(min(1, sqrt(max(0, level)) * 1.4))
                Capsule().fill(level > 0.02 ? Theme.text : Theme.tertiary).frame(width: 2.5, height: h)
            }
        }
        .frame(height: 20)
        .animation(.linear(duration: 0.07), value: levels)
        .accessibilityLabel("Listening")
    }
}

/// A raised chip under a composer: the model and its effort, the stance.
struct PickChipButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Theme.card, in: Capsule())
                .fixedSize()
        }
        .buttonStyle(RowButtonStyle())
    }
}
