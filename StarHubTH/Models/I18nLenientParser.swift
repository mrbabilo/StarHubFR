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
/// ⚠️ **INACHEVÉ au 2026-08-01 — ne pas câbler aux vues en l'état.**
///
/// Éprouvé sur les 2447 fichiers i18n réels de la modlist de l'auteur :
/// - JSON strict en accepterait **1491** ;
/// - ce parseur en lit **1920** (+429, ce qui est bien l'objet du laxisme) ;
/// - mais il en **refuse 526**, dont des fichiers valides une fois leurs
///   commentaires retirés. La passe 1 (`stripComments`) les casse : vérifié en
///   isolant les passes une à une sur
///   `[CP] Cornucopia More Flowers/i18n/default.json` (fichier en CRLF, avec
///   des commentaires de section). Aucun `//` ne survit au nettoyage, et
///   pourtant le JSON produit est invalide — donc la passe retire *aussi* du
///   contenu utile.
///
/// Les 19 tests unitaires passent : ils ne couvrent pas ce cas. C'est
/// exactement pourquoi le plan impose une validation sur données réelles avant
/// clôture — elle a fait son travail.
///
/// Prochaine étape : réduire le fichier fautif jusqu'à la plus petite entrée
/// qui casse, en faire un test, puis corriger.
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
    private static func stripComments(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var inString = false, escaped = false
        var iterator = Array(text)
        var i = 0
        while i < iterator.count {
            let c = iterator[i]
            if escaped { out.append(c); escaped = false; i += 1; continue }
            if inString {
                if c == "\\" { escaped = true }
                if c == "\"" { inString = false }
                out.append(c); i += 1; continue
            }
            if c == "\"" { inString = true; out.append(c); i += 1; continue }
            if c == "/", i + 1 < iterator.count {
                if iterator[i + 1] == "/" {
                    while i < iterator.count && iterator[i] != "\n" { i += 1 }
                    continue
                }
                if iterator[i + 1] == "*" {
                    i += 2
                    while i + 1 < iterator.count && !(iterator[i] == "*" && iterator[i + 1] == "/") { i += 1 }
                    i += 2
                    continue
                }
            }
            out.append(c); i += 1
        }
        return out
    }

    /// Passe 2 — retire une virgule qui ne précède qu'une fermeture. Consciente
    /// des chaînes : `"x,}"` est une valeur, pas une virgule structurale.
    private static func stripTrailingCommas(_ text: String) -> String {
        let chars = Array(text)
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
            while j < chars.count, chars[j].isWhitespace { j += 1 }
            if j < chars.count, chars[j] == "}" || chars[j] == "]" { keep[i] = false }
        }
        return String(chars.enumerated().filter { keep[$0.offset] }.map(\.element))
    }

    /// Passe 3 — met entre guillemets une clé nue (`{ Key: "v" }`), **seulement
    /// en position de clé** : après `{` ou `,`. Une valeur contenant `not: a key`
    /// ne doit pas être touchée.
    ///
    /// SMAPI **refuse** ces fichiers : intervenir ici lève `neededRepair`.
    private static func quoteBareKeys(_ text: String) -> (String, Bool) {
        let chars = Array(text)
        var out = ""
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
            if expectingKey, c.isLetter || c == "_" || c == "$" {
                var j = i
                var word = ""
                while j < chars.count, chars[j].isLetter || chars[j].isNumber
                        || chars[j] == "_" || chars[j] == "." || chars[j] == "-" || chars[j] == "$" {
                    word.append(chars[j]); j += 1
                }
                var k = j
                while k < chars.count, chars[k].isWhitespace { k += 1 }
                // Ce n'est une clé que si un `:` suit.
                if k < chars.count, chars[k] == ":" {
                    out.append("\"\(word)\"")
                    repaired = true
                    expectingKey = false
                    i = j
                    continue
                }
                out.append(contentsOf: word); i = j; continue
            }
            if !c.isWhitespace { expectingKey = false }
            out.append(c); i += 1
        }
        return (out, repaired)
    }

    /// Passe 4 — échappe un retour à la ligne ou une tabulation bruts dans une
    /// chaîne. JSON les interdit ; SMAPI aussi, d'où `neededRepair`.
    private static func escapeRawControlCharacters(_ text: String) -> (String, Bool) {
        var out = ""
        out.reserveCapacity(text.count)
        var inString = false, escaped = false, repaired = false
        for c in text {
            if escaped { out.append(c); escaped = false; continue }
            if inString {
                if c == "\\" { escaped = true; out.append(c); continue }
                if c == "\"" { inString = false; out.append(c); continue }
                switch c {
                case "\n": out.append("\\n"); repaired = true
                case "\r": out.append("\\r"); repaired = true
                case "\t": out.append("\\t"); repaired = true
                default: out.append(c)
                }
                continue
            }
            if c == "\"" { inString = true }
            out.append(c)
        }
        return (out, repaired)
    }
}
