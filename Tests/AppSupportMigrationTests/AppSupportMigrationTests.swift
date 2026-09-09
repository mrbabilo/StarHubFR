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
}
