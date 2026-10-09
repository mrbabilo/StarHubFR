import Foundation
import Testing
@testable import StarHubTHCore

/// Le conteneur du lot multi-mods : un ZIP plat, un JSON de lot par mod,
/// fabriqué et relu par les outils du système — les mêmes binaires que
/// `ModZipInstaller` fait parler dans l'autre sens.
struct TranslationLotArchiveTests {

    /// Round-trip : ce qui entre ressort octet pour octet, sous le même nom.
    @Test func aRoundTripReturnsTheSameBytesUnderTheSameNames() throws {
        let files: [String: Data] = [
            "M1-fr-lot.json": Data("{\"mod\":\"M1\"}".utf8),
            "[CP]M2-fr-lot.json": Data("{\"mod\":\"[CP]M2\"}".utf8),
        ]
        let zip = try TranslationLotArchive.make(files: files)
        let extracted = try TranslationLotArchive.extract(zip)
        #expect(extracted == files)
    }

    /// Pas de JSON dans l'archive : pas de lot. Le reste (README, dossiers)
    /// est ignoré, pas une erreur — un traducteur peut avoir rangé ses notes
    /// à côté.
    @Test func onlyJsonEntriesComeBack() throws {
        let files: [String: Data] = [
            "M1-fr-lot.json": Data("{}".utf8),
            "notes.txt": Data("à moi".utf8),
        ]
        let zip = try TranslationLotArchive.make(files: files)
        let extracted = try TranslationLotArchive.extract(zip)
        #expect(Array(extracted.keys) == ["M1-fr-lot.json"])
    }

    /// Un archive vide ne se fabrique pas : `zip` échouerait sans entrée, et
    /// un lot « rien à traduire » doit rester un refus côté appelant.
    @Test func makingAnEmptyArchiveFails() {
        #expect(throws: (any Error).self) {
            try TranslationLotArchive.make(files: [:])
        }
    }

    /// Des octets qui ne sont pas un ZIP : refusé avant tout `unzip` — la
    /// signature, pas le nom, fait foi.
    @Test func nonZipBytesAreRefused() {
        #expect(throws: (any Error).self) {
            try TranslationLotArchive.extract(Data("not a zip".utf8))
        }
    }

    /// Un lien symbolique glissé dans le ZIP sous un nom en `.json` : `unzip`
    /// le recrée, et sa **cible** — n'importe quel fichier local — serait lue
    /// comme un lot. Seuls les fichiers ordinaires reviennent.
    @Test func aSymbolicLinkEntryIsNotFollowed() throws {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("lot-link-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let secret = work.appendingPathComponent("secret.txt")
        try Data("ne pas lire".utf8).write(to: secret)
        try Data("{}".utf8).write(to: work.appendingPathComponent("M1-fr-lot.json"))
        try FileManager.default.createSymbolicLink(at: work.appendingPathComponent("piege.json"),
                                                   withDestinationURL: secret)
        let zipURL = work.appendingPathComponent("lot.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = work
        zip.arguments = ["-q", "-y", zipURL.path, "M1-fr-lot.json", "piege.json"]
        try zip.run(); zip.waitUntilExit()
        #expect(zip.terminationStatus == 0)

        let extracted = try TranslationLotArchive.extract(try Data(contentsOf: zipURL))

        #expect(extracted.keys.sorted() == ["M1-fr-lot.json"])
    }
}
