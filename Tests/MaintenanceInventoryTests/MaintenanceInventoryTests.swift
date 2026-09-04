import Testing
import Foundation
@testable import StarHubTHCore

/// L'exigence qui contraint tout l'écran : une sauvegarde peut être la seule
/// copie d'un fichier écrit par l'utilisateur.
///
/// Mesuré sur le parc le 2026-09-04 : 160 des 923 sauvegardes portent un
/// `config.json` et 245 un `i18n/*.json`, mais **une seule** est irremplaçable —
/// `ZebrusWhereIsMyFish`, désinstallé, dont la sauvegarde du 2026-08-14 porte un
/// `config.json` de 258 octets réglé à la main (`"SearchHotkey": "D7"`).
struct MaintenanceProtectionTests {

    private func entry(_ files: [MaintenanceInventory.UserFile],
                       mod: String = "Zebrus") -> MaintenanceInventory.BackupEntry {
        MaintenanceInventory.BackupEntry(
            id: "2026-08-14_215231_X_install_backup",
            modFolder: mod,
            timestamp: Date(timeIntervalSince1970: 1_000),
            sizeBytes: 4_550,
            userFiles: files)
    }

    @Test func aConfigStillPresentInTheInstalledModIsNotASoleCopy() {
        let e = entry([.init(relativePath: "config.json", kind: .config)])
        let installed = MaintenanceInventory.InstalledState(presentFiles: ["config.json"])
        #expect(MaintenanceInventory.protection(of: e, installed: installed) == .none)
    }

    @Test func aConfigWhoseModIsGoneIsASoleCopy() {
        // Le cas réel du parc : le mod a été désinstallé, la sauvegarde porte
        // le seul exemplaire des réglages.
        let file = MaintenanceInventory.UserFile(relativePath: "config.json", kind: .config)
        let installed = MaintenanceInventory.InstalledState(presentFiles: nil)
        #expect(MaintenanceInventory.protection(of: entry([file]), installed: installed)
                == .soleCopy([file]))
    }

    @Test func aConfigThatVanishedFromAnInstalledModIsASoleCopy() {
        // Le mod vit encore mais la mise à jour a emporté le fichier.
        let file = MaintenanceInventory.UserFile(relativePath: "config.json", kind: .config)
        let installed = MaintenanceInventory.InstalledState(presentFiles: ["manifest.json"])
        #expect(MaintenanceInventory.protection(of: entry([file]), installed: installed)
                == .soleCopy([file]))
    }

    @Test func aBackupWithoutAnyUserFileIsNeverProtected() {
        let installed = MaintenanceInventory.InstalledState(presentFiles: nil)
        #expect(MaintenanceInventory.protection(of: entry([]), installed: installed) == .none)
    }

    @Test func onlyTheMissingFilesAreListed() {
        // Le voisin qui ne doit pas être compté : deux fichiers, un seul parti.
        let kept = MaintenanceInventory.UserFile(relativePath: "config.json", kind: .config)
        let lost = MaintenanceInventory.UserFile(relativePath: "i18n/fr.json", kind: .translation)
        let installed = MaintenanceInventory.InstalledState(presentFiles: ["config.json"])
        #expect(MaintenanceInventory.protection(of: entry([kept, lost]), installed: installed)
                == .soleCopy([lost]))
    }
}
