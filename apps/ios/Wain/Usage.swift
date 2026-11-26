import SwiftUI

/// A ring filled to a percent: a chip's, the model chip's, the Usage row's mark.
struct UsageRing: View {
    let percent: Double
    var size: CGFloat = 16
    var tone = Theme.text

    var body: some View {
        let line = size * 0.15
        ZStack {
            Circle().stroke(tone == Theme.text ? Theme.raised : tone.opacity(0.25), lineWidth: line)
            Circle().trim(from: 0, to: min(max(percent, 0), 100) / 100)
                .stroke(tone, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(line / 2)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "15:30": a reset or a way back, in the reader's clock.
private func clock(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

/// "Mon 09:00" past today, else the time alone.
private func resetLabel(_ date: Date, now: Date = .now) -> String {
    Calendar.current.isDate(date, inSameDayAs: now) ? clock(date)
        : "\(date.formatted(.dateTime.weekday(.abbreviated))) \(clock(date))"
}

/// Home's strip: one chip per agent with a reading on the shown machines. A tap opens Usage.
struct UsageChips: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav

    var body: some View {
        let chips = usageChips(nav.shown(store).flatMap { store.usage[$0.id] ?? [] })
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s) {
                    ForEach(chips) { chip($0) }
                }
                .padding(.horizontal, Theme.Space.l)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("usageChips")
        }
    }

    private func chip(_ c: UsageChip) -> some View {
        Button { nav.sheet = .usage } label: {
            HStack(spacing: 6) {
                if c.limited {
                    Circle().stroke(Theme.destructive, lineWidth: 2.4).frame(width: 12, height: 12).padding(2)
                } else {
                    UsageRing(percent: c.percent)
                }
                Text(Picks.agentShort[c.harness] ?? Picks.agentLabels[c.harness] ?? c.harness)
                    .font(Theme.Font.footnoteStrong)
                    .foregroundStyle(c.limited ? Theme.destructive : Theme.text)
                Text(c.limited ? c.back.map { "back \(clock($0))" } ?? "at limit" : "\(Int(c.percent.rounded()))%")
                    .font(Theme.Font.footnote.font.monospacedDigit())
                    .foregroundStyle(c.limited ? Theme.destructive : Theme.secondary)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(height: 30)
            .background(c.limited ? Theme.destructive.opacity(0.14) : Theme.card, in: Capsule())
        }
        .buttonStyle(RowButtonStyle())
    }
}

/// Every reading by machine: per agent its plan, how old the reading is, and each window as a bar.
struct UsageSheet: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let machines = nav.shown(store).filter { !(store.usage[$0.id] ?? []).isEmpty }
        NavigationStack {
            TimelineView(.everyMinute) { tick in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        if machines.isEmpty {
                            Text("No readings yet.").font(Theme.Font.subhead).foregroundStyle(Theme.secondary)
                                .padding(.horizontal, Theme.Space.xs)
                        }
                        ForEach(machines) { s in
                            let mac = store.connection(s.id)?.welcome?.macApp == true
                            Text(mac ? "\(s.name) · This Mac" : s.name)
                                .font(Theme.Font.footnoteStrong).foregroundStyle(Theme.secondary)
                                .padding(.horizontal, Theme.Space.xs)
                                .padding(.top, s.id == machines.first?.id ? 0 : Theme.Space.l)
                            ForEach(store.usage[s.id] ?? [], id: \.harness) { meter($0, now: tick.date) }
                        }
                        Text("Readings come in while a task on that agent runs. Grok, fx, pi and OpenCode don't report usage.")
                            .font(Theme.Font.footnote).foregroundStyle(Theme.tertiary)
                            .padding(.horizontal, Theme.Space.xs).padding(.top, Theme.Space.m)
                    }
                    .padding(Theme.Space.l)
                }
            }
            .navigationTitle("Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .background(Theme.card.ignoresSafeArea())
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }

    private func meter(_ r: UsageReading, now: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(Picks.agentLabels[r.harness] ?? r.harness).font(Theme.Font.headline).foregroundStyle(Theme.text)
                Spacer(minLength: Theme.Space.s)
                Text([r.plan.map { $0.prefix(1).uppercased() + $0.dropFirst() },
                      parseDate(r.at).map { $0.timeIntervalSince(now) > -60 ? "now" : "\(shortAge($0)) ago" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.Font.footnote).foregroundStyle(Theme.tertiary)
            }
            ForEach(Array(r.windows.enumerated()), id: \.offset) { _, w in bar(w, limited: r.limited == true) }
            if r.atLimit, r.overage == "rejected" {
                Text("Extra usage is off for this account.").font(Theme.Font.footnote).foregroundStyle(Theme.tertiary)
            } else if r.usingOverage == true {
                Text("Using extra usage.").font(Theme.Font.footnote).foregroundStyle(Theme.tertiary)
            }
        }
        .padding(Theme.Space.l)
        .background(Theme.raised, in: .rect(cornerRadius: Theme.Radius.lg, style: .continuous))
    }

    private func bar(_ w: UsageReading.Window, limited: Bool) -> some View {
        let full = w.usedPercent >= 100
        let reset = w.resetsAt.flatMap(parseDate)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text([windowLabel(w), full ? "limit reached" : nil, reset.map { full ? "back \(clock($0))" : "resets \(resetLabel($0))" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(full ? Theme.destructive : Theme.secondary)
                Spacer(minLength: Theme.Space.s)
                Text("\(Int(w.usedPercent.rounded()))%").font(Theme.Font.footnoteStrong.font.monospacedDigit())
                    .foregroundStyle(full ? Theme.destructive : Theme.text)
            }
            .font(Theme.Font.footnote)
            GeometryReader { g in
                Capsule().fill(Theme.tile)
                    .overlay(alignment: .leading) {
                        Capsule().fill(full ? Theme.destructive : Theme.text)
                            .frame(width: g.size.width * min(max(w.usedPercent, 0), 100) / 100)
                    }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
    }
}
