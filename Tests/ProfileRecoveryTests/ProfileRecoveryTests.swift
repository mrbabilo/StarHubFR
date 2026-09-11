import Foundation
import Testing
@testable import StarHubTHCore

/// Ce que le dialogue de reprise R2 déclenche — « Reprendre l'application »
/// et « Garder l'état actuel ».
///
/// Ces deux gestes ne se rencontrent qu'après un crash en cours d'application
/// de profil, c'est-à-dire quand le dossier `Mods/` est à moitié déplacé.
/// Chacun de leurs refus laisse l'utilisateur devant un parc incohérent : ce
/// sont les chemins les moins parcourus et les plus coûteux à se tromper.
struct ProfileRecoveryTests {

    private let alpha = UUID()
    private let beta = UUID()

    private func profiles() -> [ModProfile] {
        [ModProfile(id: alpha, name: "Alpha", enabledModIds: [])]
    }

    private func journal(_ id: UUID, _ name: String) -> ProfileApplyJournal {
        ProfileApplyJournal(profileId: id, profileName: name, startedAt: Date(), moves: [])
    }

    private func resume(_ journal: ProfileApplyJournal?,
                        isApplying: Bool = false,
                        gameRunning: @escaping () -> Bool = { false })
        -> ProfileRecovery.Resumption {
        ProfileRecovery.resume(journal: journal, profiles: profiles(),
                               isApplying: isApplying, gameRunning: gameRunning)
    }

    // MARK: - Reprendre

    @Test func anInterruptedApplyIsResumed() {
        #expect(resume(journal(alpha, "Alpha")) == .resume(profileId: alpha))
    }

    @Test func nothingToResumeWithoutAJournal() {
        #expect(resume(nil) == .nothingToResume)
    }

    @Test func anApplyAlreadyRunningRefusesTheResumption() {
        #expect(resume(journal(alpha, "Alpha"), isApplying: true) == .refused)
    }

    @Test func aDeletedProfileCannotBeResumedSoTheJournalIsSettled() {
        // « Reprendre » n'a plus de sens : le profil n'existe plus. Laisser le
        // journal ferait revenir l'alerte à chaque lancement, sans issue.
        #expect(resume(journal(beta, "Supprimé")) == .clearJournal(profileName: "Supprimé"))
    }

    @Test func aRunningGameRefusesTheResumptionAndKeepsTheJournal() {
        // Refus net, même garde que l'activation. Le journal **reste** :
        // l'alerte reviendra au prochain lancement, et le re-clic du profil
        // actif re-présente le résolveur.
        #expect(resume(journal(alpha, "Alpha"), gameRunning: { true })
                == .refusedGameRunning(profileName: "Alpha"))
    }

    @Test func theGameIsConsultedOnlyOnceEverythingElsePasses() {
        // `isGameRunning()` informe au passage le garde anti double-lancement :
        // le consulter pour un journal absent, une application en cours ou un
        // profil disparu déplacerait ce garde pour rien.
        var asked = 0
        let counting: () -> Bool = { asked += 1; return false }
        _ = resume(nil, gameRunning: counting)
        _ = resume(journal(alpha, "Alpha"), isApplying: true, gameRunning: counting)
        _ = resume(journal(beta, "Supprimé"), gameRunning: counting)
        #expect(asked == 0)
    }

    // MARK: - Garder l'état actuel

    @Test func keepingTheDiskStateSettlesTheJournal() {
        #expect(ProfileRecovery.keepDiskState(journal: journal(alpha, "Alpha"), active: nil)
                == .settle(profileName: "Alpha", adoptingToggles: false))
    }

    @Test func keepingAdoptsTheTogglesWhenTheProfileIsStillActive() {
        // C'est l'adoption explicite de l'état du disque, celle que
        // `syncActiveProfileIds` refuse tant que le journal vit : une fois le
        // journal parti, elle doit avoir lieu.
        #expect(ProfileRecovery.keepDiskState(journal: journal(alpha, "Alpha"), active: alpha)
                == .settle(profileName: "Alpha", adoptingToggles: true))
    }

    @Test func keepingDoesNotAdoptWhenAnotherProfileIsActive() {
        #expect(ProfileRecovery.keepDiskState(journal: journal(alpha, "Alpha"), active: beta)
                == .settle(profileName: "Alpha", adoptingToggles: false))
    }

    @Test func thereIsNothingToKeepWithoutAJournal() {
        #expect(ProfileRecovery.keepDiskState(journal: nil, active: alpha) == .nothing)
    }
}
