import Testing
import Foundation
@testable import StarHubTHCore

/// I-T8 : le segment « Fichiers récupérables » montre aussi les seules copies
/// de l'Entretien — toutes les sessions, mods désinstallés compris — sans
/// répéter ce que le scanner de récupération liste déjà.
struct SoleCopyFilesTests {

    private func entry(_ session: String, mod: String, at seconds: TimeInterval)
    -> MaintenanceInventory.BackupEntry {
        MaintenanceInventory.BackupEntry(id: session, modFolder: mod,
                                         timestamp: Date(timeIntervalSince1970: seconds),
                                         sizeBytes: 1, userFiles: [])
    }

    private let config = MaintenanceInventory.UserFile(relativePath: "config.json", kind: .config)
    private let fr = MaintenanceInventory.UserFile(relativePath: "i18n/fr.json", kind: .translation)

    private func report(_ backups: [MaintenanceInventory.BackupEntry],
                        _ protections: [String: MaintenanceInventory.Protection],
                        missing: Set<String> = []) -> MaintenanceInventory.Report {
        MaintenanceInventory.Report(backups: backups, protections: protections,
                                    configBackupCount: 0, configBackupBytes: 0,
                                    orphanSessions: [], stalePreferenceKeys: [],
                                    missingMods: missing)
    }

    @Test func theMostRecentSessionWinsForTheSameFile() {
        // La plus récente d'abord : l'ordre de l'index ne doit pas décider.
        let r = report([entry("new", mod: "A", at: 2), entry("old", mod: "A", at: 1)],
                       ["old": .soleCopy([config]), "new": .soleCopy([config])])
        let files = MaintenanceInventory.soleCopyFiles(in: r, excluding: [])
        #expect(files.map(\.session) == ["new"])
    }

    @Test func anOlderSessionStillCountsForAFileTheNewerOneLacks() {
        // Le cas que le scanner (dernière sauvegarde seulement) ne voyait pas.
        let r = report([entry("old", mod: "A", at: 1), entry("new", mod: "A", at: 2)],
                       ["old": .soleCopy([config, fr]), "new": .soleCopy([config])])
        let files = MaintenanceInventory.soleCopyFiles(in: r, excluding: [])
        #expect(files.map(\.id) == ["A/config.json", "A/i18n/fr.json"])
        #expect(files.first { $0.relativePath == "i18n/fr.json" }?.session == "old")
    }

    @Test func aFileTheScannerAlreadyListsIsNotRepeated() {
        let r = report([entry("s", mod: "A", at: 1)], ["s": .soleCopy([config, fr])])
        let files = MaintenanceInventory.soleCopyFiles(in: r, excluding: ["A/config.json"])
        #expect(files.map(\.id) == ["A/i18n/fr.json"])
    }

    @Test func theSameFileOfAnotherModIsNotExcluded() {
        let r = report([entry("s", mod: "B", at: 1)], ["s": .soleCopy([config])])
        let files = MaintenanceInventory.soleCopyFiles(in: r, excluding: ["A/config.json"])
        #expect(files.map(\.id) == ["B/config.json"])
    }

    @Test func anUninstalledModIsFlaggedGone() {
        let r = report([entry("s", mod: "Zebrus", at: 1)], ["s": .soleCopy([config])],
                       missing: ["s"])
        #expect(MaintenanceInventory.soleCopyFiles(in: r, excluding: []).map(\.isGone) == [true])
    }

    @Test func anUnprotectedSessionListsNothing() {
        let r = report([entry("s", mod: "A", at: 1)], ["s": MaintenanceInventory.Protection.none])
        #expect(MaintenanceInventory.soleCopyFiles(in: r, excluding: []).isEmpty)
    }
}
