import Foundation
import Testing
@testable import StarHubTHCore

/// Préservation des fichiers utilisateur (`config.json` + `i18n/*.json`) lors
/// d'une mise à jour « avec backup » : les traductions communautaires
/// (`i18n/fr.json`, `i18n/default.json`) doivent survivre à l'écrasement du
/// dossier, **dans leur sous-dossier `i18n/`**. Historiquement le snapshot
/// cherchait ces fichiers à la racine du mod, donc ne les trouvait jamais et
/// la traduction était perdue à chaque update — voir `docs/DOMAINE.md` §5
/// (B4-T4 : 16 `fr.json` du parc de référence ne survivent qu'en backup).
@Suite struct PreserveUserConfigsTests {

    /// Construit un faux mod : `config.json` à la racine + `i18n/default.json`
    /// et `i18n/fr.json` (la structure SMAPI canonique).
    @discardableResult
    private func makeModWithTranslations() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarHubTHPreserveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try #"{"EnableFeatures":true}"#.data(using: .utf8)!
            .write(to: root.appendingPathComponent("config.json"))
        let i18n = root.appendingPathComponent("i18n", isDirectory: true)
        try FileManager.default.createDirectory(at: i18n, withIntermediateDirectories: true)
        try #"{"key":"Default"}"#.data(using: .utf8)!
            .write(to: i18n.appendingPathComponent("default.json"))
        try #"{"key":"Bonjour"}"#.data(using: .utf8)!
            .write(to: i18n.appendingPathComponent("fr.json"))
        return root
    }

    // MARK: - ModConfigFiles.preservableFiles (source unique)

    @Test func preservableFiles_returnsRelativePathsForConfigAndTranslations() throws {
        let mod = try makeModWithTranslations()
        defer { try? FileManager.default.removeItem(at: mod) }

        let found = ModConfigFiles.preservableFiles(under: mod.path)

        // Le chemin relatif — pas seulement le nom — est indispensable :
        // "i18n/fr.json", pas "fr.json". C'est ce que le snapshot doit clé.
        let paths = Set(found.map(\.relativePath))
        #expect(paths == ["config.json", "i18n/default.json", "i18n/fr.json"])
    }

    @Test func preservableFiles_ignoresNonPreservableFiles() throws {
        let mod = try makeModWithTranslations()
        defer { try? FileManager.default.removeItem(at: mod) }
        try #"{"Name":"X"}"#.data(using: .utf8)!
            .write(to: mod.appendingPathComponent("manifest.json"))

        let found = ModConfigFiles.preservableFiles(under: mod.path)

        #expect(found.map { $0.url.lastPathComponent }.contains("manifest.json") == false)
    }

    @Test func preservableFiles_keepsFullRelativePathWhenDeeplyNested() throws {
        // Certains packs Content Patcher placent l'i18n dans un sous-dossier.
        // La recherche récursive doit retrouver le fichier avec son chemin
        // relatif complet, pas l'aplatir.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarHubTHPreserveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let deep = root.appendingPathComponent("Sub", isDirectory: true)
            .appendingPathComponent("i18n", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try #"{"k":"v"}"#.data(using: .utf8)!.write(to: deep.appendingPathComponent("fr.json"))

        let found = ModConfigFiles.preservableFiles(under: root.path)

        let fr = try #require(found.first { $0.url.lastPathComponent == "fr.json" })
        #expect(fr.relativePath == "Sub/i18n/fr.json")
    }

    // MARK: - snapshot + restore, bout en bout

    @Test func snapshotKeysTranslationsByRelativePath() throws {
        let installer = ModZipInstaller()
        let mod = try makeModWithTranslations()
        defer { try? FileManager.default.removeItem(at: mod) }

        let preserved = installer.snapshotUserConfigs(from: mod.path)

        // La clé est le chemin relatif — sans cela, le restore ne saurait pas
        // que fr.json doit retourner sous i18n/.
        #expect(Set(preserved.keys) == ["config.json", "i18n/default.json", "i18n/fr.json"])
    }

    @Test func restorePutsTranslationsBackInI18nFolder() throws {
        let installer = ModZipInstaller()
        let source = try makeModWithTranslations()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarHubTHPreserveDest-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: dest)
        }

        // 1. Snapshot depuis le mod existant (config + traductions).
        var preserved = installer.snapshotUserConfigs(from: source.path)
        #expect(preserved.keys.contains("i18n/fr.json"))

        // 2. Simule l'écrasement : une archive neuve SANS le fr.json communautaire
        //    (cas courant — l'auteur ne redistribue pas la traduction FR).
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try #"{"EnableFeatures":false}"#.data(using: .utf8)!
            .write(to: dest.appendingPathComponent("config.json"))
        let newI18n = dest.appendingPathComponent("i18n", isDirectory: true)
        try FileManager.default.createDirectory(at: newI18n, withIntermediateDirectories: true)
        try #"{"key":"NewDefault"}"#.data(using: .utf8)!
            .write(to: newI18n.appendingPathComponent("default.json"))

        // 3. Restore par-dessus la copie fraîche.
        try installer.restoreUserConfigs(&preserved, into: dest.path)

        // 4. La traduction FR communautaire survit, DANS i18n/ (pas à la racine).
        let restoredFR = dest.appendingPathComponent("i18n").appendingPathComponent("fr.json")
        #expect(FileManager.default.fileExists(atPath: restoredFR.path))
        let content = try String(contentsOf: restoredFR, encoding: .utf8)
        #expect(content.contains("Bonjour"))

        // Le config.json snapshotté écrase celui de la nouvelle archive.
        let restoredConfig = try String(contentsOf: dest.appendingPathComponent("config.json"), encoding: .utf8)
        #expect(restoredConfig.contains("true"))

        // Tous les snapshots sont consommés (le defer de l'installer ne nettoie
        // rien de résiduel).
        #expect(preserved.isEmpty)
    }

    @Test func restoreCreatesI18nFolderIfMissing() throws {
        // Cas extrême : la nouvelle archive n'a même pas de dossier i18n/.
        let installer = ModZipInstaller()
        let source = try makeModWithTranslations()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarHubTHPreserveDest-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: dest)
        }

        var preserved = installer.snapshotUserConfigs(from: source.path)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        // Aucun i18n/ dans la nouvelle archive.

        try installer.restoreUserConfigs(&preserved, into: dest.path)

        #expect(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("i18n").appendingPathComponent("fr.json").path))
    }
}
