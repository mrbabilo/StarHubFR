import Foundation

/// La structure qu'un auteur donne à son fichier de traduction : l'ordre de ses
/// clés, et les commentaires dont il les coiffe.
///
/// Les auteurs séparent leurs clés par des commentaires — « Config »,
/// « Dialogue locationnel », « Titres des nouveaux livres d'Elliott ». C'est la
/// **seule structure fiable** de ces fichiers. Déduire un personnage des clés ne
/// marche pas : le nom qu'on y trouve désigne le plus souvent un lieu
/// (`HaleyHouse`) ou un participant d'événement, pas celui qui parle — mesuré
/// sur le parc, et c'est aussi la conclusion de `stardew-i18n-translator`, qui
/// groupe par ces mêmes commentaires.
///
/// 167 des 450 fichiers français du parc en portent, 3290 sections au total.
///
/// **L'ordre des clés sort du même parcours.** Il ne sert pas au regroupement,
/// mais il sera indispensable à l'écriture : réordonner un fichier rend son diff
/// illisible, et `JSONSerialization` ne préserve pas l'ordre d'origine.
///
/// L'analyse est **consciente des chaînes** : un `//` dans une URL n'ouvre pas
/// de section, et une clé peut en contenir un.
public enum I18nOutline {
    public struct Outline: Equatable, Sendable {
        /// Les clés dans l'ordre du fichier, `$schema` exclu.
        public let orderedKeys: [String]
        /// Le titre de section sous lequel chaque clé se trouve.
        public let sectionByKey: [String: String]
        /// Le **rang** de cette section dans l'ordre de lecture du fichier.
        ///
        /// Le titre ne suffit pas à identifier une section : `[CP] Ridgeside
        /// Village` en porte 65 nommées « Spring », 1407 de ses 2056 titres
        /// sont des doublons. Sans ce rang, replier l'une les replierait
        /// toutes et la navigation tomberait toujours sur la première.
        public let sectionIndexByKey: [String: Int]

        public init(orderedKeys: [String], sectionByKey: [String: String],
                    sectionIndexByKey: [String: Int] = [:]) {
            self.orderedKeys = orderedKeys
            self.sectionByKey = sectionByKey
            self.sectionIndexByKey = sectionIndexByKey
        }

        public func section(of key: String) -> String? { sectionByKey[key] }

        /// Le rang de la section d'une clé, `nil` si elle précède tout
        /// commentaire.
        public func sectionIndex(of key: String) -> Int? { sectionIndexByKey[key] }

        /// Vrai si l'auteur a structuré son fichier — sinon rien à regrouper.
        public var hasSections: Bool { !sectionByKey.isEmpty }
    }

    public static func read(_ text: String) -> Outline {
        let characters = Array(text)
        var orderedKeys: [String] = []
        var sectionByKey: [String: String] = [:]
        var currentSection: String?
        var currentSectionIndex: Int?
        var sectionIndexByKey: [String: Int] = [:]
        var sectionCount = 0
        var depth = 0
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                let (literal, next) = readString(characters, from: index)
                index = next
                // Une clé est une chaîne suivie d'un `:` **au premier niveau** :
                // les clés d'un objet imbriqué ne sont pas des entrées du
                // fichier, et une valeur ne doit jamais être prise pour une clé.
                guard depth == 1, let colon = nextSignificant(characters, from: index),
                      characters[colon] == ":" else { continue }
                if literal != "$schema" {
                    orderedKeys.append(literal)
                    if let section = currentSection { sectionByKey[literal] = section }
                    if let rank = currentSectionIndex { sectionIndexByKey[literal] = rank }
                }
                continue
            }

            if character == "/", index + 1 < characters.count {
                if characters[index + 1] == "/" {
                    let (comment, next) = readLineComment(characters, from: index)
                    if let title = sectionTitle(comment) {
                        currentSection = title
                        currentSectionIndex = sectionCount
                        sectionCount += 1
                    }
                    index = next
                    continue
                }
                if characters[index + 1] == "*" {
                    let (comment, next) = readBlockComment(characters, from: index)
                    if let title = sectionTitle(comment) {
                        currentSection = title
                        currentSectionIndex = sectionCount
                        sectionCount += 1
                    }
                    index = next
                    continue
                }
            }

            // Clé non quotée (`RingsName: "…"`), que trois mods du parc
            // emploient et que le parseur répare. L'analyse doit voir les mêmes
            // clés que lui : c'est son ordre qui guidera l'écriture.
            if depth == 1, character.isLetter || character == "_" || character == "$" {
                var end = index
                while end < characters.count, isBareKeyCharacter(characters[end]) { end += 1 }
                if let colon = nextSignificant(characters, from: end),
                   characters[colon] == ":" {
                    let literal = String(characters[index..<end])
                    if literal != "$schema" {
                        orderedKeys.append(literal)
                        if let section = currentSection { sectionByKey[literal] = section }
                        if let rank = currentSectionIndex { sectionIndexByKey[literal] = rank }
                    }
                    index = end
                    continue
                }
                index = end
                continue
            }

            if character == "{" || character == "[" { depth += 1 }
            if character == "}" || character == "]" { depth -= 1 }
            index += 1
        }

        return Outline(orderedKeys: orderedKeys, sectionByKey: sectionByKey,
                       sectionIndexByKey: sectionIndexByKey)
    }

    // MARK: - Détail

    /// Le jeu de caractères d'une clé non quotée, aligné sur ce que le parseur
    /// accepte — lettres, chiffres, `_`, `$`, plus `.` et `-` que Newtonsoft
    /// refuse mais que nous lisons.
    private static func isBareKeyCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "$" || c == "." || c == "-"
    }

    /// Le titre porté par un commentaire, ou `nil` s'il n'en porte pas.
    ///
    /// Les auteurs encadrent souvent leur titre de lignes de décoration —
    /// `----`, `****`, `====`. Les retenir donnerait des sections nommées
    /// « ------ », qui ne titrent rien.
    private static func sectionTitle(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let decoration = CharacterSet(charactersIn: "-*=_#~/ ")
        guard trimmed.rangeOfCharacter(from: decoration.inverted) != nil else { return nil }
        return trimmed
    }

    /// Lit une chaîne JSON à partir du guillemet ouvrant. Rend son contenu
    /// déséchappé sommairement et l'index qui suit le guillemet fermant.
    private static func readString(_ c: [Character], from start: Int) -> (String, Int) {
        var value = ""
        var index = start + 1
        while index < c.count {
            if c[index] == "\\", index + 1 < c.count {
                // Conserver l'échappement tel quel suffit ici : on compare des
                // noms de clés, pas des valeurs affichées.
                value.append(c[index])
                value.append(c[index + 1])
                index += 2
                continue
            }
            if c[index] == "\"" { return (value, index + 1) }
            value.append(c[index])
            index += 1
        }
        return (value, index)
    }

    /// ⚠️ `isNewline`, **jamais** `!= "\n" && != "\r"`. En Swift, `\r\n` est un
    /// seul `Character` qui n'est égal à aucun des deux : la comparaison
    /// littérale faisait courir la coupure jusqu'à la fin du fichier, et un
    /// fichier CRLF perdait toutes ses clés. C'est le même défaut que celui
    /// corrigé dans `I18nLenientParser` — deux copies d'une même logique, dont
    /// une seule savait.
    private static func readLineComment(_ c: [Character], from start: Int) -> (String, Int) {
        var index = start + 2
        var content = ""
        while index < c.count, !c[index].isNewline {
            content.append(c[index])
            index += 1
        }
        return (content, index)
    }

    private static func readBlockComment(_ c: [Character], from start: Int) -> (String, Int) {
        var index = start + 2
        var content = ""
        while index + 1 < c.count, !(c[index] == "*" && c[index + 1] == "/") {
            content.append(c[index])
            index += 1
        }
        return (content, min(index + 2, c.count))
    }

    /// L'index du prochain caractère qui n'est ni une espace ni un commentaire.
    private static func nextSignificant(_ c: [Character], from start: Int) -> Int? {
        var index = start
        while index < c.count {
            if c[index].isWhitespace { index += 1; continue }
            if c[index] == "/", index + 1 < c.count {
                if c[index + 1] == "/" { index = readLineComment(c, from: index).1; continue }
                if c[index + 1] == "*" { index = readBlockComment(c, from: index).1; continue }
            }
            return index
        }
        return nil
    }
}
