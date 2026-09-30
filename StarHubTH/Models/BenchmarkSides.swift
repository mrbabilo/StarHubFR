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
    public static let minimalProfileIds = [probeId, "SMAPI.ConsoleCommands", "SMAPI.SaveBackup",
                                           "Pathoschild.SkipIntro"]
    /// Mods à cache disque connu : les basculer fait payer la reconstruction à
    /// chaque lancement d'un seul côté — la médiane bouge sans que l'écart
    /// interne grandisse (`observedNoisePercent` ne le voit pas).
    public static let cacheModIds: Set<String> = ["sinz.speedysolutions"]

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

    public static func refusal(_ sideB: BenchmarkSideB, mods: [ModItem]) -> BenchmarkRefusal? {
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
