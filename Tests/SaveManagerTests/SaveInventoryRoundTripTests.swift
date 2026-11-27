import Foundation
import Testing
@testable import StarHubTHCore

/// **X157 — modifier l'inventaire ne doit rien effacer d'autre.**
///
/// `updateInventory` lisait la partie avec `XMLDocument(…, .documentTidyXML)`,
/// qui **supprime tout élément dont le nom commence par `_`** et resserre les
/// espaces des textes. Mesuré le 2026-11-26 sur une copie d'une vraie partie
/// (37,5 Mo) en repassant le sac sans rien changer : 101 éléments perdus —
/// `_questTitle`, `_questDescription` et `_currentObjective` de 33 quêtes,
/// `_plankPosition` et `_plankDirection` d'un lieu — et une lettre dont les
/// retours à la ligne étaient écrasés. Le fichier passait aussi de 36 à 90 Mo
/// (`.nodePrettyPrint`).
@Suite struct SaveInventoryRoundTripTests {
    private static let letter = "Quelqu'un peut m'en apporter ?\n                                - Michael"

    private func saveXML() -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>\
        <SaveGame xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
        <player><name>Jemila</name><money>100</money>\
        <items><Item xsi:type="Object"><name>Parsnip</name><itemId>24</itemId><stack>3</stack></Item>\
        <Item xsi:nil="true" /></items>\
        <questLog><Quest><_currentObjective>Livres reçus : 4 sur 12</_currentObjective>\
        <_questDescription>Retrouve les pages perdues.</_questDescription>\
        <_questTitle>La Quête de la Mystérieuse Dame</_questTitle><id>Q1</id></Quest></questLog>\
        <mailbox><string>\(Self.letter)</string></mailbox></player>\
        <locations><GameLocation><_plankPosition>3</_plankPosition></GameLocation></locations>\
        </SaveGame>
        """
    }

    private func makeSave(in env: TestEnvironment) throws -> SaveGameInfo {
        let name = "Inventaire_1"
        let folderURL = env.savesDir.appendingPathComponent(name, isDirectory: true)
        let fileURL = folderURL.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data(saveXML().utf8).write(to: fileURL)
        return makeTestSave(folderName: name, fileURL: fileURL)
    }

    private func text(of url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test func unchangedInventoryKeepsUnderscoreElements() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(in: env)
        let manager = SaveManager()

        let items = try #require(manager.fetchContents(for: info)?.inventory)
        #expect(manager.updateInventory(info: info, items: items))

        let written = text(of: info.fileURL)
        #expect(written.contains("<_questTitle>La Quête de la Mystérieuse Dame</_questTitle>"))
        #expect(written.contains("<_questDescription>Retrouve les pages perdues.</_questDescription>"))
        #expect(written.contains("<_currentObjective>Livres reçus : 4 sur 12</_currentObjective>"))
        #expect(written.contains("<_plankPosition>3</_plankPosition>"))
    }

    @Test func unchangedInventoryKeepsTextWhitespace() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(in: env)
        let manager = SaveManager()

        let items = try #require(manager.fetchContents(for: info)?.inventory)
        #expect(manager.updateInventory(info: info, items: items))

        let reread = try XMLDocument(contentsOf: info.fileURL, options: [.nodePreserveAll])
        let strings = try reread.nodes(forXPath: "//mailbox/string").map { $0.stringValue ?? "" }
        #expect(strings == [Self.letter])
    }

    @Test func editedStackIsWrittenAndFileIsNotReindented() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(in: env)
        let before = try Data(contentsOf: info.fileURL).count
        let manager = SaveManager()

        var items = try #require(manager.fetchContents(for: info)?.inventory)
        items[0] = InventoryItem(slotIndex: 0, itemId: "24", name: "Parsnip", stack: 7, isObject: true)
        #expect(manager.updateInventory(info: info, items: items))

        #expect(manager.fetchContents(for: info)?.inventory.first?.stack == 7)
        // Pas de réindentation : la taille reste celle de l'original, à la
        // déclaration XML près.
        let after = try Data(contentsOf: info.fileURL).count
        #expect(after < before + 64)
    }
}
