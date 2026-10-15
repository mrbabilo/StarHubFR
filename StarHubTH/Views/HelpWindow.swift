import SwiftUI

/// La fenêtre d'aide (spec 2026-10-15 aide intégrée §4) : le guide
/// utilisateur embarqué, dans la langue de l'interface — sommaire à gauche,
/// sections à droite, recherche dans la barre d'outils.
struct HelpWindow: View {
    var navigation: NavigationStore
    @ObservedObject var localization: LocalizationStore
    @Environment(\.openURL) private var openURL
    @State private var sections: [HelpSection] = []
    @State private var missing = false
    @State private var query = ""
    @State private var target: String?

    private var shown: [HelpSection] { HelpSearch.filter(sections, query: query) }

    var body: some View {
        NavigationSplitView {
            List(shown) { section in
                Button { target = section.id } label: {
                    Text(Self.inline(section.title)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(localization.L(L10n.Help.contents))
            .navigationSplitViewColumnWidth(min: 180, ideal: 230)
        } detail: {
            content
        }
        .searchable(text: $query, placement: .toolbar, prompt: localization.L(L10n.Help.searchPrompt))
        .frame(minWidth: 640, minHeight: 480)
        .onAppear { load(); consumeRequest() }
        .onChange(of: localization.currentLanguage) { _, _ in load() }
        .onChange(of: navigation.pendingHelpSection) { _, _ in consumeRequest() }
    }

    @ViewBuilder private var content: some View {
        if missing {
            StateCard(icon: AppDesign.Status.warning.symbol, text: localization.L(L10n.Help.missing),
                      actionTitle: localization.L(L10n.Help.openOnline)) {
                if let url = Self.onlineGuide(localization.currentLanguage) { openURL(url) }
            }
            .padding(AppDesign.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if shown.isEmpty {
            Text(String(format: localization.L(L10n.Help.noResults), query))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppDesign.Spacing.xl) {
                        ForEach(shown) { HelpSectionView(section: $0).id($0.id) }
                    }
                    .padding(AppDesign.Spacing.xl)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onAppear { scroll(proxy) }
                .onChange(of: target) { _, _ in scroll(proxy) }
            }
            .environment(\.openURL, OpenURLAction { handle($0) })
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let id = target else { return }
        withAnimation { proxy.scrollTo(id, anchor: .top) }
        target = nil
    }

    private func handle(_ url: URL) -> OpenURLAction.Result {
        switch HelpLink.resolve(url, in: sections) {
        case .section(let id):
            query = ""
            target = id
            return .handled
        case .external(let destination):
            return .systemAction(destination)
        case .ignored:
            return .handled
        }
    }

    private func consumeRequest() {
        guard let id = navigation.pendingHelpSection else { return }
        navigation.pendingHelpSection = nil
        query = ""
        target = id
    }

    private func load() {
        let name = localization.currentLanguage == "fr" ? "GUIDE" : "GUIDE_EN"
        guard let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "Help") else {
            sections = []
            missing = true
            return
        }
        do {
            sections = HelpGuide.parse(try String(contentsOf: url, encoding: .utf8))
            missing = sections.isEmpty
        } catch {
            sections = []
            missing = true
        }
    }

    private static func onlineGuide(_ language: String) -> URL? {
        URL(string: "https://github.com/mrbabilo/StarHubFR/blob/main/"
                    + (language == "fr" ? "GUIDE.md" : "GUIDE_EN.md"))
    }

    /// Markdown en ligne (gras, `code`, liens). Sans `try?` : le cliquet le
    /// compte ; un texte illisible s'affiche brut.
    static func inline(_ markdown: String) -> AttributedString {
        do {
            return try AttributedString(markdown: markdown,
                                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(markdown)
        }
    }
}

/// Une section : titre (en-tête pour VoiceOver) puis ses blocs. Texte
/// sélectionnable : le guide cite des chemins à copier.
private struct HelpSectionView: View {
    let section: HelpSection

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(HelpWindow.inline(section.title))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            // Blocs figés, sans état : l'index suffit comme identité.
            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func blockView(_ block: HelpBlock) -> some View {
        switch block {
        case .paragraph(let text):
            line(text)
        case .bulletList(let items):
            list(items) { _ in "•" }
        case .numberedList(let items):
            list(items) { "\($0 + 1)." }
        case .code(let code):
            Text(code)
                .font(.system(.body, design: .monospaced))
                .padding(AppDesign.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func list(_ items: [String], bullet: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.sm) {
                    Text(bullet(index)).foregroundStyle(.secondary).monospacedDigit()
                    line(item)
                }
            }
        }
    }

    /// Un texte qui porte un lien montre la main au survol : sur un texte
    /// sélectionnable, AppKit remettrait le curseur I (`pointingHandCursor`).
    @ViewBuilder private func line(_ markdown: String) -> some View {
        let text = Text(HelpWindow.inline(markdown)).fixedSize(horizontal: false, vertical: true)
        if markdown.contains("](") { text.pointingHandCursor() } else { text }
    }
}
