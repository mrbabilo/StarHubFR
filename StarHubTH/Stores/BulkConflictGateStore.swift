import Foundation
import Observation

/// A5-T8 — la confirmation avant un geste **groupé** qui rendrait actives des
/// paires en conflit : « Tout activer », bandeau et Espace de la sélection,
/// application d'un profil. La garde unitaire (`conflictActivationGate`) ne
/// voit qu'un mod à la fois et seulement contre les mods déjà actifs ; deux
/// mods réveillés ensemble lui échappaient. La règle est dans
/// `ModConflictVerdicts.newConflicts` (Core) ; l'écran dans
/// `View.bulkConflictGate`.
///
/// Une seule confirmation récapitulative, jamais une alerte par mod. Rien
/// n'est renommé tant que `pending` n'est pas levé : annuler laisse le parc
/// tel quel.
@MainActor
@Observable
final class BulkConflictGateStore {

    struct Pending {
        let subject: Subject
        let pairs: [ModConflictPair]
    }

    enum Subject: Equatable {
        /// « Tout activer » ou la sélection : le nombre de mods activés.
        case mods(count: Int)
        case profile(name: String)
    }

    private(set) var pending: Pending?
    private var onResume: (@MainActor () -> Void)?

    /// Pris dès la suspension, avant même que l'alerte paraisse.
    var isBusy: Bool { onResume != nil }

    /// Suspend le geste s'il rend actives des paires en conflit, et rend
    /// `true` : l'appelant s'arrête là, `confirm` le reprendra. `false` : rien
    /// à dire, continuer. `enabling`/`disabling` : les dossiers **de tête**
    /// que le geste renomme ; `mods`, les mods de tête du dernier scan.
    func suspendIfNeeded(mods: [ModItem], verdicts: ModConflictVerdicts,
                         candidates: [ModConflictPair],
                         enabling: [String], disabling: [String] = [],
                         subject: Subject,
                         resume: @escaping @MainActor () -> Void) -> Bool {
        suspend(mods.newConflicts(verdicts: verdicts, candidates: candidates,
                                  enabling: Set(enabling), disabling: Set(disabling)),
                subject: subject, resume: resume)
    }

    /// L'application d'un profil : les paires que son aperçu annonce
    /// (`ProfileApplyPreview`, P5-1), calculées sur le plan que le disque suivra.
    func suspendIfNeeded(applying profile: ModProfile, mods: [ModItem], verdicts: ModConflictVerdicts,
                         candidates: [ModConflictPair],
                         resume: @escaping @MainActor () -> Void) -> Bool {
        suspend(ProfileApplyPreview.make(applying: profile, to: mods, verdicts: verdicts,
                                         candidates: candidates).conflicts,
                subject: .profile(name: profile.name), resume: resume)
    }

    private func suspend(_ pairs: [ModConflictPair], subject: Subject,
                         resume: @escaping @MainActor () -> Void) -> Bool {
        guard !pairs.isEmpty else { return false }
        onResume = resume
        // Publiée au tour suivant : pour un profil, cette alerte suit celle
        // des empreintes, dont le bouton vient de relancer le geste — posée
        // pendant que la première se ferme, SwiftUI pourrait ne jamais la
        // présenter, et le store resterait pris.
        let next = Pending(subject: subject, pairs: pairs)
        Task { @MainActor [weak self] in
            guard let self, self.onResume != nil else { return }
            self.pending = next
        }
        return true
    }

    /// Reprendre le geste. Idempotent au repos : fermer l'alerte après un
    /// confirm ne relance rien.
    func confirm() {
        let resume = onResume
        pending = nil
        onResume = nil
        resume?()
    }

    func cancel() {
        pending = nil
        onResume = nil
    }
}
