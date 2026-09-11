import Testing
import Foundation
@testable import StarHubTHCore

/// L'état de l'écran « Entretien » : l'inventaire, la réparation, la
/// quarantaine, la corbeille — et le témoin de construction.
///
/// Les calculs sont prouvés ailleurs (`MaintenanceInventoryTests`,
/// `ModFolderRepairerTests`, `ModTrashTests`, `DisabledModsCleanupTests`) ;
/// ici, c'est l'état et ses deux gardes : le verrou de construction, et la
/// distinction entre « pas encore construit » et « rien à faire ».
@Suite struct MaintenanceStoreTests {

    /// Le rapport minimal que `MaintenanceInventory.Report.init` accepte —
    /// tous ses champs sont obligatoires, et le test ne juge que la publication.
    private func inventoryReport() -> MaintenanceInventory.Report {
        .init(backups: [], protections: [:], configBackupCount: 0,
              configBackupBytes: 0, orphanSessions: [], stalePreferenceKeys: [])
    }

    // MARK: - « Pas encore construit » n'est pas « rien à faire »

    @Test func aNewStoreHasBuiltNothingYet() {
        #expect(MaintenanceStore().report == nil)
    }

    @Test func anEmptyReportMeansNothingToDo_andIsPublished() {
        let s = MaintenanceStore()
        // Un rapport vide est une **réponse** — « tout est propre » — pas
        // l'absence de réponse. Le stocker doit se voir.
        s.setReport(inventoryReport())
        #expect(s.report != nil)
    }

    // MARK: - Le verrou de construction

    @Test func theFirstBuildTakesTheLock() {
        let s = MaintenanceStore()
        #expect(s.beginBuilding() == true)
        #expect(s.isBuilding)
    }

    @Test func aSecondBuildIsRefusedWhileTheFirstRuns() {
        let s = MaintenanceStore()
        _ = s.beginBuilding()
        #expect(s.beginBuilding() == false)
        #expect(s.isBuilding)
        s.endBuilding()
        #expect(s.isBuilding == false)
        #expect(s.beginBuilding() == true)
    }

    // MARK: - La réparation

    /// Seule une réparation **qui a tourné** a le droit d'écrire ici : sans
    /// quoi un scan sans réparation effacerait le rapport que l'utilisateur
    /// n'a pas fini de lire.
    @Test func aRepairReportIsStoredAndCleared() {
        let s = MaintenanceStore()
        s.setRepairReport(.init())   // tous champs par défaut
        #expect(s.lastRepairReport != nil)
        s.setRepairReport(nil)
        #expect(s.lastRepairReport == nil)
    }

    // MARK: - La quarantaine

    @Test func quarantineMessagesCarryTheirOwnSeverity() {
        let s = MaintenanceStore()
        s.setQuarantineMessage(QuarantineMessage(text: "vidée", isError: false))
        #expect(s.quarantineMessage == QuarantineMessage(text: "vidée", isError: false))
        s.setQuarantineMessage(QuarantineMessage(text: "raté", isError: true))
        #expect(s.quarantineMessage?.isError == true)
    }

    // MARK: - La corbeille

    /// Lu à la demande — l'ouverture de l'écran, un geste de remise ou de
    /// purge — pas un état que le scan entretient : un remplacement en bloc,
    /// jamais une fusion.
    @Test func trashEventsReplaceInBulk() {
        let s = MaintenanceStore()
        s.setTrashEvents([event("A"), event("B")])
        s.setTrashEvents([event("C")])
        // Le remplacement est en bloc : l'événement d'avant a disparu, pas
        // fusionné — la corbeille est relue du disque à chaque demande.
        #expect(s.trashEvents.map(\.folderName) == ["C"])
    }

    /// `Event` n'a pas d'init public — `@testable` le rend accessible, et
    /// le test ne construit que ce que `ModTrash.events` produit lui-même.
    private func event(_ folder: String) -> ModTrash.Event {
        .init(folderName: folder, date: nil, entries: [])
    }
}
