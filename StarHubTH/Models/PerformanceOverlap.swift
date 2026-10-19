import Foundation

/// Deux mods de performance qui patchent les mêmes méthodes (A5-T7, marche 1).
///
/// **Un recouvrement n'est pas un conflit.** Deux préfixes de culling
/// s'empilent souvent sans dommage : le message dit « ces deux mods font en
/// partie le même travail », jamais « ils sont incompatibles ». C'est aussi
/// pourquoi rien ici n'alimente la pastille « Alertes système » — une pastille
/// sur un parc sain apprend à l'ignorer.
///
/// La table est tenue à la main, chaque paire **mesurée par décompilation**
/// (ilspycmd ; dernière remesure le 2026-10-19 sur les versions du parc :
/// UltraSmooth 2.6.2, Radiance 2.3.4, Stardropium 0.3.0 — détail dans
/// `docs/audit-ultrasmooth-2.6.2.md` ; la première mesure du 2026-09-26
/// portait 2.4.1 / 2.2.1 / 0.2.0-beta) :
/// une méthode compte quand les deux DLL posent un `harmony.Patch` dessus,
/// **y compris par balayage dynamique des assemblies** (`Monster.update` est
/// posée ainsi par UltraSmooth comme par StardewOptimizer — noté « balayage
/// dynamique » dans les listes, invisible à la seule lecture des appels
/// nommés), et y compris quand le type visé vient d'une variable
/// (`AccessTools.TypeByName`, code de SpaceCore, de TMXTile ou de Farm Type
/// Manager) : le relevé par `typeof(...)` seul les avait manqués jusqu'au
/// 2026-10-19. Les noms suivent le format court de la carte de la sonde
/// (`ProbeHarmonyMap.shortName`). La comparaison porte sur `Type.méthode`
/// sans les surcharges — « même nom de méthode », pas forcément même
/// signature. Les paires à une
/// seule méthode (`ScreenFade.UpdateFadeAlpha`, `Town.getMapLoader`,
/// `Debris.updateChunks`, et StardewOptimizer × Stardropium sur
/// `NPC.update`) sont écartées comme bruit.
///
/// La clé est l'`UniqueID`, pas le `folderName` de `ModConflictPair` : un nom
/// de dossier change d'un parc à l'autre, l'identifiant du manifeste non.
public struct PerformanceOverlap: Equatable, Sendable {
    public struct Member: Equatable, Sendable {
        public let uniqueId: String
        /// La version décompilée, ou mesurée en jeu (carte de la sonde) : une
        /// autre version installée peut avoir ajouté ou retiré des patches,
        /// l'écran le dit.
        public let measuredVersion: String
        /// Le nom de l'assembly du mod, pour reconnaître dans la carte les
        /// méthodes qu'un autre mod patche **dans son code**. Relevé dans les
        /// DLL le 2026-09-26.
        public var assemblyName: String? = nil
    }

    /// Un mod qui patche des méthodes déclarées dans le code de l'autre
    /// (Loading Optimizer → `ModEntry.OnGameLaunched` de SinZ : c'est sa
    /// neutralisation).
    public struct CodePatch: Equatable, Sendable {
        public let patcher: String
        public let patched: String
        public let methods: [String]
    }

    public let first: Member
    public let second: Member
    /// Patchées par les deux mods dans leur configuration par défaut.
    public let sharedMethods: [String]
    /// Patchées par l'un des deux seulement derrière une option désactivée
    /// par défaut (`conditionalOption`) : comptées à part, jamais dans le total.
    public let conditionalMethods: [String]
    public let conditionalOption: String?
    /// Date de capture de la carte de la sonde ; `nil` = paire décompilée.
    public var measuredAt: String? = nil
    /// Mesuré en jeu seulement : la carte voit un patch dans le code de l'autre.
    public var codePatches: [CodePatch] = []

    /// Clé stable et sans ordre, en minuscules : SMAPI compare les
    /// identifiants sans la casse.
    public var key: String {
        [first.uniqueId, second.uniqueId].map { $0.lowercased() }.sorted().joined(separator: "|")
    }

    public func member(_ uniqueId: String) -> Member? {
        if first.uniqueId.caseInsensitiveCompare(uniqueId) == .orderedSame { return first }
        if second.uniqueId.caseInsensitiveCompare(uniqueId) == .orderedSame { return second }
        return nil
    }

    public func other(than uniqueId: String) -> Member? {
        guard member(uniqueId) != nil else { return nil }
        return member(uniqueId) == first ? second : first
    }
}

extension PerformanceOverlap {
    private static let ultraSmooth = Member(uniqueId: "palmhacker13.UltraSmooth", measuredVersion: "2.6.2",
                                            assemblyName: "UltraSmooth")
    private static let stardropium = Member(uniqueId: "Arshia1381.Stardropium", measuredVersion: "0.3.0",
                                            assemblyName: "Stardropium")
    private static let radiance = Member(uniqueId: "phuicmt.SDVRadiance", measuredVersion: "2.3.4",
                                         assemblyName: "SDV-Radiance")
    private static let stardewOptimizer = Member(uniqueId: "baiyu.StardewOptimizer", measuredVersion: "3.0.3",
                                                 assemblyName: "StardewOptimizer")
    private static let speedySolutions = Member(uniqueId: "SinZ.SpeedySolutions", measuredVersion: "1.1.0",
                                                assemblyName: "SinZational Speedy Solutions")
    private static let loadingOptimizer = Member(uniqueId: "neoiw.StardewLoadingOptimizer", measuredVersion: "1.0.0",
                                                 assemblyName: "StardewLoadingOptimizer")

    /// Les paires mesurées. Ajouter une paire = la décompiler d'abord ; le
    /// relevé des sources (`check_sources.py`, les six mods y sont suivis)
    /// signale chaque nouvelle version, qui peut rendre une ligne fausse.
    public static let catalog: [PerformanceOverlap] = [
        PerformanceOverlap(
            first: stardropium, second: ultraSmooth,
            // UltraSmooth 2.4.15 : `ArgUtility.SplitBySpaceAndGet`,
            // `FishingRod.distanceToLand` et `ItemQueryResolver.TryResolve`
            // sont neuves depuis 2.4.1 ; `findPathForNPCSchedules` reste
            // hors conditionnelles (`EnableRouteCache` vrai par défaut).
            // `passTimeForObjects` n'est plus conditionnelle depuis
            // UltraSmooth 2.4.9 (`ClockTickOptimizer`, seul garde `EnableMod`) :
            // les deux mods y posent chacun un préfixe qui saute les objets
            // qu'ils jugent inertes — même passage de 10 minutes, deux règles.
            // Remesure 2026-10-19 (UltraSmooth 2.6.2, Stardropium 0.3.0) : cinq
            // méthodes hors du jeu, typées par `TypeByName`, manquaient. Deux
            // touchent l'écriture de la partie : la traversée SpaceCore
            // (`FindAndRemoveModNodes`, partagée depuis UltraSmooth 2.4.9) et
            // l'itérateur `SaveGame.getSaveEnumerator` (UltraSmooth agrandit le
            // tampon que Stardropium rend réutilisable). Puis les deux setters
            // TMXTile du chargement de carte, et l'index de cases de Farm Type
            // Manager (neuf côté UltraSmooth en 2.6.0, inerte sans FTM).
            sharedMethods: ["ArgUtility.SplitBySpaceAndGet", "Bush.draw", "FarmAnimal.draw",
                            "FishingRod.distanceToLand", "FruitTree.draw", "Furniture.draw",
                            "Game1.getTimeOfDayString", "GameLocation.passTimeForObjects",
                            "Grass.draw", "HoeDirt.draw", "ItemQueryResolver.TryResolve",
                            "LightSource.Draw", "ModEntry+Utility.GetTilesByProperty", "NPC.update",
                            "PathFindController.findPathForNPCSchedules",
                            "SaveGame+<getSaveEnumerator>d__94.MoveNext",
                            "SaveGamePatcher.FindAndRemoveModNodes", "TMXExtensions.SetFlip",
                            "TMXExtensions.SetRotationValue", "Tree.draw"],
            conditionalMethods: ["GameLocation.timeUpdate"],
            conditionalOption: "EnableExperimentalFeatures"),
        PerformanceOverlap(
            first: radiance, second: ultraSmooth,
            // `SpriteBatch.Draw` : neuve côté UltraSmooth 2.4.15 ; `Object.draw`
            // en 2.6.0 (culling des objets posés). Les autres ajouts du
            // 2026-10-19 sont des **balayages dynamiques** que la lecture des
            // appels nommés ne voyait pas : les deux mods parcourent les
            // sous-classes de `Critter` (abstraite) — `Critter.draw` et
            // `Critter.drawAboveFrontLayer` désignent leurs surcharges, onze
            // types de `BellsAndWhistles` (Radiance nomme `Cloud` à part) ;
            // UltraSmooth parcourt les monstres
            // (`Bat.drawAboveAllLayers`, nommée chez Radiance) et les
            // personnages (`Junimo.draw`, `JunimoHarvester.draw`, que Radiance
            // couvre par sa liste des personnages à ombre propre).
            sharedMethods: ["Bat.drawAboveAllLayers", "Bush.draw", "Critter.draw",
                            "Critter.drawAboveFrontLayer", "Game1.drawMouseCursor",
                            "GameLocation.updateWater", "Grass.draw", "Junimo.draw",
                            "JunimoHarvester.draw", "Object.draw", "SpriteBatch.Draw",
                            "TemporaryAnimatedSprite.update", "Tree.draw"],
            conditionalMethods: [], conditionalOption: nil),
        // StardewOptimizer 1.0.0 (A5-T10) : `Monster.update` est posée par
        // **balayage dynamique** des deux côtés — UltraSmooth depuis 2.4.8
        // (`PatchMonsterUpdateMethods`), StardewOptimizer dans
        // `MonsterAiThrottleModule`. La 3.0.3 (2026-10-14,
        // `docs/audit-stardewoptimizer-3.0.3.md`) ajoute `Debris.updateChunks`,
        // `Furniture.draw`, `GameLocation.updateWater` et `GameMenu.changeTab`.
        // `MachineGroup.Automate` (code d'Automate) : UltraSmooth la patche par
        // défaut (`AutomateHibernateOptimizer` ; la `MachineGroup.Tick` qu'il
        // cherche d'abord n'existe pas), StardewOptimizer derrière
        // `AutomateThrottle` (repli faute de cible dans `MachineManager`) et
        // `AutomateZoneThrottle`, tous deux éteints par défaut en 3.0.3.
        PerformanceOverlap(
            first: stardewOptimizer, second: ultraSmooth,
            sharedMethods: ["Debris.updateChunks", "Furniture.draw", "GameLocation.DayUpdate",
                            "GameLocation.updateWater", "GameMenu.changeTab", "Monster.update",
                            "NPC.update", "TemporaryAnimatedSprite.draw"],
            conditionalMethods: ["MachineGroup.Automate"], conditionalOption: "AutomateThrottle"),
        // `Furniture.draw` (3.0.3, `FurnitureDrawThrottle`, actif par défaut)
        // rejoint `NPC.update` : la paire n'est plus du bruit. Avec Radiance,
        // `GameLocation.updateWater` seule en reste un.
        PerformanceOverlap(
            first: stardropium, second: stardewOptimizer,
            sharedMethods: ["Furniture.draw", "NPC.update"],
            conditionalMethods: [], conditionalOption: nil),
        PerformanceOverlap(
            first: radiance, second: stardropium,
            sharedMethods: ["Bush.draw", "Grass.draw", "Layer.Draw", "Tree.draw"],
            conditionalMethods: [], conditionalOption: nil),
        // `LoadRawImageData` est une méthode de SMAPI, pas du jeu : les deux
        // mods y greffent chacun leur cache d'images décodées.
        PerformanceOverlap(
            first: speedySolutions, second: loadingOptimizer,
            sharedMethods: ["ModContentManager.LoadRawImageData", "TMXFormat.Load"],
            conditionalMethods: [], conditionalOption: nil),
        // Stardropium patche aussi le postfix de SinZ lui-même : il ne fait pas
        // seulement le même travail, il modifie le code de l'autre.
        PerformanceOverlap(
            first: speedySolutions, second: stardropium,
            sharedMethods: ["ModContentManager.LoadRawImageData",
                            "ModImageCache.ModContentManager__LoadRawImageData__Postfix"],
            conditionalMethods: [], conditionalOption: nil),
        PerformanceOverlap(
            first: loadingOptimizer, second: stardropium,
            sharedMethods: ["GameLocation.loadMap", "ModContentManager.LoadRawImageData"],
            conditionalMethods: [], conditionalOption: nil),
    ]
}

/// Une paire du catalogue retrouvée sur le parc.
public struct PerformanceOverlapMatch: Equatable, Sendable {
    public let overlap: PerformanceOverlap
    public let firstMod: ModItem
    public let secondMod: ModItem

    public var bothEnabled: Bool { firstMod.isEnabled && secondMod.isEnabled }

    /// Le mod de la paire qui n'est pas `folderName`.
    public func partner(of folderName: String) -> ModItem? {
        if firstMod.folderName == folderName { return secondMod }
        if secondMod.folderName == folderName { return firstMod }
        return nil
    }

    /// La version installée diffère de la version décompilée ou mesurée —
    /// en sémantique : la carte écrit `1.3.0` pour un manifeste `1.3`.
    public func isRemeasureNeeded(for mod: ModItem) -> Bool {
        guard let member = overlap.member(mod.uniqueId) else { return false }
        return NexusUpdateChecker.compare(member.measuredVersion, mod.version) != .orderedSame
    }
}

public enum PerformanceOverlapResolver {
    /// Les paires du catalogue dont les deux mods sont installés, actifs ou
    /// non. `mods` doit être le parc **aplati** (`flattenedMods`). Un
    /// identifiant installé deux fois garde l'exemplaire actif : c'est lui que
    /// SMAPI charge.
    public static func matches(in mods: [ModItem],
                               catalog: [PerformanceOverlap] = PerformanceOverlap.catalog) -> [PerformanceOverlapMatch] {
        var byId: [String: ModItem] = [:]
        for mod in mods where !mod.uniqueId.isEmpty {
            let id = mod.uniqueId.lowercased()
            if let existing = byId[id], existing.isEnabled || !mod.isEnabled { continue }
            byId[id] = mod
        }
        return catalog.compactMap { overlap in
            guard let a = byId[overlap.first.uniqueId.lowercased()],
                  let b = byId[overlap.second.uniqueId.lowercased()] else { return nil }
            return PerformanceOverlapMatch(overlap: overlap, firstMod: a, secondMod: b)
        }
    }
}

/// Les paires que l'utilisateur a écartées, sérialisées dans une seule chaîne
/// `UserDefaults` (`@AppStorage` la partage entre la fiche et le panorama sans
/// passer par le ViewModel). Une clé par ligne : `PerformanceOverlap.key` ne
/// contient jamais de saut de ligne.
public enum PerformanceOverlapDismissals {
    public static func decode(_ raw: String) -> Set<String> {
        Set(raw.split(whereSeparator: \.isNewline).map(String.init))
    }

    public static func encode(_ keys: Set<String>) -> String {
        keys.sorted().joined(separator: "\n")
    }

    public static func dismissing(_ key: String, in raw: String) -> String {
        encode(decode(raw).union([key]))
    }
}
