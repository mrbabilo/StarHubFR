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
/// (ilspycmd, 2026-09-26) : une méthode compte quand les deux DLL posent un
/// `harmony.Patch` dessus. La comparaison porte sur `Type.méthode` sans les
/// surcharges — « même nom de méthode », pas forcément même signature. Les
/// paires à une seule méthode (`ScreenFade.UpdateFadeAlpha`,
/// `Town.getMapLoader`, `Debris.updateChunks`) sont écartées comme bruit.
///
/// La clé est l'`UniqueID`, pas le `folderName` de `ModConflictPair` : un nom
/// de dossier change d'un parc à l'autre, l'identifiant du manifeste non.
public struct PerformanceOverlap: Equatable, Sendable {
    public struct Member: Equatable, Sendable {
        public let uniqueId: String
        /// La version décompilée : une autre version installée peut avoir
        /// ajouté ou retiré des patches, l'écran le dit.
        public let measuredVersion: String
    }

    public let first: Member
    public let second: Member
    /// Patchées par les deux mods dans leur configuration par défaut.
    public let sharedMethods: [String]
    /// Patchées par l'un des deux seulement derrière une option désactivée
    /// par défaut (`conditionalOption`) : comptées à part, jamais dans le total.
    public let conditionalMethods: [String]
    public let conditionalOption: String?

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
    private static let ultraSmooth = Member(uniqueId: "palmhacker13.UltraSmooth", measuredVersion: "2.3.7")
    private static let stardropium = Member(uniqueId: "Arshia1381.Stardropium", measuredVersion: "0.1.3-beta")
    private static let radiance = Member(uniqueId: "phuicmt.SDVRadiance", measuredVersion: "2.2.1")
    private static let speedySolutions = Member(uniqueId: "SinZ.SpeedySolutions", measuredVersion: "1.1.0")
    private static let loadingOptimizer = Member(uniqueId: "neoiw.StardewLoadingOptimizer", measuredVersion: "1.0.0")

    /// Les paires mesurées. Ajouter une paire = la décompiler d'abord ; le
    /// relevé des sources (`check_sources.py`) signale chaque nouvelle version
    /// de ces mods, qui peut rendre une ligne fausse.
    public static let catalog: [PerformanceOverlap] = [
        PerformanceOverlap(
            first: stardropium, second: ultraSmooth,
            sharedMethods: ["Bush.draw", "FarmAnimal.draw", "FruitTree.draw", "Furniture.draw",
                            "Game1.getTimeOfDayString", "Grass.draw", "HoeDirt.draw", "NPC.update",
                            "Tree.draw"],
            conditionalMethods: ["GameLocation.passTimeForObjects", "GameLocation.timeUpdate",
                                 "PathFindController.findPathForNPCSchedules"],
            conditionalOption: "EnableExperimentalFeatures"),
        PerformanceOverlap(
            first: radiance, second: ultraSmooth,
            sharedMethods: ["Bush.draw", "Game1.drawMouseCursor", "GameLocation.updateWater",
                            "Grass.draw", "TemporaryAnimatedSprite.update", "Tree.draw"],
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

    /// La version installée diffère de la version décompilée.
    public func isRemeasureNeeded(for mod: ModItem) -> Bool {
        guard let member = overlap.member(mod.uniqueId) else { return false }
        return member.measuredVersion != mod.version
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
