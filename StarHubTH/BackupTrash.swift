import Foundation

/// Supprimer une sauvegarde depuis « Sauvegardes des mods » la met dans la
/// **Corbeille du Mac**, comme l'Entretien (audit UX R1) : la suppression
/// directe ne laissait aucun retour, et l'utilisateur ne la distinguait pas
/// d'une mise à la corbeille. Le dossier part d'abord ; l'index n'est
/// retouché qu'ensuite, par `deleteBackup`, qui ne trouve plus rien à effacer.
extension ModInstallBackupManager {
    public func trashBackup(_ backup: ModInstallBackup) throws {
        let dir = backupDirectory(of: backup)
        if FileManager.default.fileExists(atPath: dir.path) {
            _ = try ModZipInstaller.trashItemGrantingWriteAccess(atPath: dir.path)
        }
        try deleteBackup(backup)
    }
}

extension ModConfigBackupManager {
    public func trashBackup(_ backup: ModConfigBackup) throws {
        let dir = backupDirURL(named: backup.folderName)
        if FileManager.default.fileExists(atPath: dir.path) {
            _ = try ModZipInstaller.trashItemGrantingWriteAccess(atPath: dir.path)
        }
        try deleteBackup(backup)
    }
}
