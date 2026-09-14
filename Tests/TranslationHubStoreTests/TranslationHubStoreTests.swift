import Testing
import Foundation
@testable import StarHubTHCore

/// L'état du hub de traduction FR : ce qui est posé, ce qu'une recherche a
/// rendu, et qui est en vol.
///
/// Le registre lui-même (`InstalledTranslationRegistry`) et ses règles sont
/// en Core et testés (`InstalledTranslationTests`) ; le store le porte et
/// publie. Ce que cette tranche épine : les résultats d'une recherche sont
/// **coupés en deux moitiés** — les propositions et ce qui est déjà posé —
/// et la moitié posée est celle qui dit qu'une mise à jour existe.
@Suite struct TranslationHubStoreTests {

    /// Le champ `adultContent` est omis : il a une valeur par défaut.
    private func hit(_ modId: Int, name: String = "T") -> NexusModSearch.Hit {
        .init(modId: modId, name: name, version: "1.0", updatedAt: nil,
              categoryName: "", uploader: "", adultContent: false,
              tags: [], endorsements: nil, summary: nil)
    }

    // MARK: - Le registre

    @Test func theRegistryStartsEmptyAndSurvivesMutation() {
        let s = TranslationHubStore()
        #expect(s.installed.translation(forHost: "Mod") == nil)
        s.mutateInstalled { $0.record(InstalledTranslation(
            hostFolderName: "Mod", nexusModId: 7, nexusName: "Mod FR",
            version: "1.0", updatedAt: nil, installedAt: Date(), files: [])) }
        #expect(s.installed.translation(forHost: "Mod") != nil)
    }

    @Test func loadingReplacesTheWholeRegistry() {
        let s = TranslationHubStore()
        s.mutateInstalled { $0.record(InstalledTranslation(
            hostFolderName: "Mod", nexusModId: 7, nexusName: "Mod FR",
            version: "1.0", updatedAt: nil, installedAt: Date(), files: [])) }
        s.setInstalled(InstalledTranslationRegistry())
        #expect(s.installed.translation(forHost: "Mod") == nil)
    }

    // MARK: - Les deux moitiés d'une recherche

    @Test func aNilHitRemovesTheKeyRatherThanHidingAnEmptyValue() {
        let s = TranslationHubStore()
        s.setHits([hit(1)], for: "Mod")
        s.setHits(nil, for: "Mod")
        #expect(s.hits["Mod"] == nil)        // la clé disparaît
        #expect(s.hits.isEmpty)
    }

    // MARK: - L'identité et les suppléments d'une fiche

    @Test func aNilIdentitySearchRemovesTheKeyRatherThanHidingAnEmptyValue() {
        let s = TranslationHubStore()
        s.setIdentitySearch(IdentitySearch(candidates: [], received: 3, serverTotal: 9),
                            for: "Mod")
        s.setIdentitySearch(nil, for: "Mod")
        #expect(s.identitySearches["Mod"] == nil)
        #expect(s.identitySearches.isEmpty)
    }

    /// Le même repli que la fiche : une panne n'est pas une absence, mais
    /// l'affichage ne garde rien d'une recherche qui a échoué — et ne doit pas
    /// effacer l'autre domaine (identité ≠ suppléments).
    @Test func aFailedSupplementSearchClearsOnlyItsOwnDomain() {
        let s = TranslationHubStore()
        s.setSupplementSearch(SupplementSearch(hits: [hit(1)], alreadyInstalled: [],
                                               received: 1, serverTotal: 4), for: "Mod")
        s.setIdentitySearch(IdentitySearch(candidates: [], received: 2, serverTotal: 5),
                            for: "Mod")
        s.setSupplementSearch(nil, for: "Mod")
        #expect(s.supplementSearches["Mod"] == nil)
        #expect(s.identitySearches["Mod"] != nil)   // l'autre domaine survit
    }

    /// Le rattachement d'une greffe (`linkToNexus`) repart de la recherche
    /// précédente pour la recomposer : la pose remplace, elle n'accumule pas.
    @Test func aSupplementSearchUpdateReplacesRatherThanAppends() {
        let s = TranslationHubStore()
        s.setSupplementSearch(SupplementSearch(hits: [hit(1)], alreadyInstalled: [],
                                               received: 2, serverTotal: 4), for: "Mod")
        s.setSupplementSearch(SupplementSearch(hits: [hit(3)], alreadyInstalled: [hit(1)],
                                               received: 2, serverTotal: 4), for: "Mod")
        let search = s.supplementSearches["Mod"]
        #expect(search?.hits.map(\.modId) == [3])
        #expect(search?.alreadyInstalled.map(\.modId) == [1])
    }

    /// Taire le total ferait passer une poignée pour une réponse complète :
    /// c'est le contrat de `isCapped`, porté par les deux types.
    @Test func cappedMeansServerTotalExceedsWhatThePageBrought() {
        #expect(SupplementSearch(hits: [], alreadyInstalled: [], received: 50,
                                 serverTotal: 428).isCapped)
        #expect(!SupplementSearch(hits: [], alreadyInstalled: [], received: 50,
                                  serverTotal: 50).isCapped)
        #expect(IdentitySearch(candidates: [], received: 10, serverTotal: 11).isCapped)
        #expect(!IdentitySearch(candidates: [], received: 11, serverTotal: 11).isCapped)
    }

    /// Les vols sont des ensembles mod par mod : une fiche ne retient pas une
    /// autre en otage, et retirer l'une ne retire pas les voisines.
    @Test func inFlightIdentityAndSupplementSetsArePerFolder() {
        let s = TranslationHubStore()
        s.setIdentitySearching(true, for: "A")
        s.setIdentitySearching(true, for: "B")
        s.setSupplementsSearching(true, for: "A")
        s.setIdentitySearching(false, for: "A")
        #expect(!s.isIdentitySearching("A"))
        #expect(s.isIdentitySearching("B"))          // la voisine survit
        #expect(s.isSupplementsSearching("A"))       // l'autre domaine aussi
    }

    @Test func installedHitsHoldTheirOwnHalf() {
        let s = TranslationHubStore()
        s.setInstalledHits([hit(2)], for: "Mod")
        #expect(s.hits["Mod"] == nil)        // l'autre moitié n'est pas touchée
        #expect(s.installedHits["Mod"]?.count == 1)
    }

    /// « Vider les résultats » vide les deux moitiés : une recherche neuve
    /// ne doit rien hériter de la précédente, ni des propositions ni de la
    /// moitié posée.
    @Test func clearingSearchResultsEmptiesBothHalves() {
        let s = TranslationHubStore()
        s.setHits([hit(1)], for: "A")
        s.setInstalledHits([hit(2)], for: "B")
        s.clearSearchResults()
        #expect(s.hits.isEmpty && s.installedHits.isEmpty)
    }

    // MARK: - Les vols, mod par mod

    /// La fiche désactive ses boutons **mod par mod** : un verrou unique
    /// rendait muet le clic sur un second mod — le bouton restait actif et
    /// ne faisait rien.
    @Test func searchingAndBusyAreTrackedPerMod() {
        let s = TranslationHubStore()
        s.setSearching(true, for: "A")
        #expect(s.isSearching("A"))
        #expect(s.isSearching("B") == false) // un second mod reste libre
        s.setSearching(false, for: "A")
        #expect(s.isSearching("A") == false)
    }

    @Test func busyFollowsTheSameRule() {
        let s = TranslationHubStore()
        s.setBusy(true, for: "A")
        s.setBusy(true, for: "B")
        s.setBusy(false, for: "A")
        #expect(s.isBusy("A") == false)
        #expect(s.isBusy("B"))               // l'autre opération continue
    }
}
