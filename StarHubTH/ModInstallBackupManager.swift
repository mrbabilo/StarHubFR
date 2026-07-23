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
        try? data.write(to: metadataPath, options: .atomic)
    }

    // MARK: - Create

    /// Backs up a complete mod folder before installation or update.
    public func createBackup(for mod: ModItem, gameDir: String, reason: BackupReason) throws -> ModInstallBackup {
        guard !gameDir.isEmpty else { throw InstallBackupError.gameDirEmpty }

        let modsDisabledPath = (gameDir as NSString).appendingPathComponent("Mods_disabled")
        let modsEnabledPath = (gameDir as NSString).appendingPathComponent("Mods")
        
        let sourcePath = mod.isEnabled 
            ? (modsEnabledPath as NSString).appendingPathComponent(mod.folderName)
            : (modsDisabledPath as NSString).appendingPathComponent(mod.folderName)

        guard fm.fileExists(atPath: sourcePath) else {
            throw InstallBackupError.modNotFound(mod.folderName)
        }

        let timestamp = Date()
        let backupDir = backupDirectory(for: timestamp)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true, attributes: nil)

        let destPath = backupDir.appendingPathComponent(mod.folderName)

        do {
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

    /// Restores a backed-up mod to the game's Mods_disabled folder.
    public func restoreBackup(_ backup: ModInstallBackup, gameDir: String) throws {
        guard !gameDir.isEmpty else { throw InstallBackupError.gameDirEmpty }

        let modsDisabledPath = (gameDir as NSString).appendingPathComponent("Mods_disabled")
        let destPath = (modsDisabledPath as NSString).appendingPathComponent(backup.originalFolderName)

        guard fm.fileExists(atPath: backup.backupPath) else {
            throw InstallBackupError.restoreFailed("Backup folder not found")
        }

        do {
            try fm.createDirectory(atPath: modsDisabledPath, withIntermediateDirectories: true, attributes: nil)

            // Track the set-aside path so it can be rolled back if the
            // restore copy below fails, or registered as its own backup once
            // the copy succeeds — otherwise a failed copy loses the live mod
            // entirely, and a successful one discards the replaced version
            // with no way to undo the restore itself.
            var stalePath: String?
            if fm.fileExists(atPath: destPath) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd_HHmmss"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                // A UUID suffix keeps two restores of the same mod within
                // the same second from colliding on one set-aside path.
                let path = destPath + ".stale_\(formatter.string(from: Date()))_\(UUID().uuidString)"
                try fm.moveItem(atPath: destPath, toPath: path)
                stalePath = path
            }

            do {
                try fm.copyItem(atPath: backup.backupPath, toPath: destPath)
            } catch {
                // Roll the set-aside folder back so a failed restore doesn't
                // leave the mod missing.
                if let stale = stalePath {
                    try? fm.moveItem(atPath: stale, toPath: destPath)
                }
                throw error
            }

            // Restore succeeded — register the version it replaced as its
            // own backup rather than discarding it, so this restore is
            // itself undoable. Falls back to deleting it if that can't be
            // done (e.g. no readable manifest.json) rather than leaving a
            // ".stale_*" folder the mod scanner could pick up as a
            // duplicate/corrupt entry.
            if let stale = stalePath {
                if registerSetAsideFolderAsBackup(atPath: stale, originalFolderName: backup.originalFolderName) == nil {
                    try? fm.removeItem(atPath: stale)
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
        let cleanString = rawString.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
        guard let cleanData = cleanString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: cleanData, options: [.allowFragments]) as? [String: Any],
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
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true, attributes: nil)
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
            try fm.removeItem(at: backupDir)
        }

        withIndexLock {
            var index = loadIndex()
            index.backups.removeAll { $0.id == backup.id }
            saveIndex(index)
        }
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