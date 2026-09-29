import Testing
import Foundation
@testable import StarHubTHCore

struct ProbePerformanceActionsTests {
    private func mod(_ folder: String, id: String, enabled: Bool = true,
                     children: [ModItem]? = nil) -> ModItem {
        var item = ModItem(uniqueId: id, name: folder, folderName: folder, version: "1.0",
                           author: "", description: "", nexusUrl: "", nexusModId: "",
                           isEnabled: enabled, dependencies: [], languages: [])
        item.children = children
        return item
    }

    /// Review Focus 5 — un composant vise son pack (le point de pause vit sur
    /// l'entrée de tête) ; un mod absent ne vise rien.
    @Test func targetIsTheTopLevelEntry() {
        let pack = mod("SVE", id: "", children: [mod("SVE/CP", id: "FlashShifter.SVECode")])
        let mods = [pack, mod("UltraSmooth", id: "palmhacker13.UltraSmooth")]
        #expect(ProbePerformanceActions.target(modId: "flashshifter.svecode", in: mods)?.folderName == "SVE")
        #expect(ProbePerformanceActions.target(modId: "palmhacker13.UltraSmooth", in: mods)?.folderName
                == "UltraSmooth")
        #expect(ProbePerformanceActions.target(modId: "Gone.Mod", in: mods) == nil)
    }

    private func sandbox() throws -> (game: URL, configs: URL, backups: ModConfigBackupManager) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf-revert-\(UUID().uuidString)", isDirectory: true)
        let modDir = root.appendingPathComponent("game/Mods/Radiance", isDirectory: true)
        let configs = root.appendingPathComponent("configs", isDirectory: true)
        try FileManager.default.createDirectory(at: modDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configs, withIntermediateDirectories: true)
        try "{\"Bloom\":false}".write(to: modDir.appendingPathComponent("config.json"),
                                      atomically: true, encoding: .utf8)
        try "{\"Bloom\":true}".write(to: configs.appendingPathComponent("abc123.json"),
                                     atomically: true, encoding: .utf8)
        return (root.appendingPathComponent("game"), configs,
                ModConfigBackupManager(backupsBasePath: root.appendingPathComponent("backups")))
    }

    @Test func revertWritesTheOldContentAfterABackup() throws {
        let box = try sandbox()
        let outcome = ProbePerformanceActions.revertConfig(
            of: mod("Radiance", id: "phuicmt.SDVRadiance"), toSha: "abc123",
            configsDirectory: box.configs, gameDir: box.game.path, gameRunning: false, backups: box.backups)
        #expect(outcome == .reverted)
        let written = try String(contentsOf: box.game.appendingPathComponent("Mods/Radiance/config.json"),
                                 encoding: .utf8)
        #expect(written == "{\"Bloom\":true}")
    }

    @Test func revertRefusesWhileTheGameRunsAndWithoutContent() throws {
        let box = try sandbox()
        let radiance = mod("Radiance", id: "phuicmt.SDVRadiance")
        #expect(ProbePerformanceActions.revertConfig(of: radiance, toSha: "abc123", configsDirectory: box.configs,
                                                     gameDir: box.game.path, gameRunning: true,
                                                     backups: box.backups) == .gameRunning)
        #expect(ProbePerformanceActions.revertConfig(of: radiance, toSha: "ffff", configsDirectory: box.configs,
                                                     gameDir: box.game.path, gameRunning: false,
                                                     backups: box.backups) == .contentMissing)
        #expect(ProbePerformanceActions.revertConfig(of: radiance, toSha: "../x", configsDirectory: box.configs,
                                                     gameDir: box.game.path, gameRunning: false,
                                                     backups: box.backups) == .contentMissing)
        let untouched = try String(contentsOf: box.game.appendingPathComponent("Mods/Radiance/config.json"),
                                   encoding: .utf8)
        #expect(untouched == "{\"Bloom\":false}")
    }
}
