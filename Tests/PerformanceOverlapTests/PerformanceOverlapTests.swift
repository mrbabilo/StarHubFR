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
}
