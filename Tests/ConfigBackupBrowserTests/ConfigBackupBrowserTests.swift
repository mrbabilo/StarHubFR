import Foundation
import Testing
@testable import StarHubTHCore

private func item(_ folder: String, name: String? = nil, parent: String? = nil) -> ModConfigBackupItem {
    ModConfigBackupItem(modFolderName: folder, parentFolderName: parent, modDisplayName: name ?? folder,
                        files: ["config.json"], fileSizes: [:])
}

private func backup(_ day: Int, _ items: [ModConfigBackupItem]) -> ModConfigBackup {
    ModConfigBackup(timestamp: Date(timeIntervalSince1970: TimeInterval(day) * 86_400), items: items,
                    totalFiles: items.count, totalSize: 0, folderName: "b\(day)")
}

@Suite struct ConfigBackupBrowserTests {

    /// Une sauvegarde complète et deux ciblées : un groupe par mod, ses
    /// versions de la plus récente à la plus ancienne, les mods par nom.
    @Test func groupsByModNewestVersionFirst() {
        let backups = [backup(1, [item("Wallet"), item("Better")]), backup(3, [item("Wallet")]),
                       backup(2, [item("Wallet")])]
        let groups = ConfigBackupBrowser.groups(from: backups, search: "")
        #expect(groups.map(\.folderName) == ["Better", "Wallet"])
        #expect(groups[1].versions.map(\.backup.folderName) == ["b3", "b2", "b1"])
    }

    /// Le nom affiché est celui de la version la plus récente.
    @Test func displayNameFollowsTheNewestVersion() {
        let backups = [backup(1, [item("W", name: "Old name")]), backup(2, [item("W", name: "New name")])]
        #expect(ConfigBackupBrowser.groups(from: backups, search: "").first?.displayName == "New name")
    }

    /// La recherche lit le nom, le dossier et le pack parent, sans casse ni accents.
    @Test func searchMatchesNameFolderAndParentPack() {
        let backups = [backup(1, [item("FTM", name: "Forgotten Woods", parent: "[CP] Forêt"),
                                  item("Wallet", name: "(TM) Wallet Tools"), item("Other")])]
        #expect(ConfigBackupBrowser.groups(from: backups, search: "wallet").map(\.folderName) == ["Wallet"])
        #expect(ConfigBackupBrowser.groups(from: backups, search: "foret").map(\.folderName) == ["FTM"])
        #expect(ConfigBackupBrowser.groups(from: backups, search: "  ").count == 3)
    }
}

/// La comparaison montrée avant de restaurer une version.
@Suite struct ConfigBackupComparisonTests {
    @Test func reportsWhatDiffersFromTheCurrentFile() {
        let outcome = ConfigBackupComparison.compare(backup: #"{"Volume": 5, "Key": "F8"}"#,
                                                     current: #"{"Volume": 7, "Key": "F8"}"#)
        guard case .differs(let diffs) = outcome else { Issue.record("attendu .differs, reçu \(outcome)"); return }
        #expect(diffs.map(\.path) == ["Volume"])
        #expect(diffs.first?.valueA == "5")
    }

    @Test func identicalMissingAndUnparseableAreNamed() {
        #expect(ConfigBackupComparison.compare(backup: #"{"A": 1}"#, current: #"{"A": 1}"#) == .identical)
        #expect(ConfigBackupComparison.compare(backup: #"{"A": 1}"#, current: nil) == .missing)
        #expect(ConfigBackupComparison.compare(backup: "{oups", current: #"{"A": 1}"#) == .unparseable)
    }
}

/// Une restauration de réglages ne rend que `config.json`, jamais les i18n.
@Suite struct ConfigOnlyRestoreTests {
    @Test func narrowsToConfigJsonAndDropsTranslationOnlyItems() throws {
        let full = ModConfigBackupItem(modFolderName: "M", parentFolderName: "P", modDisplayName: "Mod",
                                       files: ["config.json", "i18n/fr.json", "i18n/default.json"],
                                       fileSizes: ["config.json": 10, "i18n/fr.json": 20])
        let narrowed = try #require(full.configOnly)
        #expect(narrowed.files == ["config.json"])
        #expect(narrowed.fileSizes == ["config.json": 10])
        #expect(narrowed.modFolderName == "M" && narrowed.parentFolderName == "P")
        let translationsOnly = ModConfigBackupItem(modFolderName: "T", parentFolderName: nil, modDisplayName: "T",
                                                   files: ["i18n/fr.json"], fileSizes: [:])
        #expect(translationsOnly.configOnly == nil)
    }
}
