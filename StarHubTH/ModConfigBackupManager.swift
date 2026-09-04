import Foundation

/// Backs up and restores enabled mods' `config.json` plus every
/// language/translation file (see `ModConfigFiles.preservable`).
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
        /// Every enabled mod was scanned but none had a config or language
        /// file to back up — distinct from `.noEnabledMods` (no mods to even
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

    /// Où les archives vivent réellement — la seule source de ce chemin.
    /// `StarHubTHViewModel.backupTranslation` y cherche les traductions
    /// perdues : avant cet accesseur, la VM reconstruisait le chemin par
    /// littéraux, et un changement de layout ici l'aurait fait chercher
    /// dans le vide, en silence.
    public var backupsDirectory: URL { backupsDirPath }

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
    ///
    /// `onlyEnabled: false` prend le mod **tel qu'il est**, en pause comprise :
    /// c'est ce dont l'éditeur de config a besoin avant d'écrire (C4-T5), où
    /// **379 des 462 mods à `config.json` du parc de référence sont en pause**.
    /// La voie par défaut ne bouge pas — une sauvegarde générale reste celle
    /// des mods actifs.
    public func createBackup(gameDir: String, mods: [ModItem], onlyEnabled: Bool = true) throws -> ModConfigBackup {
        guard !gameDir.isEmpty else { throw BackupError.gameDirEmpty }
        let selectedMods = onlyEnabled ? mods.filter { $0.isEnabled } : mods
        guard !selectedMods.isEmpty else { throw BackupError.noEnabledMods }

        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let timestamp = Date()
        let folderName = makeBackupFolderName(for: timestamp)
        let backupDir = backupDirURL(named: folderName)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        var items: [ModConfigBackupItem] = []
        var totalSize = 0

        for mod in selectedMods {
            for (leaf, parentFolderName) in Self.leafMods(of: mod, onlyEnabled: onlyEnabled) {
                // `leaf.folderName` is already the full path relative to
                // `Mods/` (e.g. "GroupFolder/ChildFolder" for a group's
                // child, or "PackFolder/ModX" for a standalone mod nested in
                // a subfolder — see ModItem.folderName / scanFolderForMods).
                // It's used as-is below (never reduced to its last path
                // component) so the backup/restore folder mirrors the real
                // on-disk location instead of a flattened one.
                // Le **chemin** passe par `physicalFolderName` (un mod en
                // pause porte un point) alors que la **clé** enregistrée reste
                // `folderName`, la forme logique que profils et restaurations
                // emploient. Pour un mod actif les deux coïncident : rien ne
                // change pour la sauvegarde générale.
                let leafPath = (modsPath as NSString).appendingPathComponent(leaf.physicalFolderName)
                let found = ModConfigFiles.preservableFiles(under: leafPath)
                guard !found.isEmpty else { continue }

                let destDir = destinationDir(in: backupDir, leafFolderName: leaf.folderName)
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

                var fileNames: [String] = []
                var fileSizes: [String: Int] = [:]
                for (relativePath, sourceURL) in found {
                    // Préserve le sous-dossier i18n/ (destDir/i18n/fr.json, pas
                    // destDir/fr.json) : sinon le restore aplatit et SMAPI ne
                    // retrouverait pas la traduction à son emplacement réel.
                    let destURL = destDir.appendingPathComponent(relativePath)
                    try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: destURL.path) {
                        try? fm.removeItem(at: destURL)
                    }
                    try fm.copyItem(at: sourceURL, to: destURL)
                    let size = (try? fm.attributesOfItem(atPath: destURL.path))?[.size] as? Int ?? 0
                    fileNames.append(relativePath)
                    fileSizes[relativePath] = size
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
    private static func leafMods(of mod: ModItem, onlyEnabled: Bool = true) -> [(leaf: ModItem, parentFolderName: String?)] {
        if mod.isGroup, let children = mod.children {
            let selected = onlyEnabled ? children.filter { $0.isEnabled } : children
            return selected.map { ($0, mod.folderName) }
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

    /// Fait suivre un renommage de dossier de mod dans l'index (X60).
    ///
    /// Une sauvegarde de configuration désigne son mod par son **nom de
    /// dossier** — `modFolderName`, et `parentFolderName` pour un composant de
    /// pack. Renommer le dossier sans le dire ici couperait le lien : la
    /// sauvegarde ne se rattacherait plus à aucun mod installé, l'écran
    /// d'entretien la compterait parmi ce qu'on peut retirer, et une
    /// restauration viserait un dossier qui n'existe plus.
    ///
    /// Le dossier de sauvegarde sur disque, lui, ne bouge pas : il porte un
    /// horodatage, jamais le nom du mod.
    ///
    /// - Returns: `true` si l'index a changé — l'appelant n'a rien à réécrire
    ///   sinon.
    @discardableResult
    /// - Parameter shared: `true` quand un **autre** mod réclame encore
    ///   l'ancien nom. Ces sauvegardes portent une configuration écrite à la
    ///   main, et rien ne dit pour lequel des deux : les emporter priverait le
    ///   mod resté en place de la sienne. Voir `ModFolderRename.SharedKeyPolicy`.
    public func renameMod(from old: String, to new: String, shared: Bool = false) -> Bool {
        guard !shared else { return false }
        return withIndexLock {
            var index = loadIndex()
            var changed = false
            index.backups = index.backups.map { backup in
                let items = backup.items.map { item -> ModConfigBackupItem in
                    var folder = item.modFolderName
                    var parent = item.parentFolderName
                    var touched = false
                    if folder == old || folder.hasPrefix(old + "/") {
                        folder = new + folder.dropFirst(old.count)
                        touched = true
                    }
                    if parent == old {
                        parent = new
                        touched = true
                    }
                    guard touched else { return item }
                    changed = true
                    return ModConfigBackupItem(modFolderName: folder,
                                               parentFolderName: parent,
                                               modDisplayName: item.modDisplayName,
                                               files: item.files,
                                               fileSizes: item.fileSizes)
                }
                guard changed else { return backup }
                return ModConfigBackup(id: backup.id, timestamp: backup.timestamp,
                                       items: items, totalFiles: backup.totalFiles,
                                       totalSize: backup.totalSize, folderName: backup.folderName)
            }
            if changed { saveIndex(index) }
            return changed
        }
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
    /// - Returns: ce qui a été écrit, et ce qui a été sauté. `@discardableResult`
    ///   parce que la valeur est un **ajout** : les appelants qui ne la lisent
    ///   pas gardent exactement le comportement d'avant.
    @discardableResult
    public func restoreBackup(gameDir: String, backup: ModConfigBackup, selectedItems: [ModConfigBackupItem], currentMods: [ModItem]) throws -> ModConfigRestoreReport {
        guard !gameDir.isEmpty else { throw BackupError.gameDirEmpty }

        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")

        // Le filet ne porte que sur ce qu'on s'apprête à écraser, et il prend
        // les mods **en pause** : c'est là que vivent presque toutes les
        // configurations (527 des 593 `config.json` du parc de référence). Le
        // prendre sur tout le parc coûterait un parcours complet de `Mods/` —
        // 93 784 entrées — pour sauvegarder des mods qu'on ne touche pas.
        let restoredNames = Set(selectedItems.map(\.modFolderName))
        let atRisk = currentMods.filter { mod in
            restoredNames.contains(mod.folderName)
                || (mod.children ?? []).contains { restoredNames.contains($0.folderName) }
        }
        if !atRisk.isEmpty {
            _ = try? createBackup(gameDir: gameDir, mods: atRisk, onlyEnabled: false)
        }

        let backupDir = backupDirURL(named: backup.folderName)

        var filesWritten = 0
        var modsRestored = 0
        var skippedMods: [String] = []
        var skippedFiles: [String] = []

        for item in selectedItems {
            let sourceDir = destinationDir(in: backupDir, leafFolderName: item.modFolderName)

            guard fm.fileExists(atPath: sourceDir.path) else {
                print("ModConfigBackup restore: source folder missing for \(item.modFolderName), skipping")
                skippedMods.append(item.modFolderName)
                continue
            }
            // Le dossier **réel** du mod, point compris. Sans cette résolution,
            // un mod en pause voyait sa configuration écrite dans un
            // `Mods/Nom` fabriqué à côté du `Mods/.Nom` bien réel : dossier
            // sans manifeste, donc invisible du scan comme du jeu, et
            // configuration jamais restaurée alors que l'app annonçait
            // « sauvegarde restaurée ».
            guard let targetDir = installedFolder(named: item.modFolderName, modsPath: modsPath) else {
                print("ModConfigBackup restore: mod folder missing for \(item.modFolderName), skipping")
                skippedMods.append(item.modFolderName)
                continue
            }
            // La racine du mod borne l'ouverture des droits ci-dessous : un
            // `i18n/` en lecture seule existe pour de bon sur le parc.
            let modRoot = Self.topLevelRoot(of: targetDir.path, under: modsPath)

            var writtenForThisMod = 0
            for relativePath in item.files {
                let source = sourceDir.appendingPathComponent(relativePath)
                guard fm.fileExists(atPath: source.path) else {
                    print("ModConfigBackup restore: file missing \(relativePath) for \(item.modFolderName), skipping")
                    skippedFiles.append("\(item.modFolderName)/\(relativePath)")
                    continue
                }
                // Même écriture que la récupération de fichiers : elle recrée
                // le sous-dossier `i18n/` disparu, retire l'existant et ouvre
                // les droits le temps de la copie. Une seule règle pour
                // « écrire un fichier dans un mod installé ».
                //
                // L'échec d'**un** fichier n'emporte pas les suivants : c'est
                // le contrat annoncé plus haut, et il n'était pas tenu — un
                // seul fichier impossible à écrire (verrouillé, appartenant à
                // un autre compte) abandonnait tous les mods restant à
                // restaurer, y compris ceux qui n'avaient aucun problème.
                do {
                    try RecoveredFileWriter.write(from: source.path,
                                                  to: targetDir.appendingPathComponent(relativePath).path,
                                                  modRoot: modRoot)
                    writtenForThisMod += 1
                } catch {
                    print("ModConfigBackup restore: could not write \(relativePath) for \(item.modFolderName): \(error)")
                    skippedFiles.append("\(item.modFolderName)/\(relativePath)")
                }
            }
            filesWritten += writtenForThisMod
            if writtenForThisMod > 0 { modsRestored += 1 }
        }

        return ModConfigRestoreReport(filesWritten: filesWritten,
                                      modsRestored: modsRestored,
                                      skippedMods: skippedMods,
                                      skippedFiles: skippedFiles)
    }

    /// Le dossier réel d'un mod sous `Mods/`, en pause compris — ou `nil` s'il
    /// n'est plus installé.
    ///
    /// Le point ne vit que sur l'entrée de premier niveau
    /// (`ModItem.physicalFolderName`), y compris pour un composant de pack :
    /// `Pack/Composant` en pause est `.Pack/Composant`, jamais
    /// `Pack/.Composant`.
    private func installedFolder(named logicalFolderName: String, modsPath: String) -> URL? {
        let direct = (modsPath as NSString).appendingPathComponent(logicalFolderName)
        if fm.fileExists(atPath: direct) { return URL(fileURLWithPath: direct) }

        var components = logicalFolderName.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return nil }
        components[0] = "." + components[0]
        let paused = (modsPath as NSString).appendingPathComponent(components.joined(separator: "/"))
        return fm.fileExists(atPath: paused) ? URL(fileURLWithPath: paused) : nil
    }

    /// Le dossier de tête sous `Mods/` dont dépend un chemin — la limite
    /// au-delà de laquelle on ne touche jamais aux droits.
    private static func topLevelRoot(of path: String, under modsPath: String) -> String {
        guard path.hasPrefix(modsPath + "/") else { return path }
        let relative = String(path.dropFirst(modsPath.count + 1))
        guard let head = relative.split(separator: "/").first.map(String.init) else { return path }
        return (modsPath as NSString).appendingPathComponent(head)
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

    // MARK: - Relecture d'un fichier sauvegardé

    /// La copie la plus récente d'un fichier de config, sans passer par une
    /// restauration.
    ///
    /// Ce que l'éditeur de config en fait : proposer un retour arrière en
    /// **chargeant** le fichier dans l'écran, l'utilisateur gardant la main
    /// sur l'écriture. C'est ce qui remplace le `config.json.bak` qu'il
    /// déposait à côté du fichier — invisible depuis l'écran des sauvegardes,
    /// et emporté par la prochaine sauvegarde générale.
    ///
    /// Une entrée d'index dont le fichier n'est plus sur le disque est
    /// **sautée**, pas rendue : le dossier de sauvegardes se supprime à la
    /// main, et un chemin mort ferait annoncer une restauration qui n'a pas eu
    /// lieu.
    public func mostRecentBackedUpFile(named relativePath: String,
                                       forMod modFolderName: String) -> (backup: ModConfigBackup, url: URL)? {
        for backup in loadBackups() {
            guard let item = backup.items.first(where: { $0.modFolderName == modFolderName }),
                  item.files.contains(relativePath) else { continue }
            let url = destinationDir(in: backupDirURL(named: backup.folderName),
                                     leafFolderName: item.modFolderName)
                .appendingPathComponent(relativePath)
            if fm.fileExists(atPath: url.path) { return (backup, url) }
        }
        return nil
    }

    /// La sauvegarde **du jour** qui protège déjà ce fichier, s'il y en a une.
    ///
    /// Ce qu'elle sert : replier les sauvegardes de l'éditeur de config **par
    /// mod et par jour**. Sans elle, dix réglages modifiés dans l'après-midi
    /// déposent dix entrées d'un seul mod en tête de l'écran des sauvegardes,
    /// devant les sauvegardes complètes.
    ///
    /// C'est la **première** du jour qui vaut filet, et elle n'est jamais
    /// remplacée : elle porte l'état avec lequel le jeu a tourné avant qu'on y
    /// touche. L'écraser à chaque enregistrement laisserait une mauvaise
    /// modification manger le filet en deux enregistrements — le défaut connu
    /// du `.bak` roulant qu'on vient de retirer.
    ///
    /// Une sauvegarde générale prise le même jour compte aussi : elle contient
    /// le fichier, donc elle protège.
    public func backupFromToday(protecting relativePath: String,
                                forMod modFolderName: String,
                                now: Date = Date(),
                                calendar: Calendar = .current) -> ModConfigBackup? {
        guard let found = mostRecentBackedUpFile(named: relativePath, forMod: modFolderName),
              calendar.isDate(found.backup.timestamp, inSameDayAs: now) else { return nil }
        return found.backup
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
