import Testing
import Foundation
@testable import StarHubTHCore

/// L'état des profils de mods : la liste, l'actif, le couple drapeau/identité
/// d'une activation en cours.
///
/// Le domaine n'est que l'état — la décision d'activation vit dans
/// `ProfileActivation`, la capture des configs dans `ProfileConfigCapture`,
/// la reprise dans `ProfileRecovery` (toutes en Core, testées). Ce que le
/// store apporte : le **lookup** qui était réécrit en `first(where:)` dix
/// fois dans le ViewModel, et un couple drapeau/identité posé en deux
/// endroits mais effacé toujours ensemble.
@Suite struct ProfileStoreTests {

    private func profile(_ name: String) -> ModProfile {
        ModProfile(name: name, enabledModIds: [])
    }

    // MARK: - Le lookup

    @Test func profileLookupFindsTheRightOne() {
        let s = ProfileStore()
        let a = profile("A"), b = profile("B")
        s.setProfiles([a, b])
        #expect(s.profile(with: a.id)?.name == "A")
        #expect(s.profile(with: b.id)?.name == "B")
    }

    @Test func profileLookupMissesCleanly() {
        let s = ProfileStore()
        #expect(s.profile(with: UUID()) == nil)
    }

    /// `activeProfile` est le lookup de l'identifiant actif — pas un état
    /// séparé qui pourrait diverger de lui.
    @Test func activeProfileFollowsTheActiveId() {
        let s = ProfileStore()
        let a = profile("A")
        s.setProfiles([a])
        #expect(s.activeProfile == nil)      // rien d'actif
        s.setActiveProfile(a.id)
        #expect(s.activeProfile?.name == "A")
        s.setActiveProfile(nil)
        #expect(s.activeProfile == nil)
    }

    /// Un profil actif qui n'est plus dans la liste ne rend rien — l'état
    /// actif orphelin ne doit pas se faufiler dans l'UI.
    @Test func anActiveIdWithoutAProfileRendersNothing() {
        let s = ProfileStore()
        s.setProfiles([profile("A")])
        s.setActiveProfile(UUID())           // un id sans profil
        #expect(s.activeProfile == nil)
    }

    // MARK: - Les mutations de la liste

    @Test func addingThenRemovingLeavesTheListClean() {
        let s = ProfileStore()
        let a = profile("A")
        s.add(a)
        #expect(s.profiles == [a])
        s.removeProfile(with: a.id)
        #expect(s.profiles.isEmpty)
    }

    /// La mutation par `inout` : le seul chemin d'écriture qui ne se voit
    /// ni dans un grep des `=`, ni dans un relevé des appels de méthode.
    @Test func mutateChangesOnlyTheTargetedProfile() {
        let s = ProfileStore()
        let a = profile("A"), b = profile("B")
        s.setProfiles([a, b])
        let changed = s.mutateProfile(with: a.id) { $0.name = "A2" }
        #expect(changed)
        #expect(s.profile(with: a.id)?.name == "A2")
        #expect(s.profile(with: b.id)?.name == "B")   // le voisin intact
    }

    @Test func mutatingAMissingProfileIsRefusedAndChangesNothing() {
        let s = ProfileStore()
        #expect(s.mutateProfile(with: UUID()) { $0.name = "fantôme" } == false)
        #expect(s.profiles.isEmpty)
    }

    // MARK: - Le couple drapeau/identité

    /// Deux rythmes de pose, un seul effacement : l'identité est posée avant
    /// l'orchestration, le drapeau par l'orchestration — mais **toujours**
    /// effacés ensemble.
    @Test func identityAndFlagAreRaisedSeparately() {
        let s = ProfileStore()
        let id = profile("A").id
        s.setApplyingId(id)
        #expect(s.applyingId == id)
        #expect(s.isApplying == false)       // l'orchestration n'a pas encore commencé
        s.setApplying(true)
        #expect(s.isApplying)
    }

    @Test func endApplyingClearsBothTogether() {
        let s = ProfileStore()
        let id = profile("A").id
        s.setApplyingId(id)
        s.setApplying(true)
        s.endApplying()
        #expect(s.isApplying == false)
        #expect(s.applyingId == nil)
    }

    // MARK: - Le chargement

    /// Le démarrage charge les deux d'un coup — depuis les préférences, dont
    /// l'une peut manquer sans invalider l'autre.
    @Test func loadingProfilesPreservesAnIndependentActiveId() {
        let s = ProfileStore()
        let a = profile("A")
        s.setActiveProfile(a.id)
        s.setProfiles([a])
        #expect(s.profiles.count == 1)
        #expect(s.activeProfileId == a.id)
        s.setProfiles([])                    // liste vidée, l'id reste
        #expect(s.activeProfileId == a.id)
        #expect(s.activeProfile == nil)      // mais ne rend plus rien
    }
}
