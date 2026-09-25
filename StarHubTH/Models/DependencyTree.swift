import Foundation

/// Resolution state of a single dependency against the installed mod set.
enum DependencyStatus: Equatable {
    case active            // installed AND enabled
    case disabled(ModItem) // installed but currently disabled
    case missing           // not installed at all
}

/// One node in a mod's dependency tree. `Identifiable` (never `Hashable` —
/// `ModItem` is only `Equatable`); `id` is the node's path from the root.
struct DependencyNode: Identifiable {
    let id: String
    let uniqueId: String
    let isRequired: Bool
    let status: DependencyStatus
    let resolved: ModItem?          // nil when `.missing`
    let children: [DependencyNode]  // empty when `.missing` / already shown / leaf
}

/// Pure builder — no ViewModel dependency, so it unit-tests with a plain
/// resolver closure. `resolve` maps a `uniqueId` to the installed mod, its
/// enabled state, and its OWN dependency list (or `nil` when not installed).
///
/// **Each dependency appears once**, at its shallowest depth (breadth-first:
/// a direct dependency wins over the same one reached through another). The
/// old path-based tree repeated every shared dependency with its whole
/// subtree under each parent: measured on the reference parc (2026-09-25),
/// 415 of 857 mods with dependencies showed duplicates, the worst 1 873 rows
/// for 125 distinct dependencies. A dependency is **required** when any
/// occurrence requires it — an optional one also required by another member
/// of the tree would otherwise read « Optionnel » and hide a real need.
/// `excluding`: the mod's own ids (a pack's components), never shown as its
/// dependencies — they also cut cycles back to the root.
enum DependencyTreeBuilder {
    static func build(
        _ deps: [ModDependency],
        excluding own: [String] = [],
        resolve: (String) -> (mod: ModItem, isEnabled: Bool, deps: [ModDependency])?
    ) -> [DependencyNode] {
        struct Placed {
            let uniqueId: String
            let path: String
            let resolved: (mod: ModItem, isEnabled: Bool, deps: [ModDependency])?
            var childKeys: [String] = []
        }
        var placed: [String: Placed] = [:]
        var required: Set<String> = []
        let excluded = Set(own.map { $0.lowercased() })
        var rootKeys: [String] = []
        // Breadth-first frontier: (dependency, parent key or nil for roots).
        var frontier: [(ModDependency, String?)] = deps.map { ($0, nil) }
        while !frontier.isEmpty {
            var next: [(ModDependency, String?)] = []
            for (dep, parentKey) in frontier {
                let key = dep.uniqueId.lowercased()
                guard !key.isEmpty, !excluded.contains(key) else { continue }
                if dep.isRequired { required.insert(key) }
                guard placed[key] == nil else { continue }
                let parentPath = parentKey.flatMap { placed[$0]?.path } ?? ""
                let resolved = resolve(dep.uniqueId)
                placed[key] = Placed(uniqueId: dep.uniqueId, path: parentPath + "/" + key,
                                     resolved: resolved)
                if let parentKey { placed[parentKey]?.childKeys.append(key) } else { rootKeys.append(key) }
                for child in resolved?.deps ?? [] { next.append((child, key)) }
            }
            frontier = next
        }

        func node(_ key: String) -> DependencyNode? {
            guard let p = placed[key] else { return nil }
            let status: DependencyStatus
            if let r = p.resolved { status = r.isEnabled ? .active : .disabled(r.mod) } else { status = .missing }
            return DependencyNode(id: p.path, uniqueId: p.uniqueId, isRequired: required.contains(key),
                                  status: status, resolved: p.resolved?.mod,
                                  children: p.childKeys.compactMap(node))
        }
        return rootKeys.compactMap(node)
    }
}
