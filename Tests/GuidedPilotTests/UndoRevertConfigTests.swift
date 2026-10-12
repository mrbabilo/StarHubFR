import Testing
import Foundation
@testable import StarHubTHCore

/// M7 — défaire le revert d'un réglage : même garde anti-écrasement que
/// l'éditeur de config, droits ouverts, et un `config.json` qui n'existait
/// pas avant le revert est retiré, pas laissé.
@Suite struct UndoRevertConfigTests {
    private struct Fixture {
        let configs: URL
        let target: URL
    }

    private func fixture(reverted: String = #"{"a":1}"#, onDisk: String? = #"{"a":1}"#) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-\(UUID().uuidString)", isDirectory: true)
        let configs = root.appendingPathComponent("configs", isDirectory: true)
        let mod = root.appendingPathComponent("Mods/M", isDirectory: true)
        try FileManager.default.createDirectory(at: configs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mod, withIntermediateDirectories: true)
        try reverted.write(to: configs.appendingPathComponent("abc123.json"), atomically: true, encoding: .utf8)
        let target = mod.appendingPathComponent("config.json")
        if let onDisk { try onDisk.write(to: target, atomically: true, encoding: .utf8) }
        return Fixture(configs: configs, target: target)
    }

    @Test func rewritesThePreviousText() throws {
        let f = try fixture()
        let outcome = ProbePerformanceActions.undoRevertConfig(
            at: f.target, previous: #"{"a":2}"#, revertedToSha: "abc123",
            configsDirectory: f.configs, gameRunning: false)
        #expect(outcome == .reverted)
        #expect(try String(contentsOf: f.target, encoding: .utf8) == #"{"a":2}"#)
    }

    @Test func removesAConfigThatDidNotExistBefore() throws {
        let f = try fixture()
        let outcome = ProbePerformanceActions.undoRevertConfig(
            at: f.target, previous: nil, revertedToSha: "abc123",
            configsDirectory: f.configs, gameRunning: false)
        #expect(outcome == .reverted)
        #expect(FileManager.default.fileExists(atPath: f.target.path) == false)
    }

    /// Le jeu ou l'utilisateur a réécrit le réglage depuis : on n'écrase pas.
    @Test func refusesWhenTheDiskChangedSinceTheRevert() throws {
        let f = try fixture(onDisk: #"{"a":9}"#)
        let outcome = ProbePerformanceActions.undoRevertConfig(
            at: f.target, previous: #"{"a":2}"#, revertedToSha: "abc123",
            configsDirectory: f.configs, gameRunning: false)
        #expect(outcome == .changedOnDisk)
        #expect(try String(contentsOf: f.target, encoding: .utf8) == #"{"a":9}"#)
    }

    @Test func refusesWithTheGameOpen() throws {
        let f = try fixture()
        #expect(ProbePerformanceActions.undoRevertConfig(
            at: f.target, previous: #"{"a":2}"#, revertedToSha: "abc123",
            configsDirectory: f.configs, gameRunning: true) == .gameRunning)
    }
}
