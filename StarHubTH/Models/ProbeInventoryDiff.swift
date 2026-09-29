import Foundation

/// Ce qui a changé pour un mod entre deux inventaires de la sonde.
public struct ProbeModChange: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case added
        case removed
        /// `configChanged` : le réglage a changé aussi — un seul changement
        /// (un seul mod), mais le réglage n'est pas perdu.
        case versionChanged(from: String, to: String, configChanged: Bool = false)
        case configChanged(oldSha: String?, newSha: String?)
    }
    public let modId: String
    public let kind: Kind
}

public struct ProbeInventoryDiff: Equatable, Sendable {
    /// La sonde elle-même mise à part (une montée de sonde n'est pas un
    /// changement du parc, mais compte pour le choix de la paire par défaut).
    public let probeChanged: Bool
    /// Hors sonde, triés par `modId`.
    public let changes: [ProbeModChange]
}

public enum ProbeInventoryDiffRule {
    static let probeId = "mrbabilo.starhubfr.probe"

    /// Les identifiants se comparent sans la casse, comme SMAPI ; le `modId`
    /// rendu est celui du côté qui le porte (B d'abord).
    public static func between(_ a: ProbeInventoryLaunch, _ b: ProbeInventoryLaunch) -> ProbeInventoryDiff {
        let byA = lowercasedIndex(a)
        let byB = lowercasedIndex(b)
        var changes: [ProbeModChange] = []
        for (key, entryB) in byB where key != probeId {
            guard let entryA = byA[key] else {
                changes.append(ProbeModChange(modId: entryB.modId, kind: .added))
                continue
            }
            if entryA.version != entryB.version {
                changes.append(ProbeModChange(modId: entryB.modId,
                                              kind: .versionChanged(from: entryA.version, to: entryB.version,
                                                                    configChanged: entryA.configSha != entryB.configSha)))
            } else if entryA.configSha != entryB.configSha {
                changes.append(ProbeModChange(modId: entryB.modId,
                                              kind: .configChanged(oldSha: entryA.configSha,
                                                                   newSha: entryB.configSha)))
            }
        }
        for (key, entryA) in byA where key != probeId && byB[key] == nil {
            changes.append(ProbeModChange(modId: entryA.modId, kind: .removed))
        }
        return ProbeInventoryDiff(probeChanged: byA[probeId]?.version != byB[probeId]?.version,
                                  changes: changes.sorted { $0.modId < $1.modId })
    }

    /// Diff clé par clé des contenus `configs/<sha>.json`. `nil` : un des deux
    /// contenus manque (la sonde ne les range pas tous) — l'écran dira
    /// « réglage modifié » seul. Les contenus peuvent porter des clés d'API :
    /// jamais exportés, jamais journalisés.
    public static func configDiff(modId: String, oldSha: String?, newSha: String?,
                                  configsDirectory: URL) -> [ConfigKeyDiff]? {
        guard let oldTree = tree(oldSha, in: configsDirectory),
              let newTree = tree(newSha, in: configsDirectory)
        else { return nil }
        return ConfigJSONDiff.compare(oldTree, newTree)
    }

    /// Les diffs clé par clé de tous les réglages modifiés d'une paire, par
    /// `modId` — lus une fois par paire (hors du fil principal), jamais au
    /// rendu. Absents de la table : contenus non rangés par la sonde.
    public static func configDiffs(of changes: [ProbeModChange],
                                   configsDirectory: URL) -> [String: [ConfigKeyDiff]] {
        var out: [String: [ConfigKeyDiff]] = [:]
        for change in changes {
            guard case .configChanged(let old, let new) = change.kind,
                  let keys = configDiff(modId: change.modId, oldSha: old, newSha: new,
                                        configsDirectory: configsDirectory)
            else { continue }
            out[change.modId] = keys
        }
        return out
    }

    // MARK: — Privé

    private static func lowercasedIndex(_ launch: ProbeInventoryLaunch) -> [String: ProbeInventoryEntry] {
        Dictionary(launch.mods.map { ($0.modId.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// L'empreinte vient d'un fichier : hexadécimale ou rien, jamais un chemin.
    private static func tree(_ sha: String?, in directory: URL) -> ConfigJSONTree.Value? {
        // Contenu absent : cas prévu (la sonde ne les range pas tous).
        guard let sha, !sha.isEmpty, sha.allSatisfy(\.isHexDigit),
              let data = FileManager.default.contents(
                  atPath: directory.appendingPathComponent("\(sha).json").path),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return ConfigJSONTree.parse(text)
    }
}
