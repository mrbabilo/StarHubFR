import Foundation

/// Backs up and restores enabled mods' `config.json`/`fr.json` files.
///
/// Mirrors `SaveManager`'s style: a plain singleton with synchronous,
/// throwing methods. This class does no threading of its own — callers
/// (see `ModConfigBackupsView`) dispatch to a background queue and hop back
/// to main for UI updates, consistent with the rest of the codebase.
public class ModConfigBackupManager {
    public static let shared = ModConfigBackupManager()

    public enum BackupError: LocalizedError {
        case gameDirEmpty
        case noEnabledMods
        /// Every enabled mod was scanned but none had a config.json/fr.json
        /// to back up — distinct from `.noEnabledMods` (no mods to even
        /// consider).
        case nothingToBackUp

        public var errorDescription: String? {
            switch self {
            case .gameDirEmpty: return "Game directory is not set."
            case .noEnabledMods: return "No enabled mods to back up."
            case .nothingToBackUp: return "None of the enabled mods have config files to back up."
            }
        }
    }

    private let fm = FileManager.default
    private let backupsBasePath: URL
    private let backupsDirPath: URL
    private let metadataPath: URL

    // Guards every metadata.json read-modify-write cycle below. Without it,
    // two calls dispatched from different background queues (e.g. a manual
    // "create backup" racing an auto-cleanup, or two rapid deletes) can each
    // load the same old index, mutate their own copy, and the second
    // `saveIndex` silently discards the first call's change.
    private let indexLock = NSLock()

    private static let targetFiles: Set<String> = ["config.json", "fr.json"]
    private static let minBackupsToKeep = 5
    private static let maxBackupAge: TimeInterval = 30 * 24 * 60 * 60

    /// `backupsBasePath` is exposed only so tests can point this manager at
    /// an isolated temporary directory instead of the real Application
    /// Support folder. Production code always uses `.shared`, which calls
    /// this with `nil` and gets the exact same directory as before.
    public init(backupsBasePath overrideBasePath: URL? = nil) {
        let base = overrideBasePath ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("StarHubTH/Backups/ModConfigs", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("StarHubTH/Backups/ModConfigs", isDirectory: true)
        backupsBasePath = base
        backupsDirPath = base.appendingPathComponent("backups", isDirectory: true)
        metadataPath = base.appendingPathComponent("metadata.json")
        try? fm.createDirectory(at: backupsDirPath, withIntermediateDirectories: true)
    }

    // MARK: - Index

    private func withIndexLock<T>(_ body: () -> T) -> T {
        indexLock.lock()
        defer { indexLock.unlock() }
        return body()
    }

    /// All backups, most recent first. Falls back to an empty list if
    /// `metadata.json` is missing or corrupted — existing backup folders on
    /// disk are left untouched, just not listed, rather than risking a
    /// destructive "rebuild" that guesses at their original structure.
    public func loadBackups() -> [ModConfigBackup] {
        withIndexLock { loadIndex().backups.sorted { $0.timestamp > $1.timestamp } }
    }

    private func loadIndex() -> ModConfigBackupsIndex {
        guard let data = try? Data(contentsOf: metadataPath),
              let index = try? JSONDecoder().decode(ModConfigBackupsIndex.self, from: data) else {
            return ModConfigBackupsIndex()
        }
        return index
    }

    private func saveIndex(_ index: ModConfigBackupsIndex) {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: metadataPath, options: .atomic)
    }

    /// Test-only seam (visible via `@testable import`) for seeding the
    /// index with pre-fabricated backups — lets tests exercise
    /// timestamp-dependent logic (like `cleanupOldBackups`'s 30-day cutoff)
    /// without waiting real time or injecting a fake clock. Deliberately
    /// left internal (not `public`) — invisible to any real consumer of
    /// this library.
    func seedIndexForTesting(with backups: [ModConfigBackup]) {
        withIndexLock {
            var index = loadIndex()
            index.backups.append(contentsOf: backups)
            saveIndex(index)
        }
    }

    // MARK: - Create

    /// Backs up every enabled mod's config files (including enabled children
    /// of group packs) into a new timestamped folder, and records it in the
    /// index.
    public func createBackup(gameDir: String, mods: [ModItem]) throws -> ModConfigBackup {
        guard !gameDir.isEmpty else { throw BackupError.gameDirEmpty }
        let enabledMods = mods.filter { $0.isEnabled }
        guard !enabledMods.isEmpty else { throw BackupError.noEnabledMods }

        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let timestamp = Date()
        let folderName = makeBackupFolderName(for: timestamp)
        let backupDir = backupDirURL(named: folderName)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        var items: [ModConfigBackupItem] = []
        var totalSize = 0

        for mod in enabledMods {
            for (leaf, parentFolderName) in Self.leafMods(of: mod) {
                // `leaf.folderName` is already the full path relative to
                // `Mods/` (e.g. "GroupFolder/ChildFolder" for a group's
                // child, or "PackFolder/ModX" for a standalone mod nested in
                // a subfolder — see ModItem.folderName / scanFolderForMods).
                // It's used as-is below (never reduced to its last path
                // component) so the backup/restore folder mirrors the real
                // on-disk location instead of a flattened one.
                let leafPath = (modsPath as NSString).appendingPathComponent(leaf.folderName)
                let found = findConfigFiles(underModFolderPath: leafPath)
                guard !found.isEmpty else { continue }

                let destDir = destinationDir(in: backupDir, leafFolderName: leaf.folderName)
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

                var fileNames: [String] = []
                var fileSizes: [String: Int] = [:]
                for (filename, sourceURL) in found {
                    let destURL = destDir.appendingPathComponent(filename)
                    if fm.fileExists(atPath: destURL.path) {
                        try? fm.removeItem(at: destURL)
                    }
                    try fm.copyItem(at: sourceURL, to: destURL)
                    let size = (try? fm.attributesOfItem(atPath: destURL.path))?[.size] as? Int ?? 0
                    fileNames.append(filename)
                    fileSizes[filename] = size
                    totalSize += size
                }

                items.append(ModConfigBackupItem(
                    modFolderName: leaf.folderName,
                    parentFolderName: parentFolderName,
                    modDisplayName: leaf.name,
                    files: fileNames,
                    fileSizes: fileSizes
                ))
            }
        }

        guard !items.isEmpty else {
            // Nothing was actually found to back up — remove the (empty)
            // backup folder rather than creating and listing a backup with
            // zero content.
            try? fm.removeItem(at: backupDir)
            throw BackupError.nothingToBackUp
        }

        let backup = ModConfigBackup(
            timestamp: timestamp,
            items: items,
            totalFiles: items.reduce(0) { $0 + $1.files.count },
            totalSize: totalSize,
            folderName: folderName
        )

        withIndexLock {
            var index = loadIndex()
            index.backups.append(backup)
            saveIndex(index)
        }

        return backup
    }

    /// Standalone mods back up as themselves (`parentFolderName == nil`);
    /// group packs back up each *enabled* child individually, tagged with
    /// the group's folder name as `parentFolderName`. The group header
    /// itself has no files of its own (see `scanFolderForMods`) and is
    /// never scanned directly.
    private static func leafMods(of mod: ModItem) -> [(leaf: ModItem, parentFolderName: String?)] {
        if mod.isGroup, let children = mod.children {
            return children.filter { $0.isEnabled }.map { ($0, mod.folderName) }
        }
        return [(mod, nil)]
    }

    /// Joins a mod's full `Mods/`-relative folder name onto `baseDir`. Used
    /// both for a backup's own folder and for the live `Mods/` folder — the
    /// on-disk layout is identical in both places, so no separate
    /// group-prefix join is needed: `leafFolderName` already contains any
    /// nesting (e.g. "GroupFolder/ChildFolder").
    private func destinationDir(in baseDir: URL, leafFolderName: String) -> URL {
        baseDir.appendingPathComponent(leafFolderName)
    }

    /// Recursively finds `config.json`/`fr.json` anywhere under a single
    /// mod's folder.
    private func findConfigFiles(underModFolderPath path: String) -> [(filename: String, url: URL)] {
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var found: [(String, URL)] = []
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            if Self.targetFiles.contains(name) {
                found.append((name, fileURL))
            }
        }
        return found
    }

    /// Builds a fresh, unique folder name for a new backup. A UUID suffix
    /// guarantees each backup gets its own directory even when several are
    /// created within the same second (e.g. a manual backup racing an
    /// auto-triggered one) — without it, sibling backups would share one
    /// timestamped folder and a single delete would wipe them all.
    private func makeBackupFolderName(for timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "\(formatter.string(from: timestamp))_\(UUID().uuidString)_backup"
    }

    private func backupDirURL(named folderName: String) -> URL {
        backupsDirPath.appendingPathComponent(folderName, isDirectory: true)
    }

    // MARK: - Restore

    /// Restores the selected items from `backup` into `gameDir`'s Mods
    /// folder. Takes `currentMods` explicitly (rather than reading a
    /// ViewModel) so this class stays free of any ViewModel dependency —
    /// the caller supplies its own `vm.enabledMods`.
    ///
    /// A backup of the *current* state is taken first (best-effort — a
    /// failure here doesn't block the restore, since the user has already
    /// confirmed they want to overwrite). Missing source files/folders are
    /// skipped with a log line rather than aborting the whole restore.
    public func restoreBackup(gameDir: String, backup: ModConfigBackup, selectedItems: [ModConfigBackupItem], currentMods: [ModItem]) throws {
        guard !gameDir.isEmpty else { throw BackupError.gameDirEmpty }

        _ = try? createBackup(gameDir: gameDir, mods: currentMods)

        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let backupDir = backupDirURL(named: backup.folderName)

        for item in selectedItems {
            let sourceDir = destinationDir(in: backupDir, leafFolderName: item.modFolderName)
            let targetDir = destinationDir(in: URL(fileURLWithPath: modsPath), leafFolderName: item.modFolderName)

            guard fm.fileExists(atPath: sourceDir.path) else {
                print("ModConfigBackup restore: source folder missing for \(item.modFolderName), skipping")
                continue
            }

            // Propagate a real failure here instead of swallowing it — a
            // silently-failed mkdir would otherwise surface as a confusing
            // "file not found" from the `copyItem` calls below instead of
            // the actual cause.
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

            for filename in item.files {
                let source = sourceDir.appendingPathComponent(filename)
                guard fm.fileExists(atPath: source.path) else {
                    print("ModConfigBackup restore: file missing \(filename) for \(item.modFolderName), skipping")
                    continue
                }
                let target = targetDir.appendingPathComponent(filename)
                // copyItem throws if the destination already exists — which
                // it always does on a restore (the live config being
                // overwritten) — so the existing file must be removed first.
                if fm.fileExists(atPath: target.path) {
                    try? fm.removeItem(at: target)
                }
                try fm.copyItem(at: source, to: target)
            }
        }
    }

    // MARK: - Delete

    public func deleteBackup(_ backup: ModConfigBackup) throws {
        try deleteBackupFiles(backup)
        withIndexLock {
            var index = loadIndex()
            index.backups.removeAll { $0.id == backup.id }
            saveIndex(index)
        }
    }

    private func deleteBackupFiles(_ backup: ModConfigBackup) throws {
        let dir = backupDirURL(named: backup.folderName)
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
        }
    }

    // MARK: - Cleanup

    /// Deletes backups older than 30 days, but always keeps at least the 5
    /// most recent regardless of age — "more than 5 backups" does not mean
    /// "delete down past 5"; the 5 most recent are never eligible.
    public func cleanupOldBackups() -> Int {
        withIndexLock {
            var index = loadIndex()
            let sorted = index.backups.sorted { $0.timestamp > $1.timestamp }
            guard sorted.count > Self.minBackupsToKeep else { return 0 }

            let protectedIds = Set(sorted.prefix(Self.minBackupsToKeep).map { $0.id })
            let cutoff = Date().addingTimeInterval(-Self.maxBackupAge)
            let toDelete = sorted.filter { !protectedIds.contains($0.id) && $0.timestamp < cutoff }
            guard !toDelete.isEmpty else { return 0 }

            // Only drop a backup's index entry once its folder is
            // confirmed actually removed — a `try?`-then-unconditional
            // index update would let the index silently diverge from what's
            // really left on disk if a removal failed.
            var removedIds = Set<UUID>()
            for backup in toDelete {
                if (try? deleteBackupFiles(backup)) != nil {
                    removedIds.insert(backup.id)
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
