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
    /// `true` quand ce mod est un **composant** d'un pack : son dossier vit
    /// dans celui d'un autre, et `folderName` porte alors le chemin relatif
    /// (`MonPack/SonComposant`).
    ///
    /// Ce que ça change : le nom d'un composant n'a le plus souvent jamais été
    /// un titre Nexus. Mesuré sur le parc, **20 des 55 mods introuvables par
    /// leur nom sont des composants** — « ARV- Maximum » ne peut pas aboutir,
    /// c'est le pack « Always Raining in the Valley » qui a une page.
    public var isPackComponent: Bool { folderName.contains("/") }

    /// La date d'installation à **montrer et à trier** : la sienne, ou — pour
    /// un en-tête de pack, fabriqué sans date propre — la plus récente de ses
    /// composants.
    ///
    /// La règle vivait en deux exemplaires (le tri de `ModListView`, le
    /// ViewModel) et la rangée n'en utilisait aucun : elle lisait
    /// `installedFileDate` brut, si bien qu'un pack laissait son créneau de
    /// date vide au milieu de voisins qui en montraient une.
    public var effectiveInstallDate: Date? {
        if let installedFileDate { return installedFileDate }
        guard isGroup, let children, !children.isEmpty else { return nil }
        return children.compactMap { $0.installedFileDate }.max()
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

    /// Les noms de dossier sur lesquels une **préférence** peut être posée :
    /// les composants **et** les en-têtes de packs (X74).
    ///
    /// `flattenedMods` remplace un pack par ses composants — c'est ce qu'il
    /// faut pour juger d'une identité, un en-tête n'en ayant pas. Mais une
    /// préférence ne se pose pas sur une identité : elle se pose sur la
    /// **ligne** que l'utilisateur a sous les yeux, et cette ligne est un
    /// en-tête de pack aussi souvent qu'un mod simple. L'identifiant Nexus est
    /// le cas exemplaire : c'est le pack qui a une page, jamais ses
    /// composants — 20 des 55 mods introuvables par leur nom sont des
    /// composants. La catégorie et l'horodatage d'activation se posent
    /// pareillement sur la ligne de tête.
    ///
    /// Juger les clés sur `flattenedMods` seul déclarait donc mortes les
    /// préférences d'un pack **installé**, et le bouton « nettoyer » les
    /// effaçait — avec, par la règle de préfixe de `ModRemovalPurge`, celles
    /// de ses composants.
    var preferenceKeyableFolders: Set<String> {
        var folders = Set(flattenedMods.map(\.folderName))
        folders.formUnion(map(\.folderName))
        folders.remove("")
        return folders
    }

    /// L'ordre de la liste des mods : alphabétique sur le nom, **packs et mods
    /// simples mêlés**. Le tri d'origine faisait passer tous les packs en tête
    /// (retour du 2026-08-26 : chercher un nom dans la liste ne doit pas
    /// dépendre de la nature pack ou non du mod). Les enfants d'un pack vivent
    /// dans sa ligne, l'imbrication ne peut donc rien orphaniser.
    ///
    /// La comparaison est celle de **macOS**, pas celle des scalaires Unicode
    /// (X73). `lowercased() <` compare octet à octet : `*` (U+002A), les
    /// chiffres et `[` (U+005B) se rangent dans un ordre qui n'est celui de
    /// personne, et l'apostrophe sépare deux mods du même auteur
    /// (`Nyapu's …` loin de `Nyapu-Style …`). Surtout, c'est déjà la règle des
    /// six autres tris de la liste et de « Nom (Z→A) » : sans elle, les deux
    /// sens du tri par nom n'étaient pas inverses l'un de l'autre — **190 des
    /// 951 noms du parc** changeaient de place.
    var alphabeticalListOrder: [ModItem] {
        sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    /// Le mod installé qui porte cet `UniqueID`, **composants de packs
    /// compris** — un mod de premier niveau d'abord, puis les composants.
    ///
    /// La comparaison est insensible à la casse, comme SMAPI, et les
    /// identifiants vides sont écartés : l'en-tête d'un pack n'en porte pas,
    /// et 111 mods du parc n'en déclarent aucun (les apparier tous entre eux
    /// serait pire que ne rien trouver).
    ///
    /// Cette règle existait déjà dans `ModZipInstaller.findExistingMod`, mais
    /// pas dans les vues, qui cherchaient dans les seules lignes de premier
    /// niveau. Mesuré sur le parc : **296 déclarations de dépendances** (109
    /// identifiants distincts) désignent un mod installé **en composant de
    /// pack** — `FlashShifter.SVE-FTM`, `Rafseazz.RSVCC`… — et étaient donc
    /// annoncées manquantes alors qu'elles sont là.
    /// **Deux passes, et non une** : la préférence pour la ligne de premier
    /// niveau ne peut pas dépendre de l'ordre du tableau. Une passe unique qui
    /// teste chaque entrée puis ses composants rend le composant dès que son
    /// pack précède le mod autonome — et l'ordre vient de l'énumération de
    /// `Mods/`, qui n'en garantit aucun. Cas réel du parc : le mod de tête
    /// `.SexyCombatIdols` (v1.1.1) et le composant
    /// `.SexyCombatIdolsNEW/SexyCombatIdols` (v1.2.0) partagent
    /// `schulz.SexyCombatIdols`.
    func mod(withUniqueId uniqueId: String) -> ModItem? {
        guard !uniqueId.isEmpty else { return nil }
        func matches(_ mod: ModItem) -> Bool {
            !mod.uniqueId.isEmpty
                && mod.uniqueId.caseInsensitiveCompare(uniqueId) == .orderedSame
        }
        if let top = first(where: matches) { return top }
        for mod in self {
            if let child = mod.children?.first(where: matches) { return child }
        }
        return nil
    }
}
