import Foundation

/// Un lot de traduction : les clés d'un mod qui n'ont pas encore de français,
/// dans **un** fichier qui se suffit à lui-même.
///
/// Le fichier est destiné à être déposé tel quel dans un modèle de chat : ses
/// consignes voyagent en tête, avant les données. C'est la troisième voie de
/// la référence, et la seule qui ne dépende ni d'un serveur local, ni d'une
/// clé d'API, ni d'un quota.
public struct TranslationLot: Codable, Equatable, Sendable {

    /// Une clé à traduire. `target` part **vide** : c'est la seule case que le
    /// modèle a le droit de remplir.
    public struct Entry: Codable, Equatable, Sendable {
        /// Le sous-dossier du mod, quand il en a plusieurs. Deux composants
        /// peuvent définir la même clé : ce sont deux entrées distinctes.
        public let component: String?
        public let key: String
        /// L'anglais. À ne jamais modifier — c'est lui qui appariera l'entrée
        /// au retour.
        public let source: String
        /// L'étiquette de section de l'auteur, en contexte. Non fiable :
        /// c'est un commentaire, pas une donnée.
        public let section: String?
        /// Les termes imposés pour cette entrée (`en` → `fr`).
        public let glossary: [String: String]
        /// La traduction. Vide à l'export.
        public var target: String

        public init(component: String?, key: String, source: String,
                    section: String?, glossary: [String: String], target: String) {
            self.component = component
            self.key = key
            self.source = source
            self.section = section
            self.glossary = glossary
            self.target = target
        }
    }

    public let formatVersion: Int
    public let mod: String
    public let language: String
    public let instructions: [String]
    public var entries: [Entry]

    /// La version du contrat du fichier, **relue** à l'import.
    public static let currentFormatVersion = 1

    public init(mod: String, language: String, entries: [Entry]) {
        self.formatVersion = Self.currentFormatVersion
        self.mod = mod
        self.language = language
        self.instructions = Self.instructions(language: language)
        self.entries = entries
    }

    /// Les consignes, en anglais : c'est la langue que les modèles suivent le
    /// mieux, et le fichier peut passer par n'importe quel chat.
    static func instructions(language: String) -> [String] {
        [
            "Translate each entry of \"entries\" from English into \(language).",
            "Write your translation into the \"target\" field. Leave every other "
                + "field exactly as it is — \"source\", \"key\" and \"component\" "
                + "must come back unchanged.",
            "Keep every game marker exactly as it appears in \"source\": things "
                + "like {{Token}}, $q, #$b#, %kid1, ${him^her^them}$. They are read "
                + "by the game, not shown to the player. Do not translate, reorder "
                + "or drop them.",
            "When an entry carries a \"glossary\", use those translations for those "
                + "terms — they are the game's own wording.",
            "Return the whole JSON document, with the same structure. No commentary, "
                + "no extra fields, no entries added or removed.",
        ]
    }

    /// Le lot d'un mod : **seulement** les clés `.missing` ou `.empty`, jamais
    /// une valeur française existante (spec §8.2). Délègue à
    /// `TranslationBatchPlanner.eligibleRows` la définition de « reste à
    /// traduire » plutôt que de la retester ici : `TranslationCoverage`
    /// stocke le français **brut**, donc un simple `row.french.isEmpty`
    /// laisserait passer une valeur faite uniquement d'espaces (état
    /// `.empty` malgré des octets non vides). `.orphan` est déjà écarté par
    /// `eligibleRows`, qui ne garde que `.missing`/`.empty` — inutile de le
    /// retester. Le garde-fou restant protège une rangée sans anglais de
    /// référence, qui n'a rien à traduire. Le glossaire, s'il est chargé,
    /// dépose sur chaque entrée les termes qui la concernent — le chat n'a
    /// pas la table du jeu.
    public static func build(mod: String, language: String,
                             rows: [TranslationCoverage.DiffRow],
                             glossary: Glossary?) -> TranslationLot {
        let entries = TranslationBatchPlanner.eligibleRows(rows).compactMap { row -> Entry? in
            guard !row.english.isEmpty else { return nil }
            let matched = glossary?.matchEntries(in: row.english) ?? []
            return Entry(component: row.component, key: row.key, source: row.english,
                         section: row.section,
                         glossary: Dictionary(matched.map { ($0.en, $0.fr) },
                                              uniquingKeysWith: { first, _ in first }),
                         target: "")
        }
        return TranslationLot(mod: mod, language: language, entries: entries)
    }
}
