import Foundation

enum NexusDownloadError: Error, LocalizedError {
    case noApiKey
    case noValidFile
    case noDownloadLink
    case authFailed
    case rateLimited
    case serverError(Int)
    /// Reserved for genuine OS/URLSession failures; `%@` is the OS-localized
    /// `error.localizedDescription`, never a hand-written English string.
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .noApiKey:            return L10nKey("vm_nexus_dl_no_api_key")
        case .noValidFile:         return L10nKey("vm_nexus_dl_no_valid_file")
        case .noDownloadLink:      return L10nKey("vm_nexus_dl_no_link")
        case .authFailed:          return L10nKey("vm_nexus_dl_auth_failed")
        case .rateLimited:         return L10nKey("vm_nexus_dl_rate_limited")
        case .serverError(let c):  return String(format: L10nKey("vm_nexus_dl_server_error"), c)
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
    /// Builds the standard Nexus GET request via the shared `NexusRequestBuilder`
    /// so headers (User-Agent, Application-Name/Version, Accept, apikey) stay
    /// consistent with `NexusUpdateChecker`. Returns nil on invalid path so
    /// callers route to `.requestFailed(...)` instead of crashing.
    private func request(path: String, apiKey: String) -> URLRequest? {
        NexusRequestBuilder.makeRequest(path: path, apiKey: apiKey)
    }

    /// HTTP status codes Nexus uses to signal auth/rate-limit/premium problems
    /// that must not be misreported as "no file"/"no link" (see resolveFileId /
    /// fetchLinkAndDownload). `treatForbiddenAsPremium` distinguishes a 403 on
    /// the premium-only download_link.json call (no key/expires - the account
    /// simply isn't Premium) from a 403 that really means "bad API key".
    private func statusError(for response: URLResponse?, treatForbiddenAsPremium: Bool) -> NexusDownloadError? {
        guard let http = response as? HTTPURLResponse else { return nil }
        switch http.statusCode {
        case 200..<300: return nil
        case 401:       return .authFailed
        case 403:       return treatForbiddenAsPremium ? .noDownloadLink : .authFailed
        case 429:       return .rateLimited
        default:        return .serverError(http.statusCode)
        }
    }

    /// Fetches the mod's file list (used both to resolve the main file id and,
    /// post-install, to read the downloaded file's version/upload date).
    func getModFiles(modId: Int, completion: @escaping (Result<NexusModFileList, NexusDownloadError>) -> Void) {
        guard let apiKey = NexusUpdateChecker.shared.apiKey(), !apiKey.isEmpty else {
            completion(.failure(.noApiKey)); return
        }
        guard let req = request(path: "/games/\(NexusRequestBuilder.gameDomain)/mods/\(modId)/files.json", apiKey: apiKey) else {
            completion(.failure(.noDownloadLink)); return
        }
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(.requestFailed(error.localizedDescription))); return }
            if let statusError = self.statusError(for: response, treatForbiddenAsPremium: false) { completion(.failure(statusError)); return }
            guard let data = data, let list = try? NexusDownloadAPI.decodeFileList(data) else {
                completion(.failure(.noValidFile)); return
            }
            completion(.success(list))
        }.resume()
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
            resolveFileId(modId: modId) { result in
                switch result {
                case .success(let fid):
                    fetchLinkAndDownload(game: game, modId: modId, fileId: fid, key: key, expires: expires, apiKey: apiKey, completion: completion)
                case .failure(let e):
                    completion(.failure(e))
                }
            }
        }
    }

    private func resolveFileId(modId: Int,
                               completion: @escaping (Result<Int, NexusDownloadError>) -> Void) {
        getModFiles(modId: modId) { result in
            switch result {
            case .success(let list):
                guard let fid = NexusDownloadAPI.pickPrimaryFileId(list) else {
                    completion(.failure(.noValidFile)); return
                }
                completion(.success(fid))
            case .failure(let e):
                completion(.failure(e))
            }
        }
    }

    private func fetchLinkAndDownload(game: String, modId: Int, fileId: Int, key: String?, expires: Int?, apiKey: String,
                                      completion: @escaping (Result<URL, NexusDownloadError>) -> Void) {
        let path = NexusDownloadAPI.downloadLinkEndpoint(game: game, modId: modId, fileId: fileId, key: key, expires: expires)
        guard let req = request(path: path, apiKey: apiKey) else {
            completion(.failure(.noDownloadLink)); return
        }
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(.requestFailed(error.localizedDescription))); return }
            if let statusError = statusError(for: response, treatForbiddenAsPremium: (key == nil && expires == nil)) { completion(.failure(statusError)); return }
            guard let data = data else { completion(.failure(.noDownloadLink)); return }
            guard let links = try? NexusDownloadAPI.decodeLinks(data) else {
                completion(.failure(.noDownloadLink)); return
            }
            guard let uri = links.first?.URI, let url = URL(string: uri) else {
                completion(.failure(.noDownloadLink)); return
            }
            // Keep the real archive format. `extractArchive` dispatches on the
            // file extension, so naming every download ".zip" sent RAR mods
            // straight to `/usr/bin/unzip` and broke their update path — even
            // though drag-and-drop installs them fine. Nexus' CDN URL carries
            // the original filename in its path (…/Mod-1-2-3.rar?md5=…), which
            // the query string doesn't disturb. Anything unexpected falls back
            // to zip, the overwhelmingly common case.
            let ext = ModZipInstaller.supportedExtensions.contains(url.pathExtension.lowercased())
                ? url.pathExtension.lowercased()
                : "zip"
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
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
