import Foundation

/// Les lectures disque de la règle « seule copie » : taille et fichiers
/// utilisateur d'une sauvegarde, état du mod installé. Sorties du ViewModel
/// pour servir aux deux portes qui suppriment une sauvegarde d'installation —
/// l'Entretien et « Sauvegardes des mods » (audit UX R1) — avec une seule
/// règle. `MaintenanceInventory` reste pur ; ce type-ci lit le disque.
public enum MaintenanceDiskReader {

    /// Taille et fichiers utilisateur en **une** traversée, `nil` si absent.
    /// Classification bornée à l'hôte (X75).
    public static func walkBackup(root: URL, hostTranslationPaths: Set<String>)
    -> (Int64, [MaintenanceInventory.UserFile])? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue
        else { return nil }
        guard let walker = fm.enumerator(at: root,
                                         includingPropertiesForKeys: [.fileSizeKey,
                                                                      .isRegularFileKey])
        else { return nil }
        var bytes: Int64 = 0
        var files: [MaintenanceInventory.UserFile] = []
        // ⚠️ `resolvingSymlinksInPath()` d'abord : l'énumérateur rend
        // `/private/var…`.
        let base = root.resolvingSymlinksInPath().path + "/"
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            bytes += Int64(values?.fileSize ?? 0)
            let relative = url.resolvingSymlinksInPath().path
                .replacingOccurrences(of: base, with: "")
            if let kind = MaintenanceInventory.classifyUserFile(
                relativePath: relative, hostTranslationPaths: hostTranslationPaths) {
                files.append(.init(relativePath: relative, kind: kind))
            }
        }
        return (bytes, files)
    }

    /// État actuel du mod, restreint aux chemins utiles ; `nil` si absent
    /// (actif ou en pause).
    public static func installedState(of folderName: String, modsRoot: String,
                                       userFiles: [MaintenanceInventory.UserFile])
    -> MaintenanceInventory.InstalledState {
        let fm = FileManager.default
        guard let current = ModRootResolver.physicalRoot(of: folderName, modsRoot: modsRoot) else {
            return .init(presentFiles: nil)
        }
        let present = userFiles.filter {
            fm.fileExists(atPath: (current as NSString).appendingPathComponent($0.relativePath))
        }
        return .init(presentFiles: Set(present.map(\.relativePath)))
    }

    /// Les fichiers dont cette sauvegarde est la **seule copie** — vide quand
    /// rien n'est protégé, ou que la sauvegarde a quitté le disque.
    public static func soleCopyFiles(backupRoot: URL, modFolder: String, modsRoot: String,
                                     hostTranslationPaths: Set<String>) -> [MaintenanceInventory.UserFile] {
        guard let (bytes, files) = walkBackup(root: backupRoot,
                                              hostTranslationPaths: hostTranslationPaths) else { return [] }
        let entry = MaintenanceInventory.BackupEntry(id: backupRoot.lastPathComponent, modFolder: modFolder,
                                                     timestamp: Date(), sizeBytes: bytes, userFiles: files)
        let installed = installedState(of: modFolder, modsRoot: modsRoot, userFiles: files)
        if case .soleCopy(let missing) = MaintenanceInventory.protection(of: entry, installed: installed) {
            return missing
        }
        return []
    }
}
