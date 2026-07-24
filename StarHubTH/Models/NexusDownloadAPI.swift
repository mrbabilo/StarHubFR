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
    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case categoryId = "category_id"
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
    static func pickPrimaryFileId(_ list: NexusModFileList) -> Int? {
        (list.files.first { $0.categoryId == 1 } ?? list.files.first)?.fileId
    }
}
