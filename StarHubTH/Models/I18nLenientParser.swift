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
/// **Ce que le jeu charge a été mesuré, pas déduit.** Le même parc a été passé
/// dans un oracle qui rejoue le chemin exact de SMAPI — `File.ReadAllText` puis
/// `JsonConvert.DeserializeObject<Dictionary<string, string>>` — avec la
/// `Newtonsoft.Json.dll` 13.0.4 embarquée dans le jeu. Verdict : **SMAPI charge
/// les 2357 fichiers, sans exception.** Newtonsoft tolère les commentaires, les
/// virgules en trop, les clés nues, les guillemets simples, les caractères de
/// contrôle bruts, les valeurs numériques, et remplace même les guillemets
/// courbes au second essai. Croisé fichier par fichier avec notre verdict :
/// **0 faux positif**, 2 faux négatifs (les deux ci-dessous).
///
/// Ne pas confondre le schéma et le chargeur : `allowComments` et
/// `allowTrailingCommas` décrivent ce que le validateur de `smapi.io/json`
/// signale, pas ce que le jeu refuse. S'y fier a fait dire à `smapiAccepts`
/// « le jeu ne chargera pas ce fichier » sur **31 fichiers** qu'il charge très
/// bien — l'inverse exact du service rendu. Corrigé le 2026-08-02.
///
/// Restent 6 fichiers que **nous** ne lisons pas, pour deux raisons étrangères
/// aux quatre passes :
/// - **4 par l'encodage**, hors périmètre de ce parseur qui prend une `String`.
///   `DestroyableBushes/i18n/ru.json` est en UTF-16 LE avec BOM — SMAPI le lit
///   parfaitement, `File.ReadAllText` détectant la marque d'ordre des octets.
///   Trois `es.json` sont dans un jeu 8 bits hérité : SMAPI les charge aussi,
///   mais en remplaçant les octets invalides par U+FFFD, donc **avec les accents
///   corrompus**. La couche de lecture devra reproduire les deux comportements
///   (cf. C1-T6 de la roadmap).
/// - **2 par des tolérances Newtonsoft de guillemets** que nous n'implémentons
///   pas : `SpecialPowerUtilities/i18n/ko.json` porte des valeurs entre
///   apostrophes simples (`'…'` contenant des `"`), et
///   `DestroyableBushes/i18n/zh.json` échappe l'apostrophe (`\'`), ce que JSON
///   interdit. Ce serait une cinquième passe.
///
/// Les 19 tests unitaires d'origine passaient déjà quand la passe 1 détruisait
/// un fichier sur deux, et deux d'entre eux affirmaient sur SMAPI le contraire
/// de ce qu'il fait : c'est pourquoi le plan impose une validation sur données
/// réelles avant clôture — et pourquoi la source d'autorité doit être le
/// chargeur, jamais un document qui le décrit.
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
    /// **Le juge n'est pas le schéma `i18n.json`, c'est Newtonsoft.** Le schéma
    /// décrit ce que le validateur de `smapi.io/json` signale ; le jeu, lui,
    /// appelle `JsonConvert.DeserializeObject<Dictionary<string, string>>` avec
    /// les réglages par défaut (`SCore.ReadTranslationFiles` →
    /// `JsonHelper.ReadJsonFileIfExists`), qui tolère bien davantage. Vérifié en
    /// exécutant ce chemin exact avec la `Newtonsoft.Json.dll` 13.0.4 embarquée
    /// dans le jeu : commentaires, virgules en trop, clés nues, guillemets
    /// simples, caractères de contrôle bruts et valeurs numériques passent tous.
    ///
    /// Ne reste donc faux que pour ce que Newtonsoft refuse réellement : une clé
    /// nue contenant un `.`, un `-` ou une espace (`config.name:` sans
    /// guillemets est refusé, `ConfigName:` accepté), une valeur objet ou
    /// tableau, et le JSON structurellement cassé.
    ///
    /// ⚠️ Faux négatifs résiduels : cette fonction ne peut être exacte que là où
    /// le parseur sait lire. Les deux fichiers qu'il refuse encore (guillemets
    /// simples, `\'` — cf. en-tête) sont chargés par le jeu et rapportés ici
    /// comme refusés. Le parc de l'auteur n'en contient que deux, mais rien ne
    /// borne ce que d'autres modlists contiennent : Newtonsoft s'est révélé plus
    /// permissif que nous sur *tous* les axes mesurés.
    ///
    /// **Ce qu'un appelant a le droit d'en conclure** : `false` signifie « nous
    /// ne savons pas lire ce fichier », pas « le jeu le refusera ». Une vue qui
    /// afficherait un avertissement rouge « ne se chargera pas » sur cette base
    /// rejouerait exactement le mensonge corrigé le 2026-08-02. Seul `true` est
    /// une affirmation sûre sur le jeu.
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
        /// Vrai si la réparation a porté sur quelque chose que **Newtonsoft
        /// refuse** — en pratique, une clé nue hors de son jeu de caractères.
        /// Les autres réparations (contrôles bruts, clés nues ordinaires) sont
        /// du confort pour `JSONSerialization` : le jeu, lui, les lit déjà.
        let neededRepair: Bool
    }

    private static func clean(_ text: String) -> Cleaned {
        // La marque d'ordre des octets fait échouer le décodage JSON alors que
        // le fichier est parfaitement valide ; SMAPI la retire aussi.
        var work = text
        if work.hasPrefix("\u{FEFF}") { work.removeFirst() }

        let withoutComments = stripComments(work)
        let withoutTrailing = stripTrailingCommas(withoutComments)
        let (quoted, quotedRefusedKey) = quoteBareKeys(withoutTrailing)
        // La passe 4 ne participe pas au verdict : Newtonsoft lit les retours à
        // la ligne et tabulations bruts dans une valeur, vérifié sur sa DLL.
        let escaped = escapeRawControlCharacters(quoted)
        return Cleaned(text: escaped, neededRepair: quotedRefusedKey)
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
    /// Le booléen retourné ne dit pas « j'ai réparé » mais « SMAPI aurait
    /// refusé ». Newtonsoft lit les clés nues, mais seulement dans son jeu de
    /// caractères — lettres (Unicode compris), chiffres, `_` et `$`. Un `.`, un
    /// `-` ou une espace l'arrête : `ConfigName:` passe, `config.name:` non.
    /// Nous lisons les deux ; seul le second lève le drapeau.
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
                    if word.contains(where: { !isNewtonsoftBareKey($0) }) { repaired = true }
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
        c.properties.isAlphabetic || isDigit(c) || c == "_" || c == "$"
    }

    private static func isKeyBody(_ c: Unicode.Scalar) -> Bool {
        isNewtonsoftBareKey(c) || c == "." || c == "-"
    }

    /// Le jeu de caractères qu'accepte Newtonsoft dans une clé **non quotée**,
    /// mesuré sur sa DLL : lettres (Unicode compris), chiffres, `_` et `$`.
    /// `isKeyBody` va plus loin — il tolère `.` et `-` pour *lire* ces fichiers —
    /// mais ce qu'il ajoute est précisément ce qui fait refuser le fichier par
    /// le jeu, d'où la distinction.
    private static func isNewtonsoftBareKey(_ c: Unicode.Scalar) -> Bool {
        c.properties.isAlphabetic || isDigit(c) || c == "_" || c == "$"
    }

    /// Passe 4 — échappe un retour à la ligne ou une tabulation bruts dans une
    /// chaîne, que `JSONSerialization` refuse. Newtonsoft, lui, les lit : cette
    /// passe est du confort pour notre lecteur, elle ne dit rien de ce que le
    /// jeu accepte et ne participe donc pas à `neededRepair`.
    private static func escapeRawControlCharacters(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(text.unicodeScalars.count)
        var inString = false, escaped = false
        for c in text.unicodeScalars {
            if escaped { out.append(c); escaped = false; continue }
            if inString {
                if c == "\\" { escaped = true; out.append(c); continue }
                if c == "\"" { inString = false; out.append(c); continue }
                switch c {
                case "\n": out.append(contentsOf: "\\n".unicodeScalars)
                case "\r": out.append(contentsOf: "\\r".unicodeScalars)
                case "\t": out.append(contentsOf: "\\t".unicodeScalars)
                default: out.append(c)
                }
                continue
            }
            if c == "\"" { inString = true }
            out.append(c)
        }
        return String(out)
    }
}
