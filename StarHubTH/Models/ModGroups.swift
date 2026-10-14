import Foundation

/// I-T21 lot 2 — un rangement à soi : groupes nommés, un seul par mod (clé
/// `folderName` logique, entrées de tête seules), ordre = rang. Un profil
/// décrit un état du parc, un groupe un rangement : rien ici n'active ni ne
/// met en pause.
public struct ModGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var collapsed: Bool
}

public struct ModGroupsState: Codable, Equatable, Sendable {
    public enum NameError: Error, Equatable, Sendable { case empty, taken }

    public private(set) var groups: [ModGroup] = []
    public private(set) var membership: [String: UUID] = [:]
    /// Clés `category:<id>` ou `category:none`.
    public private(set) var collapsedCategories: Set<String> = []

    public init() {}

    private func validated(_ raw: String, excluding id: UUID?) -> Result<String, NameError> {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.empty) }
        let taken = groups.contains { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }
        return taken ? .failure(.taken) : .success(name)
    }

    public mutating func createGroup(named raw: String) -> Result<UUID, NameError> {
        validated(raw, excluding: nil).map { name in
            let group = ModGroup(id: UUID(), name: name, collapsed: false)
            groups.append(group)
            return group.id
        }
    }

    public mutating func rename(_ id: UUID, to raw: String) -> NameError? {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return nil }
        switch validated(raw, excluding: id) {
        case .failure(let error): return error
        case .success(let name): groups[index].name = name; return nil
        }
    }

    public mutating func move(_ id: UUID, by offset: Int) {
        guard let from = groups.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(0, from + offset), groups.count - 1)
        guard to != from else { return }
        groups.insert(groups.remove(at: from), at: to)
    }

    public mutating func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        membership = membership.filter { $0.value != id }
    }

    public mutating func assign(_ folders: [String], to id: UUID?) {
        guard let id else { folders.forEach { membership[$0] = nil }; return }
        guard groups.contains(where: { $0.id == id }) else { return }
        folders.forEach { membership[$0] = id }
    }

    public mutating func setCollapsed(group id: UUID, _ value: Bool) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].collapsed = value
    }

    public mutating func setCollapsed(category key: String, _ value: Bool) {
        if value { collapsedCategories.insert(key) } else { collapsedCategories.remove(key) }
    }

    /// Le repli d'une section par sa clé : un groupe à soi le porte, les
    /// autres sections le gardent dans `collapsedCategories`.
    public mutating func setCollapsed(_ key: ModSectionKey, _ value: Bool) {
        if case .group(let id) = key { setCollapsed(group: id, value) }
        else { setCollapsed(category: key.collapseKey, value) }
    }

    /// Même règle que les favoris : `ModFolderRename.migrate` (copie quand
    /// l'ancien nom reste porté par un autre mod, clés `Pack/…` comprises).
    public mutating func migrate(from old: String, to new: String, shared: Bool) {
        ModFolderRename.migrate(&membership, from: old, to: new, shared: shared)
    }

    public mutating func purge(_ folder: String) { membership[folder] = nil }

    public func group(of folder: String) -> ModGroup? {
        membership[folder].flatMap { id in groups.first { $0.id == id } }
    }
}

// Décodage tolérant (Review Focus 4) : un fichier plus ancien se relit, champs
// absents à leur défaut. Un fichier d'un format plus récent refuse de se relire
// (`FutureFormat`) : relu sans ses champs, il serait réécrit amputé. En
// extension, pour garder l'initialiseur membre à membre dont `createGroup` a
// besoin.
extension ModGroup {
    private enum CodingKeys: String, CodingKey { case id, name, collapsed }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  name: try c.decode(String.self, forKey: .name),
                  collapsed: try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false)
    }
}

extension ModGroupsState {
    /// Le format que cette version sait relire sans rien perdre ; sans champ
    /// `version`, un fichier vaut 1.
    public static let formatVersion = 1

    public struct FutureFormat: Error, Equatable {
        public let version: Int
    }

    private enum CodingKeys: String, CodingKey { case version, groups, membership, collapsedCategories }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version <= Self.formatVersion else { throw FutureFormat(version: version) }
        self.init()
        groups = try c.decodeIfPresent([ModGroup].self, forKey: .groups) ?? []
        membership = try c.decodeIfPresent([String: UUID].self, forKey: .membership) ?? [:]
        collapsedCategories = try c.decodeIfPresent(Set<String>.self, forKey: .collapsedCategories) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.formatVersion, forKey: .version)
        try c.encode(groups, forKey: .groups)
        try c.encode(membership, forKey: .membership)
        try c.encode(collapsedCategories, forKey: .collapsedCategories)
    }
}

/// La feuille « Nouveau groupe / Renommer », portée par `ModListState` : un
/// menu contextuel se ferme avant de pouvoir présenter une feuille.
public enum ModGroupNameRequest: Identifiable, Equatable, Sendable {
    case create(folders: [String])
    case rename(UUID, current: String)

    public var id: String {
        switch self {
        case .create(let folders): return "create|" + folders.joined(separator: "|")
        case .rename(let id, _): return "rename|" + id.uuidString
        }
    }
}
