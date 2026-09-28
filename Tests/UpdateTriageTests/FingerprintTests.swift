import Foundation
import Testing
@testable import StarHubTHCore

struct FingerprintTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FingerprintTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, _ relative: String, in root: URL) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func keysIgnoreCaseSeparatorsAndUnicodeForm() {
        #expect(ModFilePath.key("Assets\\Items/Épée.png") == ModFilePath.key("assets/items/épée.png"))
        // « é » décomposé (NFD) dans le nom d'archive, composé sur le disque.
        #expect(ModFilePath.key("i18n/Re\u{0301}sume\u{0301}.json") == ModFilePath.key("i18n/Résumé.json"))
        #expect(ModFilePath.key("/manifest.json/") == "manifest.json")
    }

    @Test func translationsAndCodeAreRecognised() {
        #expect(ModFilePath.isTranslation("i18n/fr.json"))
        #expect(ModFilePath.isTranslation("sub/i18n/zh.json"))
        #expect(!ModFilePath.isTranslation("i18n/default.json"))
        #expect(!ModFilePath.isTranslation("i18n/en.json"))
        #expect(!ModFilePath.isTranslation("fr.json"))
        // Forme dossier de SMAPI 4 : une locale est un sous-dossier d'i18n.
        #expect(ModFilePath.isTranslation("i18n/fr/gui.json"))
        #expect(ModFilePath.isTranslation("[cp] x/i18n/zh/items.json"))
        #expect(!ModFilePath.isTranslation("i18n/default/gui.json"))
        #expect(!ModFilePath.isTranslation("i18n/en/gui.json"))
        #expect(!ModFilePath.isTranslation("i18n/fr/readme.txt"))
        #expect(ModFilePath.isCode("bin/release/net6.0/fotp.dll"))
        #expect(!ModFilePath.isCode("assets/dll.png"))
    }

    @Test func listingHashesFilesAndSkipsSystemJunk() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("abc", "assets/a.txt", in: root)
        try write("junk", ".DS_Store", in: root)
        try write("fork", "assets/._a.txt", in: root)
        let listing = ModFolderHasher.listing(of: root)
        #expect(listing.hashes.keys.sorted() == ["assets/a.txt"])
        // SHA-256 de « abc ».
        #expect(listing.hashes["assets/a.txt"]
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(listing.sizes["assets/a.txt"] == 3)
        #expect(listing.unreadable.isEmpty)
    }

    /// Le vrai manifeste Nexus de Wildroot 1.4.2 (fichier 184199), réduit à
    /// trois fichiers.
    @Test func decodesARecentNexusManifest() throws {
        let manifest = try #require(NexusFileManifest.decode(try Fixture.data("manifest-recent-sample.json")))
        #expect(manifest.archiveSHA256 == "20252d3391e1cdb607b129f9543931180e83c9cbe2a4840d581976b58d5bd137")
        #expect(manifest.files.count == 3)
        #expect(manifest.files["Cropgenics/Cropgenics.dll"]
                == "31d4673c342df23164a5c5b52212caf8e470d19ab1775299a074ac38aa886684")
    }

    @Test func aNon404PageIsNoManifest() {
        #expect(NexusFileManifest.decode(Data("<!doctype html><html></html>".utf8)) == nil)
        #expect(NexusFileManifest.decode(Data(#"{"version":1}"#.utf8)) == nil)
    }

    /// L'archive livre `Cropgenics/…` : la racine à `manifest.json` qui
    /// concorde le plus avec le dossier installé est retenue.
    @Test func archiveRootIsTheManifestFolderThatMatches() {
        let manifest = NexusFileManifest(archiveSHA256: nil, repackedSHA256: nil, files: [
            "Cropgenics/manifest.json": "m1", "Cropgenics/assets/a.png": "a1",
            "Other/manifest.json": "m2", "Other/assets/a.png": "zz",
        ])
        let files = manifest.files(matching: ["manifest.json": "m1", "assets/a.png": "a1"])
        #expect(files == ["manifest.json": "m1", "assets/a.png": "a1"])
    }

    /// Un optionnel posé par-dessus le mod (pas de `manifest.json`) n'est pas
    /// une version d'auteur : ses fichiers ne deviendront jamais des fantômes.
    @Test func anOverlayWithoutManifestIsNoVersion() {
        let overlay = NexusFileManifest(archiveSHA256: nil, repackedSHA256: nil, files: [
            "Alt Textures/assets/a.png": "a1",
        ])
        #expect(overlay.files(matching: ["assets/a.png": "a1"]) == nil)
    }

    @Test func tiedRootsGiveNothing() {
        let manifest = NexusFileManifest(archiveSHA256: nil, repackedSHA256: nil, files: [
            "A/manifest.json": "m", "B/manifest.json": "m",
        ])
        #expect(manifest.files(matching: ["manifest.json": "m"]) == nil)
    }
}
