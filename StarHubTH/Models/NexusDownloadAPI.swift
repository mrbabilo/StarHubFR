import Foundation

/// Decodable models + pure helpers for the Nexus "download link" API surface.
/// Kept free of networking so it can be unit-tested; the actual URLSession
/// calls live in NexusDownloader (build-verified only).
///
/// Endpoint (verified against Nexus-Mods/node-nexus-api, 2026-07):
///   GET /v1/games/{game}/mods/{modId}/files/{fileId}/download_link.json
/// Premium accounts authenticate with the API key alone; non-premium accounts
/// MUST pass key+expires taken from an nxm:// link.
struct NexusModFile: Decodable {
    let fileId: Int
    let categoryId: Int
    /// Nom lisible de la catégorie côté Nexus (« MAIN », « OLD VERSION »,
    /// « MISC »). Décodé pour observabilité ; le tri se fait sur
    /// `categoryId`/`uploadedTimestamp`.
    let categoryName: String?
    let version: String?
    let modVersion: String?
    /// Timestamp Unix (secondes) de la mise en ligne de **ce fichier**. Source
    /// unique de vérité pour « le plus récent » : `updated_timestamp` du mod
    /// entier peut appartenir à un OPTIONAL plus récent que le MAIN.
    let uploadedTimestamp: Int?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case categoryId = "category_id"
        case categoryName = "category_name"
        case version
        case modVersion = "mod_version"
        case uploadedTimestamp = "uploaded_timestamp"
    }
}

struct NexusModFileList: Decodable {
    let files: [NexusModFile]
}

struct NexusDownloadLink: Decodable {
    let URI: String
}

enum NexusDownloadAPI {
    /// Plafond du nom de base retenu pour une archive téléchargée. APFS
    /// accepte 255 octets par composant ; le nom part dans un chemin, et un
    /// nom de 600 caractères ne dit rien de plus qu'un nom de 100.
    static let maxArchiveBaseNameLength = 100

    /// **Le nom que Nexus a donné à l'archive**, pour poser le téléchargement
    /// sous ce nom-là et pas sous un identifiant inventé.
    ///
    /// Ce nom n'est pas décoratif : c'est lui que `NexusArchiveName.parse`
    /// relit pour retrouver l'identifiant de la page et la version d'un dépôt
    /// posé à la main, et c'est lui que la fiche du mod affiche. Le
    /// téléchargement intégré déplaçait le fichier fini vers `<UUID>.zip` :
    /// relevé sur le registre réel, **4 dépôts sur 13** portaient un UUID
    /// comme nom — affiché tel quel, sans identifiant ni suivi de version, et
    /// impossible à rattacher ensuite puisqu'aucun titre ne concorde avec un
    /// UUID.
    ///
    /// Deux sources, dans cet ordre : ce que le service **déclare**
    /// (`Content-Disposition`), puis le chemin de l'URL du CDN, qui porte le
    /// nom du fichier. La query n'en fait pas partie.
    ///
    /// - Parameters:
    ///   - suggested: `URLResponse.suggestedFilename`, quand la réponse en
    ///     porte un. Foundation en invente un (`CFNetworkDownload_…`) quand
    ///     elle n'en porte pas : celui-là ne dit rien de plus qu'un UUID.
    ///   - url: l'URL demandée. Son dernier segment n'est retenu que s'il
    ///     ressemble à une archive — sinon on nommerait le fichier
    ///     « stardewvalley » ou « download_link.json ».
    /// - Returns: un nom de base **sans extension et sans séparateur de
    ///   chemin**, ou `nil` quand rien d'exploitable n'est venu — à l'appelant
    ///   de retomber sur un nom neuf. L'extension, elle, se déduit des octets
    ///   du fichier, jamais de son nom (cf. `ModZipInstaller
    ///   .detectedArchiveExtension`).
    static func archiveBaseName(suggested: String?, url: URL?) -> String? {
        if let declared = usableArchiveName(suggested, requiringArchiveExtension: false) {
            return declared
        }
        return usableArchiveName(url?.lastPathComponent, requiringArchiveExtension: true)
    }

    /// Un candidat de nom, décapé et rendu inoffensif, ou `nil`.
    private static func usableArchiveName(_ raw: String?,
                                          requiringArchiveExtension: Bool) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        // Dernier segment seulement. Le nom vient d'un service distant : un
        // séparateur qui survivrait écrirait ailleurs que dans le dossier
        // voulu (`../../etc/passwd`), et `:` en est un pour les API Carbon.
        guard let segment = raw.split(whereSeparator: { "/\\:".contains($0) }).last
        else { return nil }
        let candidate = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        // Un nom qui commence par un point est caché ou relatif, jamais une
        // archive nommée.
        guard !candidate.isEmpty, !candidate.hasPrefix(".") else { return nil }
        // Le nom que Foundation invente quand la réponse n'en porte aucun.
        guard !candidate.hasPrefix("CFNetworkDownload_") else { return nil }
        let ext = (candidate as NSString).pathExtension.lowercased()
        if requiringArchiveExtension, !ModZipInstaller.supportedExtensions.contains(ext) {
            return nil
        }
        let stripped = ModZipInstaller.strippingArchiveExtension(from: candidate)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty, stripped != ".", stripped != ".." else { return nil }
        return String(stripped.prefix(maxArchiveBaseNameLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Path (relative to the v1 API base) for a file's download links.
    /// Appends key+expires only when both are present (the free-user case).
    static func downloadLinkEndpoint(game: String, modId: Int, fileId: Int, key: String?, expires: Int?) -> String {
        let base = "/games/\(game)/mods/\(modId)/files/\(fileId)/download_link.json"
        if let key = key, let expires = expires {
            // Percent-encode the key so a value containing &, =, or + can't
            // break the query (Nexus keys are alphanumeric today, but be safe).
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            return "\(base)?key=\(encodedKey)&expires=\(expires)"
        }
        return base
    }

    static func decodeLinks(_ data: Data) throws -> [NexusDownloadLink] {
        try JSONDecoder().decode([NexusDownloadLink].self, from: data)
    }

    static func decodeFileList(_ data: Data) throws -> NexusModFileList {
        try JSONDecoder().decode(NexusModFileList.self, from: data)
    }

    /// Nexus file category 1 == "Main files". Prefer it; else fall back to the
    /// first file in the list.
    static func pickPrimaryFile(_ list: NexusModFileList) -> NexusModFile? {
        list.files.first { $0.categoryId == 1 } ?? list.files.first
    }

    /// Le MAIN le plus récent (par `uploaded_timestamp` décroissant) — X8 :
    /// l'ordre de la réponse n'est pas contractualisé par Nexus, et un mod à
    /// plusieurs MAIN verra son premier renvoyé être une version passée.
    /// Repli sur le plus récent toutes catégories s'il n'y a aucun MAIN.
    /// Un timestamp absent compte comme très ancien : il n'est jamais élu
    /// « plus récent » face à un fichier daté. `pickPrimaryFile` reste pour
    /// la résolution d'ID de téléchargement (`NexusDownloader.resolveFile`).
    static func pickLatestMainFile(_ list: NexusModFileList) -> NexusModFile? {
        let main = list.files.filter { $0.categoryId == 1 }
        let pool = main.isEmpty ? list.files : main
        return pool.max { (lhs, rhs) in
            (lhs.uploadedTimestamp ?? 0) < (rhs.uploadedTimestamp ?? 0)
        }
    }

    static func pickPrimaryFileId(_ list: NexusModFileList) -> Int? {
        pickPrimaryFile(list)?.fileId
    }

    /// L'id du MAIN le plus récent — ce que « télécharger ce mod » veut dire
    /// quand l'appelant ne désigne pas de fichier précis (install direct,
    /// traductions). Voir `pickLatestMainFile` pour la règle de tri.
    static func pickLatestMainFileId(_ list: NexusModFileList) -> Int? {
        pickLatestMainFile(list)?.fileId
    }
}
