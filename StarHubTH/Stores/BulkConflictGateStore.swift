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

    var isBusy: Bool { pending != nil }

    /// Suspend le geste s'il rend actives des paires en conflit, et rend
    /// `true` : l'appelant s'arrête là, `confirm` le reprendra. `false` : rien
    /// à dire, continuer. `enabling`/`disabling` : les dossiers **de tête**
    /// que le geste renomme ; `mods`, les mods de tête du dernier scan.
    func suspendIfNeeded(mods: [ModItem], verdicts: ModConflictVerdicts,
                         candidates: [ModConflictPair],
                         enabling: [String], disabling: [String] = [],
                         subject: Subject,
                         resume: @escaping @MainActor () -> Void) -> Bool {
        let pairs = verdicts.newConflicts(
            candidates: candidates,
            activeBefore: mods.activeFolders(enabling: [], disabling: []),
            activeAfter: mods.activeFolders(enabling: Set(enabling), disabling: Set(disabling)),
            topFolders: mods.topFolders)
        guard !pairs.isEmpty else { return false }
        pending = Pending(subject: subject, pairs: pairs)
        onResume = resume
        return true
    }

    /// L'application d'un profil : ses activations **et** ses mises en pause
    /// (`ProfileApplyPlan.moves`, le plan que le disque suivra).
    func suspendIfNeeded(applying profile: ModProfile, mods: [ModItem], verdicts: ModConflictVerdicts,
                         candidates: [ModConflictPair],
                         resume: @escaping @MainActor () -> Void) -> Bool {
        let moves = ProfileApplyPlan.moves(applying: profile, to: mods)
        return suspendIfNeeded(mods: mods, verdicts: verdicts, candidates: candidates,
                               enabling: moves.filter { $0.direction == .enable }.map(\.folderName),
                               disabling: moves.filter { $0.direction == .disable }.map(\.folderName),
                               subject: .profile(name: profile.name), resume: resume)
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
