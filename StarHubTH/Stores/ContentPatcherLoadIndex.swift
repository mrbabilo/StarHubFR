import Foundation
import Observation

/// A5-T4 — l'index des cibles `Load` certaines de **toutes** les racines,
/// pauses comprises : le mod qu'on active est en pause par définition, et ses
/// cibles doivent être connues avant le geste (porte d'activation, T4b).
///
/// Construit hors du fil principal après chaque scan ; la porte reste
/// synchrone et ne lit que cet index — pas encore construit, elle laisse
/// passer sans rien dire. Cache par `folderName` logique + date du
/// `content.json` : une bascule renomme le dossier physique sans toucher au
/// fichier, une mise à jour de mod le réécrit.
@MainActor @Observable
final class ContentPatcherLoadIndex {
    private(set) var pairs: [ContentPatcherLoadTargets.Pair] = []
    @ObservationIgnored private var cache: [String: Cached] = [:]
    @ObservationIgnored private var generation = 0

    struct Cached: Sendable {
        let modified: Date
        let targets: Set<String>
    }

    var conflictPairs: [ModConflictPair] { ContentPatcherLoadTargets.conflictPairs(pairs) }

    func refresh(mods: [ModItem], gameDir: String) {
        guard !gameDir.isEmpty else { return }
        generation += 1
        let run = generation
        let modsRoot = (gameDir as NSString).appendingPathComponent("Mods")
        let cache = self.cache
        Task.detached(priority: .utility) {
            let (packs, fresh) = Self.scan(mods: mods, modsRoot: modsRoot, cache: cache)
            let pairs = ContentPatcherLoadTargets.pairs(packs)
            await MainActor.run {
                guard run == self.generation else { return }
                self.cache = fresh
                self.pairs = pairs
            }
        }
    }

    /// Toutes les racines, pause comprise. Un pack illisible ne réclame rien.
    nonisolated static func scan(mods: [ModItem], modsRoot: String,
                                 cache: [String: Cached]) -> ([ContentPatcherLoadTargets.Pack], [String: Cached]) {
        var packs: [ContentPatcherLoadTargets.Pack] = []
        var fresh: [String: Cached] = [:]
        for root in mods where !root.isPackComponent {
            for dir in ContentPatcherPacks.packDirectories(of: root, modsRoot: modsRoot) {
                let attributes = try? FileManager.default.attributesOfItem(atPath: dir.path + "/content.json")
                let modified = attributes?[.modificationDate] as? Date ?? .distantPast
                let targets: Set<String>
                if let hit = cache[dir.folderName], hit.modified == modified {
                    targets = hit.targets
                } else {
                    let count = ContentPatcherPacks.read(dir)
                    targets = count.state == .ok ? count.loadTargets : []
                }
                fresh[dir.folderName] = Cached(modified: modified, targets: targets)
                packs.append(.init(rootName: root.folderName, packName: dir.name, folderName: dir.folderName,
                                   rootEnabled: root.isEnabled, loadTargets: targets))
            }
        }
        return (packs, fresh)
    }
}
