import SwiftUI

// The picks sheets' pieces: rows, switches, chips, and the worktree branch list.

// MARK: Worktree branch

/// Which branch a new task's worktree starts on: the desktop's `WorktreeBranchSelector`,
/// a list rather than a menu since a repo can hold hundreds, its filter the search.
/// `nil` is the default branch, fetched fresh; any other is worked on by its own name.
struct WorktreeBranchPicker: View {
    let branches: BranchList
    @Binding var selection: String?
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let (fallback, local, remote) = branches.worktreeOptions(query)
        List {
            if let fallback {
                Section { row(fallback, note: "latest") }
            }
            if !local.isEmpty {
                Section {
                    ForEach(local, id: \.self) { row($0) }
                } header: {
                    if !remote.isEmpty { Text("Local") }
                }
            }
            if !remote.isEmpty {
                Section("On remote") { ForEach(remote, id: \.self) { row($0) } }
            }
            if fallback == nil && local.isEmpty && remote.isEmpty {
                Text("No branch matches").foregroundStyle(Theme.secondary)
            }
        }
        .themedList()
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Filter branches")
        .navigationTitle("Start from")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }

    private func row(_ name: String, note: String? = nil) -> some View {
        let picked = (selection ?? branches.defaultBranch ?? branches.current) == name
        return Button {
            selection = name == branches.defaultBranch ? nil : name
            Haptic.select()
            dismiss()
        } label: {
            HStack {
                Text(name).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let note { Text(note).foregroundStyle(Theme.tertiary) }
                if picked { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text) }
            }
            .font(Theme.Font.body)
        }
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

// MARK: Pieces

/// A picks sheet's frame: the title over Done on the right, then sections 24pt apart.
struct PickSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(Theme.Font.headline).foregroundStyle(Theme.text)
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.text)
                        .frame(width: 64, alignment: .trailing)
                }
            }
            .frame(height: 52)
            .padding(.horizontal, Theme.Space.xs)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) { content }
                    .padding(.top, Theme.Space.m)
                    .padding(.bottom, Theme.Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, 11)
        .background(Theme.card)
    }
}

/// A grey label over its content, with an optional note under it.
struct PickSection<Content: View>: View {
    let label: String?
    var footer: String?
    @ViewBuilder let content: Content

    init(_ label: String?, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let label { note(label) }
            content
            if let footer { note(footer) }
        }
    }

    private func note(_ line: String) -> some View {
        Text(line).font(Theme.Font.footnote).foregroundStyle(Theme.tertiary).padding(.horizontal, Theme.Space.l)
    }
}

struct PickCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }
}

struct PickDivider: View {
    var body: some View {
        Theme.hairline.frame(height: 1).padding(.leading, Theme.Space.l)
    }
}

/// A 52pt card row: the label, a grey note beside it where there is one, and what it holds.
struct PickRow<Trailing: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder let trailing: Trailing

    init(_ label: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: detail == nil ? Theme.Space.s : 6) {
            Text(label).foregroundStyle(Theme.text)
                .frame(maxWidth: detail == nil ? .infinity : nil, alignment: .leading)
            if let detail {
                Text(detail).foregroundStyle(Theme.tertiary).frame(maxWidth: .infinity, alignment: .leading)
            }
            trailing
        }
        .font(Theme.Font.body)
        .lineLimit(1)
        .rowFrame()
    }
}

/// A card row whose value is picked from a menu; `row.<label>` finds it in tests.
struct PickMenu<Content: View>: View {
    let label: String
    let value: String
    @ViewBuilder let content: Content

    init(_ label: String, value: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.value = value
        self.content = content()
    }

    var body: some View {
        Menu { content } label: { PickRow(label) { MenuValue(value) } }
            .accessibilityIdentifier("row." + label)
    }
}

/// A menu row's value and its up-down chevron; a lock in its place where the value can't move now.
struct MenuValue: View {
    let value: String
    var locked = false

    init(_ value: String, locked: Bool = false) {
        self.value = value
        self.locked = locked
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(value).foregroundStyle(locked ? Theme.tertiary : Theme.secondary)
            Image(systemName: locked ? "lock.fill" : "chevron.up.chevron.down")
                .font(.system(size: locked ? 11 : 12, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
                .frame(width: 13)
        }
    }
}

/// The phone's switch: green with a white knob when on, as Paper's tabs pages draw it; grey when off.
struct PickSwitch: View {
    let label: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button {
            isOn.toggle()
            Haptic.select()
        } label: {
            Capsule()
                .fill(isOn ? Theme.add : Theme.off)
                .frame(width: 51, height: 31)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(isOn ? Theme.onBadge : Theme.knobOff).frame(width: 27, height: 27).padding(2)
                }
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .animation(Theme.motion, value: isOn)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// Chips in one sideways-scrolling line, running to the sheet's edges, opened on `focus`.
struct ChipRow<Content: View>: View {
    var focus: String?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Space.s) { content }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Theme.Space.l, for: .scrollContent)
            .padding(.horizontal, -Theme.Space.l)
            .onAppear { if let focus { proxy.scrollTo(focus, anchor: .center) } }
            // A new agent brings a new list and pick while the row stays on screen.
            .onChange(of: focus) { if let focus { withAnimation(Theme.motion) { proxy.scrollTo(focus, anchor: .center) } } }
        }
    }
}

/// One choice in a chip row: white when picked. An agent carries its mark.
struct PickChip: View {
    let label: String
    let selected: Bool
    var harness: String?
    let pick: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if let harness {
                AgentMark(harness: harness).frame(width: 13, height: 13).padding(.trailing, 6)
            }
            Text(label).font(selected ? Theme.Font.pill : Theme.Font.subhead)
        }
        .foregroundStyle(selected ? Theme.page : Theme.text)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(selected ? Theme.text : Theme.tile, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            Haptic.select()
            pick()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// An agent's shortlisted models as chips, and More models to edit the list. It lives on this phone, per agent.
struct ModelChips: View {
    let models: [Model]
    let harness: String
    let selected: String
    /// Wrapped onto new lines rather than scrolled sideways, as New task's Agent page sets them.
    var wrap = false
    let pick: (String) -> Void
    /// The models the row draws, per agent; nil until the reader edits it, which
    /// draws every row the server doesn't mark secondary, as the desktop seeds its shortlist.
    @State private var shortlist: [String]?
    @State private var library = false

    private var listKey: String { "shortlist." + harness }
    private func listed(_ m: Model) -> Bool { shortlist?.contains(m.id) ?? (m.secondary != true) }
    /// The shortlist, and the pick if it is off it. pi and fx run their own default where
    /// nothing is picked, so that is a choice too.
    private var choices: [(id: String, label: String)] {
        (Picks.defaultModel[harness] == "" ? [("", "Default")] : [])
            + models.filter { listed($0) || $0.id == selected }.map { ($0.id, $0.label) }
    }

    var body: some View {
        Group {
            if wrap { Flow { chips } } else { ChipRow(focus: selected) { chips } }
        }
        .animation(Theme.motion, value: shortlist)
        .task(id: harness) { shortlist = UserDefaults.standard.stringArray(forKey: listKey) }
        .sheet(isPresented: $library) {
            PickSheet(title: "Models") {
                PickSection(nil, footer: "Models switched on show in the picker.") {
                    PickCard {
                        ForEach(Array(models.enumerated()), id: \.element.id) { i, m in
                            if i > 0 { PickDivider() }
                            PickRow(m.label) {
                                PickSwitch(label: m.label, isOn: Binding(get: { listed(m) }, set: { list(m, $0) }))
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(38)
            .presentationBackground(Theme.card)
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(choices, id: \.id) { m in
            PickChip(label: m.label, selected: m.id == selected) { pick(m.id) }
                .id(m.id)
        }
        if !models.isEmpty {
            PickChip(label: "More models", selected: false) { library = true }
        }
    }

    private func list(_ m: Model, _ on: Bool) {
        var ids = (shortlist ?? models.filter { $0.secondary != true }.map(\.id)).filter { $0 != m.id }
        if on { ids.append(m.id) }
        shortlist = ids
        UserDefaults.standard.set(ids, forKey: listKey)
    }
}

extension View {
    /// A card row's 52pt height and its 16/14 insets.
    func rowFrame() -> some View {
        frame(maxWidth: .infinity, minHeight: 52).padding(.leading, Theme.Space.l).padding(.trailing, 14).contentShape(Rectangle())
    }
}
