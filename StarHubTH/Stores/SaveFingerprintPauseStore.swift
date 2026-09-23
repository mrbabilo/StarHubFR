import Foundation
import Observation

/// A1-T8 — l'état de l'avertissement d'empreintes de sauvegarde, extrait du
/// VM (règle F1-T2 : une fonctionnalité neuve n'y entre plus). Voir
/// `SaveFingerprintReport` (Core) pour le chiffre, et
/// `View.saveFingerprintPauseGate` pour l'écran.
///
/// Trois temps : scanner les saves hors du fil principal (une save peut
/// dépasser 40 Mo de XML), suspendre la bascule derrière la confirmation si
/// le rapport n'est pas vide, puis reprendre (`confirm`) ou clôturer
/// (`cancel`). Pendant scan et suspension, le VM garde `isToggling` posé :
/// la file de bascule n'enchaîne pas, et `pendingToggleFolder` garde le
/// spinner de la rangée visible — le geste est en cours, pas perdu.
@MainActor
@Observable
final class SaveFingerprintPauseStore {

    /// La bascule suspendue derrière l'avertissement : `nil` au repos.
    /// Tant que ce n'est pas nil, rien n'a été renommé — la décision
    /// reste celle de l'utilisateur.
    private(set) var pending: PendingPause?

    /// Le contenu de la suspension : le mod visé (capturé par valeur à
    /// l'empilement, comme dans `pendingToggles`) et le rapport chiffré
    /// depuis les saves réelles.
    struct PendingPause {
        let mod: ModItem
        let report: SaveFingerprintReport
    }

    /// La reprise de la bascule suspendue (le renommage, au VM) et sa
    /// clôture (la complétion de la file). Tenues hors de `pending` : ce
    /// sont des fils de conduite, pas de l'état affiché.
    private var onResume: (() -> Void)?
    private var onAbort: (() -> Void)?

    /// Lance le scan des saves pour les ids du plan, hors du fil principal.
    /// Rapport vide → `resume` immédiatement (pas de confirmation pour
    /// rien) ; rapport non vide → suspendre et exposer `pending`. `abort`
    /// est la clôture à honorer si la session disparaît en route.
    func checkBeforePause(
        mod: ModItem,
        modIDs: Set<String>,
        resume: @escaping () -> Void,
        abort: @escaping () -> Void
    ) {
        DispatchQueue.global().async { [weak self] in
            // fetchSaves() est conçu pour les files de fond (SaveManager).
            let saves = SaveManager.shared.fetchSaves()
                .map { (name: $0.folderName, url: $0.fileURL) }
            let report = SaveFingerprintReport.scanSaves(at: saves, modIDs: modIDs)
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    abort()
                    return
                }
                guard !report.isEmpty else {
                    resume()
                    return
                }
                self.pending = PendingPause(mod: mod, report: report)
                self.onResume = resume
                self.onAbort = abort
            }
        }
    }

    /// « Mettre en pause quand même » : rendre la main à la bascule
    /// suspendue, sans rescanner. Idempotent au repos.
    func confirm() {
        guard let resume = takeOwnership() else { return }
        resume()
    }

    /// L'annulation : clôturer sans rien renommer. La complétion est
    /// honorée — la rangée doit rendre son état au repos et la file de
    /// bascule repartir. Idempotent au repos.
    func cancel() {
        guard let abort = takeOwnership() else { return }
        abort()
    }

    /// Sortir de la suspension en une lecture : `pending` vidé et les deux
    /// fils récupérés d'un coup — fermer l'alerte après un confirm (Esc
    /// arrive après le clic) ne déclenche jamais une seconde reprise.
    private func takeOwnership() -> (() -> Void)? {
        guard pending != nil else { return nil }
        pending = nil
        let resume = onResume
        let abort = onAbort
        onResume = nil
        onAbort = nil
        return resume ?? abort
    }
}
