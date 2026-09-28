import Foundation

/// A1-T11 plan 2 — « Nettoyer les anciens fichiers » : l'analyse d'un mod
/// (disque, journal local, Nexus récent **et ancien**), puis l'application.
///
/// ⚠️ Tout ici **bloque son appelant** (lecture Nexus synchrone,
/// `concurrentPerform`, sémaphore du transport) : à appeler depuis
/// `DispatchQueue.global`, jamais depuis un `Task` — le pool coopératif gèle
/// (CI du 2026-09-28).
public enum LegacyCleanupSession {
    /// Le nettoyage est demandé et attendu à l'écran : plus long que les 20 s
    /// par mod d'une mise à jour, une page peut compter 80 fichiers.
    public static let nexusDeadline: TimeInterval = 60

    /// Le dossier réel du mod : `physicalFolderName` (mod en pause `.X`,
    /// composant de pack `Pack/Composant`).
    public static func modFolder(for mod: ModItem, gameDir: String) -> URL {
        URL(fileURLWithPath: gameDir)
            .appendingPathComponent("Mods", isDirectory: true)
            .appendingPathComponent(mod.physicalFolderName, isDirectory: true)
    }

    public static func analyze(mod: ModItem, gameDir: String,
                               translations: InstalledTranslationRegistry,
                               customNexusIds: [String: String],
                               uniqueIdIsShared: Bool = false,
                               historyDirectory: URL? = ModHistoryFile.defaultDirectory(),
                               cacheDirectory: URL? = NexusFileManifestFetcher.defaultCacheDirectory(),
                               now: Date = Date(),
                               transport: @escaping NexusFileManifestFetcher.Transport
                                   = NexusFileManifestFetcher.liveTransport) -> LegacyFileCleanup.Outcome {
        let listing = ModFolderHasher.listing(of: modFolder(for: mod, gameDir: gameDir))
        let installedKeys = listing.byKey
        let history = ModHistoryFile.history(uniqueId: mod.uniqueId, directory: historyDirectory)
        // Un autre dossier porte le même `UniqueID` (Swim installé deux fois) :
        // le journal commun ne décrit pas celui-ci — même abstention que
        // `ModHistoryRecorder.recordInstall`. Ses dépôts restent exclus.
        let localVersions = uniqueIdIsShared ? [] : history.authorVersions

        var nexus = NexusFileManifestFetcher.Outcome(files: [], incomplete: false)
        let nexusId = NexusModIdentity.effectiveId(for: mod, customIds: customNexusIds)
        if NexusRequestBuilder.isValidModId(nexusId), let modId = Int(nexusId) {
            nexus = NexusFileManifestFetcher.fetch(
                modId: modId, cacheDirectory: cacheDirectory,
                deadline: now.addingTimeInterval(nexusDeadline), now: now,
                transport: transport, includeLegacy: true)
        }

        var deposits = history.depositedKeys
        for translation in translations.entries(forHost: mod.folderName) {
            deposits.formUnion(translation.files.map(ModFilePath.key))
        }
        let keys = Set(installedKeys.keys)
        let legacy = nexus.legacy.compactMap { file in
            file.manifest.paths(matching: keys).map {
                LegacyFileCleanup.LegacyVersion(fileId: file.fileId, version: file.version, paths: $0)
            }
        }
        return LegacyFileCleanup.plan(
            installed: listing,
            index: AuthorFileIndex.build(localVersions: localVersions,
                                         nexus: nexus.files, installed: installedKeys),
            legacy: legacy, installedVersion: mod.version,
            deposits: deposits, nexusIncomplete: nexus.incomplete,
            installedVersionFileIds: Set(nexus.listed.filter {
                NexusUpdateChecker.compare($0.version, mod.version) == .orderedSame
            }.map(\.fileId)))
    }

    public struct ApplyResult: Equatable, Sendable {
        public let removed: [ModHistory.File]
        /// Chemins non retirés : droits, chemin hors du dossier du mod, ou
        /// fichier modifié depuis l'analyse.
        public let failed: [String]
        /// `false` : le journal n'a pas pu être écrit (le nettoyage a eu lieu).
        public let historyWritten: Bool
    }

    public enum ApplyError: Error, Equatable {
        /// Pas de sauvegarde, donc rien de retiré.
        case backupFailed(String)
    }

    /// Sauvegarde le dossier, retire les fichiers choisis, efface les
    /// dossiers devenus vides, puis écrit une entrée « nettoyage » au journal.
    ///
    /// Chaque fichier est rehaché juste avant d'être retiré : le dossier a pu
    /// changer depuis l'analyse (une mise à jour, une retouche) — un fichier
    /// qui n'a plus les octets analysés est gardé.
    public static func apply(_ candidates: [LegacyFileCleanup.Candidate], mod: ModItem, gameDir: String,
                             backupManager: ModInstallBackupManager = .shared,
                             historyDirectory: URL? = ModHistoryFile.defaultDirectory(),
                             recordInHistory: Bool = true,
                             now: Date = Date()) throws -> ApplyResult {
        guard !candidates.isEmpty else { return ApplyResult(removed: [], failed: [], historyWritten: true) }
        do {
            _ = try backupManager.createBackup(for: mod, gameDir: gameDir, reason: .beforeCleanup)
        } catch {
            throw ApplyError.backupFailed(error.localizedDescription)
        }
        let folder = modFolder(for: mod, gameDir: gameDir).standardizedFileURL
        var removed: [ModHistory.File] = []
        var failed: [String] = []
        var parents: Set<URL> = []
        for candidate in candidates {
            let file = folder.appendingPathComponent(candidate.path).standardizedFileURL
            guard file.path.hasPrefix(folder.path + "/"), hasSameBytes(file, sha256: candidate.sha256) else {
                failed.append(candidate.path)
                continue
            }
            do {
                try removeGrantingParentWriteAccess(file)
                removed.append(.init(path: candidate.path, size: candidate.size, sha256: candidate.sha256))
                parents.insert(file.deletingLastPathComponent())
            } catch {
                failed.append(candidate.path)
            }
        }
        pruneEmptyDirectories(from: parents, upTo: folder)

        var historyWritten = true
        if recordInHistory, !removed.isEmpty {
            let entry = ModHistory.Entry(date: now, kind: .cleanup, fromVersion: nil, toVersion: mod.version,
                                         archiveSHA256: nil, nexusFileId: nil, source: nil,
                                         files: removed, report: nil)
            do {
                try ModHistoryFile.append(entry, uniqueId: mod.uniqueId, directory: historyDirectory, now: now)
            } catch {
                historyWritten = false
            }
        }
        return ApplyResult(removed: removed, failed: failed, historyWritten: historyWritten)
    }

    private static func hasSameBytes(_ file: URL, sha256: String) -> Bool {
        do {
            return try ModFolderHasher.sha256(of: file) == sha256
        } catch {
            return false
        }
    }

    /// `removeItemGrantingWriteAccess` n'ouvre que l'élément : dans un
    /// dossier en 0555 (cas réel du parc), c'est le **dossier parent** qu'il
    /// faut ouvrir pour y effacer une entrée. Ses droits d'origine lui sont
    /// rendus ensuite, retrait réussi ou non : l'ouverture ne sert qu'au
    /// retrait. Vaut pour un fichier comme pour un dossier vidé.
    private static func removeGrantingParentWriteAccess(_ item: URL) throws {
        do {
            try ModZipInstaller.removeItemGrantingWriteAccess(atPath: item.path)
        } catch {
            let parent = item.deletingLastPathComponent().path
            let fm = FileManager.default
            guard let mode = (try fm.attributesOfItem(atPath: parent))[.posixPermissions] as? NSNumber
            else { throw error }
            try fm.setAttributes([.posixPermissions: NSNumber(value: mode.uint16Value | 0o700)],
                                 ofItemAtPath: parent)
            defer {
                do {
                    try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: parent)
                } catch {
                    // Droits non rendus : le dossier reste ouvert en écriture,
                    // comme après une installation — le mod n'en souffre pas.
                }
            }
            try ModZipInstaller.removeItemGrantingWriteAccess(atPath: item.path)
        }
    }

    /// Les dossiers vidés par le retrait (`obj/Debug/` de FOTP), jusqu'au
    /// dossier du mod exclu. Un `.DS_Store` seul compte pour vide. Un parent
    /// en 0555 est ouvert le temps du retrait, comme pour un fichier.
    private static func pruneEmptyDirectories(from starts: Set<URL>, upTo root: URL) {
        let fm = FileManager.default
        for start in starts.sorted(by: { $0.path.count > $1.path.count }) {
            var directory = start.standardizedFileURL
            while directory.path.hasPrefix(root.path + "/") {
                let names: [String]
                do {
                    names = try fm.contentsOfDirectory(atPath: directory.path)
                } catch {
                    break
                }
                guard names.allSatisfy({ $0 == ".DS_Store" }) else { break }
                do {
                    try removeGrantingParentWriteAccess(directory)
                } catch {
                    break
                }
                directory = directory.deletingLastPathComponent()
            }
        }
    }
}
