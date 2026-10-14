import Foundation
import Testing
@testable import StarHubTHCore

@Suite @MainActor struct ModGroupStoreTests {
    private func dir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("groups-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func roundTrip() throws {
        let d = dir()
        let store = ModGroupStore(directory: d)
        store.update { state in
            if case .success(let id) = state.createGroup(named: "PNJ") { state.assign(["SVE"], to: id) }
        }
        let again = ModGroupStore(directory: d)
        #expect(again.state.group(of: "SVE")?.name == "PNJ")
        #expect(again.canPersist)
    }

    /// Review Focus 4 : jamais écrasé, mis de côté, signalé.
    @Test func anUnreadableFileIsSetAsideNeverOverwritten() throws {
        let d = dir()
        let file = d.appendingPathComponent("mod_groups.json")
        try Data("{ tronqué".utf8).write(to: file)
        var logged: [String] = []
        let store = ModGroupStore(directory: d, log: { logged.append($0) })
        #expect(store.state == ModGroupsState())
        let aside = try FileManager.default.contentsOfDirectory(atPath: d.path)
            .filter { $0.hasPrefix("mod_groups.json.unreadable-") }
        #expect(aside.count == 1)
        #expect(logged.count == 1)
        store.update { _ = $0.createGroup(named: "A") }
        let kept = try Data(contentsOf: d.appendingPathComponent(aside[0]))
        #expect(String(decoding: kept, as: UTF8.self) == "{ tronqué")
    }

    @Test func noDirectoryMeansNothingWritten() {
        let store = ModGroupStore(directory: nil)
        store.update { _ = $0.createGroup(named: "A") }
        #expect(store.state.groups.count == 1)
    }

    @Test func anUnreadableFileThatCannotMoveIsNeverWritten() throws {
        let d = dir()
        let file = d.appendingPathComponent("mod_groups.json")
        try Data("{ tronqué".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: d.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d.path) }
        let store = ModGroupStore(directory: d)
        // Écrire n'échouerait pas toujours (autre volume, autres droits) : le
        // magasin doit se savoir non inscriptible, pas compter sur l'échec.
        #expect(!store.canPersist)
        store.update { _ = $0.createGroup(named: "A") }
        #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self) == "{ tronqué")
    }
}
