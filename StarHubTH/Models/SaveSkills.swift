import Foundation

/// Une compétence du fermier : niveau et points d'expérience (B6-T3).
public struct SaveSkill: Equatable, Hashable, Sendable {
    public let level: Int
    public let experience: Int

    public init(level: Int, experience: Int) {
        self.level = level
        self.experience = experience
    }
}

/// Les six compétences du jeu, dans l'ordre de `<experiencePoints>` (mesuré
/// sur le parc le 2026-11-27 : pêche 522 points ↔ niveau 2, combat 8 206 ↔ 8).
public enum SaveSkills {
    /// Balise du niveau, à l'index de la compétence dans `<experiencePoints>`.
    static let levelTags = ["farmingLevel", "fishingLevel", "foragingLevel",
                            "miningLevel", "combatLevel", "luckLevel"]
    static let nameKeys = [L10n.Saves.skillFarming, L10n.Saves.skillFishing, L10n.Saves.skillForaging,
                           L10n.Saves.skillMining, L10n.Saves.skillCombat, L10n.Saves.skillLuck]
    /// Points cumulés pour atteindre les niveaux 1 à 10 (`Farmer.checkForLevelGain`).
    static let thresholds = [100, 380, 770, 1300, 2150, 3300, 4800, 6900, 10000, 15000]
    /// La chance n'a pas de métier : jamais de menu de niveau pour elle.
    static let luckIndex = 5

    /// Niveau du jeu de base pour `experience` points (0 à 10).
    static func level(forExperience experience: Int) -> Int {
        thresholds.lastIndex { experience >= $0 }.map { $0 + 1 } ?? 0
    }

    /// Les points de `<experiencePoints>` du fermier, `nil` s'il n'y en a pas.
    /// Seule occurrence de la partie, dans `<player>` (mesuré sur les deux
    /// parties du parc : les monstres de quête n'en portent pas).
    static func experience(in xml: String) -> [Int]? {
        guard let player = SavePlayerFields.playerBlock(in: xml),
              let open = player.range(of: "<experiencePoints>"),
              let close = player.range(of: "</experiencePoints>", range: open.upperBound..<player.endIndex)
        else { return nil }
        return player[open.upperBound..<close.lowerBound]
            .components(separatedBy: "<int>").dropFirst()
            .compactMap { Int($0.prefix { $0 != "<" }) }
    }

    /// Les compétences lues dans une partie : niveaux des enfants directs de
    /// `<player>`, points de `<experiencePoints>`. Vide si l'un manque.
    static func skills(levels player: [String: String], xml: String) -> [SaveSkill] {
        guard let points = experience(in: xml), points.count >= levelTags.count else { return [] }
        return levelTags.enumerated().map { index, tag in
            SaveSkill(level: player[tag].flatMap(Int.init) ?? 0, experience: points[index])
        }
    }
}
