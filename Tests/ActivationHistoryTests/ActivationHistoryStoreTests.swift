import Testing
import Foundation
@testable import StarHubTHCore

/// R5 — la persistance de l'historique : jamais dans le vrai Application
/// Support (dossier injecté), et un fichier illisible n'est jamais écrasé —
/// les instantanés épinglés y vivent.
@MainActor
struct ActivationHistoryStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_417_600)

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationHistoryStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func mod(_ folder: String, enabled: Bool) -> ModItem {
        ModItem(uniqueId: folder.lowercased(), name: folder, folderName: folder, version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [])
    }

    @Test func aRecordedSnapshotSurvivesANewStore() {
        let dir = tempDir()
        let store = ActivationHistoryStore(directory: dir)
        store.record(.bulkEnable, detail: nil, mods: [mod("A", enabled: true)],
                     activeProfileId: nil, now: t0)
        let reread = ActivationHistoryStore(directory: dir)
        #expect(reread.snapshots.count == 1)
        #expect(reread.snapshots.first?.enabledFolders == ["A"])
    }

    @Test func pinningIsPersisted() {
        let dir = tempDir()
        let store = ActivationHistoryStore(directory: dir)
        store.record(.bulkEnable, detail: nil, mods: [mod("A", enabled: true)],
                     activeProfileId: nil, now: t0)
        let id = store.snapshots[0].id
        store.setPinned(id, true)
        #expect(ActivationHistoryStore(directory: dir).snapshots.first?.pinned == true)
    }

    @Test func anUnreadableFileIsSetAsideNotOverwritten() throws {
        let dir = tempDir()
        let file = dir.appendingPathComponent(ActivationHistoryStore.fileName)
        try Data("pas du json".utf8).write(to: file)
        let store = ActivationHistoryStore(directory: dir)
        #expect(store.snapshots.isEmpty)
        store.record(.bulkEnable, detail: nil, mods: [mod("A", enabled: true)],
                     activeProfileId: nil, now: t0)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let aside = names.filter { $0.hasPrefix("activation_history.unreadable") }
        try #require(aside.count == 1)
        #expect(try String(contentsOf: dir.appendingPathComponent(aside[0]), encoding: .utf8) == "pas du json")
    }

    @Test func withoutADirectoryNothingIsWrittenAndNothingCrashes() {
        let store = ActivationHistoryStore(directory: nil)
        store.record(.bulkEnable, detail: nil, mods: [mod("A", enabled: true)],
                     activeProfileId: nil, now: t0)
        #expect(store.snapshots.count == 1)
    }
}
