import Foundation

/// Sépare, dans une valeur de traduction, ce qui se traduit de ce qui doit être
/// repris tel quel.
///
/// Un fichier i18n de Stardew Valley mêle la phrase et des marques que le jeu
/// interprète. Les traduire ou les déplacer casse le mod : au mieux le texte
/// s'affiche mal, au pire le dialogue ne se déclenche plus. Un traducteur qui
/// ne les distingue pas du texte les abîme sans le savoir — les montrer est la
/// première chose à faire pour lui.
///
/// Relevé sur les 473 fichiers français du parc de référence : 118 000
/// commandes de portrait, 72 000 séparateurs `#$…#`, 16 000 `@`, 13 000 `^`,
/// 3 600 tokens Content Patcher, 2 200 substitutions `%…`, 1 500 index d'objet
/// et 700 emplacements positionnels. Un dialogue en est truffé — c'est la
/// réalité de ces textes, pas un cas limite.
public enum TranslationTokens {
    /// Un morceau de la valeur : du texte, ou une marque à ne pas toucher.
    public struct Segment: Equatable, Sendable {
        public let text: String
        public let isCode: Bool

        public init(text: String, isCode: Bool) {
            self.text = text
            self.isCode = isCode
        }
    }

    /// Découpe une valeur en segments. Concaténés, ils rendent exactement la
    /// chaîne d'origine — c'est ce qui garantit qu'aucun caractère ne se perd à
    /// l'affichage.
    public static func split(_ text: String) -> [Segment] {
        let characters = Array(text)
        var segments: [Segment] = []
        var plain = ""
        var index = 0

        func flushPlain() {
            guard !plain.isEmpty else { return }
            segments.append(Segment(text: plain, isCode: false))
            plain = ""
        }

        while index < characters.count {
            guard let match = token(in: characters, at: index) else {
                plain.append(characters[index])
                index += 1
                continue
            }
            flushPlain()
            segments.append(Segment(text: String(characters[index..<match]), isCode: true))
            index = match
        }
        flushPlain()
        return segments
    }

    /// Y a-t-il une marque à `start` ? Rend l'index juste après, ou `nil`.
    ///
    /// L'ordre compte : `#$b#` contient `$b`, et le reconnaître d'abord évite
    /// de rendre trois fragments là où il n'y a qu'une marque.
    private static func token(in characters: [Character], at start: Int) -> Int? {
        dialogueSeparator(characters, start)
            ?? contentPatcherToken(characters, start)
            ?? positionalPlaceholder(characters, start)
            ?? portraitCommand(characters, start)
            ?? substitution(characters, start)
            ?? itemIndex(characters, start)
            ?? singleCharacterMark(characters, start)
    }

    /// `#$b#`, `#$e#` — pause et fin de page dans un dialogue.
    private static func dialogueSeparator(_ c: [Character], _ i: Int) -> Int? {
        guard i + 3 < c.count, c[i] == "#", c[i + 1] == "$", c[i + 3] == "#",
              c[i + 2].isLetter || c[i + 2].isNumber else { return nil }
        return i + 4
    }

    /// `{{…}}`, **imbrication comprise**.
    ///
    /// `{{Random:{{Range:1,5}}}}` est une forme réelle : compter les paires
    /// d'accolades plutôt que s'arrêter au premier `}}` évite de couper en deux
    /// ce qui n'est qu'un token.
    private static func contentPatcherToken(_ c: [Character], _ i: Int) -> Int? {
        guard i + 1 < c.count, c[i] == "{", c[i + 1] == "{" else { return nil }
        var depth = 0
        var j = i
        while j + 1 < c.count {
            if c[j] == "{" && c[j + 1] == "{" {
                depth += 1
                j += 2
            } else if c[j] == "}" && c[j + 1] == "}" {
                depth -= 1
                j += 2
                if depth == 0 { return j }
            } else {
                j += 1
            }
        }
        // Jamais refermé : c'est du texte abîmé, pas une marque. Le signaler
        // comme du code laisserait croire qu'il ne faut pas y toucher.
        return nil
    }

    /// `{0}`, `{12}` — emplacement positionnel de SMAPI.
    private static func positionalPlaceholder(_ c: [Character], _ i: Int) -> Int? {
        guard c[i] == "{" else { return nil }
        var j = i + 1
        while j < c.count, c[j].isNumber { j += 1 }
        guard j > i + 1, j < c.count, c[j] == "}" else { return nil }
        return j + 1
    }

    /// `$2`, `$h` — expression du portrait. Numérique autant que littérale.
    private static func portraitCommand(_ c: [Character], _ i: Int) -> Int? {
        guard c[i] == "$", i + 1 < c.count,
              c[i + 1].isLetter || c[i + 1].isNumber else { return nil }
        return i + 2
    }

    /// `%item`, `%farm` — substitution du jeu.
    private static func substitution(_ c: [Character], _ i: Int) -> Int? {
        guard c[i] == "%", i + 1 < c.count, c[i + 1].isLetter else { return nil }
        var j = i + 1
        while j < c.count, c[j].isLetter { j += 1 }
        return j
    }

    /// `[#]`, `[128]` — index d'objet dans une description de quête.
    private static func itemIndex(_ c: [Character], _ i: Int) -> Int? {
        guard c[i] == "[" else { return nil }
        var j = i + 1
        while j < c.count, c[j].isNumber { j += 1 }
        if j == i + 1, j < c.count, c[j] == "#" { j += 1 }
        guard j > i + 1, j < c.count, c[j] == "]" else { return nil }
        return j + 1
    }

    /// `^` saut de ligne, `@` nom du joueur. Une seule lettre, mais qui compte :
    /// un `@` perdu et le personnage n'appelle plus le joueur par son nom.
    private static func singleCharacterMark(_ c: [Character], _ i: Int) -> Int? {
        (c[i] == "^" || c[i] == "@") ? i + 1 : nil
    }
}
