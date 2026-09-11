import Foundation
import Observation

/// L'état des profils de mods : la liste, l'identifiant actif, et le couple
/// drapeau/identité d'une activation en cours.
///
/// Le domaine n'est que l'état — la décision d'activation vit dans
/// `ProfileActivation`, la capture des configs dans `ProfileConfigCapture`,
/// la reprise dans `ProfileRecovery` (toutes en Core, testées). L'orchestration
/// disque (`applyProfileToFilesystem`, la sauvegarde en préférences) reste au
/// ViewModel et mute ce store par des setters nommés.
///
/// **Le couple drapeau/identité a deux rythmes de pose et un seul
/// effacement.** L'identité (`applyingId`) est posée par l'aiguillage, avant
/// l'orchestration — elle fait remplacer le bouton « Activer » de la ligne
/// par un spinner. Le drapeau (`isApplying`) est posé par l'orchestration
/// elle-même et verrouille toute seconde activation. À la fin, les deux
/// s'effacent ensemble (`endApplying`) : un drapeau oublié figeait tous les
/// boutons, une identité oubliée laissait un spinner mort.
@Observable
final class ProfileStore {

    private(set) var profiles: [ModProfile] = []
    private(set) var activeProfileId: UUID?
    /// Vrai pendant qu'une activation déplace des dossiers puis rescanne :
    /// verrouille une seconde activation et désactive les boutons.
    private(set) var isApplying = false
    /// Le profil dont l'activation est en vol — le spinner de sa ligne.
    private(set) var applyingId: UUID?

    /// Le profil portant cet identifiant, ou `nil`. Réécrit dix fois en
    /// `first(where:)` dans le ViewModel, et encore dans les vues.
    func profile(with id: UUID) -> ModProfile? {
        profiles.first { $0.id == id }
    }

    /// Le profil actif — le lookup de l'identifiant actif, pas un état
    /// séparé qui pourrait en diverger. Un identifiant orphelin ne rend rien.
    var activeProfile: ModProfile? {
        activeProfileId.flatMap { profile(with: $0) }
    }

    // MARK: - Publication

    func setProfiles(_ newProfiles: [ModProfile]) {
        profiles = newProfiles
    }

    func setActiveProfile(_ id: UUID?) {
        activeProfileId = id
    }

    /// Pose l'identité de l'activation en vol — avant l'orchestration.
    func setApplyingId(_ id: UUID?) {
        applyingId = id
    }

    /// Pose ou relâche le verrou d'activation — par l'orchestration.
    func setApplying(_ applying: Bool) {
        isApplying = applying
    }

    /// Fin d'activation : le drapeau et l'identité **ensemble**.
    func endApplying() {
        isApplying = false
        applyingId = nil
    }
}
