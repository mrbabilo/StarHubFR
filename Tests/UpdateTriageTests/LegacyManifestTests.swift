import Foundation
import Testing
@testable import StarHubTHCore

/// A1-T11 plan 2 — le manifeste Nexus au format ancien : un arbre de chemins,
/// sans empreinte. Fixture réelle : ItemBags 3.1.0 (Nexus 5382), 31 fichiers.
struct LegacyManifestTests {
    private func itemBags() throws -> NexusLegacyFileManifest {
        try #require(NexusLegacyFileManifest.decode(Fixture.data("manifest-legacy-itembags-3.1.0.json")))
    }

    @Test func decodesEveryFileOfTheRealTree() throws {
        let manifest = try itemBags()
        #expect(manifest.paths.count == 31)
        #expect(manifest.paths.contains("ItemBags/ItemBags.dll"))
        #expect(!manifest.paths.contains("ItemBags/assets"))   // un dossier n'est pas un fichier
    }

    @Test func aNotFoundBodyOrHtmlIsNoManifest() {
        let notFound = #"{"code":"not_found","message":"File with such name does not exist.","status":404}"#
        #expect(NexusLegacyFileManifest.decode(Data(notFound.utf8)) == nil)
        #expect(NexusLegacyFileManifest.decode(Data("<html>404</html>".utf8)) == nil)
        #expect(NexusLegacyFileManifest.decode(Data(#"{"children":[]}"#.utf8)) == nil)
    }

    @Test func pathsAreBroughtBackToTheInstalledFolder() throws {
        let installed = Set(try Fixture.triageCase("itembags").installedListing.byKey.keys)
        let mapped = try #require(try itemBags().paths(matching: installed))
        #expect(mapped.contains("itembags.dll"))
        #expect(mapped.contains("manifest.json"))
        #expect(!mapped.contains { $0.hasPrefix("itembags/") })
        // L'auteur livre des échantillons sous « Samples (…) » ; les sacs de
        // l'utilisateur, posés à côté dans « Modded Bags/ », ne sont pas à lui.
        #expect(mapped.contains { $0.hasPrefix("assets/modded bags/samples") })
        #expect(!mapped.contains { $0.hasPrefix("assets/modded bags/") && !$0.contains("/samples") })
    }

    private func manifest(_ paths: [String]) -> NexusLegacyFileManifest {
        NexusLegacyFileManifest(paths: paths)
    }

    @Test func withoutAManifestRootItIsNotAnAuthorVersion() {
        // Un optionnel posé par-dessus le mod : pas de manifest.json.
        #expect(manifest(["Mod/textures/a.png"]).paths(matching: ["textures/a.png"]) == nil)
    }

    @Test func theBestMatchingRootWinsAndATieIsRefused() {
        let pack = manifest(["A/manifest.json", "A/a.png", "A/x.png",
                             "B/manifest.json", "B/b.png", "B/c.png"])
        #expect(pack.paths(matching: ["manifest.json", "b.png", "c.png"]) == ["manifest.json", "b.png", "c.png"])
        #expect(pack.paths(matching: ["manifest.json", "a.png", "b.png"]) == nil)   // A et B à égalité
        #expect(pack.paths(matching: ["other.png"]) == nil)                          // aucune concordance
    }

    @Test func aRootMatchedOnlyByItsManifestIsNotThisMod() {
        // Sans empreinte, manifest.json concorde avec toute racine : l'archive
        // d'un autre composant du pack ne doit pas passer pour ce mod.
        let other = manifest(["Other/manifest.json", "Other/content.json"])
        #expect(other.paths(matching: ["manifest.json", "mine.png"]) == nil)
    }

    @Test func aRootMatchedOnlyByContentPatcherBoilerplateIsNotThisMod() {
        // content.json et i18n/default.json sont dans presque tout pack Content
        // Patcher : un composant voisin ne concorde pas par eux.
        let other = manifest(["Other/manifest.json", "Other/content.json", "Other/i18n/default.json",
                              "Other/assets/x.png"])
        #expect(other.paths(matching: ["manifest.json", "content.json", "i18n/default.json", "mine.png"]) == nil)
        #expect(other.paths(matching: ["manifest.json", "content.json", "assets/x.png"]) != nil)
    }

    @Test func pathsCompareWithoutCase() {
        let m = manifest(["Mod/Manifest.json", "Mod/Assets/Old.PNG"])
        #expect(m.paths(matching: ["manifest.json", "assets/old.png"]) == ["manifest.json", "assets/old.png"])
    }
}
