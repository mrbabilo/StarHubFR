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

    private func pack(_ folder: String, id: String, requires: String, enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: id, name: folder, folderName: folder, version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [ModDependency(uniqueId: requires, isRequired: true)], languages: [])
    }
    private var contentPatcher: ModItem { mod("ContentPatcher", id: "Pathoschild.ContentPatcher") }
    private var svePack: ModItem { pack("SVE CP", id: "FlashShifter.StardewValleyExpandedCP", requires: "Pathoschild.ContentPatcher") }
    private var ridgesideGroup: ModItem {
        var group = mod("RidgesideVillage", id: "", children: [
            mod("Ridgeside Village", id: "Rafseazz.RidgesideVillage"),
            mod("Ridgeside Village (CP)", id: "Rafseazz.RSVCP"),
            mod("Ridgeside Village (TMXL)", id: "Rafseazz.RSVTMXL"),
        ])
        group.isGroup = true
        return group
    }

    /// D5-B — pas de mise en pause d'un mod dont d'autres dépendent ; les
    /// frères du pack de tête partent avec lui.
    @Test func frameworkWithDependentsHasNoGesture() {
        let blockers = ProbePerformanceActions.pauseBlockers(modId: "Pathoschild.ContentPatcher", in: [contentPatcher, svePack])
        #expect(blockers.dependents == [svePack.name])
    }

    @Test func packComponentNamesItsSiblings() {
        let blockers = ProbePerformanceActions.pauseBlockers(modId: "Rafseazz.RSVCP", in: [ridgesideGroup])
        #expect(blockers.dependents.isEmpty)
        #expect(blockers.siblings == ["Ridgeside Village", "Ridgeside Village (TMXL)"])
    }

    @Test func disabledDependentDoesNotBlock() {
        let paused = pack("SVE CP", id: "FlashShifter.StardewValleyExpandedCP",
                          requires: "Pathoschild.ContentPatcher", enabled: false)
        #expect(ProbePerformanceActions.pauseBlockers(modId: "Pathoschild.ContentPatcher", in: [contentPatcher, paused]).dependents.isEmpty)
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

    /// X134 : le réglage d'un composant de pack vit dans le dossier du
    /// composant — 78 packs du parc en portent un. Le revert écrivait à la
    /// racine du pack, annonçait `.reverted`, et le composant restait inchangé.
    @Test func packComponentRevertWritesTheComponentConfig() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("perf-pack-\(UUID().uuidString)")
        let game = root.appendingPathComponent("game")
        let component = game.appendingPathComponent("Mods/.Cape Stardew 1.6/Cape Stardew", isDirectory: true)
        let configs = root.appendingPathComponent("configs", isDirectory: true)
        try FileManager.default.createDirectory(at: component, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configs, withIntermediateDirectories: true)
        try "{\"A\":false}".write(to: component.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "{\"A\":true}".write(to: configs.appendingPathComponent("abc123.json"), atomically: true, encoding: .utf8)
        // Pack en pause : le point vit sur l'entrée de tête.
        var head = mod("Cape Stardew 1.6", id: "", enabled: false,
                       children: [mod("Cape Stardew 1.6/Cape Stardew", id: "Cape.Stardew", enabled: false)])
        head.isGroup = true
        let owner = try #require(ProbePerformanceActions.configOwner(modId: "cape.stardew", in: [head]))
        #expect(owner.folderName == "Cape Stardew 1.6/Cape Stardew")
        #expect(ProbePerformanceActions.configURL(of: owner, gameDir: game.path)?.resolvingSymlinksInPath()
                == component.appendingPathComponent("config.json").resolvingSymlinksInPath())
        let outcome = ProbePerformanceActions.revertConfig(
            of: owner, toSha: "abc123", configsDirectory: configs, gameDir: game.path, gameRunning: false,
            backups: ModConfigBackupManager(backupsBasePath: root.appendingPathComponent("backups")))
        #expect(outcome == .reverted)
        #expect(try String(contentsOf: component.appendingPathComponent("config.json"), encoding: .utf8) == "{\"A\":true}")
        #expect(!FileManager.default.fileExists(atPath: game.appendingPathComponent("Mods/.Cape Stardew 1.6/config.json").path))
        // Un mod à plat se résout sur lui-même.
        let flat = mod("Radiance", id: "phuicmt.SDVRadiance")
        #expect(ProbePerformanceActions.configOwner(modId: "phuicmt.SDVRadiance", in: [flat, head])?.folderName == "Radiance")
    }
}
