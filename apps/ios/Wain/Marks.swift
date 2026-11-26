import SwiftUI
import UIKit

/// What dictation said instead of words, over the composer; Retry and
/// Discard beside it while the server never answered and the audio is kept.
struct KeptNote: View {
    @Environment(Store.self) private var store
    let line: String
    let draft: SessionKey

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Text(line).foregroundStyle(Theme.tertiary).multilineTextAlignment(.center)
            if Dictations.shared.kept[draft] != nil {
                Button("Retry") { Task { await Dictations.shared.retry(store, draft: draft) } }
                    .foregroundStyle(Theme.text)
                Button("Discard") { Dictations.shared.dismiss(draft) }
                    .foregroundStyle(Theme.destructive)
            }
        }
        .font(Theme.Font.footnote)
    }
}

/// The agent's mark: the desktop's `AgentIcon`, Claude in its rust and the rest in the text's colour.
struct AgentMark: View {
    let harness: String

    var body: some View {
        if UIImage(named: "agent-" + harness) != nil {
            Image("agent-" + harness).resizable().scaledToFit()
                .foregroundStyle(harness == "claude_code" ? AnyShapeStyle(Theme.claude) : AnyShapeStyle(.foreground))
        } else {
            Image(systemName: "sparkle").resizable().scaledToFit()
        }
    }
}

/// The desktop's `ServerFilledIcon`: two filled racks with their lights cut out.
struct ServerIcon: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / 24, y: size.height / 24)
            var racks = Path()
            racks.addRoundedRect(in: CGRect(x: 1, y: 2, width: 22, height: 8.5), cornerSize: CGSize(width: 2.5, height: 2.5))
            racks.addRoundedRect(in: CGRect(x: 1, y: 12.5, width: 22, height: 8.5), cornerSize: CGSize(width: 2.5, height: 2.5))
            ctx.fill(racks, with: .foreground)
            ctx.blendMode = .destinationOut
            ctx.fill(Path(ellipseIn: CGRect(x: 4.5, y: 4.75, width: 3, height: 3)), with: .color(.black))
            ctx.fill(Path(ellipseIn: CGRect(x: 4.5, y: 15.25, width: 3, height: 3)), with: .color(.black))
        }
    }
}
