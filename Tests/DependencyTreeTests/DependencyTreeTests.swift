import Testing
import Foundation
@testable import StarHubTHCore

private func mod(_ id: String, deps: [ModDependency] = [], enabled: Bool = true) -> ModItem {
    ModItem(uniqueId: id, name: id, folderName: id, version: "1.0.0", author: "a",
            description: "", nexusUrl: "", nexusModId: "", isEnabled: enabled, dependencies: deps)
}
private func req(_ id: String) -> ModDependency { ModDependency(uniqueId: id, isRequired: true) }

/// Builds a resolver over a fixed set of installed mods (keyed lowercased).
private func resolver(_ mods: [ModItem]) -> (String) -> (mod: ModItem, isEnabled: Bool, deps: [ModDependency])? {
    let byId = Dictionary(uniqueKeysWithValues: mods.map { ($0.uniqueId.lowercased(), $0) })
    return { uid in byId[uid.lowercased()].map { ($0, $0.isEnabled, $0.dependencies) } }
}

struct DependencyTreeTests {
    @Test func resolvesTransitiveDepthThree() {
        let c = mod("C")
        let b = mod("B", deps: [req("C")])
        let a = mod("A", deps: [req("B")])
        let tree = DependencyTreeBuilder.build(a.dependencies, resolve: resolver([a, b, c]))
        #expect(tree.count == 1)
        #expect(tree[0].uniqueId == "B")
        #expect(tree[0].children.count == 1)
        #expect(tree[0].children[0].uniqueId == "C")
        #expect(tree[0].children[0].children.isEmpty)
    }
    @Test func cycleTerminates() {
        let a = mod("A", deps: [req("B")])
        let b = mod("B", deps: [req("A")])
        let tree = DependencyTreeBuilder.build(a.dependencies, resolve: resolver([a, b]))
        #expect(tree[0].uniqueId == "B")
        #expect(tree[0].children[0].uniqueId == "A")
        #expect(tree[0].children[0].children.isEmpty)
    }
    @Test func missingDependencyIsLeaf() {
        let a = mod("A", deps: [req("Ghost")])
        let tree = DependencyTreeBuilder.build(a.dependencies, resolve: resolver([a]))
        #expect(tree[0].uniqueId == "Ghost")
        #expect(tree[0].status == .missing)
        #expect(tree[0].resolved == nil)
        #expect(tree[0].children.isEmpty)
    }
    /// Un diamant (D requis par B et par C) : D une seule fois, sous le
    /// premier parent. L'ancien arbre le répétait sous chacun, sous-arbre
    /// compris — 1 873 lignes pour 125 dépendances sur le parc.
    @Test func diamondShowsSharedNodeOnce() {
        let d = mod("D")
        let b = mod("B", deps: [req("D")])
        let c = mod("C", deps: [req("D")])
        let a = mod("A", deps: [req("B"), req("C")])
        let tree = DependencyTreeBuilder.build(a.dependencies, resolve: resolver([a, b, c, d]))
        #expect(tree.map(\.uniqueId) == ["B", "C"])
        #expect(tree[0].children.map(\.uniqueId) == ["D"])
        #expect(tree[1].children.isEmpty)
    }
    /// Une dépendance directe, aussi atteinte par une autre : elle reste à la
    /// racine (le moins profond gagne), pas sous l'autre.
    @Test func directDependencyWinsOverNestedOccurrence() {
        let cp = mod("CP")
        let x = mod("X", deps: [req("CP")])
        let a = mod("A", deps: [req("X"), req("CP")])
        let tree = DependencyTreeBuilder.build(a.dependencies, resolve: resolver([a, x, cp]))
        #expect(tree.map(\.uniqueId) == ["X", "CP"])
        #expect(tree[0].children.isEmpty)
    }
    /// Optionnelle pour le mod, requise par une autre de ses dépendances :
    /// elle s'affiche « Requis ». Le cas voisin, optionnelle partout, reste
    /// optionnelle.
    @Test func requiredWhenAnyOccurrenceRequiresIt() {
        let d = mod("D")
        let e = mod("E")
        let b = mod("B", deps: [req("D"), ModDependency(uniqueId: "E", isRequired: false)])
        let a = mod("A", deps: [ModDependency(uniqueId: "D", isRequired: false), req("B"),
                                ModDependency(uniqueId: "E", isRequired: false)])
        let tree = DependencyTreeBuilder.build(a.dependencies, resolve: resolver([a, b, d, e]))
        #expect(tree.first { $0.uniqueId == "D" }?.isRequired == true)
        #expect(tree.first { $0.uniqueId == "E" }?.isRequired == false)
    }
    /// Le mod lui-même (ou un composant de son pack) n'est jamais sa propre
    /// dépendance : un cycle vers la racine s'arrête là.
    @Test func ownIdsAreExcluded() {
        let a = mod("A", deps: [req("B")])
        let b = mod("B", deps: [req("a")])
        let tree = DependencyTreeBuilder.build(a.dependencies, excluding: ["A"], resolve: resolver([a, b]))
        #expect(tree.map(\.uniqueId) == ["B"])
        #expect(tree[0].children.isEmpty)
    }
    /// Identifiants distincts partout : `ForEach` ne confond jamais deux lignes.
    @Test func nodeIdsAreUnique() {
        let d = mod("D")
        let b = mod("B", deps: [req("D")])
        let c = mod("C", deps: [req("D"), req("B")])
        let a = mod("A", deps: [req("B"), req("C")])
        let tree = DependencyTreeBuilder.build(a.dependencies, resolve: resolver([a, b, c, d]))
        func ids(_ n: [DependencyNode]) -> [String] { n.flatMap { [$0.id] + ids($0.children) } }
        let all = ids(tree)
        #expect(all.count == 3)
        #expect(Set(all).count == all.count)
    }
    @Test func statusReflectsEnabledState() {
        let b = mod("B", enabled: false)
        let a = mod("A", deps: [req("B")])
        let tree = DependencyTreeBuilder.build(a.dependencies, resolve: resolver([a, b]))
        if case .disabled(let m) = tree[0].status { #expect(m.uniqueId == "B") }
        else { Issue.record("expected .disabled") }
    }
    @Test func requiredFlagPreserved() {
        let a = mod("A", deps: [ModDependency(uniqueId: "B", isRequired: false)])
        let b = mod("B")
        let tree = DependencyTreeBuilder.build(a.dependencies, resolve: resolver([a, b]))
        #expect(tree[0].isRequired == false)
    }
    @Test func emptyDepsYieldEmptyTree() {
        #expect(DependencyTreeBuilder.build([], resolve: resolver([])).isEmpty)
    }
}
