import Foundation

/// Construit la requête groupée envoyée à `smapi.io/api/v3.0/mods`.
///
/// C'est la source que SMAPI lui-même consulte au démarrage. Elle compare
/// elle-même les versions, en tenant compte des `UpdateKeys` du mod (Nexus,
/// GitHub, CurseForge, ModDrop) — l'app ne calcule plus rien. Mesuré sur le
/// parc réel : 960 mods, 41 mises à jour, 115 diagnostics, sans clé ni quota.
public enum SmapiUpdateRequest {

    /// Un dossier de mod tel que le scan l'a vu.
    public struct Candidate {
        public let uniqueId: String
        public let manifestVersion: String
        public let updateKeys: [String]
        /// Un mod en pause est un dossier préfixé par un point : le jeu ne le
        /// charge pas.
        public let isPaused: Bool
        /// Identifiant Nexus saisi par l'utilisateur, quand le manifest n'en
        /// déclare aucun.
        public let manualNexusId: String?

        public init(uniqueId: String, manifestVersion: String, updateKeys: [String],
                    isPaused: Bool, manualNexusId: String?) {
            self.uniqueId = uniqueId
            self.manifestVersion = manifestVersion
            self.updateKeys = updateKeys
            self.isPaused = isPaused
            self.manualNexusId = manualNexusId
        }
    }

    public struct Entry: Encodable, Equatable {
        public let id: String
        public let updateKeys: [String]
        public let installedVersion: String

        public init(id: String, updateKeys: [String], installedVersion: String) {
            self.id = id
            self.updateKeys = updateKeys
            self.installedVersion = installedVersion
        }
    }

    public struct Body: Encodable {
        public let mods: [Entry]
        public let includeExtendedMetadata: Bool
        public let gameVersion: String
        public let platform: String

        public init(mods: [Entry],
                    includeExtendedMetadata: Bool = true,
                    gameVersion: String,
                    platform: String = "Mac") {
            self.mods = mods
            self.includeExtendedMetadata = includeExtendedMetadata
            self.gameVersion = gameVersion
            self.platform = platform
        }
    }

    /// Une entrée **par `UniqueID`**, pas par dossier.
    ///
    /// Sur le parc réel, 6 `UniqueID` sont portés par deux dossiers — Swim Mod
    /// est installé en pack *et* à plat. Envoyer les deux ferait dépendre le
    /// verdict de l'ordre de parcours du disque.
    public static func entries(from candidates: [Candidate],
                               anchors: [String: ModVersionAnchor]) -> [Entry] {
        var best: [String: Candidate] = [:]
        for candidate in candidates where !candidate.uniqueId.isEmpty {
            guard let existing = best[candidate.uniqueId] else {
                best[candidate.uniqueId] = candidate
                continue
            }
            if prefer(candidate, over: existing) {
                best[candidate.uniqueId] = candidate
            }
        }
        return best.values
            .sorted { $0.uniqueId < $1.uniqueId }   // ordre stable, pour les tests et les journaux
            .map { candidate in
                Entry(id: candidate.uniqueId,
                      updateKeys: resolvedUpdateKeys(candidate),
                      installedVersion: anchors[candidate.uniqueId]?.anchoredVersion
                          ?? candidate.manifestVersion)
            }
    }

    public static func batches(_ entries: [Entry], size: Int) -> [[Entry]] {
        guard size > 0 else { return entries.isEmpty ? [] : [entries] }
        return stride(from: 0, to: entries.count, by: size).map {
            Array(entries[$0..<min($0 + size, entries.count)])
        }
    }

    // MARK: - Privé

    /// La copie active décrit ce qui tourne ; à défaut, la plus haute version.
    private static func prefer(_ candidate: Candidate, over existing: Candidate) -> Bool {
        if existing.isPaused != candidate.isPaused { return !candidate.isPaused }
        return NexusUpdateChecker.isNewer(candidate.manifestVersion,
                                          installed: existing.manifestVersion)
    }

    /// L'identifiant saisi à la main devient une `UpdateKey` synthétique —
    /// mais seulement quand le manifest n'en déclare aucune vers Nexus. Le
    /// manifest fait foi : c'est ce que SMAPI lit.
    private static func resolvedUpdateKeys(_ candidate: Candidate) -> [String] {
        let declaresNexus = candidate.updateKeys.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("nexus:")
        }
        guard !declaresNexus,
              let manual = candidate.manualNexusId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !manual.isEmpty else {
            return candidate.updateKeys
        }
        return candidate.updateKeys + ["Nexus:\(manual)"]
    }
}
