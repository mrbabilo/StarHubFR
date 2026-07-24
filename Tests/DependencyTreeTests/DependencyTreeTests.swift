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
    @Test func diamondShowsSharedNodeUnderBothParents() {
        let d = mod("D")
        let b = mod("B", deps: [req("D")])
        let c = mod("C", deps: [req("D")])
        let a = mod("A", deps: [req("B"), req("C")])
        let tree = DependencyTreeBuilder.build(a.dependencies, resolve: resolver([a, b, c, d]))
        #expect(tree[0].children[0].uniqueId == "D")
        #expect(tree[1].children[0].uniqueId == "D")
        #expect(tree[0].children[0].id != tree[1].children[0].id)
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
