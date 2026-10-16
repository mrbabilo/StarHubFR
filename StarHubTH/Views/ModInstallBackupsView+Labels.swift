import SwiftUI

/// Libellés purs de la page des sauvegardes d'installation, sortis de la vue
/// (plafond de taille) quand la suppression est passée à la corbeille (R1).
extension ModInstallBackupsView {
    func reasonText(for reason: BackupReason) -> String {
        switch reason {
        case .beforeInstall: return localization.L(L10n.ModInstall.backupReasonInstall)
        case .beforeUpdate: return localization.L(L10n.ModInstall.backupReasonUpdate)
        case .beforeRestore: return localization.L(L10n.ModInstall.backupReasonRestore)
        case .beforeCleanup: return localization.L(L10n.ModInstall.backupReasonCleanup)
        }
    }

    func reasonIcon(for reason: BackupReason) -> String {
        switch reason {
        case .beforeInstall: return "plus.circle"
        case .beforeUpdate: return "arrow.up.circle"
        case .beforeRestore: return "arrow.uturn.backward.circle"
        case .beforeCleanup: return "wand.and.stars"
        }
    }

    /// Met le compte rendu en phrases, pour la ligne de journal. Le panneau
    /// affiché sous la liste (`restoreReportPanel`) rend les mêmes sept
    /// champs en lignes étiquetées ; cette fonction ne sert plus qu'au log
    /// (elle a servi au message de l'alerte avant T9 H-T6).
    func restoreReportMessage(_ report: ModInstallRestoreReport) -> String {
        var lines = [
            String(format: localization.L(L10n.ModInstall.restoreReportWritten),
                   report.modName, report.version, report.displayPath),
            String(format: localization.L(L10n.ModInstall.restoreReportFiles), Int64(report.fileCount)),
            localization.L(report.landedEnabled ? L10n.ModInstall.restoreReportActive
                                      : L10n.ModInstall.restoreReportPaused)
        ]
        if !report.replacedVersions.isEmpty {
            let key = report.replacedVersions.count == 1
                ? L10n.ModInstall.restoreReportReplaced
                : L10n.ModInstall.restoreReportReplacedMany
            lines.append(String(format: localization.L(key),
                                report.replacedVersions.joined(separator: ", ")))
        }
        return lines.joined(separator: "\n")
    }

    /// R1 — la règle « seule copie » de l'Entretien pour cette sauvegarde, lue
    /// hors du fil principal (un gros pack compte des milliers de fichiers).
    func soleCopy(of backup: ModInstallBackup) async -> [MaintenanceInventory.UserFile] {
        let model = vm
        let modsRoot = (model.gameDir as NSString).appendingPathComponent("Mods")
        let paths = model.installedTranslationRelativePaths()[backup.originalFolderName] ?? []
        let root = URL(fileURLWithPath: backup.backupPath), folder = backup.originalFolderName
        return await Task.detached(priority: .userInitiated) {
            MaintenanceDiskReader.soleCopyFiles(backupRoot: root, modFolder: folder,
                                                modsRoot: modsRoot, hostTranslationPaths: paths)
        }.value
    }

    /// Message de confirmation : la corbeille, et ce dont cette sauvegarde est
    /// la seule copie — ces fichiers ne sont plus dans le mod installé.
    func deleteMessage(soleCopy: [MaintenanceInventory.UserFile]) -> String {
        let base = localization.L(L10n.ModInstall.deleteConfirmMessage)
        guard !soleCopy.isEmpty else { return base }
        return base + "\n\n" + String(format: localization.L(L10n.ModInstall.deleteSoleCopy),
                                         soleCopy.map(\.relativePath).joined(separator: ", "))
    }
}
