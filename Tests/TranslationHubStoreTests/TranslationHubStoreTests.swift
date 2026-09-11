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

    // MARK: - Les deux moitiés d'une recherche

    @Test func aNilHitRemovesTheKeyRatherThanHidingAnEmptyValue() {
        let s = TranslationHubStore()
        s.setHits([hit(1)], for: "Mod")
        s.setHits(nil, for: "Mod")
        #expect(s.hits["Mod"] == nil)        // la clé disparaît
        #expect(s.hits.isEmpty)
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
