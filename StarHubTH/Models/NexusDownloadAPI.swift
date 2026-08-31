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
