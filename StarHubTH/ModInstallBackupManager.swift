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

    /// Fait suivre un renommage de dossier de mod dans l'index (X60).
    ///
    /// `originalFolderName` dit **où la restauration remettra le mod**. Sans ce
    /// suivi, restaurer après un renommage recréerait le dossier sous son
    /// ancien nom — soit, dans le cas qui motive X60, en plein sur le dossier
    /// du voisin avec lequel le nom était disputé.
    ///
    /// Le dossier de sauvegarde sur disque ne bouge pas : `backupPath` désigne
    /// une session horodatée, et son contenu est le mod tel qu'il était.
    ///
    /// - Returns: `true` si l'index a changé.
    @discardableResult
    /// - Parameter shared: `true` quand un **autre** mod réclame encore
    ///   l'ancien nom. L'historique d'installation est une affirmation sur un
    ///   mod, pas une préférence partageable : le déplacer volerait au mod
    ///   resté en place le sien. Voir `ModFolderRename.SharedKeyPolicy`.
    public func renameMod(from old: String, to new: String, shared: Bool = false) -> Bool {
        guard !shared else { return false }
        return withIndexLock {
            var index = loadIndex()
            var changed = false
            index.backups = index.backups.map { backup in
                let folder = backup.originalFolderName
                // Le mod lui-même, ou l'un de ses composants — jamais un voisin
                // dont le nom commence pareil (`Pack` ≠ `PackDeLuxe`).
                guard folder == old || folder.hasPrefix(old + "/") else { return backup }
                changed = true
                return ModInstallBackup(id: backup.id,
                                        timestamp: backup.timestamp,
                                        originalFolderName: new + folder.dropFirst(old.count),
                                        backupPath: backup.backupPath,
                                        modMetadata: backup.modMetadata,
                                        reason: backup.reason)
            }
            if changed { saveIndex(index) }
            return changed
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
            // La copie a pu poser une partie de l'arbre avant d'échouer, avec
            // les droits du mod source — souvent en lecture seule. Un
            // `removeItem` nu abandonnait alors le dossier horodaté sur le
            // disque : 19 coquilles du magasin réel portent cette signature
            // (même mod, même jour, plusieurs tentatives).
            try? ModZipInstaller.removeItemGrantingWriteAccess(atPath: backupDir.path)
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
        return backupsDirPath.appendingPathComponent(
            "\(formatter.string(from: timestamp))_\(UUID().uuidString)\(Self.backupDirectorySuffix)",
            isDirectory: true)
    }

    /// Ce qui termine le nom d'un dossier horodaté — écrit ici, reconnu par
    /// `backupDirectory(of:)`, nulle part ailleurs.
    private static let backupDirectorySuffix = "_install_backup"

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
    /// nouvelle installation : l'utilisateur l'active après relecture. Une
    /// exception, et une seule : un **composant de pack** n'a pas d'état à lui
    /// — il revient dans le pack tel qu'il est sur le disque, donc actif si le
    /// pack l'est (voir `freshDestination`). Le compte rendu le dit.
    ///
    /// - Returns: ce qui a été écrit et où, pour que la page le dise à
    ///   l'utilisateur au lieu d'un « restaurée avec succès » qui ne se
    ///   vérifie pas. `@discardableResult` : les appelants qui n'affichent
    ///   rien (tests de comportement disque) n'ont pas à le consommer.
    @discardableResult
    public func restoreBackup(_ backup: ModInstallBackup, gameDir: String) throws -> ModInstallRestoreReport {
        guard !gameDir.isEmpty else { throw InstallBackupError.gameDirEmpty }

        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let activePath = (modsPath as NSString).appendingPathComponent(backup.originalFolderName)
        let pausedPath = (modsPath as NSString).appendingPathComponent("." + backup.originalFolderName)
        // Les deux peuvent coexister : c'est précisément l'état que les
        // restaurations d'avant ce correctif laissaient derrière elles. Tout
        // ce qui est en place est mis de côté ; la destination est celle que
        // SMAPI lit, donc l'active dès qu'elle existe.
        let occupied = [activePath, pausedPath].filter { fm.fileExists(atPath: $0) }
        let destPath = occupied.first
            ?? freshDestination(activePath: activePath, pausedPath: pausedPath,
                                folderName: backup.originalFolderName, modsPath: modsPath)

        guard fm.fileExists(atPath: backup.backupPath) else {
            throw InstallBackupError.restoreFailed("Backup folder not found")
        }

        do {
            try fm.createDirectory(atPath: modsPath, withIntermediateDirectories: true, attributes: nil)

            // Un composant se restaure **dans** son pack : tout ce qui suit —
            // mise de côté, copie, archivage du dossier remplacé — écrit dans
            // le dossier de tête, et une bonne part du parc l'a en lecture
            // seule (`.[CP] Toothless Pet`, le seul dans ce cas aujourd'hui,
            // est justement un pack). Même mécanisme que la récupération de
            // fichiers : les droits sont ouverts le temps du geste puis rendus
            // tels quels, sans jamais remonter au-delà du dossier de tête.
            // Pour un mod ordinaire, la racine est le dossier à créer :
            // l'ouverture ne trouve rien et ne touche donc pas à `Mods/`.
            return try RecoveredFileWriter.withWriteAccess(
                to: destPath, modRoot: Self.topLevelRoot(of: destPath, under: modsPath)
            ) {
                // Chaque dossier mis de côté est suivi pour pouvoir être remis en
                // place si la copie échoue, ou enregistré comme sauvegarde une
                // fois la copie réussie — sans quoi un échec perdrait le mod
                // installé, et un succès jetterait la version remplacée sans
                // aucun moyen de défaire la restauration.
                var setAside: [(original: String, stale: String)] = []
                for path in occupied {
                    let stale = Self.setAsidePath(for: path, now: Date(), uuid: UUID().uuidString)
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
                var replacedVersions: [String] = []
                for entry in setAside {
                    if let registered = registerSetAsideFolderAsBackup(atPath: entry.stale, originalFolderName: backup.originalFolderName) {
                        replacedVersions.append(registered.modMetadata.version)
                    } else {
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

                // Le chemin lisible se déduit du chemin du jeu, pas d'une
                // reconstruction : `destPath` est celui où la copie a réellement
                // eu lieu.
                let displayPath = destPath.hasPrefix(gameDir + "/")
                    ? String(destPath.dropFirst(gameDir.count + 1))
                    : destPath
                return ModInstallRestoreReport(
                    modName: backup.modMetadata.name,
                    version: backup.modMetadata.version,
                    destinationPath: destPath,
                    displayPath: displayPath,
                    landedEnabled: destPath == activePath,
                    fileCount: Self.fileCount(at: destPath),
                    replacedVersions: replacedVersions)
            }
        } catch {
            throw InstallBackupError.restoreFailed(error.localizedDescription)
        }
    }

    /// Le dossier de tête sous `Mods/` dont dépend un chemin — la limite au-delà
    /// de laquelle on ne touche jamais aux droits. Pour `Mods/.Pack/Composant`,
    /// c'est `Mods/.Pack` ; pour `Mods/.Mod`, c'est le dossier lui-même, et
    /// l'ouverture des droits n'y trouve alors rien à faire.
    private static func topLevelRoot(of path: String, under modsPath: String) -> String {
        guard path.hasPrefix(modsPath + "/") else { return path }
        let relative = String(path.dropFirst(modsPath.count + 1))
        guard let head = relative.split(separator: "/").first.map(String.init) else { return path }
        return (modsPath as NSString).appendingPathComponent(head)
    }

    /// Où atterrit un mod dont **plus aucun** dossier n'est en place — le cas
    /// normal d'une restauration, puisqu'on restaure ce qu'on a perdu.
    ///
    /// Un mod ordinaire revient **en pause**, comme toute nouvelle
    /// installation. Un composant de pack, lui, n'a pas d'état à lui : le
    /// point ne vit que sur l'entrée de premier niveau (`physicalFolderName`
    /// vaut `(isEnabled ? "" : ".") + folderName`), et le scan fait hériter à
    /// chaque composant l'état du dossier de tête. Sa place est donc dans le
    /// pack **tel qu'il est sur le disque** : rendre `Pack/Composant` dans un
    /// `.Pack` fabriqué alors que `Pack` est là poserait un second dossier de
    /// même nom logique — exactement ce que cette méthode s'interdit — et
    /// laisserait le composant invisible au jeu comme à l'app (le
    /// sous-parcours du scan passe `.skipsHiddenFiles`).
    ///
    /// Conséquence assumée : dans un pack actif, le composant revient actif.
    /// C'est la seule forme qu'il puisse prendre là, et le compte rendu le
    /// dit (`landedEnabled`).
    private func freshDestination(activePath: String, pausedPath: String,
                                  folderName: String, modsPath: String) -> String {
        guard let packRoot = folderName.split(separator: "/").first.map(String.init),
              packRoot != folderName else { return pausedPath }
        let activeRoot = (modsPath as NSString).appendingPathComponent(packRoot)
        return fm.fileExists(atPath: activeRoot) ? activePath : pausedPath
    }

    /// Les fichiers réellement écrits — dossiers exclus. « 12 fichiers » se
    /// vérifie dans le Finder ; « restaurée avec succès » ne se vérifie pas.
    private static func fileCount(at path: String) -> Int {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: URL(fileURLWithPath: path),
                                         includingPropertiesForKeys: [.isRegularFileKey])
        else { return 0 }
        var count = 0
        for case let url as URL in walker
        where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            count += 1
        }
        return count
    }

    /// Le chemin où un dossier installé est mis de côté le temps d'une
    /// restauration, avant d'être archivé dans `Backups/`.
    ///
    /// Toujours **préfixé d'un point**, quel que soit l'état du mod remplacé :
    /// entre la mise de côté et l'archivage, ce dossier vit encore dans
    /// `Mods/`. Sans point, SMAPI le charge, et deux dossiers déclarant le
    /// même `UniqueID` sont une erreur qu'il signale au démarrage. Si l'app
    /// s'arrête entre les deux étapes, ce point est tout ce qui protège la
    /// partie.
    ///
    /// Le point va sur le **dernier composant** : masquer un enfant de pack
    /// en pointant le dossier du pack retirerait du jeu les mods voisins.
    ///
    /// - Parameters:
    ///   - now: l'instant de la mise de côté, lisible dans le nom.
    ///   - uuid: ce qui empêche deux restaurations du même mod dans la même
    ///     seconde de se disputer un seul chemin.
    static func setAsidePath(for path: String, now: Date, uuid: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let parent = (path as NSString).deletingLastPathComponent
        let leaf = (path as NSString).lastPathComponent
        // Un mod en pause porte déjà son point : en ajouter un second donne
        // `..Nom`, un chemin que le scanner ne retrouve pas.
        let hidden = leaf.hasPrefix(".") ? leaf : "." + leaf
        return (parent as NSString)
            .appendingPathComponent(hidden + ".stale_\(formatter.string(from: now))_\(uuid)")
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
            // Même raison qu'à la création : ce qui vient d'un dossier de mod
            // porte ses droits, et un `removeItem` nu laisse la coquille.
            try? ModZipInstaller.removeItemGrantingWriteAccess(atPath: backupDir.path)
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

    /// Le dossier horodaté d'une sauvegarde — celui qu'il faut supprimer pour
    /// n'en rien laisser.
    ///
    /// Ce n'est **pas** le parent de `backupPath` : pour un composant de pack,
    /// `backupPath` vaut `<horodaté>/Pack/Composant`, et son parent n'est que
    /// la coquille du pack. Supprimer celle-ci emportait bien les fichiers,
    /// mais laissait le dossier horodaté vide, absent de l'index donc
    /// invisible dans l'app et hors d'atteinte de tout ménage. Mesuré sur le
    /// magasin réel le 2026-09-03 : **1 262 dossiers pour 922 entrées**, soit
    /// 340 coquilles ; 373 des entrées restantes en produiraient une de plus.
    ///
    /// La règle est donc la position, pas la profondeur : le premier composant
    /// sous `backups/`. Un chemin qui ne s'y trouve pas, ou dont le premier
    /// composant ne porte pas le suffixe de nommage, retombe sur l'ancien
    /// calcul — une entrée d'index d'une version antérieure ou fabriquée à la
    /// main ne doit jamais faire remonter la suppression jusqu'à `backups/`.
    /// Le suffixe UUID garantit par ailleurs qu'un dossier horodaté n'abrite
    /// qu'une sauvegarde : y remonter ne peut pas emporter celle d'à côté.
    ///
    /// Public pour l'inventaire d'entretien (X25) : la passe de lecture et les
    /// actions de purge nomment les sessions par la même règle que celle qui
    /// les supprime — une seconde formule, fût-elle plus simple, référencerait
    /// mal les dossiers qu'elle prétend décrire.
    public func backupDirectory(of backup: ModInstallBackup) -> URL {
        let stored = URL(fileURLWithPath: backup.backupPath).standardizedFileURL
        let fallback = stored.deletingLastPathComponent()
        let base = backupsDirPath.standardizedFileURL.path
        guard stored.path.hasPrefix(base + "/") else { return fallback }
        let relative = String(stored.path.dropFirst(base.count + 1))
        guard let head = relative.split(separator: "/").first.map(String.init),
              head.hasSuffix(Self.backupDirectorySuffix) else { return fallback }
        return backupsDirPath.appendingPathComponent(head, isDirectory: true)
    }

    public func deleteBackup(_ backup: ModInstallBackup) throws {
        let backupDir = backupDirectory(of: backup)
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
                let backupDir = backupDirectory(of: backup)
                do {
                    if fm.fileExists(atPath: backupDir.path) {
                        // Même suppression que `deleteBackup` : une sauvegarde
                        // hérite des permissions du mod copié, et le parc en
                        // compte en lecture seule. Un `removeItem` nu échouait
                        // dessus — le ménage automatique gardait alors l'entrée
                        // d'index (à raison) et repoussait ces sauvegardes
                        // indéfiniment, sans jamais rien reprendre.
                        try ModZipInstaller.removeItemGrantingWriteAccess(atPath: backupDir.path)
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