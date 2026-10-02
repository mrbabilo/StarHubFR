import Foundation
import Testing
@testable import StarHubTHCore

/// La règle SMAPI (A1-T4, lue dans `ModScanner.cs`) : on ne descend que dans
/// un dossier **sans fichier pertinent** ; sinon le manifeste local fait le
/// mod, et rien en dessous. Mesuré sur le parc : 15 entrées fantômes que
/// SMAPI ne chargeait pas, une fois leurs parents activés.
@Suite struct ModFolderTraversalTests {

    private let fm = FileManager.default

    private func makeTree() throws -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ body: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    private let manifest = #"{"Name": "M", "UniqueID": "a.m", "Version": "1.0.0", "EntryDll": "m.dll"}"#

    private func names(_ root: URL) -> [String] {
        ModFolderTraversal.manifestURLs(under: root)
            .map { $0.deletingLastPathComponent().lastPathComponent }
            .sorted()
    }

    /// Un `examples/` sous un vrai mod (assets + manifeste) n'est pas un
    /// composant : SMAPI lit le parent, jamais les exemples.
    @Test func examplesUnderARealModAreInvisible() throws {
        let root = try makeTree()
        try write(manifest, to: root.appendingPathComponent("BushBloomMod/manifest.json"))
        try "assets".write(to: root.appendingPathComponent("BushBloomMod/content.json"), atomically: true, encoding: .utf8)
        try write(manifest, to: root.appendingPathComponent("BushBloomMod/examples/[BBM] Example/manifest.json"))
        try write(manifest, to: root.appendingPathComponent("BushBloomMod/examples/[CP] Advanced/manifest.json"))
        #expect(names(root) == ["BushBloomMod"])
    }

    /// Un dossier réduit à des sous-dossiers est exploré : les gabarits
    /// qu'il porte **sont** chargés par SMAPI, les montrer est juste.
    @Test func groupFolderRevealsEveryPack() throws {
        let root = try makeTree()
        try write(manifest, to: root.appendingPathComponent("IsekaiBonds/[Pack] A/manifest.json"))
        try write(manifest, to: root.appendingPathComponent("IsekaiBonds/character_packs/_ContentPackTemplate/manifest.json"))
        #expect(names(root) == ["[Pack] A", "_ContentPackTemplate"])
    }

    /// Le manifeste compte comme fichier pertinent : un dossier à
    /// manifeste n'est jamais un dossier de recherche — SMAPI le lit
    /// comme un mod et ignore ce qui est en dessous.
    @Test func manifestMakesTheFolderAMod() throws {
        let root = try makeTree()
        try write(manifest, to: root.appendingPathComponent("Bundle/manifest.json"))
        try write(manifest, to: root.appendingPathComponent("Bundle/[CP] Inner/manifest.json"))
        #expect(names(root) == ["Bundle"])
    }

    /// README, images et archives ne pèsent pas dans la décision (le
    /// dossier au README seul est exploré) ; un dossier à fichiers **sans**
    /// manifeste ne charge rien, même s'il a des sous-dossiers.
    @Test func readmeAloneStillSearchesAndFilesWithoutManifestLoadNothing() throws {
        let root = try makeTree()
        try fm.createDirectory(at: root.appendingPathComponent("WithReadme"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("WithContent"), withIntermediateDirectories: true)
        try "# doc".write(to: root.appendingPathComponent("WithReadme/README.md"), atomically: true, encoding: .utf8)
        try "preview".write(to: root.appendingPathComponent("WithReadme/preview.png"), atomically: true, encoding: .utf8)
        try write(manifest, to: root.appendingPathComponent("WithReadme/[CP] Pack/manifest.json"))
        try write(manifest, to: root.appendingPathComponent("WithContent/content.json"))
        try write(manifest, to: root.appendingPathComponent("WithContent/[CP] Inner/manifest.json"))
        #expect(names(root) == ["[CP] Pack"])
    }

    /// Les fichiers d'outils connus ne comptent pas davantage.
    @Test func toolMarkerFilesAreIgnored() throws {
        let root = try makeTree()
        try fm.createDirectory(at: root.appendingPathComponent("ByVortex"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("ByVortex/__folder_managed_by_vortex"))
        try write(manifest, to: root.appendingPathComponent("ByVortex/[CP] Pack/manifest.json"))
        #expect(names(root) == ["[CP] Pack"])
    }
}
