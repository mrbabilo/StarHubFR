import Foundation

/// Tâche 8 du plan P2b — le glossaire assemblé et son matching (spec §5).
///
/// Matching whole-word **case-sensitive** (les entités nommées sont
/// capitalisées ; `Play` de l'UI ne matche pas le verbe `play` en prose),
/// termes ≥ 3 caractères, tri par longueur décroissante : le terme le plus
/// spécifique réclame sa plage de caractères (`Iridium Ore` avant `Ore` sur
/// le même texte), plafond 15 par valeur.
public struct Glossary: Codable, Equatable, Sendable {
    public let entries: [GlossaryEntry]

    /// Les entrées prêtes pour le matching, rangées par leur **premier mot** —
    /// filtrées, triées et indexées **une fois**, à la construction. Refaire ce
    /// tri à chaque appel coûtait, sur le glossaire réel (1 126 entrées),
    /// environ 2·n log n évaluations de `String.count` — une longueur en
    /// graphèmes, donc O(n) — par rangée traduite, et un lot en traite des
    /// milliers.
    ///
    /// Dérivé d'`entries`, donc hors du JSON : la clé de codage reste seule.
    ///
    /// Un terme ne peut apparaître dans une source que si son premier mot y
    /// figure comme mot entier : l'appariement exige déjà une frontière de mot
    /// de part et d'autre de la plage, donc le premier mot du terme y forme
    /// forcément un mot entier de la source. Relever les mots de la source une
    /// fois, puis ne chercher que les termes ainsi désignés, écarte le reste du
    /// glossaire sans le chercher.
    ///
    /// Ce n'est pas un raffinement : sans lui, chaque valeur payait une
    /// recherche de sous-chaîne pour **chacune** des 1 126 entrées du
    /// glossaire réel, soit 9 ms par valeur. Préparer le lot de
    /// `[CP] Ridgeside Village` (17 519 clés) demandait 158 s, sur le fil
    /// principal, sans rien afficher.
    private let candidatesByFirstWord: [String: [GlossaryEntry]]
    /// Les termes sans le moindre caractère de mot (`...`) : rien à indexer,
    /// donc toujours cherchés. Le glossaire du jeu n'en produit aucun.
    private let unindexedCandidates: [GlossaryEntry]

    private enum CodingKeys: String, CodingKey {
        case entries
    }

    public init(entries: [GlossaryEntry]) {
        self.entries = entries
        let candidates = Self.candidates(from: entries)
        var byFirstWord: [String: [GlossaryEntry]] = [:]
        var unindexed: [GlossaryEntry] = []
        for entry in candidates {
            if let word = Self.firstWord(of: entry.en) {
                byFirstWord[word, default: []].append(entry)
            } else {
                unindexed.append(entry)
            }
        }
        self.candidatesByFirstWord = byFirstWord
        self.unindexedCandidates = unindexed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(entries: try container.decode([GlossaryEntry].self, forKey: .entries))
    }

    /// Termes d'au moins 3 caractères, longueur décroissante puis ordre
    /// alphabétique : le terme le plus spécifique réclame sa plage d'abord.
    private static func candidates(from entries: [GlossaryEntry]) -> [GlossaryEntry] {
        entries
            .filter { $0.en.count >= 3 }
            .sorted {
                $0.en.count != $1.en.count ? $0.en.count > $1.en.count : $0.en < $1.en
            }
    }

    /// Les entrées du glossaire présentes dans `source`, longueur d'`en`
    /// décroissante (la plus spécifique d'abord), au plus 15.
    public func matchEntries(in source: String) -> [GlossaryEntry] {
        var claimed: [Range<String.Index>] = []
        var matched: [GlossaryEntry] = []
        for entry in shortlist(for: source) where !entry.en.isEmpty {
            if let free = source.ranges(of: entry.en).first(where: { range in
                isBoundary(source, immediatelyBefore: range.lowerBound)
                    && isBoundary(source, immediatelyAfter: range.upperBound)
                    && !claimed.contains { $0.overlaps(range) }
            }) {
                claimed.append(free)
                matched.append(entry)
            }
        }
        return Array(matched.prefix(15))
    }

    /// Les seuls termes qui peuvent apparaître dans cette source : ceux dont le
    /// premier mot y figure, plus les inindexables. Rendus dans l'**ordre
    /// global** de `candidates` — longueur décroissante puis alphabétique —
    /// sans quoi le terme le plus spécifique ne réclamerait plus sa plage en
    /// premier.
    ///
    /// Le tri porte sur une poignée de termes (au plus autant que de mots
    /// distincts dans la source), là où la boucle qu'il remplace parcourait le
    /// glossaire entier.
    private func shortlist(for source: String) -> [GlossaryEntry] {
        // ⚠️ Les mots sont **dédoublonnés** avant d'aller chercher leur seau.
        // Sans cela, un terme dont le premier mot revient deux fois dans la
        // source entrait deux fois dans la liste, et `matchEntries` lui
        // accordait deux plages : « Bear » rendu deux fois. 58 valeurs du parc
        // sur 20 762 comparées y tombaient — aucun test écrit d'avance ne l'a
        // vu, seule la comparaison avec l'ancien parcours sur les vraies
        // données l'a montré.
        var words = Set<String>()
        var word = ""
        func flush() {
            guard !word.isEmpty else { return }
            words.insert(word)
            word = ""
        }
        for character in source {
            if isWordCharacter(character) { word.append(character) } else { flush() }
        }
        flush()

        var shortlisted = unindexedCandidates
        for word in words {
            if let bucket = candidatesByFirstWord[word] { shortlisted.append(contentsOf: bucket) }
        }
        guard shortlisted.count > 1 else { return shortlisted }
        return shortlisted.sorted {
            $0.en.count != $1.en.count ? $0.en.count > $1.en.count : $0.en < $1.en
        }
    }

    /// Le premier mot d'un terme, découpé sur la **même** règle que la
    /// frontière — le tiret et l'apostrophe vivent dans le mot. Découper sur
    /// l'espace seul rangerait `Bear's Knowledge` sous `Bear`, mot que la
    /// source ne porte jamais entier. `nil` quand le terme n'a aucun caractère
    /// de mot.
    private static func firstWord(of term: String) -> String? {
        var word = ""
        for character in term {
            if character == "-" || character == "'" || character.isLetter || character.isNumber {
                word.append(character)
            } else if word.isEmpty {
                continue    // ponctuation de tête : le mot commence après
            } else {
                break
            }
        }
        return word.isEmpty ? nil : word
    }

    /// Frontière de mot : début/fin de chaîne, ou caractère qui n'est ni
    /// lettre, ni chiffre, ni tiret, ni apostrophe — le tiret et l'apostrophe
    /// vivent à l'intérieur du mot (spec §5), `Iridium` ne matche pas
    /// `l'Iridium` ni `Iridium-Ore`.
    private func isBoundary(_ source: String, immediatelyBefore index: String.Index) -> Bool {
        index == source.startIndex
            || !isWordCharacter(source[source.index(before: index)])
    }

    private func isBoundary(_ source: String, immediatelyAfter index: String.Index) -> Bool {
        index == source.endIndex || !isWordCharacter(source[index])
    }

    private func isWordCharacter(_ character: Character) -> Bool {
        character == "-" || character == "'" || character.isLetter || character.isNumber
    }
}
