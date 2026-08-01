import Foundation

/// Une traduction thaïe publiée au catalogue.
///
/// Le type ne sait plus se traduire lui-même : il exposait deux méthodes prenant
/// le ViewModel en paramètre, ce qui faisait remonter un modèle vers la couche
/// au-dessus et l'excluait du module testable. Il rend désormais une **clé** de
/// localisation, que la vue traduit — même correction que celle appliquée en
/// amont (`AppleBoiy/StarHubTH`, étape 2.1 de leur refactor).
public struct ThaiTranslationMod: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let author: String
    public let version: String
    public let status: String
    public let url: String
    public let nexusUrl: String
    public var isInstalled: Bool = false
    public var isOriginalModInstalled: Bool = false

    public init(name: String, author: String, version: String, status: String,
                url: String, nexusUrl: String,
                isInstalled: Bool = false, isOriginalModInstalled: Bool = false) {
        self.name = name
        self.author = author
        self.version = version
        self.status = status
        self.url = url
        self.nexusUrl = nexusUrl
        self.isInstalled = isInstalled
        self.isOriginalModInstalled = isOriginalModInstalled
    }

    /// Ce qu'on peut faire de cette traduction, sous forme de clé L10n : déjà
    /// installée, téléchargeable, ou inutile faute du mod d'origine.
    public var availabilityKey: String {
        if isInstalled { return L10n.ThaiHub.installed }
        if isOriginalModInstalled { return L10n.ThaiHub.availableDownload }
        return L10n.ThaiHub.missingOriginal
    }
}

/// Découpe le catalogue des traductions, publié sous forme de tableau Markdown
/// dans un dépôt tiers.
///
/// Extrait du ViewModel, où rien ne le testait — alors qu'il dépend entièrement
/// d'une mise en forme que nous ne maîtrisons pas : le repère d'en-tête est le
/// libellé thaï de la première colonne, écrit en dur. Si le dépôt source le
/// renomme, le catalogue devient vide (et non erroné) ; c'est le comportement
/// d'origine, figé par un test plutôt que corrigé ici.
public enum ThaiTranslationTable {
    /// Repère de début : la première cellule d'en-tête du tableau, en thaï.
    private static let headerPrefix = "| ชื่อม็อด"
    /// `[Texte](cible)` — le texte peut lui-même contenir des crochets, comme
    /// dans `[[CP] Nom](url)`, d'où la capture non gourmande.
    private static let linkPattern = "\\[(.*?)\\]\\((.*?)\\)"

    public static func parse(_ markdown: String) -> [ThaiTranslationMod] {
        var mods: [ThaiTranslationMod] = []
        var inTable = false

        for line in markdown.components(separatedBy: .newlines) {
            if line.starts(with: headerPrefix) {
                inTable = true
                continue
            }
            guard inTable else { continue }
            // Ligne de séparation (`| :--- | :--- |`) : mise en forme, pas un mod.
            if line.starts(with: "| :---") { continue }
            if line.starts(with: "|") {
                let parts = line.components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                // Une ligne tronquée n'est pas complétée au jugé : on la saute.
                guard parts.count >= 6 else { continue }

                let (name, url) = unwrapLink(parts[1].replacingOccurrences(of: "**", with: ""))
                mods.append(ThaiTranslationMod(name: name,
                                               author: parts[2],
                                               version: parts[3],
                                               status: parts[4],
                                               url: url,
                                               nexusUrl: linkTarget(in: parts[5])))
            } else if line.isEmpty {
                // En Markdown, une ligne vide referme le tableau : ce qui suit
                // est de la prose.
                inTable = false
            }
        }
        return mods
    }

    /// `[Texte](cible)` → (`Texte`, `cible`). Rend le texte inchangé et une
    /// cible vide quand il n'y a pas de lien — certaines lignes n'en portent pas.
    private static func unwrapLink(_ text: String) -> (name: String, url: String) {
        guard let regex = try? NSRegularExpression(pattern: linkPattern),
              let match = regex.firstMatch(in: text, options: [],
                                           range: NSRange(location: 0, length: text.utf16.count)),
              let nameRange = Range(match.range(at: 1), in: text) else {
            return (text, "")
        }
        let url = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
        return (String(text[nameRange]), url)
    }

    /// La cible d'un lien Markdown, ou une chaîne vide. Volontairement tolérant :
    /// la colonne Nexus contient parfois un tiret au lieu d'un lien.
    private static func linkTarget(in text: String) -> String {
        guard let open = text.range(of: "("), let close = text.range(of: ")") else { return "" }
        return String(text[text.index(after: open.lowerBound)..<close.lowerBound])
    }
}
