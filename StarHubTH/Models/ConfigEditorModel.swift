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
        /// Une valeur prise dans la liste que le schéma du pack déclare
        /// (`AllowValues`). `among` porte déjà l'entrée vide quand le schéma
        /// l'autorise, et la valeur courante en tête quand elle n'est pas
        /// dans la liste.
        case choice(selected: String, among: [String])
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
        case .choice(let selected, _):
            // Les 3900 clés décrites du parc sont des chaînes JSON : c'est
            // Content Patcher qui engendre le fichier, et il n'écrit que ça.
            return .string(selected)
        }
    }

    /// Le texte d'une valeur scalaire — de quoi la comparer aux littéraux d'un
    /// schéma, qui sont tous des chaînes.
    public static func literalText(of value: ConfigJSONTree.Value) -> String? {
        switch value {
        case .string(let text): return text
        case .bool(let flag):   return flag ? "true" : "false"
        case .number(let text): return text
        case .object, .array, .null: return nil
        }
    }

    /// Une valeur écrite depuis un littéral de schéma, **dans le type que le
    /// fichier emploie déjà** : remettre un défaut ne doit pas changer un
    /// booléen en chaîne au passage.
    public static func value(ofLiteral literal: String,
                             matchingTypeOf current: ConfigJSONTree.Value) -> ConfigJSONTree.Value? {
        switch current {
        case .string:
            return .string(literal)
        case .bool:
            switch literal.lowercased() {
            case "true":  return .bool(true)
            case "false": return .bool(false)
            default:      return nil
            }
        case .number:
            guard Double(literal) != nil else { return nil }
            return .number(literal)
        case .object, .array, .null:
            return nil
        }
    }

    // MARK: - Fusion avec le schéma d'un content pack

    /// Une rangée de l'écran : la valeur, plus ce que le schéma du pack en dit.
    ///
    /// Sans schéma — les 246 mods C# du parc, qui n'en publient aucun — les
    /// champs venus du schéma sont nuls et la rangée vaut exactement ce que
    /// l'écran affichait avant.
    public struct Row: Equatable, Sendable, Identifiable {
        public let keyPath: [String]
        /// `Name` du schéma quand il existe (rare : 173 tokens sur tout le
        /// parc), sinon la clé elle-même.
        public let label: String
        public let description: String?
        public let control: Control
        /// Le contrôle qui remettrait le défaut du schéma — **non nul
        /// seulement quand la valeur s'en écarte**, ce qui en fait aussi le
        /// marqueur « modifié ». 161 clés du parc sont dans ce cas.
        public let defaultControl: Control?
        /// La valeur courante n'est pas dans la liste que le schéma admet.
        /// 6 cas relevés sur le parc (`ShirtSpring = WarmWeather` quand le
        /// schéma dit `Cold | Vanilla | Warm`).
        public let isOutsideAllowedValues: Bool

        public var id: String { keyPath.joined(separator: "\u{1}") }

        public init(keyPath: [String], label: String, description: String?,
                    control: Control, defaultControl: Control?,
                    isOutsideAllowedValues: Bool) {
            self.keyPath = keyPath
            self.label = label
            self.description = description
            self.control = control
            self.defaultControl = defaultControl
            self.isOutsideAllowedValues = isOutsideAllowedValues
        }
    }

    /// Les rangées d'une section. `section` nulle = celles que le schéma n'a
    /// pas rangées, ou l'intégralité du fichier quand il n'y a pas de schéma.
    public struct Group: Equatable, Sendable {
        public let section: String?
        public let rows: [Row]

        public init(section: String?, rows: [Row]) {
            self.section = section
            self.rows = rows
        }
    }

    /// Les options du fichier, groupées par section du schéma.
    ///
    /// Les sections sortent **dans leur ordre d'apparition** dans le fichier —
    /// mesuré sur le parc : cet ordre est celui du schéma dans les 210 packs,
    /// Content Patcher engendrant l'un depuis l'autre. Le groupe sans section
    /// vient en dernier (11 packs mêlent les deux).
    public static func groups(of tree: ConfigJSONTree.Value,
                              describedBy options: [ConfigSchemaOption]) -> [Group] {
        var index: [String: ConfigSchemaOption] = [:]
        for option in options where index[option.token.lowercased()] == nil {
            index[option.token.lowercased()] = option
        }

        var sectionOrder: [String] = []
        var bySection: [String: [Row]] = [:]
        var unsectioned: [Row] = []

        for leaf in leaves(of: tree) {
            let option = leaf.keyPath.last.flatMap { index[$0.lowercased()] }
            guard let row = row(for: leaf, describedBy: option) else { continue }
            guard let section = option?.section else { unsectioned.append(row); continue }
            if bySection[section] == nil { sectionOrder.append(section) }
            bySection[section, default: []].append(row)
        }

        var groups = sectionOrder.map { Group(section: $0, rows: bySection[$0] ?? []) }
        if !unsectioned.isEmpty || groups.isEmpty {
            groups.append(Group(section: nil, rows: unsectioned))
        }
        return groups
    }

    private static func row(for leaf: Leaf, describedBy option: ConfigSchemaOption?) -> Row? {
        guard var control = control(for: leaf.value) else { return nil }
        var isOutside = false
        if let option, let choice = choiceControl(for: leaf.value, option: option) {
            control = choice.control
            isOutside = choice.isOutside
        }
        return Row(keyPath: leaf.keyPath,
                   label: option?.name ?? leaf.keyPath.last ?? "",
                   description: option?.description,
                   control: control,
                   defaultControl: defaultControl(of: leaf.value, shownAs: control, option: option),
                   isOutsideAllowedValues: isOutside)
    }

    /// La liste déroulante que le schéma justifie, ou `nil` pour garder le
    /// contrôle d'origine.
    ///
    /// Deux refus mesurés sur le parc : `true`/`false` reste un interrupteur
    /// (2801 des 3777 clés à valeurs admises — un menu à deux entrées serait
    /// une régression), et un choix multiple reste un champ texte (22 clés :
    /// la valeur y est une liste à virgules qu'un menu à choix unique
    /// réduirait à une seule entrée).
    private static func choiceControl(for value: ConfigJSONTree.Value,
                                      option: ConfigSchemaOption) -> (control: Control, isOutside: Bool)? {
        guard !option.allowValues.isEmpty, option.allowMultiple != true else { return nil }
        guard Set(option.allowValues.map { $0.lowercased() }) != ["true", "false"] else { return nil }
        guard let current = literalText(of: value) else { return nil }

        var among = option.allowValues
        if option.allowBlank == true, !among.contains("") { among.append("") }

        if let position = among.firstIndex(where: { $0.lowercased() == current.lowercased() }) {
            // ⚠️ C'est **l'orthographe du fichier** qui est retenue, pas celle
            // du schéma. Rendre celle du schéma ferait réécrire le fichier au
            // premier passage dans le menu là où les deux ne diffèrent que par
            // la casse — 3 clés du parc (`spring` contre `Spring`). Les autres
            // entrées gardent l'orthographe du schéma.
            among[position] = current
            return (.choice(selected: current, among: among), false)
        }
        // Jamais remplacée en silence : elle prend la tête de la liste et
        // l'appelant la signale.
        among.insert(current, at: 0)
        return (.choice(selected: current, among: among), true)
    }

    private static func defaultControl(of value: ConfigJSONTree.Value,
                                       shownAs control: Control,
                                       option: ConfigSchemaOption?) -> Control? {
        guard let option, let literal = option.defaultLiteral,
              let current = literalText(of: value),
              !isSameValue(current, literal, multiple: option.allowMultiple == true) else { return nil }

        if case .choice(_, let among) = control {
            let spelling = among.first { $0.lowercased() == literal.lowercased() } ?? literal
            return .choice(selected: spelling, among: among)
        }
        guard let defaultValue = self.value(ofLiteral: literal, matchingTypeOf: value) else { return nil }
        return self.control(for: defaultValue)
    }

    /// ⚠️ Quand plusieurs valeurs sont admises, le défaut porte lui-même des
    /// virgules (24 cas relevés) : comparer les deux chaînes telles quelles
    /// annoncerait « modifié » dès que l'ordre diffère.
    private static func isSameValue(_ current: String, _ literal: String, multiple: Bool) -> Bool {
        if multiple { return commaList(current) == commaList(literal) }
        return normalized(current) == normalized(literal)
    }

    private static func commaList(_ text: String) -> Set<String> {
        Set(text.split(separator: ",").map { normalized(String($0)) }.filter { !$0.isEmpty })
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
