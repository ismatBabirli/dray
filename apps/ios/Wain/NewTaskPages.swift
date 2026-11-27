import SwiftUI

// The pages New task pushes, and its worktree rows: Paper's "New task · project menu",
// "New task · Agent sheet" and "New task · sheet".

/// Which checkout the task runs in: this machine's projects, then the other machines' repos
/// it lacks (picked to clone at the start), then a clone from GitHub or a folder by path.
struct ProjectPage: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: NewTask
    @State private var typing = false
    @State private var path = ""
    @State private var failure: String?

    var body: some View {
        let machine = task.server.map(store.name(of:)) ?? "this machine"
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if !task.projectChoices.isEmpty {
                    PickSection("On \(machine)") {
                        PickCard {
                            ForEach(Array(task.projectChoices.enumerated()), id: \.element) { i, choice in
                                if i > 0 { PickDivider() }
                                Button {
                                    task.pick(choice)
                                    Haptic.select()
                                    dismiss()
                                } label: {
                                    PickRow(choice.label) {
                                        if task.cloning == nil && choice == task.projectChoice {
                                            Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.link)
                                        }
                                    }
                                }
                                .accessibilityAddTraits(task.cloning == nil && choice == task.projectChoice ? .isSelected : [])
                            }
                        }
                    }
                }
                let offers = task.cloneOffers
                if !offers.isEmpty {
                    PickSection("On your other machines", footer: "Not on \(machine) yet. Picking one clones it into ~/wain before the task starts.") {
                        PickCard {
                            ForEach(Array(offers.enumerated()), id: \.element) { i, offer in
                                if i > 0 { PickDivider() }
                                Button {
                                    task.pickClone(offer)
                                    Haptic.select()
                                    dismiss()
                                } label: { offerRow(offer) }
                                .accessibilityIdentifier("clone.\(offer.slug)")
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    PickCard {
                        NavigationLink {
                            if let server = task.server {
                                AttachProjectView(server: server, projects: store.projects[server] ?? []) { attached($0) }
                            }
                        } label: { chevronRow("Clone from GitHub") }
                        PickDivider()
                        Button { typing = true } label: { chevronRow("Attach a folder on \(machine)") }
                    }
                    if let failure {
                        Text(sentence(failure)).font(Theme.Font.footnote).foregroundStyle(Theme.destructive)
                            .padding(.horizontal, Theme.Space.l)
                    }
                }
                .disabled(task.server == nil)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
        }
        .scrollIndicators(.hidden)
        .background(Theme.card)
        .navigationTitle("Project")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Folder on \(machine)", isPresented: $typing) {
            TextField("~/code/project", text: $path)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Attach") { Task { await attachFolder() } }
        }
    }

    private func offerRow(_ offer: CloneOffer) -> some View {
        HStack(spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.name).font(Theme.Font.body).foregroundStyle(Theme.text)
                Text("\(offer.slug) · on \(offer.machine)").font(Theme.Font.footnote).foregroundStyle(Theme.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if task.cloning == offer {
                Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.link)
            } else {
                Text("Clone").font(Theme.Font.body).foregroundStyle(Theme.link)
            }
        }
        .lineLimit(1)
        .padding(.vertical, 10)
        .rowFrame()
    }

    private func chevronRow(_ label: String) -> some View {
        PickRow(label) {
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.tertiary)
        }
    }

    /// An attach or a GitHub clone lands as the server's new list: its newest is the pick.
    private func attached(_ list: [Project]) {
        guard let server = task.server else { return }
        store.attached(server, list)
        if let made = list.max(by: { $0.lastSelected < $1.lastSelected }) {
            task.pick(ProjectChoice(name: made.name, path: list.filter { $0.name == made.name }.count > 1 ? made.path : nil))
        }
    }

    private func attachFolder() async {
        guard let server = task.server else { return }
        failure = nil
        do {
            let list: [Project] = try await store.call(server, "add_project", ["path": .string(path.trimmingCharacters(in: .whitespaces))])
            attached(list)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// What runs the task: the picked machine's agents, the model, and effort, fast mode and
/// permissions where the agent offers them. Where it runs is the sheet's to pick, never this page's.
struct AgentPage: View {
    @Environment(Store.self) private var store
    @Bindable var task: NewTask

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                let agents = task.available.filter(\.available)
                if !agents.isEmpty {
                    PickSection("Agents on \(task.server.map(store.name(of:)) ?? "this machine")") {
                        Flow {
                            ForEach(agents, id: \.harness) { a in
                                PickChip(label: a.label, selected: a.harness == task.harness, harness: a.harness) { task.harness = a.harness }
                            }
                        }
                    }
                }
                PickSection("Model") {
                    ModelChips(models: task.list, harness: task.harness, selected: task.modelId, wrap: true, pick: task.pickModel)
                }
                settings
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
        }
        .scrollIndicators(.hidden)
        .background(Theme.card)
        .navigationTitle("Agent")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var settings: some View {
        let effort = task.model.map { !$0.efforts.isEmpty } ?? false
        let fast = Picks.offersFast(task.harness, task.model)
        let stance = Picks.offersStances(task.harness)
        if effort || fast || stance {
            PickCard {
                if effort, let model = task.model {
                    PickMenu("Effort", value: task.effort.map { Picks.effortLabels[$0] ?? $0 } ?? "") {
                        Picker("Effort", selection: Binding(get: { task.effort ?? "" }, set: task.pickEffort)) {
                            ForEach(model.efforts, id: \.self) { Text(Picks.effortLabels[$0] ?? $0).tag($0) }
                        }
                    }
                }
                if fast {
                    if effort { PickDivider() }
                    PickRow("Fast mode") { PickSwitch(label: "Fast mode", isOn: $task.fast) }
                }
                if stance {
                    if effort || fast { PickDivider() }
                    PickMenu("Permissions", value: task.stanceLabel) {
                        Picker("Permissions", selection: Binding(get: { Picks.stanceFor(task.harness, task.stance) }, set: { task.stance = $0 })) {
                            ForEach(Picks.stances.filter { Picks.honours(task.harness, $0.0) }, id: \.0) { Text($0.1).tag($0.0) }
                        }
                    }
                }
            }
        }
    }
}

/// The Worktree switch and the branch row under it: "Start from" with a worktree where the
/// repo offers a base, "Branch" without, which switches the checkout itself.
struct WorktreeRows: View {
    @Environment(Store.self) private var store
    @Bindable var task: NewTask
    @State private var pickingBase = false
    @State private var branches: BranchList?
    /// A branch picked while the checkout has uncommitted files: Bring or Stash decides.
    @State private var switching: String?
    @State private var branchError: String?

    var body: some View {
        PickRow("Worktree") { PickSwitch(label: "Worktree", isOn: $task.worktree) }
        if task.worktree, let branches, branches.offersWorktreeBase {
            PickDivider()
            Button { pickingBase = true } label: {
                PickRow("Start from") {
                    Text(task.worktreeBase ?? branches.defaultBranch ?? branches.current ?? "").foregroundStyle(Theme.secondary)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.tertiary)
                }
            }
            .accessibilityIdentifier("row.Start from")
        } else if !task.worktree, let branches, let current = branches.current {
            PickDivider()
            PickMenu("Branch", value: current) {
                Picker("Branch", selection: Binding(get: { current }, set: pickBranch)) {
                    ForEach(branches.branches, id: \.self) { Text($0).tag($0) }
                }
            }
        }
        if let branchError {
            Text(sentence(branchError)).font(Theme.Font.footnote).foregroundStyle(Theme.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.l).padding(.bottom, Theme.Space.m)
        }
        Color.clear.frame(height: 0)
            .task(id: place) {
                branches = nil
                branchError = nil
                await readBranches()
            }
            // A sheet, not a push: popped mid-search, a page left its bar standing over this one.
            .sheet(isPresented: $pickingBase) {
                if let branches {
                    NavigationStack { WorktreeBranchPicker(branches: branches, selection: $task.worktreeBase) }
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                        .presentationCornerRadius(38)
                        .presentationBackground(Theme.card)
                }
            }
            .confirmationDialog(dirtyTitle, isPresented: Binding(get: { switching != nil }, set: { if !$0 { switching = nil } }),
                                titleVisibility: .visible, presenting: switching) { branch in
                Button("Bring changes") { Task { await checkout(branch, stash: false) } }
                Button("Stash changes") { Task { await checkout(branch, stash: true) } }
                Button("Cancel", role: .cancel) {}
            } message: { branch in
                Text("Switching to \(branch). Bring moves them with you; Stash keeps them here, saved for later.")
            }
    }

    private var dirtyTitle: String {
        let n = branches?.dirty ?? 0
        return n == 1 ? "1 uncommitted file" : "\(n) uncommitted files"
    }

    /// The checkout the branch row speaks for; a reply for any other is dropped on landing.
    private var place: String { "\(task.server?.uuidString ?? "")|\(task.checkout ?? "")" }

    @discardableResult
    private func readBranches() async -> BranchList? {
        let at = place
        guard let server = task.server, let cwd = task.checkout else { return nil }
        do {
            let read: BranchList = try await store.call(server, "list_branches", ["cwd": .string(cwd)])
            guard at == place else { return nil }
            branches = read
            branchError = nil
            return read
        } catch {
            // The last list stays, so the row is still there to try again from.
            if at == place { branchError = error.localizedDescription }
            return nil
        }
    }

    /// A clean checkout switches at once; uncommitted files ask first, as the desktop's picker does.
    /// Counted afresh, since the agent or an editor may have written since the sheet opened.
    private func pickBranch(_ branch: String) {
        guard branch != branches?.current else { return }
        Task {
            guard let fresh = await readBranches() else { return }
            if fresh.dirty > 0 { switching = branch } else { await checkout(branch, stash: false) }
        }
    }

    private func checkout(_ branch: String, stash: Bool) async {
        let at = place
        guard let server = task.server, let cwd = task.checkout else { return }
        branchError = nil
        do {
            let list: BranchList = try await store.call(server, "checkout_branch",
                                                        ["cwd": .string(cwd), "branch": .string(branch), "stash": .bool(stash)])
            guard at == place else { return }
            branches = list
            Haptic.success()
        } catch {
            guard at == place else { return }
            // Git refusing names the files in the way, which is the part to act on.
            branchError = error.localizedDescription
            Haptic.error()
        }
    }
}

/// Chips that wrap onto new lines, as Paper's Agent page sets them.
struct Flow: Layout {
    var spacing: CGFloat = Theme.Space.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        lines(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in lines(bounds.width, subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func lines(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += line + spacing
                line = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return (points, CGSize(width: widest, height: y + line))
    }
}
