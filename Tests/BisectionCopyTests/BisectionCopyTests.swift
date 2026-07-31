import Testing
import Foundation

/// Garde-fou de vocabulaire. La fonctionnalité s'adresse à quelqu'un dont le jeu
/// plante, pas à quelqu'un qui débogue : on parle de « mettre en pause » et non
/// de « désactiver », de « mod à l'origine du problème » et non de « candidat ».
/// Sans ce garde-fou, le jargon reviendrait par une clé ajoutée dans six mois
/// sans y penser.
struct BisectionCopyTests {
    private static let banned = [
        "bissection", "bisection", "dichotom", "itération", "iteration",
        "toggle", "verdict", "c#", ".dll", "désactiver", "disable",
        "candidat", "suspect", "closure", "fermeture",
    ]

    private func strings(_ locale: String) throws -> [String: String] {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("assets/\(locale).json")
        let data = try Data(contentsOf: url)
        let all = try JSONDecoder().decode([String: String].self, from: data)
        return all.filter { $0.key.hasPrefix("bisect_") }
    }

    @Test func everyBisectStringExistsInBothLocales() throws {
        let en = try strings("en"), fr = try strings("fr")
        #expect(!en.isEmpty)
        #expect(Set(en.keys) == Set(fr.keys))
    }

    @Test func noVisibleStringUsesJargon() throws {
        for locale in ["en", "fr"] {
            for (key, value) in try strings(locale) {
                let lowered = value.lowercased()
                for word in Self.banned where lowered.contains(word) {
                    Issue.record("\(locale).json / \(key) contient « \(word) » : \(value)")
                }
            }
        }
    }
}
