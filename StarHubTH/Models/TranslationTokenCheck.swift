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
    public static func mismatches(source: String, target: String) -> [Mismatch] {
        let sourceCounts = counted(extract(source))
        let targetCounts = counted(extract(target))
        return Set(sourceCounts.keys).union(targetCounts.keys).sorted().compactMap { token in
            let expected = sourceCounts[token] ?? 0
            let found = targetCounts[token] ?? 0
            guard expected != found else { return nil }
            return Mismatch(token: token, expected: expected, found: found, isHard: isHard(token))
        }
    }

    private static func counted(_ tokens: [String]) -> [String: Int] {
        tokens.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
}
