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
        // L'ordre va du plus spécifique au plus court : `${…}$` avant la
        // commande `$x`, `%… %%` avant la substitution `%mot`. Autrement, la
        // forme longue se ferait entamer par la courte et le reste passerait
        // pour du texte à traduire.
        genderSelector(characters, start)
            ?? mailCommand(characters, start)
            ?? dialogueSeparator(characters, start)
            ?? contentPatcherToken(characters, start)
            ?? positionalPlaceholder(characters, start)
            ?? portraitCommand(characters, start)
            ?? substitution(characters, start)
            ?? itemIndex(characters, start)
            ?? singleCharacterMark(characters, start)
    }

    /// `${him^her^them}$` — sélection selon le genre du joueur.
    ///
    /// 1520 occurrences dans le parc. Sans reconnaissance dédiée, le `^` interne
    /// passait pour un saut de ligne et les mots pour du texte : traduire
    /// « him » en « lui » ici casse la sélection.
    private static func genderSelector(_ c: [Character], _ i: Int) -> Int? {
        guard i + 1 < c.count, c[i] == "$", c[i + 1] == "{" else { return nil }
        var j = i + 2
        while j < c.count, c[j] != "}" { j += 1 }
        guard j + 1 < c.count, c[j] == "}", c[j + 1] == "$" else { return nil }
        return j + 2
    }

    /// `%item … %%`, `%action … %%` — commandes de courrier.
    ///
    /// Les arguments sont des identifiants d'objet et des quantités, pas du
    /// texte : n'en marquer que `%item` laissait le reste à la merci du
    /// traducteur. 110 occurrences de la première forme dans le parc.
    private static func mailCommand(_ c: [Character], _ i: Int) -> Int? {
        guard c[i] == "%" else { return nil }
        for word in ["item", "action", "revealtaste"] {
            let end = i + 1 + word.count
            guard end <= c.count,
                  String(c[(i + 1)..<end]).lowercased() == word else { continue }
            // Chercher le `%%` de fermeture, sans franchir une fin de ligne :
            // un `%` isolé plus loin dans le texte ne ferme rien.
            var j = end
            while j + 1 < c.count, !c[j].isNewline {
                if c[j] == "%" && c[j + 1] == "%" { return j + 2 }
                j += 1
            }
            return nil
        }
        return nil
    }

    /// `#$b#`, `#$e#` — pause et fin de page dans un dialogue.
    /// Les commandes de plus d'une lettre attestées après `#$`.
    ///
    /// Mesuré sur le parc : 22 formes multi-lettres y suivent `#$`, et **une
    /// seule** est une commande — `#$action`, 812 occurrences. Les 21 autres
    /// sont une commande d'une lettre suivie de prose : `#$bWhat` (19 fois) est
    /// `#$b` puis « What ». D'où une liste close plutôt qu'un mot gourmand :
    /// tout avaler soustrairait ce texte à la traduction.
    private static let multiLetterSeparators: Set<String> = ["action"]

    private static func dialogueSeparator(_ c: [Character], _ i: Int) -> Int? {
        guard i + 2 < c.count, c[i] == "#", c[i + 1] == "$",
              c[i + 2].isLetter || c[i + 2].isNumber else { return nil }
        // Une lettre par défaut ; le mot entier seulement s'il est attesté.
        var j = i + 3
        var word = i + 2
        while word < c.count, c[word].isLetter { word += 1 }
        if word > i + 3, multiLetterSeparators.contains(String(c[(i + 2)..<word])) {
            j = word
        }
        // Le `#` de fermeture (`#$b#`) — sauf quand il ouvre le séparateur
        // suivant : dans `#$action#$b#`, le `#` appartient à `#$b#`, et
        // l'avaler dégradait celui-ci en `$b` en laissant un `#` orphelin.
        if j < c.count, c[j] == "#", !(j + 1 < c.count && c[j + 1] == "$") {
            j += 1
        }
        return j
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
        // Un index à deux chiffres reste entier : `$10` se rendait `$1`, et le
        // `0` retombait dans le texte traduisible. Les formes littérales, elles,
        // tiennent en une lettre (`$b`, `$h`, `$s`) — consommer la suite
        // avalerait le mot qui suit.
        guard c[i + 1].isNumber else { return i + 2 }
        var j = i + 1
        while j < c.count, c[j].isNumber { j += 1 }
        return j
    }

    /// `%item`, `%farm` — substitution du jeu.
    private static func substitution(_ c: [Character], _ i: Int) -> Int? {
        guard c[i] == "%", i + 1 < c.count, c[i + 1].isLetter else { return nil }
        var j = i + 1
        while j < c.count, c[j].isLetter { j += 1 }
        // Les chiffres qui suivent appartiennent à la marque : `%kid1` et
        // `%kid2` se réduisaient tous deux à `%kid`, si bien qu'intervertir le
        // premier et le second enfant passait la comparaison sans un mot.
        while j < c.count, c[j].isNumber { j += 1 }
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
