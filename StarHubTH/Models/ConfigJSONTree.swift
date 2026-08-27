import Foundation

/// Un JSON ordonné et imbriqué, taillé pour le `config.json` d'un mod.
///
/// Pourquoi ce type existe alors que `OrderedJSONWriter` et
/// `I18nLenientParser` sont déjà là (spec §5.2) : l'écrivain est **plat**
/// (`[String: String]`), écrit avec un saut de ligne final, omet les valeurs
/// vides et perd `$schema` ; le parseur lit des fichiers de traduction
/// clé→chaîne, pas des objets à 8 niveaux avec tableaux et nombres. Trois de
/// ces quatre comportements sont justes pour un fichier `i18n` et faux pour
/// un `config.json`.
///
/// Les **nombres sont portés en texte brut** : `Double` transformerait
/// `9007199254740993` en `9007199254740992` et un jour `0.1` en
/// `0.10000000000000004`. Le littéral d'origine est la seule forme fidèle —
/// et le `config.json` est réécrit par SMAPI à chaque lancement, pas par
/// nous : ce qu'on doit à l'auteur, c'est l'**ordre des clés** (celui des
/// champs de sa classe C#) et la forme de ses nombres.
public enum ConfigJSONTree {

    /// Un objet JSON qui se souvient de l'ordre de ses clés.
    ///
    /// `keys` ne porte jamais deux fois la même clé : face à un doublon dans
    /// le texte, la position reste celle de la première rencontre et la
    /// valeur celle de la dernière — le comportement de Newtonsoft sur un
    /// dictionnaire, sans perdre l'ordre.
    public struct Object: Equatable, Sendable {
        public var keys: [String]
        public var members: [String: Value]

        public init(_ pairs: [(String, Value)]) {
            keys = []
            members = [:]
            for (key, value) in pairs {
                if members[key] == nil { keys.append(key) }
                members[key] = value
            }
        }

        public init(keys: [String], members: [String: Value]) {
            self.keys = keys
            self.members = members
        }
    }

    public indirect enum Value: Equatable, Sendable {
        case object(Object)
        case array([Value])
        case string(String)
        /// Le littéral d'origine, jamais un `Double` (voir le doc de l'enum).
        case number(String)
        case bool(Bool)
        case null
    }

    // MARK: - Analyse

    /// Parse un `config.json` avec la tolérance de Newtonsoft — le chargeur
    /// réel de SMAPI (mesuré par l'oracle du dépôt, pas déduit du schéma) :
    /// commentaires `//` et `/* */`, virgules traînantes avant `}` et `]`.
    ///
    /// `nil` sur texte cassé : le repli verbatim de la restauration dépend
    /// de ce `nil` — un arbre partiel rendu « tolerant » ferait écrire une
    /// reconstruction au lieu du texte mémorisé.
    ///
    /// Tout le travail se fait sur des `Unicode.Scalar` : en Swift, `\r\n`
    /// est **un seul `Character`**, et la première version du parseur lenient
    /// coupait les commentaires de ligne jusqu'à la fin de chacun des 1474
    /// fichiers CRLF du parc pour cette raison exacte.
    public static func parse(_ text: String) -> Value? {
        var scanner = Cursor(text: text)
        scanner.skipTrivia()
        guard let value = parseValue(&scanner) else { return nil }
        scanner.skipTrivia()
        guard scanner.isAtEnd else { return nil }
        // Un `config.json` est un objet. Accepter un scalaire en racine
        // donnerait au merge et au diff des arbres sans clé — aucun sens
        // pour ce format.
        guard case .object = value else { return nil }
        return value
    }

    // MARK: - Curseur

    /// Un curseur conscient des chaînes : `skipTrivia` saute les blancs et
    /// les commentaires, mais jamais *à l'intérieur* d'une chaîne — c'est le
    /// point qui distingue un parseur d'une expression régulière.
    private struct Cursor {
        let scalars: [Unicode.Scalar]
        var index = 0

        init(text: String) { scalars = Array(text.unicodeScalars) }

        var current: Unicode.Scalar? { index < scalars.count ? scalars[index] : nil }
        var isAtEnd: Bool { index >= scalars.count }

        mutating func advance() { index += 1 }

        mutating func skipTrivia() {
            while let c = current {
                if c == " " || c == "\t" || c == "\n" || c == "\r" {
                    advance(); continue
                }
                if c == "/" {
                    let next = index + 1 < scalars.count ? scalars[index + 1] : nil
                    if next == "/" {                 // commentaire de ligne
                        advance(); advance()
                        while let l = current, l != "\n" { advance() }
                        continue
                    }
                    if next == "*" {                 // commentaire de bloc
                        advance(); advance()
                        var closed = false
                        while !isAtEnd {
                            if current == "*" , index + 1 < scalars.count,
                               scalars[index + 1] == "/" {
                                advance(); advance(); closed = true; break
                            }
                            advance()
                        }
                        if !closed { index = scalars.count }  // bloc non fermé : tout commenter
                        continue
                    }
                }
                break
            }
        }
    }

    // MARK: - Grammaire

    private static func parseValue(_ s: inout Cursor) -> Value? {
        s.skipTrivia()
        guard let c = s.current else { return nil }
        switch c {
        case "{": return parseObject(&s)
        case "[": return parseArray(&s)
        case "\"": return parseString(&s).map(Value.string)
        case "t": return literal(&s, "true", .bool(true))
        case "f": return literal(&s, "false", .bool(false))
        case "n": return literal(&s, "null", .null)
        default:  return parseNumber(&s)
        }
    }

    private static func literal(_ s: inout Cursor, _ word: String, _ value: Value) -> Value? {
        for expected in word.unicodeScalars {
            guard s.current == expected else { return nil }
            s.advance()
        }
        return value
    }

    private static func parseObject(_ s: inout Cursor) -> Value? {
        s.advance()                                   // '{'
        var pairs: [(String, Value)] = []
        var lastWasValue = false
        while true {
            s.skipTrivia()
            guard let c = s.current else { return nil }
            if c == "}" { s.advance(); break }
            if c == "," {
                // Une virgule ne vaut qu'après une valeur — la traînante est
                // tolérée parce qu'elle précède '}', jamais une seconde fois.
                guard lastWasValue else { return nil }
                lastWasValue = false
                s.advance(); continue
            }
            guard c == "\"" , let key = parseString(&s) else { return nil }
            s.skipTrivia()
            guard s.current == ":" else { return nil }
            s.advance()
            guard let value = parseValue(&s) else { return nil }
            pairs.append((key, value))
            lastWasValue = true
        }
        return .object(Object(pairs))
    }

    private static func parseArray(_ s: inout Cursor) -> Value? {
        s.advance()                                   // '['
        var items: [Value] = []
        var lastWasValue = false
        while true {
            s.skipTrivia()
            guard let c = s.current else { return nil }
            if c == "]" { s.advance(); break }
            if c == "," {
                guard lastWasValue else { return nil }
                lastWasValue = false
                s.advance(); continue
            }
            guard let value = parseValue(&s) else { return nil }
            items.append(value)
            lastWasValue = true
        }
        return .array(items)
    }

    private static func parseString(_ s: inout Cursor) -> String? {
        s.advance()                                   // '"'
        var out = String.UnicodeScalarView()
        while let c = s.current {
            if c == "\"" { s.advance(); return String(out) }
            if c == "\\" {
                s.advance()
                guard let e = s.current else { return nil }
                switch e {
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "/":  out.append("/")
                case "b":  out.append("\u{08}")
                case "f":  out.append("\u{0C}")
                case "n":  out.append("\n")
                case "r":  out.append("\r")
                case "t":  out.append("\t")
                case "u":
                    var hex = ""
                    for _ in 0..<4 {
                        s.advance()
                        guard let h = s.current, isHex(h) else { return nil }
                        hex.unicodeScalars.append(h)
                    }
                    guard let code = UInt32(hex, radix: 16),
                          let scalar = Unicode.Scalar(code) else { return nil }
                    out.append(scalar)
                default: return nil
                }
                s.advance()
                continue
            }
            // Un guillemet non fermé avant la fin : texte cassé.
            if c == "\n" || c == "\r" { return nil }
            out.append(c)
            s.advance()
        }
        return nil
    }

    private static func isHex(_ c: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(c) || ("a"..."f").contains(c) || ("A"..."F").contains(c)
    }

    private static func parseNumber(_ s: inout Cursor) -> Value? {
        var literal = ""
        while let c = s.current,
              ("0"..."9").contains(c) || c == "-" || c == "+" || c == "." || c == "e" || c == "E" {
            literal.unicodeScalars.append(c)
            s.advance()
        }
        guard !literal.isEmpty,
              literal.contains(where: { ("0"..."9").contains($0) }) else { return nil }
        return .number(literal)
    }
}
