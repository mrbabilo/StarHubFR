import Testing
import Foundation
@testable import StarHubTHCore

/// Extension de R1 — une sauvegarde de configuration n'est la seule copie
/// que de ce que le dossier Mods n'a plus, mod en pause compris.
@Suite("ConfigBackupSoleCopy")
struct ConfigBackupSoleCopyTests {
    private func backup(_ items: [(String, [String])]) -> ModConfigBackup {
        ModConfigBackup(timestamp: Date(), items: items.map {
            ModConfigBackupItem(modFolderName: $0.0, parentFolderName: nil, modDisplayName: $0.0,
                                files: $0.1, fileSizes: [:])
        }, totalFiles: 0, totalSize: 0, folderName: "b")
    }

    @Test func onlyWhatTheModsFolderNoLongerHasIsASoleCopy() {
        let disk: Set<String> = ["Active/config.json", ".Paused/config.json", "Group/.Child/config.json"]
        let b = backup([("Active", ["config.json"]), ("Paused", ["config.json"]),
                        ("Gone", ["config.json", "i18n/fr.json"])])
        #expect(ConfigBackupSoleCopy.files(in: b, exists: disk.contains)
                == ["Gone/config.json", "Gone/i18n/fr.json"])
    }

    @Test func aBackupOfInstalledModsGuardsNothing() {
        let b = backup([("Active", ["config.json"])])
        #expect(ConfigBackupSoleCopy.files(in: b, exists: { _ in true }).isEmpty)
    }
}
