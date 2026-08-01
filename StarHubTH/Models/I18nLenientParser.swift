import Foundation

/// Lit un fichier de traduction SMAPI (`i18n/default.json`, `i18n/fr.json`…)
/// avec la tolérance du chargeur du jeu, que `JSONSerialization` n'a pas.
///
/// Ces fichiers sont écrits à la main par des centaines d'auteurs : ils portent
/// des commentaires de section, des virgules en trop, parfois des retours à la
/// ligne bruts dans une valeur. Refuser de les lire reviendrait à afficher
/// « pas de traduction » sur un mod parfaitement traduit.
///
/// Quatre passes, toutes **conscientes des chaînes** — c'est le point
/// délicat : une URL `https://…` contient `//` sans être un commentaire, et une
/// valeur peut contenir `,}` sans être une virgule structurale. Une expression
/// régulière appliquée au texte entier corromprait les deux.
///
/// Approche reprise de `scanner.rs` (Nana1873/stardew-i18n-translator, GPL) :
/// **réimplémentée depuis son principe**, aucun code repris.
///
/// ⚠️ Tout le nettoyage travaille sur des `Unicode.Scalar`, **jamais** des
/// `Character` : en Swift, `\r\n` est un seul Character, que ni `== "\n"` ni
/// `== "\r"` ne reconnaît. Une première version par Character faisait courir la
/// coupure d'un commentaire de ligne jusqu'à la fin de tout fichier CRLF — soit
/// 1474 des 2357 fichiers du parc. Ne pas repasser aux `Character`.
///
/// Mesuré sur les 2357 fichiers `i18n/*.json` de la modlist de l'auteur
/// (2026-08-01, même harnais avant et après, décodage UTF-8 strict) :
/// **2353** sont décodables, dont **1471** en CRLF ; JSON strict en accepterait
/// **1441**.
/// - avant la correction, ce parseur en lisait **1866** et en refusait **487** ;
/// - il en lit désormais **2351** et n'en refuse plus que **2**, sans aucune
///   régression (aucun fichier lisible en JSON strict n'est refusé).
/// - **2326** de ces 2351 ne demandent aucune réparation, donc SMAPI les
///   charge. Vérifié dans les deux sens : le drapeau `neededRepair` concorde
///   exactement avec la comparaison textuelle des passes 3 et 4 (aucun
///   désaccord sur 2351), et les 25 fichiers réparés se répartissent en 16 clés
///   nues (3 mods) et 9 caractères de contrôle bruts — aucun fichier CRLF
///   ordinaire, ce qui serait le signe d'une passe 4 trop zélée.
///
/// Reste 6 fichiers hors de portée (0,25 %), pour deux raisons étrangères aux
/// quatre passes :
/// - **4 par l'encodage** — `DestroyableBushes/i18n/ru.json` est en UTF-16 LE
///   avec BOM, trois `es.json` sont dans un jeu 8 bits hérité. C'est affaire de
///   *décodage* : la couche qui lira les fichiers devra honorer la marque
///   d'ordre des octets et se rabattre sur un jeu hérité, comme le
///   `StreamReader` de SMAPI, avant d'appeler ce parseur qui prend une `String`.
/// - **2 par des tolérances Newtonsoft de guillemets** que nous n'implémentons
///   pas : `SpecialPowerUtilities/i18n/ko.json` porte des valeurs entre
///   apostrophes simples (`'…'` contenant des `"`), et
///   `DestroyableBushes/i18n/zh.json` échappe l'apostrophe (`\'`), ce que JSON
///   interdit. Le jeu charge ces deux fichiers ; ce serait une cinquième passe.
///
/// Les 19 tests unitaires d'origine passaient déjà quand la passe 1 détruisait
/// un fichier sur deux : c'est exactement pourquoi le plan impose une
/// validation sur données réelles avant clôture.
enum I18nLenientParser {
    enum ParseError: Error, Equatable {
        /// Illisible même après nettoyage.
        case malformed
        /// Lisible, mais ce n'est pas un objet plat de chaînes vers chaînes —
        /// donc pas un fichier i18n.
        case notFlatObject
    }

    /// Les entrées du fichier. `$schema`, quand il est présent, est écarté :
    /// c'est une annotation d'éditeur, pas une traduction. **Divergence assumée
    /// avec SMAPI**, qui la traite comme une clé ordinaire — sans quoi nos
    /// totaux différeraient des siens de un.
    static func parse(_ text: String) throws -> [String: String] {
        let cleaned = clean(text).text
        guard let data = cleaned.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let object = any as? [String: Any] else {
            throw ParseError.malformed
        }
        var out: [String: String] = [:]
        out.reserveCapacity(object.count)
        for (key, value) in object where key != "$schema" {
            guard let string = value as? String else { throw ParseError.notFlatObject }
            out[key] = string
        }
        return out
    }

    /// SMAPI chargerait-il ce fichier tel quel ?
    ///
    /// Vrai quand seules les passes 1 et 2 ont été nécessaires — commentaires et
    /// virgules en trop, que le schéma officiel `i18n.json` autorise
    /// explicitement (`allowComments`, `allowTrailingCommas`). Faux dès qu'une
    /// clé nue ou un caractère de contrôle brut a dû être réparé : le parseur
    /// sait les lire, le jeu non.
    static func smapiAccepts(_ text: String) -> Bool {
        let result = clean(text)
        guard !result.neededRepair else { return false }
        guard let data = result.text.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let object = any as? [String: Any] else { return false }
        return object.values.allSatisfy { $0 is String }
    }

    // MARK: - Nettoyage

    private struct Cleaned {
        let text: String
        /// Vrai si une passe 3 ou 4 a dû intervenir — donc si SMAPI refuserait.
        let neededRepair: Bool
    }

    private static func clean(_ text: String) -> Cleaned {
        // La marque d'ordre des octets fait échouer le décodage JSON alors que
        // le fichier est parfaitement valide ; SMAPI la retire aussi.
        var work = text
        if work.hasPrefix("\u{FEFF}") { work.removeFirst() }

        let withoutComments = stripComments(work)
        let withoutTrailing = stripTrailingCommas(withoutComments)
        let (quoted, quotedAny) = quoteBareKeys(withoutTrailing)
        let (escaped, escapedAny) = escapeRawControlCharacters(quoted)
        return Cleaned(text: escaped, neededRepair: quotedAny || escapedAny)
    }

    /// Passe 1 — retire `// …` et `/* … */`, sauf à l'intérieur d'une chaîne.
    ///
    /// Le commentaire de ligne s'arrête au premier `\n` **ou** `\r` : les
    /// fichiers CRLF sont majoritaires, et les fins de ligne héritées de Mac OS
    /// classique existent encore dans le parc.
    private static func stripComments(_ text: String) -> String {
        let chars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        out.reserveCapacity(chars.count)
        var inString = false, escaped = false
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if escaped { out.append(c); escaped = false; i += 1; continue }
            if inString {
                if c == "\\" { escaped = true }
                if c == "\"" { inString = false }
                out.append(c); i += 1; continue
            }
            if c == "\"" { inString = true; out.append(c); i += 1; continue }
            if c == "/", i + 1 < chars.count {
                if chars[i + 1] == "/" {
                    while i < chars.count, chars[i] != "\n", chars[i] != "\r" { i += 1 }
                    continue
                }
                if chars[i + 1] == "*" {
                    i += 2
                    while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                    i += 2
                    continue
                }
            }
            out.append(c); i += 1
        }
        return String(out)
    }

    /// Passe 2 — retire une virgule qui ne précède qu'une fermeture. Consciente
    /// des chaînes : `"x,}"` est une valeur, pas une virgule structurale.
    private static func stripTrailingCommas(_ text: String) -> String {
        let chars = Array(text.unicodeScalars)
        var keep = [Bool](repeating: true, count: chars.count)
        var inString = false, escaped = false
        for (i, c) in chars.enumerated() {
            if escaped { escaped = false; continue }
            if inString {
                if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                continue
            }
            if c == "\"" { inString = true; continue }
            guard c == "," else { continue }
            // Regarder la prochaine chose significative hors chaîne.
            var j = i + 1
            while j < chars.count, isSpace(chars[j]) { j += 1 }
            if j < chars.count, chars[j] == "}" || chars[j] == "]" { keep[i] = false }
        }
        var out = String.UnicodeScalarView()
        out.reserveCapacity(chars.count)
        for (i, c) in chars.enumerated() where keep[i] { out.append(c) }
        return String(out)
    }

    /// Passe 3 — met entre guillemets une clé nue (`{ Key: "v" }`), **seulement
    /// en position de clé** : après `{` ou `,`. Une valeur contenant `not: a key`
    /// ne doit pas être touchée.
    ///
    /// SMAPI **refuse** ces fichiers : intervenir ici lève `neededRepair`.
    private static func quoteBareKeys(_ text: String) -> (String, Bool) {
        let chars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        out.reserveCapacity(chars.count)
        var inString = false, escaped = false, expectingKey = false, repaired = false
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if escaped { out.append(c); escaped = false; i += 1; continue }
            if inString {
                if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                out.append(c); i += 1; continue
            }
            if c == "\"" { inString = true; expectingKey = false; out.append(c); i += 1; continue }
            if c == "{" || c == "," { expectingKey = true; out.append(c); i += 1; continue }
            if c == ":" || c == "}" { expectingKey = false; out.append(c); i += 1; continue }
            if expectingKey, isKeyStart(c) {
                var j = i
                var word = String.UnicodeScalarView()
                while j < chars.count, isKeyBody(chars[j]) { word.append(chars[j]); j += 1 }
                var k = j
                while k < chars.count, isSpace(chars[k]) { k += 1 }
                // Ce n'est une clé que si un `:` suit.
                if k < chars.count, chars[k] == ":" {
                    out.append("\"")
                    out.append(contentsOf: word)
                    out.append("\"")
                    repaired = true
                    expectingKey = false
                    i = j
                    continue
                }
                out.append(contentsOf: word); i = j; continue
            }
            if !isSpace(c) { expectingKey = false }
            out.append(c); i += 1
        }
        return (String(out), repaired)
    }

    // MARK: - Prédicats sur scalaires

    // Tout le nettoyage travaille sur des `Unicode.Scalar`, jamais des
    // `Character`. En Swift, `\r\n` est **un seul** Character : le comparer à
    // `"\n"` renvoie faux, ce qui faisait courir la coupure d'un commentaire de
    // ligne jusqu'à la fin d'un fichier CRLF. `Unicode.Scalar` n'offre pas les
    // prédicats de `Character`, d'où ces trois helpers.

    private static func isSpace(_ c: Unicode.Scalar) -> Bool { c.properties.isWhitespace }

    private static func isDigit(_ c: Unicode.Scalar) -> Bool { c.value >= 0x30 && c.value <= 0x39 }

    private static func isKeyStart(_ c: Unicode.Scalar) -> Bool {
        c.properties.isAlphabetic || c == "_" || c == "$"
    }

    private static func isKeyBody(_ c: Unicode.Scalar) -> Bool {
        c.properties.isAlphabetic || isDigit(c)
            || c == "_" || c == "." || c == "-" || c == "$"
    }

    /// Passe 4 — échappe un retour à la ligne ou une tabulation bruts dans une
    /// chaîne. JSON les interdit ; SMAPI aussi, d'où `neededRepair`.
    private static func escapeRawControlCharacters(_ text: String) -> (String, Bool) {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(text.unicodeScalars.count)
        var inString = false, escaped = false, repaired = false
        for c in text.unicodeScalars {
            if escaped { out.append(c); escaped = false; continue }
            if inString {
                if c == "\\" { escaped = true; out.append(c); continue }
                if c == "\"" { inString = false; out.append(c); continue }
                switch c {
                case "\n": out.append(contentsOf: "\\n".unicodeScalars); repaired = true
                case "\r": out.append(contentsOf: "\\r".unicodeScalars); repaired = true
                case "\t": out.append(contentsOf: "\\t".unicodeScalars); repaired = true
                default: out.append(c)
                }
                continue
            }
            if c == "\"" { inString = true }
            out.append(c)
        }
        return (String(out), repaired)
    }
}
