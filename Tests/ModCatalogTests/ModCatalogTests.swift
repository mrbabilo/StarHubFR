import Testing
import Foundation
@testable import StarHubTHCore

struct ModCatalogTests {
    private func page(_ ids: Int...) -> NexusModSearch.Page {
        NexusModSearch.Page(
            hits: ids.map { NexusModSearch.Hit(modId: $0, name: "M\($0)", version: "1",
                                                updatedAt: nil, categoryName: "Gameplay",
                                                uploader: "a", adultContent: false, tags: []) },
            totalCount: ids.count)
    }

    /// Un catalogue branché sur un dictionnaire en mémoire : tout le
    /// comportement se teste sans disque. `Store` est une classe pour que
    /// les closures de lecture/écriture capturent une référence — une var
    /// locale capturée par une closure qui lui survit ne compile pas.
    private final class Store {
        var files: [String: Data] = [:]
        var corrupt = false
        var read: (String) -> Data? { { self.corrupt ? Data("n'est pas json".utf8) : self.files[$0] } }
        var write: (String, Data) -> Void { { self.files[$0] = $1 } }
    }

    private func makeCatalog(now: Date = Date(timeIntervalSince1970: 1_000_000),
                             store: Store = Store()) -> (ModCatalog, Store) {
        (ModCatalog(load: store.read, save: store.write, now: { now }), store)
    }

    @Test func aFreshSectionStaysFreshForADayThenStale() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let (catalog, store) = makeCatalog(now: t0)
        #expect(catalog.state(.trending) == .empty(.neverLoaded))
        catalog.record(.trending, page: page(1, 2))
        if case .fresh(let p) = catalog.state(.trending) { #expect(p.hits.count == 2) }
        else { Issue.record("à t0 la section est fraîche") }
        // 24 h moins une minute : encore fraîche
        let (stillFresh, _) = makeCatalog(now: t0.addingTimeInterval(ModCatalog.freshness - 60),
                                          store: store)
        if case .fresh = stillFresh.state(.trending) {} else { Issue.record("23 h 59 : fraîche") }
        // 24 h pile : périmée mais affichée — pas un spinner sur page blanche
        let (after, _) = makeCatalog(now: t0.addingTimeInterval(ModCatalog.freshness + 1),
                                     store: store)
        if case .stale(let p) = after.state(.trending) { #expect(p.hits.count == 2) }
        else { Issue.record("périmée = stale avec l'ancien contenu") }
    }

    /// Spécification §6 : une requête ne doit jamais rendre deux fois le même
    /// mod dans une même bande ; le retrouver dans une autre section est
    /// normal, les fichiers ne se mélangent pas.
    @Test func recordingDeduplicatesInsideASection() {
        let (catalog, _) = makeCatalog()
        let duplicated = NexusModSearch.Page(
            hits: page(1, 2).hits + page(1).hits, totalCount: 3)
        catalog.record(.recent, page: duplicated)
        if case .fresh(let p) = catalog.state(.recent) {
            #expect(p.hits.map(\.modId) == [1, 2])  // un mod, une carte, même bande
        } else { Issue.record("attendu fresh") }
    }

    @Test func aCorruptCacheReadsAsNeverLoaded() {
        let store = Store(); store.corrupt = true
        let (catalog, _) = makeCatalog(store: store)
        #expect(catalog.state(.french) == .empty(.neverLoaded))
        // on recharge, jamais d'erreur surfaced pour un cache (spec §6)
    }

    @Test func sectionsDoNotShareTheirFiles() {
        let (catalog, store) = makeCatalog()
        catalog.record(.trending, page: page(5))
        catalog.record(.french, page: page(6))
        #expect(store.files.count == 2)  // une entrée par section
    }

    @Test func sectionDefaultsMatchTheSpec() {
        #expect(ModCatalog.SectionKind.trending.defaultSort == .endorsed)
        #expect(ModCatalog.SectionKind.recent.defaultSort == .recentlyUpdated)
        #expect(ModCatalog.SectionKind.french.defaultSort == .recentlyUpdated)
        #expect(ModCatalog.SectionKind.french.defaultTag == NexusModSearch.frenchTag)
        #expect(ModCatalog.SectionKind.trending.defaultTag == nil)
    }

    @Test func aDetailIsCachedForADayThenForgotten() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let (catalog, store) = makeCatalog(now: t0)
        let detail = NexusModSearch.Detail(modId: 9, name: "Nine", summary: nil,
                                           descriptionText: "d", endorsements: 3,
                                           version: "1", updatedAt: nil, tags: [],
                                           pictureUrls: [], uploaderName: nil)
        #expect(catalog.detail(for: 9) == nil)
        catalog.recordDetail(detail)
        #expect(catalog.detail(for: 9)?.name == "Nine")
        let (nextDay, _) = makeCatalog(now: t0.addingTimeInterval(ModCatalog.freshness + 1),
                                       store: store)
        #expect(nextDay.detail(for: 9) == nil)  // périmée : la fiche se re-demande
    }

    /// Une catégorie a son propre fichier de cache : filtrer sur « Portraits »
    /// ne doit pas écraser les tendances sans filtre, ni les servir à sa
    /// place. Sans cette clé distincte, revenir à « toutes les catégories »
    /// rendrait la liste filtrée pendant 24 h.
    @Test func eachCategoryCachesUnderItsOwnKey() {
        let (catalog, store) = makeCatalog()
        catalog.record(.trending, category: nil, page: page(1, 2))
        catalog.record(.trending, category: 6, page: page(7))

        #expect(store.files.count == 2)
        if case .fresh(let all) = catalog.state(.trending, category: nil) {
            #expect(all.hits.map(\.modId) == [1, 2])
        } else { Issue.record("les tendances sans filtre restent en cache") }
        if case .fresh(let portraits) = catalog.state(.trending, category: 6) {
            #expect(portraits.hits.map(\.modId) == [7])
        } else { Issue.record("la catégorie a son propre cache") }
        // Une catégorie jamais chargée ne récupère pas celui d'une autre.
        #expect(catalog.state(.trending, category: 21) == .empty(.neverLoaded))
    }
}
