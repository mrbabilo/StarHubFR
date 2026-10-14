import Foundation

/// Ce qu'une traduction n'a **pas** le droit de perdre.
///
/// Le vocabulaire des marques n'est pas redéfini ici : il vit dans
/// `TranslationTokens`, reconnu caractère par caractère et éprouvé sur les 473
/// fichiers français du parc. En tenir une seconde liste la ferait diverger, et
/// la nôtre serait la plus faible — une expression régulière ne sait ni suivre
/// l'imbrication de `{{Random:{{Range:1,5}}}}`, ni voir où se ferme
/// `%item object 349 10 %%`, dont les arguments sont des identifiants d'objet
/// et non du texte.
///
/// Ce module n'ajoute que ce qui manquait : **compter**, **comparer**, et
/// distinguer ce qui bloque de ce qui avertit.
public enum TranslationTokenCheck {

    /// Une marque dont le compte diffère entre la source et la traduction.
    public struct Mismatch: Equatable, Sendable {
        public let token: String
        /// Occurrences dans la source anglaise.
        public let expected: Int
        /// Occurrences dans la traduction.
        public let found: Int
        public let isHard: Bool

        public init(token: String, expected: Int, found: Int, isHard: Bool) {
            self.token = token
            self.expected = expected
            self.found = found
            self.isHard = isHard
        }
    }

    /// Les marques présentes, dans l'ordre d'apparition, doublons compris.
    public static func extract(_ text: String) -> [String] {
        TranslationTokens.split(text).filter(\.isCode).map(\.text)
    }

    /// Dur = significatif à l'exécution, donc bloquant.
    ///
    /// Tout ce que `TranslationTokens` reconnaît l'est : ce sont des marques que
    /// le jeu interprète. Les formes **souples** — le saut de ligne littéral et
    /// les apostrophes appariées — ne sont pas reconnues comme des marques par
    /// le découpage et ne remontent donc jamais ici. C'est voulu : une
    /// traduction qui replie ses lignes n'est pas fautive, et la refuser pour
    /// cela est le défaut le plus coûteux de la référence.
    public static func isHard(_ token: String) -> Bool {
        !token.isEmpty
    }

    /// Les divergences entre source et traduction, comparées en **multiensemble**.
    ///
    /// Un ensemble ne verrait pas la perte du second `#$b#` sur deux : c'est
    /// précisément ce qui casse un dialogue en jeu. L'**ordre**, lui, n'entre
    /// pas en compte — le français déplace volontiers ce que l'anglais met en
    /// tête, sans rien casser.
    ///
    /// Compare `comparedTokens`, pas `extract` : le sélecteur de genre est hors
    /// jeu, pour la raison qu'y explique sa note.
    public static func mismatches(source: String, target: String) -> [Mismatch] {
        let sourceCounts = counted(comparedTokens(source))
        let targetCounts = counted(comparedTokens(target))
        var out = Set(sourceCounts.keys).union(targetCounts.keys).sorted().compactMap { token -> Mismatch? in
            let expected = sourceCounts[token] ?? 0
            let found = targetCounts[token] ?? 0
            guard expected != found else { return nil }
            return Mismatch(token: token, expected: expected, found: found, isHard: isHard(token))
        }
        // Attendu : les `_` que la source **écrit** ; trouvé : ceux que le jeu
        // **lira** dans la traduction. Pas le jeu des deux côtés : une source
        // déjà coupée par son anglais (« you're » chez Sterling) refuserait la
        // bonne correction française.
        let expected = quickResponseSeparators(source, asWritten: true)
        let found = quickResponseSeparators(target)
        if expected != found {
            out.append(Mismatch(token: quickResponseToken, expected: expected.reduce(0, +),
                                found: found.reduce(0, +), isHard: true))
        }
        return out
    }

    /// La structure d'une réponse rapide `$y`, comparée comme une marque : ses
    /// `_` comptés **tels que le jeu les lit**.
    public static let quickResponseToken = "$y _"

    /// Les `_` de chaque `$y`, dans l'ordre. Règle de `Dialogue.parseDialogueString`
    /// (Stardew Valley.dll, relue le 2026-10-14) : le dialogue se découpe sur
    /// `#` ; un segment dont le premier mot est `$y` garde le texte après sa
    /// **première** apostrophe (tout le segment s'il n'en a pas), en retire le
    /// dernier caractère, puis se coupe sur `_` en question, puis paires
    /// réponse / réplique. Une apostrophe droite dans une source sans
    /// guillemets (« j'aie », Sterling `winter_Mon6` du parc) déplace donc le
    /// début de la réponse ; un `_` de trop ou de moins change les réponses, et
    /// un nombre impair fait lire une réplique qui n'existe pas — le dialogue
    /// plante. Le `’` typographique ne coupe rien.
    /// `asWritten` : tous les `_` du segment, ceux que l'auteur a voulus.
    static func quickResponseSeparators(_ text: String, asWritten: Bool = false) -> [Int] {
        text.split(separator: "#", omittingEmptySubsequences: false).compactMap { segment -> Int? in
            guard segment.split(separator: " ", maxSplits: 1).first == "$y" else { return nil }
            if asWritten { return segment.filter { $0 == "_" }.count }
            let start = segment.firstIndex(of: "'").map { segment.index(after: $0) } ?? segment.startIndex
            return segment[start...].dropLast().filter { $0 == "_" }.count
        }
    }

    /// Les marques **comparables** : celles d'`extract`, moins les bornes d'un
    /// sélecteur de genre et le `^` qui les sépare. Rien d'autre — ce qui vit
    /// *dans* un sélecteur reste comparé.
    ///
    /// Le nombre de `${…}$` d'une traduction ne se déduit pas de sa source : le
    /// français accorde en genre là où l'anglais reste neutre. Sur le parc de
    /// l'auteur, 211 sélecteurs côté source contre **1 528** côté français ; et
    /// la localisation française du jeu fait de même — un sélecteur devient
    /// trois dans `Abigail/summer_Tue4`. Les compter revenait à refuser la
    /// traduction juste : **1 092 des 4 331** lignes du parc signalées en écart
    /// de marques n'avaient que ce motif, et l'écriture les bloquait toutes.
    ///
    /// ⚠️ La levée s'arrête là. Exempter tout le **contenu** d'un sélecteur
    /// aurait levé 1 227 lignes au lieu de 1 092 — les 135 de plus sont de
    /// vraies pertes (`$10`, `$0`, `@`) que ce contrôle doit voir : un `#$b#`
    /// reste une fin de page dans un sélecteur comme dehors. Un sélecteur mal
    /// refermé, lui, n'en est pas un pour `TranslationTokens` : son contenu
    /// retombe dans le texte comparé, donc l'écart remonte.
    private static func comparedTokens(_ text: String) -> [String] {
        var out: [String] = []
        var depth = 0
        for segment in TranslationTokens.split(text) where segment.isCode {
            if segment.text == "${" { depth += 1; continue }
            if segment.text == "}$" { depth = max(0, depth - 1); continue }
            // Le `^` d'un sélecteur est un séparateur de genre, pas un saut de
            // ligne : c'est **lui** que le nombre de sélecteurs entraîne. Les
            // autres marques, elles, restent comparées où qu'elles soient —
            // un `#$b#` reste une fin de page à l'intérieur d'un sélecteur
            // comme dehors, et le perdre casse le dialogue de la même façon.
            if depth > 0, segment.text == "^" { continue }
            out.append(segment.text)
        }
        return out
    }

    private static func counted(_ tokens: [String]) -> [String: Int] {
        tokens.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
}
