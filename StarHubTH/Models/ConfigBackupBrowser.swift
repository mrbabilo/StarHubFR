import Foundation

/// Les sauvegardes de configuration vues **par mod** (remarque de l'auteur,
/// 2026-10-16 : « la vue Configuration n'est pas pratique »). Rangées par
/// date, une sauvegarde complète déversait ses ~200 mods d'un bloc : retrouver
/// les versions d'un seul mod obligeait à déplier chaque date. Même forme que
/// `BackupBrowser`, son voisin du segment Installations.
public enum ConfigBackupBrowser {

    /// Une version d'un mod : la sauvegarde datée et l'élément qui le porte.
    public struct Version: Identifiable, Equatable, Sendable {
        public var id: UUID { item.id }
        public let backup: ModConfigBackup
        public let item: ModConfigBackupItem
    }

    /// Toutes les versions sauvegardées d'un dossier de mod (nom **logique** :
    /// une pause ne change pas le mod).
    public struct ModGroup: Identifiable, Equatable, Sendable {
        public var id: String { folderName }
        public let folderName: String
        /// Le nom de la version la plus récente : un mod renommé par son
        /// auteur s'affiche sous son nom actuel.
        public let displayName: String
        public let parentFolderName: String?
        /// Plus récente d'abord.
        public let versions: [Version]
        public var latest: Date { versions.first?.backup.timestamp ?? .distantPast }
    }

    /// Les groupes, par nom ; `search` cherche dans le nom, le dossier et le
    /// pack parent, sans casse ni accents.
    public static func groups(from backups: [ModConfigBackup], search: String) -> [ModGroup] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var byFolder: [String: [Version]] = [:]
        for backup in backups {
            for item in backup.items where needle.isEmpty || matches(item, needle) {
                byFolder[item.modFolderName, default: []].append(Version(backup: backup, item: item))
            }
        }
        return byFolder.map { folder, list in
            let ordered = list.sorted { $0.backup.timestamp > $1.backup.timestamp }
            let newest = ordered.first?.item
            return ModGroup(folderName: folder, displayName: newest?.modDisplayName ?? folder,
                            parentFolderName: newest?.parentFolderName, versions: ordered)
        }
        .sorted {
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            return order != .orderedSame ? order == .orderedAscending : $0.folderName < $1.folderName
        }
    }

    /// Ce que la recherche retient d'un élément — partagé avec la vue par date.
    public static func matches(_ item: ModConfigBackupItem, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return [item.modDisplayName, item.modFolderName, item.parentFolderName ?? ""]
            .contains { $0.range(of: needle, options: options) != nil }
    }
}
