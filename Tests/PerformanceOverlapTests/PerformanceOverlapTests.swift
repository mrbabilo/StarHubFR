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

    /// A5-T10 — remesure du 2026-10-10 sur les versions du parc :
    /// UltraSmooth 2.4.15, Radiance 2.3.1, Stardropium 0.2.2-beta, et
    /// StardewOptimizer 1.0.0 comme nouveau membre.
    @Test func lesVersionsMesureesSontCellesDuReleve20261010() {
        func measured(_ id: String) -> String? {
            PerformanceOverlap.catalog.flatMap { [$0.first, $0.second] }
                .first { $0.uniqueId == id }?.measuredVersion
        }
        #expect(measured("palmhacker13.UltraSmooth") == "2.4.15")
        #expect(measured("phuicmt.SDVRadiance") == "2.3.1")
        #expect(measured("Arshia1381.Stardropium") == "0.2.2-beta")
        #expect(measured("baiyu.StardewOptimizer") == "1.0.0")
    }

    @Test func stardewOptimizerRecouvreUltraSmoothEtStardropium() throws {
        let so = PerformanceOverlap.catalog.first { $0.key.hasPrefix("baiyu.stardewoptimizer") }
        let soUS = try #require(so)
        #expect(soUS.sharedMethods.sorted()
                == ["GameLocation.DayUpdate", "Monster.update", "NPC.update",
                    "TemporaryAnimatedSprite.draw"])
        // Une seule méthode commune avec Stardropium : écartée comme bruit,
        // comme `ScreenFade.UpdateFadeAlpha` avant elle.
        let soDrop = PerformanceOverlap.catalog.first {
            $0.key == "arshia1381.stardropium|baiyu.stardewoptimizer"
        }
        #expect(soDrop == nil)
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
