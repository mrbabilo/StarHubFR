import Foundation

/// Une ligne de la palette ⌘K.
///
/// Le `kind` sert au groupement à l'écran et au départage : à égalité de
/// correspondance, une page passe devant un mod — les pages sont peu
/// nombreuses et l'utilisateur les vise sciemment.
///
/// ⚠️ Le nom porte `CommandPalette` et pas `Palette` seul : `SaveFarmerPalette`
/// désigne déjà les **couleurs du fermier** dans ce dépôt.
public struct CommandPaletteEntry: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable, Comparable {
        case destination, mod, profile, save

        var rank: Int {
            switch self {
            case .destination: return 0
            case .mod:         return 1
            case .profile:     return 2
            case .save:        return 3
            }
        }
        public static func < (a: Kind, b: Kind) -> Bool { a.rank < b.rank }
    }

    /// Composé (`"mod:<folderName>"`), jamais un index : un `ForEach` identifié
    /// par position ferait fuiter l'`@State` d'une ligne vers sa voisine à
    /// chaque frappe.
    public let id: String
    public let kind: Kind
    public let title: String
    public let subtitle: String?
    public let icon: String

    public init(id: String, kind: Kind, title: String,
                subtitle: String?, icon: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }

    public static func forDestination(_ entry: SidebarEntry,
                                      title: String) -> CommandPaletteEntry {
        CommandPaletteEntry(id: "dest:\(entry.destination.rawValue)",
                            kind: .destination, title: title,
                            subtitle: nil, icon: entry.icon)
    }

    public static func forMod(_ mod: ModItem) -> CommandPaletteEntry {
        CommandPaletteEntry(id: "mod:\(mod.folderName)", kind: .mod,
                            title: mod.name, subtitle: mod.folderName,
                            icon: "puzzlepiece.extension.fill")
    }

    /// Prend le **nom**, pas un `ModProfile` : ce type est interne au module
    /// Core, un test vivant dans un autre module ne peut pas en construire.
    public static func forProfile(name: String) -> CommandPaletteEntry {
        CommandPaletteEntry(id: "profile:\(name)", kind: .profile, title: name,
                            subtitle: nil, icon: "person.2.fill")
    }

    public static func forSave(playerName: String,
                               farmName: String) -> CommandPaletteEntry {
        CommandPaletteEntry(id: "save:\(playerName)|\(farmName)", kind: .save,
                            title: playerName, subtitle: farmName,
                            icon: "folder.fill")
    }
}

/// Le classement de la palette — pur, déterministe, testé.
///
/// Déterministe n'est pas un raffinement : sans départages complets, l'ordre
/// danse d'une frappe à l'autre et le classement n'est pas testable.
public enum CommandPaletteSearch {

    /// Nature de la correspondance, de la plus forte à la plus faible.
    private enum MatchKind: Int, Comparable {
        case exact = 0, prefix = 1, contains = 2, subsequence = 3, subtitle = 4
        static func < (a: MatchKind, b: MatchKind) -> Bool {
            a.rawValue < b.rawValue
        }
    }

    /// Locale figé, comme partout ailleurs dans le dépôt : le déterminisme.
    ///
    /// ⚠️ `.diacriticInsensitive` ne décompose PAS `œ` en `oe`. Mesuré le
    /// 2026-09-09 sur le parc réel : 1 098 manifestes, **zéro** nom portant
    /// `œ`/`æ`, zéro portant un diacritique — d'où l'absence de repli
    /// explicite. Le pliage sert les libellés FR des destinations
    /// (« Réglages », « Découvrir »…) et les noms de profils et de
    /// sauvegardes, que l'utilisateur écrit lui-même.
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive,
                            .widthInsensitive],
                  locale: Locale(identifier: "en_US_POSIX"))
    }

    /// `true` si `needle` apparaît dans `haystack` en gardant l'ordre des
    /// caractères, sans exiger la contiguïté — « cp » dans « content patcher ».
    private static func isSubsequence(_ needle: [Character],
                                      of haystack: [Character]) -> Bool {
        guard !needle.isEmpty else { return true }
        var i = needle.startIndex
        for c in haystack where c == needle[i] {
            i = needle.index(after: i)
            if i == needle.endIndex { return true }
        }
        return false
    }

    private struct Scored {
        let entry: CommandPaletteEntry
        let match: MatchKind
        let position: Int
        let length: Int
    }

    private static func score(_ entry: CommandPaletteEntry,
                              query: String) -> Scored? {
        let title = fold(entry.title)
        if title == query {
            return Scored(entry: entry, match: .exact, position: 0,
                          length: title.count)
        }
        if title.hasPrefix(query) {
            return Scored(entry: entry, match: .prefix, position: 0,
                          length: title.count)
        }
        if let r = title.range(of: query) {
            return Scored(entry: entry, match: .contains,
                          position: title.distance(from: title.startIndex,
                                                   to: r.lowerBound),
                          length: title.count)
        }
        if isSubsequence(Array(query), of: Array(title)) {
            return Scored(entry: entry, match: .subsequence, position: 0,
                          length: title.count)
        }
        if let sub = entry.subtitle, fold(sub).contains(query) {
            return Scored(entry: entry, match: .subtitle, position: 0,
                          length: title.count)
        }
        return nil
    }

    /// Les meilleures correspondances, les meilleures d'abord.
    ///
    /// Requête vide ⇒ les destinations seules : faire tomber 966 mods dans une
    /// palette qu'on vient d'ouvrir la rendrait illisible.
    ///
    /// `limit` borne l'**affichage**, jamais le parcours : il faut classer tout
    /// le parc pour savoir quels vingt sortir.
    public static func rank(_ query: String,
                            in entries: [CommandPaletteEntry],
                            limit: Int = 20) -> [CommandPaletteEntry] {
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else {
            return Array(entries.filter { $0.kind == .destination }.prefix(limit))
        }
        let scored = entries.compactMap { score($0, query: q) }
        let sorted = scored.sorted { a, b in
            if a.match != b.match { return a.match < b.match }
            if a.position != b.position { return a.position < b.position }
            if a.length != b.length { return a.length < b.length }
            if a.entry.kind != b.entry.kind { return a.entry.kind < b.entry.kind }
            return a.entry.title.localizedCompare(b.entry.title) == .orderedAscending
        }
        return Array(sorted.prefix(limit).map(\.entry))
    }
}
