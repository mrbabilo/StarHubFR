import Foundation
import Testing
@testable import StarHubTHCore

/// Quand **ne pas** mémoriser les `config.json` d'un profil, et comment
/// compter ce qu'une passe a changé.
///
/// Les trois abstentions de `captureProfileConfigs` partagent une même règle,
/// écrite dans le code mais jamais éprouvée : **laisser le trou visible plutôt
/// que maquiller une donnée fausse**. Chacune couvre un état où le disque ne
/// porte pas ce que le profil croit y avoir — et capturer y attribuerait au
/// profil le contenu d'un autre.
struct ProfileConfigCaptureTests {

    private let alpha = UUID()
    private let beta = UUID()

    private func profiles() -> [ModProfile] {
        [ModProfile(id: alpha, name: "Alpha", enabledModIds: []),
         ModProfile(id: beta, name: "Beta", enabledModIds: [])]
    }

    private func journal(_ id: UUID, _ name: String) -> ProfileApplyJournal {
        ProfileApplyJournal(profileId: id, profileName: name, startedAt: Date(), moves: [])
    }

    private func abstention(for profileId: UUID,
                            gameRunning: Bool = false,
                            desynced: UUID? = nil,
                            journal: ProfileApplyJournal? = nil)
        -> ProfileConfigCapture.Abstention? {
        ProfileConfigCapture.abstention(capturing: profileId, profiles: profiles(),
                                        gameRunning: gameRunning,
                                        desyncedProfileId: desynced, journal: journal)
    }

    // MARK: - Les trois abstentions

    @Test func nothingStopsAnOrdinaryCapture() {
        #expect(abstention(for: alpha) == nil)
    }

    @Test func aRunningGameStopsTheCapture() {
        #expect(abstention(for: alpha, gameRunning: true) == .gameRunning)
    }

    @Test func aDesyncedProfileIsNotCaptured() {
        // Une bascule antérieure faite jeu ouvert a laissé ce profil actif
        // sans que son disque en porte les réglages : il tient encore ceux
        // d'un autre. Capturer attribuerait ce contenu étranger à son magasin.
        #expect(abstention(for: alpha, desynced: alpha) == .desynced(profileName: "Alpha"))
    }

    @Test func aDesyncMarkOnAnotherProfileDoesNotStopThisCapture() {
        #expect(abstention(for: alpha, desynced: beta) == nil)
    }

    @Test func aProfileWhoseApplyWasInterruptedIsNotCaptured() {
        // R2 : son disque tient un état dont rien ne dit pour quel profil il
        // est fait — même règle que la désynchronisation.
        #expect(abstention(for: alpha, journal: journal(alpha, "Alpha"))
                == .interruptedApply(profileName: "Alpha"))
    }

    @Test func theInterruptedApplyIsNamedByTheJournalNotByTheProfile() {
        // Le journal survit à la suppression — et au renommage — du profil :
        // l'alerte doit parler avec le nom qu'il porte, pas avec l'actuel.
        #expect(abstention(for: alpha, journal: journal(alpha, "Ancien nom"))
                == .interruptedApply(profileName: "Ancien nom"))
    }

    @Test func aJournalOfAnotherProfileDoesNotStopThisCapture() {
        #expect(abstention(for: alpha, journal: journal(beta, "Beta")) == nil)
    }

    @Test func anUnknownProfileWithNothingPendingDoesNotAbstain() {
        // Rien ne le désigne : ni le jeu, ni la désynchronisation, ni un
        // journal. L'absence du profil de la liste ne suffit pas à s'abstenir.
        #expect(abstention(for: UUID()) == nil)
    }

    @Test func theGameGuardComesFirst() {
        // Jeu ouvert **et** désynchronisé : c'est le jeu qu'on nomme, la
        // cause que l'utilisateur peut traiter tout de suite.
        #expect(abstention(for: alpha, gameRunning: true, desynced: alpha) == .gameRunning)
    }

    // MARK: - Ce que la passe a changé

    private func entry(_ text: String, at seconds: TimeInterval = 0) -> ProfileConfigEntry {
        ProfileConfigEntry(text: text, capturedAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func anAddedEntryCounts() {
        #expect(ProfileConfigCapture.touchedCount(before: [:], after: ["A": entry("{}")]) == 1)
    }

    @Test func aRemovedEntryCounts() {
        // « Repartir des réglages par défaut » supprime le fichier : l'entrée
        // disparaît, et c'est bien un changement.
        #expect(ProfileConfigCapture.touchedCount(before: ["A": entry("{}")], after: [:]) == 1)
    }

    @Test func aChangedTextCounts() {
        #expect(ProfileConfigCapture.touchedCount(before: ["A": entry("{}")],
                                                  after: ["A": entry("{\"x\":1}")]) == 1)
    }

    @Test func anUnchangedTextCountsForNothingEvenWithANewDate() {
        // Le compte porte sur ce que la passe a changé, pas sur le total du
        // magasin : « 12 configs mémorisés » quand un seul a bougé donnerait
        // une fausse idée de ce que la bascule vient de faire.
        #expect(ProfileConfigCapture.touchedCount(before: ["A": entry("{}", at: 0)],
                                                  after: ["A": entry("{}", at: 999)]) == 0)
    }

    @Test func severalChangesOfDifferentKindsAddUp() {
        let before = ["A": entry("{}"), "B": entry("{}"), "C": entry("{}")]
        let after = ["A": entry("{}"), "B": entry("{\"x\":1}"), "D": entry("{}")]
        // A inchangé, B modifié, C retiré, D ajouté.
        #expect(ProfileConfigCapture.touchedCount(before: before, after: after) == 3)
    }
}
