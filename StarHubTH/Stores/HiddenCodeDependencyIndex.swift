import Foundation
import Observation

/// A5-T6 — qui lit le code interne de qui, sur **tout** le parc, pauses
/// comprises : la cible d'une mise à jour peut être en pause, et la fiche
/// d'un mod en pause dit ce qu'il lira une fois activé.
///
/// Construit hors du fil principal après chaque scan (523 DLL lues en ~10 s
/// en debug sur le parc de référence). Cache par chemin **logique** (sans
/// points de pause) + `EntryDll`, validé par date et taille de la DLL : une
/// bascule renomme le dossier sans toucher au fichier, une mise à jour le
/// réécrit.
@MainActor @Observable
final class HiddenCodeDependencyIndex {
    private(set) var links: [HiddenCodeDependencies.Link] = []
    @ObservationIgnored private var cache: [String: Cached] = [:]
    @ObservationIgnored private var generation = 0

    struct Cached: Sendable {
        let modified: Date
        let size: Int
        let assembly: HiddenCodeDependencies.Assembly?
    }

    /// Les liens dont le citant porte l'un de ces `UniqueID` (sans casse).
    func links(citing uniqueIds: [String]) -> [HiddenCodeDependencies.Link] {
        let keys = Set(uniqueIds.map { $0.lowercased() })
        return links.filter { keys.contains($0.citing.lowercased()) }
    }

    /// Les liens qui visent ce `UniqueID` (sans casse).
    func links(targeting uniqueId: String) -> [HiddenCodeDependencies.Link] {
        links.filter { $0.target.caseInsensitiveCompare(uniqueId) == .orderedSame }
    }

    /// Ce que la fiche montre (choix du 2026-10-08) : les liens de ce mod, ou
    /// des composants de ce pack, que leur manifeste ne déclare pas.
    func undeclaredLinks(for mod: ModItem, installed: [ModItem]) -> [HiddenCodeDependencies.Link] {
        let ids = ([mod] + mod.components).map(\.uniqueId).filter { !$0.isEmpty }
        let flat = installed.flattenedMods
        return HiddenCodeDependencies.undeclared(links(citing: ids)) { citing in
            flat.filter { $0.uniqueId.caseInsensitiveCompare(citing) == .orderedSame }
                .flatMap(\.dependencies).map(\.uniqueId)
        }
    }

    func refresh(gameDir: String) {
        guard !gameDir.isEmpty else { return }
        generation += 1
        let run = generation
        let modsRoot = URL(fileURLWithPath: gameDir).appendingPathComponent("Mods")
        let cache = self.cache
        Task.detached(priority: .utility) {
            let (assemblies, fresh) = Self.scan(modsRoot: modsRoot, cache: cache)
            let links = HiddenCodeDependencies.links(assemblies)
            await MainActor.run {
                guard run == self.generation else { return }
                self.cache = fresh
                self.links = links
            }
        }
    }

    /// Une DLL illisible ne cite rien et ne définit rien.
    nonisolated static func scan(modsRoot: URL, cache: [String: Cached])
        -> ([HiddenCodeDependencies.Assembly], [String: Cached]) {
        var assemblies: [HiddenCodeDependencies.Assembly] = []
        var fresh: [String: Cached] = [:]
        for target in SmapiBlacklistScan.targets(modsRoot: modsRoot) {
            guard let dll = target.entryDll else { continue }
            let path = target.folder.appendingPathComponent(dll).path
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try FileManager.default.attributesOfItem(atPath: path)
            } catch {
                continue   // `EntryDll` absente : SMAPI refuse ce mod, il ne lit rien
            }
            let modified = attributes[.modificationDate] as? Date ?? .distantPast
            let size = (attributes[.size] as? NSNumber)?.intValue ?? -1
            // Chemin relatif sans points de pause : deux copies d'un même
            // mod (à plat et dans son dossier de téléchargement) restent deux.
            let logicalPath = target.folder.pathComponents.dropFirst(modsRoot.pathComponents.count)
                .map { String($0.drop { $0 == "." }) }.joined(separator: "/")
            let key = "\(logicalPath)|\(dll)"
            let assembly: HiddenCodeDependencies.Assembly?
            if let hit = cache[key], hit.modified == modified, hit.size == size {
                assembly = hit.assembly
            } else {
                assembly = FileManager.default.contents(atPath: path).flatMap {
                    HiddenCodeDependencies.assembly(uniqueId: target.uniqueId, bytes: [UInt8]($0))
                }
            }
            fresh[key] = Cached(modified: modified, size: size, assembly: assembly)
            if let assembly { assemblies.append(assembly) }
        }
        return (assemblies, fresh)
    }
}
