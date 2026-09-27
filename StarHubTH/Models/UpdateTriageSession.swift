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
        let archiveSHA256 = archive.flatMap { sha256(of: $0) }
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
            let sourceFileId = archiveSHA256.flatMap { sha in
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
}
