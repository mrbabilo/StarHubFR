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
        ///
        /// Une clé lue deux fois dans le fichier — du JSON à clés dupliquées,
        /// que le jeu accepte — garde la section de sa **première**
        /// occurrence, jamais la dernière : c'est là que la clé se trouve dans
        /// le fichier, et c'est cette position que suit `orderedSourceKeys`.
        /// Prendre la section de la dernière tout en gardant la position de la
        /// première ferait porter à la rangée le rang d'une autre section que
        /// celle où elle est rangée, et `diffGroups` couperait en deux le bloc
        /// qui l'entoure.
        ///
        /// ⚠️ **Écart connu, assumé** : la *valeur* affichée, elle, est celle
        /// de la **dernière** occurrence — `I18nLenientParser` déduplique comme
        /// le jeu, dernier-gagne (voir `neutralizeDuplicateKeys`). Une clé
        /// dupliquée sous deux titres différents s'affiche donc sous le
        /// premier des deux. Mesuré sur le parc (2 749 fichiers lisibles) :
        /// 60 fichiers portent 139 clés dupliquées, dont **17** changent de
        /// section entre la première et la dernière occurrence et **21** de
        /// rang — `[CP] Tea` en tête, où `spring_23` est défini sous
        /// « Seasonal + Day-Specific Dialogue » puis sous « Marriage
        /// Dialogue ». Tout aligner sur la dernière occurrence demanderait de
        /// déplacer aussi la position, donc de réordonner le fichier affiché.
        public let sectionByKey: [String: String]
        /// Le **rang** de cette section dans l'ordre de lecture du fichier.
        ///
        /// Le titre ne suffit pas à identifier une section : `[CP] Ridgeside
        /// Village` porte, au sens de ce parseur, 2065 lignes de commentaire
        /// titrées — dont un grand nombre de « Spring » homonymes, une par
        /// saison de personnage. (Un compte différent de celui des groupes que
        /// ce fichier donne au diff, 1861 : lui ne retient pas les titres qui
        /// ne précèdent aucune clé — voir `TranslationDiffGroups`. Le mod
        /// entier, ses trois composants réunis, en rend 1878 titrés.) Sans ce
        /// rang, replier
        /// l'une les replierait toutes et la navigation tomberait toujours sur
        /// la première.
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
                    // Une clé lue deux fois garde la section de sa **première**
                    // occurrence — voir la note sur `sectionByKey`/`sectionIndexByKey`.
                    if let section = currentSection, sectionByKey[literal] == nil {
                        sectionByKey[literal] = section
                    }
                    if let rank = currentSectionIndex, sectionIndexByKey[literal] == nil {
                        sectionIndexByKey[literal] = rank
                    }
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
                        // Même règle que la clé quotée ci-dessus : première
                        // occurrence gagne.
                        if let section = currentSection, sectionByKey[literal] == nil {
                            sectionByKey[literal] = section
                        }
                        if let rank = currentSectionIndex, sectionIndexByKey[literal] == nil {
                            sectionIndexByKey[literal] = rank
                        }
                    }
                    index = end
                    continue
                }
                index = end
                continue
            }

            if character == "{" || character == "[" { depth += 1 }
            // Borné à zéro : une accolade fermante en trop — un fichier que le
            // parseur laxiste répare pourtant — faisait passer la profondeur
            // sous zéro, et toutes les clés suivantes étaient alors vues hors
            // du premier niveau, donc perdues.
            if character == "}" || character == "]" { depth = max(0, depth - 1) }
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
    /// ⚠️ Déséchapper est obligatoire, pas cosmétique : c'est par ce nom que la
    /// clé est retrouvée dans ce que rend le parseur, et `JSONSerialization`
    /// rend `a"b`, jamais `a\"b`. Garder l'échappement brut — ce que faisait ce
    /// code — donnait deux orthographes de la même clé, donc une clé sans
    /// section ni rang dans l'onglet Traduction.
    ///
    /// Les unités UTF-16 sont accumulées telles quelles pour que `😀`
    /// se recompose en un seul emoji, comme le fait le parseur.
    private static func readString(_ c: [Character], from start: Int) -> (String, Int) {
        var units: [UInt16] = []
        var index = start + 1
        while index < c.count {
            if c[index] == "\\", index + 1 < c.count {
                let escaped = c[index + 1]
                switch escaped {
                case "\"", "\\", "/": units.append(contentsOf: String(escaped).utf16)
                case "b": units.append(0x08)
                case "f": units.append(0x0C)
                case "n": units.append(0x0A)
                case "r": units.append(0x0D)
                case "t": units.append(0x09)
                case "u":
                    let hexStart = index + 2
                    let hexEnd = hexStart + 4
                    if hexEnd <= c.count,
                       let unit = UInt16(String(c[hexStart..<hexEnd]), radix: 16) {
                        units.append(unit)
                        index = hexEnd
                        continue
                    }
                    // Séquence tronquée ou non hexadécimale : la laisser telle
                    // quelle plutôt que d'inventer un caractère.
                    units.append(contentsOf: "\\u".utf16)
                default:
                    // Échappement inconnu : le parseur le refuserait, l'analyse
                    // reste tolérante et garde les deux caractères.
                    units.append(contentsOf: String(c[index]).utf16)
                    units.append(contentsOf: String(escaped).utf16)
                }
                index += 2
                continue
            }
            if c[index] == "\"" { return (String(decoding: units, as: UTF16.self), index + 1) }
            units.append(contentsOf: String(c[index]).utf16)
            index += 1
        }
        return (String(decoding: units, as: UTF16.self), index)
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
