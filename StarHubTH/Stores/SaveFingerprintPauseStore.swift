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

    /// Le contenu de la suspension : ce qui met en pause — un mod (capturé
    /// par valeur à l'empilement, comme dans `pendingToggles`) ou un profil
    /// à l'activation — et le rapport chiffré depuis les saves réelles.
    struct PendingPause {
        let subject: Subject
        let report: SaveFingerprintReport
    }

    enum Subject: Equatable {
        case mod(ModItem)
        case profile(name: String)
    }

    /// La reprise de la bascule suspendue (le renommage, au VM) et sa
    /// clôture (la complétion de la file). Tenues hors de `pending` : ce
    /// sont des fils de conduite, pas de l'état affiché.
    private var onResume: (@MainActor () -> Void)?
    private var onAbort: (@MainActor () -> Void)?

    /// Lance le scan des saves pour les ids du plan, hors du fil principal.
    /// Rapport vide → `resume` immédiatement (pas de confirmation pour
    /// rien) ; rapport non vide → suspendre et exposer `pending`. `abort`
    /// est la clôture à honorer si la session disparaît en route.
    func checkBeforePause(
        subject: Subject,
        modIDs: Set<String>,
        resume: @escaping @MainActor () -> Void,
        abort: @escaping @MainActor () -> Void
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
                self.suspend(subject: subject, report: report, resume: resume, abort: abort)
            }
        }
    }

    /// Suspendre la bascule derrière l'avertissement — le point d'entrée
    /// des tests, qui n'ont pas à scanner de vraies saves.
    func suspend(
        subject: Subject,
        report: SaveFingerprintReport,
        resume: @escaping @MainActor () -> Void,
        abort: @escaping @MainActor () -> Void
    ) {
        pending = PendingPause(subject: subject, report: report)
        onResume = resume
        onAbort = abort
    }

    /// « Mettre en pause quand même » : rendre la main à la bascule
    /// suspendue, sans rescanner. Idempotent au repos.
    func confirm() {
        takeOwnership()?.resume()
    }

    /// L'annulation : clôturer sans rien renommer. La complétion est
    /// honorée — la rangée doit rendre son état au repos et la file de
    /// bascule repartir. Idempotent au repos.
    func cancel() {
        takeOwnership()?.abort()
    }

    /// Sortir de la suspension en une lecture : `pending` vidé et les deux
    /// fils récupérés d'un coup — fermer l'alerte après un confirm (Esc
    /// arrive après le clic) ne déclenche jamais une seconde reprise.
    /// Chaque sortie appelle **son** fil : rendre un seul fil (`resume ??
    /// abort`) faisait reprendre la bascule sur une annulation.
    private func takeOwnership()
        -> (resume: @MainActor () -> Void, abort: @MainActor () -> Void)? {
        guard pending != nil, let resume = onResume, let abort = onAbort
        else { return nil }
        pending = nil
        onResume = nil
        onAbort = nil
        return (resume, abort)
    }
}
