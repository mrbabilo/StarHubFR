import Foundation
import Security

/// Checks installed Stardew Valley mods against Nexus Mods for available updates.
///
/// Uses the Nexus Mods public API (https://api-docs.nexusmods.com/). Each user
/// must provide their own personal API key, available free of charge from
/// `https://www.nexusmods.com/users/myaccount?tab=api`. Keys are stored in the
/// macOS Keychain (never in UserDefaults), one per app.
///
/// Rate-limit policy on the public API is generous for legitimate per-user use
/// (a few thousand requests/day). To stay well under the limit, we:
///   - Only query mods that declare a `nexus:<id>` UpdateKey.
///   - Issue requests serially (no parallel fan-out).
///   - Cache last-seen versions in UserDefaults keyed by Nexus mod id, so a
///     re-check inside the dedupe window (default 1 hour) is a no-op.
final class NexusUpdateChecker {
    static let shared = NexusUpdateChecker()

    private let service = "com.appleboiy.StarHubTH"
    private let keychainAccount = "nexusApiKey"
    private let gameDomain = "stardewvalley"
    private let apiBase = "https://api.nexusmods.com/v1"
    private let userAgent = "StarHubTH/1.0 (macOS; +https://github.com/AppleBoiy/StarHubTH)"

    /// UserDefaults key for the last full check timestamp.
    private let lastCheckKey = "nexusLastCheckAt"
    /// UserDefaults key caching the last successful update list (JSON-encoded
    /// `[ModUpdate]`). Used to replay the result inside the dedupe window
    /// instead of clearing the UI on a repeated non-forced check.
    private let cachedUpdatesKey = "nexusCachedUpdates"
    /// UserDefaults key caching the Nexus category id for every mod we've ever
    /// queried (`{ "modId": categoryId }`). Persisted independently from
    /// `cachedUpdates` because categories apply to *all* mods, not just those
    /// with available updates — we want them to survive even when the update
    /// list is empty.
    private let cachedCategoriesKey = "nexusCachedCategories"
    /// UserDefaults key caching the short summary + primary picture URL for
    /// every mod we've ever queried (`{ "modId": NexusModExtra }`). Same
    /// lifetime rules as `cachedCategoriesKey` — populated for free from the
    /// same API response, so it's kept alongside it.
    private let cachedExtrasKey = "nexusCachedExtras"
    /// Minimum interval between two full checks (seconds). Re-checks sooner than
    /// this return the cached result without hitting the network.
    private let dedupeInterval: TimeInterval = 60 * 60 // 1 hour

    /// Guards all metadata-cache mutations (categories + extras) so
    /// `fetchSingleMod` (on-demand) and `check` (full scan) can't lose entries
    /// when they overlap.
    private let metadataCacheLock = NSLock()
    /// Bumped (under `metadataCacheLock`) every time `clearApiKey()` runs.
    /// `check()` and `fetchSingleMod()` capture it when they start and check
    /// it again right before persisting their results — if it changed, the
    /// key was cleared while they were in flight, so their results were
    /// fetched under an account that no longer applies and must be discarded
    /// instead of being written back (which would resurrect that account's
    /// data right after `clearApiKey()` removed it).
    private var metadataGeneration = 0

    private init() {}

    private func withMetadataCacheLock<T>(_ body: () -> T) -> T {
        metadataCacheLock.lock()
        defer { metadataCacheLock.unlock() }
        return body()
    }

    // MARK: - API Key (Keychain)

    func apiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    func setApiKey(_ key: String) {
        let data = Data(key.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        // Try update first; if no item exists, add a new one.
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var newItem = baseQuery
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    func clearApiKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        // Drop any cached results so they don't leak across accounts, and
        // bump the generation so an in-flight check()/fetchSingleMod() from
        // the old key discards its results instead of writing them back
        // after this clear. All under the same lock those writes use, so
        // this can't interleave with one of them mid-write either.
        metadataCacheLock.lock()
        metadataGeneration += 1
        UserDefaults.standard.removeObject(forKey: cachedUpdatesKey)
        UserDefaults.standard.removeObject(forKey: lastCheckKey)
        UserDefaults.standard.removeObject(forKey: cachedCategoriesKey)
        UserDefaults.standard.removeObject(forKey: cachedExtrasKey)
        metadataCacheLock.unlock()
    }

    // MARK: - Update check

    /// Represents a mod that has a newer version available on Nexus.
    /// `uploadedTime` is the Nexus `updated_time` (timestamp of the latest
    /// file/version upload) — used to break ties when several children of a
    /// pack share the same highest version, and surfaced in the UI.
    struct ModUpdate: Identifiable, Equatable {
        var id: String { nexusModId }
        let name: String
        let installedVersion: String
        let latestVersion: String
        let nexusModId: String
        let url: String
        let uploadedTime: Date?
    }

    /// Short summary text + primary screenshot URL for a mod, as returned by
    /// the Nexus API alongside version/category in the same response. Either
    /// field may be empty when Nexus has none on file for that mod.
    struct NexusModExtra: Codable, Equatable {
        let summary: String
        let pictureUrl: String
    }

    /// Outcome of a full check pass. `partialErrorMessage` on `.success` is
    /// non-nil when at least one candidate succeeded (so there IS real data
    /// to merge) but the run didn't fully complete cleanly — e.g. a 429
    /// aborted the remaining candidates after some updates were already
    /// found, or one unrelated candidate 404'd while everything else
    /// succeeded. Distinguishing this from a full success without losing
    /// the gathered data is the whole point of carrying it here rather than
    /// collapsing the run to `.error` (which would drop it) or plain
    /// `.success` (which would silently hide that the scan was incomplete).
    enum CheckResult {
        case success(updates: [ModUpdate], categories: [String: Int], extras: [String: NexusModExtra], partialErrorMessage: String? = nil)
        case noApiKey
        case rateLimited(retryAfter: TimeInterval)
        case error(String)
    }

    /// Returns `true` if a recent cached check is still valid (within
    /// `dedupeInterval`). UI can use this to avoid showing a spinner when the
    /// result hasn't changed.
    func hasRecentCheck() -> Bool {
        withMetadataCacheLock {
            guard let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date else {
                return false
            }
            return Date().timeIntervalSince(last) < dedupeInterval
        }
    }

    /// Returns the last successful update list, regardless of freshness.
    /// Useful for seeding the UI on launch before any check runs.
    func cachedUpdates() -> [ModUpdate] {
        withMetadataCacheLock { loadCachedUpdates() }
    }

    /// Removes a mod from the persisted update cache (e.g. right after
    /// installing its update) so it no longer shows as "update available",
    /// including across app launches.
    func dismissUpdate(nexusModId: String) {
        withMetadataCacheLock {
            let remaining = loadCachedUpdates().filter { $0.nexusModId != nexusModId }
            saveCachedUpdates(remaining)
        }
    }

    /// Runs a full check across all mods that declare a Nexus id.
    /// Uses bounded concurrency (default 6 parallel requests) to stay fast
    /// while remaining friendly with the API rate limit. Calls `completion`
    /// exactly once on the main queue, and `progress` for each request that
    /// completes (also on the main queue).
    ///
    /// - Parameters:
    ///   - mods: All installed mods (groups are flattened automatically).
    ///   - customModIds: Per-folder overrides `{ folderName: nexusModId }` so
    ///     mods with no manifest id but a user-assigned one still get checked.
    ///   - force: If `true`, ignore the dedupe window and always hit the API.
    ///   - progress: Optional callback `(done, total)` invoked on the main thread.
    ///   - completion: Invoked on the main thread with the result.
    func check(mods: [ModItem],
               customModIds: [String: String] = [:],
               force: Bool = false,
               progress: ((Int, Int) -> Void)? = nil,
               completion: @escaping (CheckResult) -> Void) {
        guard let apiKey = apiKey(), !apiKey.isEmpty else {
            DispatchQueue.main.async { completion(.noApiKey) }
            return
        }

        if !force, hasRecentCheck() {
            // Replay the cached update list so the UI keeps showing updates
            // found during the previous real check.
            let cached = loadCachedUpdates()
            let cats = loadCachedCategories()
            let extras = loadCachedExtras()
            DispatchQueue.main.async { completion(.success(updates: cached, categories: cats, extras: extras)) }
            return
        }

        // Helper: resolve a mod's effective Nexus id (custom override first).
        func effectiveId(_ mod: ModItem) -> String {
            if let custom = customModIds[mod.folderName], !custom.isEmpty { return custom }
            return mod.nexusModId
        }

        // Flatten groups and keep only mods with an effective Nexus id + known
        // version. The effective id includes user-assigned overrides so mods
        // that lack a manifest `nexus:` key but were manually linked are still
        // checked for updates.
        // `installedFileDate` (on-disk manifest mod date) is carried so a
        // same-version but newer Nexus upload is still flagged as an update.
        var candidates: [(modId: String, name: String, version: String, installedFileDate: Date?)] = []
        for mod in mods {
            if mod.isGroup, let children = mod.children {
                for child in children where !effectiveId(child).isEmpty && child.version != "Unknown" {
                    candidates.append((effectiveId(child), child.name, child.version, child.installedFileDate))
                }
            } else if !effectiveId(mod).isEmpty && mod.version != "Unknown" {
                candidates.append((effectiveId(mod), mod.name, mod.version, mod.installedFileDate))
            }
        }
        // De-duplicate by Nexus id (a pack may reference the same mod twice).
        var seen = Set<String>()
        candidates.removeAll { !seen.insert($0.modId).inserted }
        guard !candidates.isEmpty else {
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            DispatchQueue.main.async {
                completion(.success(updates: [], categories: self.loadCachedCategories(), extras: self.loadCachedExtras()))
            }
            return
        }

        let total = candidates.count
        DispatchQueue.main.async { progress?(0, total) }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            self.metadataCacheLock.lock()
            let startGeneration = self.metadataGeneration
            self.metadataCacheLock.unlock()

            // Thread-safe accumulators shared across concurrent requests.
            let lock = NSLock()
            var updates: [ModUpdate] = []
            // `categories` is seeded from the existing cache so that a partial
            // run (aborted by rate-limit) still preserves older lookups and so
            // that newly fetched ids just overwrite their previous entry.
            var categories: [String: Int] = self.loadCachedCategories()
            // Same seeding rationale as `categories` — a partial run keeps
            // whatever extras were already known.
            var extras: [String: NexusModExtra] = self.loadCachedExtras()
            var lastError: String?
            var done = 0
            var aborted = false
            // Counts candidates that actually completed successfully, so the
            // final classification below can tell "some real data was
            // gathered" apart from "nothing succeeded at all" — see
            // `CheckResult.success(partialErrorMessage:)`.
            var successCount = 0

            // Bounded concurrency: allow up to `maxConcurrent` in-flight requests.
            // 6 is a sweet spot — fast (150 mods in ~15s) yet gentle on the API.
            let maxConcurrent = 6
            let concurrencyLimiter = DispatchSemaphore(value: maxConcurrent)
            let group = DispatchGroup()

            for candidate in candidates {
                // If a hard rate-limit came back, stop scheduling new requests.
                lock.lock()
                let shouldStop = aborted
                lock.unlock()
                if shouldStop { break }

                concurrencyLimiter.wait()
                group.enter()

                // Capture per-request context to avoid races on `candidate`.
                let modId = candidate.modId
                let modName = candidate.name
                let installedVer = candidate.version
                let installedFileDate = candidate.installedFileDate

                self.fetchModInfo(modId: modId, apiKey: apiKey) { result in
                    defer {
                        concurrencyLimiter.signal()
                        group.leave()
                    }

                    lock.lock()
                    switch result {
                    case .success(let latest, let catId, let extra, let uploaded):
                        successCount += 1
                        // Record the category for every successful fetch,
                        // whether or not the mod has an update. This is what
                        // powers the per-category filter in the mods list.
                        if let cid = catId, cid > 0 {
                            categories[modId] = cid
                        }
                        // Same rationale for extras — recorded for every
                        // successful fetch so the popover preview works even
                        // for mods with no available update.
                        extras[modId] = extra
                        // An update is available when:
                        //  (a) the Nexus version is strictly newer than the
                        //      installed one, OR
                        //  (b) the versions are identical BUT the Nexus upload
                        //      is more recent than the local manifest file date
                        //      (same-version re-upload — the installed copy is
                        //      stale and should be re-downloaded).
                        let versionBumped = Self.isNewer(latest, installed: installedVer)
                        let sameVersionNewerFile = !versionBumped
                            && Self.compare(latest, installedVer) == .orderedSame
                            && Self.isNexusUploadNewer(uploaded, than: installedFileDate)
                        if versionBumped || sameVersionNewerFile {
                            updates.append(ModUpdate(
                                name: modName,
                                installedVersion: installedVer,
                                latestVersion: latest,
                                nexusModId: modId,
                                url: "https://www.nexusmods.com/\(self.gameDomain)/mods/\(modId)",
                                uploadedTime: uploaded
                            ))
                        }
                    case .rateLimited(let retry):
                        lastError = "rate_limited:\(retry)"
                        // Stop scheduling further requests after a 429.
                        aborted = true
                    case .failure(let msg):
                        lastError = msg
                    }
                    done += 1
                    let snapshotDone = done
                    lock.unlock()

                    DispatchQueue.main.async { progress?(snapshotDone, total) }
                }
            }

            // Wait for all in-flight requests to drain.
            group.wait()

            // Persist the merged category + extras maps so the mods-list
            // filter and popover preview can show data even before the user
            // re-runs a check. Lock to avoid racing with a concurrent
            // fetchSingleMod write, and to check `metadataGeneration`
            // atomically with the write itself.
            self.metadataCacheLock.lock()
            let staleGeneration = self.metadataGeneration != startGeneration
            var mergedCats = self.loadCachedCategories()
            var mergedExtras = self.loadCachedExtras()
            if staleGeneration {
                // The API key was cleared mid-check — this run's results were
                // fetched under an account that no longer applies. Discard
                // them instead of merging them back over whatever the clear
                // just removed.
                self.metadataCacheLock.unlock()
            } else {
                UserDefaults.standard.set(Date(), forKey: self.lastCheckKey)
                // Merge with any categories/extras fetched by on-demand calls
                // while this check was running, so we don't clobber them.
                for (k, v) in categories { mergedCats[k] = v }
                self.saveCachedCategories(mergedCats)
                for (k, v) in extras { mergedExtras[k] = v }
                self.saveCachedExtras(mergedExtras)
                self.metadataCacheLock.unlock()
            }
            let finalResult: CheckResult
            if staleGeneration {
                finalResult = .noApiKey
            } else if successCount > 0 {
                // At least one candidate produced real data — always
                // deliver it as `.success` (so the caller merges it) even
                // when the run didn't fully complete cleanly. Losing this
                // data to `.error`/`.rateLimited` just because one other
                // candidate 404'd, or because a 429 cut the run short after
                // some updates were already found, is exactly the bug this
                // branch avoids.
                self.saveCachedUpdates(updates)
                finalResult = .success(updates: updates, categories: mergedCats, extras: mergedExtras, partialErrorMessage: lastError)
            } else if let err = lastError {
                if err.hasPrefix("rate_limited:") {
                    let retry = TimeInterval(err.split(separator: ":").last ?? "0") ?? 0
                    finalResult = .rateLimited(retryAfter: retry)
                } else {
                    finalResult = .error(err)
                }
            } else {
                self.saveCachedUpdates(updates)
                finalResult = .success(updates: updates, categories: mergedCats, extras: mergedExtras)
            }
            DispatchQueue.main.async { completion(finalResult) }
        }
    }

    // MARK: - Single-mod fetch

    /// Outcome of an on-demand single-mod metadata fetch (used when the user
    /// enters a Nexus mod id in the per-mod editor popover).
    enum SingleFetchResult {
        case success(version: String, categoryId: Int?, extra: NexusModExtra)
        case noApiKey
        case rateLimited(retryAfter: TimeInterval)
        case error(String)
    }

    /// Fetches a single mod's metadata (latest version + category id + summary/
    /// picture) by Nexus mod id, bypassing the dedupe window. Caches the
    /// category and extra immediately so the mods list badge and popover
    /// preview pick them up without a full check. The completion is always
    /// invoked on the main queue.
    func fetchSingleMod(modId: String, completion: @escaping (SingleFetchResult) -> Void) {
        guard let apiKey = apiKey(), !apiKey.isEmpty else {
            DispatchQueue.main.async { completion(.noApiKey) }
            return
        }
        metadataCacheLock.lock()
        let startGeneration = metadataGeneration
        metadataCacheLock.unlock()
        fetchModInfo(modId: modId, apiKey: apiKey) { [weak self] result in
            switch result {
            case .success(let version, let catId, let extra, _):
                guard let self = self else { return }
                // Persist the category + extra in the shared cache so they
                // survive relaunches and the mods-list badge / popover preview
                // appear instantly — unless the key was cleared while this
                // fetch was in flight, in which case discard it instead of
                // resurrecting the old account's data (see `metadataGeneration`).
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
                        completion(.success(version: version, categoryId: catId, extra: extra))
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
        let name: String
        let installedVersion: String
        let latestVersion: String
        let nexusModId: String
        let url: String
        // Optional for backward compatibility with caches written before this
        // field existed — old entries decode with `nil`.
        let uploadedTime: Date?
    }

    private func saveCachedUpdates(_ updates: [ModUpdate]) {
        let codable = updates.map {
            CachedUpdate(name: $0.name, installedVersion: $0.installedVersion,
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
            ModUpdate(name: $0.name, installedVersion: $0.installedVersion,
                      latestVersion: $0.latestVersion, nexusModId: $0.nexusModId, url: $0.url,
                      uploadedTime: $0.uploadedTime)
        }
    }

    // MARK: - Category cache

    /// Returns the last known `{ nexusModId: categoryId }` map, regardless of
    /// freshness. Used to seed the mods-list filter on launch before any check
    /// has run this session.
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

    /// Returns the last known `{ nexusModId: NexusModExtra }` map, regardless
    /// of freshness. Used to seed the popover preview on launch before any
    /// check has run this session.
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

    private enum FetchResult {
        case success(version: String, categoryId: Int?, extra: NexusModExtra, uploadedTime: Date?)
        case rateLimited(retryAfter: TimeInterval)
        case failure(String)
    }

    private func fetchModInfo(modId: String, apiKey: String,
                              completion: @escaping (FetchResult) -> Void) {
        guard let url = URL(string: "\(apiBase)/games/\(gameDomain)/mods/\(modId).json") else {
            completion(.failure("invalid_url"))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Nexus recommends telling them which app is calling.
        request.setValue("StarHubTH", forHTTPHeaderField: "Application-Name")
        request.setValue("1.0.9", forHTTPHeaderField: "Application-Version")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error.localizedDescription))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure("no_response"))
                return
            }
            if http.statusCode == 429 {
                completion(.rateLimited(retryAfter: Self.parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After"))))
                return
            }
            guard http.statusCode == 200, let data = data else {
                completion(.failure("http_\(http.statusCode)"))
                return
            }
            // `strict: false` — some mod descriptions embed raw control chars
            // (e.g. form feeds) that JSONSerialization would otherwise reject.
            guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let dict = json as? [String: Any],
                  let version = dict["version"] as? String else {
                completion(.failure("parse_error"))
                return
            }
            // `category_id` is an Int in the Nexus payload; tolerate NSNumber
            // / String just in case the API ever widens the field.
            var categoryId: Int?
            if let cid = dict["category_id"] as? Int {
                categoryId = cid
            } else if let cid = dict["category_id"] as? NSNumber {
                categoryId = cid.intValue
            }
            // `summary` and `picture_url` are both optional in the Nexus
            // payload (absent for some mods) — default to empty string rather
            // than threading an extra Optional through every caller.
            let summary = (dict["summary"] as? String) ?? ""
            let pictureUrl = (dict["picture_url"] as? String) ?? ""
            let extra = NexusModExtra(summary: summary, pictureUrl: pictureUrl)
            // Nexus returns the "last updated" instant under TWO keys:
            //  - `updated_timestamp`: a Unix epoch in seconds (the reliable one)
            //  - `updated_time`: a human-readable ISO8601 string (fallback)
            // We prefer the numeric form and fall back to parsing the string.
            // This reflects when the latest file/version was uploaded and is
            // used to break version ties inside packs + shown in the UI.
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
            completion(.success(version: version, categoryId: categoryId, extra: extra, uploadedTime: uploadedDate))
        }
        task.resume()
    }

    // MARK: - Rich mod detail (Task 3: description + changelog)

    /// Fetches only the raw HTML/BBCode `description` field for a mod, for the
    /// rich detail pane. Reuses the exact same endpoint/headers as
    /// `fetchModInfo` above (mods/{id}.json) rather than standing up a second
    /// client — this is the sole request the VM needs beyond `getModFiles`
    /// (which already lives on `NexusDownloader` for the changelog).
    /// Returns `""` on any failure (no API key, network error, non-200 status,
    /// parse error, missing field) so callers can treat that uniformly as
    /// "offline / unavailable" and keep showing cached/local data instead.
    func fetchRawDescription(modId: Int, completion: @escaping (String) -> Void) {
        guard let apiKey = apiKey(), !apiKey.isEmpty else {
            completion("")
            return
        }
        guard let url = URL(string: "\(apiBase)/games/\(gameDomain)/mods/\(modId).json") else {
            completion("")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("StarHubTH", forHTTPHeaderField: "Application-Name")
        request.setValue("1.0.9", forHTTPHeaderField: "Application-Version")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
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

    /// Legacy fallback for the human-readable `updated_time` string some
    /// older Nexus responses use ("Wed, 21 Oct 2026 07:28:00 GMT").
    private static let legacyNexusFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    /// Parses a `Retry-After` header value, which per RFC 7231 can be either
    /// a delay in seconds ("120") or an HTTP-date ("Wed, 21 Oct 2026
    /// 07:28:00 GMT"). Falls back to 60s (logged) if neither form parses.
    private static func parseRetryAfter(_ header: String?) -> TimeInterval {        guard let header = header else { return 60 }
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
        print("Retry-After header could not be parsed (\(header)) — falling back to 60s")
        return 60
    }

    // MARK: - Version comparison

    /// Returns `true` if `latest` is strictly newer than `installed` using
    /// dotted-numeric comparison. Non-numeric segments are compared lexically.
    static func isNewer(_ latest: String, installed: String) -> Bool {
        compare(latest, installed) == .orderedDescending
    }

    /// Returns `true` when the Nexus upload date is known and strictly more
    /// recent than the installed mod's on-disk file date. Used to flag a
    /// same-version update (the modder re-uploaded the current version after
    /// the local copy was installed). When either date is missing we can't be
    /// sure, so we return `false` (don't show a spurious update).
    static func isNexusUploadNewer(_ nexusUpload: Date?, than installedFileDate: Date?) -> Bool {
        guard let nexus = nexusUpload, let installed = installedFileDate else {
            return false
        }
        return nexus > installed
    }

    /// Compares two version strings like "1.4.2", "1.4.10-beta.1".
    /// Splits the numeric core on `.` and compares segment-by-segment. A
    /// leading `v`/`V` prefix is stripped first. After the numeric core, a
    /// `-suffix` (pre-release, e.g. "beta") ranks *lower* than no suffix per
    /// the semver spec, so `1.0.0-beta` < `1.0.0`. `+build` metadata is
    /// ignored entirely.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let aNorm = a.hasPrefix("v") || a.hasPrefix("V") ? String(a.dropFirst()) : a
        let bNorm = b.hasPrefix("v") || b.hasPrefix("V") ? String(b.dropFirst()) : b

        // Separate the numeric core from the pre-release suffix. `+build` is
        // dropped (semver: build metadata does not affect precedence).
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

        // Cores are equal — pre-release precedence (semver: a version with a
        // pre-release tag is LOWER than the same version without one).
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
