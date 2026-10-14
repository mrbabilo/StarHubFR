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

    /// Revue finale, point 4 : présent mais illisible n'est pas absent.
    @Test func aFileThatCannotBeReadIsNeverOverwritten() throws {
        let d = dir()
        let file = d.appendingPathComponent("mod_groups.json")
        try Data(#"{"groups":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Vieux"}]}"#.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? [] {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                       ofItemAtPath: d.appendingPathComponent(name).path)
            }
        }
        let store = ModGroupStore(directory: d, log: { _ in })
        store.update { _ = $0.createGroup(named: "A") }
        let names = try FileManager.default.contentsOfDirectory(atPath: d.path)
        for name in names {
            try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                  ofItemAtPath: d.appendingPathComponent(name).path)
        }
        let kept = names.contains { name in
            (try? String(contentsOf: d.appendingPathComponent(name), encoding: .utf8))?.contains("Vieux") == true
        }
        #expect(kept)
    }

    /// Revue finale, point 3 : un format plus récent reste en place, intact,
    /// pour la version qui l'a écrit.
    @Test func aFileFromAFutureVersionStaysInPlaceUntouched() throws {
        let d = dir()
        let file = d.appendingPathComponent("mod_groups.json")
        let future = #"{"version":2,"groups":[],"membership":{},"collapsedCategories":[],"colors":{"x":1}}"#
        try Data(future.utf8).write(to: file)
        var logged: [String] = []
        let store = ModGroupStore(directory: d, log: { logged.append($0) })
        #expect(!store.canPersist)
        #expect(logged.count == 1)
        store.update { _ = $0.createGroup(named: "A") }
        #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self) == future)
        #expect(try FileManager.default.contentsOfDirectory(atPath: d.path) == ["mod_groups.json"])
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
