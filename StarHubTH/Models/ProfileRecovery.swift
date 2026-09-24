import Foundation

/// Ce que le dialogue de reprise R2 déclenche.
///
/// Ces deux gestes — « Reprendre l'application » et « Garder l'état actuel » —
/// ne se rencontrent qu'après un crash survenu en cours d'application de
/// profil, c'est-à-dire quand `Mods/` est à moitié déplacé. Chacun de leurs
/// refus laisse l'utilisateur devant un parc incohérent : ce sont les chemins
/// les moins parcourus, et les plus coûteux à se tromper.
enum ProfileRecovery {

    enum Resumption: Equatable, Sendable {
        /// Rien à reprendre : aucun journal d'interruption.
        case nothingToResume
        /// Une application tourne déjà.
        case refused
        /// Le profil n'existe plus : « Reprendre » n'a plus de sens, et
        /// laisser le journal ferait revenir l'alerte à chaque lancement sans
        /// issue. Le journal est tranché, le disque reste tel quel.
        case clearJournal(profileName: String)
        /// Le jeu tourne. Le journal **reste** : l'alerte reviendra au
        /// prochain lancement, et le re-clic du profil actif re-présente le
        /// résolveur.
        case refusedGameRunning(profileName: String)
        /// Reprendre les déplacements, puis restaurer les configs du profil —
        /// c'est cette restauration que le crash avait avalée avec le
        /// completion (la capture, elle, avait déjà couru avant le dispatch).
        case resume(profileId: UUID)
    }

    /// - Parameter gameRunning: **paresseux à dessein**, et un test le
    ///   vérifie. Chez l'appelant, `isGameRunning()` informe au passage le
    ///   garde anti double-lancement : le consulter pour un journal absent,
    ///   une application en cours ou un profil disparu déplacerait ce garde
    ///   pour rien.
    static func resume(journal: ProfileApplyJournal?,
                       profiles: [ModProfile],
                       isApplying: Bool,
                       gameRunning: () -> Bool) -> Resumption {
        guard let journal else { return .nothingToResume }
        guard !isApplying else { return .refused }
        guard let profile = profiles.first(where: { $0.id == journal.profileId }) else {
            return .clearJournal(profileName: journal.profileName)
        }
        guard !gameRunning() else { return .refusedGameRunning(profileName: profile.name) }
        return .resume(profileId: profile.id)
    }

    enum Keep: Equatable, Sendable {
        case nothing
        /// Trancher le journal, et — seulement si le profil interrompu est
        /// encore l'actif — adopter l'état du disque. C'est l'adoption
        /// explicite que `syncActiveProfileIds` refuse tant que le journal
        /// vit ; une fois le journal parti, elle doit avoir lieu.
        case settle(profileName: String, adoptingToggles: Bool)
    }

    static func keepDiskState(journal: ProfileApplyJournal?, active: UUID?) -> Keep {
        guard let journal else { return .nothing }
        return .settle(profileName: journal.profileName,
                       adoptingToggles: active == journal.profileId)
    }

    enum Adoption: Equatable, Sendable {
        case nothing
        case adopt(profileId: UUID)
        /// Une application est morte en route : l'adopter écrirait l'accident
        /// dans le profil.
        case blockedByJournal(profileName: String)
        /// X109 — le dernier scan n'a pas pu lire `Mods/` (disque externe
        /// éjecté) : sa liste vide veut dire « rien lu », pas « rien
        /// d'activé ». L'adopter vidait le profil actif.
        case blockedUnreadable
    }

    /// Faut-il recopier les mods activés du disque dans le profil actif ?
    static func adoptDiskState(active: UUID?, profiles: [ModProfile],
                               journal: ProfileApplyJournal?,
                               modsFolderWasReadable: Bool) -> Adoption {
        guard let active, profiles.contains(where: { $0.id == active }) else { return .nothing }
        if let journal, journal.profileId == active {
            return .blockedByJournal(profileName: journal.profileName)
        }
        guard modsFolderWasReadable else { return .blockedUnreadable }
        return .adopt(profileId: active)
    }
}
