import Foundation

/// Ce que la page des sauvegardes donne à voir : des mods, chacun avec ses
/// versions, plutôt qu'une liste plate.
///
/// Mesuré sur un parc réel le 2026-08-21 : 1 494 sauvegardes s'y déversaient
/// d'un bloc, sans tri ni recherche. Le critère de la roadmap — retrouver une
/// sauvegarde en moins de dix secondes — n'est pas atteignable ainsi.
public enum BackupBrowser {

    public enum Sort: String, CaseIterable, Sendable {
        /// Le mod touché en dernier d'abord : c'est celui dont on vient de
        /// rater la mise à jour.
        case mostRecent
        case nameAscending
        case nameDescending
        /// Le plus sauvegardé d'abord — « qu'est-ce qui occupe ma place ? ».
        case count
    }

    /// Les sauvegardes d'une même version d'un mod.
    public struct VersionGroup: Identifiable, Equatable, Sendable {
        public var id: String { version }
        public let version: String
        /// Plus récente d'abord.
        public let backups: [ModInstallBackup]
        public var latest: Date { backups.first?.timestamp ?? .distantPast }
    }

    /// Toutes les sauvegardes d'un **dossier** de mod.
    public struct ModGroup: Identifiable, Equatable, Sendable {
        /// Le dossier d'origine, comme pour la déduplication et la
        /// restauration : deux installations du même mod dans deux dossiers
        /// sont deux entrées distinctes, et le parc de référence en porte.
        public var id: String { folderName }
        public let folderName: String
        /// Le nom de la sauvegarde la plus récente : un mod renommé par son
        /// auteur s'affiche sous son nom actuel.
        public let displayName: String
        public let author: String
        /// Plus récente d'abord, toutes versions confondues.
        public let backups: [ModInstallBackup]
        public let versions: [VersionGroup]
        public var latest: Date { backups.first?.timestamp ?? .distantPast }
    }

    public static func groups(from backups: [ModInstallBackup],
                              search: String, sort: Sort) -> [ModGroup] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = needle.isEmpty ? backups : backups.filter { matches($0, needle) }

        var byFolder: [String: [ModInstallBackup]] = [:]
        for backup in kept {
            byFolder[backup.originalFolderName, default: []].append(backup)
        }

        let groups = byFolder.map { folder, list -> ModGroup in
            let ordered = list.sorted { $0.timestamp > $1.timestamp }
            return ModGroup(folderName: folder,
                            displayName: ordered.first?.modMetadata.name ?? folder,
                            author: ordered.first?.modMetadata.author ?? "",
                            backups: ordered,
                            versions: versionGroups(of: ordered))
        }
        return sorted(groups, by: sort)
    }

    /// Les versions, la plus récemment sauvegardée en tête. Une version
    /// sauvegardée deux fois ne fait qu'une section : c'est le cas courant
    /// d'une réinstallation.
    private static func versionGroups(of ordered: [ModInstallBackup]) -> [VersionGroup] {
        var order: [String] = []
        var byVersion: [String: [ModInstallBackup]] = [:]
        for backup in ordered {
            let version = backup.modMetadata.version
            if byVersion[version] == nil { order.append(version) }
            byVersion[version, default: []].append(backup)
        }
        return order.map { VersionGroup(version: $0, backups: byVersion[$0] ?? []) }
    }

    private static func sorted(_ groups: [ModGroup], by sort: Sort) -> [ModGroup] {
        switch sort {
        case .mostRecent:
            return groups.sorted { $0.latest > $1.latest }
        case .nameAscending:
            return groups.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .nameDescending:
            return groups.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedDescending }
        case .count:
            // À nombre égal, le plus récent d'abord : l'ordre ne doit pas
            // sauter d'un affichage à l'autre.
            return groups.sorted {
                $0.backups.count == $1.backups.count
                    ? $0.latest > $1.latest
                    : $0.backups.count > $1.backups.count
            }
        }
    }

    /// Le nom du mod, son dossier, son auteur, sa version. Le dossier compte
    /// autant que le nom : c'est lui qu'on lit dans `Mods/`, et 111 mods du
    /// parc de référence n'ont pas d'identifiant à opposer.
    private static func matches(_ backup: ModInstallBackup, _ needle: String) -> Bool {
        let fields = [backup.modMetadata.name, backup.originalFolderName,
                      backup.modMetadata.author, backup.modMetadata.version]
        return fields.contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}
