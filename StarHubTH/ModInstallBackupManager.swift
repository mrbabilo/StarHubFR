import Foundation

/// Manages backups of complete mod folders before installation or update.
///
/// Mirrors `ModConfigBackupManager`'s singleton pattern with synchronous,
/// throwing methods. Callers dispatch to background queues and hop back to
/// main for UI updates, consistent with the rest of the codebase.
public class ModInstallBackupManager {
    public static let shared = ModInstallBackupManager()

    public enum InstallBackupError: LocalizedError {
        case gameDirEmpty
        case modNotFound(String)
        case backupCreationFailed(String)
        case restoreFailed(String)

        public var errorDescription: String? {
            switch self {
            case .gameDirEmpty: return "Game directory is not set."
            case .modNotFound(let folder): return "Mod '\(folder)' not found."
            case .backupCreationFailed(let reason): return "Backup failed: \(reason)"
            case .restoreFailed(let reason): return "Restore failed: \(reason)"
            }
        }
    }

    private let fm = FileManager.default
    private let backupsBasePath: URL
    private let backupsDirPath: URL
    private let metadataPath: URL

    // Guards every install_metadata.json read-modify-write cycle. Without
    // it, concurrent create/restore/delete/cleanup calls dispatched from
    // different background queues can each load the same old index and the
    // last `saveIndex` silently discards the others' changes.
    private let indexLock = NSLock()

    private static let minBackupsToKeep = 5
    private static let maxBackupAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days

    /// `backupsBasePath` is exposed only so tests can point this manager at
    /// an isolated temporary directory instead of the real Application
    /// Support folder. Production code always uses `.shared`, which calls
    /// this with `nil` and gets the exact same directory as before.
    public init(backupsBasePath overrideBasePath: URL? = nil) {
        let base = overrideBasePath ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("StarHubTH/Backups/ModInstalls", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("StarHubTH/Backups/ModInstalls", isDirectory: true)
        backupsBasePath = base
        backupsDirPath = base.appendingPathComponent("backups", isDirectory: true)
        metadataPath = base.appendingPathComponent("install_metadata.json")
        try? fm.createDirectory(at: backupsDirPath, withIntermediateDirectories: true, attributes: nil)
    }

    // MARK: - Index

    private func withIndexLock<T>(_ body: () -> T) -> T {
        indexLock.lock()
        defer { indexLock.unlock() }
        return body()
    }

    /// All backups, most recent first. Returns empty list if index is missing/corrupted.
    public func loadBackups() -> [ModInstallBackup] {
        withIndexLock { loadIndex().backups.sorted { $0.timestamp > $1.timestamp } }
    }

    private func loadIndex() -> ModInstallBackupsIndex {
        guard let data = try? Data(contentsOf: metadataPath),
              let index = try? JSONDecoder().decode(ModInstallBackupsIndex.self, from: data) else {
            return ModInstallBackupsIndex()
        }
        return index
    }

    private func saveIndex(_ index: ModInstallBackupsIndex) {
        guard let data = try? JSONEncoder().encode(index) else { return }
        do {
            try data.write(to: metadataPath, options: .atomic)
        } catch {
            // Un backup peut déjà être sur disque (createBackup) sans être
            // référencé dans l'index → orphelin invisible (impossible à
            // restaurer/supprimer depuis l'UI). Consigner pour la traçabilité.
            print("CRITICAL: ModInstallBackup index write failed at \(metadataPath.path): \(error) — backups may be orphaned")
        }
    }

    /// Test-only seam (visible via `@testable import`) for seeding the
    /// index with pre-fabricated backups — lets tests exercise
    /// timestamp-dependent logic (like `cleanupOldBackups`'s retention
    /// tiers) without waiting real time or injecting a fake clock.
    /// Deliberately left internal (not `public`) — invisible to any real
    /// consumer of this library.
    func seedIndexForTesting(with backups: [ModInstallBackup]) {
        withIndexLock {
            var index = loadIndex()
            index.backups.append(contentsOf: backups)
            saveIndex(index)
        }
    }

    // MARK: - Create

    /// Backs up a complete mod folder before installation or update.
    public func createBackup(for mod: ModItem, gameDir: String, reason: BackupReason) throws -> ModInstallBackup {
        guard !gameDir.isEmpty else { throw InstallBackupError.gameDirEmpty }

        // A mod always lives under Mods/ now — disabled ones carry a leading
        // dot in `physicalFolderName`. This single source handles both states.
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let sourcePath = (modsPath as NSString).appendingPathComponent(mod.physicalFolderName)

        guard fm.fileExists(atPath: sourcePath) else {
            throw InstallBackupError.modNotFound(mod.folderName)
        }

        let timestamp = Date()
        let backupDir = backupDirectory(for: timestamp)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true, attributes: nil)

        let destPath = backupDir.appendingPathComponent(mod.folderName)

        do {
            // Pack/group children carry a nested folderName like
            // "PackName/ChildMod" (see ModItem.folderName / the scanner).
            // `backupDir` is created above, but the intermediate component
            // ("PackName") is not, so `copyItem` would fail mid-path. Create
            // the full parent chain first — mirroring ModConfigBackupManager,
            // which uses the same nested-folderName pattern.
            try fm.createDirectory(at: destPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(atPath: sourcePath, toPath: destPath.path)
        } catch {
            try? fm.removeItem(at: backupDir)
            throw InstallBackupError.backupCreationFailed(error.localizedDescription)
        }

        let metadata = ModMetadata(
            name: mod.name,
            version: mod.version,
            author: mod.author,
            uniqueId: mod.uniqueId
        )

        let backup = ModInstallBackup(
            timestamp: timestamp,
            originalFolderName: mod.folderName,
            backupPath: destPath.path,
            modMetadata: metadata,
            reason: reason
        )

        withIndexLock {
            var index = loadIndex()
            index.backups.append(backup)
            saveIndex(index)
        }

        return backup
    }

    private func backupDirectory(for timestamp: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // A UUID suffix guarantees each backup gets its own directory even
        // when several are created within the same second (e.g. a multi-mod
        // overwrite install). Without it, sibling backups would share one
        // timestamped folder and a single delete would wipe them all.
        return backupsDirPath.appendingPathComponent("\(formatter.string(from: timestamp))_\(UUID().uuidString)_install_backup", isDirectory: true)
    }

    // MARK: - Restore

    /// Restaure un mod sauvegardé dans le dossier `Mods/` du jeu.
    ///
    /// **Où il atterrit** : là où le mod se trouve déjà, actif (`Mods/Nom`)
    /// ou en pause (`Mods/.Nom`). Restaurer, c'est revenir à une version
    /// antérieure d'un mod qu'on a — pas en déposer une seconde copie à côté.
    /// Deux dossiers pour un même `folderName` mettraient en double la clé du
    /// registre d'installation, des profils et des sauvegardes (cf.
    /// `ModItem.physicalFolderName`), et le scanner en tirerait deux `ModItem`
    /// de même identité.
    ///
    /// Quand le mod n'est plus installé, il revient **en pause**, comme toute
    /// nouvelle installation : l'utilisateur l'active après relecture.
    public func restoreBackup(_ backup: ModInstallBackup, gameDir: String) throws {
        guard !gameDir.isEmpty else { throw InstallBackupError.gameDirEmpty }

        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let activePath = (modsPath as NSString).appendingPathComponent(backup.originalFolderName)
        let pausedPath = (modsPath as NSString).appendingPathComponent("." + backup.originalFolderName)
        // Les deux peuvent coexister : c'est précisément l'état que les
        // restaurations d'avant ce correctif laissaient derrière elles. Tout
        // ce qui est en place est mis de côté ; la destination est celle que
        // SMAPI lit, donc l'active dès qu'elle existe.
        let occupied = [activePath, pausedPath].filter { fm.fileExists(atPath: $0) }
        let destPath = occupied.first ?? pausedPath

        guard fm.fileExists(atPath: backup.backupPath) else {
            throw InstallBackupError.restoreFailed("Backup folder not found")
        }

        do {
            try fm.createDirectory(atPath: modsPath, withIntermediateDirectories: true, attributes: nil)

            // Chaque dossier mis de côté est suivi pour pouvoir être remis en
            // place si la copie échoue, ou enregistré comme sauvegarde une
            // fois la copie réussie — sans quoi un échec perdrait le mod
            // installé, et un succès jetterait la version remplacée sans
            // aucun moyen de défaire la restauration.
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            var setAside: [(original: String, stale: String)] = []
            for path in occupied {
                // Le suffixe UUID empêche deux restaurations du même mod dans
                // la même seconde de se disputer un seul chemin.
                let stale = path + ".stale_\(formatter.string(from: Date()))_\(UUID().uuidString)"
                try fm.moveItem(atPath: path, toPath: stale)
                setAside.append((path, stale))
            }

            do {
                // `originalFolderName` may be a nested path for a pack/group
                // child (e.g. "PackName/ChildMod"); ensure the intermediate
                // parent exists under Mods/ before copying.
                let destParent = (destPath as NSString).deletingLastPathComponent
                try fm.createDirectory(atPath: destParent, withIntermediateDirectories: true)
                try fm.copyItem(atPath: backup.backupPath, toPath: destPath)
            } catch {
                // Roll the set-aside folders back so a failed restore doesn't
                // leave the mod missing.
                for entry in setAside {
                    do {
                        try fm.moveItem(atPath: entry.stale, toPath: entry.original)
                    } catch {
                        print("CRITICAL: restore rollback failed — mod still in \(entry.stale) (could not move back to \(entry.original): \(error))")
                    }
                }
                throw error
            }

            // Restore succeeded — register the version it replaced as its
            // own backup rather than discarding it, so this restore is
            // itself undoable. Falls back to deleting it if that can't be
            // done (e.g. no readable manifest.json) rather than leaving a
            // ".stale_*" folder the mod scanner could pick up as a
            // duplicate/corrupt entry.
            for entry in setAside {
                if registerSetAsideFolderAsBackup(atPath: entry.stale, originalFolderName: backup.originalFolderName) == nil {
                    // Enregistrer comme backup a échoué (manifeste illisible) :
                    // on supprime le dossier mis de côté. La suppression robuste
                    // répare d'abord les perms en lecture seule (un mod installé
                    // avant `grantOwnerWriteAccess` peut encore en porter) — un
                    // simple `removeItem` échouait dessus et laissait un
                    // `.stale_*` oublié, remonté chez le scanner comme un mod en
                    // pause.
                    do {
                        try ModZipInstaller.removeItemGrantingWriteAccess(atPath: entry.stale)
                    } catch {
                        print("Warning: could not remove leftover .stale folder \(entry.stale) — it may resurface as a paused mod: \(error)")
                    }
                }
            }
        } catch {
            throw InstallBackupError.restoreFailed(error.localizedDescription)
        }
    }

    /// Best-effort metadata read from a mod folder's `manifest.json`,
    /// mirroring `ModZipInstaller`'s comment-stripping parse.
    private func extractMetadata(fromModFolder path: String) -> ModMetadata? {
        let manifestPath = (path as NSString).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let rawString = String(data: data, encoding: .utf8) else { return nil }
        // Même lecture JSON5 que le scan et l'installation : sans quoi un mod
        // au manifeste commenté serait sauvegardé sans métadonnées.
        guard let json = ManifestJSON.decode(rawString),
              let manifest = ModManifest(dict: json) else { return nil }
        return ModMetadata(name: manifest.name, version: manifest.version, author: manifest.author, uniqueId: manifest.uniqueId)
    }

    /// Registers a folder that was just set aside during a restore as its
    /// own backup (rather than deleting it outright), so the restore itself
    /// can be undone later. Returns nil (caller should then delete the
    /// folder directly) if metadata can't be read or the move fails.
    private func registerSetAsideFolderAsBackup(atPath stalePath: String, originalFolderName: String) -> ModInstallBackup? {
        guard let metadata = extractMetadata(fromModFolder: stalePath) else { return nil }
        let timestamp = Date()
        let backupDir = backupDirectory(for: timestamp)
        let destPath = backupDir.appendingPathComponent(originalFolderName)
        do {
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
            // `originalFolderName` may be a nested path for a pack/group
            // child (e.g. "PackName/ChildMod"); create the intermediate
            // parent chain before moving the set-aside folder in.
            try fm.createDirectory(at: destPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(atPath: stalePath, toPath: destPath.path)
        } catch {
            try? fm.removeItem(at: backupDir)
            return nil
        }

        let backup = ModInstallBackup(
            timestamp: timestamp,
            originalFolderName: originalFolderName,
            backupPath: destPath.path,
            modMetadata: metadata,
            reason: .beforeRestore
        )
        withIndexLock {
            var index = loadIndex()
            index.backups.append(backup)
            saveIndex(index)
        }
        return backup
    }

    // MARK: - Delete

    public func deleteBackup(_ backup: ModInstallBackup) throws {
        // `backupPath` points at the mod folder inside the timestamped
        // backup directory; its parent is the directory to remove. Using the
        // stored path is more robust than reconstructing it from the
        // timestamp format.
        let backupDir = URL(fileURLWithPath: backup.backupPath).deletingLastPathComponent()
        if fm.fileExists(atPath: backupDir.path) {
            // removeItemGrantingWriteAccess (pas removeItem) : les backups
            // héritent des perms read-only POSIX du mod source, et un removeItem
            // simple échouait dessus (audit 2026-08-05, même famille que M3).
            try ModZipInstaller.removeItemGrantingWriteAccess(atPath: backupDir.path)
        }

        withIndexLock {
            var index = loadIndex()
            index.backups.removeAll { $0.id == backup.id }
            saveIndex(index)
        }
    }

    // MARK: - Doublons stricts

    /// Supprime les sauvegardes dont les **octets** sont identiques à une
    /// autre du même mod, et rend leur nombre.
    ///
    /// La comparaison porte sur le contenu, jamais sur les métadonnées.
    /// Mesuré sur un parc réel le 2026-08-21 : parmi les sauvegardes de même
    /// mod **et même version**, 12 avaient un contenu différent — une
    /// traduction ou une configuration modifiée entre les deux. Dédupliquer
    /// sur `(mod, version)` aurait effacé ce travail ; sur les octets, il n'y
    /// a rien à perdre par construction. Le gain restait de 90 sauvegardes et
    /// 175 Mo sur ce même parc.
    ///
    /// La plus **récente** de chaque groupe survit : c'est sa date qui répond
    /// à « ce que j'avais avant ma dernière mise à jour ».
    ///
    /// `limitedTo` borne le travail à un mod — c'est ainsi qu'on l'appelle
    /// après une sauvegarde, là où le parc entier coûterait une empreinte de
    /// tout le dossier (8,6 s pour 1,1 Go sur la machine de mesure).
    @discardableResult
    public func purgeRedundantBackups(limitedTo uniqueId: String? = nil) -> Int {
        let candidates = loadBackups().filter {
            uniqueId == nil || modKey(of: $0) == uniqueId
        }
        var seenDigests: [String: Set<String>] = [:]
        var redundant: [ModInstallBackup] = []
        // `loadBackups` rend la plus récente d'abord : la première vue d'une
        // empreinte est donc celle qu'on garde.
        for backup in candidates {
            // Sans empreinte — dossier disparu, illisible — on ne conclut
            // rien : une suppression ne se décide jamais sur une absence.
            guard let digest = FolderDigest.of(URL(fileURLWithPath: backup.backupPath)) else {
                continue
            }
            let key = modKey(of: backup)
            if seenDigests[key, default: []].contains(digest) {
                redundant.append(backup)
            } else {
                seenDigests[key, default: []].insert(digest)
            }
        }
        var removed = 0
        for backup in redundant where (try? deleteBackup(backup)) != nil {
            removed += 1
        }
        return removed
    }

    /// L'identité qui autorise la comparaison : le **dossier d'origine**, pas
    /// le `UniqueID`.
    ///
    /// C'est vers ce dossier que la restauration réécrit, et c'est donc lui
    /// qui décide si deux sauvegardes répondent à la même question. Le
    /// `UniqueID` ne le peut pas : sur le parc de référence, un même mod est
    /// installé dans deux dossiers distincts — les dédupliquer priverait
    /// l'une des deux installations de sa sauvegarde. 111 mods n'ont d'ailleurs
    /// aucun `UniqueID`.
    private func modKey(of backup: ModInstallBackup) -> String {
        backup.originalFolderName
    }

    // MARK: - Cleanup

    /// Hybrid retention: keeps ALL backups ≤30 days, plus the most recent
    /// backup per calendar month for long-term history, and always at least
    /// the 5 most recent backups regardless of age. Returns the count of
    /// deleted backups.
    public func cleanupOldBackups() -> Int {
        withIndexLock {
            var index = loadIndex()
            let sorted = index.backups.sorted { $0.timestamp > $1.timestamp }
            guard sorted.count > Self.minBackupsToKeep else { return 0 }

            var protectedIds = Set<UUID>()

            // 1) Always keep the most recent N backups.
            for backup in sorted.prefix(Self.minBackupsToKeep) {
                protectedIds.insert(backup.id)
            }

            let cutoff = Date().addingTimeInterval(-Self.maxBackupAge)

            // 2) Keep every backup within the 30-day window.
            for backup in sorted {
                if backup.timestamp >= cutoff {
                    protectedIds.insert(backup.id)
                }
            }

            // 3) For backups beyond 30 days, keep the most recent one per
            //    calendar month (long-term history).
            var seenMonths = Set<String>()
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "yyyy-MM"
            monthFormatter.locale = Locale(identifier: "en_US_POSIX")
            for backup in sorted {
                guard backup.timestamp < cutoff else { continue }
                let monthKey = monthFormatter.string(from: backup.timestamp)
                if seenMonths.insert(monthKey).inserted {
                    protectedIds.insert(backup.id)
                }
            }

            let toDelete = sorted.filter { !protectedIds.contains($0.id) }
            guard !toDelete.isEmpty else { return 0 }

            // Only drop a backup's index entry once its on-disk folder is
            // actually confirmed gone — consistent with `deleteBackup`,
            // which never updates the index for a removal it can't verify
            // succeeded. A `try?`-then-unconditional-index-update here would
            // let the index silently diverge from what's really on disk.
            var removedIds = Set<UUID>()
            for backup in toDelete {
                let backupDir = URL(fileURLWithPath: backup.backupPath).deletingLastPathComponent()
                do {
                    if fm.fileExists(atPath: backupDir.path) {
                        try fm.removeItem(at: backupDir)
                    }
                    removedIds.insert(backup.id)
                } catch {
                    // Leave this one's index entry in place — its files are
                    // still on disk.
                }
            }
            guard !removedIds.isEmpty else { return 0 }

            index.backups.removeAll { removedIds.contains($0.id) }
            index.lastAutoCleanup = Date()
            saveIndex(index)

            return removedIds.count
        }
    }
}