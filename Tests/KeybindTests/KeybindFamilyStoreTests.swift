import Testing
import Foundation
@testable import StarHubTHCore

@MainActor
struct KeybindFamilyStoreTests {
    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kfs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func roundTripAndReload() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KeybindFamilyStore(directory: dir)
        store.set(.info, for: "UIInfoSuite2Alt")
        let second = KeybindFamilyStore(directory: dir)
        #expect(second.families["UIInfoSuite2Alt"] == .info)
    }

    @Test func unreadableFileIsSetAsideNeverOverwritten() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(KeybindFamilyStore.fileName)
        try Data("pas du json".utf8).write(to: url)
        let store = KeybindFamilyStore(directory: dir)
        #expect(store.families.isEmpty)
        #expect(store.canPersist)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(siblings.contains { $0.contains("unreadable") })
        store.set(.rare, for: "Z")
        let reloaded = KeybindFamilyStore(directory: dir)
        #expect(reloaded.families["Z"] == .rare)
    }

    @Test func futureVersionIsReadOnlyAndUntouched() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(KeybindFamilyStore.fileName)
        let original = Data(#"{"version": 99, "families": {"X": "info"}}"#.utf8)
        try original.write(to: url)
        let store = KeybindFamilyStore(directory: dir)
        #expect(store.canPersist == false)
        #expect(store.families.isEmpty)
        store.set(.rare, for: "Y")
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func nilRemovesTheChoiceAndPersists() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KeybindFamilyStore(directory: dir)
        store.set(.action, for: "Swim")
        store.set(nil, for: "Swim")
        #expect(store.families["Swim"] == nil)
        #expect(KeybindFamilyStore(directory: dir).families["Swim"] == nil)
    }

    @Test func nilDirectoryWorksInMemory() {
        let store = KeybindFamilyStore(directory: nil)
        #expect(store.canPersist == false)
        store.set(.info, for: "A")
        #expect(store.families["A"] == .info)
    }
}
