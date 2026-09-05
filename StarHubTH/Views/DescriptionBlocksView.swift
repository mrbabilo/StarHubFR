import SwiftUI

/// A description image rendered at (up to) its **native** size: it downscales
/// to fit the pane when wider, but is never upscaled — the previous
/// `resizable().scaledToFit()` blew small inline icons up to the full pane
/// width, making them huge and blurry. Loads via a shared in-memory cache so
/// re-renders (tab switches, scrolling) don't refetch.
struct DescriptionImage: View {
    let url: URL
    @State private var image: NSImage?
    @State private var failed = false
    /// Largeur offerte par le conteneur, mesurée une fois via une
    /// `PreferenceKey` (un `GeometryReader` en arrière-plan n'altère pas la
    /// mise en page). Sert à la règle de centrage ci-dessous.
    @State private var availableWidth: CGFloat = .infinity

    private static let cache = NSCache<NSURL, NSImage>()

    var body: some View {
        Group {
            if let image {
                // Une image dont la largeur native dépasse 40 % de la colonne est
                // centrée ; une icône de 16 px reste alignée à gauche et ne flotte
                // pas seule au milieu.
                let centered = image.size.width > 0.4 * availableWidth
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    // Cap at the native width so it never upscales; scaledToFit
                    // still shrinks it to the pane when the pane is narrower.
                    .frame(maxWidth: image.size.width)
                    .clipShape(RoundedRectangle(cornerRadius: AppDesignCore.Radius.md))
                    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            } else if failed {
                EmptyView()                       // offline / broken → skip
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: PaneWidthKey.self, value: proxy.size.width)
        })
        .onPreferenceChange(PaneWidthKey.self) { availableWidth = $0 }
        .task(id: url) { await load() }
    }

    private func load() async {
        if let cached = Self.cache.object(forKey: url as NSURL) {
            image = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = NSImage(data: data) {
                Self.cache.setObject(img, forKey: url as NSURL)
                image = img
            } else {
                failed = true
            }
        } catch {
            failed = true
        }
    }
}

/// Renders a Markdown string as native SwiftUI text, preserving line breaks and
/// inline formatting (bold/italic/links). Built from a precomputed
/// `AttributedString` so the (relatively costly) Markdown parse happens once per
/// value change, never on every layout pass — `Text(.init(String))` would
/// re-parse the `LocalizedStringKey` on each pass, and it also collapses the
/// newlines a mod description relies on.
struct MarkdownText: View {
    private let attributed: AttributedString
    /// Whether any run carries a link, so we can show the pointing-hand cursor
    /// over this block (SwiftUI `Text` can't scope a cursor to just the link
    /// sub-range without an AppKit text view, so the hint covers the block).
    private let hasLink: Bool

    init(_ markdown: String) {
        let a = MarkdownText.render(markdown)
        self.attributed = a
        self.hasLink = a.runs.contains { $0.link != nil }
    }

    /// Le fond de fenêtre **résolu sous l'apparence réelle de l'app** (X68).
    ///
    /// `windowBackgroundColor` est une couleur dynamique : `usingColorSpace`
    /// la résout contre `NSAppearance.currentDrawing()`, qui n'est posée que
    /// pendant un dessin. Or `render` est appelé depuis l'`init` de la vue —
    /// il n'y a là aucun contexte de dessin, et rien ne garantit l'apparence
    /// ambiante.
    ///
    /// Ce n'est pas une nuance : **la valeur résolue décide du sens de la
    /// correction**. Mesuré le 2026-09-05 en compilant le cas —
    /// sans apparence posée, `windowBackgroundColor` rend du **blanc**
    /// (luminance 1,0) ; sous `.darkAqua`, du gris 0,118 (luminance 0,013). Le
    /// seuil de `ContrastChecker.adjusted` étant à 0,2, la première réponse
    /// fait **assombrir** le texte et la seconde l'**éclaircir**. Se tromper,
    /// c'est écrire du texte sombre sur fond sombre — exactement ce que cette
    /// correction de contraste existe pour empêcher.
    ///
    /// `performAsCurrentDrawingAppearance` est l'API prévue pour ça. Elle rend
    /// le résultat juste quelle que soit l'apparence ambiante : sans effet
    /// quand celle-ci était déjà la bonne, décisive sinon.
    private static func resolvedWindowBackground() -> NSColor {
        var resolved: NSColor?
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)
        }
        return resolved ?? .windowBackgroundColor
    }

    /// Découpe le Markdown sur les attributs personnalisés `^[X](shcolor: 'hex')`
    /// (couleur, contraste-corrigée sur le fond fenêtre) et `^[X](shunderline:
    /// 'true')` (souligné), puis applique de vrais runs natifs `.foregroundColor`
    /// / `.underlineStyle` sur chaque portion — la couleur et le souligné
    /// n'existent pas en Markdown, et Foundation n'attache pas fiablement les
    /// attributs custom en mode inline, on les applique donc soi-même. Le texte
    /// hors de ces spans est parsé à l'identique d'avant (un seul segment).
    static func render(_ s: String) -> AttributedString {
        let background = resolvedWindowBackground()
        var result = AttributedString()
        let ns = s as NSString
        let pattern = "(?s)\\^\\[(.*?)\\]\\((?:shcolor: '([^']*)'|shunderline: '([^']*)')\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return parseInline(s)
        }
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        var cursor = 0
        for m in matches {
            if m.range.location > cursor {
                result += parseInline(ns.substring(with: NSRange(location: cursor,
                                                                  length: m.range.location - cursor)))
            }
            let content = ns.substring(with: m.range(at: 1))
            let hex = m.range(at: 2).location == NSNotFound ? nil : ns.substring(with: m.range(at: 2))
            let under = m.range(at: 3).location == NSNotFound ? nil : ns.substring(with: m.range(at: 3))
            var piece = parseInline(content)
            if let hex, let nsColor = NSColor(hex: hex),
               let adjusted = ContrastChecker.adjusted(nsColor, on: background) {
                piece.foregroundColor = Color(nsColor: adjusted)
            }
            if under != nil {
                piece.underlineStyle = .single
            }
            result += piece
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            result += parseInline(ns.substring(from: cursor))
        }
        return result
    }

    /// Parse Markdown inline en préservant les espaces/newlines (le corps d'une
    /// description s'appuie sur les sauts de ligne) ; dégrade vers le brut plutôt
    /// que de planter sur du Markdown malformé ou un `%` parasite. Au passage,
    /// retire toute syntaxe résiduelle d'attribut couleur/souligné qu'un span
    /// mal formé aurait laissé fuir (couleurs imbriquées, balise vide, span à
    /// cheval sur un bloc) — voir `scrubResidualColorSyntax`.
    private static func parseInline(_ s: String) -> AttributedString {
        let cleaned = scrubResidualColorSyntax(s)
        return (try? AttributedString(
            markdown: cleaned,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(cleaned)
    }

    /// Retire toute syntaxe résiduelle d'attribut couleur/souligné (`^[`,
    /// `](shcolor: '…')`, `^(shcolor: '…')`, `shcolor: '…'`) qu'un span mal formé
    /// aurait laissé fuir. Les vrais liens Markdown `[texte](https://…)` ne sont
    /// pas touchés (ils ne contiennent pas `shcolor`). Garantit qu'aucun balisage
    /// interne ne s'affiche, même quand le parseur a produit un span imparfait.
    private static func scrubResidualColorSyntax(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "\\]\\((?:shcolor|shunderline): '[^']*'\\)",
                                       with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\^\\((?:shcolor|shunderline): '[^']*'\\)",
                                       with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\^\\[", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "(?:shcolor|shunderline): '[^']*'",
                                       with: "", options: .regularExpression)
        return out
    }

    var body: some View {
        Text(attributed)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(LinkHandCursor(active: hasLink))
    }
}

/// Applies the pointing-hand cursor only when the text actually contains a link.
private struct LinkHandCursor: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active { content.pointingHandCursor() } else { content }
    }
}

/// Renders a parsed mod-description/changelog as native SwiftUI.
///
/// Uses a plain (eager) `VStack`, matching upstream: a `LazyVStack` here is
/// counter-productive because a description tokenizes into only a handful of
/// blocks — often a single very tall `.text` — and lazily measuring a few huge
/// items inside a `ScrollView` thrashes layout instead of helping.
struct DescriptionBlocksView: View {
    let blocks: [DescriptionBlock]
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // id: \.self (contenu Hashable) plutôt que \.offset : l'offset est
            // réutilisé entre fiches de mods, donc le @State (SpoilerView
            // isExpanded) fuyait d'un mod à l'autre. Le contenu, lui, diffère.
            ForEach(blocks, id: \.self) { block in
                switch block {
                case .text(let markdown):
                    MarkdownText(markdown)
                case .heading(let markdown, let level):
                    // Hiérarchie typographique de l'app (20/16/14), jamais les
                    // tailles arbitraires reprises de l'auteur.
                    MarkdownText(markdown).font(DescriptionBlocksView.headingFont(level))
                case .list(let items, let ordered):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(ordered ? "\(idx + 1)." : "•")
                                    .foregroundStyle(.secondary)
                                MarkdownText(item)
                            }
                        }
                    }
                case .code(let source):
                    // Chasse fixe, fond teinté, coins arrondis, défilement
                    // horizontal : un chemin de fichier ne revient jamais à la
                    // ligne en plein milieu.
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(source)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(AppDesignCore.Spacing.sm)
                    }
                    .background(Color.primary.opacity(AppDesignCore.Opacity.light))
                    .clipShape(RoundedRectangle(cornerRadius: AppDesignCore.Radius.sm))
                case .quote(let markdown):
                    // Filet vertical à gauche, texte atténué.
                    MarkdownText(markdown)
                        .foregroundStyle(.secondary)
                        .padding(.leading, AppDesignCore.Spacing.sm)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .frame(width: 2)
                                .foregroundStyle(Color.primary.opacity(AppDesignCore.Opacity.medium))
                        }
                case .image(let url):
                    DescriptionImage(url: url)
                case .spoiler(let title, let content):
                    SpoilerView(title: title, content: content, vm: vm)
                case .divider:
                    Divider().padding(.vertical, 4)
                case .centered(let inner):
                    // Conteneur récursif : on délègue au rendu de blocs, centré.
                    DescriptionBlocksView(blocks: inner, vm: vm)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Typo de titre selon le niveau (1 = le plus grand). Hiérarchie 20/16/14
    /// tirée des tokens `AppDesign.Font`, jamais les tailles de l'auteur.
    private static func headingFont(_ level: Int) -> SwiftUI.Font {
        switch level {
        case 1:  return AppDesign.Font.viewTitle            // 20 semibold
        case 2:  return AppDesign.Font.headline(.semibold)  // 16
        default: return AppDesign.Font.rowTitle(.semibold)  // 14
        }
    }
}

/// Collapsible spoiler (native disclosure). The content is re-parsed into
/// blocks so it renders images and nested formatting just like the top-level
/// description — upstream rendered spoiler content as a single Markdown string,
/// leaving any `[img]` inside shown as raw BBCode.
struct SpoilerView: View {
    let title: String
    private let blocks: [DescriptionBlock]
    @ObservedObject var vm: StarHubTHViewModel
    @State private var isExpanded = false

    init(title: String, content: String, vm: StarHubTHViewModel) {
        self.title = title
        self.blocks = DescriptionBlockParser.parse(content)
        self.vm = vm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                    Text((title.isEmpty || title == "Spoiler") ? vm.L(L10n.Mods.spoiler) : title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(isExpanded ? vm.L(L10n.Mods.spoilerHide) : vm.L(L10n.Mods.spoilerShow))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            if isExpanded {
                DescriptionBlocksView(blocks: blocks, vm: vm)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

private extension NSColor {
    /// Construit une `NSColor` depuis un `#hex` à 6 chiffres. Nil si invalide.
    convenience init?(hex: String) {
        var h = hex
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let n = UInt32(h, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((n >> 16) & 0xff) / 255,
                  green: CGFloat((n >> 8) & 0xff) / 255,
                  blue: CGFloat(n & 0xff) / 255,
                  alpha: 1)
    }
}

/// Largeur offerte à un bloc image, mesurée sans `GeometryReader` envahissant.
private struct PaneWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
