import Foundation

enum NexusDownloadError: Error, LocalizedError {
    case noApiKey
    case noValidFile
    case noDownloadLink
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .noApiKey:            return L10nKey("vm_nexus_dl_no_api_key")
        case .noValidFile:         return L10nKey("vm_nexus_dl_no_valid_file")
        case .noDownloadLink:      return L10nKey("vm_nexus_dl_no_link")
        case .requestFailed(let m): return String(format: L10nKey("vm_nexus_dl_request_failed"), m)
        }
    }
    // Small localized-string helper (the ViewModel owns the language bundle;
    // here we fall back to the main bundle, which build_app.py populates).
    private func L10nKey(_ k: String) -> String { NSLocalizedString(k, comment: "") }
}

/// Downloads a Nexus mod file to a temp `.zip`, then hands the URL back to the
/// caller (which feeds it into ModZipInstaller). Two paths converge here:
///  - premium: key/expires nil → API key alone authorizes the link.
///  - free: key/expires from an nxm:// link.
/// Networking only; pure logic lives in NexusDownloadAPI (unit-tested).
struct NexusDownloader {
    private let apiBase = "https://api.nexusmods.com/v1"

    /// Mirrors NexusUpdateChecker's request headers so Nexus sees a consistent client.
    /// Returns nil if `path` doesn't form a valid URL, so callers can fail into
    /// `.requestFailed(...)` instead of crashing.
    private func request(path: String, apiKey: String) -> URLRequest? {
        guard let url = URL(string: apiBase + path) else { return nil }
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("StarHubTH", forHTTPHeaderField: "Application-Name")
        req.setValue("1.1.0", forHTTPHeaderField: "Application-Version")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    /// HTTP status codes Nexus uses to signal auth/rate-limit problems that must
    /// not be misreported as "no file"/"no link" (see resolveFileId / fetchLinkAndDownload).
    private func statusError(for response: URLResponse?) -> NexusDownloadError? {
        guard let http = response as? HTTPURLResponse else { return nil }
        switch http.statusCode {
        case 200..<300: return nil
        case 401, 403:  return .requestFailed("authentication failed (check your Nexus API key)")
        case 429:       return .requestFailed("rate limited by Nexus, try again later")
        default:        return .requestFailed("unexpected server response (\(http.statusCode))")
        }
    }

    /// If `fileId` is nil, first resolves the main file id via the files list.
    func download(modId: Int, fileId: Int?, game: String, key: String?, expires: Int?,
                  completion: @escaping (Result<URL, NexusDownloadError>) -> Void) {
        guard let apiKey = NexusUpdateChecker.shared.apiKey(), !apiKey.isEmpty else {
            completion(.failure(.noApiKey)); return
        }
        if let fileId = fileId {
            fetchLinkAndDownload(game: game, modId: modId, fileId: fileId, key: key, expires: expires, apiKey: apiKey, completion: completion)
        } else {
            resolveFileId(game: game, modId: modId, apiKey: apiKey) { result in
                switch result {
                case .success(let fid):
                    fetchLinkAndDownload(game: game, modId: modId, fileId: fid, key: key, expires: expires, apiKey: apiKey, completion: completion)
                case .failure(let e):
                    completion(.failure(e))
                }
            }
        }
    }

    private func resolveFileId(game: String, modId: Int, apiKey: String,
                               completion: @escaping (Result<Int, NexusDownloadError>) -> Void) {
        guard let req = request(path: "/games/\(game)/mods/\(modId)/files.json", apiKey: apiKey) else {
            completion(.failure(.requestFailed("invalid URL"))); return
        }
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(.requestFailed(error.localizedDescription))); return }
            if let statusError = statusError(for: response) { completion(.failure(statusError)); return }
            guard let data = data else { completion(.failure(.noValidFile)); return }
            guard let list = try? NexusDownloadAPI.decodeFileList(data) else {
                completion(.failure(.requestFailed("unexpected response"))); return
            }
            guard let fid = NexusDownloadAPI.pickPrimaryFileId(list) else {
                completion(.failure(.noValidFile)); return
            }
            completion(.success(fid))
        }.resume()
    }

    private func fetchLinkAndDownload(game: String, modId: Int, fileId: Int, key: String?, expires: Int?, apiKey: String,
                                      completion: @escaping (Result<URL, NexusDownloadError>) -> Void) {
        let path = NexusDownloadAPI.downloadLinkEndpoint(game: game, modId: modId, fileId: fileId, key: key, expires: expires)
        guard let req = request(path: path, apiKey: apiKey) else {
            completion(.failure(.requestFailed("invalid URL"))); return
        }
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(.requestFailed(error.localizedDescription))); return }
            if let statusError = statusError(for: response) { completion(.failure(statusError)); return }
            guard let data = data else { completion(.failure(.noDownloadLink)); return }
            guard let links = try? NexusDownloadAPI.decodeLinks(data) else {
                completion(.failure(.requestFailed("unexpected response"))); return
            }
            guard let uri = links.first?.URI, let url = URL(string: uri) else {
                completion(.failure(.noDownloadLink)); return
            }
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
            URLSession.shared.downloadTask(with: url) { localURL, _, dlError in
                if let dlError = dlError { completion(.failure(.requestFailed(dlError.localizedDescription))); return }
                guard let localURL = localURL else { completion(.failure(.noDownloadLink)); return }
                do {
                    try FileManager.default.moveItem(at: localURL, to: temp)
                    completion(.success(temp))
                } catch {
                    completion(.failure(.requestFailed(error.localizedDescription)))
                }
            }.resume()
        }.resume()
    }
}
