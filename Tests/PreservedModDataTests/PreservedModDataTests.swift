import Foundation
import Testing
@testable import StarHubTHCore

/// A1-T7 — « absent de l'archive neuve ⇒ donnée locale ».
///
/// Les cas sont tirés du parc réel (ROADMAP §8.4) : `FarmTypeManager/data/`
/// mêle un `default.json` **livré** et des `*_SaveData.save` **écrits en
/// jouant**, et c'est précisément le couple que seule l'archive sépare.
@Suite struct PreservedModDataTests {

    // MARK: - La règle

    @Test("Un fichier que l'archive neuve ne livre pas est préservé")
    func keepsWhatTheArchiveDoesNotShip() {
        let extras = PreservedModData.extraPaths(
            installed: ["data/Zofia_443716371_SaveData.save", "FarmTypeManager.dll"],
            shippedByArchive: ["FarmTypeManager.dll", "manifest.json"],
            alreadyHandled: [])
        #expect(extras == ["data/Zofia_443716371_SaveData.save"])
    }

    /// **Le test central.** C'est l'asymétrie qui empêche la règle de rejouer
    /// le défaut d'`isAuthorLanguageFile` : un fichier que la version neuve
    /// livre ne doit JAMAIS être préservé, sinon on fige la version de
    /// l'auteur à chaque mise à jour.
    @Test("Un fichier que l'archive livre n'est jamais préservé")
    func neverKeepsWhatTheArchiveShips() {
        let extras = PreservedModData.extraPaths(
            installed: ["data/default.json", "data/essai_448486987_SaveData.save"],
            shippedByArchive: ["data/default.json"],
            alreadyHandled: [])
        #expect(extras == ["data/essai_448486987_SaveData.save"])
        #expect(!extras.contains("data/default.json"))
    }

    @Test("Ce que la liste blanche gouverne déjà ne repasse pas ici")
    func leavesTheWhitelistAlone() {
        // `i18n/en.json` est délibérément écarté par `isAuthorLanguageFile` :
        // le reprendre ici contredirait C2-T4 en silence.
        let extras = PreservedModData.extraPaths(
            installed: ["config.json", "i18n/en.json", "i18n/fr.json", "data/save.save"],
            shippedByArchive: [],
            alreadyHandled: ["config.json", "i18n/en.json", "i18n/fr.json"])
        #expect(extras == ["data/save.save"])
    }

    // MARK: - Les formes de chemin

    @Test("La casse ne crée pas un faux extra : macOS est insensible à la casse")
    func matchesCaseInsensitively() {
        let extras = PreservedModData.extraPaths(
            installed: ["Assets/Foo.png"],
            shippedByArchive: ["assets/foo.png"],
            alreadyHandled: [])
        #expect(extras.isEmpty)
    }

    @Test("Un séparateur Windows désigne le même fichier")
    func normalizesBackslashes() {
        let extras = PreservedModData.extraPaths(
            installed: ["data\\config.json"],
            shippedByArchive: ["data/config.json"],
            alreadyHandled: [])
        #expect(extras.isEmpty)
    }

    @Test("Les résidus du système ne sont pas des données")
    func dropsOSJunk() {
        let extras = PreservedModData.extraPaths(
            installed: [".DS_Store", "assets/.DS_Store", "assets/._Foo.png",
                        "__MACOSX/x.png", "data/vrai.save"],
            shippedByArchive: [],
            alreadyHandled: [])
        #expect(extras == ["data/vrai.save"])
    }

    @Test("Un même fichier listé deux fois ne sort qu'une fois")
    func deduplicates() {
        let extras = PreservedModData.extraPaths(
            installed: ["data/a.save", "data/A.SAVE"],
            shippedByArchive: [],
            alreadyHandled: [])
        #expect(extras == ["data/a.save"])
    }

    // MARK: - Le parcours du disque

    @Test("Le parcours rend des chemins relatifs, sous-dossiers compris")
    func enumeratesRelativePaths() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("pmd_\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("data"),
                               withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("manifest.json"))
        try Data().write(to: root.appendingPathComponent("data/Zofia_1_SaveData.save"))
        defer { try? fm.removeItem(at: root) }

        let found = Set(PreservedModData.relativeFiles(under: root, using: fm))
        #expect(found == ["manifest.json", "data/Zofia_1_SaveData.save"])
    }

    /// Un mod en pause vit dans un dossier préfixé par un point, et certains
    /// mods écrivent leurs données dans un sous-dossier caché : les sauter
    /// perdrait exactement ce qu'on cherche à sauver.
    @Test("Le parcours ne saute pas les fichiers cachés")
    func doesNotSkipHiddenFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("pmd_\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent(".cache"),
                               withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent(".cache/state.json"))
        defer { try? fm.removeItem(at: root) }

        #expect(PreservedModData.relativeFiles(under: root, using: fm) == [".cache/state.json"])
    }

    @Test("Un dossier vide ne rend aucun fichier")
    func emptyFolderYieldsNothing() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("pmd_\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("vide"),
                               withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        #expect(PreservedModData.relativeFiles(under: root, using: fm).isEmpty)
    }

    // MARK: - Le cas réel, bout à bout

    /// Le couple mesuré sur le parc : `FarmTypeManager/data/` porte les deux
    /// populations. La règle doit garder les sauvegardes et rendre la main sur
    /// le fichier livré.
    @Test("FarmTypeManager : les parties survivent, le modèle livré ne bloque pas")
    func farmTypeManagerCase() {
        let extras = PreservedModData.extraPaths(
            installed: ["FarmTypeManager.dll", "manifest.json", "data/default.json",
                        "data/essai_448486987.json", "data/essai_448486987_SaveData.save",
                        "data/test_443014860_SaveData.save"],
            shippedByArchive: ["FarmTypeManager.dll", "manifest.json", "data/default.json"],
            alreadyHandled: [])
        #expect(extras == ["data/essai_448486987.json",
                           "data/essai_448486987_SaveData.save",
                           "data/test_443014860_SaveData.save"])
    }
}
