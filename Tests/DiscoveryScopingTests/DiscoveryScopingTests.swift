import Foundation
import Testing
@testable import StarHubTHCore

/// Ce que la vitrine montre, et ce qu'elle écarte.
///
/// Trois écarts en une seule passe — contenu adulte, traductions non
/// françaises, « masquer les installés » — plus la reconnaissance d'un mod
/// déjà au parc. Aucun n'était sous test, et chacun décide de ce que
/// l'utilisateur voit sur un catalogue de 33 000 entrées.
struct DiscoveryScopingTests {

    /// ⚠️ **C'est le tag `Translation` qui range un mod parmi les traductions,
    /// jamais sa catégorie** (`NexusModSearch.Hit.isTranslation`). La première
    /// version de ces fixtures posait `categoryName: "Translations"` : elle
    /// décrivait un état que Nexus ne produit pas, et le filtre francophone y
    /// paraissait inopérant.
    private func hit(_ modId: Int, _ name: String,
                     adult: Bool = false, tags: [String] = [],
                     translation: Bool = false) -> NexusModSearch.Hit {
        NexusModSearch.Hit(modId: modId, name: name, version: "1.0", updatedAt: nil,
                           categoryName: translation ? "Translations" : "Gameplay",
                           uploader: "someone", adultContent: adult,
                           tags: translation ? ["Translation"] + tags : tags)
    }

    private func rows(_ hits: [NexusModSearch.Hit],
                      installedIds: Set<Int> = [],
                      installedTitles: Set<String> = [],
                      hidingInstalled: Bool = false,
                      francophoneOnly: Bool = true) -> [DiscoveryScoping.Row] {
        DiscoveryScoping.rows(from: hits, installedNexusIds: installedIds,
                              installedTitles: installedTitles,
                              hidingInstalled: hidingInstalled,
                              francophoneOnly: francophoneOnly)
    }

    // MARK: - Les trois écarts

    @Test func adultContentNeverReachesTheShowcase() {
        #expect(rows([hit(1, "Sage Romance", adult: true)]).isEmpty)
    }

    @Test func aTranslationWithoutTheFrenchTagIsNotShown() {
        // La vitrine est francophone : une traduction allemande y serait du
        // bruit pour cet utilisateur.
        #expect(rows([hit(1, "Deutsche Übersetzung", tags: ["German"], translation: true)])
                .isEmpty)
    }

    @Test func aFrenchTranslationIsShown() {
        #expect(rows([hit(1, "Traduction FR", tags: ["French"], translation: true)]).count == 1)
    }

    @Test func anOrdinaryModIsNeverJudgedOnItsLanguageTags() {
        // Le filtre francophone ne vaut que pour les traductions : l'appliquer
        // à tout viderait la vitrine.
        #expect(rows([hit(1, "Stardew Valley Expanded")]).count == 1)
    }

    @Test func theSearchShowsEverythingIncludingForeignTranslations() {
        // On cherche un mod précis : filtrer sur la langue ferait conclure
        // « ce mod n'existe pas ».
        #expect(rows([hit(1, "Deutsche Übersetzung", tags: ["German"], translation: true)],
                     francophoneOnly: false).count == 1)
    }

    // MARK: - Reconnaître ce qui est déjà au parc

    @Test func anInstalledModIsRecognisedByItsNexusId() {
        let row = rows([hit(42, "Stardew Valley Expanded")], installedIds: [42]).first
        #expect(row?.installed == true)
    }

    @Test func anInstalledModIsRecognisedByItsTitleWithoutAnyId() {
        // Sur un compte gratuit tout s'installe à la main, donc sans
        // identifiant : le titre est le seul recours.
        let row = rows([hit(42, "Stardew Valley Expanded")],
                       installedTitles: ["Stardew Valley Expanded"]).first
        #expect(row?.installed == true)
    }

    @Test func anUnrelatedTitleDoesNotCountAsInstalled() {
        let row = rows([hit(42, "Stardew Valley Expanded")],
                       installedTitles: ["Content Patcher"]).first
        #expect(row?.installed == false)
    }

    @Test func hidingInstalledRemovesThemFromTheRows() {
        let shown = rows([hit(42, "Stardew Valley Expanded"), hit(7, "Autre chose")],
                         installedIds: [42], hidingInstalled: true)
        #expect(shown.map(\.hit.modId) == [7])
    }

    @Test func withoutHidingAnInstalledModStaysWithItsBadge() {
        // Le badge « installé » est l'information : le retirer de la liste par
        // défaut ferait croire que le mod n'existe pas sur Nexus.
        let shown = rows([hit(42, "Stardew Valley Expanded")], installedIds: [42])
        #expect(shown.count == 1)
        #expect(shown.first?.installed == true)
    }

    @Test func theOrderNexusSentIsKept() {
        // Le tri est celui de la section demandée (populaires, récents…) :
        // réordonner ici le contredirait en silence.
        let shown = rows([hit(3, "Trois"), hit(1, "Un"), hit(2, "Deux")])
        #expect(shown.map(\.hit.modId) == [3, 1, 2])
    }

    // MARK: - « Voir plus »

    @Test func thereIsMoreWhenTheServerSaysSo() {
        #expect(DiscoveryScoping.hasMore(received: 20, serverTotal: 33_204))
    }

    @Test func thereIsNoMoreOnceEverythingIsReceived() {
        #expect(!DiscoveryScoping.hasMore(received: 33, serverTotal: 33))
    }

    @Test func theOffsetCountsWhatWasReceivedNotWhatIsShown() {
        // ⚠️ Compter les cartes **visibles** ferait redemander sans fin ce que
        // les filtres viennent d'écarter : la page suivante repartirait du
        // même offset, et « voir plus » tournerait en rond.
        let received = [hit(1, "Un", adult: true), hit(2, "Deux")]
        #expect(rows(received).count == 1)
        #expect(DiscoveryScoping.nextOffset(received: received.count) == 2)
    }
}
