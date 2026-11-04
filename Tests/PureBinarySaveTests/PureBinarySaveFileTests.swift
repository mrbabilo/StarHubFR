import Compression
import Foundation
import Testing
@testable import StarHubTHCore

/// X138, suite — ce que l'app sait lire dans les `.bin` de PureBinarySave :
/// la partie pendant la fenêtre du talon, et le jour de jeu qu'ils portent.
struct PureBinarySaveFileTests {
    private let stub = Data("<!-- PureBinarySave -->\n<PureBinarySave active=\"true\"/>".utf8)

    private func xml(_ root: String) -> String {
        "<?xml version=\"1.0\"?>\n<\(root) xmlns:xsi=\"x\">" + String(repeating: "<item />", count: 80) + "</\(root)>"
    }

    private func farmer(year: Int = 1, season: Int = 0, day: Int) -> String {
        "<?xml version=\"1.0\"?><Farmer><name>Zofia</name><dayOfMonthForSaveGame>\(day)</dayOfMonthForSaveGame>"
            + "<seasonForSaveGame>\(season)</seasonForSaveGame><yearForSaveGame>\(year)</yearForSaveGame></Farmer>"
    }

    /// Le format relevé sur le parc : 28 octets d'en-tête, puis du Brotli.
    private func packed(_ text: String, declaredSize: Int? = nil) -> Data {
        let source = [UInt8](text.utf8)
        var body = [UInt8](repeating: 0, count: source.count + 1024)
        let written = compression_encode_buffer(&body, body.count, source, source.count, nil, COMPRESSION_BROTLI)
        func bytes<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        return Data("PPBS".utf8) + bytes(UInt16(1)) + bytes(UInt16(0))
            + bytes(UInt32(declaredSize ?? source.count)) + bytes(UInt32(written))
            + bytes(UInt32(0)) + bytes(UInt64(0)) + Data(body[0..<written])
    }

    private func folder(main: Data, bin: Data? = nil, info: String? = nil, infoBin: String? = nil) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("Ferme_1")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try main.write(to: folder.appendingPathComponent("Ferme_1"))
        if let bin { try bin.write(to: folder.appendingPathComponent("Ferme_1.bin")) }
        if let info { try Data(info.utf8).write(to: folder.appendingPathComponent("SaveGameInfo")) }
        if let infoBin { try packed(infoBin).write(to: folder.appendingPathComponent("SaveGameInfo.bin")) }
        return folder.appendingPathComponent("Ferme_1")
    }

    private func mod(enabled: Bool) -> ModItem {
        ModItem(uniqueId: "palmhacker13.PureBinarySave", name: "PureBinarySave", folderName: "PureBinarySave",
                version: "1.0.10", author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [], languages: [])
    }

    @Test func aBinFileIsDecoded() {
        #expect(PureBinarySave.decoded(packed("<SaveGame />")) == Data("<SaveGame />".utf8))
    }

    @Test func anUnreadableBinFileIsRefused() {
        let good = packed("<SaveGame />")
        #expect(PureBinarySave.decoded(Data("PPBS".utf8)) == nil)
        #expect(PureBinarySave.decoded(Data("XXXX".utf8) + good.dropFirst(4)) == nil)
        #expect(PureBinarySave.decoded(good.dropLast(4)) == nil)
        #expect(PureBinarySave.decoded(packed("<SaveGame />", declaredSize: 4)) == nil)
        #expect(PureBinarySave.decoded(packed("<SaveGame />", declaredSize: Int(UInt32.max))) == nil)
    }

    /// Pendant la fenêtre du talon, la page Parties lit la partie du `.bin`.
    @Test func aStubIsReadThroughItsBinFile() throws {
        let main = try folder(main: stub, bin: packed(xml("SaveGame")))
        #expect(PureBinarySave.readableText(of: main) == xml("SaveGame"))
    }

    @Test func aCompleteSaveIsReadAsIs() throws {
        let main = try folder(main: Data(xml("SaveGame").utf8), bin: packed("<other />"))
        #expect(PureBinarySave.readableText(of: main) == xml("SaveGame"))
    }

    @Test func aStubWithoutAReadableBinStaysAStub() throws {
        let text = String(decoding: stub, as: UTF8.self)
        #expect(PureBinarySave.readableText(of: try folder(main: stub)) == text)
        #expect(PureBinarySave.readableText(of: try folder(main: stub, bin: Data("PPBS".utf8))) == text)
    }

    /// Des jours joués sans le mod : le XML avance, le `.bin` reste.
    @Test func aBinBehindTheSaveIsCountedInGameDays() throws {
        let main = try folder(main: Data(xml("SaveGame").utf8), bin: packed("x"),
                              info: farmer(year: 2, season: 1, day: 3), infoBin: farmer(day: 5))
        #expect(PureBinarySave.daysBehind(main) == 112 + 28 + 3 - 5)
    }

    @Test func aBinLevelWithOrAheadOfTheSaveIsNotBehind() throws {
        let level = try folder(main: Data(xml("SaveGame").utf8), bin: packed("x"),
                               info: farmer(day: 5), infoBin: farmer(day: 5))
        #expect(PureBinarySave.daysBehind(level) == nil)
        let ahead = try folder(main: stub, bin: packed("x"), info: farmer(day: 5), infoBin: farmer(day: 6))
        #expect(PureBinarySave.daysBehind(ahead) == nil)
    }

    @Test func withoutTheFilesToCompareNothingIsBehind() throws {
        let noBin = try folder(main: Data(xml("SaveGame").utf8), info: farmer(day: 9), infoBin: farmer(day: 5))
        #expect(PureBinarySave.daysBehind(noBin) == nil)
        let noDate = try folder(main: Data(xml("SaveGame").utf8), bin: packed("x"),
                                info: "<Farmer />", infoBin: farmer(day: 5))
        #expect(PureBinarySave.daysBehind(noDate) == nil)
    }

    private func staleSave() throws -> [PureBinarySave.StaleSave] {
        let main = try folder(main: Data(xml("SaveGame").utf8), bin: packed("x"),
                              info: farmer(day: 9), infoBin: farmer(day: 5))
        return PureBinarySave.staleSaves([(name: "Zofia", url: main)])
    }

    @Test func aPausedModWarnsBeforeItIsTurnedBackOn() throws {
        let stale = try staleSave()
        let issues = PureBinarySave.issues([mod(enabled: false)], stale: stale, { $0 })
        #expect(issues.map(\.severity) == [.warning])
        #expect(issues.first?.title == PureBinarySave.staleTitlePausedKey)
        #expect(issues.first?.actions == [.setAsideStaleBinaries(saves: stale.map(\.path))])
    }

    @Test func anActiveModIsCriticalItLoadsTheOldBinNext() throws {
        let issues = PureBinarySave.issues([mod(enabled: true)], stale: try staleSave(), { $0 })
        #expect(issues.map(\.severity) == [.critical])
        #expect(issues.first?.title == PureBinarySave.staleTitleActiveKey)
    }

    /// Sans le mod, un `.bin` oublié ne sera jamais relu.
    @Test func withoutTheModAnOldBinIsHarmless() throws {
        #expect(PureBinarySave.issues([], stale: try staleSave(), { $0 }).isEmpty)
    }

    /// Le geste relit la partie : le jeu a pu tourner depuis l'alerte.
    @Test func settingAsideChecksTheSaveAgain() throws {
        let stale = try folder(main: Data(xml("SaveGame").utf8), bin: packed("x"),
                               info: farmer(day: 9), infoBin: farmer(day: 5))
        let level = try folder(main: Data(xml("SaveGame").utf8), bin: packed("x"),
                               info: farmer(day: 9), infoBin: farmer(day: 9))
        var removed: [String] = []
        PureBinarySave.setAsideStale([stale.path, level.path]) { url in
            removed.append(url.deletingLastPathComponent().path + "/" + url.lastPathComponent)
            try FileManager.default.removeItem(at: url)
        }
        #expect(Set(removed) == [stale.path + ".bin",
                                 stale.deletingLastPathComponent().appendingPathComponent("SaveGameInfo.bin").path])
        #expect(FileManager.default.fileExists(atPath: level.path + ".bin"))
    }

    @Test func aStubRefusalSaysSo() throws {
        let main = try folder(main: stub, bin: packed("x"))
        #expect(PureBinarySave.refusalKey(for: main) == PureBinarySave.refusalStubKey)
    }

    @Test func aNewerBinRefusalSaysSo() throws {
        let main = try folder(main: Data(xml("SaveGame").utf8), bin: packed("x"))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: main.path)
        #expect(PureBinarySave.refusalKey(for: main) == PureBinarySave.refusalNewerKey)
    }

    @Test func anEditableSaveHasNoRefusal() throws {
        #expect(PureBinarySave.refusalKey(for: try folder(main: stub)) == nil)
    }

    /// Une copie renomme la partie : les `.bin` et caches à l'ancien nom ne
    /// serviraient plus, et `SaveGameInfo.bin` ramènerait l'ancien nom.
    @Test func aCopyDropsTheBinariesOfTheOriginal() throws {
        let main = try folder(main: Data(xml("SaveGame").utf8), bin: packed("x"), info: "x", infoBin: "x")
        let dir = main.deletingLastPathComponent()
        for name in ["Ferme_1.bin.bak", "Ferme_1.fr.assets.bin", "SaveGameInfo.bin.bak", "Ferme_1_old"] {
            try Data("x".utf8).write(to: dir.appendingPathComponent(name))
        }
        PureBinarySave.dropBinaries(named: "Ferme_1", in: dir)
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(Set(left) == ["Ferme_1", "Ferme_1_old", "SaveGameInfo"])
    }
}
