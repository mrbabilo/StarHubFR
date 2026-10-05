import Testing
import Foundation
@testable import StarHubTHCore

struct SloOptimizerConfigTests {
    /// La vraie ligne du format 1.0.0 (relevée dans la DLL décompilée,
    /// `ModEntry.cs`) : préfixe SMAPI `INFO` à double espace, paires séparées
    /// par `", "`, triplets à virgules collées, point final. Le `0,8x` porte
    /// la virgule décimale d'un système en français.
    static let realLine = """
    [18:55:50 INFO  Stardew Loading Optimizer] [OPTIMIZER CONFIG] profile=3, resourceProfile=balanced, prepareToUninstall=False, detailedDiagnostics=False, performanceMeasurement=True, diagnosticsScope=low-frequency-comparison-markers, contentPatcherPerPatchProbe=False, prefetch=True, prefetchStart=after-save-loaded, prefetchLimit=512 MB, prefetchRate=8 MB/s, savePrefetchSelection=last-selected, saveSourceOwner=native+SpaceCore, backgroundSaveObjects=retired, fastSaveObjects=retired, removeSaveSelectionDelay=True, mapCache=True, mapCacheLimit=256 MB, backgroundMapPreparation=configured=True,effective=false,reason=retired-thread-affinity, backgroundImagePreparation=configured=True,effective=True,reason=single-player-session, backgroundPreparationGate=SaveLoaded, imageCache=True, imageCacheLimit=512 MB, imageEntryLimit=64 MB, imageRuntimeJoin=4 ms, imageSaveWindowAdmission=first-use, workingSetSoftLimit=1024 MB, fastWarp=configured=True,effective=True,reason=single-player-session, fastWarpMultiplier=0,8x, deferredTileSheets=configured=False,effective=False,reason=disabled-by-config, deferredScope=main-save-and-secondary-local-screen, deferredWarmupDelay=5s, deferredIdle=2s, spaceCoreParallelSerializers=True, spaceCoreEmptySidecarFastPath=True, automaticSnapshot=0s.
    """

    /// Profil, limites de cache en clair, et les triplets des optimisations —
    /// capitalisation mixte des booléens (`True` de config, `false` littéral).
    @Test func parsesRealLine() throws {
        let config = try #require(SloOptimizerConfig.parse(line: Self.realLine))
        #expect(config.profile == 3)
        #expect(config.resourceProfile == "balanced")
        #expect(config.raw["imageCacheLimit"] == "512 MB")
        #expect(config.raw["prefetchRate"] == "8 MB/s")
        #expect(config.raw["fastWarpMultiplier"] == "0,8x")

        let fastWarp = try #require(config.optimizations["fastWarp"])
        #expect(fastWarp.configured == true)
        #expect(fastWarp.effective == true)
        #expect(fastWarp.reason == "single-player-session")

        let mapPreparation = try #require(config.optimizations["backgroundMapPreparation"])
        #expect(mapPreparation.configured == true)
        #expect(mapPreparation.effective == false)
        #expect(mapPreparation.reason == "retired-thread-affinity")

        let deferred = try #require(config.optimizations["deferredTileSheets"])
        #expect(deferred.configured == false)
    }

    /// La migration porte presque le même marqueur : la ligne de config seule
    /// est retenue, dans un journal qui contient les deux.
    @Test func migrationLineIsNotTheConfig() {
        let migration = "[18:55:49 INFO  Stardew Loading Optimizer] [OPTIMIZER CONFIG MIGRATION] profile=2, resourceProfile=balanced, reason=stable-profile-and-production-diagnostics, configPersisted=true."
        #expect(SloOptimizerConfig.parse(line: migration) == nil)

        let config = SloOptimizerConfig.parse(log: migration + "\n" + Self.realLine)
        #expect(config?.raw["prepareToUninstall"] == "False")
    }

    /// Une ligne qui a changé de forme rend `nil`, jamais des valeurs inventées.
    @Test func changedShapeFailsSilently() {
        #expect(SloOptimizerConfig.parse(line: "[18:55:50 INFO  Stardew Loading Optimizer] [OPTIMIZER CONFIG] forme inconnue sans paires.") == nil)
        #expect(SloOptimizerConfig.parse(log: "un journal sans la ligne") == nil)
    }

    /// Les nombres du journal suivent la locale du processus du jeu.
    @Test func decimalCommaIsANumber() {
        #expect(SloOptimizerConfig.double("0,8") == 0.8)
        #expect(SloOptimizerConfig.double("0.8") == 0.8)
        #expect(SloOptimizerConfig.bool("True") == true)
        #expect(SloOptimizerConfig.bool("false") == false)
        #expect(SloOptimizerConfig.int("3") == 3)
    }
}
