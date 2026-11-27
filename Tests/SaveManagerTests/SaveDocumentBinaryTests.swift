import Compression
import Foundation
import Testing
@testable import StarHubTHCore

/// **B6-T2 — éditer une partie dont la version vraie est dans le `.bin`.**
///
/// Refusées par X138 jusqu'ici : XML réduit à un talon au coucher, ou XML plus
/// ancien que le `.bin` (copie différée). La partie est lue dans le `.bin`,
/// écrite en XML complet, et les `.bin` écartés — l'app n'en écrit jamais.
@Suite struct SaveDocumentBinaryTests {
    private let stub = Data("<!-- PureBinarySave -->\n<PureBinarySave active=\"true\"/>".utf8)
    private let padding = String(repeating: "<item />", count: 80)

    private func save(money: Int) -> String {
        "<?xml version=\"1.0\" encoding=\"utf-8\"?><SaveGame xmlns:xsi=\"x\"><player><name>Zofia</name>"
            + "<money>\(money)</money></player><locations>\(padding)</locations></SaveGame>"
    }

    private func info(money: Int) -> String {
        "<?xml version=\"1.0\" encoding=\"utf-8\"?><Farmer><name>Zofia</name><money>\(money)</money>\(padding)</Farmer>"
    }

    /// Le format relevé sur le parc : 28 octets d'en-tête, puis du Brotli.
    private func packed(_ text: String) -> Data {
        let source = [UInt8](text.utf8)
        var body = [UInt8](repeating: 0, count: source.count + 1024)
        let written = compression_encode_buffer(&body, body.count, source, source.count, nil, COMPRESSION_BROTLI)
        func bytes<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        return Data("PPBS".utf8) + bytes(UInt16(1)) + bytes(UInt16(0)) + bytes(UInt32(source.count))
            + bytes(UInt32(written)) + bytes(UInt32(0)) + bytes(UInt64(0)) + Data(body[0..<written])
    }

    private struct Files {
        let main: URL
        var folder: URL { main.deletingLastPathComponent() }
        func url(_ name: String) -> URL { folder.appendingPathComponent(name) }
        func text(_ name: String) -> String { (try? String(contentsOf: url(name), encoding: .utf8)) ?? "" }
        func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: url(name).path) }
    }

    private func files(_ env: TestEnvironment, main: Data, bin: Data?, info infoXML: Data?, infoBin: Data?) throws -> Files {
        let saveInfo = try env.makeSave(named: "Ferme_1")
        let files = Files(main: saveInfo.fileURL)
        try main.write(to: files.main)
        if let bin { try bin.write(to: files.url("Ferme_1.bin")) }
        if let infoXML { try infoXML.write(to: files.url("SaveGameInfo")) }
        if let infoBin { try infoBin.write(to: files.url("SaveGameInfo.bin")) }
        return files
    }

    /// Écarter = supprimer ici : pas de Corbeille pendant les tests.
    private func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }

    @Test func aStubIsEditedThroughItsBinAndWrittenAsAFullXML() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let f = try files(env, main: stub, bin: packed(save(money: 700)),
                          info: stub, infoBin: packed(info(money: 700)))

        let doc = try SaveDocument(contentsOf: f.main)
        #expect(doc.fromBinary)
        #expect(doc.player?.elements(forName: "money").first?.stringValue == "700")
        doc.setFarmerField("money", to: "900")
        try doc.write(backup: { true }, setAside: remove)

        #expect(f.text("Ferme_1").contains("<money>900</money>"))
        #expect(PureBinarySave.isCompleteSave(try Data(contentsOf: f.main)))
        #expect(!f.exists("Ferme_1.bin") && !f.exists("SaveGameInfo.bin"))
        // L'écran de chargement garde sa partie : `SaveGameInfo` recopié du `.bin`.
        #expect(f.text("SaveGameInfo").contains("<money>700</money>"))
    }

    @Test func aBinNewerThanACompleteXMLIsTheOneEdited() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let f = try files(env, main: Data(save(money: 100).utf8), bin: packed(save(money: 5000)),
                          info: nil, infoBin: nil)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)],
                                              ofItemAtPath: f.main.path)

        let doc = try SaveDocument(contentsOf: f.main)
        #expect(doc.fromBinary)
        #expect(doc.player?.elements(forName: "money").first?.stringValue == "5000")
        #expect(PureBinarySave.readableText(of: f.main)?.contains("<money>5000</money>") == true)
    }

    @Test func anUpToDateXMLIsStillReadAsIs() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let f = try files(env, main: Data(save(money: 100).utf8), bin: packed(save(money: 5000)),
                          info: nil, infoBin: nil)

        let doc = try SaveDocument(contentsOf: f.main)
        #expect(!doc.fromBinary)
        #expect(doc.player?.elements(forName: "money").first?.stringValue == "100")
    }

    @Test func anUnreadableBinKeepsTheX138Refusal() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let f = try files(env, main: stub, bin: Data("PPBS".utf8), info: nil, infoBin: nil)

        let doc = try SaveDocument(contentsOf: f.main)
        #expect(!doc.fromBinary)
        #expect(throws: SaveDocument.Failure.binaryOnly(PureBinarySave.refusalStubKey)) {
            try doc.write(backup: { true }, setAside: remove)
        }
        #expect(try Data(contentsOf: f.main) == stub)
    }

    /// Sans `SaveGameInfo` lisible, le jeu ne proposerait plus la partie au
    /// chargement : rien n'est écrit.
    @Test func aLostLoadScreenStopsTheWrite() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let f = try files(env, main: stub, bin: packed(save(money: 700)),
                          info: stub, infoBin: Data("PPBS".utf8))

        let doc = try SaveDocument(contentsOf: f.main)
        #expect(throws: SaveDocument.Failure.writeFailed) { try doc.write(backup: { true }, setAside: remove) }
        #expect(try Data(contentsOf: f.main) == stub)
        #expect(f.exists("Ferme_1.bin"))
    }

    @Test func aBinRewrittenSinceOpeningIsNeverOverwritten() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let f = try files(env, main: stub, bin: packed(save(money: 700)), info: nil, infoBin: nil)
        let doc = try SaveDocument(contentsOf: f.main)
        try packed(save(money: 800)).write(to: f.url("Ferme_1.bin"))   // le jeu a sauvegardé

        #expect(throws: SaveDocument.Failure.changedOnDisk) { try doc.write(backup: { true }, setAside: remove) }
        #expect(try Data(contentsOf: f.main) == stub)
    }
}
