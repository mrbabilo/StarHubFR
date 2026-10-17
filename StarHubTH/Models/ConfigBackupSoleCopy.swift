import Foundation

/// I-T31 (décision de l'auteur, extension de R1) — la garde « seule copie »
/// des sauvegardes de configuration, comme celle des sauvegardes
/// d'installation : avant de mettre une sauvegarde à la Corbeille, dire de
/// quels fichiers elle est la dernière copie.
///
/// **La présence tranche, jamais le contenu** (même règle que
/// `MaintenanceInventory.protection`) : tant que le mod porte son
/// `config.json`, la sauvegarde n'en garde qu'un état antérieur, ce qui est
/// son rôle. Seul un fichier absent du dossier `Mods/` — mod désinstallé,
/// fichier supprimé — en fait la seule copie.
public enum ConfigBackupSoleCopy {
    /// Les fichiers (« Dossier/config.json », relatifs à `Mods/`) que seule
    /// cette sauvegarde garde encore. `exists` répond pour un chemin relatif.
    public static func files(in backup: ModConfigBackup, exists: (String) -> Bool) -> [String] {
        backup.items.flatMap { item in item.files.map { "\(item.modFolderName)/\($0)" } }
            .filter { path in !diskCandidates(path).contains(where: exists) }
    }

    /// Le chemin tel que la sauvegarde l'a noté, puis sa forme en pause : un
    /// mod en pause porte un point sur son dossier de tête (`Mods/.X`).
    public static func diskCandidates(_ relativePath: String) -> [String] {
        [relativePath, "." + relativePath]
    }
}
