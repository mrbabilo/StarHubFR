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
}
