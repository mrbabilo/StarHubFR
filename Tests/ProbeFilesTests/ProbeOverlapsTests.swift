import Testing
import Foundation
@testable import StarHubTHCore

struct ProbeOverlapsTests {
    private func map() throws -> ProbeHarmonyMap {
        try #require(ProbeHarmonyMap.decode(try Fixture.data("harmony-map.json")))
    }

    private func pair(_ a: String, _ b: String, in catalog: [PerformanceOverlap]) -> PerformanceOverlap? {
        catalog.first { $0.member(a) != nil && $0.member(b) != nil }
    }

    private func mod(_ id: String, version: String) -> ModItem {
        ModItem(uniqueId: id, name: id, folderName: id, version: version,
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: true, dependencies: [])
    }

    /// La vraie carte, retouchée : on n'y garde, parmi les méthodes patchées
    /// par Stardropium et UltraSmooth ensemble, que celles de `keep`.
    private func map(keepingSharedSdUs keep: Set<String>) throws -> ProbeHarmonyMap {
        let data = try Fixture.data("harmony-map.json")
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let methods = try #require(json["Methods"] as? [[String: Any]])
        json["Methods"] = methods.filter { method in
            let owners = Set(((method["Patches"] as? [[String: Any]]) ?? []).compactMap { $0["Owner"] as? String })
            guard owners.isSuperset(of: ["Arshia1381.Stardropium", "palmhacker13.UltraSmooth"]) else { return true }
            return keep.contains(ProbeHarmonyMap.shortName(method["Method"] as? String ?? ""))
        }
        return try #require(ProbeHarmonyMap.decode(try JSONSerialization.data(withJSONObject: json)))
    }

    /// Seuil de la marche 1 : une seule méthode en commun ne fait pas une paire.
    @Test func oneSharedMethodIsNotAPair() throws {
        let one = PerformanceOverlap.effectiveCatalog(map: try map(keepingSharedSdUs: ["Bush.draw"]))
        #expect(pair("Arshia1381.Stardropium", "palmhacker13.UltraSmooth", in: one) == nil)
        let two = PerformanceOverlap.effectiveCatalog(map: try map(keepingSharedSdUs: ["Bush.draw", "Grass.draw"]))
        #expect(pair("Arshia1381.Stardropium", "palmhacker13.UltraSmooth", in: two)?.sharedMethods
                == ["Bush.draw", "Grass.draw"])
    }

    /// Une carte du lancement (partie quittée à l'écran titre) est incomplète :
    /// le catalogue décompilé, pas une mesure tronquée.
    @Test func aMapWrittenAtLaunchIsIgnored() throws {
        let text = try #require(String(data: try Fixture.data("harmony-map.json"), encoding: .utf8))
        let launched = text.replacingOccurrences(of: "\"Stage\": \"DayStarted\"", with: "\"Stage\": \"GameLaunched\"")
        let map = try #require(ProbeHarmonyMap.decode(Data(launched.utf8)))
        #expect(map.stage == "GameLaunched")
        #expect(PerformanceOverlap.effectiveCatalog(map: map) == PerformanceOverlap.catalog)
    }

    /// Sans carte : le catalogue décompilé, à l'identique.
    @Test func withoutAMapTheCatalogIsUnchanged() {
        #expect(PerformanceOverlap.effectiveCatalog(map: nil) == PerformanceOverlap.catalog)
    }

    /// La carte corrige le catalogue : 6 méthodes partagées, pas 9 ; pas de
    /// méthodes conditionnelles pour une paire mesurée ; versions et date de
    /// la carte.
    @Test func measuredPairsReplaceDecompiledOnes() throws {
        let catalog = PerformanceOverlap.effectiveCatalog(map: try map())
        let sdUs = try #require(pair("Arshia1381.Stardropium", "palmhacker13.UltraSmooth", in: catalog))
        #expect(sdUs.sharedMethods == ["Bush.draw", "FarmAnimal.draw", "Furniture.draw",
                                       "Game1.getTimeOfDayString", "Grass.draw", "NPC.update"])
        #expect(sdUs.conditionalMethods.isEmpty && sdUs.conditionalOption == nil)
        #expect(sdUs.measuredAt == "2026-09-26T20:40:00.3802060+02:00")
        #expect(sdUs.member("palmhacker13.UltraSmooth")?.measuredVersion == "2.3.8")
    }

    /// Absente du catalogue, présente en jeu.
    @Test func aMeasuredPairMissingFromTheCatalogIsAdded() throws {
        let catalog = PerformanceOverlap.effectiveCatalog(map: try map())
        let sloUs = try #require(pair("neoiw.StardewLoadingOptimizer", "palmhacker13.UltraSmooth", in: catalog))
        #expect(sloUs.sharedMethods == ["LoadGameMenu+SaveFileSlot..ctor", "ScreenFade.UpdateFadeAlpha"])
    }

    /// Aucune méthode partagée, mais Loading Optimizer patche le code de SinZ :
    /// la paire existe, sa liste partagée est vide.
    @Test func aCodePatchAloneKeepsThePair() throws {
        let catalog = PerformanceOverlap.effectiveCatalog(map: try map())
        let sinzSlo = try #require(pair("SinZ.SpeedySolutions", "neoiw.StardewLoadingOptimizer", in: catalog))
        #expect(sinzSlo.sharedMethods.isEmpty)
        #expect(sinzSlo.codePatches == [.init(patcher: "neoiw.StardewLoadingOptimizer",
                                              patched: "SinZ.SpeedySolutions",
                                              methods: ["ModEntry.OnGameLaunched"])])
        let sinzSd = try #require(pair("SinZ.SpeedySolutions", "Arshia1381.Stardropium", in: catalog))
        #expect(sinzSd.codePatches.map(\.methods)
                == [["ModImageCache.ModContentManager__LoadRawImageData__Postfix"]])
    }

    /// Les deux chargés, rien en commun en jeu : la paire du catalogue
    /// (Loading Optimizer × Stardropium) disparaît.
    @Test func aPairWithNothingMeasuredDisappears() throws {
        let catalog = PerformanceOverlap.effectiveCatalog(map: try map())
        #expect(pair("neoiw.StardewLoadingOptimizer", "Arshia1381.Stardropium", in: catalog) == nil)
        #expect(pair("palmhacker13.UltraSmooth", "SinZ.SpeedySolutions", in: catalog) == nil)
    }

    /// Radiance en pause, absent de la carte : ses paires restent décompilées.
    @Test func aModAbsentFromTheMapKeepsItsDecompiledPairs() throws {
        let catalog = PerformanceOverlap.effectiveCatalog(map: try map())
        let radUs = try #require(pair("phuicmt.SDVRadiance", "palmhacker13.UltraSmooth", in: catalog))
        #expect(radUs.measuredAt == nil)
        #expect(radUs == PerformanceOverlap.catalog.first {
            $0.member("phuicmt.SDVRadiance") != nil && $0.member("palmhacker13.UltraSmooth") != nil
        })
        #expect(catalog.count == 7) // 6 paires + StardewOptimizer × UltraSmooth (A5-T10)
    }

    /// La carte écrit la version normalisée par SMAPI : `1.0` installé et
    /// `1.0.0` mesuré sont la même version.
    @Test func remeasureComparesVersionsSemantically() throws {
        let catalog = PerformanceOverlap.effectiveCatalog(map: try map())
        let sloUs = try #require(pair("neoiw.StardewLoadingOptimizer", "palmhacker13.UltraSmooth", in: catalog))
        let match = PerformanceOverlapMatch(overlap: sloUs,
                                            firstMod: mod("neoiw.StardewLoadingOptimizer", version: "1.0"),
                                            secondMod: mod("palmhacker13.UltraSmooth", version: "2.3.7"))
        #expect(!match.isRemeasureNeeded(for: match.firstMod))
        #expect(match.isRemeasureNeeded(for: match.secondMod))
    }
}
