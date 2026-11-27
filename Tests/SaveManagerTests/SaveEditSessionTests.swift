import Foundation
import Testing
@testable import StarHubTHCore

/// **A0 — une session d'édition, une lecture.** L'état d'édition d'une partie
/// (formulaire, sac, note) vit dans `SaveEditSession`, gardée par
/// `NavigationStore` : changer de segment ne le perd pas, ouvrir une autre
/// partie en repart à neuf. Le sac et sa référence viennent de la **même**
/// lecture que l'empreinte qui garde l'écriture.
@Suite @MainActor struct SaveEditSessionTests {
    private let xml = """
        <?xml version="1.0" encoding="utf-8"?><SaveGame xmlns:xsi="x"><player><name>Jemila</name>\
        <money>100</money><items><Item xsi:type="Object"><name>Parsnip</name><itemId>24</itemId>\
        <stack>3</stack></Item></items></player></SaveGame>
        """

    /// Les lectures demandées au store, et leur remise, gardées pour les rendre à la main.
    /// Classe, pas variable capturée : la fermeture du chargeur est `@Sendable`.
    private final class ReadSpy: @unchecked Sendable {
        var dones: [(id: String, done: @MainActor @Sendable (SaveContents?) -> Void)] = []
        var loader: SaveContents.Loader { { [self] asked, done in dones.append((asked.id, done)) } }
    }

    private func save(_ folder: String) -> SaveGameInfo {
        makeTestSave(folderName: "A0_\(folder)_\(UUID().uuidString)", fileURL: URL(fileURLWithPath: "/tmp/\(folder)"))
    }

    nonisolated private static func contents() -> SaveContents {
        SaveContents(inventory: [InventoryItem(slotIndex: 0, itemId: "24", name: "Parsnip", stack: 3, isObject: true),
                                 InventoryItem.empty(slot: 1)],
                     stamp: SaveDocument.Stamp(of: Data("x".utf8)))
    }

    @Test func aSessionCountsFieldsSlotsAndNotes() {
        let session = SaveEditSession(save: save("count"), notes: SaveNotesStore())
        #expect(session.changeCount == 0)
        // Sac pas encore lu : rien à écrire pour lui.
        #expect(session.pendingEdits().items == nil)
        session.load(Self.contents())
        // Référence = la lecture elle-même : rien de modifié à l'arrivée.
        #expect(session.changeCount == 0)
        #expect(session.pendingEdits().sheet == nil && session.pendingEdits().items == nil)

        session.draft.money = "4321"
        session.inventory[0].stack = 9
        session.noteText = "à revoir"
        #expect(session.changeCount == 3)
        // Accepté : une case vidée compte 1, même une case déjà vide
        // (`InventoryItem.empty` porte un nouvel `UUID`).
        session.inventory[1] = InventoryItem.empty(slot: 1)
        #expect(session.changeCount == 4)

        let edits = session.pendingEdits()
        #expect(edits.sheet?.money == 4321)
        #expect(edits.items?.first?.stack == 9)
    }

    @Test func switchingSegmentsKeepsTheEdits() {
        let reads = ReadSpy()
        let navigation = NavigationStore(loadContents: reads.loader)
        navigation.setEditingSave(save("segments"))
        reads.dones.first?.done(Self.contents())
        let session = navigation.editSession
        session?.draft.money = "1"
        session?.inventory[0].stack = 4
        navigation.saveSegment = .history
        navigation.saveSegment = .details
        #expect(navigation.editSession === session)
        #expect(navigation.editSession?.changeCount == 2)
    }

    @Test func aSecondSaveOpenedDropsTheFirstSession() {
        let reads = ReadSpy()
        let navigation = NavigationStore(loadContents: reads.loader)
        let first = save("first"), second = save("second")
        navigation.setEditingSave(first)
        navigation.editSession?.draft.money = "1"
        navigation.setEditingSave(second)
        #expect(navigation.editingSave?.id == second.id)
        #expect(navigation.editSession?.changeCount == 0)
        // La lecture de la première, arrivée en retard, n'atterrit pas.
        reads.dones.first { $0.id == first.id }?.done(Self.contents())
        #expect(navigation.editSession?.loaded == nil)
        #expect(navigation.editSession?.inventory.isEmpty == true)
    }

    @Test func expectedStampIsAskedOnlyForBagEditsWithoutConfirmedOverwrite() {
        let session = SaveEditSession(save: save("stamp"), notes: SaveNotesStore())
        session.load(Self.contents())
        #expect(session.expectedStamp(overwriteNewer: false) == nil)
        session.inventory[0].stack = 9
        #expect(session.expectedStamp(overwriteNewer: false) == session.loaded?.stamp)
        #expect(session.expectedStamp(overwriteNewer: true) == nil)
    }

    @Test func theStampComesFromTheSameReadAsTheContents() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try env.makeSave(named: "A0_Stamp", content: xml)
        let manager = SaveManager(isGameRunning: { false })
        var contents = try #require(manager.fetchContents(for: info))
        #expect(contents.stamp == SaveDocument.Stamp.current(of: info.fileURL))
        #expect(contents.inventory.first?.stack == 3)

        // Une partie plus récente posée après la lecture : l'écriture du sac
        // lu refuse, l'empreinte retenue est celle de cette lecture.
        let newer = xml.replacingOccurrences(of: "<money>100</money>", with: "<money>5000</money>")
        try Data(newer.utf8).write(to: info.fileURL)
        #expect(contents.stamp != SaveDocument.Stamp.current(of: info.fileURL))
        contents.inventory[0].stack = 9
        #expect(throws: SaveDocument.Failure.changedOnDisk) {
            try manager.writeEdits(info: info, sheet: nil, items: contents.inventory, expected: contents.stamp)
        }
    }
}
