import Testing
import Foundation
@testable import StarHubTHCore

/// Restaurer des `config.json` jeu ouvert : un mod chargé réécrit le sien à
/// son prochain enregistrement (menu de réglages, MLD's Keybind, GMCM) et
/// défait la restauration. Un mod en pause n'est pas chargé.
struct ConfigRestoreWhileRunningTests {
    private func mod(_ folder: String, enabled: Bool) -> ModItem {
        ModItem(uniqueId: "a.\(folder)", name: "Nom \(folder)", folderName: folder, version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [], languages: [])
    }

    private func item(_ folder: String) -> ModConfigBackupItem {
        ModConfigBackupItem(modFolderName: folder, parentFolderName: nil, modDisplayName: "Nom \(folder)",
                            files: ["config.json"], fileSizes: [:])
    }

    @Test func namesOnlyActiveModsWhileTheGameRuns() {
        let mods = [mod("A", enabled: true), mod("B", enabled: false), mod("C", enabled: true)]
        let items = [item("A"), item("B"), item("D")]
        #expect(ConfigRestoreWhileRunning.activeNames(items, mods: mods, gameRunning: true) == ["Nom A"])
        #expect(ConfigRestoreWhileRunning.activeNames(items, mods: mods, gameRunning: false).isEmpty)
    }
}
