import Testing
import Foundation
@testable import StarHubTHCore

struct PerformanceOverlapTests {
    private func mod(_ id: String, folder: String, version: String = "1.0.0", enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: id, name: folder, folderName: folder, version: version,
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [])
    }

    private let pair = PerformanceOverlap(
        first: .init(uniqueId: "A.Perf", measuredVersion: "1.0.0"),
        second: .init(uniqueId: "B.Perf", measuredVersion: "2.0.0"),
        sharedMethods: ["Tree.draw", "Grass.draw"], conditionalMethods: [], conditionalOption: nil)

    /// SMAPI compare les identifiants sans la casse : un manifeste qui écrit
    /// `a.perf` est le même mod.
    @Test func matchesIgnoreIdentifierCase() {
        let found = PerformanceOverlapResolver.matches(
            in: [mod("a.perf", folder: "A"), mod("B.PERF", folder: "B")], catalog: [pair])
        #expect(found.count == 1)
        #expect(found.first?.partner(of: "A")?.folderName == "B")
    }

    /// Un seul des deux installé : rien. Les deux installés mais l'un en
    /// pause : la paire est rendue (la fiche prévient avant d'activer), mais
    /// n'est pas « active ».
    @Test func aPausedPartnerIsFoundButNotActive() {
        #expect(PerformanceOverlapResolver.matches(in: [mod("A.Perf", folder: "A")], catalog: [pair]).isEmpty)
        let found = PerformanceOverlapResolver.matches(
            in: [mod("A.Perf", folder: "A"), mod("B.Perf", folder: "B", enabled: false)], catalog: [pair])
        #expect(found.count == 1)
        #expect(found.first?.bothEnabled == false)
    }

    /// Un mod installé deux fois (Swim, sur le parc réel) : l'exemplaire actif
    /// gagne, quel que soit l'ordre du scan — c'est lui que SMAPI charge.
    @Test func theEnabledCopyWinsOverAPausedDuplicate() {
        for order in [[false, true], [true, false]] {
            let mods = order.enumerated().map { i, enabled in
                mod("A.Perf", folder: "A\(i)", enabled: enabled)
            } + [mod("B.Perf", folder: "B")]
            let found = PerformanceOverlapResolver.matches(in: mods, catalog: [pair])
            #expect(found.first?.firstMod.isEnabled == true)
            #expect(found.first?.bothEnabled == true)
        }
    }

    /// Une version installée autre que la version décompilée : la ligne le dit.
    @Test func aDifferentVersionAsksForRemeasure() {
        let found = PerformanceOverlapResolver.matches(
            in: [mod("A.Perf", folder: "A", version: "1.0.0"), mod("B.Perf", folder: "B", version: "2.1.0")],
            catalog: [pair])
        #expect(found.first.map { $0.isRemeasureNeeded(for: $0.firstMod) } == false)
        #expect(found.first.map { $0.isRemeasureNeeded(for: $0.secondMod) } == true)
    }

    /// La clé ne dépend ni de l'ordre ni de la casse : un écart posé depuis la
    /// fiche de l'un vaut pour la fiche de l'autre.
    @Test func theKeyIsUnorderedAndCaseless() {
        let swapped = PerformanceOverlap(first: pair.second, second: pair.first,
                                         sharedMethods: [], conditionalMethods: [], conditionalOption: nil)
        #expect(pair.key == swapped.key)
        #expect(pair.key == "a.perf|b.perf")
    }

    @Test func dismissalsRoundTrip() {
        let raw = PerformanceOverlapDismissals.dismissing("b|c", in: PerformanceOverlapDismissals.dismissing("a|b", in: ""))
        #expect(PerformanceOverlapDismissals.decode(raw) == ["a|b", "b|c"])
        #expect(PerformanceOverlapDismissals.dismissing("a|b", in: raw) == raw)
        #expect(PerformanceOverlapDismissals.decode("").isEmpty)
    }

    /// Le catalogue ne répète aucune paire, n'associe jamais un mod à
    /// lui-même, et ne garde que des paires à deux méthodes ou plus.
    @Test func catalogIsWellFormed() {
        let keys = PerformanceOverlap.catalog.map(\.key)
        #expect(Set(keys).count == keys.count)
        for entry in PerformanceOverlap.catalog {
            #expect(entry.first.uniqueId.lowercased() != entry.second.uniqueId.lowercased())
            #expect(entry.sharedMethods.count >= 2)
            #expect(Set(entry.sharedMethods).isDisjoint(with: entry.conditionalMethods))
            #expect(entry.conditionalMethods.isEmpty == (entry.conditionalOption == nil))
        }
    }

    /// Remesure du 2026-10-19 sur les versions du parc : UltraSmooth 2.6.2
    /// (Nexus publie déjà la 2.6.3, absente du parc : l'écran demandera une
    /// remesure à son installation), Radiance 2.3.4, Stardropium 0.3.0,
    /// StardewOptimizer 3.0.3.
    @Test func lesVersionsMesureesSontCellesDuParc() {
        func measured(_ id: String) -> String? {
            PerformanceOverlap.catalog.flatMap { [$0.first, $0.second] }
                .first { $0.uniqueId == id }?.measuredVersion
        }
        #expect(measured("palmhacker13.UltraSmooth") == "2.6.2")
        #expect(measured("phuicmt.SDVRadiance") == "2.3.4")
        #expect(measured("Arshia1381.Stardropium") == "0.3.0")
        #expect(measured("baiyu.StardewOptimizer") == "3.0.3")
    }

    /// Ce que le relevé par `typeof(...)` seul ne voyait pas : des méthodes
    /// typées par `TypeByName` (SpaceCore, l'itérateur de sauvegarde du jeu,
    /// TMXTile, Farm Type Manager) et des balayages dynamiques. Les deux
    /// premières touchent l'écriture de la partie.
    @Test func lesMethodesTypeesParVariableSontAuCatalogue() throws {
        let dropUS = try #require(PerformanceOverlap.catalog.first {
            $0.key == "arshia1381.stardropium|palmhacker13.ultrasmooth"
        })
        for m in ["SaveGamePatcher.FindAndRemoveModNodes", "SaveGame+<getSaveEnumerator>d__94.MoveNext",
                  "TMXExtensions.SetFlip", "TMXExtensions.SetRotationValue",
                  "ModEntry+Utility.GetTilesByProperty"] {
            #expect(dropUS.sharedMethods.contains(m))
        }
        #expect(dropUS.sharedMethods.count == 20)
        let radUS = try #require(PerformanceOverlap.catalog.first {
            $0.key == "palmhacker13.ultrasmooth|phuicmt.sdvradiance"
        })
        for m in ["Object.draw", "Critter.draw", "Critter.drawAboveFrontLayer",
                  "Bat.drawAboveAllLayers", "Junimo.draw", "JunimoHarvester.draw"] {
            #expect(radUS.sharedMethods.contains(m))
        }
        let soUS = try #require(PerformanceOverlap.catalog.first {
            $0.key == "baiyu.stardewoptimizer|palmhacker13.ultrasmooth"
        })
        #expect(soUS.conditionalMethods == ["MachineGroup.Automate"])
        #expect(soUS.conditionalOption == "AutomateThrottle")
    }

    /// `GameLocation.passTimeForObjects` est patchée **par défaut** des deux
    /// côtés : UltraSmooth par `ClockTickOptimizer` depuis 2.4.9 (seul garde
    /// `EnableMod`), Stardropium par `TenMinuteClockOptimizationModule`. Seule
    /// `timeUpdate` reste derrière l'option expérimentale d'UltraSmooth.
    @Test func passTimeForObjectsEstPartageeParDefaut() throws {
        let pair = try #require(PerformanceOverlap.catalog.first {
            $0.key == "arshia1381.stardropium|palmhacker13.ultrasmooth"
        })
        #expect(pair.sharedMethods.contains("GameLocation.passTimeForObjects"))
        #expect(pair.conditionalMethods == ["GameLocation.timeUpdate"])
        #expect(pair.conditionalOption == "EnableExperimentalFeatures")
    }

    @Test func stardewOptimizerRecouvreUltraSmoothEtStardropium() throws {
        // 3.0.3 (2026-10-14) : `Debris.updateChunks`, `Furniture.draw`,
        // `GameLocation.updateWater` et `GameMenu.changeTab` rejoignent les
        // quatre de la 1.0.0.
        let soUS = try #require(PerformanceOverlap.catalog.first {
            $0.key == "baiyu.stardewoptimizer|palmhacker13.ultrasmooth"
        })
        #expect(soUS.sharedMethods.sorted()
                == ["Debris.updateChunks", "Furniture.draw", "GameLocation.DayUpdate",
                    "GameLocation.updateWater", "GameMenu.changeTab", "Monster.update",
                    "NPC.update", "TemporaryAnimatedSprite.draw"])
        // `Furniture.draw` fait de Stardropium une paire : deux méthodes,
        // là où `NPC.update` seule était écartée comme bruit.
        let soDrop = try #require(PerformanceOverlap.catalog.first {
            $0.key == "arshia1381.stardropium|baiyu.stardewoptimizer"
        })
        #expect(soDrop.sharedMethods.sorted() == ["Furniture.draw", "NPC.update"])
        // Avec Radiance, `GameLocation.updateWater` seule : bruit.
        #expect(!PerformanceOverlap.catalog.contains {
            $0.key == "baiyu.stardewoptimizer|phuicmt.sdvradiance"
        })
    }

    @Test func lesRecouplementsNouveauxDUltraSmooth2415SontAuCatalogue() throws {
        let dropUS = try #require(PerformanceOverlap.catalog.first {
            $0.key == "arshia1381.stardropium|palmhacker13.ultrasmooth"
        })
        for m in ["ArgUtility.SplitBySpaceAndGet", "FishingRod.distanceToLand",
                  "ItemQueryResolver.TryResolve"] {
            #expect(dropUS.sharedMethods.contains(m))
        }
        let radUS = try #require(PerformanceOverlap.catalog.first {
            $0.key == "palmhacker13.ultrasmooth|phuicmt.sdvradiance"
        })
        #expect(radUS.sharedMethods.contains("SpriteBatch.Draw"))
    }
}
