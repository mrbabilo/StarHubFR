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

    // MARK: - Mise à l'abri et remise en place

    /// Un dossier de mod jetable, avec les fichiers demandés.
    private func makeFolder(_ files: [String]) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("pmd_\(UUID().uuidString)")
        for f in files {
            let url = root.appendingPathComponent(f)
            try fm.createDirectory(at: url.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try Data(f.utf8).write(to: url)
        }
        return root
    }

    @Test("Un extra survit à l'effacement du dossier et revient à sa place")
    func survivesTheFolderBeingReplaced() throws {
        let fm = FileManager.default
        let old = try makeFolder(["data/Zofia_1_SaveData.save"])
        var snaps = PreservedModData.snapshot(["data/Zofia_1_SaveData.save"],
                                              from: old, using: fm)
        #expect(snaps.count == 1)

        // Le vrai geste de l'installateur : l'ancien dossier disparaît.
        try fm.removeItem(at: old)
        let fresh = try makeFolder(["manifest.json"])
        defer { try? fm.removeItem(at: fresh) }

        let result = PreservedModData.restore(&snaps, into: fresh, using: fm)
        #expect(result.restored == 1)
        #expect(result.failed.isEmpty)
        #expect(snaps.isEmpty)   // le ménage de l'appelant n'a plus rien à balayer
        let back = fresh.appendingPathComponent("data/Zofia_1_SaveData.save")
        #expect(fm.fileExists(atPath: back.path))
        #expect(try String(contentsOf: back, encoding: .utf8) == "data/Zofia_1_SaveData.save")
    }

    /// A1-T7 (suite) — le bilan doit **nommer** ce qui a été remis, pas
    /// seulement le compter : « lesquelles » est la demande du joueur.
    @Test("La restauration rapporte les chemins remis, triés")
    func restoreReportsThePathsItPutBack() throws {
        let fm = FileManager.default
        let old = try makeFolder(["data/b.save", "data/a.save"])
        var snaps = PreservedModData.snapshot(["data/b.save", "data/a.save"],
                                              from: old, using: fm)
        try fm.removeItem(at: old)
        let fresh = try makeFolder(["manifest.json"])
        defer { try? fm.removeItem(at: fresh) }

        let result = PreservedModData.restore(&snaps, into: fresh, using: fm)
        #expect(result.restoredPaths == ["data/a.save", "data/b.save"])
    }

    /// Le choix de conception d'A1-T7 : un extra qu'on ne peut pas reposer ne
    /// fait **pas** avorter une mise à jour par ailleurs réussie — le dossier
    /// entier est déjà en sauvegarde. L'échec se compte, il ne se tait pas.
    @Test("Un extra irrécupérable est compté, pas fatal")
    func aFailedExtraIsCountedNotFatal() throws {
        let fm = FileManager.default
        let fresh = try makeFolder(["manifest.json"])
        defer { try? fm.removeItem(at: fresh) }

        // Un instantané qui pointe sur un fichier temporaire disparu.
        var snaps = ["data/perdu.save": fm.temporaryDirectory
            .appendingPathComponent("absent_\(UUID().uuidString)")]
        let result = PreservedModData.restore(&snaps, into: fresh, using: fm)

        #expect(result.restored == 0)
        #expect(result.failed == ["data/perdu.save"])
        #expect(snaps.count == 1)   // conservé : rien n'a été restauré
    }

    @Test("Mettre à l'abri un fichier absent n'invente pas d'entrée")
    func snapshotSkipsMissingFiles() throws {
        let fm = FileManager.default
        let folder = try makeFolder(["present.json"])
        defer { try? fm.removeItem(at: folder) }

        let snaps = PreservedModData.snapshot(["present.json", "absent.json"],
                                              from: folder, using: fm)
        #expect(Array(snaps.keys) == ["present.json"])
    }

    // MARK: - Ce qui est dit à l'utilisateur

    @Test("Une mise à jour ordinaire ne dit rien")
    func silentWhenNothingHappened() {
        #expect(PreservedModData.messages(restored: 0, failed: [], modFolder: "X").isEmpty)
    }

    @Test("Une préservation réussie se mentionne, sans alerte")
    func mentionsSuccess() {
        let m = PreservedModData.messages(restored: 3, failed: [], modFolder: "FarmTypeManager")
        #expect(m.count == 1)
        #expect(m[0].isFailure == false)
        #expect(m[0].text.contains("FarmTypeManager"))
        #expect(m[0].text.contains("3"))
    }

    /// Le cas critique : sans les noms, l'utilisateur ne sait pas quoi aller
    /// rechercher dans la sauvegarde d'installation.
    @Test("Un échec est une alerte, et il nomme les fichiers")
    func namesTheFailures() {
        let m = PreservedModData.messages(restored: 0, failed: ["data/a.save", "data/b.save"],
                                          modFolder: "FTM")
        #expect(m.count == 1)
        #expect(m[0].isFailure == true)
        #expect(m[0].text.contains("data/a.save"))
        #expect(m[0].text.contains("data/b.save"))
    }

    /// A1-T7 (suite) — le succès nomme aussi : « lesquelles » vaut pour les
    /// remises comme pour les échecs.
    @Test("Le succès nomme les fichiers remis, cinq au plus puis un compte")
    func namesTheRestoredPaths() {
        let m = PreservedModData.messages(
            restored: 2, failed: [],
            restoredPaths: ["data/a.save", "data/b.save"], modFolder: "FTM")
        #expect(m.count == 1)
        #expect(m[0].isFailure == false)
        #expect(m[0].text.contains("data/a.save"))
        #expect(m[0].text.contains("data/b.save"))

        let longs = (1...7).map { "data/f\($0).save" }
        let m2 = PreservedModData.messages(restored: 7, failed: [],
                                           restoredPaths: longs, modFolder: "FTM")
        #expect(m2[0].text.contains("data/f5.save"))
        #expect(m2[0].text.contains("2 autres"))
        #expect(!m2[0].text.contains("data/f6.save"))
    }

    /// L'option de non-remise (réglage global) : les données laissées dans
    /// la sauvegarde d'installation se disent, en alerte — l'utilisateur
    /// doit savoir où elles sont.
    @Test("Des données non remises par choix sont signalées avec leur chemin")
    func skippedDataIsAnnounced() {
        let m = PreservedModData.messages(restored: 0, failed: [], skipped: 2,
                                          modFolder: "FTM")
        #expect(m.count == 1)
        #expect(m[0].isFailure == true)
        #expect(m[0].text.contains("2"))
        #expect(m[0].text.contains("sauvegarde"))
    }

    // MARK: - A1-T7 (suite) — le réglage « remettre les données »

    /// Le piège du `bool(forKey:)` nu : absent = false, alors que la remise
    /// des données est le comportement **par défaut** de l'app.
    @Test("La clé absente vaut « remettre »")
    func missingKeyMeansRestore() {
        let d = UserDefaults(suiteName: "pmd_missing_\(UUID().uuidString)")!
        d.removeObject(forKey: UDKey.restoreModDataOnUpdate)
        #expect(PreservedModData.shouldRestore(defaults: d) == true)
    }

    @Test("La clé positionnée tranche", arguments: [false, true])
    func explicitKeyDecides(value: Bool) {
        let d = UserDefaults(suiteName: "pmd_set_\(UUID().uuidString)")!
        d.set(value, forKey: UDKey.restoreModDataOnUpdate)
        #expect(PreservedModData.shouldRestore(defaults: d) == value)
    }

    @Test("Au-delà de cinq échecs, le reste est compté")
    func abbreviatesLongFailureLists() {
        let files = (1...8).map { "data/f\($0).save" }
        let m = PreservedModData.messages(restored: 0, failed: files, modFolder: "FTM")
        #expect(m[0].text.contains("+3 autres"))
        #expect(!m[0].text.contains("data/f6.save"))
    }

    @Test("Succès et échec cohabitent en deux messages")
    func reportsBothOutcomes() {
        let m = PreservedModData.messages(restored: 2, failed: ["x.save"], modFolder: "M")
        #expect(m.count == 2)
        #expect(m.filter(\.isFailure).count == 1)
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
