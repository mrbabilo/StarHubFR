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
    /// marque d'ordre des octets en tête, commentaires `//` et `/* */`,
    /// virgules traînantes avant `}` et `]`, clés nues, guillemets simples et
    /// retours à la ligne bruts dans une chaîne.
    ///
    /// **Les cinq dernières tolérances viennent d'une mesure sur le parc, pas
    /// d'un principe** : ce parseur sert aussi à lire le `content.json` d'un
    /// content pack (`ContentPackConfigSchema`), et il en **refusait 14 sur
    /// 606** — dont 7 qui portent un `ConfigSchema`, et 6 de ces 7 ont un
    /// `config.json` que l'éditeur ouvre. Aucun `config.json` du parc (0 sur
    /// 593) n'en a besoin : la leniance est là pour les `content.json`, que
    /// personne ne réécrit. Les causes relevées, toutes acceptées par
    /// Newtonsoft : clés nues (`32:`, `winter_2:`), chaînes à guillemets
    /// simples et chaînes qui courent sur plusieurs lignes.
    ///
    /// Le jeu de caractères d'une clé nue est celui **que Newtonsoft accepte**
    /// — lettres, chiffres, `_`, `$` — jamais celui, plus large, qu'un
    /// nettoyeur tolère pour *lire* (`I18nLenientParser.isKeyBody` ajoute `.`
    /// et `-`, et c'est précisément ce qui fait refuser le fichier par le
    /// jeu). `parse` alimente le témoin « JSON invalide » de l'éditeur : le
    /// dire valide pour un fichier que SMAPI refuse serait le mensonge
    /// inverse.
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
        // La marque d'ordre des octets fait échouer la lecture d'un fichier
        // parfaitement valide ; SMAPI la retire aussi (cf. `I18nLenientParser`).
        var body = text
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        var scanner = Cursor(text: body)
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
        case "\"", "'": return parseString(&s).map(Value.string)
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
            guard let key = parseKey(&s) else { return nil }
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

    /// La clé d'un membre : quotée — double ou simple — ou **nue**.
    ///
    /// Une clé nue n'est jamais désambiguïsée par un `:` de contrôle ici : la
    /// grammaire l'exige déjà juste après, `parseObject` refuse sinon. Le jeu
    /// de caractères est le strict jeu de Newtonsoft (voir `parse`).
    private static func parseKey(_ s: inout Cursor) -> String? {
        if s.current == "\"" || s.current == "'" { return parseString(&s) }
        var out = String.UnicodeScalarView()
        while let c = s.current, isBareKeyScalar(c) {
            out.append(c)
            s.advance()
        }
        return out.isEmpty ? nil : String(out)
    }

    /// Lettres (Unicode comprises), chiffres, `_` et `$` — mesuré sur la DLL
    /// de Newtonsoft pour `I18nLenientParser`, repris tel quel. Ni `.` ni `-`,
    /// que le jeu refuse dans une clé nue.
    private static func isBareKeyScalar(_ c: Unicode.Scalar) -> Bool {
        c.properties.isAlphabetic || ("0"..."9").contains(c) || c == "_" || c == "$"
    }

    /// La chaîne qui commence au curseur. Le **guillemet ouvrant** fait
    /// terminateur : dans une chaîne à guillemets simples, un `"` est un
    /// caractère ordinaire, et l'inverse aussi.
    private static func parseString(_ s: inout Cursor) -> String? {
        guard let quote = s.current else { return nil }
        s.advance()                                   // '"' ou '\''
        var out = String.UnicodeScalarView()
        while let c = s.current {
            if c == quote { s.advance(); return String(out) }
            if c == "\\" {
                s.advance()
                guard let e = s.current else { return nil }
                switch e {
                case "\"": out.append("\"")
                case "'":  out.append("'")
                case "\\": out.append("\\")
                case "/":  out.append("/")
                case "b":  out.append("\u{08}")
                case "f":  out.append("\u{0C}")
                case "n":  out.append("\n")
                case "r":  out.append("\r")
                case "t":  out.append("\t")
                case "u":
                    guard let code = readHexQuad(&s) else { return nil }
                    if let scalar = Unicode.Scalar(code) {
                        out.append(scalar)
                    } else if code >= 0xD800, code <= 0xDBFF {
                        // Un caractère hors du plan de base s'écrit en JSON
                        // par une **paire de substitution** (`\uD83D\uDE00`
                        // pour 😀) : c'est la forme que .NET produit dès
                        // qu'il échappe. Lire le demi-mot seul rendait `nil`,
                        // donc perdait le fichier entier.
                        s.advance()
                        guard s.current == "\\" else { return nil }
                        s.advance()
                        guard s.current == "u", let low = readHexQuad(&s),
                              low >= 0xDC00, low <= 0xDFFF else { return nil }
                        let combined = 0x10000 + (code - 0xD800) << 10 + (low - 0xDC00)
                        guard let scalar = Unicode.Scalar(combined) else { return nil }
                        out.append(scalar)
                    } else {
                        // Un demi-mot orphelin fait échouer la lecture, et ne
                        // devient **jamais** U+FFFD : cet arbre repart en
                        // écriture, et substituer en silence corromprait une
                        // valeur que l'éditeur réécrit.
                        return nil
                    }
                default: return nil
                }
                s.advance()
                continue
            }
            // Un retour à la ligne brut **appartient** à la chaîne : quatre
            // `content.json` du parc font courir une valeur sur plusieurs
            // lignes, et Newtonsoft les lit. Une chaîne jamais fermée reste
            // refusée — la boucle sort en fin de texte sur `nil`.
            out.append(c)
            s.advance()
        }
        return nil
    }

    /// Les quatre chiffres d'une échappée `\uXXXX`. Entre avec le curseur sur
    /// le `u`, sort sur le **dernier chiffre** — la convention des autres
    /// échappées, dont l'avance finale appartient à l'appelant.
    private static func readHexQuad(_ s: inout Cursor) -> UInt32? {
        var hex = ""
        for _ in 0..<4 {
            s.advance()
            guard let h = s.current, isHex(h) else { return nil }
            hex.unicodeScalars.append(h)
        }
        return UInt32(hex, radix: 16)
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

    // MARK: - Écriture

    /// Sérialise au format de SMAPI : 2 espaces, LF, **pas de saut de ligne
    /// final** (spec §5.2 — `Formatting.Indented` de Newtonsoft, qui termine
    /// par `}` sans `\n`).
    ///
    /// **Se relit avant de rendre** : une échappée manquée écrirait un
    /// fichier que le jeu refuserait, et l'app n'aurait aucun moyen de le
    /// savoir. C'est la garde reprise d'`OrderedJSONWriter` — la seule partie
    /// de cet écrivain qui se transplantait telle quelle.
    public static func write(_ value: Value) -> String? {
        var out = ""
        writeIndented(value, indent: 0, into: &out)
        guard let reparsed = parse(out), reparsed == value else { return nil }
        return out
    }

    /// Rendu compact sur une ligne, sans espaces — pour **afficher** une
    /// valeur composée dans l'écran de comparaison, jamais pour écrire.
    public static func inline(_ value: Value) -> String {
        var out = ""
        switch value {
        case .object(let obj):
            out += "{"
            for (rank, key) in obj.keys.enumerated() {
                if rank > 0 { out += "," }
                out += "\(escape(key)):\(inline(obj.members[key] ?? .null))"
            }
            out += "}"
        case .array(let items):
            out += "[" + items.map(inline).joined(separator: ",") + "]"
        case .string(let s): out += escape(s)
        case .number(let n): out += n
        case .bool(let b):   out += b ? "true" : "false"
        case .null:          out += "null"
        }
        return out
    }

    private static func writeIndented(_ value: Value, indent: Int, into out: inout String) {
        let pad = String(repeating: "  ", count: indent)
        switch value {
        case .object(let obj):
            if obj.keys.isEmpty { out += "{}"; return }
            out += "{\n"
            for (rank, key) in obj.keys.enumerated() {
                out += pad + "  " + escape(key) + ": "
                writeIndented(obj.members[key] ?? .null, indent: indent + 1, into: &out)
                out += rank == obj.keys.count - 1 ? "\n" : ",\n"
            }
            out += pad + "}"
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[\n"
            for (rank, item) in items.enumerated() {
                out += pad + "  "
                writeIndented(item, indent: indent + 1, into: &out)
                out += rank == items.count - 1 ? "\n" : ",\n"
            }
            out += pad + "]"
        case .string(let s):
            out += escape(s)
        case .number(let n):
            out += n
        case .bool(let b):
            out += b ? "true" : "false"
        case .null:
            out += "null"
        }
    }

    /// Échappement JSON d'une chaîne, guillemets compris. À la main plutôt
    /// que par `JSONSerialization` : elle n'encode pas une chaîne nue sans
    /// conteneur, et son passage par `Any` a déjà coûté à ce dépôt.
    /// (Repris d'`OrderedJSONWriter.escape`, inchangé.)
    private static func escape(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"":  out += "\\\""
            case "\\":  out += "\\\\"
            case "\n":  out += "\\n"
            case "\r":  out += "\\r"
            case "\t":  out += "\\t"
            default:
                if c.value < 0x20 {
                    out += String(format: "\\u%04x", c.value)
                } else {
                    out.unicodeScalars.append(c)
                }
            }
        }
        return out + "\""
    }
}
