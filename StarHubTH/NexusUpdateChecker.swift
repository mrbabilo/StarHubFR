import Foundation

/// Client Nexus Mods pour tout ce qui n'est pas la détection de mises à jour
/// en masse : fiche d'un mod à la demande, description, changelogs, et les
/// caches partagés (catégories, résumés/images, liste de mises à jour connue)
/// que ces requêtes alimentent.
///
/// ⚠️ Ancien rôle disparu : ce client faisait autrefois LA détection de mises
/// à jour, en interrogeant Nexus mod par mod (`check()`, jusqu'à ~850
/// requêtes sur ce parc). Ce chemin a été retiré (Task 10, lot « ancrage des
/// versions ») : `StarHubTHViewModel.checkNexusUpdates` interroge désormais
/// `smapi.io/api/v3.0/mods` en quelques appels groupés — voir
/// `SmapiUpdateClient`. Ce fichier ne fait plus que du ponctuel, à la demande
/// de l'utilisateur (éditeur par mod, fiche détaillée), plus les caches que
/// `checkNexusUpdates` lit pour afficher immédiatement au lancement.
///
/// Utilise l'API publique de Nexus Mods (https://api-docs.nexusmods.com/).
/// Chaque utilisateur fournit sa propre clé API personnelle, gratuite via
/// `https://www.nexusmods.com/users/myaccount?tab=api`. Les clés sont
/// stockées dans le Trousseau macOS (jamais dans UserDefaults), une par app.
final class NexusUpdateChecker {
    static let shared = NexusUpdateChecker()

    // `gameDomain`/`apiBase`/`userAgent`/`appVersion` are centralized in
    // `NexusRequestBuilder` and accessed via `NexusRequestBuilder.xxx` so the
    // whole app reports a single consistent client to Nexus.

    /// UserDefaults key caching the last successful update list (JSON-encoded
    /// `[ModUpdate]`). C'est la **vérité** de la liste des mises à jour, à
    /// plat : ce qui s'affiche en est la consolidation par pack, jamais
    /// l'inverse (voir `StarHubTHViewModel.republishUpdatesFromCache`).
    private let cachedUpdatesKey = "nexusCachedUpdates"
    /// UserDefaults key holding the epoch of the last update check that
    /// returned a response — A2-T4's TTL gate reads it at launch. A failed
    /// pass writes nothing, so the next launch retries.
    private let lastCheckedKey = "nexusUpdatesLastCheckedAt"
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

    /// Back-off partagé après un 429. Les trois chemins réseau (`fetchModInfo`,
    /// `fetchRawDescription`, `fetchChangelogs`) l'arment et le consultent :
    /// sans lui, seul `check()` freinait, et parcourir les fiches de mods
    /// pendant une limitation continuait de taper l'API.
    private var rateLimitGate = NexusRateLimitGate()
    private let rateLimitLock = NSLock()

    private init() {}

    /// `true` si la requête doit être refusée sans partir. Armé par
    /// `noteRateLimit`, relâché tout seul à l'expiration du délai.
    private func isRateLimited() -> Bool {
        rateLimitLock.lock()
        defer { rateLimitLock.unlock() }
        return rateLimitGate.isBlocked()
    }

    /// Enregistre un 429 pour tous les chemins réseau à la fois. Le quota
    /// relevé sur la même réponse accompagne : une fenêtre épuisée avec sa
    /// remise à zéro y vaut plus que le `Retry-After` plafonné (B2-T8).
    private func noteRateLimit(retryAfter: TimeInterval, quota: NexusQuota?) {
        rateLimitLock.lock()
        rateLimitGate.note(retryAfter: retryAfter, quota: quota)
        rateLimitLock.unlock()
    }

    /// Attente restante en secondes, pour rendre un `.rateLimited` cohérent
    /// quand la requête est refusée localement plutôt que par le serveur.
    private func rateLimitRemaining() -> TimeInterval {
        rateLimitLock.lock()
        defer { rateLimitLock.unlock() }
        return rateLimitGate.remaining() ?? 0
    }

    /// Arme la porte quand une réponse est un 429, et relève le quota que
    /// **toute** réponse annonce. Pour les chemins qui rendent `""` sur
    /// n'importe quel échec (`fetchRawDescription`, `fetchChangelogs`) : ils ne
    /// distinguent pas le 429 du reste, mais leur 429 doit quand même freiner
    /// tout le monde.
    ///
    /// Tous les `dataTask` de ce fichier passent par ici, sauf `fetchModInfo`
    /// qui traite son 429 lui-même et appelle donc `noteQuota` directement :
    /// une réponse qui échappe au relevé est un 429 non vu, qui aggrave le
    /// bannissement au lieu de l'attendre.
    private func noteRateLimitIfThrottled(_ response: URLResponse?) {
        guard let http = response as? HTTPURLResponse else { return }
        let quota = noteQuota(from: http)
        guard http.statusCode == 429 else { return }
        noteRateLimit(retryAfter: Self.parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After")),
                      quota: quota)
    }

    // MARK: - Quota (B2-T6)

    /// Clé UserDefaults du dernier quota relevé (JSON d'un `NexusQuota`).
    /// Persisté parce que l'app ne parle plus à l'API Nexus qu'à la demande :
    /// sans ça, les réglages n'afficheraient rien tant qu'aucune fiche de mod
    /// n'a été ouverte dans la session.
    private static let cachedQuotaKey = "nexusQuota"

    /// Posté après chaque relevé, pour que les réglages ouverts se remettent
    /// à jour sans être rouverts.
    static let quotaDidChange = Notification.Name("StarHubFR.nexusQuotaDidChange")

    /// Relève les en-têtes `x-rl-*` d'une réponse Nexus et retient la mesure.
    ///
    /// Une réponse sans ces en-têtes (la patte CDN d'un téléchargement, par
    /// exemple) ne dit **rien** du quota : `NexusQuota.init?` rend `nil` et la
    /// mesure précédente reste en place, plutôt que d'être écrasée par un zéro.
    @discardableResult
    func noteQuota(from response: HTTPURLResponse) -> NexusQuota? {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let key = key as? String else { continue }
            headers[key] = String(describing: value)
        }
        guard let quota = NexusQuota(headers: headers) else { return nil }

        // Le quota décrit un compte. Une réponse partie avant `clearApiKey()`
        // et arrivée après ne doit pas ressusciter celui du compte retiré :
        // plus de clé, plus de relevé. (La garde par génération des caches de
        // métadonnées ne s'applique pas ici — elle suppose de connaître la
        // génération au *départ* de la requête, que ce chemin générique, appelé
        // depuis n'importe quelle réponse, n'a pas.)
        guard apiKey()?.isEmpty == false else { return nil }
        guard let data = try? JSONEncoder().encode(quota) else { return nil }
        UserDefaults.standard.set(data, forKey: Self.cachedQuotaKey)
        // Sur le fil principal : `NotificationCenter.post` délivre de façon
        // synchrone sur le fil qui poste, et `.onReceive` ne change pas de file.
        // Or ce code tourne dans un rappel `URLSession` — poster ici écrirait
        // un `@Published` depuis un fil de fond. C'est la première notification
        // du dépôt postée depuis le réseau ; les autres partent de boutons,
        // déjà sur le fil principal.
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

    /// Demande à Nexus si ce compte est premium.
    ///
    /// La réponse décide d'un bouton : le téléchargement direct par l'API est
    /// réservé aux comptes premium — `/download_link.json` répond sinon
    /// `403 « this is for premium users only »`. Sans ce renseignement, l'app
    /// propose une action qui échouera à coup sûr.
    func fetchAccount(completion: @escaping (NexusAccount?) -> Void) {
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
            // Comme le quota : une réponse arrivée après le retrait de la clé
            // ne doit pas ressusciter le compte auquel elle appartenait.
            guard self.apiKey()?.isEmpty == false else {
                DispatchQueue.main.async { completion(nil) }; return
            }
            if let encoded = try? JSONEncoder().encode(account) {
                UserDefaults.standard.set(encoded, forKey: Self.cachedAccountKey)
            }
            DispatchQueue.main.async { completion(account) }
        }.resume()
    }

    /// Le dernier quota relevé, périmé ou non — c'est l'affichage qui décide
    /// quoi en dire (`NexusQuota.isStale`).
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
        // Drop any cached results so they don't leak across accounts, and
        // bump the generation so an in-flight check()/fetchSingleMod() from
        // the old key discards its results instead of writing them back
        // after this clear. All under the same lock those writes use, so
        // this can't interleave with one of them mid-write either.
        //
        // **Les mises à jour ne sont plus de celles-là.** Elles viennent de
        // smapi.io — source publique, sans compte ni clé — et se déduisent des
        // manifests du disque : rien à faire fuir d'un compte à l'autre. Les
        // effacer ici ne faisait que détruire un travail valide, et obligeait à
        // refaire les 7 lots pour retrouver ce que le retrait de la clé n'avait
        // aucune raison d'emporter. Catégories et fiches, elles, viennent bien
        // de l'API Nexus : leur purge reste juste.
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

    /// Represents a mod that has a newer version available on Nexus.
    /// `uploadedTime` is the Nexus `updated_time` (timestamp of the latest
    /// file/version upload) — used to break ties when several children of a
    /// pack share the same highest version, and surfaced in the UI.
    struct ModUpdate: Identifiable, Equatable {
        /// L'identité d'une ligne est le `UniqueID` du mod, **pas** son
        /// identifiant Nexus. Sur le parc réel, 58 identifiants Nexus sont
        /// portés par plusieurs dossiers et l'identifiant 8828 rassemble trois
        /// mods sans rapport : indexer sur lui donnait plusieurs lignes de même
        /// `id` à un `ForEach`, avec les lignes fantômes et la sélection
        /// incohérente que ça entraîne. L'ancien code s'en protégeait par sa
        /// déduplication par identifiant Nexus, partie avec lui.
        var id: String { uniqueId }
        let uniqueId: String
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
        /// The mod's latest Nexus version (the Main file / changelog version),
        /// captured on every successful fetch. Optional so older cached entries
        /// (written before this field existed) still decode. Used to show a
        /// mod **pack**'s version in the list, since a pack is one Nexus mod
        /// even though its installed children carry their own manifest versions.
        var version: String? = nil
        /// When the mod's latest file/version was uploaded on Nexus
        /// (`updated_timestamp`). Optional/back-compatible; shown as the mod's
        /// "last updated" date in the detail pane.
        var uploadedTime: Date? = nil
    }

    /// Returns the last successful update list, regardless of freshness.
    /// Useful for seeding the UI on launch before any check runs.
    func cachedUpdates() -> [ModUpdate] {
        withMetadataCacheLock { loadCachedUpdates() }
    }

    /// The last update check that returned a response, `nil` if none ever
    /// completed. Read by the launch gate (A2-T4); the manual check button
    /// on the Updates page bypasses the gate — asking outranks freshness.
    var lastSuccessfulCheck: Date? {
        let epoch = UserDefaults.standard.double(forKey: lastCheckedKey)
        return epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
    }

    /// Marks a pass as completed. Called when the smapi.io fetch returned —
    /// per-mod states (broken, abandoned) are data, not failures.
    func recordSuccessfulCheck(at date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastCheckedKey)
    }

    /// Remplace entièrement le cache des mises à jour.
    ///
    /// C'est le **seul** point de persistance du chemin smapi.io. Sans lui, les
    /// lignes trouvées mouraient à la fermeture et le lancement suivant
    /// réaffichait `cachedUpdates()`, c'est-à-dire la liste écrite par le code
    /// que cette branche remplace. L'ancien `check()` persistait ; la garantie
    /// est partie avec lui.
    func replaceCachedUpdates(_ updates: [ModUpdate]) {
        withMetadataCacheLock { saveCachedUpdates(updates) }
    }

    /// Retire une ligne du cache persistant des mises à jour, sur l'identité
    /// qui fait foi : le `UniqueID`.
    ///
    /// La variante sur identifiant Nexus, retirée avec son dernier appelant,
    /// emportait tout ce qui partage la page — et le parc réel montre que
    /// « la page » n'est pas une identité : 47 identifiants y sont déclarés par
    /// plusieurs `UniqueID`, dont le 8828 par trois mods sans rapport.
    ///
    /// Retrait ciblé plutôt que `replaceCachedUpdates(nexusUpdates)` : la liste
    /// en mémoire est consolidée par pack au lancement, pas le cache. La
    /// réécrire entière effacerait les lignes des enfants absorbés.
    func dismissUpdate(uniqueId: String) {
        withMetadataCacheLock {
            let remaining = loadCachedUpdates().filter { $0.uniqueId != uniqueId }
            saveCachedUpdates(remaining)
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
    /// picture) by Nexus mod id. Caches the
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
        /// Optionnel : une charge écrite avant que `ModUpdate` porte ce champ
        /// se décode encore, et retombe alors sur `nexusModId`.
        let uniqueId: String?
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
        // Ne pas repartir tant que le back-off d'un 429 précédent court : la
        // boucle de `check()` s'arrête alors dès le premier mod, et un appel à
        // la demande échoue localement au lieu d'ajouter une requête bannie.
        if isRateLimited() {
            completion(.rateLimited(retryAfter: rateLimitRemaining()))
            return
        }
        // Un modId vient d'un UpdateKey de manifest — source externe non fiable.
        // Sans validation, l'interpoler dans le chemin (`/mods/<modId>.json`)
        // ouvrirait la porte au path traversal et à l'injection de query.
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
            // Relevé du quota avant tout aiguillage : c'est le 429 qui porte le
            // « 0 restant », le chiffre qui compte le plus (B2-T6).
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
            // Single source of truth: bake the latest version + upload date into
            // the extra so every consumer (update check, single fetch, cache)
            // carries them without re-injecting at each call site.
            // Secondary lookup on `files.json`: some mod authors set a stale
            // overview header version (e.g. "1") while uploading version "2.0.0"
            // under Main Files. Querying files.json resolves the true main file version.
            var finalVersion = version
            let finalize = { (ver: String) in
                let extra = NexusModExtra(summary: summary, pictureUrl: pictureUrl,
                                          version: ver, uploadedTime: uploadedDate)
                completion(.success(version: ver, categoryId: categoryId, extra: extra, uploadedTime: uploadedDate))
            }

            guard let filesRequest = NexusRequestBuilder.makeRequest(
                path: "/games/\(NexusRequestBuilder.gameDomain)/mods/\(modId)/files.json",
                apiKey: apiKey
            ) else {
                finalize(finalVersion)
                return
            }

            URLSession.shared.dataTask(with: filesRequest) { filesData, response, _ in
                // La fenêtre de quota peut se fermer entre la requête principale
                // (200) et cette requête secondaire files.json : son 429 doit lui
                // aussi armer la porte partagée, sinon les chemins suivants
                // repartent pendant la limitation.
                self.noteRateLimitIfThrottled(response)
                if let filesData = filesData,
                   let fileList = try? NexusDownloadAPI.decodeFileList(filesData),
                   // X8 : le MAIN le plus récent, pas le premier renvoyé — un
                   // mod à plusieurs MAIN comparerait sinon sa version à une
                   // version passée.
                   let primaryFile = NexusDownloadAPI.pickLatestMainFile(fileList),
                   let fileVer = (primaryFile.version ?? primaryFile.modVersion)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !fileVer.isEmpty {
                    if Self.compare(fileVer, finalVersion) == .orderedDescending {
                        finalVersion = fileVer
                    }
                }
                finalize(finalVersion)
            }.resume()
        }
        task.resume()
    }

    // MARK: - Rich mod detail (Task 3: description + changelog)

    /// Fetches only the raw HTML/BBCode `description` field for a mod, for the
    /// rich detail pane. Reuses the exact same endpoint/headers as
    /// `fetchModInfo` above (mods/{id}.json) rather than standing up a second
    /// client. The pane's changelog comes separately from `fetchChangelogs`
    /// (changelogs.json), so this request only owns the description.
    /// Returns `""` on any failure (no API key, network error, non-200 status,
    /// parse error, missing field) so callers can treat that uniformly as
    /// "offline / unavailable" and keep showing cached/local data instead.
    func fetchRawDescription(modId: Int, completion: @escaping (String) -> Void) {
        guard let apiKey = apiKey(), !apiKey.isEmpty else {
            completion("")
            return
        }
        // Un 429 en cours vaut « indisponible » : la fiche garde ses données en
        // cache au lieu d'ajouter une requête pendant la limitation.
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

    /// Fetches a mod's **complete** changelog via the dedicated
    /// `mods/{id}/changelogs.json` endpoint, which returns every version's
    /// entries (`{ "1.2.0": ["line", …], … }`) — unlike `files.json`, whose
    /// per-file `changelog_html` only covers a single upload. Formats the
    /// result as Markdown, newest version first (compared with
    /// `NexusUpdateChecker.compare`). Yields `""` on any failure (no key,
    /// offline, empty) so the caller keeps its cached/local fallback.
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

    /// Renders `{version: [entries]}` as Markdown, newest version first: a bold
    /// version heading followed by one `- ` bullet per entry. Kept pure/static
    /// so it can be reasoned about (and unit-tested) without networking.
    static func formatChangelogs(_ dict: [String: [String]]) -> String {
        let versions = dict.keys.sorted { compare($0, $1) == .orderedDescending }
        return versions.map { version -> String in
            let lines = dict[version]?.map { "- \($0)" }.joined(separator: "\n") ?? ""
            return "**\(version)**\n\(lines)"
        }.joined(separator: "\n\n")
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
