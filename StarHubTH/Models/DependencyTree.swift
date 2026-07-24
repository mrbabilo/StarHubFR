import Foundation

/// Resolution state of a single dependency against the installed mod set.
enum DependencyStatus: Equatable {
    case active            // installed AND enabled
    case disabled(ModItem) // installed but currently disabled
    case missing           // not installed at all
}

/// One node in a mod's dependency tree. `Identifiable` (never `Hashable` —
/// `ModItem` is only `Equatable`); `id` encodes the path so a shared dependency
/// reached via two parents (a diamond) has two distinct rows.
struct DependencyNode: Identifiable {
    let id: String
    let uniqueId: String
    let isRequired: Bool
    let status: DependencyStatus
    let resolved: ModItem?          // nil when `.missing`
    let children: [DependencyNode]  // empty when `.missing` / cycle-cut / leaf
}

/// Pure, recursive builder — no ViewModel dependency, so it unit-tests with a
/// plain resolver closure. `resolve` maps a `uniqueId` to the installed mod, its
/// enabled state, and its OWN dependency list (or `nil` when not installed).
enum DependencyTreeBuilder {
    static func build(
        _ deps: [ModDependency],
        resolve: (String) -> (mod: ModItem, isEnabled: Bool, deps: [ModDependency])?
    ) -> [DependencyNode] {
        build(deps, ancestors: [], pathPrefix: "", resolve: resolve)
    }

    private static func build(
        _ deps: [ModDependency],
        ancestors: Set<String>,
        pathPrefix: String,
        resolve: (String) -> (mod: ModItem, isEnabled: Bool, deps: [ModDependency])?
    ) -> [DependencyNode] {
        deps.compactMap { dep -> DependencyNode? in
            let key = dep.uniqueId.lowercased()
            // Path-based cycle guard: if this dependency already appears in the
            // ancestor chain, it's a back-edge — drop it entirely rather than
            // re-rendering the cycle. A diamond (same id via two *different*
            // parents) is NOT an ancestor, so it still appears under each parent.
            if ancestors.contains(key) { return nil }
            let nodeId = pathPrefix + "/" + key
            let resolved = resolve(dep.uniqueId)
            let status: DependencyStatus
            var children: [DependencyNode] = []
            if let r = resolved {
                status = r.isEnabled ? .active : .disabled(r.mod)
                children = build(r.deps,
                                 ancestors: ancestors.union([key]),
                                 pathPrefix: nodeId,
                                 resolve: resolve)
            } else {
                status = .missing
            }
            return DependencyNode(id: nodeId, uniqueId: dep.uniqueId, isRequired: dep.isRequired,
                                  status: status, resolved: resolved?.mod, children: children)
        }
    }
}
