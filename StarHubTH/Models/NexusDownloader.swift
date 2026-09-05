import Foundation

/// Le fruit d'un téléchargement abouti : l'archive posée, et le fichier Nexus
/// qu'elle matérialise quand l'app l'a **choisi** elle-même (MAIN le plus
/// récent, résolu via files.json). Un lien `nxm://` désigne son fichier
/// explicitement : X9 n'interroge pas la liste en plus pour le dater, donc
/// `resolvedFile` y reste nil.
struct NexusDownloadOutcome {
    let zip: URL
    let resolvedFile: NexusModFile?
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

    /// HTTP status codes Nexus uses to signal auth/rate-limit/premium/link
    /// problems that must not be misreported as "no file"/"no link" (see
    /// resolveFile / fetchLinkAndDownload). `forbiddenMeaning` says what a 403
    /// announces **on this call** — premium-only endpoint, expired nxm:// or
    /// CDN link, or a genuine auth refusal.
    ///
    /// Relève **aussi** le quota Nexus au passage (B2-T6) — d'où le nom : la
    /// fonction n'est pas une simple question. C'est le seul point où les trois
    /// réponses du téléchargement convergent ; les dupliquer sur trois sites
    /// serait l'occasion d'en oublier un. Celle du CDN ne porte aucun en-tête
    /// `x-rl-*` — `NexusQuota` la reconnaît comme muette et laisse la mesure
    /// précédente intacte.
    /// X67 — le relevé passe par `noteRateLimitIfThrottled`, qui **arme aussi
    /// la porte de limitation partagée** sur un 429. Ce site n'appelait que
    /// `noteQuota` : il reconnaissait pourtant le 429 (`statusError` le rend en
    /// `.rateLimited`) sans que rien ne freine la suite. C'est la **même API v1**
    /// que `fetchModInfo`, qui arme, elle — une asymétrie pure, sans la
    /// question de budget partagé que pose le GraphQL v2. Et le téléchargement
    /// est le geste le plus cher en quota : un 429 non vu y aggrave le
    /// bannissement au lieu de l'attendre.
    private func noteQuotaAndStatusError(for response: URLResponse?,
                                         forbiddenMeaning: Forbidden403Meaning) -> NexusDownloadError? {
        guard let http = response as? HTTPURLResponse else { return nil }
        NexusUpdateChecker.shared.noteRateLimitIfThrottled(http)
        return NexusDownloadAPI.statusError(http.statusCode, forbiddenMeaning: forbiddenMeaning)
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
            if let statusError = self.noteQuotaAndStatusError(for: response, forbiddenMeaning: .authProblem) { completion(.failure(statusError)); return }
            guard let data = data, let list = try? NexusDownloadAPI.decodeFileList(data) else {
                completion(.failure(.noValidFile)); return
            }
            completion(.success(list))
        }.resume()
    }

    /// If `fileId` is nil, first resolves the main file via the files list.
    ///
    /// Rend l'objet du téléchargement : c'est **le** point d'annulation, et il
    /// existe dès maintenant — donc avant même que le lien ne soit résolu, ce
    /// qui prend deux appels d'API. Annuler pendant cette résolution doit
    /// marcher aussi.
    ///
    /// Toutes les sorties passent par lui, y compris les échecs d'API : c'est
    /// ce qui rend « la complétion est appelée une fois exactement » vrai du
    /// flux entier, et pas seulement du transfert (voir `NexusFileDownload`).
    @discardableResult
    func download(modId: Int, fileId: Int?, game: String, key: String?, expires: Int?,
                  onProgress: NexusFileDownload.ProgressHandler? = nil,
                  completion: @escaping (Result<NexusDownloadOutcome, NexusDownloadError>) -> Void)
        -> NexusFileDownload {
        // X9 : le fichier résolu n'est connu qu'au retour de files.json —
        // après la création du téléchargement. La complétion le lit au moment
        // où elle rend la main, jamais avant.
        final class ResolvedBox { var file: NexusModFile? }
        let resolved = ResolvedBox()
        let download = NexusFileDownload(
            validate: { response in
                // Le CDN peut renvoyer une page HTML (403 lien expiré, 429
                // limite de débit) au lieu de l'archive : sans ce contrôle,
                // elle était sauvée comme le fichier du mod. Un 403 sur le
                // CDN n'annonce ni une clé premium ni une clé refusée, mais
                // un lien périmé — le message doit dire lequel.
                self.noteQuotaAndStatusError(for: response, forbiddenMeaning: .expiredLink)
            },
            onProgress: onProgress,
            completion: { result in
                completion(result.map { NexusDownloadOutcome(zip: $0, resolvedFile: resolved.file) })
            })

        guard let apiKey = NexusUpdateChecker.shared.apiKey(), !apiKey.isEmpty else {
            download.complete(.failure(.noApiKey)); return download
        }
        if let fileId = fileId {
            fetchLinkAndDownload(game: game, modId: modId, fileId: fileId, key: key,
                                 expires: expires, apiKey: apiKey, download: download)
        } else {
            resolveFile(modId: modId) { result in
                switch result {
                case .success(let file):
                    resolved.file = file
                    fetchLinkAndDownload(game: game, modId: modId, fileId: file.fileId, key: key,
                                         expires: expires, apiKey: apiKey, download: download)
                case .failure(let e):
                    download.complete(.failure(e))
                }
            }
        }
        return download
    }

    private func resolveFile(modId: Int,
                             completion: @escaping (Result<NexusModFile, NexusDownloadError>) -> Void) {
        getModFiles(modId: modId) { result in
            switch result {
            case .success(let list):
                // X8 — le plus récent MAIN, pas le premier renvoyé : pour un
                // mod à plusieurs MAIN, « installer ce mod » désigne la
                // dernière version publiée, pas une version passée. X9 : le
                // fichier **entier** remonte — l'ancre d'installation en fait
                // ses faits (identifiant + date de mise en ligne).
                guard let file = NexusDownloadAPI.pickLatestMainFile(list) else {
                    completion(.failure(.noValidFile)); return
                }
                completion(.success(file))
            case .failure(let e):
                completion(.failure(e))
            }
        }
    }

    private func fetchLinkAndDownload(game: String, modId: Int, fileId: Int, key: String?,
                                      expires: Int?, apiKey: String,
                                      download: NexusFileDownload) {
        let path = NexusDownloadAPI.downloadLinkEndpoint(game: game, modId: modId, fileId: fileId, key: key, expires: expires)
        guard let req = request(path: path, apiKey: apiKey) else {
            download.complete(.failure(.noDownloadLink)); return
        }
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                download.complete(.failure(.requestFailed(error.localizedDescription))); return
            }
            if let statusError = noteQuotaAndStatusError(
                for: response,
                // Sans clé nxm://, c'est l'appel réservé aux Premium ; avec,
                // un 403 dit que la clé nxm — à usage unique et courte
                // durée — est périmée, pas que l'API key est refusée.
                forbiddenMeaning: (key == nil && expires == nil) ? .premiumRequired : .expiredLink) {
                download.complete(.failure(statusError)); return
            }
            guard let data = data else { download.complete(.failure(.noDownloadLink)); return }
            guard let links = try? NexusDownloadAPI.decodeLinks(data) else {
                download.complete(.failure(.noDownloadLink)); return
            }
            guard let uri = links.first?.URI, let url = URL(string: uri) else {
                download.complete(.failure(.noDownloadLink)); return
            }
            // Le transfert lui-même vit dans `NexusFileDownload` : c'est lui
            // qui rapporte la progression, accepte l'annulation, et déplace le
            // fichier avant qu'`URLSession` ne le supprime.
            download.start(url: url)
        }.resume()
    }
}
