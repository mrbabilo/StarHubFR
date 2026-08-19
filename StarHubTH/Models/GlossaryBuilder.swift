import Foundation

/// Tâche 7 du plan P2b — glossaire des termes du jeu, spec §5.
///
/// La construction croise les assets typés du jeu (`<asset>.xnb` anglais ↔
/// `<asset>.fr-FR.xnb`), appariés clé à clé ; une clé sans équivalent FR ne
/// produit rien, un asset absent est ignoré sans erreur. La gate qualité est
/// volontairement stricte (précision > rappel) : un mauvais terme empoisonne
/// le hint des chips et le prompt IA — mieux vaut un glossaire plus petit.
public enum GlossaryTermKind: String, Codable, Sendable {
    case item, bigCraftable, weapon, tool, clothing, npc, location, season
}

public struct GlossaryEntry: Codable, Equatable, Sendable {
    public let en: String
    public let fr: String
    public let kind: GlossaryTermKind

    public init(en: String, fr: String, kind: GlossaryTermKind) {
        self.en = en
        self.fr = fr
        self.kind = kind
    }
}

public enum GlossaryBuilder {

    /// Règle de clés d'une table typée (spec §5).
    private enum KeyRule {
        /// Toutes les clés de l'asset.
        case all
        /// Clés se terminant par `_Name` uniquement (nom, pas la description).
        case nameSuffix
        /// Les quatre clés de saison uniquement.
        case seasonsOnly
    }

    /// Assets typés dans l'ordre de priorité : sur un même `en`, la première
    /// table qui produit une entrée valide gagne.
    private static let tables: [(asset: String, kind: GlossaryTermKind, rule: KeyRule)] = [
        ("Objects", .item, .all),
        ("BigCraftables", .bigCraftable, .all),
        ("Weapons", .weapon, .nameSuffix),
        ("Tools", .tool, .nameSuffix),
        ("Pants", .clothing, .nameSuffix),
        ("Shirts", .clothing, .nameSuffix),
        ("NPCNames", .npc, .all),
        ("Locations", .location, .all),
        ("StringsFromCSFiles", .season, .seasonsOnly),
    ]

    /// Les clés de saison de `StringsFromCSFiles`, relevées dans l'asset du
    /// jeu : les quatre premières portent la saison **en minuscules**
    /// (`spring` → « printemps »), les `Utility.cs.568x` la portent
    /// capitalisée (`Spring` → « Printemps »). Le matching étant sensible
    /// à la casse, les deux formes méritent leur entrée.
    private static let seasonKeys: Set<String> = [
        "spring", "summer", "fall", "winter",
        "Utility.cs.5680", "Utility.cs.5681", "Utility.cs.5682", "Utility.cs.5683",
    ]

    /// Stoplist UI (la référence, spec §5) — minuscules, comparaison
    /// insensible à la casse.
    private static let stoplist: Set<String> = [
        "yes", "no", "ok", "okay", "cancel", "back", "next", "previous",
        "play", "pause", "quit", "exit", "menu", "options", "settings",
        "save", "load", "continue", "help", "done", "close", "open",
        "skip", "start", "stop", "new", "delete", "remove", "add", "edit",
        "on", "off", "book", "right", "left", "up", "down", "and", "or",
        "with", "good", "bad", "ran", "run",
    ]

    /// Accolades, crochets, sauts de ligne et tabulations — jamais dans un
    /// terme du glossaire (bruit de formatage, pas des noms propres).
    private static let forbiddenCharacters: Set<Character> = ["{", "}", "[", "]", "\n", "\r", "\t"]

    /// Ponctuation finale : une phrase, pas un nom.
    private static let endPunctuation: Set<Character> = [".", "!", "?", ":"]

    /// La gate qualité, testable seule. `true` = l'entrée entre au glossaire.
    ///
    /// `allowsLowercaseInitial` n'est levé que pour la table des saisons :
    /// le jeu écrit `spring` en minuscules et l'exiger capitalisé vidait la
    /// catégorie entière. Partout ailleurs la majuscule initiale reste le
    /// filtre qui écarte les fragments d'interface.
    public static func passesGate(en: String, fr: String,
                                  allowsLowercaseInitial: Bool = false) -> Bool {
        guard !en.isEmpty, !fr.isEmpty else { return false }
        guard en != fr else { return false }
        guard allowsLowercaseInitial || en.first?.isUppercase == true else { return false }
        guard en.count <= 30 else { return false }
        let enWords = en.split(whereSeparator: \.isWhitespace)
        guard enWords.count <= 4 else { return false }
        let frWords = fr.split(whereSeparator: \.isWhitespace)
        guard frWords.count <= enWords.count + 1 else { return false }
        guard forbiddenCharacters.isDisjoint(with: en),
              forbiddenCharacters.isDisjoint(with: fr) else { return false }
        guard let last = en.last, !endPunctuation.contains(last) else { return false }
        guard !stoplist.contains(en.lowercased()) else { return false }
        guard TranslationTokenCheck.extract(en).isEmpty else { return false }
        return true
    }

    /// Construit le glossaire depuis des maps d'asset injectées (XNB ou JSON —
    /// la source ne regarde pas, spec §5). La closure rend la map d'un asset
    /// par son nom (`Objects`, `Weapons`…), ou `nil` s'il est absent.
    /// Le rendu est trié par `en` croissant : déterministe d'un run à l'autre.
    public static func build(english: (String) -> [String: String]?,
                             french: (String) -> [String: String]?) -> [GlossaryEntry] {
        var accepted = Set<String>()
        var entries: [GlossaryEntry] = []
        for table in tables {
            guard let enMap = english(table.asset),
                  let frMap = french(table.asset) else { continue }
            for key in enMap.keys.sorted() where frMap[key] != nil && keeps(table.rule, key: key) {
                // Sept valeurs du jeu traînent une espace : on rabote avant
                // la gate, jamais un terme imposé au modèle avec son espace.
                let source = enMap[key]!.trimmingCharacters(in: .whitespaces)
                let target = frMap[key]!.trimmingCharacters(in: .whitespaces)
                guard !accepted.contains(source),
                      passesGate(en: source, fr: target,
                                 allowsLowercaseInitial: table.kind == .season)
                else { continue }
                accepted.insert(source)
                entries.append(GlossaryEntry(en: source, fr: target, kind: table.kind))
            }
        }
        return entries.sorted { $0.en < $1.en }
    }

    private static func keeps(_ rule: KeyRule, key: String) -> Bool {
        switch rule {
        case .all: true
        case .nameSuffix: key.hasSuffix("_Name")
        case .seasonsOnly: seasonKeys.contains(key)
        }
    }
}
