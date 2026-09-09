import Testing
import Foundation
@testable import StarHubTHCore

struct AppSupportMigrationTests {
    /// **Le chemin destructeur.** `installed_translations.json` stocke des
    /// chemins **absolus** vers les sauvegardes de dépôt. Déplacer le dossier
    /// sans les réécrire ferait supprimer le fichier déposé au lieu de rendre
    /// l'original — `ManifestlessInstaller.uninstall` supprime quand la
    /// sauvegarde est introuvable.
    @Test func absolutePathsAreRewritten() throws {
        let old = "/Users/x/Library/Application Support/StarHubTH"
        let new = "/Users/x/Library/Application Support/StarHubFR"
        let json = Data("""
        {"byHost":{},"addonsByHost":{"ItemBags":[{"hostFolderName":"ItemBags",
        "nexusModId":48157,"nexusName":"Config","version":"1","installedAt":1,
        "files":["bagconfig.json"],
        "replacedFiles":{"bagconfig.json":"\(old)/TranslationBackups/ItemBags/a/bagconfig.json"}}]}}
        """.utf8)
        let rewritten = try #require(AppSupportMigration.rewrite(json, from: old, to: new))
        let text = String(decoding: rewritten, as: UTF8.self)
        #expect(text.contains("\(new)/TranslationBackups"))
        #expect(!text.contains("Support/StarHubTH/"))
    }

    /// Un JSON sans aucun chemin de l'ancien dossier n'est pas réécrit : rendre
    /// `nil` évite de réécrire 617 Ko pour rien.
    @Test func aFileWithNothingToRewriteIsLeftAlone() {
        let json = Data(#"{"byHost":{},"addonsByHost":{}}"#.utf8)
        #expect(AppSupportMigration.rewrite(json, from: "/a/StarHubTH", to: "/a/StarHubFR") == nil)
        #expect(!AppSupportMigration.needsRewrite(json, oldRoot: "/a/StarHubTH"))
    }

    /// **Ne réécrire que la racine.** Un mod nommé « StarHubTH » dans le dossier
    /// `Mods/` ne doit pas voir son chemin changer.
    @Test func onlyTheRootIsRewritten() throws {
        let old = "/Users/x/Library/Application Support/StarHubTH"
        let json = Data("""
        {"a":"\(old)/TranslationBackups/x","b":"/Applications/Game/Mods/StarHubTH/y"}
        """.utf8)
        let text = String(decoding: try #require(
            AppSupportMigration.rewrite(json, from: old, to: "/Users/x/Library/Application Support/StarHubFR")),
            as: UTF8.self)
        #expect(text.contains("/Applications/Game/Mods/StarHubTH/y"))
    }

    /// Un JSON illisible n'est pas réécrit à l'aveugle : mieux vaut ne rien
    /// faire que produire un fichier corrompu.
    @Test func unreadableDataIsRefused() {
        let bytes = Data([0xFF, 0xFE, 0x00])
        #expect(AppSupportMigration.rewrite(bytes, from: "/a", to: "/b") == nil)
    }

    // MARK: - Le déplacement réel

    private func makeLegacy(_ fm: FileManager) throws -> (root: URL, old: URL, new: URL) {
        let root = fm.temporaryDirectory.appendingPathComponent("as-\(UUID().uuidString)")
        let old = root.appendingPathComponent("StarHubTH")
        let new = root.appendingPathComponent("StarHubFR")
        try fm.createDirectory(at: old.appendingPathComponent("TranslationBackups/ItemBags/a"),
                               withIntermediateDirectories: true)
        try Data("sauvegarde".utf8)
            .write(to: old.appendingPathComponent("TranslationBackups/ItemBags/a/bagconfig.json"))
        try Data("""
        {"byHost":{},"addonsByHost":{"ItemBags":[{"hostFolderName":"ItemBags",
        "nexusModId":48157,"nexusName":"C","version":"1","installedAt":1,
        "files":["bagconfig.json"],"replacedFiles":{"bagconfig.json":
        "\(old.path)/TranslationBackups/ItemBags/a/bagconfig.json"}}]}}
        """.utf8).write(to: old.appendingPathComponent("installed_translations.json"))
        return (root, old, new)
    }

    /// Le cas nominal : le dossier passe, et le chemin stocké **suit**.
    @Test func theFolderMovesAndTheStoredPathFollows() throws {
        let fm = FileManager.default
        let g = try makeLegacy(fm)
        defer { try? fm.removeItem(at: g.root) }

        #expect(AppSupport.migrate(from: g.old, to: g.new, fileManager: fm))
        #expect(!fm.fileExists(atPath: g.old.path))
        let moved = g.new.appendingPathComponent("TranslationBackups/ItemBags/a/bagconfig.json")
        #expect(fm.fileExists(atPath: moved.path))
        let text = try String(contentsOf: g.new.appendingPathComponent("installed_translations.json"),
                              encoding: .utf8)
        #expect(text.contains(g.new.path))
        #expect(!text.contains(g.old.path))
    }

    /// **Rien à migrer n'est pas un échec.** Une installation neuve n'a pas
    /// d'ancien dossier ; la migration doit passer sans bruit.
    @Test func nothingToMigrateSucceedsQuietly() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("as-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        #expect(AppSupport.migrate(from: root.appendingPathComponent("StarHubTH"),
                                   to: root.appendingPathComponent("StarHubFR"),
                                   fileManager: fm))
    }

    /// **Ce qui est déjà arrivé n'est jamais écrasé** — l'utilisateur a lancé
    /// une version migrée, puis une ancienne qui a réécrit dans l'ancien
    /// dossier. La donnée en place est la plus récente.
    @Test func anythingAlreadyMovedIsNeverOverwritten() throws {
        let fm = FileManager.default
        let g = try makeLegacy(fm)
        defer { try? fm.removeItem(at: g.root) }
        try fm.createDirectory(at: g.new, withIntermediateDirectories: true)
        try Data("récent".utf8).write(to: g.new.appendingPathComponent("installed_translations.json"))

        #expect(AppSupport.migrate(from: g.old, to: g.new, fileManager: fm))
        #expect(try String(contentsOf: g.new.appendingPathComponent("installed_translations.json"),
                           encoding: .utf8) == "récent")
        // Le reste a bien suivi, lui.
        #expect(fm.fileExists(atPath: g.new
            .appendingPathComponent("TranslationBackups/ItemBags/a/bagconfig.json").path))
    }

    /// **La migration est reprenable.** Un échec en cours de route ne doit pas
    /// figer un état à moitié migré : un second passage finit le travail.
    @Test func aSecondPassFinishesTheJob() throws {
        let fm = FileManager.default
        let g = try makeLegacy(fm)
        defer { try? fm.removeItem(at: g.root) }
        // Premier passage partiel simulé : le registre est déjà arrivé.
        try fm.createDirectory(at: g.new, withIntermediateDirectories: true)
        try fm.moveItem(at: g.old.appendingPathComponent("installed_translations.json"),
                        to: g.new.appendingPathComponent("installed_translations.json"))

        #expect(AppSupport.migrate(from: g.old, to: g.new, fileManager: fm))
        #expect(fm.fileExists(atPath: g.new
            .appendingPathComponent("TranslationBackups/ItemBags/a/bagconfig.json").path))
        #expect(!fm.fileExists(atPath: g.old.path))
    }

    /// **La réécriture d'abord, le déplacement ensuite.** Un dossier déplacé
    /// dont le JSON n'aurait pas été réécrit détruirait des fichiers au premier
    /// retrait de greffe : la migration doit échouer sans avoir rien bougé.
    @Test func aFailedRewriteLeavesTheFolderWhereItWas() throws {
        let fm = FileManager.default
        let g = try makeLegacy(fm)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: g.old.path)
            try? fm.removeItem(at: g.root)
        }
        // Registre illisible en écriture : la réécriture ne peut pas aboutir.
        let registry = g.old.appendingPathComponent("installed_translations.json")
        try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: registry.path)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: g.old.path)

        #expect(!AppSupport.migrate(from: g.old, to: g.new, fileManager: fm))
        #expect(fm.fileExists(atPath: g.old.path))
        #expect(!fm.fileExists(atPath: g.new.path))
    }
}
