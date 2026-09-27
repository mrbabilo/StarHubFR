import Foundation

/// Le fournisseur réel : journal local, manifestes Nexus récents, dépôts
/// connus de l'app, empreintes des deux dossiers.
///
/// Appelé par `ModZipInstaller.install` sur sa file de fond, un mod à la
/// fois — la lecture Nexus (jusqu'à `NexusFileManifestFetcher.perModTimeout`
/// par mod) se fait donc pendant l'installation, sous l'indicateur existant.
public enum UpdateTriageSession {
    /// - Parameters:
    ///   - translations: le registre des traductions posées (règle 2), pris
    ///     sur le fil principal avant l'installation.
    ///   - customNexusIds: les identifiants Nexus saisis à la main, par nom
    ///     de dossier (`NexusModIdentity.effectiveId`).
    ///   - archive: l'archive installée, pour identifier son fichier Nexus
    ///     par empreinte.
    public static func provider(translations: InstalledTranslationRegistry,
                                customNexusIds: [String: String],
                                archive: URL?,
                                historyDirectory: URL? = ModHistoryFile.defaultDirectory(),
                                cacheDirectory: URL? = NexusFileManifestFetcher.defaultCacheDirectory(),
                                transport: @escaping NexusFileManifestFetcher.Transport
                                    = NexusFileManifestFetcher.liveTransport) -> UpdateTriageProvider {
        // Lue au premier plan demandé, sur la file de fond de l'installateur —
        // jamais ici : le fournisseur se construit sur le fil principal, et
        // une archive pèse jusqu'à des centaines de Mo. Une seule lecture pour
        // tous les composants d'un pack.
        let archiveHash = ArchiveHash(archive: archive)
        return UpdateTriageProvider { existing, installedFolder, newSource in
            let installed = ModFolderHasher.listing(of: installedFolder)
            let newArchive = ModFolderHasher.listing(of: newSource)
            let history = ModHistoryFile.history(uniqueId: existing.uniqueId, directory: historyDirectory)

            var nexus = NexusFileManifestFetcher.Outcome(files: [], incomplete: false)
            let nexusId = NexusModIdentity.effectiveId(for: existing, customIds: customNexusIds)
            if NexusRequestBuilder.isValidModId(nexusId), let modId = Int(nexusId) {
                let now = Date()
                nexus = NexusFileManifestFetcher.fetch(
                    modId: modId, cacheDirectory: cacheDirectory,
                    deadline: now.addingTimeInterval(NexusFileManifestFetcher.perModTimeout),
                    now: now, transport: transport)
            }

            var deposits = history.depositedKeys
            for translation in translations.entries(forHost: existing.folderName) {
                deposits.formUnion(translation.files.map(ModFilePath.key))
            }
            let sourceFileId = archiveHash.value.flatMap { sha in
                nexus.files.first { $0.manifest.archiveSHA256 == sha || $0.manifest.repackedSHA256 == sha }?.fileId
            }
            return UpdateFileTriage.plan(
                installed: installed, newArchive: newArchive,
                index: AuthorFileIndex.build(localVersions: history.authorVersions,
                                             nexus: nexus.files, installed: installed.byKey),
                installedVersion: existing.version, deposits: deposits,
                nexusIncomplete: nexus.incomplete, sourceFileId: sourceFileId)
        }
    }

    /// L'empreinte de l'archive, `nil` si elle ne se lit pas : on perd alors
    /// seulement l'identification du fichier Nexus, jamais l'installation.
    static func sha256(of archive: URL) -> String? {
        do {
            return try ModFolderHasher.sha256(of: archive)
        } catch {
            return nil
        }
    }

    /// L'empreinte d'une archive, calculée une fois, à la première demande.
    private final class ArchiveHash: @unchecked Sendable {
        private let lock = NSLock()
        private let archive: URL?
        private var computed = false
        private var sha: String?

        init(archive: URL?) {
            self.archive = archive
        }

        var value: String? {
            lock.withLock {
                if !computed {
                    computed = true
                    sha = archive.flatMap { UpdateTriageSession.sha256(of: $0) }
                }
                return sha
            }
        }
    }
}
