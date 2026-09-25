import Foundation

/// Client Nexus pour le ponctuel : fiche à la demande, description,
/// changelogs, et les caches partagés (catégories, résumés/images, liste de
/// mises à jour) que `checkNexusUpdates` lit au lancement.
/// ⚠️ Ne détecte plus les mises à jour (ancien `check()`, ~850 requêtes) :
/// c'est smapi.io, en quelques lots (`SmapiUpdateClient`).
/// API publique Nexus ; clé personnelle de l'utilisateur, au Trousseau.
/// `@unchecked` : état d'instance (`metadataGeneration`, `rateLimitGate`)
/// sous le verrou qui le nomme. `legacyNexusFormatter`, statique, hors
/// périmètre.
final class NexusUpdateChecker: @unchecked Sendable {
    static let shared = NexusUpdateChecker()

    // Client identity centralized in `NexusRequestBuilder` (one client for
    // Nexus).

    /// Last update list (`[ModUpdate]` JSON) : la **vérité**, à plat ;
    /// l'affichage en est la consolidation par pack.
    private let cachedUpdatesKey = "nexusCachedUpdates"
    /// Epoch of the last check that answered (A2-T4 TTL gate); a failure
    /// writes nothing.
    private let lastCheckedKey = "nexusUpdatesLastCheckedAt"
    /// `{ "modId": categoryId }` for every queried mod, kept apart from
    /// updates (categories apply to all mods).
    private let cachedCategoriesKey = "nexusCachedCategories"
    /// `{ "modId": NexusModExtra }` (summary + picture), same lifetime.
    private let cachedExtrasKey = "nexusCachedExtras"

    /// Guards metadata-cache mutations (overlapping fetches lose nothing).
    private let metadataCacheLock = NSLock()
    /// Bumped by `clearApiKey()`: an in-flight fetch compares it before
    /// persisting and discards results from the removed account.
    private var metadataGeneration = 0

    /// Back-off partagé après un 429, armé et lu par les trois chemins réseau.
    private var rateLimitGate = NexusRateLimitGate()
    private let rateLimitLock = NSLock()

    private init() {}

    /// `true` : refuser sans partir (relâché à l'expiration).
    private func isRateLimited() -> Bool {
        rateLimitLock.lock()
        defer { rateLimitLock.unlock() }
        return rateLimitGate.isBlocked()
    }

    /// Arme la porte pour tous ; le quota relevé (fenêtre épuisée) prime sur
    /// `Retry-After` plafonné (B2-T8).
    private func noteRateLimit(retryAfter: TimeInterval, quota: NexusQuota?) {
        rateLimitLock.lock()
        rateLimitGate.note(retryAfter: retryAfter, quota: quota)
        rateLimitLock.unlock()
    }

    /// Attente restante, pour un `.rateLimited` refusé localement.
    private func rateLimitRemaining() -> TimeInterval {
        rateLimitLock.lock()
        defer { rateLimitLock.unlock() }
        return rateLimitGate.remaining() ?? 0
    }

    /// Arme la porte sur un 429 et relève le quota de **toute** réponse. Tous
    /// les `dataTask` passent ici, sauf `fetchModInfo` (qui appelle
    /// `noteQuota`) : une réponse non relevée = un 429 non vu. **Interne**
    /// depuis X67 : `NexusSearchClient` (GraphQL) y passe aussi.
    /// - Returns: le délai annoncé sur un 429, `nil` sinon.
    @discardableResult
    func noteRateLimitIfThrottled(_ response: URLResponse?) -> TimeInterval? {
        guard let http = response as? HTTPURLResponse else { return nil }
        let quota = noteQuota(from: http)
        guard http.statusCode == 429 else { return nil }
        let retry = Self.parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After"))
        noteRateLimit(retryAfter: retry, quota: quota)
        return retry
    }

    // MARK: - Quota (B2-T6)

    /// Dernier quota (JSON `NexusQuota`), persisté : l'app n'appelle Nexus
    /// qu'à la demande.
    private static let cachedQuotaKey = "nexusQuota"

    /// Posté après chaque relevé (réglages ouverts rafraîchis).
    static let quotaDidChange = Notification.Name("StarHubFR.nexusQuotaDidChange")

    /// Relève les en-têtes `x-rl-*`. Sans en-têtes (CDN) : rien, la mesure
    /// précédente reste.
    @discardableResult
    func noteQuota(from response: HTTPURLResponse) -> NexusQuota? {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let key = key as? String else { continue }
            headers[key] = String(describing: value)
        }
        guard let quota = NexusQuota(headers: headers) else { return nil }

        // Plus de clé, plus de relevé : une réponse tardive ne ressuscite pas le
        // compte retiré.
        guard apiKey()?.isEmpty == false else { return nil }
        guard let data = try? JSONEncoder().encode(quota) else { return nil }
        UserDefaults.standard.set(data, forKey: Self.cachedQuotaKey)
        // Sur main : `post` délivre sur le fil qui poste, et on est dans un
        // rappel `URLSession`.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.quotaDidChange, object: nil)
        }
        return quota
    }

    // MARK: - Compte (premium ou non)

    private static let cachedAccountKey = "nexusAccount"

    /// Le compte tel qu'on l'a appris la dernière fois, périmé ou non.
    func cachedAccount() -> NexusAccount? {
        guard let data = UserDefaults.standard.data(forKey: Self.cachedAccountKey) else { return nil }
        return try? JSONDecoder().decode(NexusAccount.self, from: data)
    }

    /// Compte premium ? Décide d'un bouton : `/download_link.json` répond 403
    /// sinon.
    func fetchAccount(completion: @escaping @Sendable (NexusAccount?) -> Void) {
        guard let apiKey = apiKey(), !apiKey.isEmpty,
              let request = NexusRequestBuilder.makeRequest(path: "/users/validate.json",
                                                            apiKey: apiKey)
        else { DispatchQueue.main.async { completion(nil) }; return }

        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse { self.noteQuota(from: http) }
            guard let data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let account = NexusAccount(json: json)
            else { DispatchQueue.main.async { completion(nil) }; return }
            // Réponse après retrait de la clé : ignorée.
            guard self.apiKey()?.isEmpty == false else {
                DispatchQueue.main.async { completion(nil) }; return
            }
            if let encoded = try? JSONEncoder().encode(account) {
                UserDefaults.standard.set(encoded, forKey: Self.cachedAccountKey)
            }
            DispatchQueue.main.async { completion(account) }
        }.resume()
    }

    /// Dernier quota, périmé ou non (`NexusQuota.isStale` décide).
    func cachedQuota() -> NexusQuota? {
        guard let data = UserDefaults.standard.data(forKey: Self.cachedQuotaKey) else { return nil }
        return try? JSONDecoder().decode(NexusQuota.self, from: data)
    }

    private func withMetadataCacheLock<T>(_ body: () -> T) -> T {
        metadataCacheLock.lock()
        defer { metadataCacheLock.unlock() }
        return body()
    }

    // MARK: - API Key (Keychain)

    func apiKey() -> String? {
        KeychainSecret.nexusApiKey.read()
    }

    @discardableResult
    func setApiKey(_ key: String) -> Bool {
        KeychainSecret.nexusApiKey.write(key)
    }

    func clearApiKey() {
        KeychainSecret.nexusApiKey.clear()
        // Drop cached metadata across accounts and bump the generation, under the
        // writers' lock. **Pas les mises à jour** : smapi.io, sans compte ; les
        // effacer détruisait un travail valide.
        metadataCacheLock.lock()
        metadataGeneration += 1
        UserDefaults.standard.removeObject(forKey: cachedCategoriesKey)
        UserDefaults.standard.removeObject(forKey: cachedExtrasKey)
        // Le quota est du même bois : il décrit le compte, pas les mods.
        UserDefaults.standard.removeObject(forKey: Self.cachedQuotaKey)
        UserDefaults.standard.removeObject(forKey: Self.cachedAccountKey)
        metadataCacheLock.unlock()
        NotificationCenter.default.post(name: Self.quotaDidChange, object: nil)
    }

    // MARK: - Update check

    /// A mod with a newer Nexus version; `uploadedTime` breaks version ties
    /// inside packs and is shown in the UI.
    struct ModUpdate: Identifiable, Equatable {
        /// Identité = `UniqueID`, **pas** l'id Nexus (58 partagés, 8828 = trois
        /// mods) : sinon `id` dupliqués dans un `ForEach`.
        var id: String { uniqueId }
        let uniqueId: String
        let name: String
        let installedVersion: String
        let latestVersion: String
        let nexusModId: String
        let url: String
        let uploadedTime: Date?
    }

    /// Summary + primary picture from the same response; either may be empty.
    struct NexusModExtra: Codable, Equatable {
        let summary: String
        let pictureUrl: String
        /// Latest Nexus version (optional for old caches); shows a pack's version.
        var version: String? = nil
        /// Latest upload date (`updated_timestamp`), optional; "last updated".
        var uploadedTime: Date? = nil
    }

    /// Last update list, regardless of freshness (launch seed).
    func cachedUpdates() -> [ModUpdate] {
        withMetadataCacheLock { loadCachedUpdates() }
    }

    /// Last answered check, `nil` if none (A2-T4 gate; manual check bypasses).
    var lastSuccessfulCheck: Date? {
        let epoch = UserDefaults.standard.double(forKey: lastCheckedKey)
        return epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
    }

    /// Marks a completed pass (per-mod states are data, not failures).
    func recordSuccessfulCheck(at date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastCheckedKey)
    }

    /// Remplace le cache des mises à jour : **seul** point de persistance du
    /// chemin smapi.io (sinon l'ancienne liste revient au lancement).
    func replaceCachedUpdates(_ updates: [ModUpdate]) {
        withMetadataCacheLock { saveCachedUpdates(updates) }
    }

    /// Retire une ligne par `UniqueID` (l'id Nexus emportait toute la page :
    /// 47 partagés). Ciblé : le cache n'est pas consolidé par pack.
    func dismissUpdate(uniqueId: String) {
        withMetadataCacheLock {
            let remaining = loadCachedUpdates().filter { $0.uniqueId != uniqueId }
            saveCachedUpdates(remaining)
        }
    }

    // MARK: - Single-mod fetch

    /// On-demand single-mod fetch outcome (per-mod editor).
    enum SingleFetchResult {
        /// `pageFile` : MAIN le plus récent (X9), si `files.json` a répondu.
        case success(version: String, categoryId: Int?, extra: NexusModExtra, pageFile: NexusModFile?)
        case noApiKey
        case rateLimited(retryAfter: TimeInterval)
        case error(String)
    }

    /// Single mod metadata by id; caches category + extra at once. Completion
    /// on main.
    func fetchSingleMod(modId: String, completion: @escaping @Sendable (SingleFetchResult) -> Void) {
        guard let apiKey = apiKey(), !apiKey.isEmpty else {
            DispatchQueue.main.async { completion(.noApiKey) }
            return
        }
        metadataCacheLock.lock()
        let startGeneration = metadataGeneration
        metadataCacheLock.unlock()
        fetchModInfo(modId: modId, apiKey: apiKey) { [weak self] result in
            switch result {
            case .success(let version, let catId, let extra, _, let pageFile):
                guard let self = self else { return }
                // Persist unless the key was cleared meanwhile (`metadataGeneration`).
                self.metadataCacheLock.lock()
                let staleGeneration = self.metadataGeneration != startGeneration
                if !staleGeneration {
                    if let cid = catId, cid > 0 {
                        var cats = self.loadCachedCategories()
                        cats[modId] = cid
                        self.saveCachedCategories(cats)
                    }
                    var extrasMap = self.loadCachedExtras()
                    extrasMap[modId] = extra
                    self.saveCachedExtras(extrasMap)
                }
                self.metadataCacheLock.unlock()
                DispatchQueue.main.async {
                    if staleGeneration {
                        completion(.noApiKey)
                    } else {
                        completion(.success(version: version, categoryId: catId,
                                            extra: extra, pageFile: pageFile))
                    }
                }
            case .rateLimited(let retry):
                DispatchQueue.main.async { completion(.rateLimited(retryAfter: retry)) }
            case .failure(let msg):
                DispatchQueue.main.async { completion(.error(msg)) }
            }
        }
    }

    // MARK: - Cached results
    private struct CachedUpdate: Codable {
        /// Optionnel (anciennes charges) : repli sur `nexusModId`.
        let uniqueId: String?
        let name: String
        let installedVersion: String
        let latestVersion: String
        let nexusModId: String
        let url: String
        // Optional for older caches.
        let uploadedTime: Date?
    }

    private func saveCachedUpdates(_ updates: [ModUpdate]) {
        let codable = updates.map {
            CachedUpdate(uniqueId: $0.uniqueId,
                         name: $0.name, installedVersion: $0.installedVersion,
                         latestVersion: $0.latestVersion, nexusModId: $0.nexusModId, url: $0.url,
                         uploadedTime: $0.uploadedTime)
        }
        if let data = try? JSONEncoder().encode(codable) {
            UserDefaults.standard.set(data, forKey: cachedUpdatesKey)
        }
    }

    private func loadCachedUpdates() -> [ModUpdate] {
        guard let data = UserDefaults.standard.data(forKey: cachedUpdatesKey),
              let decoded = try? JSONDecoder().decode([CachedUpdate].self, from: data) else {
            return []
        }
        return decoded.map {
            ModUpdate(uniqueId: $0.uniqueId ?? $0.nexusModId,
                      name: $0.name, installedVersion: $0.installedVersion,
                      latestVersion: $0.latestVersion, nexusModId: $0.nexusModId, url: $0.url,
                      uploadedTime: $0.uploadedTime)
        }
    }

    // MARK: - Category cache

    /// Last `{ nexusModId: categoryId }` (launch seed).
    func cachedCategories() -> [String: Int] {
        withMetadataCacheLock { loadCachedCategories() }
    }

    private func loadCachedCategories() -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: cachedCategoriesKey) else {
            return [:]
        }
        // Decode `[String: Int]` directly — small payload, no schema drift.
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private func saveCachedCategories(_ categories: [String: Int]) {
        guard let data = try? JSONEncoder().encode(categories) else { return }
        UserDefaults.standard.set(data, forKey: cachedCategoriesKey)
    }

    // MARK: - Extras cache (summary + picture URL)

    /// Last `{ nexusModId: NexusModExtra }` (launch seed).
    func cachedExtras() -> [String: NexusModExtra] {
        withMetadataCacheLock { loadCachedExtras() }
    }

    private func loadCachedExtras() -> [String: NexusModExtra] {
        guard let data = UserDefaults.standard.data(forKey: cachedExtrasKey) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: NexusModExtra].self, from: data)) ?? [:]
    }

    private func saveCachedExtras(_ extras: [String: NexusModExtra]) {
        guard let data = try? JSONEncoder().encode(extras) else { return }
        UserDefaults.standard.set(data, forKey: cachedExtrasKey)
    }

    // MARK: - Networking

    /// `Sendable` explicite (P5-L5). ⚠️ La CI (Xcode 16.4, Swift 6.0) l'exige :
    /// c'est **elle** qui juge.
    private enum FetchResult: Sendable {
        case success(version: String, categoryId: Int?, extra: NexusModExtra, uploadedTime: Date?, pageFile: NexusModFile?)
        case rateLimited(retryAfter: TimeInterval)
        case failure(String)
    }

    private func fetchModInfo(modId: String, apiKey: String,
                              completion: @escaping @Sendable (FetchResult) -> Void) {
        // Back-off en cours : échec local, pas de requête bannie.
        if isRateLimited() {
            completion(.rateLimited(retryAfter: rateLimitRemaining()))
            return
        }
        // `modId` vient d'un manifeste (non fiable) : validé contre le path
        // traversal et l'injection.
        guard NexusRequestBuilder.isValidModId(modId) else {
            completion(.failure("invalid_mod_id"))
            return
        }
        guard let request = NexusRequestBuilder.makeRequest(
            path: "/games/\(NexusRequestBuilder.gameDomain)/mods/\(modId).json",
            apiKey: apiKey
        ) else {
            completion(.failure("invalid_url"))
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error.localizedDescription))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure("no_response"))
                return
            }
            // Quota relevé d'abord : le 429 porte le « 0 restant » (B2-T6).
            let quota = self.noteQuota(from: http)
            if http.statusCode == 429 {
                let retry = Self.parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After"))
                self.noteRateLimit(retryAfter: retry, quota: quota)
                completion(.rateLimited(retryAfter: retry))
                return
            }
            guard http.statusCode == 200, let data = data else {
                completion(.failure("http_\(http.statusCode)"))
                return
            }
            // Some descriptions embed raw control chars.
            guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let dict = json as? [String: Any],
                  let version = dict["version"] as? String else {
                completion(.failure("parse_error"))
                return
            }
            // `category_id` Int; NSNumber/String tolerated.
            var categoryId: Int?
            if let cid = dict["category_id"] as? Int {
                categoryId = cid
            } else if let cid = dict["category_id"] as? NSNumber {
                categoryId = cid.intValue
            }
            // Optional fields default to "".
            let summary = (dict["summary"] as? String) ?? ""
            let pictureUrl = (dict["picture_url"] as? String) ?? ""
            // Upload date: `updated_timestamp` (epoch), else `updated_time` (string).
            var uploadedDate: Date?
            if let ts = dict["updated_timestamp"] as? Int {
                uploadedDate = Date(timeIntervalSince1970: TimeInterval(ts))
            } else if let ts = dict["updated_timestamp"] as? NSNumber {
                uploadedDate = Date(timeIntervalSince1970: ts.doubleValue)
            } else if let ts = dict["updated_timestamp"] as? Double {
                uploadedDate = Date(timeIntervalSince1970: ts)
            } else if let raw = dict["updated_time"] as? String {
                let iso = ISO8601DateFormatter()
                uploadedDate = iso.date(from: raw)
                    ?? Self.legacyNexusFormatter.date(from: raw)
            }
            // Version + date baked into the extra. `files.json` second lookup: an
            // overview header can lag (e.g. "1" vs Main File "2.0.0").
            var finalVersion = version
            // X9 : le MAIN choisi remonte ; c'est lui qui juge un mod installé par
            // l'app.
            var finalPageFile: NexusModFile?
            let finalize = { (ver: String) in
                let extra = NexusModExtra(summary: summary, pictureUrl: pictureUrl,
                                          version: ver, uploadedTime: uploadedDate)
                completion(.success(version: ver, categoryId: categoryId, extra: extra,
                                    uploadedTime: uploadedDate, pageFile: finalPageFile))
            }

            guard let filesRequest = NexusRequestBuilder.makeRequest(
                path: "/games/\(NexusRequestBuilder.gameDomain)/mods/\(modId)/files.json",
                apiKey: apiKey
            ) else {
                finalize(finalVersion)
                return
            }

            URLSession.shared.dataTask(with: filesRequest) { filesData, response, _ in
                // Le 429 de `files.json` arme aussi la porte.
                self.noteRateLimitIfThrottled(response)
                if let filesData = filesData,
                   let fileList = try? NexusDownloadAPI.decodeFileList(filesData),
                   // X8 : MAIN le plus récent, pas le premier.
                   let primaryFile = NexusDownloadAPI.pickLatestMainFile(fileList) {
                    if let fileVer = (primaryFile.version ?? primaryFile.modVersion)?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !fileVer.isEmpty,
                       Self.compare(fileVer, finalVersion) == .orderedDescending {
                        finalVersion = fileVer
                    }
                    finalPageFile = primaryFile
                }
                finalize(finalVersion)
            }.resume()
        }
        task.resume()
    }

    // MARK: - Rich mod detail (Task 3: description + changelog)

    /// Raw description (`mods/{id}.json`, same client) for the detail pane;
    /// `""` on any failure (cached/local data stays).
    /// ⚠️ **Complétion hors fil principal** (fil `URLSession`) : l'appelant
    /// repasse par main.
    func fetchRawDescription(modId: Int, completion: @escaping (String) -> Void) {
        guard let apiKey = apiKey(), !apiKey.isEmpty else {
            completion("")
            return
        }
        // 429 en cours = indisponible.
        guard !isRateLimited() else {
            completion("")
            return
        }
        guard let request = NexusRequestBuilder.makeRequest(
            path: "/games/\(NexusRequestBuilder.gameDomain)/mods/\(modId).json",
            apiKey: apiKey
        ) else {
            completion("")
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            self.noteRateLimitIfThrottled(response)
            guard error == nil,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let dict = json as? [String: Any],
                  let description = dict["description"] as? String else {
                completion("")
                return
            }
            completion(description)
        }
        task.resume()
    }

    /// **Complete** changelog (`changelogs.json`, every version) as Markdown,
    /// newest first; `""` on failure. ⚠️ Complétion sur le fil `URLSession`.
    func fetchChangelogs(modId: Int, completion: @escaping (String) -> Void) {
        guard let apiKey = apiKey(), !apiKey.isEmpty else {
            completion("")
            return
        }
        guard !isRateLimited() else {
            completion("")
            return
        }
        guard let request = NexusRequestBuilder.makeRequest(
            path: "/games/\(NexusRequestBuilder.gameDomain)/mods/\(modId)/changelogs.json",
            apiKey: apiKey
        ) else {
            completion("")
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            self.noteRateLimitIfThrottled(response)
            guard error == nil,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let dict = json as? [String: [String]], !dict.isEmpty else {
                completion("")
                return
            }
            completion(Self.formatChangelogs(dict))
        }
        task.resume()
    }

    /// `{version: [entries]}` → Markdown, newest first. Pure.
    static func formatChangelogs(_ dict: [String: [String]]) -> String {
        let versions = dict.keys.sorted { compare($0, $1) == .orderedDescending }
        return versions.map { version -> String in
            let lines = dict[version]?.map { "- \($0)" }.joined(separator: "\n") ?? ""
            return "**\(version)**\n\(lines)"
        }.joined(separator: "\n\n")
    }

    /// Legacy `updated_time` format.
    private static let legacyNexusFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    /// `Retry-After`: seconds or HTTP-date; 60 s fallback (logged).
    private static func parseRetryAfter(_ header: String?) -> TimeInterval {
        guard let header = header else { return 60 }
        if let seconds = TimeInterval(header) {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: header) {
            return max(0, date.timeIntervalSinceNow)
        }
        NSLog("[StarHubFR] Retry-After header could not be parsed (%@) — falling back to 60s", header)
        return 60
    }

    // MARK: - Version comparison

    /// `latest` strictly newer (dotted-numeric).
    static func isNewer(_ latest: String, installed: String) -> Bool {
        compare(latest, installed) == .orderedDescending
    }

    /// Nexus upload strictly after the local file date; `false` if unknown.
    static func isNexusUploadNewer(_ nexusUpload: Date?, than installedFileDate: Date?) -> Bool {
        guard let nexus = nexusUpload, let installed = installedFileDate else {
            return false
        }
        return nexus > installed
    }

    /// Compares "1.4.2", "1.4.10-beta.1": leading `v` stripped, numeric
    /// segments, pre-release lower (semver), `+build` ignored.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let aNorm = a.hasPrefix("v") || a.hasPrefix("V") ? String(a.dropFirst()) : a
        let bNorm = b.hasPrefix("v") || b.hasPrefix("V") ? String(b.dropFirst()) : b

        // Numeric core vs pre-release; `+build` dropped.
        func splitCore(_ s: String) -> (core: [String], hasPre: Bool, pre: [String]) {
            var work = s
            if let plusIdx = work.firstIndex(of: "+") {
                work = String(work[..<plusIdx])
            }
            if let dashIdx = work.firstIndex(of: "-") {
                let core = String(work[..<dashIdx])
                let pre = String(work[work.index(after: dashIdx)...])
                return (core.split(separator: ".").map(String.init), true,
                        pre.split(separator: ".").map(String.init))
            }
            return (work.split(separator: ".").map(String.init), false, [])
        }

        let (aCore, aHasPre, aPre) = splitCore(aNorm.lowercased())
        let (bCore, bHasPre, bPre) = splitCore(bNorm.lowercased())

        // Compare numeric cores segment by segment.
        let count = max(aCore.count, bCore.count)
        for i in 0..<count {
            let lhs = i < aCore.count ? aCore[i] : "0"
            let rhs = i < bCore.count ? bCore[i] : "0"
            if let ln = Int(lhs), let rn = Int(rhs) {
                if ln != rn { return ln < rn ? .orderedAscending : .orderedDescending }
            } else {
                if lhs != rhs { return lhs.compare(rhs) }
            }
        }

        // Equal cores: pre-release ranks lower.
        if aHasPre && !bHasPre { return .orderedAscending }
        if !aHasPre && bHasPre { return .orderedDescending }
        if aHasPre && bHasPre {
            // Both have pre-release tags — compare lexically segment by segment.
            let pCount = max(aPre.count, bPre.count)
            for i in 0..<pCount {
                let lhs = i < aPre.count ? aPre[i] : ""
                let rhs = i < bPre.count ? bPre[i] : ""
                // A shorter pre-release with all-equal prefixes ranks lower.
                if lhs.isEmpty && !rhs.isEmpty { return .orderedAscending }
                if !lhs.isEmpty && rhs.isEmpty { return .orderedDescending }
                if let ln = Int(lhs), let rn = Int(rhs) {
                    if ln != rn { return ln < rn ? .orderedAscending : .orderedDescending }
                } else if lhs != rhs {
                    return lhs.compare(rhs)
                }
            }
        }
        return .orderedSame
    }
}
