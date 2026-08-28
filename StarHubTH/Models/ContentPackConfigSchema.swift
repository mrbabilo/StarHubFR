import Foundation

/// Une option décrite par le `ConfigSchema` d'un content pack.
///
/// Les champs facultatifs le sont **par mesure** : sur les 6376 tokens du parc,
/// `Default` est présent 6372 fois, `AllowValues` 5053, `Section` 4831,
/// `Description` 3378, `AllowBlank` 871, `AllowMultiple` 408 et `Name` 173.
/// Aucun n'est garanti ; l'appelant doit savoir afficher une option nue.
public struct ConfigSchemaOption: Equatable, Sendable {

    /// La clé du `ConfigSchema`, qui est **aussi** celle du `config.json` :
    /// c'est Content Patcher qui engendre le fichier depuis le schéma, d'où
    /// la couverture de 100 % mesurée. C'est ce que les mods C# n'ont pas —
    /// leur identifiant d'option GMCM est indépendant de la clé de config.
    public let token: String

    /// Libellé explicite. Absent, c'est `token` qu'on montre.
    public let name: String?
    public let description: String?

    /// Le regroupement. Absent de la documentation de référence, présent
    /// 4831 fois dans le parc — c'est lui qui remplace la liste à plat.
    public let section: String?

    /// Les valeurs admises, déjà découpées et nettoyées.
    public let allowValues: [String]

    /// La valeur par défaut **telle qu'écrite** : `0.5` reste `"0.5"`.
    /// Sert à proposer la réinitialisation et à repérer ce qui a été modifié.
    ///
    /// ⚠️ **Jamais découpée**, contrairement à `allowValues` : quand
    /// `allowMultiple` vaut vrai, le défaut porte lui-même des virgules
    /// (24 cas relevés). Comparer ce littéral à une sélection déjà découpée
    /// ne peut que donner un faux « modifié » — découper des deux côtés.
    public let defaultLiteral: String?

    public let allowBlank: Bool?
    public let allowMultiple: Bool?
}

/// Lit le `ConfigSchema` d'un `content.json` de Content Patcher.
///
/// C'est la **seule** description d'options qu'un mod publie sur le disque.
/// Les menus de config du jeu n'en écrivent aucune : Generic Mod Config Menu
/// garde tout en mémoire — ses libellés sont des `Func<string>` évaluées au
/// rendu — et l'export de Modern Config Menu ne porte que des valeurs.
/// Décompilation et mesures : `docs/audit-config-menus.md` (**C4-T4**).
public enum ContentPackConfigSchema {

    /// Ce que la lecture d'un `content.json` a donné.
    ///
    /// Les trois cas se ressemblent — aucune option à afficher — mais **un
    /// seul mérite d'être signalé**. Mesuré sur le parc : 591 `content.json`,
    /// dont **276 avec schéma, 301 sans, et 14 illisibles**. Confondre les
    /// deux derniers ferait afficher des clés brutes sans un mot d'explication
    /// aux 14, et un avertissement injustifié aux 301.
    public enum Reading: Equatable, Sendable {

        /// Le fichier n'a pas pu être analysé. À signaler : ce pack décrit
        /// peut-être ses options, et on n'a pas su les lire.
        case unreadable

        /// Lisible, mais sans `ConfigSchema` exploitable — le cas normal d'un
        /// pack qui n'expose aucune option. Rien à dire à l'utilisateur.
        case noSchema

        /// Au moins une option décrite, dans l'ordre du fichier.
        case options([ConfigSchemaOption])

        /// Les options, ou rien — pour l'appelant que la distinction
        /// n'intéresse pas.
        public var options: [ConfigSchemaOption] {
            if case .options(let options) = self { return options }
            return []
        }
    }

    /// Lit un `content.json` en distinguant l'absence de schéma de l'échec de
    /// lecture. Ne lève jamais.
    ///
    /// Les options sont rendues **dans l'ordre du fichier**, jamais triées :
    /// cet ordre est celui que l'auteur a choisi pour son écran de réglages.
    public static func read(_ contentJSON: String) -> Reading {
        guard case .object(let root)? = ConfigJSONTree.parse(contentJSON) else { return .unreadable }
        guard case .object(let schema)? = field(root, "ConfigSchema") else { return .noSchema }
        let options = self.options(in: schema)
        return options.isEmpty ? .noSchema : .options(options)
    }

    /// Les options seules. Passer par `read(_:)` quand il faut pouvoir
    /// avertir que le fichier était illisible.
    public static func parse(_ contentJSON: String) -> [ConfigSchemaOption] {
        read(contentJSON).options
    }

    private static func options(in schema: ConfigJSONTree.Object) -> [ConfigSchemaOption] {
        schema.keys.compactMap { token in
            guard case .object(let spec)? = schema.members[token] else { return nil }
            return ConfigSchemaOption(
                token: token,
                name: text(field(spec, "Name")),
                description: text(field(spec, "Description")),
                section: text(field(spec, "Section")),
                allowValues: values(field(spec, "AllowValues")),
                defaultLiteral: text(field(spec, "Default")),
                allowBlank: flag(field(spec, "AllowBlank")),
                allowMultiple: flag(field(spec, "AllowMultiple"))
            )
        }
    }

    // MARK: - Lecture tolérante

    /// La casse et les espaces ne comptent pas : le parc porte
    /// `Allow Multiple` avec une espace (40 fois) et `section` en minuscules
    /// (35 fois). Un champ non reconnu — les coquilles `HostowValues` et
    /// `HostowBlank` existent — est ignoré sans faire disparaître l'option.
    private static func field(_ object: ConfigJSONTree.Object,
                              _ name: String) -> ConfigJSONTree.Value? {
        let wanted = normalized(name)
        for key in object.keys where normalized(key) == wanted {
            return object.members[key]
        }
        return nil
    }

    private static func normalized(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace }
    }

    /// Rend un scalaire en texte sans le reformater — le littéral numérique
    /// est déjà une `String` dans l'arbre, précisément pour que `0.5` ne
    /// reparte pas en `0.500000`.
    private static func text(_ value: ConfigJSONTree.Value?) -> String? {
        switch value {
        case .string(let string): return string
        case .number(let literal): return literal
        case .bool(let flag):      return flag ? "true" : "false"
        default:                   return nil
        }
    }

    /// `AllowValues` est toujours une chaîne à virgules (5053 relevés, aucun
    /// tableau). La virgule traînante est courante — `"3, 7, 14, 21,"` — et
    /// produirait sans ce filtre un choix vide, sélectionnable et sans nom.
    private static func values(_ value: ConfigJSONTree.Value?) -> [String] {
        guard let raw = text(value) else { return [] }
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Les drapeaux sont booléens 1220 fois, mais des chaînes 99 fois.
    private static func flag(_ value: ConfigJSONTree.Value?) -> Bool? {
        switch value {
        case .bool(let flag): return flag
        case .string(let string):
            switch string.lowercased() {
            case "true":  return true
            case "false": return false
            default:      return nil
            }
        default: return nil
        }
    }
}
