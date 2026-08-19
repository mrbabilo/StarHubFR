import Foundation
import Testing
@testable import StarHubTHCore

/// L'oracle : notre lecteur XNB contre la sortie de StardewXnbHack, sur les
/// fichiers **réels** du jeu installé. Une erreur de bit LZX ne survit pas
/// au parse structuré — l'égalité est intégrale, fichier par fichier.
///
/// Se skippe proprement sans l'environnement : il exige `STARDEW_GAME_DIR`,
/// un dossier qui expose `Content/Strings` (les `.xnb`) **et**
/// `Content (unpacked)/Strings` (les `.json` de StardewXnbHack). Aucune
/// donnée du jeu ne vit dans le dépôt.
///
/// Recette mesurée le 2026-08-19 (macOS, jeu GOG), qui ne touche pas au
/// bundle installé — StardewXnbHack démarre une instance du jeu, il lui
/// faut donc **tout** `Content`, pas seulement `Strings` :
///
/// 1. `StardewXnbHack-<v>-for-macOS.zip` → un binaire unique.
/// 2. Monter un faux dossier de jeu : liens vers tout
///    `Stardew Valley.app/Contents/MacOS/*` (sauf `Mods`), **copie** de
///    `Contents/Resources/Content`, et le binaire dedans.
/// 3. L'exécuter depuis ce `MacOS/` ; il écrit `Content (unpacked)` à côté.
///    L'exception finale (`Cannot read keys…`) n'est que le « press any
///    key » sans console : le travail est fait.
/// 4. Un dossier racine avec deux liens — `Content` vers le vrai jeu,
///    `Content (unpacked)` vers la sortie — puis `STARDEW_GAME_DIR=…`.
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
        #expect(files.count > 300, "le jeu expose 372 fichiers Strings")

        var checked = 0
        var matched = 0
        var nonDictionaries: [String] = []
        for file in files {
            let ours: [String: String]
            do {
                ours = try XnbStringDictionaryReader.read(try Data(contentsOf: file))
            } catch XnbStringDictionaryReader.ReadError.rootNotStringDictionary {
                // Refus **voulu** : les 12 `credits.*.xnb` sont des
                // `List<String>`, pas des dictionnaires — le lecteur est
                // délibérément étroit, et StardewXnbHack en fait un tableau
                // JSON qu'on ne saurait pas comparer non plus.
                nonDictionaries.append(file.lastPathComponent)
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
        print("ORACLE \(files.count) fichiers — \(checked) dictionnaires comparés, "
            + "\(matched) identiques, \(nonDictionaries.count) non-dictionnaires")
        #expect(checked > 300, "chaque dictionnaire doit être lisible ET comparable")
        // Compter les `credits.*` figerait le nombre de langues du jeu : une
        // langue ajoutée virerait l'oracle au rouge sans rien dire du
        // lecteur. Ce qui compte, c'est qu'aucun **autre** asset ne se
        // refuse — 12 fichiers `credits` le 2026-08-19, sur 372.
        let unexpected = nonDictionaries.filter { !$0.hasPrefix("credits") }
        #expect(unexpected.isEmpty,
                "seuls les `credits.*.xnb` (des `List<String>`) peuvent se refuser — reçu \(unexpected)")
        #expect(checked == matched, "égalité intégrale attendue — \(checked - matched) divergences")
    }
}
