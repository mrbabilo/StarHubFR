import Foundation

/// Une archive téléchargée de Nexus est-elle bien le fichier publié ?
///
/// Le manifeste récent d'un fichier Nexus porte l'empreinte SHA-256 de
/// l'archive déposée, et de sa version reconditionnée (`NexusFileManifest`).
/// L'app les lisait pour **reconnaître** une archive, jamais pour **vérifier**
/// qu'elle était intacte : une archive tronquée ou altérée en route
/// s'installait. Idée relevée chez JuniGrid 1.3.0 (contrôle md5 de ses
/// morceaux, relevé des sources du 2026-11-11) ; rien de son code n'est repris.
///
/// Mesuré le 2026-11-11 sur les archives conservées par l'app
/// (`NexusArchives`) : **224 sur 224** archives dont la version a encore un
/// manifeste récent correspondent à l'empreinte de l'archive déposée — aucune
/// fausse alerte. La comparaison se fait au manifeste **du fichier
/// téléchargé** (`fileId`), jamais à « un fichier de la même version » : trois
/// pages du parc publient plusieurs fichiers de même version, dont un seul est
/// le bon. Sans manifeste (format ancien, 18 archives sur 245 au relevé), on
/// s'abstient : rien n'est refusé faute de preuve.
public enum NexusArchiveIntegrity {
    public enum Verdict: Equatable, Sendable {
        case verified
        /// L'archive ne correspond à aucune des deux empreintes publiées.
        case mismatch
        /// Rien à comparer : on ne conclut pas.
        case unverifiable
    }

    public static func verdict(archiveSHA256: String?, manifest: NexusFileManifest?) -> Verdict {
        guard let manifest, let sha = archiveSHA256?.lowercased() else { return .unverifiable }
        let published = [manifest.archiveSHA256, manifest.repackedSHA256].compactMap { $0?.lowercased() }
        guard !published.isEmpty else { return .unverifiable }
        return published.contains(sha) ? .verified : .mismatch
    }

    /// Bloque son appelant (lecture réseau synchrone, comme
    /// `NexusFileManifestFetcher`) : depuis une file de fond, jamais depuis un
    /// `Task`. L'archive n'est hachée que si un manifeste existe.
    public static func check(archive: URL, modId: Int, fileId: Int,
                             cacheDirectory: URL? = NexusFileManifestFetcher.defaultCacheDirectory(),
                             transport: @escaping NexusFileManifestFetcher.Transport = NexusFileManifestFetcher.liveTransport,
                             now: Date = Date()) -> Verdict {
        guard let manifest = NexusFileManifestFetcher.manifest(
            modId: modId, fileId: fileId, cacheDirectory: cacheDirectory,
            deadline: now.addingTimeInterval(NexusFileManifestFetcher.perModTimeout), now: now,
            transport: transport) else { return .unverifiable }
        let sha: String
        do { sha = try ModFolderHasher.sha256(of: archive) } catch { return .unverifiable }
        return verdict(archiveSHA256: sha, manifest: manifest)
    }
}
