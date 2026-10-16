import Foundation
import Testing
@testable import StarHubTHCore

private func mod(_ name: String, languages: [String] = ["en", "fr"], enabled: Bool = true) -> ModItem {
    ModItem(uniqueId: "a.\(name)", name: name, folderName: name, version: "1.0.0",
            author: "Auteur", description: "", nexusUrl: "", nexusModId: "",
            isEnabled: enabled, dependencies: [], languages: languages)
}

private func coverage(_ total: Int, _ translated: Int) -> TranslationCoverage.Coverage {
    TranslationCoverage.Coverage(total: total, translated: translated, missing: [], empty: [],
                                 orphan: [], identicalToSource: [])
}

@Suite struct TranslationWorklistTests {

    /// Le segment vaut l'union des filtres « Partiellement traduits » et
    /// « À revoir » de la liste : ni plus, ni moins.
    @Test func membershipIsTheUnionOfTheListFilters() {
        let mods = [mod("Partiel"), mod("Complet"), mod("AReviser"), mod("SansFr", languages: ["en"]),
                    mod("PasLu")]
        let state = ModListScoping.TranslationState(
            coverage: ["Partiel": coverage(10, 4), "Complet": coverage(10, 10), "AReviser": coverage(5, 5)],
            stale: ["AReviser"])
        let names = TranslationWorklist.items(in: mods, state: state).map(\.name)
        #expect(Set(names) == ["Partiel", "AReviser"])
        let listCount = mods.filter {
            ModListScoping.matchesTranslation($0, .partial, state: state)
                || ModListScoping.matchesTranslation($0, .stale, state: state)
        }.count
        #expect(names.count == listCount)
    }

    /// Le plus gros reste d'abord ; un mod complet mais « à revoir » se
    /// départage par ses clés obsolètes avant le nom.
    @Test func biggestRemainderFirstThenOutdatedKeysThenName() {
        let mods = [mod("Petit"), mod("Gros"), mod("Zeta"), mod("Alpha")]
        let state = ModListScoping.TranslationState(
            coverage: ["Petit": coverage(10, 9), "Gros": coverage(100, 10),
                       "Zeta": coverage(5, 5), "Alpha": coverage(5, 5)],
            outdatedKeys: ["Zeta": 7, "Alpha": 2])
        #expect(TranslationWorklist.items(in: mods, state: state).map(\.name)
                == ["Gros", "Petit", "Zeta", "Alpha"])
    }

    /// Les deux autres ordres de la page : part restante, puis nom.
    @Test func percentAndNameOrders() {
        let mods = [mod("beta"), mod("Alpha"), mod("Gamma")]
        let state = ModListScoping.TranslationState(
            coverage: ["beta": coverage(1000, 900), "Alpha": coverage(10, 2), "Gamma": coverage(100, 50)])
        let items = TranslationWorklist.items(in: mods, state: state)
        #expect(items.map(\.name) == ["beta", "Gamma", "Alpha"])
        #expect(items.sorted(by: TranslationWorklist.Order.remainingPercent.precedes).map(\.name)
                == ["Alpha", "Gamma", "beta"])
        #expect(items.sorted(by: TranslationWorklist.Order.name.precedes).map(\.name)
                == ["Alpha", "beta", "Gamma"])
    }

    @Test func itemCarriesItsRemainderAndStaleness() throws {
        let state = ModListScoping.TranslationState(coverage: ["M": coverage(12, 3)], stale: ["M"])
        let item = try #require(TranslationWorklist.items(in: [mod("M", enabled: false)], state: state).first)
        #expect(item.missingCount == 9)
        #expect(item.isStale)
        #expect(!item.isEnabled)
    }

    /// « À traduire » est compté, pas listé ; « pas encore lu » distingue une
    /// liste vide d'une mesure en cours.
    @Test func untranslatedAndUnmeasuredAreCountedApart() throws {
        let mods = [mod("SansFr", languages: ["en"]), mod("SansI18n", languages: []),
                    mod("Lu"), mod("PasLu")]
        let state = ModListScoping.TranslationState(coverage: ["Lu": coverage(4, 4)])
        #expect(TranslationWorklist.untranslatedCount(in: mods, state: state) == 1)
        var pass = FrenchCoveragePass.State(coverage: state.coverage)
        #expect(TranslationWorklist.unmeasuredCount(in: mods, pass: pass) == 1)
        // Un `fr` sans `default.json` lu une fois n'est plus « en attente ».
        let stamp = pass.tick()
        pass = try #require(FrenchCoveragePass.merging([:], stale: [], unmeasurable: ["PasLu"],
                                                       into: pass, stamp: stamp))
        #expect(TranslationWorklist.unmeasuredCount(in: mods, pass: pass) == 0)
    }
}

/// R3 — la fiche reprend les résultats du balayage de la page, par le même
/// statut que la page.
@Suite struct SweepShownHitsTests {
    private let hit = NexusModSearch.Hit(modId: 42, name: "Mod FR", version: "1.0", updatedAt: nil,
                                         categoryName: "", uploader: "Trad", adultContent: false)

    @Test func ownSearchWinsOverTheSweep() {
        let entry = FrenchTranslationSweep.Entry(hits: [hit], searchedAt: .now)
        #expect(FrenchTranslationSweep.shownHits(own: [], entry: entry, installed: nil) == [])
    }

    @Test func sweepFillsTheGapAndAFailureSaysNothing() {
        let found = FrenchTranslationSweep.Entry(hits: [hit], searchedAt: .now)
        let none = FrenchTranslationSweep.Entry(hits: [], searchedAt: .now)
        let failed = FrenchTranslationSweep.Entry(hits: [], searchedAt: .now, failed: true)
        #expect(FrenchTranslationSweep.shownHits(own: nil, entry: found, installed: nil) == [hit])
        #expect(FrenchTranslationSweep.shownHits(own: nil, entry: none, installed: nil) == [])
        #expect(FrenchTranslationSweep.shownHits(own: nil, entry: failed, installed: nil) == nil)
        #expect(FrenchTranslationSweep.shownHits(own: nil, entry: nil, installed: nil) == nil)
    }
}
