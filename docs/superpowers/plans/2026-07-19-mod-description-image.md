# Description + image de mod (Nexus) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fetch a mod's short Nexus summary and primary picture URL (for free, from the JSON response already fetched for version/category) and display them at the top of the mod details popover.

**Architecture:** `NexusUpdateChecker` extracts `summary`/`picture_url` from the existing `fetchModInfo` response into a new `NexusModExtra` struct, caches it in UserDefaults the same way categories are cached, and threads it through both existing fetch paths (`check()` bulk scan, `fetchSingleMod()` on-demand). `StarHubTHViewModel` mirrors this into a published `nexusModExtras` map and exposes `modExtra(for:)`. `ModDetailsPopover` reads it purely for display — it never triggers a fetch itself.

**Tech Stack:** Swift 5 / SwiftUI (macOS 14+ target), `AsyncImage` for the thumbnail (no manual image download/cache code needed). No automated test target in this repo — verification is `python3 build_app.py` plus manual/code-reading verification (see each task).

## Global Constraints

- Deployment target is macOS 14.0 — `AsyncImage` requires macOS 12+, so it's safe to use.
- Follow the existing code style: doc comments only where the *why* is non-obvious, no comment restating what the code already says.
- No new user-facing strings are introduced by this feature (the preview section has no header text), so no `en.json`/`th.json`/`L10n.swift` changes are needed and the en/th key-parity constraint is not touched.
- The Nexus API fields are `summary` (string, optional) and `picture_url` (string, optional) — confirmed via the official `node-nexus-api` `IModInfo` type. Both default to `""` when absent.

---

### Task 1: Fetch, cache, and expose mod summary + picture URL

**Files:**
- Modify: `StarHubTH/NexusUpdateChecker.swift` (multiple locations — see steps)
- Modify: `StarHubTH/StarHubTHViewModel.swift` (multiple locations — see steps)
- Modify: `StarHubTH/Views/ModListView.swift:1005` (one-line fix, required for the file to keep compiling after `SingleFetchResult`'s arity changes)

**Interfaces:**
- Produces: `NexusUpdateChecker.NexusModExtra` (`Codable, Equatable` struct: `summary: String`, `pictureUrl: String`); `NexusUpdateChecker.shared.cachedExtras() -> [String: NexusModExtra]`; `NexusUpdateChecker.CheckResult.success(updates:categories:extras:)`; `NexusUpdateChecker.SingleFetchResult.success(version:categoryId:extra:)`; `StarHubTHViewModel.nexusModExtras: [String: NexusUpdateChecker.NexusModExtra]` (published); `StarHubTHViewModel.modExtra(for mod: ModItem) -> NexusUpdateChecker.NexusModExtra?`.
- Consumes: nothing from other tasks (this task is self-contained and must land as one unit — `NexusUpdateChecker`'s enum signature changes force call-site updates in both `StarHubTHViewModel.swift` and `ModListView.swift`, so splitting it further would leave the project non-compiling between commits).

- [ ] **Step 1: Add `cachedExtrasKey`, rename the cache lock, and update `clearApiKey()`**

In `StarHubTH/NexusUpdateChecker.swift`, find this block (near the top of the class):

```swift
    private let cachedCategoriesKey = "nexusCachedCategories"
    /// Minimum interval between two full checks (seconds). Re-checks sooner than
    /// this return the cached result without hitting the network.
    private let dedupeInterval: TimeInterval = 60 * 60 // 1 hour

    /// Guards all category-cache mutations so `fetchSingleMod` (on-demand) and
    /// `check` (full scan) can't lose entries when they overlap.
    private let categoryCacheLock = NSLock()
```

Replace it with:

```swift
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
```

Then find `clearApiKey()`:

```swift
        SecItemDelete(query as CFDictionary)
        // Drop any cached results so they don't leak across accounts.
        UserDefaults.standard.removeObject(forKey: cachedUpdatesKey)
        UserDefaults.standard.removeObject(forKey: lastCheckKey)
        UserDefaults.standard.removeObject(forKey: cachedCategoriesKey)
    }
```

Replace with:

```swift
        SecItemDelete(query as CFDictionary)
        // Drop any cached results so they don't leak across accounts.
        UserDefaults.standard.removeObject(forKey: cachedUpdatesKey)
        UserDefaults.standard.removeObject(forKey: lastCheckKey)
        UserDefaults.standard.removeObject(forKey: cachedCategoriesKey)
        UserDefaults.standard.removeObject(forKey: cachedExtrasKey)
    }
```

- [ ] **Step 2: Add `NexusModExtra` and update `CheckResult`**

Find:

```swift
    /// Represents a mod that has a newer version available on Nexus.
    struct ModUpdate: Identifiable, Equatable {
        var id: String { nexusModId }
        let name: String
        let installedVersion: String
        let latestVersion: String
        let nexusModId: String
        let url: String
    }

    /// Outcome of a full check pass.
    enum CheckResult {
        case success(updates: [ModUpdate], categories: [String: Int])
        case noApiKey
        case rateLimited(retryAfter: TimeInterval)
        case error(String)
    }
```

Replace with:

```swift
    /// Represents a mod that has a newer version available on Nexus.
    struct ModUpdate: Identifiable, Equatable {
        var id: String { nexusModId }
        let name: String
        let installedVersion: String
        let latestVersion: String
        let nexusModId: String
        let url: String
    }

    /// Short summary text + primary screenshot URL for a mod, as returned by
    /// the Nexus API alongside version/category in the same response. Either
    /// field may be empty when Nexus has none on file for that mod.
    struct NexusModExtra: Codable, Equatable {
        let summary: String
        let pictureUrl: String
    }

    /// Outcome of a full check pass.
    enum CheckResult {
        case success(updates: [ModUpdate], categories: [String: Int], extras: [String: NexusModExtra])
        case noApiKey
        case rateLimited(retryAfter: TimeInterval)
        case error(String)
    }
```

- [ ] **Step 3: Thread `extras` through the dedupe-replay and empty-candidates paths of `check()`**

Find:

```swift
        if !force, hasRecentCheck() {
            // Replay the cached update list so the UI keeps showing updates
            // found during the previous real check.
            let cached = loadCachedUpdates()
            let cats = loadCachedCategories()
            DispatchQueue.main.async { completion(.success(updates: cached, categories: cats)) }
            return
        }
```

Replace with:

```swift
        if !force, hasRecentCheck() {
            // Replay the cached update list so the UI keeps showing updates
            // found during the previous real check.
            let cached = loadCachedUpdates()
            let cats = loadCachedCategories()
            let extras = loadCachedExtras()
            DispatchQueue.main.async { completion(.success(updates: cached, categories: cats, extras: extras)) }
            return
        }
```

Find:

```swift
        guard !candidates.isEmpty else {
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            DispatchQueue.main.async {
                completion(.success(updates: [], categories: self.loadCachedCategories()))
            }
            return
        }
```

Replace with:

```swift
        guard !candidates.isEmpty else {
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            DispatchQueue.main.async {
                completion(.success(updates: [], categories: self.loadCachedCategories(), extras: self.loadCachedExtras()))
            }
            return
        }
```

- [ ] **Step 4: Accumulate extras in the concurrent scan loop**

Find:

```swift
            // Thread-safe accumulators shared across concurrent requests.
            let lock = NSLock()
            var updates: [ModUpdate] = []
            // `categories` is seeded from the existing cache so that a partial
            // run (aborted by rate-limit) still preserves older lookups and so
            // that newly fetched ids just overwrite their previous entry.
            var categories: [String: Int] = self.loadCachedCategories()
            var lastError: String?
            var done = 0
            var aborted = false
```

Replace with:

```swift
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
```

Find:

```swift
                self.fetchModInfo(modId: modId, apiKey: apiKey) { result in
                    defer {
                        concurrencyLimiter.signal()
                        group.leave()
                    }

                    lock.lock()
                    switch result {
                    case .success(let latest, let catId):
                        // Record the category for every successful fetch,
                        // whether or not the mod has an update. This is what
                        // powers the per-category filter in the mods list.
                        if let cid = catId, cid > 0 {
                            categories[modId] = cid
                        }
                        if Self.isNewer(latest, installed: installedVer) {
                            updates.append(ModUpdate(
                                name: modName,
                                installedVersion: installedVer,
                                latestVersion: latest,
                                nexusModId: modId,
                                url: "https://www.nexusmods.com/\(self.gameDomain)/mods/\(modId)"
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
```

Replace with:

```swift
                self.fetchModInfo(modId: modId, apiKey: apiKey) { result in
                    defer {
                        concurrencyLimiter.signal()
                        group.leave()
                    }

                    lock.lock()
                    switch result {
                    case .success(let latest, let catId, let extra):
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
                        if Self.isNewer(latest, installed: installedVer) {
                            updates.append(ModUpdate(
                                name: modName,
                                installedVersion: installedVer,
                                latestVersion: latest,
                                nexusModId: modId,
                                url: "https://www.nexusmods.com/\(self.gameDomain)/mods/\(modId)"
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
```

- [ ] **Step 5: Persist merged extras and include them in the final `CheckResult`**

Find:

```swift
            // Wait for all in-flight requests to drain.
            group.wait()

            UserDefaults.standard.set(Date(), forKey: self.lastCheckKey)
            // Persist the merged category map so the mods-list filter can show
            // categories even before the user re-runs a check. Lock to avoid
            // racing with a concurrent fetchSingleMod write.
            self.categoryCacheLock.lock()
            // Merge with any categories fetched by on-demand calls while this
            // check was running, so we don't clobber them.
            var mergedCats = self.loadCachedCategories()
            for (k, v) in categories { mergedCats[k] = v }
            self.saveCachedCategories(mergedCats)
            self.categoryCacheLock.unlock()
            let categoriesSnapshot = mergedCats
            let finalResult: CheckResult
            if let err = lastError, updates.isEmpty {
                if err.hasPrefix("rate_limited:") {
                    let retry = TimeInterval(err.split(separator: ":").last ?? "0") ?? 0
                    finalResult = .rateLimited(retryAfter: retry)
                } else {
                    finalResult = .error(err)
                }
            } else {
                self.saveCachedUpdates(updates)
                finalResult = .success(updates: updates, categories: categoriesSnapshot)
            }
            DispatchQueue.main.async { completion(finalResult) }
```

Replace with:

```swift
            // Wait for all in-flight requests to drain.
            group.wait()

            UserDefaults.standard.set(Date(), forKey: self.lastCheckKey)
            // Persist the merged category + extras maps so the mods-list
            // filter and popover preview can show data even before the user
            // re-runs a check. Lock to avoid racing with a concurrent
            // fetchSingleMod write.
            self.metadataCacheLock.lock()
            // Merge with any categories/extras fetched by on-demand calls
            // while this check was running, so we don't clobber them.
            var mergedCats = self.loadCachedCategories()
            for (k, v) in categories { mergedCats[k] = v }
            self.saveCachedCategories(mergedCats)
            var mergedExtras = self.loadCachedExtras()
            for (k, v) in extras { mergedExtras[k] = v }
            self.saveCachedExtras(mergedExtras)
            self.metadataCacheLock.unlock()
            let categoriesSnapshot = mergedCats
            let extrasSnapshot = mergedExtras
            let finalResult: CheckResult
            if let err = lastError, updates.isEmpty {
                if err.hasPrefix("rate_limited:") {
                    let retry = TimeInterval(err.split(separator: ":").last ?? "0") ?? 0
                    finalResult = .rateLimited(retryAfter: retry)
                } else {
                    finalResult = .error(err)
                }
            } else {
                self.saveCachedUpdates(updates)
                finalResult = .success(updates: updates, categories: categoriesSnapshot, extras: extrasSnapshot)
            }
            DispatchQueue.main.async { completion(finalResult) }
```

- [ ] **Step 6: Update `SingleFetchResult` and `fetchSingleMod()`**

Find:

```swift
    /// Outcome of an on-demand single-mod metadata fetch (used when the user
    /// enters a Nexus mod id in the per-mod editor popover).
    enum SingleFetchResult {
        case success(version: String, categoryId: Int?)
        case noApiKey
        case rateLimited(retryAfter: TimeInterval)
        case error(String)
    }

    /// Fetches a single mod's metadata (latest version + category id) by Nexus
    /// mod id, bypassing the dedupe window. Caches the category immediately so
    /// the mods list picks it up without a full check. The completion is always
    /// invoked on the main queue.
    func fetchSingleMod(modId: String, completion: @escaping (SingleFetchResult) -> Void) {
        guard let apiKey = apiKey(), !apiKey.isEmpty else {
            DispatchQueue.main.async { completion(.noApiKey) }
            return
        }
        fetchModInfo(modId: modId, apiKey: apiKey) { [weak self] result in
            switch result {
            case .success(let version, let catId):
                // Persist the category in the shared cache so it survives
                // relaunches and the mods-list badge appears instantly.
                if let cid = catId, cid > 0, let self = self {
                    self.categoryCacheLock.lock()
                    var cats = self.loadCachedCategories()
                    cats[modId] = cid
                    self.saveCachedCategories(cats)
                    self.categoryCacheLock.unlock()
                }
                DispatchQueue.main.async {
                    completion(.success(version: version, categoryId: catId))
                }
            case .rateLimited(let retry):
                DispatchQueue.main.async { completion(.rateLimited(retryAfter: retry)) }
            case .failure(let msg):
                DispatchQueue.main.async { completion(.error(msg)) }
            }
        }
    }
```

Replace with:

```swift
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
        fetchModInfo(modId: modId, apiKey: apiKey) { [weak self] result in
            switch result {
            case .success(let version, let catId, let extra):
                // Persist the category + extra in the shared cache so they
                // survive relaunches and the mods-list badge / popover preview
                // appear instantly.
                if let self = self {
                    self.metadataCacheLock.lock()
                    if let cid = catId, cid > 0 {
                        var cats = self.loadCachedCategories()
                        cats[modId] = cid
                        self.saveCachedCategories(cats)
                    }
                    var extrasMap = self.loadCachedExtras()
                    extrasMap[modId] = extra
                    self.saveCachedExtras(extrasMap)
                    self.metadataCacheLock.unlock()
                }
                DispatchQueue.main.async {
                    completion(.success(version: version, categoryId: catId, extra: extra))
                }
            case .rateLimited(let retry):
                DispatchQueue.main.async { completion(.rateLimited(retryAfter: retry)) }
            case .failure(let msg):
                DispatchQueue.main.async { completion(.error(msg)) }
            }
        }
    }
```

- [ ] **Step 7: Add the extras cache accessors**

Find:

```swift
    private func saveCachedCategories(_ categories: [String: Int]) {
        guard let data = try? JSONEncoder().encode(categories) else { return }
        UserDefaults.standard.set(data, forKey: cachedCategoriesKey)
    }

    // MARK: - Networking
```

Replace with:

```swift
    private func saveCachedCategories(_ categories: [String: Int]) {
        guard let data = try? JSONEncoder().encode(categories) else { return }
        UserDefaults.standard.set(data, forKey: cachedCategoriesKey)
    }

    // MARK: - Extras cache (summary + picture URL)

    /// Returns the last known `{ nexusModId: NexusModExtra }` map, regardless
    /// of freshness. Used to seed the popover preview on launch before any
    /// check has run this session.
    func cachedExtras() -> [String: NexusModExtra] {
        loadCachedExtras()
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
```

- [ ] **Step 8: Extract `summary`/`picture_url` in `fetchModInfo`**

Find:

```swift
    private enum FetchResult {
        case success(version: String, categoryId: Int?)
        case rateLimited(retryAfter: TimeInterval)
        case failure(String)
    }
```

Replace with:

```swift
    private enum FetchResult {
        case success(version: String, categoryId: Int?, extra: NexusModExtra)
        case rateLimited(retryAfter: TimeInterval)
        case failure(String)
    }
```

Find:

```swift
            // `category_id` is an Int in the Nexus payload; tolerate NSNumber
            // / String just in case the API ever widens the field.
            var categoryId: Int?
            if let cid = dict["category_id"] as? Int {
                categoryId = cid
            } else if let cid = dict["category_id"] as? NSNumber {
                categoryId = cid.intValue
            }
            completion(.success(version: version, categoryId: categoryId))
        }
        task.resume()
    }
```

Replace with:

```swift
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
            completion(.success(version: version, categoryId: categoryId, extra: extra))
        }
        task.resume()
    }
```

- [ ] **Step 9: Add `nexusModExtras` to `StarHubTHViewModel` and seed it at init**

In `StarHubTH/StarHubTHViewModel.swift`, find:

```swift
    /// `{ nexusModId: categoryId }` map populated from each Nexus check.
    /// Survives launches (cached in UserDefaults) so the mods-list category
    /// filter works even before the user re-checks. Mods without a known
    /// category simply don't appear under any category scope.
    @Published var nexusCategories: [String: Int] = [:]
```

Replace with:

```swift
    /// `{ nexusModId: categoryId }` map populated from each Nexus check.
    /// Survives launches (cached in UserDefaults) so the mods-list category
    /// filter works even before the user re-checks. Mods without a known
    /// category simply don't appear under any category scope.
    @Published var nexusCategories: [String: Int] = [:]

    /// `{ nexusModId: NexusModExtra }` map (summary + primary picture URL)
    /// populated alongside `nexusCategories` from the same API response.
    /// Survives launches (cached in UserDefaults). Powers the preview shown
    /// in the mod details popover.
    @Published var nexusModExtras: [String: NexusUpdateChecker.NexusModExtra] = [:]
```

Find:

```swift
        // Seed the category map so the mods-list filter is usable immediately.
        self.nexusCategories = NexusUpdateChecker.shared.cachedCategories()
```

Replace with:

```swift
        // Seed the category map so the mods-list filter is usable immediately.
        self.nexusCategories = NexusUpdateChecker.shared.cachedCategories()
        // Seed the extras map so the popover preview is usable immediately.
        self.nexusModExtras = NexusUpdateChecker.shared.cachedExtras()
```

- [ ] **Step 10: Clear `nexusModExtras` in `clearNexusApiKey()`**

Find:

```swift
    /// Removes the stored Nexus Mods API key.
    func clearNexusApiKey() {
        NexusUpdateChecker.shared.clearApiKey()
        hasNexusApiKey = false
        nexusUpdates = []
        nexusCategories = [:]
        nexusCheckError = nil
    }
```

Replace with:

```swift
    /// Removes the stored Nexus Mods API key.
    func clearNexusApiKey() {
        NexusUpdateChecker.shared.clearApiKey()
        hasNexusApiKey = false
        nexusUpdates = []
        nexusCategories = [:]
        nexusModExtras = [:]
        nexusCheckError = nil
    }
```

- [ ] **Step 11: Merge `extras` in `checkNexusUpdates`**

Find:

```swift
            switch result {
            case .success(let updates, let categories):
                self.nexusUpdates = updates
                // Merge so a partial/aborted run never erases previously
                // fetched categories. The checker already merged its prior
                // cache, but this guards against any race.
                if !categories.isEmpty {
                    var merged = self.nexusCategories
                    for (k, v) in categories { merged[k] = v }
                    self.nexusCategories = merged
                }
                self.log("Nexus check: \(updates.count) update(s), \(categories.count) categor(ies)", level: .info)
```

Replace with:

```swift
            switch result {
            case .success(let updates, let categories, let extras):
                self.nexusUpdates = updates
                // Merge so a partial/aborted run never erases previously
                // fetched categories. The checker already merged its prior
                // cache, but this guards against any race.
                if !categories.isEmpty {
                    var merged = self.nexusCategories
                    for (k, v) in categories { merged[k] = v }
                    self.nexusCategories = merged
                }
                // Same merge rationale for extras.
                if !extras.isEmpty {
                    var mergedExtras = self.nexusModExtras
                    for (k, v) in extras { mergedExtras[k] = v }
                    self.nexusModExtras = mergedExtras
                }
                self.log("Nexus check: \(updates.count) update(s), \(categories.count) categor(ies)", level: .info)
```

- [ ] **Step 12: Update `fetchMetadata` to cache the extra**

Find:

```swift
    /// Fetches a single mod's metadata (category + latest version) from Nexus
    /// and applies the category to the published `nexusCategories` map so the
    /// mods-list badge updates instantly. Bypasses the dedupe window. Intended
    /// for on-demand lookups after the user enters a mod id in the per-mod
    /// editor popover. `completion` is invoked on the main queue.
    func fetchMetadata(forNexusModId modId: String,
                       completion: @escaping (NexusUpdateChecker.SingleFetchResult) -> Void) {
        NexusUpdateChecker.shared.fetchSingleMod(modId: modId) { [weak self] result in
            guard let self = self else { return }
            if case .success(_, let catId) = result, let cid = catId, cid > 0 {
                self.nexusCategories[modId] = cid
            }
            completion(result)
        }
    }
```

Replace with:

```swift
    /// Fetches a single mod's metadata (category + latest version + summary/
    /// picture) from Nexus and applies it to the published `nexusCategories`
    /// / `nexusModExtras` maps so the mods-list badge and popover preview
    /// update instantly. Bypasses the dedupe window. Intended for on-demand
    /// lookups after the user enters a mod id in the per-mod editor popover.
    /// `completion` is invoked on the main queue.
    func fetchMetadata(forNexusModId modId: String,
                       completion: @escaping (NexusUpdateChecker.SingleFetchResult) -> Void) {
        NexusUpdateChecker.shared.fetchSingleMod(modId: modId) { [weak self] result in
            guard let self = self else { return }
            if case .success(_, let catId, let extra) = result {
                if let cid = catId, cid > 0 {
                    self.nexusCategories[modId] = cid
                }
                self.nexusModExtras[modId] = extra
            }
            completion(result)
        }
    }
```

- [ ] **Step 13: Add `modExtra(for:)`**

Find (the end of `nexusLink(for:)`):

```swift
    func nexusLink(for mod: ModItem) -> String {
        let id = effectiveNexusModId(for: mod)
        if !id.isEmpty {
            return "https://www.nexusmods.com/stardewvalley/mods/\(id)"
        }
        if !mod.nexusUrl.isEmpty {
            return mod.nexusUrl
        }
        if mod.isGroup, let children = mod.children {
            for c in children {
                let link = nexusLink(for: c)
                if !link.isEmpty { return link }
            }
        }
        return ""
    }
```

Replace with:

```swift
    func nexusLink(for mod: ModItem) -> String {
        let id = effectiveNexusModId(for: mod)
        if !id.isEmpty {
            return "https://www.nexusmods.com/stardewvalley/mods/\(id)"
        }
        if !mod.nexusUrl.isEmpty {
            return mod.nexusUrl
        }
        if mod.isGroup, let children = mod.children {
            for c in children {
                let link = nexusLink(for: c)
                if !link.isEmpty { return link }
            }
        }
        return ""
    }

    /// The cached Nexus summary + picture URL for a mod, or `nil` when none
    /// has been fetched yet (no check has run, or the mod has no effective
    /// Nexus id). For pack headers with no own data, falls back to the first
    /// child that has some — same convention as `nexusLink(for:)`.
    func modExtra(for mod: ModItem) -> NexusUpdateChecker.NexusModExtra? {
        let id = effectiveNexusModId(for: mod)
        if !id.isEmpty, let extra = nexusModExtras[id] {
            return extra
        }
        if mod.isGroup, let children = mod.children {
            for c in children {
                if let extra = modExtra(for: c) { return extra }
            }
        }
        return nil
    }
```

- [ ] **Step 14: Fix the now-broken pattern match in `ModListView.swift`**

`SingleFetchResult.success` now has 3 associated values, so the existing 2-value pattern match in `commitDraft()` no longer compiles. In `StarHubTH/Views/ModListView.swift`, find:

```swift
        vm.fetchMetadata(forNexusModId: effectiveId) { result in
            switch result {
            case .success(let version, let catId):
                let catName: String? = catId.flatMap { NexusCategory.from(id: $0) }
                    .map { $0.localizedName(vm.L) }
                fetchStatus = .success(categoryName: catName, latestVersion: version)
```

Replace with:

```swift
        vm.fetchMetadata(forNexusModId: effectiveId) { result in
            switch result {
            case .success(let version, let catId, _):
                let catName: String? = catId.flatMap { NexusCategory.from(id: $0) }
                    .map { $0.localizedName(vm.L) }
                fetchStatus = .success(categoryName: catName, latestVersion: version)
```

(The popover doesn't need the extra here — it re-reads `vm.modExtra(for: mod)` reactively once Task 2 wires up the preview UI, since `nexusModExtras` is `@Published`.)

- [ ] **Step 15: Build to confirm everything compiles**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app` — no Swift compile errors.

Run: `grep -rn "categoryCacheLock" StarHubTH/`
Expected: no output (fully renamed to `metadataCacheLock`).

Run: `grep -n "case .success(let version, let catId)" StarHubTH/Views/ModListView.swift`
Expected: no output (the old 2-value pattern is gone; only the 3-value form with `_` remains).

---

### Task 2: Display the Nexus preview in the mod details popover

**Files:**
- Modify: `StarHubTH/Views/ModListView.swift` (`ModDetailsPopover.body`, and a new `previewSection` method)

**Interfaces:**
- Consumes: `vm.modExtra(for mod: ModItem) -> NexusUpdateChecker.NexusModExtra?` and `NexusUpdateChecker.NexusModExtra { summary: String; pictureUrl: String }`, both from Task 1 (already merged and compiling).

- [ ] **Step 1: Add `previewSection` and wire it into `body`**

In `StarHubTH/Views/ModListView.swift`, inside `struct ModDetailsPopover`, find:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            categorySection
            Divider()
            nexusSection
            if !mod.dependencies.isEmpty {
                Divider()
                dependenciesSection
            }
        }
        .padding()
        .frame(width: 320)
        .frame(maxHeight: 380)
        .onAppear { seedDraft() }
    }

    // MARK: Category
```

Replace with:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let extra = vm.modExtra(for: mod), !extra.summary.isEmpty || !extra.pictureUrl.isEmpty {
                previewSection(extra)
                Divider()
            }
            categorySection
            Divider()
            nexusSection
            if !mod.dependencies.isEmpty {
                Divider()
                dependenciesSection
            }
        }
        .padding()
        .frame(width: 320)
        .frame(maxHeight: 380)
        .onAppear { seedDraft() }
    }

    // MARK: Preview (Nexus summary + picture)

    /// Nexus-fetched preview shown at the top of the popover when available.
    /// Purely informational — never triggers a network fetch itself; it only
    /// reflects data already cached by a previous check or on-demand fetch
    /// (see `StarHubTHViewModel.modExtra(for:)`). The image view collapses to
    /// nothing while loading or on failure (no broken-image placeholder) since
    /// `AsyncImage`'s phase closure only attaches a frame in the success case.
    @ViewBuilder
    private func previewSection(_ extra: NexusUpdateChecker.NexusModExtra) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !extra.pictureUrl.isEmpty, let url = URL(string: extra.pictureUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 100)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .cornerRadius(6)
                    }
                }
            }
            if !extra.summary.isEmpty {
                Text(extra.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(4)
            }
        }
    }

    // MARK: Category
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app`.

- [ ] **Step 3: Manual verification in the running app**

Run: `open StarHubTH.app`

1. Open the Mods tab, run a Nexus update check (or enter a Nexus mod id for a specific mod in its info popover and save it) for at least one mod that has a summary and a picture on its Nexus page.
2. Reopen that mod's info popover. Confirm a thumbnail image and 1-4 lines of summary text appear at the very top, above the "Category" section, followed by a divider.
3. Open the info popover for a mod that has never been checked against Nexus (no cached data). Confirm no preview section, no empty divider, and no blank space appear — the popover looks exactly as it did before this feature.
4. If reachable, check a mod whose Nexus entry has a summary but no picture (or vice versa) — confirm only the available piece renders, not an empty box for the missing one.
