import Testing
import Foundation
@testable import StarHubTHCore

struct ProbeHarmonyMapTests {
    private func map() throws -> ProbeHarmonyMap {
        try #require(ProbeHarmonyMap.decode(try Fixture.data("harmony-map.json")))
    }

    @Test func decodesTheRealMap() throws {
        let map = try map()
        #expect(map.mods.count == 291)
        #expect(map.methods.count == 294)
        #expect(map.stage == "DayStarted")
        #expect(map.capturedAt == "2026-09-26T20:40:00.3802060+02:00")
    }

    /// Chargé = présent dans `Mods` de la carte ; sans la casse, comme SMAPI.
    @Test func loadedModsAndVersionsComeFromTheMap() throws {
        let map = try map()
        #expect(map.isLoaded("palmhacker13.ultrasmooth"))
        #expect(!map.isLoaded("phuicmt.SDVRadiance"))
        #expect(map.version(of: "Arshia1381.Stardropium") == "0.1.4-beta")
        #expect(map.version(of: "phuicmt.SDVRadiance") == nil)
    }

    /// 16 propriétaires Harmony du parc ne sont pas des UniqueID : rattachés
    /// au plus long identifiant chargé suivi d'un point.
    @Test func secondaryOwnersResolveToTheirMod() throws {
        let map = try map()
        #expect(map.modId(forOwner: "Cropgenics.cjb-compat") == "Cropgenics")
        #expect(map.modId(forOwner: "PALMHACKER13.ULTRASMOOTH") == "palmhacker13.UltraSmooth")
        #expect(map.modId(forOwner: "MiniMonoModHotfix") == nil)
    }

    /// Nos propres enveloppes ne sont jamais le patch d'un mod du parc.
    @Test func theProbeItselfIsNeverAnOwner() throws {
        let map = try map()
        #expect(map.modId(forOwner: "mrbabilo.StarHubFR.Probe") == nil)
        #expect(map.modId(forOwner: "mrbabilo.StarHubFR.Probe.PatchCosts") == nil)
    }

    @Test func sharedMethodsAreMeasuredOnTheRealMap() throws {
        let map = try map()
        #expect(map.sharedMethods("Arshia1381.Stardropium", "palmhacker13.UltraSmooth")
                == ["Bush.draw", "FarmAnimal.draw", "Furniture.draw", "Game1.getTimeOfDayString",
                    "Grass.draw", "NPC.update"])
        #expect(map.sharedMethods("neoiw.StardewLoadingOptimizer", "palmhacker13.UltraSmooth")
                == ["LoadGameMenu+SaveFileSlot..ctor", "ScreenFade.UpdateFadeAlpha"])
        #expect(map.sharedMethods("neoiw.StardewLoadingOptimizer", "Arshia1381.Stardropium").isEmpty)
    }

    /// Patcher le code d'un autre mod : un seul propriétaire, que « méthodes
    /// partagées » ne voit pas. C'est ainsi que Loading Optimizer neutralise SinZ.
    @Test func patchesOfAnotherModsCodeAreFound() throws {
        let map = try map()
        #expect(map.methods(patchedBy: "neoiw.StardewLoadingOptimizer",
                            inAssembly: "SinZational Speedy Solutions") == ["ModEntry.OnGameLaunched"])
        #expect(map.methods(patchedBy: "Arshia1381.Stardropium",
                            inAssembly: "SinZational Speedy Solutions")
                == ["ModImageCache.ModContentManager__LoadRawImageData__Postfix"])
        #expect(map.methods(patchedBy: "palmhacker13.UltraSmooth",
                            inAssembly: "SinZational Speedy Solutions").isEmpty)
    }

    @Test func shortNamesKeepTypeAndMethodOnly() {
        #expect(ProbeHarmonyMap.shortName("StardewValley.TerrainFeatures.Bush.draw(SpriteBatch)") == "Bush.draw")
        #expect(ProbeHarmonyMap.shortName("StardewValley.Menus.LoadGameMenu+SaveFileSlot..ctor(LoadGameMenu, Farmer, Nullable`1)")
                == "LoadGameMenu+SaveFileSlot..ctor")
        #expect(ProbeHarmonyMap.shortName("Game1.update") == "Game1.update")
    }

    @Test func anUnreadableMapIsNil() {
        #expect(ProbeHarmonyMap.decode(Data("{}".utf8)) == nil)
        #expect(ProbeHarmonyMap.decode(Data()) == nil)
    }
}
