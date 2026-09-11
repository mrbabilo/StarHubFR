import Foundation
import Testing
@testable import StarHubTHCore

/// Ce qu'un clic sur un profil déclenche — l'aiguillage de `applyProfile`.
///
/// Six branches, chacune avec sa raison, et aucune sous test : le re-clic du
/// profil actif fait trois choses différentes selon l'état de la reprise R2,
/// quitter un profil capture ses réglages même si aucun dossier ne bouge, et
/// un refus doit arriver **avant la moindre mutation**. Ce sont les branches
/// rares qui portent le risque : elles ne se rencontrent qu'après un crash ou
/// une application partielle.
struct ProfileActivationTests {

    private let alpha = UUID()
    private let beta = UUID()

    private func profile(_ id: UUID, _ name: String) -> ModProfile {
        ModProfile(id: id, name: name, enabledModIds: [])
    }

    private func journal(_ id: UUID, _ name: String) -> ProfileApplyJournal {
        ProfileApplyJournal(profileId: id, profileName: name, startedAt: Date(), moves: [])
    }

    private func decide(requested: UUID?,
                        active: UUID? = nil,
                        isApplying: Bool = false,
                        gameRunning: @escaping () -> Bool = { false },
                        journal: ProfileApplyJournal? = nil,
                        incomplete: Set<UUID> = [])
        -> ProfileActivation.Decision {
        ProfileActivation.decide(requested: requested,
                                 profiles: [profile(alpha, "Alpha"), profile(beta, "Beta")],
                                 active: active, isApplying: isApplying,
                                 gameRunning: gameRunning, journal: journal,
                                 incomplete: incomplete)
    }

    // MARK: - Les refus, avant toute mutation

    @Test func anApplyAlreadyRunningRefusesTheNextOne() {
        // Deux activations concurrentes renommeraient les mêmes dossiers.
        #expect(decide(requested: alpha, isApplying: true) == .refused)
    }

    @Test func aRunningGameRefusesTheActivationByName() {
        // Activer un profil déplace des centaines de dossiers : refus net
        // **avant** la capture, `activeProfileId` et l'enregistrement.
        #expect(decide(requested: alpha, gameRunning: { true })
                == .refusedGameRunning(profileName: "Alpha"))
    }

    @Test func aProfileThatNoLongerExistsIsTreatedAsLeaving() {
        // Un identifiant orphelin ne doit pas activer un profil au hasard.
        #expect(decide(requested: UUID(), active: alpha)
                == .leave(capturing: alpha, clearingJournalNamed: nil))
    }

    @Test func theGameGuardDoesNotBlockLeaving() {
        // Quitter ne déplace rien : le refus ne vaut que pour une activation.
        #expect(decide(requested: nil, active: alpha, gameRunning: { true })
                == .leave(capturing: alpha, clearingJournalNamed: nil))
    }

    @Test func theGameIsNotEvenConsultedWhenNothingWillBeActivated() {
        // Chez l'appelant, `isGameRunning()` informe au passage le garde
        // anti double-lancement : le consulter pour un départ ou un refus
        // déplacerait ce garde sans qu'aucune activation soit en jeu.
        var asked = 0
        _ = decide(requested: nil, active: alpha, gameRunning: { asked += 1; return false })
        _ = decide(requested: alpha, isApplying: true, gameRunning: { asked += 1; return false })
        #expect(asked == 0)
    }

    // MARK: - Quitter

    @Test func leavingCapturesTheConfigsOfTheProfileBeingLeft() {
        // Quitter est une transition réelle : le config est capturé au crédit
        // du profil qu'on quitte, même si aucun dossier ne bouge.
        #expect(decide(requested: nil, active: alpha)
                == .leave(capturing: alpha, clearingJournalNamed: nil))
    }

    @Test func leavingTheJournaledProfileSettlesTheQuestionTheCrashAsked() {
        // Sans cela, le prochain lancement re-proposerait de reprendre un
        // profil explicitement quitté.
        #expect(decide(requested: nil, active: alpha, journal: journal(alpha, "Alpha"))
                == .leave(capturing: alpha, clearingJournalNamed: "Alpha"))
    }

    @Test func leavingDoesNotTouchAJournalOfAnotherProfile() {
        #expect(decide(requested: nil, active: alpha, journal: journal(beta, "Beta"))
                == .leave(capturing: alpha, clearingJournalNamed: nil))
    }

    @Test func leavingWithNothingActiveStillClearsTheMarker() {
        #expect(decide(requested: nil, active: nil)
                == .leave(capturing: nil, clearingJournalNamed: nil))
    }

    // MARK: - Re-cliquer le profil déjà actif : trois issues

    @Test func reclickingTheJournaledProfileRepresentsTheResolver() {
        // Sans cette branche, le garde de `syncActiveProfileIds` rendrait le
        // geste muet : le seul moyen de rouvrir le résolveur disparaîtrait.
        #expect(decide(requested: alpha, active: alpha, journal: journal(alpha, "Alpha"))
                == .presentRecovery)
    }

    @Test func reclickingAnIncompletelyAppliedProfileResumesTheMoves() {
        // Re-cliquer est le seul geste de reprise offert (« Activer » est
        // masqué pour le profil actif) : reprendre les déplacements, plutôt
        // qu'enregistrer l'état où l'échec les a laissés — ce qui effacerait
        // justement ce qu'il restait à faire.
        #expect(decide(requested: alpha, active: alpha, incomplete: [alpha])
                == .resume(profileId: alpha))
    }

    @Test func theJournalWinsOverTheIncompleteMarkOnTheSameProfile() {
        // Les deux peuvent coexister après un crash en cours d'application :
        // la question posée à l'utilisateur passe avant la reprise muette.
        #expect(decide(requested: alpha, active: alpha,
                       journal: journal(alpha, "Alpha"), incomplete: [alpha])
                == .presentRecovery)
    }

    @Test func reclickingASettledActiveProfileAdoptsManualToggles() {
        // Le cas courant : le profil actif adopte les bascules faites à la
        // main depuis la page des mods.
        #expect(decide(requested: alpha, active: alpha) == .adoptManualToggles)
    }

    // MARK: - Changer de profil

    @Test func switchingCapturesTheOutgoingProfileFirst() {
        // Le disque porte encore les réglages du sortant : c'est la seule
        // fenêtre où ils existent.
        #expect(decide(requested: beta, active: alpha)
                == .activate(profileId: beta, capturing: alpha, clearingJournalNamed: nil))
    }

    @Test func switchingClearsAJournalOfAnyOtherProfile() {
        // Le journal du sortant doit être effacé **avant** que celui du
        // profil entrant ne s'écrive.
        #expect(decide(requested: beta, active: alpha, journal: journal(alpha, "Alpha"))
                == .activate(profileId: beta, capturing: alpha, clearingJournalNamed: "Alpha"))
    }

    @Test func switchingKeepsTheJournalOfTheProfileBeingEntered() {
        // Il appartient au profil entrant : l'effacer perdrait la question
        // que la reprise doit poser.
        #expect(decide(requested: beta, active: alpha, journal: journal(beta, "Beta"))
                == .activate(profileId: beta, capturing: alpha, clearingJournalNamed: nil))
    }

    @Test func activatingFromNoProfileCapturesNothing() {
        #expect(decide(requested: alpha, active: nil)
                == .activate(profileId: alpha, capturing: nil, clearingJournalNamed: nil))
    }
}
