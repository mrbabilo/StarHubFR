import Foundation

/// Un bloc d'une section du guide. Le texte reste du Markdown **en ligne**
/// (gras, `code`, liens), rendu par la vue.
public enum HelpBlock: Equatable, Sendable {
    case paragraph(String)
    case bulletList([String])
    case numberedList([String])
    case code(String)
}

/// Une section `## ` du guide utilisateur (spec 2026-10-15 aide intégrée §3).
public struct HelpSection: Identifiable, Equatable, Sendable {
    /// Le marqueur `<!-- help: id -->` ; à défaut, l'ancre.
    public let id: String
    /// Le titre tel quel, numéro compris : le texte renvoie à « section 10 ».
    public let title: String
    /// L'ancre GitHub du titre, pour résoudre les liens internes.
    public let anchor: String
    public let blocks: [HelpBlock]
    /// Tout le texte de la section, pour la recherche : le texte *rendu*
    /// (ni cibles de liens ni `**`), le code restant tel quel. Calculé une
    /// fois : relire le Markdown à chaque frappe coûtait ~57 ms (mesuré le
    /// 2026-10-15 sur GUIDE.md, trois filtrages par rendu).
    public let searchText: String

    public init(id: String, title: String, anchor: String, blocks: [HelpBlock]) {
        self.id = id
        self.title = title
        self.anchor = anchor
        self.blocks = blocks
        var parts = [Self.plain(title)]
        for block in blocks {
            switch block {
            case .paragraph(let text): parts.append(Self.plain(text))
            case .code(let text): parts.append(text)
            case .bulletList(let items), .numberedList(let items): parts += items.map(Self.plain)
            }
        }
        searchText = parts.joined(separator: "\n")
    }

    /// Markdown en ligne → texte brut ; illisible, le morceau reste tel quel.
    private static func plain(_ markdown: String) -> String {
        do {
            let rendered = try AttributedString(
                markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            return String(rendered.characters)
        } catch {
            return markdown
        }
    }
}

/// `GUIDE.md` / `GUIDE_EN.md` → sections. Pur et tolérant : un fichier mal
/// formé rend moins de structure, jamais une erreur ni une section perdue.
public enum HelpGuide {
    public static func parse(_ markdown: String) -> [HelpSection] {
        var builder = Builder()
        // "\r\n" est UN Character en Swift : le normaliser avant de découper.
        let text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        for raw in text.components(separatedBy: "\n") { builder.consume(raw) }
        return builder.finish()
    }

    /// La règle d'ancre de GitHub : minuscules, lettres et chiffres gardés
    /// (accents compris), `-` et `_` gardés, espace → `-`, le reste retiré.
    public static func githubAnchor(_ title: String) -> String {
        var out = ""
        for character in title.lowercased() {
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                out.append(character)
            } else if character == " " {
                out.append("-")
            }
        }
        return out
    }

    /// `<!-- help: install -->` → `install`.
    public static func marker(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->") else { return nil }
        let inner = trimmed.dropFirst(4).dropLast(3).trimmingCharacters(in: .whitespaces)
        guard inner.hasPrefix("help:") else { return nil }
        let id = inner.dropFirst("help:".count).trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? nil : id
    }

    private struct Builder {
        var sections: [HelpSection] = []
        var pendingID: String?
        var current: (id: String, title: String, anchor: String)?
        var blocks: [HelpBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbered: [String] = []
        var code: [String]?

        mutating func consume(_ raw: String) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if var lines = code {
                if line.hasPrefix("```") {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    lines.append(raw)
                    code = lines
                }
                return
            }
            if let id = HelpGuide.marker(in: line) {
                pendingID = id
                return
            }
            if line.hasPrefix("## ") {
                closeSection()
                let title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let anchor = HelpGuide.githubAnchor(title)
                current = (pendingID ?? anchor, title, anchor)
                pendingID = nil
                return
            }
            guard current != nil else { return }        // préambule : titre, sommaire
            if line.hasPrefix("```") { flushText(); code = []; return }
            if line.isEmpty || line == "---" { flushText(); return }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph(); flushNumbered()
                bullets.append(String(line.dropFirst(2)))
                return
            }
            if let item = Self.numberedItem(line) {
                flushParagraph(); flushBullets()
                numbered.append(item)
                return
            }
            // Ligne de suite : elle prolonge l'élément de liste ouvert, sinon le paragraphe.
            if !bullets.isEmpty {
                bullets[bullets.count - 1] += " " + line
            } else if !numbered.isEmpty {
                numbered[numbered.count - 1] += " " + line
            } else {
                paragraph.append(line)
            }
        }

        mutating func finish() -> [HelpSection] {
            if let lines = code {           // bloc de code jamais refermé : gardé tel quel
                blocks.append(.code(lines.joined(separator: "\n")))
                code = nil
            }
            closeSection()
            return sections
        }

        private mutating func closeSection() {
            flushText()
            if let section = current {
                sections.append(HelpSection(id: section.id, title: section.title,
                                            anchor: section.anchor, blocks: blocks))
            }
            blocks = []
        }

        private mutating func flushText() { flushParagraph(); flushBullets(); flushNumbered() }

        private mutating func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }

        private mutating func flushBullets() {
            guard !bullets.isEmpty else { return }
            blocks.append(.bulletList(bullets))
            bullets = []
        }

        private mutating func flushNumbered() {
            guard !numbered.isEmpty else { return }
            blocks.append(.numberedList(numbered))
            numbered = []
        }

        /// `12. Texte` → `Texte`.
        private static func numberedItem(_ line: String) -> String? {
            let digits = line.prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty else { return nil }
            let rest = line.dropFirst(digits.count)
            guard rest.hasPrefix(". ") else { return nil }
            return String(rest.dropFirst(2))
        }
    }
}

/// Où mène un lien du guide (spec §3).
public enum HelpLink: Equatable, Sendable {
    case section(String)
    case external(URL)
    case ignored

    private static let repository = "https://github.com/mrbabilo/StarHubFR"

    public static func resolve(_ url: URL, in sections: [HelpSection]) -> HelpLink {
        if let scheme = url.scheme, ["http", "https", "mailto"].contains(scheme) {
            return .external(url)
        }
        let raw = url.relativeString
        if raw.hasPrefix("#") {
            // `AttributedString(markdown:)` rend l'ancre percent-encodée.
            let encoded = String(raw.dropFirst())
            let anchor = encoded.removingPercentEncoding ?? encoded
            guard let section = sections.first(where: { $0.anchor == anchor }) else { return .ignored }
            return .section(section.id)
        }
        let path = raw.hasPrefix("../../") ? "/" + raw.dropFirst("../../".count)
                                           : "/blob/main/" + raw
        guard let target = URL(string: repository + path) else { return .ignored }
        return .external(target)
    }
}

/// Filtre les sections sur le titre et le texte, sans casse ni accents.
/// Même pliage que la palette ⌘K ; il ne décompose pas `œ`, et les guides
/// n'en contiennent aucun (mesuré le 2026-10-15).
public enum HelpSearch {
    public static func filter(_ sections: [HelpSection], query: String) -> [HelpSection] {
        let needle = CommandPaletteSearch.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return sections }
        return sections.filter { CommandPaletteSearch.fold($0.searchText).contains(needle) }
    }
}

/// La page affichée → la section du guide qui l'explique (spec §3).
/// `switch` exhaustif, sans `default` : une destination ajoutée sans section
/// est une erreur de compilation.
enum HelpTopic {
    static let sectionIDs = ["first-launch", "install", "pause", "profiles", "updates",
                             "troubleshooting", "shortcuts", "performance", "translate",
                             "recover", "other-managers", "uninstall"]

    static func section(for destination: SidebarDestination,
                        diagnosticsSegment: DiagnosticsSegment,
                        alertsSegment: AlertsSegment) -> String {
        switch destination {
        case .home, .settings, .appChangelog: return "first-launch"
        case .mods, .discover: return "install"
        case .updates: return "updates"
        case .frenchTranslations: return "translate"
        case .profiles: return "profiles"
        case .saves, .backups, .maintenance, .quarantine: return "recover"
        case .systemAlerts: return alertsSegment == .keybinds ? "shortcuts" : "troubleshooting"
        case .logs: return diagnosticsSegment == .performance ? "performance" : "troubleshooting"
        }
    }
}
