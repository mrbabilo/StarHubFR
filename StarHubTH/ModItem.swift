import Foundation

public struct ModDependency: Equatable, Sendable {
    public let uniqueId: String
    public let isRequired: Bool

    public init(uniqueId: String, isRequired: Bool) {
        self.uniqueId = uniqueId
        self.isRequired = isRequired
    }
}

public struct ModItem: Identifiable, Equatable, Sendable {
    public var id: String { folderName }
    public let uniqueId: String
    public let name: String
    public let folderName: String
    /// On-disk folder name within `Mods/`: a leading `.` is prepended when the
    /// mod is disabled (SMAPI ignores `.X` folders, so a same-parent rename is
    /// an atomic enable/disable toggle). `folderName` itself stays **logical**
    /// (never dotted) because it is the key for the install registry, profiles,
    /// activation timestamps and backups — those maps never migrate.
    public var physicalFolderName: String {
        (isEnabled ? "" : ".") + folderName
    }
    public let version: String
    public let author: String
    public let description: String
    public let nexusUrl: String
    /// Numeric Nexus Mods mod id parsed from `UpdateKeys: ["nexus:191"]` in the
    /// mod manifest. Empty when the mod doesn't declare a Nexus update key.
    public let nexusModId: String
    /// `UpdateKeys` bruts du manifest (`["Nexus:191", "GitHub:auteur/mod"]`,
    /// etc.) — ce que smapi.io compare lui-même. Vide quand le manifest n'en
    /// déclare aucune.
    public let updateKeys: [String]
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
    /// SMAPI i18n language codes the mod ships (from its `i18n/<code>.json`
    /// files, `default.json` excluded), detected at scan time. Lowercased and
    /// sorted; for a pack (group) it's the union across children. Empty when the
    /// mod has no `i18n` folder or wasn't constructed with it (test helpers).
    public let languages: [String]

    public init(
        uniqueId: String,
        name: String,
        folderName: String,
        version: String,
        author: String,
        description: String,
        nexusUrl: String,
        nexusModId: String,
        updateKeys: [String] = [],
        isEnabled: Bool,
        dependencies: [ModDependency],
        children: [ModItem]? = nil,
        isGroup: Bool = false,
        installedFileDate: Date? = nil,
        hasConfigFile: Bool = false,
        languages: [String] = []
    ) {
        self.uniqueId = uniqueId
        self.name = name
        self.folderName = folderName
        self.version = version
        self.author = author
        self.description = description
        self.nexusUrl = nexusUrl
        self.nexusModId = nexusModId
        self.updateKeys = updateKeys
        self.isEnabled = isEnabled
        self.dependencies = dependencies
        self.children = children
        self.isGroup = isGroup
        self.installedFileDate = installedFileDate
        self.hasConfigFile = hasConfigFile
        self.languages = languages
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

extension Array where Element == ModItem {
    /// Les mods individuels : un pack est remplacé par ses composants, un mod
    /// autonome se représente lui-même.
    ///
    /// Ce dépliage était réécrit à la main **22 fois** dans 10 fichiers au
    /// 2026-08-01, sous des formes voisines mais pas identiques — le terrain
    /// exact sur lequel ce dépôt a déjà produit des listes divergentes. Une
    /// seule définition, testée, plutôt que vingt-deux relectures.
    var flattenedMods: [ModItem] {
        flatMap { $0.isGroup ? ($0.children ?? []) : [$0] }
    }

    /// Les identifiants uniques des mods **activés**, ceux qu'un profil retient.
    /// Les identifiants vides sont écartés : un manifeste sans `UniqueID` ne
    /// peut être retrouvé par personne, et l'en-tête d'un pack n'en porte pas.
    var enabledUniqueIds: [String] {
        flattenedMods.filter(\.isEnabled).map(\.uniqueId).filter { !$0.isEmpty }
    }

    /// Tous les identifiants uniques présents, activés ou non — ce qui permet de
    /// dire d'un profil qu'il réclame un mod qui n'est plus installé.
    var allUniqueIds: Set<String> {
        Set(flattenedMods.map(\.uniqueId).filter { !$0.isEmpty })
    }
}
