import SwiftUI

/// What the app ships under someone else's licence, and Wain's own, read from `licences.json`.
/// Apache-2.0, MIT and BSD all ask that their text reach whoever gets the app.
struct Licences: Decodable {
    struct Component: Decodable, Hashable {
        let name: String
        let licence: String
        let copyright: String
        /// The package or bundled file it accounts for, which `LicencesTests` holds to project.yml.
        let covers: [String]
    }

    let components: [Component]
    let licences: [String: String]

    static let shared: Licences = Bundle.main.url(forResource: "licences", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(Licences.self, from: $0) }
        ?? Licences(components: [], licences: [:])
}

/// Settings › Open source licences: a row per component, its licence beside it.
struct LicencesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Wain is open source under the Apache License 2.0, and it ships these libraries under their own licences. Tap one to read it.")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, Theme.Space.xs)
                RowGroup {
                    ForEach(Array(Licences.shared.components.enumerated()), id: \.element.name) { i, c in
                        if i > 0 { RowDivider() }
                        NavigationLink(value: SettingsPage.licence(c)) { SettingsRow(c.name, value: c.licence) }
                    }
                }
                .buttonStyle(RowButtonStyle())
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.card.ignoresSafeArea())
        .navigationTitle("Licences")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One component's licence in full: which licence, whose copyright, then its text.
struct LicenceView: View {
    let component: Licences.Component

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(component.licence).font(Theme.Font.footnoteStrong).foregroundStyle(Theme.secondary)
                Text(component.copyright).font(Theme.Font.subhead).foregroundStyle(Theme.text)
                Text(Licences.shared.licences[component.licence] ?? "").font(Theme.Font.subhead).foregroundStyle(Theme.secondary)
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.l + Theme.Space.xs)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.card.ignoresSafeArea())
        .navigationTitle(component.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
