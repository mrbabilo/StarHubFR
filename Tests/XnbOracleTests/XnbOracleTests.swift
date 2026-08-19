import Foundation
import Testing
@testable import StarHubTHCore

/// L'oracle : notre lecteur XNB contre la sortie de StardewXnbHack, sur les
/// fichiers **réels** du jeu installé. Une erreur de bit LZX ne survit pas
/// au parse structuré — l'égalité est intégrale, fichier par fichier.
///
/// Se skippe proprement sans l'environnement : il exige `STARDEW_GAME_DIR`
/// (le dossier `Resources` du jeu) et un `Content (unpacked)` produit une
/// fois par StardewXnbHack (https://github.com/Pathoschild/StardewXnbHack —
/// dézipper dans le dossier du jeu, lancer le binaire). Aucune donnée du
/// jeu ne vit dans le dépôt.
struct XnbOracleTests {
    static let gameDir = ProcessInfo.processInfo.environment["STARDEW_GAME_DIR"]
        .map { URL(fileURLWithPath: $0) }
    static let strings = gameDir?.appendingPathComponent("Content/Strings")
    static let unpacked = gameDir?.appendingPathComponent("Content (unpacked)/Strings")

    /// Se skippe proprement sans l'environnement (spec §9) : l'oracle n'a de
    /// valeur que contre des fichiers réels, jamais en fixture.
    @Test(.enabled(if: gameDir != nil && FileManager.default.fileExists(
        atPath: unpacked?.path ?? ""),
        "STARDEW_GAME_DIR absent ou dossier unpacké manquant — lancer StardewXnbHack puis exporter STARDEW_GAME_DIR"))
    func everyRealXnbMatchesStardewXnbHackOutput() throws {
        guard let strings = Self.strings, let unpacked = Self.unpacked else {
            preconditionFailure("garanti par .enabled — intouchable sans environnement")
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: strings, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "xnb" }
        #expect(files.count > 300, "le jeu expose ~373 fichiers Strings")

        var checked = 0
        var matched = 0
        var nonDictionaries = 0
        for file in files {
            let ours: [String: String]
            do {
                ours = try XnbStringDictionaryReader.read(try Data(contentsOf: file))
            } catch XnbStringDictionaryReader.ReadError.rootNotStringDictionary {
                // Refus **voulu** : les 12 `credits.*.xnb` sont des
                // `List<String>`, pas des dictionnaires — le lecteur est
                // délibérément étroit, et StardewXnbHack en fait un tableau
                // JSON qu'on ne saurait pas comparer non plus.
                nonDictionaries += 1
                continue
            } catch {
                Issue.record("Illisible par notre lecteur : \(file.lastPathComponent) → \(error)")
                continue
            }
            let jsonName = file.deletingPathExtension()
                .appendingPathExtension("json").lastPathComponent
            guard let raw = try? Data(contentsOf: unpacked.appendingPathComponent(jsonName)),
                  let obj = (try? JSONSerialization.jsonObject(with: raw)) as? [String: String] else {
                Issue.record("Illisible côté oracle : \(jsonName)")
                continue
            }
            checked += 1
            if ours == obj {
                matched += 1
            } else {
                Issue.record("Divergence sur \(file.lastPathComponent)")
            }
        }
        #expect(checked > 300, "chaque dictionnaire doit être lisible ET comparable")
        #expect(nonDictionaries == 12, "les 12 `credits.*.xnb` sont les seuls non-dictionnaires")
        #expect(checked == matched, "égalité intégrale attendue — \(checked - matched) divergences")
    }
}
