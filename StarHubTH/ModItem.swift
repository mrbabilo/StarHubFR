import Foundation

public struct ModDependency: Equatable {
    public let uniqueId: String
    public let isRequired: Bool

    public init(uniqueId: String, isRequired: Bool) {
        self.uniqueId = uniqueId
        self.isRequired = isRequired
    }
}

public struct ModItem: Identifiable, Equatable {
    public var id: String { folderName }
    public let uniqueId: String
    public let name: String
    public let folderName: String
    public let version: String
    public let author: String
    public let description: String
    public let nexusUrl: String
    /// Numeric Nexus Mods mod id parsed from `UpdateKeys: ["nexus:191"]` in the
    /// mod manifest. Empty when the mod doesn't declare a Nexus update key.
    public let nexusModId: String
    public var isEnabled: Bool
    public let dependencies: [ModDependency]
    public var children: [ModItem]?
    public var isGroup: Bool = false
    /// Content-modification date of the mod's `manifest.json` on disk, captured
    /// at scan time. Used to detect same-version updates: when the installed
    /// version equals the Nexus latest but the Nexus upload is newer than this
    /// file, the installed copy is stale and an update is offered. `nil` for
    /// group headers and when the date can't be read.
    public var installedFileDate: Date? = nil

    public init(
        uniqueId: String,
        name: String,
        folderName: String,
        version: String,
        author: String,
        description: String,
        nexusUrl: String,
        nexusModId: String,
        isEnabled: Bool,
        dependencies: [ModDependency],
        children: [ModItem]? = nil,
        isGroup: Bool = false,
        installedFileDate: Date? = nil
    ) {
        self.uniqueId = uniqueId
        self.name = name
        self.folderName = folderName
        self.version = version
        self.author = author
        self.description = description
        self.nexusUrl = nexusUrl
        self.nexusModId = nexusModId
        self.isEnabled = isEnabled
        self.dependencies = dependencies
        self.children = children
        self.isGroup = isGroup
        self.installedFileDate = installedFileDate
    }
}
