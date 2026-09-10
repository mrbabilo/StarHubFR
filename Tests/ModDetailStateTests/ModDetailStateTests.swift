import Foundation
import Testing
@testable import StarHubTHCore

/// Les transitions d'état de la fiche de mod (REFACTORING §6, domaine
/// Détail de mod) : cache instantané ou repli local, puis rafraîchissement
/// réseau. Le câblage (didSet, anti-course) reste au VM ; ce qui se teste,
/// ce sont les états eux-mêmes.
@Suite struct ModDetailStateTests {

    @Test func initialStateFromCacheIsStaleAndLoading() {
        let raw = ModDetailRaw(description: "cached desc", changelog: "cached log")
        let state = ModDetailState.initial(modId: 42, cached: raw, localDescription: "local desc")
        #expect(state.modId == 42)
        #expect(state.description == [.text("cached desc")])
        #expect(state.changelog == [.text("cached log")])
        #expect(state.isStale)
        #expect(state.isLoading)
    }

    /// Sans cache : la description locale du manifeste prend la relève,
    /// changelog vide.
    @Test func initialStateWithoutCacheFallsBackToLocalDescription() {
        let state = ModDetailState.initial(modId: 42, cached: nil, localDescription: "manifest desc")
        #expect(state.description == [.text("manifest desc")])
        #expect(state.changelog.isEmpty)
        #expect(state.isStale)
        #expect(state.isLoading)
    }

    /// Pas d'identifiant Nexus (`modId <= 0`) : pas de réseau en vol —
    /// le spinner ne doit pas tourner pour un fetch qui n'aura jamais lieu.
    @Test func unknownNexusIdIsNotLoading() {
        let state = ModDetailState.initial(modId: -1, cached: nil, localDescription: "local only")
        #expect(state.modId == -1)
        #expect(!state.isLoading)
        #expect(state.description == [.text("local only")])
    }

    /// Le rafraîchissement réussi n'est plus stale ni en chargement.
    @Test func refreshedStateIsFreshAndDone() {
        let raw = ModDetailRaw(description: "fresh desc", changelog: "fresh log")
        let state = ModDetailState.refreshed(modId: 42, raw: raw)
        #expect(!state.isStale)
        #expect(!state.isLoading)
        #expect(state.description == [.text("fresh desc")])
    }

    /// L'arrêt du spinner ne s'applique qu'à la fiche affichée : une
    /// réponse tardive pour un autre mod ne ferme pas le spinner de
    /// celle-ci.
    @Test func stopLoadingOnlyForMatchingModId() {
        var state = ModDetailState.initial(modId: 42, cached: nil, localDescription: "d")
        state.isLoading = true
        state.stopLoading(ifShowing: 43)
        #expect(state.isLoading)
        state.stopLoading(ifShowing: 42)
        #expect(!state.isLoading)
    }
}
