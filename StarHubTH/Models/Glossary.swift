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

    /// Les entrées prêtes pour le matching : filtrées et triées **une fois**,
    /// à la construction. Refaire ce tri à chaque appel coûtait, sur le
    /// glossaire réel (1 126 entrées), environ 2·n log n évaluations de
    /// `String.count` — une longueur en graphèmes, donc O(n) — par rangée
    /// traduite, et un lot en traite des milliers.
    ///
    /// Dérivé de `entries`, donc hors du JSON : la clé de codage reste seule.
    private let candidates: [GlossaryEntry]

    private enum CodingKeys: String, CodingKey {
        case entries
    }

    public init(entries: [GlossaryEntry]) {
        self.entries = entries
        self.candidates = Self.candidates(from: entries)
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
        for entry in candidates where !entry.en.isEmpty {
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
