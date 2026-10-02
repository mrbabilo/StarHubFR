import Foundation

/// Le Markdown inline d'un bloc de description, parsé **en une seule passe**,
/// avec les spans d'attribut que `DescriptionBlockParser` émet pour la couleur
/// (`^[X](shcolor: '#hex')`) et le souligné (`^[X](shunderline: 'true')`).
///
/// Avant, le rendu découpait le texte sur ces spans et parsait chaque morceau
/// à part. Un gras qui les enjambait — `[b][u]Barn Owl[/u][/b]`, ou un titre
/// `[size=4]` portant un mot `[color]` — voyait son `**` ouvrant dans un
/// morceau et le fermant dans un autre : les deux s'affichaient en clair.
/// Mesuré le 2026-10-02 sur les 22 fiches du cache : 103 marqueurs visibles
/// sur 10 fiches, en grande majorité de cette forme.
///
/// Ici chaque span devient son contenu entouré de deux sentinelles. Chacune
/// **imite la classe du caractère qu'elle borde** — lettre ou ponctuation —
/// parce que CommonMark décide si un `*` ouvre ou ferme d'après son voisin : une
/// sentinelle « lettre » devant `**--Conditions--**` faisait lire le `**` comme
/// fermant. Le Markdown est parsé une fois, puis les sentinelles sont retirées
/// et leurs positions rendues comme plages. Couleur et souligné restent à la
/// vue : la couleur se corrige contre le fond de fenêtre, inconnu du Core.
///
/// Reste ensuite le balisage d'auteur cassé (`[b]` refermé trois paragraphes
/// plus loin, gras qui commence par un saut de ligne) : CommonMark ne peut pas
/// le lire, et ses `**` s'afficheraient. Ils sont retirés après le parse —
/// voir `dropOrphanDelimiters`.
enum DescriptionInlineMarkdown {
    struct Span {
        let range: Range<AttributedString.Index>
        let colorHex: String?
        let underline: Bool
    }

    /// Sentinelles « lettre » : zone d'usage privé, ni ponctuation ni espace.
    static let open: Unicode.Scalar = "\u{E000}"
    static let close: Unicode.Scalar = "\u{E001}"
    /// Sentinelles « ponctuation » (catégorie Po, absentes des descriptions).
    static let openPunct: Unicode.Scalar = "\u{2E44}"
    static let closePunct: Unicode.Scalar = "\u{2E45}"
    private static let opens: Set<Unicode.Scalar> = [open, openPunct]
    private static let sentinels: Set<Unicode.Scalar> = [open, close, openPunct, closePunct]

    static func parse(_ s: String) -> (text: AttributedString, spans: [Span]) {
        let (marked, kinds) = markSpans(in: s)
        let cleaned = scrubResidualAttributeSyntax(marked)
        var text = (try? AttributedString(
            markdown: cleaned,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                           failurePolicy: .returnPartiallyParsedIfPossible)
        )) ?? AttributedString(cleaned)
        dropOrphanDelimiters(from: &text)
        // Les plages d'abord : `(text, extractSpans(from: &text…))` copierait
        // le texte avant que ses sentinelles ne soient retirées.
        let spans = extractSpans(from: &text, kinds: kinds)
        return (text, spans)
    }

    /// Remplace chaque span par `open + contenu + close` et rend, dans l'ordre,
    /// ce que chacun porte.
    private static func markSpans(in s: String) -> (String, [(hex: String?, underline: Bool)]) {
        let pattern = "(?s)\\^\\[(.*?)\\]\\((?:shcolor: '([^']*)'|shunderline: '([^']*)')\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (s, []) }
        let ns = s as NSString
        var out = ""
        var kinds: [(hex: String?, underline: Bool)] = []
        var cursor = 0
        for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            cursor = m.range.location + m.range.length
            // Les délimiteurs qui ouvrent ou ferment le contenu passent hors des
            // sentinelles : `*^[**X**](…)*` doit rester la suite `***` que
            // CommonMark sait lire, pas `*`, sentinelle, `**`.
            let content = Substring(ns.substring(with: m.range(at: 1)))
            let isDelimiter: (Character) -> Bool = { $0 == "*" || $0 == "~" }
            let lead = content.prefix(while: isDelimiter)
            let rest = content.dropFirst(lead.count)
            let trail = String(rest.reversed().prefix(while: isDelimiter).reversed())
            let middle = rest.dropLast(trail.count)
            guard let first = middle.unicodeScalars.first, let last = middle.unicodeScalars.last else {
                out += content                // rien à colorer : le span tombe
                continue
            }
            out += lead
            out.unicodeScalars.append(isMarkdownPunctuation(first) ? openPunct : open)
            out += middle
            out.unicodeScalars.append(isMarkdownPunctuation(last) ? closePunct : close)
            out += trail
            let hex = m.range(at: 2).location == NSNotFound ? nil : ns.substring(with: m.range(at: 2))
            kinds.append((hex, m.range(at: 3).location != NSNotFound))
        }
        out += ns.substring(from: cursor)
        return (out, kinds)
    }

    /// Retire les sentinelles et rend la plage de chaque paire. Les positions
    /// sont relevées en scalaires (une sentinelle suivie d'un accent combinant
    /// fusionnerait en un seul `Character`), puis les sentinelles sont ôtées
    /// de la fin vers le début, pour ne jamais invalider une position déjà lue.
    /// Une paire incomplète — le parseur Markdown n'en perd pas, mais rien ne
    /// le garantit — est retirée sans plage plutôt que laissée à l'écran.
    private static func extractSpans(from text: inout AttributedString,
                                     kinds: [(hex: String?, underline: Bool)]) -> [Span] {
        var marks: [(offset: Int, isOpen: Bool)] = []
        for (offset, scalar) in text.unicodeScalars.enumerated() where sentinels.contains(scalar) {
            marks.append((offset, opens.contains(scalar)))
        }
        guard !marks.isEmpty else { return [] }
        // Appariement séquentiel : les spans ne s'imbriquent pas (`markSpans`
        // ne prend que des spans sans span intérieur).
        var pairs: [(open: Int, close: Int)] = []
        var pendingOpen: Int?
        for mark in marks {
            if mark.isOpen { pendingOpen = mark.offset }
            else if let o = pendingOpen { pairs.append((o, mark.offset)); pendingOpen = nil }
        }
        for mark in marks.reversed() {
            let i = text.unicodeScalars.index(text.startIndex, offsetBy: mark.offset)
            text.unicodeScalars.removeSubrange(i...i)
        }
        let removedBefore = { (offset: Int) in marks.filter { $0.offset < offset }.count }
        return pairs.enumerated().compactMap { k, pair in
            guard k < kinds.count else { return nil }
            let lower = pair.open - removedBefore(pair.open)
            let upper = pair.close - removedBefore(pair.close)
            guard lower < upper else { return nil }
            let start = text.unicodeScalars.index(text.startIndex, offsetBy: lower)
            let end = text.unicodeScalars.index(text.startIndex, offsetBy: upper)
            return Span(range: start..<end, colorHex: kinds[k].hex, underline: kinds[k].underline)
        }
    }

    /// Ponctuation au sens de CommonMark : ASCII, catégories P et S d'Unicode.
    private static func isMarkdownPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar)
    }

    /// Retire, hors code inline, les suites de 2 à 4 `*` et de exactement 2 `~`
    /// que le parse a laissées en texte : un délimiteur que CommonMark n'a pas
    /// su apparier — `[b]` d'auteur refermé trois paragraphes plus loin, gras
    /// qui commence par un saut de ligne, `** Titre**:` d'un changelog — ne
    /// porte plus aucun sens et s'afficherait tel quel. Mesuré sur les 22 fiches
    /// du cache le 2026-10-02 : 217 suites retirées, aucune décorative.
    ///
    /// Bornes de ce que le parseur émet (`**`, `***`, `****` d'un titre gras,
    /// `~~`) : un `*` seul est le renvoi de note des auteurs (« category* »),
    /// et `*****` ou `~~~ Installation ~~~` sont des décors, gardés.
    private static func dropOrphanDelimiters(from text: inout AttributedString) {
        var orphans: [Range<AttributedString.Index>] = []
        var i = text.startIndex
        while i < text.endIndex {
            let c = text.characters[i]
            guard c == "*" || c == "~" else { i = text.characters.index(after: i); continue }
            var j = text.characters.index(after: i)
            while j < text.endIndex, text.characters[j] == c { j = text.characters.index(after: j) }
            let length = text.characters.distance(from: i, to: j)
            let inCode = text[i..<j].runs.contains { $0.inlinePresentationIntent?.contains(.code) == true }
            let isOrphan = c == "*" ? (2...4).contains(length) : length == 2
            if isOrphan, !inCode { orphans.append(i..<j) }
            i = j
        }
        for range in orphans.reversed() { text.removeSubrange(range) }
    }

    /// Retire toute syntaxe résiduelle d'attribut couleur/souligné (`^[`,
    /// `](shcolor: '…')`, `^(shcolor: '…')`, `shcolor: '…'`) qu'un span mal formé
    /// aurait laissé fuir. Les vrais liens Markdown `[texte](https://…)` ne sont
    /// pas touchés (ils ne contiennent pas `shcolor`). Garantit qu'aucun balisage
    /// interne ne s'affiche, même quand le parseur a produit un span imparfait.
    static func scrubResidualAttributeSyntax(_ s: String) -> String {
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
}
