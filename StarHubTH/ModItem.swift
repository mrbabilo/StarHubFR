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
    /// Whether the mod's own folder contains a `config.json`, captured at
    /// scan time. `false` for group headers (a pack's own folder never has
    /// one — only its children might) and for anything constructed without
    /// passing it explicitly (e.g. existing test helpers). Backs both the
    /// "with configuration" list filter and the per-row config-editor icon
    /// in `ModListView`.
    public let hasConfigFile: Bool

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
        installedFileDate: Date? = nil,
        hasConfigFile: Bool = false
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
        self.hasConfigFile = hasConfigFile
    }
}

extension ModItem {
    /// Infers an offline "type" category from the mod's manifest fields. Stable
    /// English keys; display is localized via L10n.ModTag. Ported from upstream.
    static func inferTag(name: String, uniqueId: String, description: String) -> String {
        let haystack = "\(name) \(uniqueId) \(description)".lowercased()
        let matchWord = { (word: String) -> Bool in
            haystack.range(of: "\\b\(word)\\b", options: .regularExpression) != nil
        }
        if matchWord("translation") || matchWord("language") || matchWord("locale") || matchWord("thai") || matchWord("i18n") || matchWord("spanish") || matchWord("chinese") || matchWord("korean") || matchWord("french") || matchWord("russian") || matchWord("german") {
            return "Translation"
        }
        if matchWord("framework") || matchWord("api") || matchWord("library") || matchWord("core") || matchWord("toolkit") || matchWord("util") || matchWord("utility") || haystack.contains("smapi") || (haystack.contains("spacechase") && haystack.contains("core")) {
            return "Framework"
        }
        if haystack.contains("content patcher") || uniqueId.lowercased().hasPrefix("pathoschild.contentpatcher") || matchWord("cp") {
            return "Content Patcher"
        }
        if matchWord("ui") || matchWord("interface") || matchWord("hud") || matchWord("menu") || matchWord("inventory") || matchWord("tooltip") || matchWord("display") || matchWord("cursor") || matchWord("minimap") {
            return "UI"
        }
        if matchWord("cosmetic") || matchWord("portrait") || matchWord("portraits") || matchWord("sprite") || matchWord("sprites") || matchWord("retexture") || matchWord("skin") || matchWord("hair") || matchWord("fashion") || matchWord("visual") || matchWord("texture") || matchWord("textures") || matchWord("recolor") || matchWord("appearance") || matchWord("clothes") || matchWord("shirt") || matchWord("hat") || matchWord("furniture") || matchWord("building") || matchWord("buildings") || matchWord("aesthetic") {
            return "Cosmetic"
        }
        if matchWord("npc") || matchWord("npcs") || matchWord("marriage") || matchWord("bachelor") || matchWord("bachelorette") || matchWord("villager") || matchWord("dialogue") || matchWord("dialogues") || matchWord("event") || matchWord("events") || matchWord("character") || matchWord("schedule") || matchWord("heart") {
            return "NPC"
        }
        if matchWord("music") || matchWord("audio") || matchWord("sound") || matchWord("sounds") || matchWord("ambient") || matchWord("bgm") || matchWord("voice") || matchWord("sfx") {
            return "Audio"
        }
        if matchWord("map") || matchWord("maps") || matchWord("location") || matchWord("locations") || matchWord("world") || matchWord("tile") || matchWord("tiles") || matchWord("expansion") || matchWord("dungeon") || matchWord("greenhouse") || matchWord("cave") || matchWord("caves") || matchWord("town") {
            return "Map"
        }
        if matchWord("cheat") || matchWord("time") || matchWord("speed") || matchWord("gameplay") || matchWord("harvest") || matchWord("farm") || matchWord("crop") || matchWord("crops") || matchWord("fishing") || matchWord("balance") || matchWord("combat") || matchWord("mining") || matchWord("foraging") || matchWord("animal") || matchWord("animals") || matchWord("pet") || matchWord("pets") || matchWord("economy") || matchWord("item") || matchWord("items") || matchWord("recipe") || matchWord("recipes") || matchWord("machine") || matchWord("machines") || matchWord("artisan") || matchWord("tool") || matchWord("tools") || matchWord("weapon") || matchWord("weapons") || matchWord("skill") || matchWord("skills") || matchWord("automate") || matchWord("automation") {
            return "Gameplay"
        }
        return "Other"
    }
}
