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
    /// verdict de l'ordre de parcours du disque. Quand deux candidats sont
    /// strictement égaux sur statut et version, on fusionne leurs UpdateKeys
    /// pour garantir le déterminisme : c'est l'union, dédoublonnée, triée.
    public static func entries(from candidates: [Candidate],
                               anchors: [String: ModVersionAnchor]) -> [Entry] {
        var best: [String: Candidate] = [:]
        for candidate in candidates where !candidate.uniqueId.isEmpty {
            guard let existing = best[candidate.uniqueId] else {
                best[candidate.uniqueId] = candidate
                continue
            }
            let comparison = compare(candidate, with: existing)
            switch comparison {
            case .prefers:
                best[candidate.uniqueId] = candidate
            case .merges:
                best[candidate.uniqueId] = merge(candidate, with: existing)
            case .keepExisting:
                break
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

    /// Résultat de la comparaison de deux candidats avec le même UniqueID.
    private enum Comparison {
        case prefers      // le candidat courant remplace l'existant
        case merges       // stricte égalité sur statut et version, fusion requise
        case keepExisting // l'existant reste meilleur
    }

    /// Compare deux candidats pour déterminer lequel retenir.
    /// La priorité est : (1) statut pause, (2) version, (3) fusion si égalité stricte.
    /// La fusion garantit que les UpdateKeys de deux copies identiques ne dépendent
    /// pas de l'ordre de parcours du disque.
    private static func compare(_ candidate: Candidate, with existing: Candidate) -> Comparison {
        // La copie active décrit ce qui tourne ; elle l'emporte sur la copie en pause.
        if existing.isPaused != candidate.isPaused {
            return !candidate.isPaused ? .prefers : .keepExisting
        }

        // Comparaison stricte des versions.
        let candidateIsNewer = NexusUpdateChecker.isNewer(candidate.manifestVersion,
                                                          installed: existing.manifestVersion)
        if candidateIsNewer {
            return .prefers
        }

        let existingIsNewer = NexusUpdateChecker.isNewer(existing.manifestVersion,
                                                         installed: candidate.manifestVersion)
        if existingIsNewer {
            return .keepExisting
        }

        // Versions égales : fusion requise pour le déterminisme.
        return .merges
    }

    /// Fusionne deux candidats strictement égaux (même statut et version).
    /// L'ensemble des UpdateKeys est l'union des deux, dédoublonnée et triée.
    /// Le manualNexusId retenu est le plus petit lexicographiquement, ou nil.
    private static func merge(_ candidate: Candidate, with existing: Candidate) -> Candidate {
        let mergedKeys = Set(candidate.updateKeys + existing.updateKeys)
            .sorted()
        let manualId = [candidate.manualNexusId, existing.manualNexusId]
            .compactMap { $0 }
            .sorted()
            .first

        return Candidate(
            uniqueId: candidate.uniqueId,
            manifestVersion: candidate.manifestVersion,
            updateKeys: mergedKeys,
            isPaused: candidate.isPaused,
            manualNexusId: manualId
        )
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
