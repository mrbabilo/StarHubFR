import Foundation
import Observation

/// L'état de l'écran « Entretien » : l'inventaire, le dernier rapport de
/// réparation, le message de quarantaine, et les événements de corbeille.
///
/// Les calculs sont en Core et testés (`MaintenanceInventory`,
/// `ModFolderRepairer`, `ModTrash`, `DisabledModsCleanup`) ; ce store ne
/// porte que l'état — et deux gardes que le ViewModel tenait par discipline
/// au point d'appel.
///
/// Ce qu'il ne fait pas : traverser le dossier de sauvegardes, réparer,
/// déplacer une corbeille. L'orchestration reste au ViewModel — elle lit
/// `mods` et les gestionnaires de backups, donc d'autres domaines.
@Observable
final class MaintenanceStore {

    /// L'inventaire de l'écran. `nil` tant qu'il n'a pas été construit —
    /// **distinct d'un rapport vide**, qui veut dire « rien à faire ».
    private(set) var report: MaintenanceInventory.Report?

    /// Vrai pendant qu'une construction d'inventaire tourne — pilote le
    /// spinner et l'anti-double-clic du bouton.
    private(set) var isBuilding = false

    /// Le rapport de la dernière réparation **qui a tourné**. Une opération
    /// sans réparation n'a pas le droit de l'effacer : l'utilisateur ne l'a
    /// peut-être pas fini de lire.
    private(set) var lastRepairReport: ModFolderRepairer.Report?

    /// Le message d'une action de quarantaine, avec sa sévérité.
    private(set) var quarantineMessage: QuarantineMessage?

    /// Les événements de corbeille, du plus récent au plus ancien. Lu à la
    /// demande — l'ouverture de l'écran, un geste de remise ou de purge —
    /// pas un état que le scan entretient : la corbeille est hors liste par
    /// construction.
    private(set) var trashEvents: [ModTrash.Event] = []

    // MARK: - Le verrou de construction

    /// Prend le verrou de construction, ou rend `false` s'il est déjà tenu.
    /// Test-et-pose en une opération, comme les autres verrous du dépôt.
    func beginBuilding() -> Bool {
        if isBuilding { return false }
        isBuilding = true
        return true
    }

    func endBuilding() {
        isBuilding = false
    }

    // MARK: - Publication

    func setReport(_ newReport: MaintenanceInventory.Report?) {
        report = newReport
    }

    /// Ne passe ici qu'une réparation qui a réellement tourné — le ViewModel
    /// garde la décision, le store garde la valeur.
    func setRepairReport(_ newReport: ModFolderRepairer.Report?) {
        lastRepairReport = newReport
    }

    func setQuarantineMessage(_ message: QuarantineMessage?) {
        quarantineMessage = message
    }

    /// Remplacement en bloc : la corbeille est relue du disque à chaque
    /// demande, il n'y a rien à fusionner.
    func setTrashEvents(_ events: [ModTrash.Event]) {
        trashEvents = events
    }
}
