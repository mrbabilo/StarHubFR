import Foundation

/// Le type attendu d'une valeur d'un `.xnb` typé, tel que le jeu l'a
/// sérialisé. Sert de guide à `XnbTypedReader` : le fichier ne dit pas la
/// forme de son contenu, seulement le nom des readers employés.
///
/// `object` : `name` = nom .NET complet du type (`StardewValley.GameData.
/// Objects.ObjectData`), `members` dans l'ordre de sérialisation du
/// `ReflectiveReader` — classe de base d'abord, puis, dans chaque classe,
/// les propriétés publiques avant les champs.
public indirect enum XnbSchema: Sendable {
    case string
    case int
    case bool
    case float
    case double
    /// Une énumération : un `Int32` nu.
    case enumInt
    /// `Nullable<T>` : un `bool`, puis la valeur s'il est vrai.
    case nullable(XnbSchema)
    case list(XnbSchema)
    case dictionary(key: XnbSchema, value: XnbSchema)
    case object(name: String, members: [(String, XnbSchema)])

    /// Type valeur .NET : lu nu dans un objet, une liste ou un dictionnaire,
    /// sans index de reader devant.
    var isValueType: Bool {
        switch self {
        case .int, .bool, .float, .double, .enumInt, .nullable: true
        case .string, .list, .dictionary, .object: false
        }
    }

    /// Le reader que le fichier doit déclarer pour ce type.
    var expectedReader: XnbTypePattern {
        let content = "Microsoft.Xna.Framework.Content."
        switch self {
        case .string: return .named(content + "StringReader", [])
        case .int: return .named(content + "Int32Reader", [])
        case .bool: return .named(content + "BooleanReader", [])
        case .float: return .named(content + "SingleReader", [])
        case .double: return .named(content + "DoubleReader", [])
        case .enumInt: return .named(content + "EnumReader`1", [.any])
        case .nullable(let inner): return .named(content + "NullableReader`1", [inner.typeName])
        case .list(let element): return .named(content + "ListReader`1", [element.typeName])
        case .dictionary(let key, let value):
            return .named(content + "DictionaryReader`2", [key.typeName, value.typeName])
        case .object(let name, _): return .named(content + "ReflectiveReader`1", [.named(name, [])])
        }
    }

    /// Le nom .NET du type, argument générique d'un reader. Le nom d'une
    /// énumération n'est pas dans le schéma : n'importe lequel convient.
    private var typeName: XnbTypePattern {
        switch self {
        case .string: .named("System.String", [])
        case .int: .named("System.Int32", [])
        case .bool: .named("System.Boolean", [])
        case .float: .named("System.Single", [])
        case .double: .named("System.Double", [])
        case .enumInt: .any
        case .nullable(let inner): .named("System.Nullable`1", [inner.typeName])
        case .list(let element): .named("System.Collections.Generic.List`1", [element.typeName])
        case .dictionary(let key, let value):
            .named("System.Collections.Generic.Dictionary`2", [key.typeName, value.typeName])
        case .object(let name, _): .named(name, [])
        }
    }
}

/// Une valeur lue. `null` : référence nulle ou `Nullable` sans valeur.
/// Une énumération se lit `int`.
public indirect enum XnbValue: Equatable, Sendable {
    case null
    case string(String)
    case int(Int32)
    case bool(Bool)
    case float(Float)
    case double(Double)
    case list([XnbValue])
    case dictionary([XnbPair])
    case object([String: XnbValue])
}

/// Une paire de dictionnaire, dans l'ordre du fichier.
public struct XnbPair: Equatable, Sendable {
    public let key: XnbValue
    public let value: XnbValue

    public init(key: XnbValue, value: XnbValue) {
        self.key = key
        self.value = value
    }
}

/// Nom de type .NET attendu, arguments génériques compris ; `any` accepte
/// n'importe quel type à cette place.
indirect enum XnbTypePattern: Equatable, Sendable {
    case any
    case named(String, [XnbTypePattern])

    /// Forme courte, sans qualificatif d'assembly (`ListReader\`1[[System.String]]`).
    var description: String {
        switch self {
        case .any: return "*"
        case .named(let name, let arguments):
            guard !arguments.isEmpty else { return name }
            return name + "[" + arguments.map { "[\($0.description)]" }.joined(separator: ",") + "]"
        }
    }

    /// Compare au nom écrit dans le fichier, dont chaque argument générique
    /// est qualifié par son assembly (`[[System.String, mscorlib, …]]`).
    func matches(_ written: String) -> Bool {
        var parser = TypeNameParser(Array(written))
        guard let parsed = parser.typeName(), parser.atEnd else { return false }
        return matches(parsed)
    }

    private func matches(_ parsed: TypeNameParser.Parsed) -> Bool {
        switch self {
        case .any: return true
        case .named(let name, let arguments):
            return name == parsed.name && arguments.count == parsed.arguments.count
                && zip(arguments, parsed.arguments).allSatisfy { $0.matches($1) }
        }
    }
}

/// Analyse un nom de type .NET : `Nom`, ou `Nom\`n[[Arg, Assembly…],[…]]`.
private struct TypeNameParser {
    struct Parsed {
        let name: String
        let arguments: [Parsed]
    }

    private let chars: [Character]
    private var pos = 0

    init(_ chars: [Character]) { self.chars = chars }

    var atEnd: Bool { pos == chars.count }

    private func peek(_ offset: Int = 0) -> Character? {
        pos + offset < chars.count ? chars[pos + offset] : nil
    }

    mutating func typeName() -> Parsed? {
        var name = ""
        while let char = peek(), char != ",", char != "]" {
            if char == "[" {
                guard peek(1) == "]" else { break }   // `[]` : tableau, partie du nom
                name += "[]"
                pos += 2
            } else {
                name.append(char)
                pos += 1
            }
        }
        guard !name.isEmpty else { return nil }
        guard peek() == "[" else { return Parsed(name: name, arguments: []) }
        pos += 1
        var arguments: [Parsed] = []
        repeat {
            guard peek() == "[" else { return nil }
            pos += 1
            guard let argument = typeName() else { return nil }
            // Qualificatif d'assembly (`, mscorlib, Version=…`) : ignoré.
            while let char = peek(), char != "]" { pos += 1 }
            guard peek() == "]" else { return nil }
            pos += 1
            arguments.append(argument)
            guard peek() == "," else { break }
            pos += 1
        } while true
        guard peek() == "]" else { return nil }
        pos += 1
        return Parsed(name: name, arguments: arguments)
    }
}
