import Foundation
import Testing
@testable import StarHubTHCore

/// Ce que la page des sauvegardes montre : des mods, pas une liste plate.
/// Sur un parc réel, 1 494 sauvegardes s'y déversaient d'un bloc.
struct BackupBrowserTests {

    private func backup(_ folder: String, _ name: String, version: String = "1.0.0",
                        author: String = "Tester", daysAgo: Double = 0) -> ModInstallBackup {
        ModInstallBackup(
            timestamp: Date().addingTimeInterval(-daysAgo * 86400),
            originalFolderName: folder,
            backupPath: "/backups/\(folder)-\(version)-\(daysAgo)",
            modMetadata: ModMetadata(name: name, version: version, author: author,
                                     uniqueId: "id.\(folder)"),
            reason: .beforeUpdate)
    }

    /// Le regroupement se fait par **dossier**, comme la restauration : deux
    /// installations d'un même mod dans deux dossiers restent deux entrées.
    @Test func backupsAreGroupedByOriginFolder() {
        let groups = BackupBrowser.groups(from: [
            backup("SwimMod", "Swim", daysAgo: 1),
            backup("SwimMod", "Swim", version: "1.1.0"),
            backup("SwimMod-copie", "Swim"),
        ], search: "", sort: .mostRecent)
        #expect(groups.count == 2)
        #expect(groups.first { $0.id == "SwimMod" }?.backups.count == 2)
    }

    /// Par défaut, le mod touché le plus récemment vient en tête — c'est
    /// celui dont on vient de rater la mise à jour.
    @Test func groupsAreOrderedByTheirMostRecentBackup() {
        let groups = BackupBrowser.groups(from: [
            backup("Ancien", "Ancien", daysAgo: 30),
            backup("Frais", "Frais", daysAgo: 1),
        ], search: "", sort: .mostRecent)
        #expect(groups.map(\.id) == ["Frais", "Ancien"])
    }

    @Test func alphabeticalSortsRunBothWays() {
        let list = [backup("b", "Banane"), backup("a", "Abricot"), backup("c", "Cerise")]
        #expect(BackupBrowser.groups(from: list, search: "", sort: .nameAscending)
                    .map(\.displayName) == ["Abricot", "Banane", "Cerise"])
        #expect(BackupBrowser.groups(from: list, search: "", sort: .nameDescending)
                    .map(\.displayName) == ["Cerise", "Banane", "Abricot"])
    }

    /// Trier par nombre répond à « qu'est-ce qui occupe ma place ? ».
    @Test func countSortPutsTheMostBackedUpModFirst() {
        let groups = BackupBrowser.groups(from: [
            backup("Seul", "Seul"),
            backup("Nombreux", "Nombreux", daysAgo: 1),
            backup("Nombreux", "Nombreux", version: "1.1.0", daysAgo: 2),
            backup("Nombreux", "Nombreux", version: "1.2.0", daysAgo: 3),
        ], search: "", sort: .count)
        #expect(groups.map(\.id) == ["Nombreux", "Seul"])
    }

    @Test func theSearchLooksAtNameFolderAuthorAndVersion() {
        let list = [
            backup("SwimMod", "Swim Mod", version: "1.9.0", author: "Aedenthorn"),
            backup("Autre", "Autre chose", version: "2.0.0", author: "Quelquun"),
        ]
        for needle in ["swim", "SwimMod", "aedenthorn", "1.9"] {
            let groups = BackupBrowser.groups(from: list, search: needle, sort: .mostRecent)
            #expect(groups.count == 1, "« \(needle) » devrait ne trouver que Swim")
            #expect(groups.first?.id == "SwimMod")
        }
    }

    @Test func anEmptySearchKeepsEverything() {
        let list = [backup("a", "A"), backup("b", "B")]
        #expect(BackupBrowser.groups(from: list, search: "   ", sort: .mostRecent).count == 2)
    }

    /// Dans un mod, les sauvegardes se rangent par version, la plus
    /// récemment sauvegardée en tête. Une version sauvegardée deux fois ne
    /// fait qu'une section.
    @Test func versionsAreSubgroupedAndOrderedByRecency() {
        let group = BackupBrowser.groups(from: [
            backup("Mod", "Mod", version: "1.0.0", daysAgo: 10),
            backup("Mod", "Mod", version: "1.0.0", daysAgo: 9),
            backup("Mod", "Mod", version: "2.0.0", daysAgo: 1),
        ], search: "", sort: .mostRecent).first
        #expect(group?.versions.map(\.version) == ["2.0.0", "1.0.0"])
        #expect(group?.versions.last?.backups.count == 2)
    }

    /// Le nom affiché vient de la sauvegarde la plus récente : un mod
    /// renommé par son auteur doit apparaître sous son nom actuel.
    @Test func theDisplayNameFollowsTheMostRecentBackup() {
        let group = BackupBrowser.groups(from: [
            backup("Mod", "Ancien nom", daysAgo: 10),
            backup("Mod", "Nouveau nom", daysAgo: 1),
        ], search: "", sort: .mostRecent).first
        #expect(group?.displayName == "Nouveau nom")
    }
}
