import Foundation

/// Ce que l'éditeur visuel de `config.json` fait d'un `ConfigJSONTree`
/// (**C4-T5**) : l'aplatir en options affichables, puis y réinjecter la
/// **seule** valeur que l'utilisateur vient de changer.
///
/// Pourquoi ces règles vivent en Core et pas dans la vue : l'écran est hors de
/// portée de `swift test`, et ce qui s'y cassait ne se voyait pas —
/// l'éditeur listait les options par ordre alphabétique (`dict.keys.sorted()`)
/// alors que **363 des 462 `config.json` de premier niveau du parc** ont un
/// ordre d'auteur différent, et il réécrivait le fichier entier à chaque
/// clic, ce qui repassait tous les nombres par un `Double`.
///
/// Le principe tenu ici : **on ne réécrit que le nœud touché**. Une valeur que
/// l'utilisateur n'a pas ouverte ressort avec le littéral exact de son fichier
/// (`1.50` reste `1.50`, `9007199254740993` ne devient pas `…92`).
public enum ConfigEditorModel {

    /// Une valeur éditable du fichier, avec le chemin qui y mène.
    ///
    /// `keyPath` mêle des clés d'objet et des index de tableau notés `[0]` :
    /// c'est une notation d'**affichage**. `apply` ne la relit jamais pour
    /// deviner un type — c'est le conteneur rencontré qui trancherait, si
    /// bien qu'une clé d'objet nommée `"[0]"` reste une clé.
    public struct Leaf: Equatable, Sendable {
        public let keyPath: [String]
        public let value: ConfigJSONTree.Value

        public init(keyPath: [String], value: ConfigJSONTree.Value) {
            self.keyPath = keyPath
            self.value = value
        }
    }

    // MARK: - Aplatissement

    /// Les feuilles éditables de l'arbre, **dans l'ordre du fichier**.
    ///
    /// `null` est écarté : sans type, il n'offre aucun contrôle à l'écran, et
    /// le retyper en chaîne écrirait autre chose que ce que l'auteur a posé.
    public static func leaves(of value: ConfigJSONTree.Value) -> [Leaf] {
        var out: [Leaf] = []
        collect(value, path: [], into: &out)
        return out
    }

    private static func collect(_ value: ConfigJSONTree.Value,
                                path: [String],
                                into out: inout [Leaf]) {
        switch value {
        case .object(let object):
            for key in object.keys {
                guard let child = object.members[key] else { continue }
                collect(child, path: path + [key], into: &out)
            }
        case .array(let items):
            for (index, item) in items.enumerated() {
                collect(item, path: path + ["[\(index)]"], into: &out)
            }
        case .null:
            break
        case .string, .number, .bool:
            out.append(Leaf(keyPath: path, value: value))
        }
    }

    // MARK: - Application d'une édition

    /// Remplace la valeur au bout de `keyPath`, et rien d'autre.
    ///
    /// `nil` quand le chemin ne retombe pas sur une feuille de l'arbre — le
    /// chemin vient toujours de l'arbre lui-même, donc un échec signifie que
    /// le texte a changé sous l'écran. Créer la clé au passage (ce que faisait
    /// l'ancien `setValue`, avec son `dict[first] ?? [String: Any]()`)
    /// ajouterait au `config.json` une option que le mod n'a jamais lue.
    public static func apply(_ newValue: ConfigJSONTree.Value,
                             at keyPath: [String],
                             to tree: ConfigJSONTree.Value) -> ConfigJSONTree.Value? {
        guard let segment = keyPath.first else { return nil }
        let rest = Array(keyPath.dropFirst())

        switch tree {
        case .object(var object):
            guard let child = object.members[segment] else { return nil }
            guard let updated = rest.isEmpty ? newValue : apply(newValue, at: rest, to: child)
            else { return nil }
            object.members[segment] = updated
            return .object(object)

        case .array(var items):
            guard let index = arrayIndex(segment), index >= 0, index < items.count else { return nil }
            guard let updated = rest.isEmpty ? newValue : apply(newValue, at: rest, to: items[index])
            else { return nil }
            items[index] = updated
            return .array(items)

        default:
            // Un scalaire n'a pas d'enfant : le chemin est plus profond que
            // l'arbre.
            return nil
        }
    }

    /// L'index porté par un segment `[3]`, `nil` sinon.
    private static func arrayIndex(_ segment: String) -> Int? {
        guard segment.hasPrefix("["), segment.hasSuffix("]") else { return nil }
        return Int(segment.dropFirst().dropLast())
    }

    // MARK: - Le contrôle qu'une valeur mérite à l'écran

    /// Ce que l'écran doit offrir pour une valeur donnée.
    ///
    /// Le tri est fait **ici** parce que deux de ses cas sont des pièges :
    /// une chaîne `"true"` qui doit rester une chaîne une fois basculée, et un
    /// littéral entier trop grand pour un `Int` — `Int(1e19)` piège à
    /// l'exécution, ce que l'ancien champ entier faisait à chaque rendu.
    public enum Control: Equatable, Sendable {
        /// `asString` : la valeur d'origine était la chaîne `"true"`/`"false"`,
        /// pas un booléen JSON. Le mod attend ce type-là.
        case toggle(Bool, asString: Bool)
        case integer(Int)
        case decimal(Double)
        case text(String)
    }

    public static func control(for value: ConfigJSONTree.Value) -> Control? {
        switch value {
        case .bool(let flag):
            return .toggle(flag, asString: false)
        case .string(let text):
            switch text.lowercased() {
            case "true":  return .toggle(true, asString: true)
            case "false": return .toggle(false, asString: true)
            default:      return .text(text)
            }
        case .number(let literal):
            guard let number = doubleValue(ofLiteral: literal), number.isFinite else { return nil }
            if isIntegerLiteral(literal), let integer = Int(exactly: number) { return .integer(integer) }
            return .decimal(number)
        case .object, .array, .null:
            return nil
        }
    }

    /// La valeur à réinjecter dans l'arbre après une édition, `nil` quand elle
    /// ne s'écrit pas (voir `numberLiteral`).
    public static func value(of control: Control) -> ConfigJSONTree.Value? {
        switch control {
        case .toggle(let flag, let asString):
            return asString ? .string(flag ? "true" : "false") : .bool(flag)
        case .integer(let integer):
            return .number(String(integer))
        case .decimal(let number):
            guard let literal = numberLiteral(number, asInteger: false) else { return nil }
            return .number(literal)
        case .text(let text):
            return .string(text)
        }
    }

    // MARK: - Littéraux numériques

    /// `true` quand le littéral s'édite au pas de 1 (champ entier), `false`
    /// quand il porte une partie décimale ou un exposant.
    public static func isIntegerLiteral(_ literal: String) -> Bool {
        !literal.contains(".") && !literal.lowercased().contains("e")
    }

    /// La valeur d'un littéral, pour le seul usage de l'affichage.
    public static func doubleValue(ofLiteral literal: String) -> Double? {
        Double(literal)
    }

    /// Le littéral à écrire pour un nombre que l'utilisateur vient de saisir.
    ///
    /// `nil` quand il n'y a rien d'écrivable : `Int(1e19)` **piège à
    /// l'exécution**, et l'ancien éditeur faisait exactement cette conversion
    /// sur la valeur d'un champ.
    public static func numberLiteral(_ value: Double, asInteger: Bool) -> String? {
        guard value.isFinite else { return nil }
        if asInteger {
            guard let integer = Int(exactly: value.rounded(.towardZero)) else { return nil }
            return String(integer)
        }
        return String(value)
    }
}
