import Foundation
import Testing
@testable import StarHubTHCore

/// P5-9 — une pastille par profil, la plus grave d'abord.
struct ProfileAnomalyTests {
    private let id = UUID()

    @Test func aHealthyProfileShowsNothing() {
        #expect(ProfileAnomaly.of(profileId: id, isActive: true, journalProfileId: nil,
                                  incomplete: [], desyncedId: nil) == nil)
    }

    @Test func theInterruptedApplyOutranksTheRest() {
        #expect(ProfileAnomaly.of(profileId: id, isActive: true, journalProfileId: id,
                                  incomplete: [id], desyncedId: id) == .interruptedApply)
        #expect(ProfileAnomaly.of(profileId: id, isActive: true, journalProfileId: nil,
                                  incomplete: [id], desyncedId: id) == .incompletelyApplied)
    }

    /// La marque de désynchronisation ne vaut que pour le profil actif : une
    /// marque restée sur un profil quitté ne dit rien de son disque.
    @Test func desyncOnlyShowsOnTheActiveProfile() {
        #expect(ProfileAnomaly.of(profileId: id, isActive: true, journalProfileId: nil,
                                  incomplete: [], desyncedId: id) == .configsDesynced)
        #expect(ProfileAnomaly.of(profileId: id, isActive: false, journalProfileId: nil,
                                  incomplete: [], desyncedId: id) == nil)
    }

    /// Le journal d'un autre profil ne marque pas celui-ci.
    @Test func anotherProfilesJournalIsNotThisOnes() {
        #expect(ProfileAnomaly.of(profileId: id, isActive: false, journalProfileId: UUID(),
                                  incomplete: [], desyncedId: nil) == nil)
    }
}
