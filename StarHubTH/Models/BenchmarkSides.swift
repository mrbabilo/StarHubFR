import Foundation

/// Ce qui change entre les deux côtés d'un benchmark (spec §5).
public enum BenchmarkSideB: Equatable, Sendable {
    /// Dossier de **tête** (le point vit sur l'entrée de tête d'un pack).
    case pauseMod(folderName: String)
    case profile(enabledModIds: [String])
    /// B = A : mesurer le bruit.
    case sameState
}

public enum BenchmarkRefusal: Equatable, Sendable {
    case probeMissing
    case probeTooOld(String)
    case probeInSideB
    case dependents([String])
    case duplicateIds([String])
    case unknownMod
}

public enum BenchmarkSides {
    public static let probeId = "mrbabilo.StarHubFR.Probe"
    /// Nom fixe, identique en anglais et en français : le profil se retrouve
    /// par ce nom (celui de l'utilisateur, s'il en a déjà fait un, est repris tel quel).
    public static let minimalProfileName = "BENCHMARK"
    public static let minimalProfileIds = [probeId, "SMAPI.ConsoleCommands", "SMAPI.SaveBackup",
                                           "Pathoschild.SkipIntro"]
    /// Mods à cache disque connu : les basculer fait payer la reconstruction à
    /// chaque lancement d'un seul côté — la médiane bouge sans que l'écart
    /// interne grandisse (`observedNoisePercent` ne le voit pas).
    public static let cacheModIds: Set<String> = ["sinz.speedysolutions"]

    /// Ce qui change entre A et B, en termes humains — la ligne du panneau
    /// et du statut inline. Le nom du mod en pause est résolu depuis la liste
    /// (le `folderName` seul n'est pas le libellé de l'utilisateur).
    public enum ABChange: Equatable, Sendable {
        case pauseMod(modName: String)
        case profile(modCount: Int)
        case sameState
    }

    public static func change(for sideB: BenchmarkSideB, mods: [ModItem]) -> ABChange {
        switch sideB {
        case .sameState:
            return .sameState
        case .pauseMod(let folder):
            let name = mods.first { $0.folderName == folder }?.name ?? folder
            return .pauseMod(modName: name)
        case .profile(let ids):
            return .profile(modCount: ids.count)
        }
    }

    public static func foldersA(_ mods: [ModItem]) -> [String] {
        mods.filter(\.isEnabled).map(\.folderName)
    }

    public static func foldersB(_ sideB: BenchmarkSideB, foldersA: [String], mods: [ModItem]) -> [String] {
        switch sideB {
        case .sameState:
            return foldersA
        case .pauseMod(let folder):
            return foldersA.filter { $0 != folder }
        case .profile(let ids):
            let wanted = Set(ids.map { $0.lowercased() })
            return mods.filter { mod in
                mod.components.contains { wanted.contains($0.uniqueId.lowercased()) }
            }.map(\.folderName)
        }
    }

    /// Le parc vu dans l'état A. `baseProfileIds` : un profil de base
    /// (« BENCHMARK ») que la série active pour A — `nil`, le parc tel quel.
    /// Un dossier y est actif si l'un de ses composants est dans le profil
    /// (règle de `foldersB(.profile)`) ; les composants d'un pack suivent sa tête.
    public static func stateA(_ mods: [ModItem], baseProfileIds: [String]?) -> [ModItem] {
        guard let baseProfileIds else { return mods }
        let wanted = Set(baseProfileIds.map { $0.lowercased() })
        return mods.map { mod in
            var item = mod
            item.isEnabled = mod.components.contains { wanted.contains($0.uniqueId.lowercased()) }
            item.children = mod.children?.map { child in
                var copy = child
                copy.isEnabled = item.isEnabled
                return copy
            }
            return item
        }
    }

    /// Jugé sur l'état A. Avec un profil de base, les doublons du parc réel
    /// comptent aussi : la restauration finale le rebascule en entier.
    public static func refusal(_ sideB: BenchmarkSideB, mods: [ModItem],
                               baseProfileIds: [String]? = nil) -> BenchmarkRefusal? {
        if baseProfileIds != nil {
            let duplicates = duplicateIdFolders(mods)
            if !duplicates.isEmpty { return .duplicateIds(duplicates) }
        }
        return refusalInState(sideB, mods: stateA(mods, baseProfileIds: baseProfileIds))
    }

    private static func refusalInState(_ sideB: BenchmarkSideB, mods: [ModItem]) -> BenchmarkRefusal? {
        guard let probe = mods.first(where: { head in
            head.isEnabled && head.components.contains { isProbe($0.uniqueId) }
        }) else { return .probeMissing }
        guard ProbeLoadRecords.version(probe.version, atLeast: [0, 7, 0]) else { return .probeTooOld(probe.version) }
        let duplicates = duplicateIdFolders(mods)
        if !duplicates.isEmpty { return .duplicateIds(duplicates) }
        switch sideB {
        case .sameState:
            return nil
        case .pauseMod(let folder):
            guard let target = mods.first(where: { $0.folderName == folder }) else { return .unknownMod }
            if target.folderName == probe.folderName { return .probeInSideB }
            // Un pack : l'entrée de tête n'a pas d'identifiant, les dépendants
            // visent ses composants — union sur chacun, frères exclus.
            var dependents = Set<String>()
            for component in target.components where !component.uniqueId.isEmpty {
                dependents.formUnion(ProbePerformanceActions.pauseBlockers(modId: component.uniqueId, in: mods).dependents)
            }
            return dependents.isEmpty ? nil : .dependents(dependents.sorted())
        case .profile(let ids):
            return ids.contains(where: isProbe) ? nil : .probeInSideB
        }
    }

    public static func cacheWarning(foldersA: [String], foldersB: [String], mods: [ModItem]) -> [String] {
        let changed = Set(foldersA).symmetricDifference(foldersB)
        return mods.filter { mod in
            changed.contains(mod.folderName)
                && mod.components.contains { cacheModIds.contains($0.uniqueId.lowercased()) }
        }.map(\.folderName).sorted()
    }

    private static func isProbe(_ id: String) -> Bool {
        id.caseInsensitiveCompare(probeId) == .orderedSame
    }

    /// Dossiers activés qui partagent un `UniqueID` non vide avec un autre —
    /// le renommage point voyage par identifiant, pas par dossier : un doublon
    /// partirait avec l'original et ne reviendrait pas à la restauration.
    public static func duplicateIdFolders(_ mods: [ModItem]) -> [String] {
        var byId: [String: [String]] = [:]
        for mod in mods where mod.isEnabled {
            for component in mod.components where !component.uniqueId.isEmpty {
                byId[component.uniqueId.lowercased(), default: []].append(mod.folderName)
            }
        }
        return byId.filter { $0.value.count > 1 }
            .flatMap(\.value)
            .sorted()
    }
}
