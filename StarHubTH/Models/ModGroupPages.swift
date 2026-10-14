import Foundation

/// I-T21 lot 2 — la liste découpée en sections, puis en pages de `pageSize`
/// **places** : une ligne de mod en prend une, un groupe replié aussi (son
/// seul bandeau). Une section ouverte coupée par la page reprend en tête de
/// la suivante, marquée `continued`. Les mods d'une section repliée sortent
/// de l'ordre de navigation (donc de la sélection effective, I-T20).
public enum ModGrouping: String, CaseIterable, Sendable { case none, groups, category }

public enum ModSectionKey: Hashable, Sendable {
    case group(UUID), ungrouped, category(Int), uncategorized

    public var collapseKey: String {
        switch self {
        case .group(let id): return id.uuidString
        case .ungrouped: return "group:none"
        case .category(let id): return "category:\(id)"
        case .uncategorized: return "category:none"
        }
    }
}

public struct ModListSectionModel: Equatable, Sendable {
    public let key: ModSectionKey
    public let title: String?
    public let mods: [ModItem]
    public let collapsed: Bool
    public var pausedCount: Int { mods.filter { !$0.isEnabled }.count }
}

public struct ModListPageSection: Equatable, Sendable {
    public let section: ModListSectionModel
    public let mods: [ModItem]
    public let continued: Bool
}

public enum ModGroupPages {
    public static func sections(display: [ModItem], mode: ModGrouping, state: ModGroupsState,
                                category: (ModItem) -> (id: Int, name: String)?) -> [ModListSectionModel] {
        switch mode {
        case .none:
            return []   // la vue garde son rendu d'avant, sans sections
        case .groups:
            var byGroup: [UUID: [ModItem]] = [:]
            var ungrouped: [ModItem] = []
            for mod in display {
                if let id = state.group(of: mod.folderName)?.id { byGroup[id, default: []].append(mod) }
                else { ungrouped.append(mod) }
            }
            var out = state.groups.compactMap { group -> ModListSectionModel? in
                guard let mods = byGroup[group.id], !mods.isEmpty else { return nil }
                return ModListSectionModel(key: .group(group.id), title: group.name, mods: mods,
                                           collapsed: group.collapsed)
            }
            if !ungrouped.isEmpty {
                out.append(ModListSectionModel(key: .ungrouped, title: nil, mods: ungrouped,
                                               collapsed: state.collapsedCategories.contains("group:none")))
            }
            return out
        case .category:
            var byId: [Int: (name: String, mods: [ModItem])] = [:]
            var none: [ModItem] = []
            for mod in display {
                if let cat = category(mod) { byId[cat.id, default: (cat.name, [])].mods.append(mod) }
                else { none.append(mod) }
            }
            var out = byId.sorted { $0.value.name.localizedStandardCompare($1.value.name) == .orderedAscending }
                .map { id, entry in
                    ModListSectionModel(key: .category(id), title: entry.name, mods: entry.mods,
                                        collapsed: state.collapsedCategories.contains("category:\(id)"))
                }
            if !none.isEmpty {
                out.append(ModListSectionModel(key: .uncategorized, title: nil, mods: none,
                                               collapsed: state.collapsedCategories.contains("category:none")))
            }
            return out
        }
    }

    public static func pages(_ sections: [ModListSectionModel], pageSize: Int) -> [[ModListPageSection]] {
        guard pageSize > 0 else { return [] }
        var pages: [[ModListPageSection]] = []
        var current: [ModListPageSection] = []
        var used = 0
        func flush() { if !current.isEmpty { pages.append(current); current = []; used = 0 } }
        for section in sections {
            if section.collapsed {
                if used == pageSize { flush() }
                current.append(ModListPageSection(section: section, mods: [], continued: false))
                used += 1
                continue
            }
            var rest = section.mods[...]
            // Un tronçon ne s'arrête qu'en fin de page : le second tronçon d'une
            // section est donc toujours sur une page neuve. Une section qui
            // **commence** en tête de page n'est pas une suite.
            var emitted = false
            while !rest.isEmpty {
                if used == pageSize { flush() }
                let take = min(pageSize - used, rest.count)
                current.append(ModListPageSection(section: section, mods: Array(rest.prefix(take)),
                                                  continued: emitted))
                used += take
                rest = rest.dropFirst(take)
                emitted = true
            }
        }
        flush()
        return pages
    }

    public static func navigationOrder(_ sections: [ModListSectionModel]) -> [String] {
        sections.filter { !$0.collapsed }.flatMap { $0.mods.map(\.folderName) }
    }

    /// Les mods des pages qui précèdent `page` (1-based) : le début de la
    /// plage du pied, un bandeau replié ne portant aucun mod.
    public static func modsBefore(page: Int, in pages: [[ModListPageSection]]) -> Int {
        pages.prefix(max(0, page - 1)).joined().reduce(0) { $0 + $1.mods.count }
    }

    public static func page(of folder: String, in pages: [[ModListPageSection]]) -> Int? {
        pages.firstIndex { $0.contains { $0.mods.contains { $0.folderName == folder } } }.map { $0 + 1 }
    }
}
