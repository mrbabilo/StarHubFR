import Foundation

/// La famille de touches d'un mod (spec §1) : lettres pour l'action en jeu,
/// chiffres pour l'informatif courant, F pour le rarement sollicité.
public enum KeybindFamily: String, Codable, CaseIterable, Sendable {
    case action, info, rare
}

/// Devine la famille d'un mod depuis ses noms (mesuré au spike : ~80 % des
/// 107 mods à raccourcis du parc). `nil` = inconnu, jamais déplacé.
public enum KeybindFamilyGuess {
    // Mots-clés du spike : recherche insensible à la casse, par simple
    // `contains`, sur le texte concaténé (pas d'expression régulière).
    private static let rare = ["debug", "overlay", "benchmark", "fps", "screenshot",
                               "reload", "tracing", "clean", "dump", "console",
                               "terminal", "camera", "unlock", "stabilizer", "tuner", "hud"]
    private static let info = ["menu", "planner", "ledger", "encyclop", "overview",
                               "map", "journal", "list", "lookup", "tooltip",
                               "scrapbook", "notebook", "gallery", "collection",
                               "search", "info", "calendar", "tracker", "wiki",
                               "guide", "browser", "catalog"]
    private static let action = ["dive", "jump", "swim", "call", "cast", "use",
                                 "harvest", "store", "swap", "dash", "attack",
                                 "ability", "spell", "slot", "grab", "place",
                                 "water", "plant", "eat", "ride", "whistle",
                                 "roll", "sprint", "charge", "activate", "trigger", "interact"]
    private static let nexusInfo = ["User Interface", "Maps"]
    private static let nexusAction = ["Gameplay Mechanics"]

    public static func guess(modName: String, settingNames: [String],
                             nexusCategory: String?, hasOwnModeContext: Bool) -> KeybindFamily? {
        if hasOwnModeContext { return .rare }
        let text = ([modName] + settingNames).joined(separator: " ").lowercased()
        func count(_ words: [String]) -> Int {
            words.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        }
        let votes: [(KeybindFamily, Int)] = [(.rare, count(rare)), (.action, count(action)), (.info, count(info))]
        if let best = votes.max(by: { ($0.1, voteRank($0.0)) < ($1.1, voteRank($1.0)) }), best.1 > 0 {
            return best.0
        }
        if let category = nexusCategory {
            if nexusInfo.contains(category) { return .info }
            if nexusAction.contains(category) { return .action }
        }
        return nil
    }

    /// Départage d'égalité des votes, stable : rare > action > info — le mot
    /// « overlay » d'un HUD pèse plus que le « menu » qu'il ouvre.
    private static func voteRank(_ family: KeybindFamily) -> Int {
        switch family { case .rare: 2 case .action: 1 case .info: 0 }
    }
}
