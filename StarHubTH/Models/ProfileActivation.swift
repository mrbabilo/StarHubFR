import Foundation

/// Ce qu'un clic sur un profil déclenche.
///
/// Extrait de `applyProfile` (ViewModel) : six branches, chacune avec sa
/// raison, et aucune sous test. Ce sont les branches **rares** qui portent le
/// risque — elles ne se rencontrent qu'après un crash (reprise R2) ou une
/// application partielle, c'est-à-dire précisément quand l'état du parc est
/// déjà fragile.
///
/// Le type ne fait rien : il rend la décision, l'appelant l'exécute (capture
/// des configs, journal, `activeProfileId`, déplacements de dossiers).
enum ProfileActivation {

    enum Decision: Equatable, Sendable {
        /// Une application tourne déjà : deux activations concurrentes
        /// renommeraient les mêmes dossiers.
        case refused
        /// Le jeu tourne. Activer déplace des centaines de dossiers : le refus
        /// tombe **avant** la moindre mutation.
        case refusedGameRunning(profileName: String)
        /// Quitter sans en prendre un autre — une transition réelle : les
        /// réglages du profil quitté sont capturés à son crédit, même si aucun
        /// dossier ne bouge.
        case leave(capturing: UUID?, clearingJournalNamed: String?)
        /// Re-clic du profil dont une application a été interrompue par un
        /// crash : re-présenter le résolveur. Sans cette branche, le garde de
        /// `syncActiveProfileIds` rendrait le geste muet et la question
        /// deviendrait irrécupérable.
        case presentRecovery
        /// Re-clic d'un profil appliqué à moitié : reprendre les déplacements.
        /// Enregistrer l'état où l'échec les a laissés effacerait justement ce
        /// qu'il restait à faire.
        case resume(profileId: UUID)
        /// Re-clic du profil actif, rien en suspens : il adopte les bascules
        /// faites à la main depuis la page des mods.
        case adoptManualToggles
        /// Changer de profil.
        case activate(profileId: UUID, capturing: UUID?, clearingJournalNamed: String?)
    }

    /// - Parameters:
    ///   - requested: le profil cliqué ; `nil` pour « quitter ».
    ///   - journal: l'application interrompue dont la question n'est pas
    ///     tranchée (R2).
    ///   - incomplete: les profils dont la dernière application s'est arrêtée
    ///     en chemin sans crash.
    ///   - gameRunning: **paresseux à dessein**, et un test le vérifie. Chez
    ///     l'appelant, `isGameRunning()` a un effet de bord — il informe le
    ///     garde anti double-lancement (`launchGate.noticeGameRunning()`). Le
    ///     consulter pour un départ ou un refus déplacerait ce garde sans
    ///     qu'aucune activation soit en jeu. Même patron que les closures
    ///     d'`Inputs` du cadrage de la liste (REFACTORING §6).
    static func decide(requested: UUID?,
                       profiles: [ModProfile],
                       active: UUID?,
                       isApplying: Bool,
                       gameRunning: () -> Bool,
                       journal: ProfileApplyJournal?,
                       incomplete: Set<UUID>) -> Decision {
        guard !isApplying else { return .refused }

        // Un identifiant orphelin vaut « quitter » : activer un profil au
        // hasard serait pire que ne rien faire.
        guard let requested, let profile = profiles.first(where: { $0.id == requested }) else {
            // Quitter le profil journalisé tranche la question posée par le
            // crash — sinon le prochain lancement re-proposerait de reprendre
            // un profil explicitement quitté.
            let clearing = journal.flatMap { $0.profileId == active ? $0.profileName : nil }
            return .leave(capturing: active, clearingJournalNamed: clearing)
        }

        // Le refus ne vaut que pour une activation : quitter ne déplace rien.
        guard !gameRunning() else { return .refusedGameRunning(profileName: profile.name) }

        if active == requested {
            // La question posée à l'utilisateur passe avant la reprise muette :
            // les deux peuvent coexister après un crash en cours d'application.
            if journal?.profileId == requested { return .presentRecovery }
            if incomplete.contains(requested) { return .resume(profileId: requested) }
            return .adoptManualToggles
        }

        // Le journal du sortant est effacé avant que celui du profil entrant
        // ne s'écrive ; celui du profil **entrant** est gardé, il porte la
        // question que sa propre reprise doit poser.
        let clearing = journal.flatMap { $0.profileId == requested ? nil : $0.profileName }
        return .activate(profileId: requested, capturing: active,
                         clearingJournalNamed: clearing)
    }
}
