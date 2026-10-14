import Foundation

/// La famille de touches d'un mod (spec §1) : lettres pour l'action en jeu,
/// chiffres pour l'informatif courant, F pour le rarement sollicité.
public enum KeybindFamily: String, Codable, CaseIterable, Sendable {
    case action, info, rare
}

/// Devine la famille d'un mod depuis ses noms (mesuré au spike : ~80 % des
/// 107 mods à raccourcis du parc). `nil` = inconnu, jamais déplacé.
public enum KeybindFamilyGuess {
    // Mots-clés du spike, comparés à des *jetons* (camelCase, chiffres et
    // séparateurs découpés), jamais à des sous-chaînes : « Controller »
    // contient « roll », « Weather » « eat », « Mouse » « use »…
    // Mot de 4 lettres ou moins : jeton exact (ou + « s ») ; 5 et plus : préfixe.
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
        let tokens = ([modName] + settingNames).flatMap(tokenize)
        func matches(_ word: String) -> Bool {
            tokens.contains { word.count <= 4 ? ($0 == word || $0 == word + "s") : $0.hasPrefix(word) }
        }
        func count(_ words: [String]) -> Int {
            words.reduce(0) { $0 + (matches($1) ? 1 : 0) }
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

    /// Découpe un nom en jetons minuscules : frontières camelCase/PascalCase
    /// (« UIInfoSuite2Alt » → ui, info, suite, 2, alt), chiffres, séparateurs.
    static func tokenize(_ name: String) -> [String] {
        var tokens: [String] = []
        var current: [Character] = []
        func flush() {
            if !current.isEmpty { tokens.append(String(current).lowercased()); current = [] }
        }
        let chars = Array(name)
        for (i, c) in chars.enumerated() {
            guard c.isLetter || c.isNumber else { flush(); continue }
            if let last = current.last {
                let nextIsLower = i + 1 < chars.count && chars[i + 1].isLowercase
                let boundary = (c.isNumber != last.isNumber)
                    || (c.isUppercase && last.isLowercase)
                    || (c.isUppercase && last.isUppercase && nextIsLower)
                if boundary { flush() }
            }
            current.append(c)
        }
        flush()
        return tokens
    }

    /// Départage d'égalité des votes, stable : rare > action > info — le mot
    /// « overlay » d'un HUD pèse plus que le « menu » qu'il ouvre.
    private static func voteRank(_ family: KeybindFamily) -> Int {
        switch family { case .rare: 2 case .action: 1 case .info: 0 }
    }
}
