import Foundation

/// A5-T4 — les cibles `Load` disputées entre deux mods, dites **avant** de
/// jouer. Une cible n'est réclamée que par un `Load` inconditionnel, sans
/// `Priority` déclarée et sans jeton (voir `ContentPatcherPacks.loadTargets`) :
/// c'est le seul cas certain, vérifié par décompilation — deux `Load`
/// exclusifs sur la même cible laissent l'asset **vanilla**.
public enum ContentPatcherLoadTargets {
    public struct Pack: Equatable, Sendable {
        public let rootName: String
        public let packName: String
        /// Le `folderName` logique du pack — la clé des `ModConflictPair`,
        /// la même forme que celle des conflits du journal.
        public let folderName: String
        public let rootEnabled: Bool
        public let loadTargets: Set<String>

        public init(rootName: String, packName: String, folderName: String? = nil,
                    rootEnabled: Bool, loadTargets: Set<String>) {
            self.rootName = rootName; self.packName = packName
            self.folderName = folderName ?? rootName
            self.rootEnabled = rootEnabled; self.loadTargets = loadTargets
        }
    }

    public struct Pair: Equatable, Sendable, Identifiable {
        public let asset: String
        /// Deux packs de **mods racine différents** (intra-mod : affaire de
        /// l'auteur, pas un arbitrage d'utilisateur).
        public let packs: [Pack]
        public let bothActive: Bool
        public var id: String { asset + "|" + packs.map(\.rootName).sorted().joined(separator: "|") }
    }

    public static func pairs(_ packs: [Pack]) -> [Pair] {
        var claims: [String: [Pack]] = [:]
        for pack in packs where !pack.loadTargets.isEmpty {
            for asset in pack.loadTargets { claims[asset, default: []].append(pack) }
        }
        var result: [Pair] = []
        for (asset, holders) in claims.sorted(by: { $0.key < $1.key }) {
            for i in holders.indices {
                for j in holders.indices where j > i {
                    guard holders[i].rootName != holders[j].rootName else { continue }
                    result.append(Pair(asset: asset,
                                       packs: [holders[i], holders[j]],
                                       bothActive: holders[i].rootEnabled && holders[j].rootEnabled))
                }
            }
        }
        return result
    }

    /// Les paires en `ModConflictPair` (dossiers logiques), une par duo de
    /// packs quel que soit le nombre de cibles qu'ils se disputent.
    public static func conflictPairs(_ pairs: [Pair]) -> [ModConflictPair] {
        Array(Set(pairs.map { ModConflictPair($0.packs[0].folderName, $0.packs[1].folderName) }))
            .sorted { ($0.first, $0.second) < ($1.first, $1.second) }
    }

    /// Les assets disputés par un duo, pour dire **lesquels** dans le message.
    public static func assets(of pair: ModConflictPair, in pairs: [Pair]) -> [String] {
        pairs.filter { ModConflictPair($0.packs[0].folderName, $0.packs[1].folderName) == pair }
            .map(\.asset).sorted()
    }

    /// Les assets qu'un geste d'activation rendrait disputés avec `other` :
    /// `activating` porte l'en-tête et les composants du mod activé.
    public static func assets(activating: Set<String>, other: String, in pairs: [Pair]) -> [String] {
        pairs.filter { pair in
            let folders = pair.packs.map(\.folderName)
            return folders.contains(other) && folders.contains { activating.contains($0) }
        }.map(\.asset).sorted()
    }

    /// Les paires qui deviennent réelles : `candidate` (mod qu'on active)
    /// contre chaque pack actif de `others`.
    public static func activationConflicts(candidate: Pack, others: [Pack]) -> [Pair] {
        pairs(others.filter(\.rootEnabled)
              + [Pack(rootName: candidate.rootName, packName: candidate.packName,
                      folderName: candidate.folderName, rootEnabled: true,
                      loadTargets: candidate.loadTargets)])
            .filter { $0.bothActive && $0.packs.contains { $0.rootName == candidate.rootName } }
    }
}

/// Lecture d'une cible `Load` certaine, hors du compteur de patches.
enum ContentPatcherPatches {
    /// Les cibles d'un patch `Load` **certain**, ou `nil` : pas un `Load`,
    /// `When` présent, jeton dans `Target`, ou `Priority` autre
    /// qu'`Exclusive` (le défaut CP ; un `Exclusive` écrit reste exclusif).
    /// Cibles éclatées sur `,`/`|`, `\` ramené à `/` (CP les confond), casse
    /// pliée.
    static func certainLoadTargets(of patch: [String: Any]) -> Set<String>? {
        guard let action = ContentPatcherPacks.field(patch, "Action") as? String,
              action.caseInsensitiveCompare("Load") == .orderedSame,
              ContentPatcherPacks.field(patch, "When") == nil,
              let target = ContentPatcherPacks.field(patch, "Target") as? String,
              !target.contains("{{") else { return nil }
        if let priority = ContentPatcherPacks.field(patch, "Priority") {
            guard (priority as? String)?.caseInsensitiveCompare("Exclusive") == .orderedSame else { return nil }
        }
        let targets = Set(target.split(whereSeparator: { $0 == "," || $0 == "|" })
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\", with: "/").lowercased() }
            .filter { !$0.isEmpty })
        return targets.isEmpty ? nil : targets
    }
}
