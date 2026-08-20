import Foundation
import Cocoa
import SwiftUI

enum SaveViewMode: String, Codable {
    case list
    case grid
}

class StarHubTHViewModel: ObservableObject {
    @Published var saveViewMode: SaveViewMode = .list
    @Published var saveSortOption: SaveSortOption = .lastPlayed
    @Published var saveFilterTag: String = ""

    // Does NOT auto-refresh on set — every call site that changes `gameDir`
    // (init, selectGameDir) calls `refresh()` itself, exactly once. This
    // used to auto-refresh here *and* have callers refresh again right
    // after, firing two overlapping background scans that both read/write
    // `gameDir` and `self.mods` with no synchronization between them.
    @Published var gameDir: String = "" {
        didSet {
            UserDefaults.standard.set(gameDir, forKey: UDKey.gameDir)
        }
    }
    
    @Published var outOfDateMods: [ModUpdateInfo] = []
    @Published var smapiErrors: [String] = []
    @Published var showSmapiAlerts: Bool = false
    /// Structured health diagnostics parsed from SMAPI-latest.txt (nil until
    /// first parse). Drives the SMAPI health card in LogsView.
    @Published var smapiDiagnostics: SmapiDiagnostics?
    /// mtime of the parsed SMAPI log (nil if unread); used for the "stale" badge.
    @Published var smapiLogDate: Date?
    /// True when the log's mtime predates this app session (= no game launch
    /// logged since StarHubFR was opened).
    @Published var smapiLogStale: Bool = false
    /// App-session start captured once at init (= app launch for the single
    /// @StateObject VM). Reference for SMAPI-log staleness.
    private let sessionStart = Date()

    /// Folder name of the mod currently being toggled (enabled/disabled), or
    /// nil when no toggle operation is in flight. Drives the spinner shown
    /// next to the toggle in ModListRow during the (now fast, but still
    /// background-dispatched) rename within Mods/.
    @Published var pendingToggleFolder: String? = nil

    /// Folder name of the mod currently being deleted, or nil when no delete
    /// is in flight. Drives the per-row spinner shown in place of the delete
    /// button (and the row is dimmed) during the (potentially slow) folder
    /// removal + rescan.
    @Published var pendingDeleteFolder: String? = nil

    /// Mods with an available update on Nexus Mods (from last user-triggered check).
    @Published var nexusUpdates: [NexusUpdateChecker.ModUpdate] = []
    /// Pourquoi un mod n'a pas pu être vérifié, par `UniqueID`. 115 mods du
    /// parc réel en portent un motif ; ils étaient jusqu'ici indistinguables
    /// à l'écran d'un mod vérifié et à jour.
    @Published private(set) var unverifiableMods: [String: SmapiUpdateResponse.Blocker] = [:]
    /// True while a Nexus check is in flight.
    @Published var isCheckingNexusUpdates: Bool = false
    /// Last error message from a Nexus check (nil = none / not run yet).
    @Published var nexusCheckError: String? = nil
    /// Progress of the in-flight Nexus check: `(done, total)`. `nil` when idle.
    @Published var nexusCheckProgress: (done: Int, total: Int)? = nil
    /// Whether the user has provided a Nexus API key (kept in sync with Keychain).
    @Published var hasNexusApiKey: Bool = false
    /// Set when a Nexus download finishes; MainView observes it to open the
    /// install sheet pre-loaded with the downloaded .zip.
    @Published var pendingDownloadedZip: URL?
    struct NexusInstallSource: Equatable { let modId: Int }
    /// Set alongside pendingDownloadedZip when the zip came from a Nexus download,
    /// so the post-install step can reconcile the manifest version.
    @Published var pendingNexusSource: NexusInstallSource?
    @Published var isDownloadingFromNexus = false
    /// Nexus mod id of the mod currently being downloaded, or nil when idle.
    /// Drives the per-row spinner in the Updates list while a premium update
    /// is in flight (isDownloadingFromNexus only tells "one is running").
    @Published var downloadingNexusModId: Int? = nil
    private let nexusDownloader = NexusDownloader()

    /// Rich detail state for the mod currently shown in the detail pane
    /// (Task 3 data layer; nav wiring lands in a later task).
    struct ModDetailState {
        let modId: Int
        var description: [DescriptionBlock]
        var changelog: [DescriptionBlock]
        var isStale: Bool     // served from cache/local, refresh in-flight or failed
        var isLoading: Bool
    }
    @Published var modDetailState: ModDetailState?
    /// Non-nil = the detail pane is showing this mod. Its didSet kicks off
    /// loading (cache/local instantly, then a background refresh).
    @Published var viewingModDetail: ModItem? {
        didSet { if let m = viewingModDetail { loadModDetail(for: m) } }
    }

    /// Loads a mod's rich detail: cached raw shown instantly (parsed), then a
    /// background refresh. Offline / no-cache → falls back to the local manifest
    /// description. The refreshed result is applied only if `viewingModDetail`
    /// is still this same mod (anti-race guard) — if the user navigated away
    /// before the network call returned, its result is dropped.
    func loadModDetail(for mod: ModItem) {
        let modId = Int(resolvedNexusModId(for: mod)) ?? -1
        // Immediate: cache if any, else local manifest description.
        if modId > 0, let cached = ModDetailCache.load(modId: modId) {
            modDetailState = ModDetailState(modId: modId,
                description: DescriptionBlockParser.parse(cached.description),
                changelog: DescriptionBlockParser.parse(cached.changelog),
                isStale: true, isLoading: modId > 0)
        } else {
            modDetailState = ModDetailState(modId: modId,
                description: DescriptionBlockParser.parse(mod.description),  // local manifest
                changelog: [], isStale: true, isLoading: modId > 0)
        }
        guard modId > 0 else { return }
        // Background refresh: description (mods/{id}.json) + changelog (files.json).
        fetchModDetailRemote(modId: modId) { [weak self] raw in
            guard let self = self, let raw = raw else {
                DispatchQueue.main.async { self?.markDetailNotLoading(modId: modId) }
                return
            }
            ModDetailCache.save(modId: modId, raw)
            DispatchQueue.main.async {
                // Anti-race: only apply if still viewing this mod.
                guard self.viewingModDetail.map({ Int(self.resolvedNexusModId(for: $0)) }) == modId else { return }
                self.modDetailState = ModDetailState(modId: modId,
                    description: DescriptionBlockParser.parse(raw.description),
                    changelog: DescriptionBlockParser.parse(raw.changelog),
                    isStale: false, isLoading: false)
            }
        }
    }

    private func markDetailNotLoading(modId: Int) {
        if modDetailState?.modId == modId { modDetailState?.isLoading = false }
    }

    /// Fetches the remote description + changelog for `modId`, combining two
    /// calls: `NexusUpdateChecker.fetchRawDescription` (mods/{id}.json) and
    /// `fetchChangelogs` (mods/{id}/changelogs.json — the *complete*, all-
    /// versions changelog, not a single file's `changelog_html`). Both reuse
    /// the fork's existing Nexus request infra/headers/API key — no second HTTP
    /// client. Returns `nil` when the description fetch fails (no key / offline
    /// / parse error) so the caller leaves the cached/local fallback untouched
    /// instead of overwriting it with blanks; an empty changelog is fine (some
    /// mods simply have none) and doesn't void the description.
    private func fetchModDetailRemote(modId: Int, completion: @escaping (ModDetailRaw?) -> Void) {
        NexusUpdateChecker.shared.fetchRawDescription(modId: modId) { description in
            guard !description.isEmpty else {
                completion(nil)
                return
            }
            NexusUpdateChecker.shared.fetchChangelogs(modId: modId) { changelog in
                completion(ModDetailRaw(description: description, changelog: changelog))
            }
        }
    }
    /// `{ nexusModId: categoryId }` map populated from each Nexus check.
    /// Survives launches (cached in UserDefaults) so the mods-list category
    /// filter works even before the user re-checks. Mods without a known
    /// category simply don't appear under any category scope.
    @Published var nexusCategories: [String: Int] = [:] {
        didSet { categoryCache.removeAll() }
    }

    /// `{ nexusModId: NexusModExtra }` map (summary + primary picture URL)
    /// populated alongside `nexusCategories` from the same API response.
    /// Survives launches (cached in UserDefaults). Powers the preview shown
    /// in the mod details popover.
    @Published var nexusModExtras: [String: NexusUpdateChecker.NexusModExtra] = [:]

    /// User-assigned category overrides keyed by mod `folderName` (= `ModItem.id`).
    /// A non-nil entry takes precedence over anything fetched from the Nexus API,
    /// which lets the user categorize mods that have no `nexus:` UpdateKey (and
    /// therefore no category_id from the API) as well as correct wrong automatic
    /// assignments. Persisted in UserDefaults so it survives rescans / launches.
    @Published var nexusCustomCategories: [String: Int] = [:] {
        didSet { categoryCache.removeAll() }
    }

    /// User-assigned Nexus mod id overrides keyed by mod `folderName`. Used to
    /// give a Nexus link to mods that don't declare a `nexus:<id>` UpdateKey in
    /// their manifest. When present, it also feeds back into the update check so
    /// the manually-linked mod can be checked for updates like any other.
    @Published var nexusCustomModIds: [String: String] = [:] {
        didSet { categoryCache.removeAll() }
    }

    /// `{ folderName: lastActivatedDate }` — stamped every time a mod (or a
    /// whole pack, which moves as a single folder) transitions from
    /// disabled to enabled, in `toggleMod()` and
    /// `applyProfileToFilesystem()`. Never touched on disable — it records
    /// the *last activation*, not the last state change. Drives the
    /// "Activation order" sort in the mods list. Persisted in UserDefaults.
    @Published var modActivationTimestamps: [String: Date] = [:]

    @Published var smapiInstalledVersion: String? = nil   // nil = not installed
    /// True during the initial launch load (mod scan + save reload + profile
    /// load). Drives the launch spinner overlay in `MainView` so the user sees
    /// immediate feedback before the first mod list is ready.
    @Published var isLaunching: Bool = true
    /// Granular progress for the launch overlay, 0.0 → 1.0. Drives a
    /// determinate progress bar instead of an indeterminate spinner, so the
    /// user sees exactly where the app is in its startup sequence.
    @Published var launchProgress: Double = 0.0
    /// Localized label of the current launch step (e.g. "Scanning mods…").
    /// Updated atomically with `launchProgress` from `performInitialLoad`.
    @Published var launchStep: String = ""

    /// Per-mod progress published (throttled) during `scanMods()`'s top-level
    /// enumeration, so the launch overlay can show "Analyse de <mod>… (X/N)"
    /// instead of a frozen bar. `nil` outside a scan. The overlay maps
    /// `done/total` onto the [`launchScanProgressStart`…`launchScanProgressEnd`]
    /// slice of the launch bar.
    struct ScanProgress: Equatable {
        let done: Int
        let total: Int
        let currentName: String
    }
    @Published var scanProgress: ScanProgress? = nil

    /// Launch-bar slice reserved for the "Scanning mods" phase. Kept as
    /// constants so `performInitialLoad` and the launch overlay agree on how
    /// far the bar should move while `scanMods` streams per-mod progress.
    static let launchScanProgressStart: Double = 0.25
    static let launchScanProgressEnd: Double = 0.70

    @Published var mods: [ModItem] = [] {
        didSet {
            categoryCache.removeAll()
            recomputeFrenchCoverage()
        }
    }

    /// Couverture française par mod, indexée par `folderName`. Absente tant
    /// qu'elle n'est pas calculée — c'est un badge qui apparaît, pas une valeur
    /// qu'on attend.
    ///
    /// La `Coverage` entière est conservée, pas seulement son pourcentage : la
    /// fiche mod doit pouvoir dire **ce qui** manque — les clés absentes, et
    /// surtout les vides, qui cassent l'affichage en jeu au lieu de retomber
    /// sur l'anglais.
    @Published private(set) var frenchCoverageByMod: [String: TranslationCoverage.Coverage] = [:]

    /// L'index des clés obsolètes, relu après chaque calcul de diff. Le lire
    /// depuis le disque à chaque ligne de la liste ouvrirait un fichier par mod
    /// affiché.
    @Published private(set) var outdatedKeysByMod: [String: Int] = [:]

    /// Les mods dont l'anglais est plus récent que le français, mesuré au scan.
    /// Deux lectures d'attributs par dossier `i18n` : assez léger pour la liste
    /// entière, contrairement à la lecture des fichiers eux-mêmes.
    @Published private(set) var staleTranslationMods: Set<String> = []

    /// `@MainActor` explicite : `translationDiff(for:)` n'est pas lui-même
    /// isolé à l'acteur principal, et la reprise après un `await` sur une
    /// tâche détachée n'y revient pas toute seule — `scanMods()` documente
    /// déjà ce piège plus haut dans ce fichier. Sans l'annotation, cette
    /// mutation de `@Published` s'exécuterait parfois hors du fil principal.
    @MainActor
    func reloadOutdatedKeyIndex() {
        guard let store = TranslationBaseline.defaultDirectory() else { return }
        outdatedKeysByMod = TranslationBaseline.loadIndex(in: store)
    }

    /// Le calcul en cours, annulé dès qu'un nouveau scan le rend caduc.
    private var frenchCoverageTask: Task<Void, Never>?

    /// Recalcule la couverture française **hors du thread principal**.
    ///
    /// Jamais pendant le scan : celui-ci est déjà le coût dominant au
    /// lancement, et lire tous les `default.json` et `fr.json` du parc y
    /// ajouterait des secondes. Le badge peut apparaître après la liste.
    ///
    /// Seuls les mods que la détection dit traduits en français sont mesurés —
    /// c'est ce qui rend la passe abordable, et c'est pourquoi cette détection
    /// devait être juste d'abord.
    ///
    /// **Incrémental.** La passe complète coûte ~13 s de lecture disque sur le
    /// parc de référence (424 mods, 159 503 clés), et `mods` est republié à
    /// chaque mise en pause, chaque rafraîchissement, chaque activation de
    /// profil : tout recalculer à chaque fois relancerait ce travail pour rien.
    /// Seuls les mods dont la couverture n'est pas déjà connue sont mesurés.
    /// Mettre un mod en pause déplace son dossier sans toucher à ses fichiers de
    /// traduction — le résultat reste valable. `invalidateFrenchCoverage(for:)`
    /// est là pour les cas où le contenu change réellement.
    private func recomputeFrenchCoverage() {
        frenchCoverageTask?.cancel()
        // L'index des clés obsolètes survit au redémarrage sur disque
        // (`TranslationBaseline.updateIndex`, dans `translationDiff(for:)`),
        // mais sans cette relecture il ne serait jamais chargé en bloc : le
        // filtre « À revoir » repartirait de zéro à chaque lancement pour tout
        // le parc, jusqu'à ce qu'on rouvre un par un les onglets Traduction
        // déjà consultés lors d'une session précédente. Une seule lecture d'un
        // petit fichier JSON, sans mesure de fichiers : le coût est
        // négligeable, même répété à chaque recalcul (mise en pause,
        // rafraîchissement, activation de profil). `Task { @MainActor … }`
        // plutôt qu'un appel direct : cette fonction n'est pas elle-même
        // isolée à l'acteur principal.
        Task { @MainActor [weak self] in
            self?.reloadOutdatedKeyIndex()
        }
        let root = gameDir
        guard !root.isEmpty else { return }
        let known = Set(frenchCoverageByMod.keys)
        let snapshot = mods.filter { !known.contains($0.folderName) }
        guard !snapshot.isEmpty else { return }

        frenchCoverageTask = Task.detached(priority: .utility) { [weak self] in
            let modsPath = (root as NSString).appendingPathComponent("Mods")
            var batch: [String: TranslationCoverage.Coverage] = [:]
            var staleBatch: Set<String> = []
            for mod in snapshot where mod.languages.contains("fr") {
                if Task.isCancelled { return }
                let directory = URL(fileURLWithPath: modsPath)
                    .appendingPathComponent(mod.physicalFolderName)
                guard let coverage = TranslationCoverage.coverage(forModAt: directory,
                                                                  locale: "fr") else { continue }
                batch[mod.folderName] = coverage
                if TranslationFreshness.staleness(forModAt: directory, locale: "fr") != nil {
                    staleBatch.insert(mod.folderName)
                }
                // Publier par paquets : un envoi par mod ferait redessiner la
                // liste des centaines de fois pour rien.
                if batch.count >= 25 {
                    let published = batch
                    let publishedStale = staleBatch
                    batch.removeAll(keepingCapacity: true)
                    staleBatch.removeAll(keepingCapacity: true)
                    await self?.mergeFrenchCoverage(published, stale: publishedStale)
                }
            }
            if Task.isCancelled { return }
            await self?.mergeFrenchCoverage(batch, stale: staleBatch)
        }
    }

    @MainActor
    private func mergeFrenchCoverage(_ batch: [String: TranslationCoverage.Coverage],
                                     stale: Set<String>) {
        guard !batch.isEmpty || !stale.isEmpty else { return }
        frenchCoverageByMod.merge(batch) { _, new in new }
        // Un mod du lot qui n'y est plus signalé a cessé d'être suspect — le
        // retirer d'abord laisse `formUnion` ne faire grandir l'ensemble que
        // de ce que ce lot confirme. Latent aujourd'hui, le balayage étant
        // incrémental (chaque mod n'est mesuré qu'une fois) ; nécessaire dès
        // qu'une re-mesure ciblée existera.
        staleTranslationMods.subtract(batch.keys)
        staleTranslationMods.formUnion(stale)
    }

    /// Le taux à afficher sur la pastille de la liste, si mesuré.
    func frenchCoverage(for mod: ModItem) -> Int? {
        frenchCoverageByMod[mod.folderName]?.displayPercent
    }

    /// Le détail de la couverture — ce qui manque, ce qui est vide — pour la
    /// fiche mod, qui a la place de l'expliquer.
    func frenchCoverageDetail(for mod: ModItem) -> TranslationCoverage.Coverage? {
        frenchCoverageByMod[mod.folderName]
    }

    /// Le diff EN/FR d'un mod, clé par clé.
    ///
    /// **Hors du fil principal, obligatoirement.** Lire et analyser les fichiers
    /// d'un mod n'est pas gratuit : `East Scarp NPCs` en compte 11 021 clés
    /// réparties sur plusieurs composants. Le faire dans un `.task` synchrone
    /// figerait la fenêtre le temps du chargement — c'est la faute qui avait
    /// rendu la vue des journaux inutilisable à 2 000 lignes.
    ///
    /// Rien n'est mis en cache ici : le diff ne sert qu'à une vue ouverte à la
    /// demande, là où la couverture alimente une liste entière.
    func translationDiff(for mod: ModItem) async -> [TranslationCoverage.DiffRow] {
        let directory = URL(fileURLWithPath: (gameDir as NSString)
            .appendingPathComponent("Mods"))
            .appendingPathComponent(mod.physicalFolderName)
        let folderName = mod.folderName
        let rows = await Task.detached(priority: .userInitiated) {
            let rows = TranslationCoverage.diffRows(forModAt: directory, locale: "fr")
            guard let store = TranslationBaseline.defaultDirectory() else { return rows }

            // La référence d'abord : elle ne dépend que de ce qu'on a déjà vu.
            let baseline = TranslationBaseline.load(modFolderName: folderName, in: store)
            let marked = TranslationBaselineRules.applying(baseline: baseline, to: rows)

            // Puis l'adoption de ce qu'on découvre — sans elle, une traduction
            // déjà présente sur le disque ne pourrait jamais être dite obsolète,
            // faute de point de comparaison — et le réancrage de ce qui a été
            // retraduit, sans quoi ces clés-là deviendraient des angles morts
            // permanents.
            let adopted = TranslationBaselineRules.adoptions(rows: marked, existing: baseline)
            let refreshed = TranslationBaselineRules.refreshments(rows: marked, existing: baseline)
            if !adopted.isEmpty || !refreshed.isEmpty {
                let updated = baseline
                    .merging(adopted) { _, new in new }
                    .merging(refreshed) { _, new in new }
                try? TranslationBaseline.save(updated, modFolderName: folderName, in: store)
            }
            // L'index alimente le filtre de la liste sans rouvrir les magasins.
            let outdated = marked.filter { $0.state == .outdated }.count
            try? TranslationBaseline.updateIndex(modFolderName: folderName,
                                                 outdatedCount: outdated, in: store)
            return marked
        }.value
        await reloadOutdatedKeyIndex()
        return rows
    }

    /// L'anglais de ce mod a-t-il été touché après son français ?
    ///
    /// Hors du fil principal : la mesure lit les attributs de chaque fichier de
    /// chaque dossier `i18n`, et un mod peut en avoir plusieurs.
    func translationStaleness(for mod: ModItem) async -> TranslationFreshness.Staleness? {
        let directory = URL(fileURLWithPath: (gameDir as NSString)
            .appendingPathComponent("Mods"))
            .appendingPathComponent(mod.physicalFolderName)
        return await Task.detached(priority: .utility) {
            TranslationFreshness.staleness(forModAt: directory, locale: "fr")
        }.value
    }

    /// Le nombre de clés obsolètes connues pour ce mod, tel que l'index le
    /// garde du dernier calcul de son diff. Zéro tant qu'on n'a jamais ouvert
    /// son onglet Traduction : sans référence, il n'y a pas de verdict.
    func outdatedKeyCount(for mod: ModItem) -> Int {
        outdatedKeysByMod[mod.folderName] ?? 0
    }

    /// Une traduction française de ce mod retrouvée dans une sauvegarde.
    ///
    /// Une mise à jour remplace le dossier du mod, et les auteurs ne
    /// redistribuent pas toujours les traductions communautaires : le `fr.json`
    /// disparaît sans que rien ne le signale. Sur le parc de l'auteur, **43 des
    /// 86 mods traduisibles sans français** ont pourtant une traduction dans une
    /// sauvegarde — la moitié.
    ///
    /// Phase 1 se limite à le dire. La récupération relève de B4-T4.
    func backupTranslation(for mod: ModItem) async -> TranslationBackupFinder.Found? {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("StarHubTH/Backups", isDirectory: true)
        guard let base else { return nil }
        let roots = ["ModInstalls/backups", "ModConfigs/backups"]
            .map { base.appendingPathComponent($0, isDirectory: true) }
        let folderName = mod.folderName
        return await Task.detached(priority: .utility) {
            TranslationBackupFinder.mostRecentFrenchFile(forModFolder: folderName,
                                                         inBackupRoots: roots)
        }.value
    }

    /// Les fichiers de traduction de ce mod que le jeu n'ouvrira jamais — un
    /// `pt-BR.json` sans `pt.json`, un `fr-FR.json` mort à côté d'un `fr.json`
    /// bien nommé. Cherché à l'ouverture de la fiche, hors du fil principal :
    /// une lecture de dossier par composant, pas gratuite sur un mod à
    /// plusieurs `i18n`.
    func unloadableLocaleFiles(for mod: ModItem) async -> [I18nLocaleResolver.UnloadableLocaleFile] {
        let directory = URL(fileURLWithPath: (gameDir as NSString)
            .appendingPathComponent("Mods"))
            .appendingPathComponent(mod.physicalFolderName)
        return await Task.detached(priority: .utility) {
            I18nLocaleResolver.unloadableLocaleFiles(inModDirectory: directory)
        }.value
    }

    /// Le résultat d'un `saveTranslation(...)`.
    ///
    /// Un simple `[Mismatch]` ne distinguait pas un enregistrement réussi d'un
    /// échec : les deux rendaient `[]`, composant introuvable ou `default.json`
    /// illisible compris. Un traducteur aurait cru son travail sauvé.
    enum SaveOutcome: Equatable {
        /// Écrit sur le disque.
        case saved
        /// Une divergence de token dure, ni acceptée ni déjà déroguée : rien
        /// n'a été écrit, à l'appelant de demander confirmation.
        case blocked([TranslationTokenCheck.Mismatch])
        /// Rien n'a été écrit. Le message est déjà dans le journal — cette
        /// valeur ne fait que le rendre visible à l'appelant.
        case failed(String)
    }

    // MARK: - Pré-traduction assistée

    /// Posé quand une pré-traduction échoue faute de serveur configuré :
    /// l'appelant en fait l'invitation à ouvrir les réglages au lieu d'un
    /// message d'erreur générique.

    /// Le glossaire en mémoire — une langue à la fois : le hub FR n'en charge
    /// qu'une, et recharger le JSON à chaque clé traduite serait payer le
    /// même fichier des centaines de fois dans un lot.
    private var glossaryCache: (language: String, glossary: Glossary)?
    /// Le contrôle de fraîcheur du glossaire n'a lieu qu'une fois par
    /// lancement — voir `refreshGlossaryIfSourcesChanged`.
    private var checkedGlossaryFreshness = false

    /// Le dossier racine du glossaire en Application Support — même règle de
    /// placement que `TranslationBaseline`, jamais Caches.
    private static func glossaryAppSupport() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("StarHubTH", isDirectory: true)
    }

    /// Le glossaire courant s'il existe (construit depuis les réglages),
    /// chargé une fois puis gardé en mémoire.
    func currentGlossary(language: String) -> Glossary? {
        if let cache = glossaryCache, cache.language == language { return cache.glossary }
        guard let appSupport = Self.glossaryAppSupport(),
              let glossary = GlossaryStore.load(language: language, appSupport: appSupport) else {
            return nil
        }
        glossaryCache = (language, glossary)
        return glossary
    }

    /// Les termes du jeu présents dans une source anglaise — les chips de
    /// l'éditeur et le prompt IA se servent dans le même panier, c'est ce qui
    /// garantit que l'IA impose ce que les chips proposent.
    func glossaryMatches(for source: String, language: String) -> [GlossaryEntry] {
        currentGlossary(language: language)?.matchEntries(in: source) ?? []
    }

    /// L'endpoint IA validé depuis les préférences, `nil` si l'URL saisie
    /// n'est pas du loopback admissible.
    private var localAIEndpoint: URL? {
        UserDefaults.standard.string(forKey: UDKey.localAIBaseURL)
            .flatMap(LocalLLMEndpoint.validate)
    }

    /// Le nom de modèle choisi, chaîne vide si non configuré.
    private var localAIModelName: String {
        UserDefaults.standard.string(forKey: UDKey.localAIModel) ?? ""
    }

    /// `true` quand URL validée **et** modèle nommé — ce qui rend le bouton
    /// de lot visible (spec §7 : visible s'il reste des clés à traduire et
    /// qu'une IA est configurée).
    var isLocalAIConfigured: Bool {
        localAIEndpoint != nil && !localAIModelName.isEmpty
    }

    /// Propose une traduction par IA locale pour une ligne du diff. Rend la
    /// proposition, ou `nil` — **rien n'est écrit sur le disque** : le
    /// brouillon remplit le champ, l'« Enregistrer » explicite reste le seul
    /// chemin d'écriture, et la voie par clé ne pose jamais le drapeau
    /// « à relire » (spec §2.4).
    ///
    /// Sans IA réglée, la vue n'appelle même pas : elle affiche où aller
    /// (`isLocalAIConfigured` est son garde-fou). La garde ci-dessous reste
    /// la ceinture — rendre `nil` plutôt qu'un message trompeur.
    @MainActor
    func preTranslate(mod: ModItem, locale: String,
                      row: TranslationCoverage.DiffRow) async -> String? {
        guard let base = localAIEndpoint, !localAIModelName.isEmpty else {
            return nil
        }
        let request = LocalLLMClient.Request(
            model: localAIModelName,
            source: row.english,
            glossary: glossaryMatches(for: row.english, language: locale),
            sectionLabel: row.section)
        let session = LocalLLMEndpoint.makeSession()
        defer { session.finishTasksAndInvalidate() }
        let outcome = await LocalLLMClient.translate(
            request, baseURL: base, session: session)
        log("Pré-traduction \(mod.folderName)/\(row.key) : \(outcome)", level: .info)
        guard case .translated(let proposal) = outcome else { return nil }
        return proposal
    }

    // MARK: - Pré-traduction par lot

    /// Où en est le lot en cours — `nil` quand aucun lot ne tourne.
    struct BatchProgress: Equatable {
        let done: Int
        let total: Int
    }

    /// Le bilan du dernier lot : les traduites, les clés refusées pour
    /// marques manquantes (nommées), les erreurs, et les termes du glossaire
    /// que l'IA n'a pas repris — un signalement doux, jamais bloquant.
    struct BatchReport: Equatable {
        let translated: Int
        let refusedRowIDs: [String]
        let errors: Int
        let softGlossaryIgnored: Int
    }

    @Published private(set) var batchProgress: BatchProgress?
    @Published private(set) var batchReport: BatchReport?
    private var batchTask: Task<Void, Never>?

    /// Lance le lot — **une requête à la fois** : le GPU local est le goulot
    /// (spec §7). Chaque résultat est persisté immédiatement, avant toute
    /// navigation (spec §8.4) : annuler ou fermer ne perd rien, relancer
    /// reprend ce qui reste.
    @MainActor
    func startBatch(mod: ModItem, locale: String, rows: [TranslationCoverage.DiffRow]) {
        guard batchTask == nil else { return }
        batchReport = nil
        batchTask = Task { await runBatch(mod: mod, locale: locale, rows: rows) }
    }

    /// Arrêt coopératif : la clé en cours finit, la suivante ne part pas.
    func cancelBatch() {
        batchTask?.cancel()
    }

    /// Les identités des clés « à relire » d'un mod, au format de
    /// `DiffRow.id` — le badge et le filtre du diff comparent directement.
    func reviewNeededRowIDs(for mod: ModItem) async -> Set<String> {
        guard let store = TranslationBaseline.defaultDirectory() else { return [] }
        let folder = mod.folderName
        return await Task.detached(priority: .utility) {
            TranslationBaseline.reviewNeededRowIDs(modFolderName: folder, in: store)
        }.value
    }

    // MARK: - Glossaire (réglages)

    /// Le suffixe de fichier du jeu pour une langue cible du hub. Le code du
    /// paramètre (`fr`) est la langue de l'éditeur ; le suffixe (`fr-FR`)
    /// est celui des assets localisés du jeu — deux vocabulaires différents,
    /// la correspondance vit ici.
    private static func gameAssetSuffix(for language: String) -> String {
        switch language {
        case "fr": "fr-FR"
        default: language
        }
    }

    /// Reconstruit le glossaire depuis les sources du jeu installé et
    /// sauvegarde le cache. Rend le nombre d'entrées ; `nil` quand aucune
    /// source n'est trouvable — l'appelant le dit plutôt que d'afficher
    /// « 0 termes » sur un jeu introuvable.
    @MainActor
    @discardableResult
    func rebuildGlossary(language: String = "fr") async -> Int? {
        let folder = gameDir
        let suffix = Self.gameAssetSuffix(for: language)
        let (entries, saved, unreadable) = await Task.detached(priority: .utility) {
            guard let kind = GlossarySource.resolve(gameFolder: URL(fileURLWithPath: folder))
            else { return ([GlossaryEntry](), false, [String]()) }
            // Un asset présent mais illisible amputait le glossaire d'une
            // table entière en silence : le décompte restait rassurant.
            // Absent reste normal (spec §5), illisible se nomme.
            var unreadable: [String] = []
            func map(_ asset: String, _ language: String) -> [String: String]? {
                switch GlossarySource.read(asset: asset, language: language, from: kind) {
                case .loaded(let map): return map
                case .absent: return nil
                case .unreadable:
                    unreadable.append(language.isEmpty ? asset : "\(asset).\(language)")
                    return nil
                }
            }
            let entries = GlossaryBuilder.build(english: { map($0, "") },
                                                french: { map($0, suffix) })
            var saved = false
            if let appSupport = Self.glossaryAppSupport() {
                saved = ((try? GlossaryStore.save(Glossary(entries: entries),
                                                  language: language,
                                                  appSupport: appSupport)) != nil)
            }
            return (entries, saved, unreadable)
        }.value
        if saved { glossaryCache = nil }   // le cache mémoire doit relire
        if !unreadable.isEmpty {
            log("Glossaire \(language) : \(unreadable.count) asset(s) illisibles, ignorés — "
                + unreadable.joined(separator: ", "), level: .warning)
        }
        log(saved ? "Glossaire \(language) reconstruit : \(entries.count) entrées"
                  : "Glossaire \(language) non reconstruit — sources introuvables ou écriture refusée",
            level: .info)
        return saved ? entries.count : nil
    }

    /// Reconstruit le glossaire si les assets du jeu ont bougé depuis sa
    /// construction — une mise à jour de Stardew réécrit `Content/Strings`,
    /// et sans ça le cache gardait les anciens termes indéfiniment, sauf
    /// reconstruction à la main. Une fois par lancement : le contrôle
    /// parcourt les dates du dossier, inutile de le refaire à chaque
    /// ouverture de l'onglet.
    ///
    /// Sans glossaire en cache, rien à faire : c'est « Reconstruire » qui
    /// pose le premier, pas une mise à jour du jeu.
    @MainActor
    func refreshGlossaryIfSourcesChanged(language: String = "fr") async {
        guard !checkedGlossaryFreshness else { return }
        checkedGlossaryFreshness = true
        guard let appSupport = Self.glossaryAppSupport(),
              let builtAt = GlossaryStore.builtDate(language: language, appSupport: appSupport)
        else { return }
        let folder = gameDir
        let stale = await Task.detached(priority: .utility) { () -> Bool in
            guard let kind = GlossarySource.resolve(gameFolder: URL(fileURLWithPath: folder)),
                  let newest = GlossarySource.newestSourceDate(of: kind) else { return false }
            return GlossaryStore.needsRebuild(cachedAt: builtAt, sourcesNewerThan: newest)
        }.value
        guard stale else { return }
        log("Glossaire \(language) périmé — les assets du jeu ont changé depuis sa construction",
            level: .info)
        await rebuildGlossary(language: language)
    }

    /// La date de construction du glossaire en cache — pour la ligne
    /// d'information des réglages.
    func glossaryBuiltDate(language: String = "fr") -> Date? {
        guard let appSupport = Self.glossaryAppSupport() else { return nil }
        return GlossaryStore.builtDate(language: language, appSupport: appSupport)
    }

    /// Le nombre de drapeaux « à relire » gardés en mémoire avant écriture.
    /// Un compromis assumé : la borne de ce qu'un arrêt brutal peut perdre,
    /// et le diviseur du nombre de réécritures du sidecar.
    private static let reviewFlagFlushSize = 25

    /// Écrit les drapeaux accumulés et vide la liste. Une lecture et une
    /// écriture pour tout le paquet ; rien du tout s'il est vide.
    @MainActor
    private func flushReviewFlags(_ flags: inout [TranslationBaseline.ReviewFlag],
                                  mod: ModItem) {
        guard !flags.isEmpty, let store = TranslationBaseline.defaultDirectory() else {
            flags.removeAll()
            return
        }
        do {
            try TranslationBaseline.setReviewNeeded(flags, modFolderName: mod.folderName,
                                                    in: store)
        } catch {
            log("Drapeaux à relire non posés pour \(mod.name) : \(error)", level: .warning)
        }
        flags.removeAll()
    }

    @MainActor
    private func runBatch(mod: ModItem, locale: String,
                          rows: [TranslationCoverage.DiffRow]) async {
        defer { batchTask = nil; batchProgress = nil }
        guard let base = localAIEndpoint, !localAIModelName.isEmpty else {
            return
        }
        // Jamais une valeur française existante (spec §8.2) : le planneur ne
        // retient que ce qui est absent ou vide.
        let eligible = TranslationBatchPlanner.eligibleRows(rows)
        var translated = 0
        var refused: [String] = []
        var errors = 0
        var softIgnored = 0
        var flags: [TranslationBaseline.ReviewFlag] = []
        // Une seule session pour tout le lot : `URLSession` retient fortement
        // son délégué jusqu'à invalidation, une par clé laissait autant de
        // sessions, de délégués et de pools de connexions vivants.
        let session = LocalLLMEndpoint.makeSession()
        defer { session.finishTasksAndInvalidate() }
        batchProgress = BatchProgress(done: 0, total: eligible.count)
        for (index, row) in eligible.enumerated() {
            // Le point d'arrêt : la clé en cours est déjà partie, la
            // suivante ne partira pas — son résultat, s'il arrive, n'est pas
            // écrit puisque l'écriture suit le retour.
            if Task.isCancelled { break }
            let matches = glossaryMatches(for: row.english, language: locale)
            let request = LocalLLMClient.Request(
                model: localAIModelName, source: row.english,
                glossary: matches, sectionLabel: row.section)
            let outcome = await LocalLLMClient.translate(
                request, baseURL: base, session: session)
            switch outcome {
            case .translated(let proposal):
                // Le chemin d'écriture existant, avec son `.bak` et son gate
                // de marques — le client n'a déjà rendu que des traductions
                // sans marque dure manquante, mais le gate reste juge.
                // Le retrait du drapeau est sauté : la clé n'en a pas (le
                // planneur ne retient que du vide) et le lot va le poser.
                if case .saved = saveTranslation(mod: mod, locale: locale,
                                                 row: row, value: proposal,
                                                 clearingReviewFlag: false) {
                    flags.append(.init(component: row.component, key: row.key,
                                       source: row.english, target: proposal))
                    translated += 1
                    // Le français est déjà sur le disque ; le drapeau suit par
                    // paquets. Tout garder pour la fin exposerait un arrêt
                    // brutal — fermeture forcée, panne — à rendre des valeurs
                    // écrites par la machine sans leur badge, donc présentées
                    // comme relues. Un paquet borne la perte à 25 clés au lieu
                    // du lot entier, pour une écriture toutes les 25 au lieu
                    // d'une par clé.
                    if flags.count >= Self.reviewFlagFlushSize {
                        flushReviewFlags(&flags, mod: mod)
                    }
                    // Signalement doux : l'IA n'a pas repris le terme imposé.
                    // Jamais bloquant — le texte reste valide — mais le
                    // rapport le dit.
                    softIgnored += matches.filter { !proposal.contains($0.fr) }.count
                } else {
                    errors += 1
                }
            case .refusedTokens:
                refused.append(row.id)
            case .endpointError:
                // `data(for:)` honore l'annulation : la requête en vol échoue
                // *par notre fait*. La compter ferait rapporter une erreur
                // fantôme à chaque arrêt demandé.
                if !Task.isCancelled { errors += 1 }
            }
            batchProgress = BatchProgress(done: index + 1, total: eligible.count)
        }
        flushReviewFlags(&flags, mod: mod)   // le reliquat, arrêt compris
        batchReport = BatchReport(translated: translated, refusedRowIDs: refused,
                                  errors: errors, softGlossaryIgnored: softIgnored)
        log("Lot \(mod.folderName) : \(translated) traduites, \(refused.count) refusées "
            + "(marques manquantes), \(errors) erreurs, \(softIgnored) termes glossaire ignorés",
            level: .info)
    }

    /// Enregistre une valeur traduite pour une ligne du diff.
    ///
    /// Bloque sur une divergence de tokens **dure**, ni acceptée ni déjà
    /// déroguée : un token dur perdu casse le mod en jeu, et l'utilisateur
    /// n'aurait aucun moyen de s'en apercevoir avant de lancer une partie. Les
    /// divergences souples ne bloquent pas.
    ///
    /// La référence anglaise n'est pas écrite ici : `TranslationBaselineRules`
    /// l'adopte et la réancre au prochain calcul du diff. Un second chemin
    /// d'écriture vers le même magasin est exactement ce que ce dépôt a déjà
    /// payé ailleurs.
    ///
    /// `@MainActor` explicite : `invalidateFrenchCoverage(for:)` l'exige déjà,
    /// et cette méthode mute in fine les mêmes `@Published` par son biais.
    @MainActor
    @discardableResult
    func saveTranslation(mod: ModItem, locale: String,
                         row: TranslationCoverage.DiffRow,
                         value: String,
                         acceptingTokenMismatch: Bool = false,
                         clearingReviewFlag: Bool = true) -> SaveOutcome {
        let blocking = TranslationTokenCheck.mismatches(source: row.english, target: value)
            .filter(\.isHard)

        // Un accord déjà donné pour ce couple source/cible exact vaut réponse
        // — c'est ici, pas côté appelant, que se prend la décision de
        // bloquer. Le magasin n'est consulté que si un blocage est en jeu :
        // payer cette lecture disque à chaque enregistrement ordinaire serait
        // pour rien, la quasi-totalité des sauvegardes n'ayant aucune
        // divergence dure.
        var waived = false
        var baselineStore: URL?
        var existingBaseline: [String: TranslationBaseline.Entry] = [:]
        if !blocking.isEmpty, let store = TranslationBaseline.defaultDirectory() {
            baselineStore = store
            existingBaseline = TranslationBaseline.load(modFolderName: mod.folderName, in: store)
            let entry = existingBaseline[TranslationBaseline.key(component: row.component, key: row.key)]
            waived = TranslationWaiver.isAccepted(entry, source: row.english, target: value)
        }
        let accepted = acceptingTokenMismatch || waived
        // Rendues à l'appelant plutôt qu'écrites : c'est lui qui demandera
        // confirmation, sauf quand l'accord ci-dessus en tient déjà lieu.
        if !blocking.isEmpty && !accepted { return .blocked(blocking) }

        let modDirectory = URL(fileURLWithPath: (gameDir as NSString)
            .appendingPathComponent("Mods"))
            .appendingPathComponent(mod.physicalFolderName)
        guard let i18n = TranslationComponentResolver.directory(forComponent: row.component,
                                                                inModDirectory: modDirectory) else {
            let message = "Traduction non enregistrée : composant introuvable pour \(mod.name)"
            log(message, level: .warning)
            return .failed(message)
        }

        // Un dossier i18n range ses fichiers de deux façons, et SMAPI accepte
        // les deux (voir `I18nLocaleResolver`) : layout A, un fichier par
        // locale à la racine (`fr.json`) ; layout B, un sous-dossier par
        // locale (`fr/dialogue.json`, `fr/items.json`…). Composer
        // "i18n/<locale>.json" à la main revient à ignorer le second cas — et
        // pire, à *casser* un mod en layout B : un seul `.json` écrit à la
        // racine suffit à faire ignorer tous les sous-dossiers par SMAPI, pour
        // toutes les locales (« la racine gagne, entièrement »).
        let sourceFiles = I18nLocaleResolver.files(in: i18n, locale: "default")
        guard !sourceFiles.isEmpty else {
            let message = "Traduction non enregistrée : aucun default.json dans \(i18n.path)"
            log(message, level: .warning)
            return .failed(message)
        }
        let localeFiles = I18nLocaleResolver.files(in: i18n, locale: locale)

        let target: URL
        let realKey: String
        if !localeFiles.isEmpty {
            // La locale existe déjà, sur un ou plusieurs fichiers (layout B).
            // Quand la clé y est déjà, on édite le fichier qui la porte —
            // repliée, puisque SMAPI compare ses clés en `OrdinalIgnoreCase`
            // (`TranslationCoverage.fold`) — jamais un autre : y écrire une
            // clé absente créerait un doublon invisible en jeu (voir la
            // Critique 2 plus bas). `files(in:locale:)` rend ses fichiers
            // triés par nom ; le premier qui porte la clé l'emporte, comme
            // `I18nLocaleResolver.merge` le ferait à la lecture.
            let folded = TranslationCoverage.fold(row.key)
            var found: (file: URL, key: String)?
            for file in localeFiles {
                guard let data = FileManager.default.contents(atPath: file.path),
                      let text = I18nFileDecoder.decode(data)?.text,
                      let parsed = try? I18nLenientParser.parse(text) else { continue }
                if let match = parsed.keys.first(where: { TranslationCoverage.fold($0) == folded }) {
                    found = (file, match)
                    break
                }
            }
            if let found {
                target = found.file
                realKey = found.key
            } else if localeFiles.count == 1 {
                // Un seul fichier pour cette locale : aucune ambiguïté à
                // résoudre, que ce soit layout A (`fr.json`) ou layout B à un
                // seul composant. La clé est neuve pour cette locale — le cas
                // central de l'écran, une ligne « À traduire » — donc écrite
                // sous la casse de la source dans cet unique fichier.
                target = localeFiles[0]
                realKey = row.key
            } else {
                // Layout B à plusieurs fichiers, et aucun ne porte déjà la
                // clé : refuser plutôt qu'inventer celui où la ranger, faute
                // de savoir laquelle des sections (`fr/dialogue.json`,
                // `fr/items.json`…) devrait l'accueillir.
                let message = "Traduction non enregistrée : \(row.key) absente des "
                    + "\(localeFiles.count) fichiers de \(locale) dans \(i18n.path)"
                log(message, level: .warning)
                return .failed(message)
            }
        } else {
            // La locale n'existe pas encore. La créer à la racine (layout A)
            // n'est légitime que si le dossier n'est **pas** déjà en layout B
            // — `sourceFiles` en layout A vit dans `i18n` lui-même ; en
            // layout B, dans un sous-dossier `default/`. Le confondre
            // écrirait un `fr.json` à la racine d'un dossier en layout B, et
            // SMAPI cesserait d'y lire quoi que ce soit.
            let sourceIsLayoutA = sourceFiles.allSatisfy {
                $0.deletingLastPathComponent().path == i18n.path
            }
            guard sourceIsLayoutA else {
                let message = "Traduction non enregistrée : \(locale) inexistante et \(i18n.path) "
                    + "est en layout B — créer un fichier à la racine casserait la lecture des "
                    + "sous-dossiers existants"
                log(message, level: .warning)
                return .failed(message)
            }
            target = i18n.appendingPathComponent("\(locale).json")
            realKey = row.key
        }

        // Le texte source correspondant : celui qui porte le même nom de
        // fichier que la cible choisie, à défaut le premier. Il ne sert qu'à
        // la garde de lisibilité et à l'ordre des clés *nouvelles* — jamais
        // consulté ici, puisqu'une clé trouvée par le bloc ci-dessus a déjà
        // son rang dans le fichier cible, et qu'une création en layout A n'a
        // qu'un seul fichier source possible.
        let sourceFile = sourceFiles.first { $0.lastPathComponent == target.lastPathComponent }
            ?? sourceFiles[0]
        guard let sourceData = FileManager.default.contents(atPath: sourceFile.path),
              let sourceText = I18nFileDecoder.decode(sourceData)?.text else {
            let message = "Traduction non enregistrée : \(sourceFile.path) illisible"
            log(message, level: .warning)
            return .failed(message)
        }

        do {
            let text: String
            if let data = FileManager.default.contents(atPath: target.path),
               let existing = I18nFileDecoder.decode(data)?.text {
                text = try TranslationDocument.apply(edits: [realKey: value],
                                                     toTarget: existing, sourceText: sourceText)
            } else {
                text = try TranslationDocument.create(fromSource: sourceText,
                                                      translations: [realKey: value])
            }
            try TranslationFileStore.write(text, to: target)

            // Consigner l'accord, et lui seul — le reste de la référence est
            // adopté par `TranslationBaselineRules` au prochain calcul du diff :
            // écrire ici ce qu'il sait déjà poser créerait un second chemin vers
            // le même magasin. Un accord qui tenait déjà (`waived`) n'est pas
            // réécrit : rien n'a changé pour lui.
            if !blocking.isEmpty, accepted, !waived, let store = baselineStore {
                var baseline = existingBaseline
                baseline[TranslationBaseline.key(component: row.component, key: row.key)] =
                    TranslationWaiver.accepting(source: row.english, target: value)
                do {
                    try TranslationBaseline.save(baseline, modFolderName: mod.folderName, in: store)
                } catch {
                    // La traduction, elle, est déjà sur le disque : seul
                    // l'accord de dérogation ne survit pas. Le journaliser
                    // comme toute autre branche d'échec — un `try?` muet
                    // l'aurait fait disparaître sans trace.
                    log("Accord de dérogation non enregistré pour \(mod.name) — \(row.key) : \(error)",
                        level: .warning)
                }
            }

            // Enregistrer la clé (modifiée ou non) retire « à relire »
            // (spec §7) : quelqu'un vient de la relire. Sans drapeau posé,
            // la fonction ne réécrit rien — ce coût est une lecture par
            // enregistrement ordinaire.
            if clearingReviewFlag, let store = TranslationBaseline.defaultDirectory() {
                do {
                    try TranslationBaseline.clearReviewNeeded(component: row.component,
                                                              key: row.key,
                                                              modFolderName: mod.folderName,
                                                              in: store)
                } catch {
                    log("Retrait du drapeau à relire non enregistré pour \(mod.name) — \(row.key) : \(error)",
                        level: .warning)
                }
            }

            // Le fichier vient de changer : sa couverture en cache ne vaut plus
            // rien. Sans cela le pourcentage affiché reste celui d'avant.
            invalidateFrenchCoverage(for: mod.folderName)

            // Remesurée pour ce seul mod, hors du fil principal : le
            // rafraîchissement habituel (`recomputeFrenchCoverage`, déclenché
            // par le `didSet` de `mods`) ne s'applique pas ici — rien ne
            // republie `mods` — et son propre filtre le manquerait de toute
            // façon : `mod.languages.contains("fr")` est calé sur la
            // détection du dernier scan, donc encore faux au moment précis où
            // l'on vient de poser le tout premier `fr.json` d'un mod. Sans ce
            // recalcul ciblé, la carte de couverture de la fiche et la
            // pastille de la liste resteraient vides jusqu'à la fin de la
            // session — `frenchCoverageDetail(for:)` rend `nil`, et
            // `ModDetailView` masque toute la section.
            let root = gameDir
            let folderName = mod.folderName
            let physicalFolderName = mod.physicalFolderName
            Task.detached(priority: .utility) { [weak self] in
                let directory = URL(fileURLWithPath: (root as NSString)
                    .appendingPathComponent("Mods"))
                    .appendingPathComponent(physicalFolderName)
                guard let coverage = TranslationCoverage.coverage(forModAt: directory,
                                                                   locale: locale) else {
                    // Sans cette ligne, l'échec du recalcul rendait exactement
                    // le défaut que ce chemin ferme — carte de couverture vide
                    // jusqu'à la fin de la session — mais sans rien laisser
                    // pour le diagnostiquer.
                    await self?.log("Couverture non recalculée pour \(folderName) : "
                                    + "\(directory.path) illisible", level: .warning)
                    return
                }
                let isStale = TranslationFreshness.staleness(forModAt: directory,
                                                              locale: locale) != nil
                await self?.mergeFrenchCoverage([folderName: coverage],
                                                stale: isStale ? [folderName] : [])
            }

            log("Traduction enregistrée : \(mod.name) — \(row.key)", level: .info)
            return .saved
        } catch {
            let message = "Traduction non enregistrée : \(error)"
            log(message, level: .warning)
            return .failed(message)
        }
    }

    /// Oublie la couverture d'un mod dont les fichiers ont pu changer —
    /// installation, mise à jour, restauration de sauvegarde. Le prochain
    /// passage la recalculera. Sans cet appel, un mod mis à jour garderait
    /// éternellement le pourcentage de sa version précédente — et, sans le
    /// retrait de `outdatedKeysByMod`, son ancien compte de clés obsolètes,
    /// sa note sur la fiche et sa place dans le filtre « À revoir » jusqu'à
    /// ce qu'on rouvre son onglet Traduction.
    ///
    /// `@MainActor` explicite comme `reloadOutdatedKeyIndex()` : trois
    /// `@Published` mutés ici, et rien ne garantirait le fil principal pour
    /// un futur appelant sans l'annotation.
    ///
    /// **La purge de l'index sur disque doit précéder celle en mémoire, et
    /// s'exécuter de façon synchrone.** Purger seulement `outdatedKeysByMod`
    /// ne suffit pas : `index.json` garderait l'ancien compte, et le premier
    /// `reloadOutdatedKeyIndex()` qui suit — au prochain scan, puisque
    /// `recomputeFrenchCoverage()` en déclenche un à chaque republication de
    /// `mods` — le relirait et le réinjecterait, ramenant silencieusement la
    /// note et la place dans le filtre d'un mod pourtant réinstallé. Rendre
    /// cette écriture asynchrone rouvrirait la même fenêtre : un rechargement
    /// qui passerait entre les deux compléterait la course. Le fichier ne
    /// contient que quelques centaines d'entiers — la justesse vaut ici plus
    /// qu'un hoquet théorique sur le fil principal.
    @MainActor
    func invalidateFrenchCoverage(for folderName: String) {
        if let store = TranslationBaseline.defaultDirectory() {
            try? TranslationBaseline.removeFromIndex(modFolderName: folderName, in: store)
        }
        frenchCoverageByMod.removeValue(forKey: folderName)
        staleTranslationMods.remove(folderName)
        outdatedKeysByMod.removeValue(forKey: folderName)
    }
    /// Cache for `category(for:)`, invalidated whenever `mods`,
    /// `nexusCategories`, `nexusCustomCategories`, or `nexusCustomModIds`
    /// change. Without it, a group's dominant-category scan over its
    /// children re-ran on every call (badge, filter, `availableCategories`,
    /// counts) within the same render.
    private var categoryCache: [String: NexusCategory?] = [:]

    /// Top-level enabled mods (packs included as their own header entry).
    /// Feeds `ModConfigBackupManager`, which resolves each pack's enabled
    /// children itself — this stays a simple top-level filter.
    var enabledMods: [ModItem] {
        mods.filter { $0.isEnabled }
    }

    /// Lowercased set of every installed mod's UniqueID (including group children).
    /// Rebuilt in `scanMods()` so that `getMissingDependencies(for:)` stays O(deps)
    /// instead of rebuilding the set on every row render.
    private var installedUniqueIds: Set<String> = []

    /// Lowercased UniqueID → enabled state, rebuilt alongside `installedUniqueIds`.
    /// Used by `getDisabledDependencies(for:)` to flag required deps that are
    /// installed but currently disabled (a real problem for the mod that needs them).
    private var installedModStates: [String: Bool] = [:]

    /// Lowercased UniqueID → the installed `ModItem` (pack children included),
    /// rebuilt in `scanMods()`. The single lookup shared by `dependencyTree(for:)`
    /// (and available to the Issues-filter helpers, which read sibling indexes
    /// rebuilt from the same `scannedMods`). Unlike the bool maps above it yields
    /// the resolved mod, needed to read a dependency's OWN dependencies when
    /// recursing.
    private var installedModsByUniqueId: [String: ModItem] = [:]

    /// Manifest decode cache, keyed by manifest.json absolute path. Each
    /// entry stores the file's mtime alongside the decoded JSON so a stale
    /// cache entry is detected by `stat()` instead of a full re-read + decode.
    /// Persisted across scans (a rescan with no changes does ~N stats and 0
    /// decodes) and mutated on the background queue that runs `scanMods()`.
    /// Guarded by `manifestCacheLock`: `scanMods()` can run concurrently with
    /// itself (refresh + initial load, or a profile activation racing a manual
    /// refresh), and an unprotected Dictionary subscript setter is a classic
    /// EXC_BAD_ACCESS under that race.
    private var manifestCache: [String: (mtime: Date, manifest: [String: Any])] = [:]
    private let manifestCacheLock = NSLock()

    // Thai Translation Hub State
    @Published var thaiTranslations: [ThaiTranslationMod] = []
    /// Set when fetchThaiTranslations() fails (network error, bad response,
    /// unparseable content) — lets the hub show a retry state instead of
    /// spinning forever, since thaiTranslations staying empty is otherwise
    /// indistinguishable from "still loading".
    @Published var thaiTranslationsError: String? = nil
    @Published var viewingThaiMod: ThaiTranslationMod? = nil
    @Published var editingModConfig: ModItem? = nil

    /// Result of the last automatic mod-folder repair run. Non-nil when the
    /// repairer quarantined corrupt items or found duplicates; the UI surfaces
    /// a banner so the user knows what was moved to `_Trash_` and can review.
    @Published var lastRepairReport: ModFolderRepairer.Report? = nil

    /// Transient result message from the Quarantine view's "empty to Mac
    /// Trash" action. Published (not @State on the view) because the recycle
    /// completion fires asynchronously after the view struct may have been
    /// recreated — capturing the VM reference keeps the update observable.
    /// Résultat d'une action de quarantaine : le texte affiché, et s'il
    /// s'agit d'une erreur (rendue en rouge, pas en vert de succès).
    struct QuarantineMessage: Equatable {
        let text: String
        let isError: Bool
    }

    @Published var quarantineActionMessage: QuarantineMessage? = nil

    /// Tracks the set of SMAPI errors already journaled, so only genuinely
    /// new alerts are logged on each re-parse (prevents re-logging the full
    /// list when the count fluctuates between game sessions).
    private var lastLoggedSMAPIErrors: Set<String> = []

    @Published var logEntries: [LogEntry] = []
    /// Maximum number of log entries retained in memory to avoid unbounded growth
    /// during long sessions (each SMAPI reload can append hundreds of lines).
    private let maxLogEntries = 2000
    @Published var alertMessage: String = ""
    @Published var showAlert: Bool = false
    @Published var saves: [SaveGameInfo] = []
    @Published var editingSave: SaveGameInfo? = nil {
        didSet {
            guard let save = editingSave else {
                inventoryToEdit = []
                return
            }
            // `fetchInventory` reads and parses the full save file from
            // disk — dispatched off main so opening the inventory editor
            // doesn't freeze the UI on a large save (verified against a
            // real ~40MB save file).
            inventoryToEdit = []
            let requestedSaveId = save.id
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let items = SaveManager.shared.fetchInventory(for: save) ?? []
                DispatchQueue.main.async {
                    guard let self = self, self.editingSave?.id == requestedSaveId else { return }
                    self.inventoryToEdit = items
                }
            }
        }
    }
    @Published var inventoryToEdit: [InventoryItem] = []
    @Published var viewingSaveTimeline: SaveGameInfo? = nil
    
    @Published var saveToDuplicate: SaveGameInfo? = nil
    @Published var backupToBranch: SaveBackup? = nil

    /// Vrai pendant qu'une écriture de sauvegarde (suppression, duplication,
    /// backup, restauration) tourne en tâche de fond.
    ///
    /// Ces opérations bloquaient le fil principal, ce qui empêchait par
    /// accident un second clic. Une fois asynchrones, le bouton reste vivant :
    /// sans ce drapeau, deux clics sur « Dupliquer » lanceraient deux copies
    /// concurrentes du même dossier. Même rôle qu'`isApplyingProfile` —
    /// `guard` dans le ViewModel, `.disabled` sur les boutons.
    @Published private(set) var isSaveOperationRunning = false
    
    @Published var steamUsername: String = ""
    @Published var steamAvatarPath: String? = nil
    
    private static let supportedLanguages = Set(["en", "fr"])
    /// Les codes de langue SMAPI vivent désormais en Core avec la résolution
    /// qui s'en sert — `I18nLocaleResolver.knownLanguageCodes`. Les garder ici
    /// aurait laissé la moitié de la règle hors de portée des tests.
    static var knownLanguageCodes: Set<String> { I18nLocaleResolver.knownLanguageCodes }
    private static func normalizedLanguage(_ language: String?) -> String {
        guard let language, supportedLanguages.contains(language) else { return defaultLanguage }
        return language
    }
    /// This fork (StarHubFR) launches in **French by default**, regardless of
    /// the system locale — English is only used when the user explicitly picks
    /// it (via the sidebar flag toggle). Only affects a first launch with no
    /// saved `currentLanguage`; an existing choice is always respected.
    private static var defaultLanguage: String { "fr" }
    
    @Published var currentLanguage: String = StarHubTHViewModel.normalizedLanguage(UserDefaults.standard.string(forKey: UDKey.currentLanguage)) {
        didSet {
            if !Self.supportedLanguages.contains(currentLanguage) {
                currentLanguage = "en"
                return
            }
            UserDefaults.standard.set(currentLanguage, forKey: UDKey.currentLanguage)
            UserDefaults.standard.set([currentLanguage], forKey: "AppleLanguages")
        }
    }
    
    
    @Published var modProfiles: [ModProfile] = []
    @Published var activeProfileId: UUID? = nil

    /// True while a profile is being applied to disk (mod folders moving, then
    /// the rescan). Blocks starting another activation until it finishes, and
    /// lets the UI disable the Activate/Manage buttons meanwhile.
    @Published var isApplyingProfile = false

    /// Id of the profile currently being applied, or nil when none is in
    /// flight. Drives the per-row spinner in ModProfilesView (the Activate
    /// button of the matching row is replaced by a ProgressView). Cleared
    /// together with `isApplyingProfile` once the move + rescan completes.
    @Published var applyingProfileId: UUID? = nil

    /// When true, toggling a mod also cascades to its dependencies / dependents.
    @Published var chainToggleDependencies: Bool = UserDefaults.standard.object(forKey: UDKey.chainToggleDependencies) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(chainToggleDependencies, forKey: UDKey.chainToggleDependencies)
        }
    }
    @Published var autoCheckNexusUpdates: Bool = UserDefaults.standard.object(forKey: UDKey.autoCheckNexusUpdates) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoCheckNexusUpdates, forKey: UDKey.autoCheckNexusUpdates)
        }
    }
    
    let smapiInstaller = SmapiInstaller()
    
    init() {
        // Les avertissements de l'installateur SMAPI n'ont pas d'autre chemin
        // vers l'onglet Journaux : sa complétion ne porte qu'un succès ou un
        // échec, et une installation peut réussir en laissant un défaut.
        smapiInstaller.onWarning = { [weak self] message in
            self?.log(message, level: .warning)
        }
        // Force sync AppleLanguages with currentLanguage at startup
        let savedLang = Self.normalizedLanguage(UserDefaults.standard.string(forKey: UDKey.currentLanguage))
        currentLanguage = savedLang
        UserDefaults.standard.set([savedLang], forKey: "AppleLanguages")
        
        // Automatically retrieve saved game path, or attempt to find the default Steam path on Mac
        let savedPath = UserDefaults.standard.string(forKey: UDKey.gameDir) ?? ""
        if !savedPath.isEmpty && FileManager.default.fileExists(atPath: savedPath) {
            self.gameDir = savedPath
        } else {
            self.gameDir = self.detectDefaultGameDir()
        }
        // Seed the first launch step label synchronously so the overlay never
        // shows an empty string before the first async hop lands.
        self.launchStep = self.L(L10n.Main.launchStepInit)
        // IMPORTANT: everything below `performInitialLoad()` runs on a
        // background thread; this `init()` returns as fast as possible so the
        // app window can render the launch overlay without waiting for any
        // JSON decode, file I/O, or cache seeding. The old init blocked the
        // main thread on ~6 UserDefaults decodes + a pack-consolidation pass
        // before the window could appear — visibly slow on cold launches.
        self.performInitialLoad()   // launches the overlay-tracked first load
    }

    /// Seeds the UI with the last-known Nexus data (cached from the previous
    /// session) plus user overrides. Moved out of `init()` so the window can
    /// render the launch overlay immediately; this runs on the background
    /// launch task and publishes each @Published value on the main thread.
    /// All these caches are non-blocking for the first frame: the sidebar
    /// and home tab don't need them, and the mods list catches up the moment
    /// the Nexus data lands.
    private func seedNexusAndUserData() {
        // Keychain lookup — light, but it's still a round-trip to the security
        // daemon, so we avoid it during the time-critical init.
        let hasKey = NexusUpdateChecker.shared.apiKey()?.isEmpty == false
        // Two UserDefaults-backed JSON decodes. Each one independently parses
        // a blob; running them together here (rather than one-by-one on demand)
        // front-loads the work so later UI hits are cache-fast. (Le cache des
        // mises à jour, lui, se relit sur le fil principal juste en dessous —
        // c'est une petite liste, et sa consolidation doit lire `mods`.)
        let categories = NexusUpdateChecker.shared.cachedCategories()
        let extras = NexusUpdateChecker.shared.cachedExtras()
        // User-saved overrides (per-mod custom categories / Nexus id links /
        // activation timestamps). Small dicts, but still UserDefaults I/O.
        let customCats = Self.loadCustomCategories()
        let customIds = Self.loadCustomModIds()
        let activationTs = Self.loadModActivationTimestamps()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasNexusApiKey = hasKey
            // `republishUpdatesFromCache` et non une consolidation calculée en
            // amont : elle lit `mods`, qui est `@Published`, et la lire depuis
            // la file de fond était une lecture non synchronisée. Sur le fil
            // principal, et par le même chemin que la vérification manuelle.
            self.republishUpdatesFromCache()
            self.nexusCategories = categories
            self.nexusModExtras = extras
            self.nexusCustomCategories = customCats
            self.nexusCustomModIds = customIds
            self.modActivationTimestamps = activationTs
        }
    }
    
    func detectDefaultGameDir() -> String {
        let home = NSHomeDirectory()
        let steamPath = "\(home)/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS"
        if FileManager.default.fileExists(atPath: steamPath) {
            return steamPath
        }
        
        let gogPath = "/Applications/Stardew Valley.app/Contents/MacOS"
        if FileManager.default.fileExists(atPath: gogPath) {
            return gogPath
        }
        
        return ""
    }
    
    func selectGameDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            self.gameDir = panel.url?.path ?? ""
            self.refresh()
        }
    }
    
    // Helper to force localization using the currently selected language bundle
    /// Cache of locale-specific bundles keyed by language code (e.g. "en", "th").
    /// Avoids rebuilding a `Bundle(url:)` on every `L(...)` call, which is invoked
    /// dozens of times per render pass.
    private static var bundleCache: [String: Bundle] = [:]
    private static let bundleCacheLock = NSLock()

    private func cachedBundle(for language: String) -> Bundle? {
        Self.bundleCacheLock.lock()
        let cached = Self.bundleCache[language]
        Self.bundleCacheLock.unlock()
        if let cached = cached { return cached }

        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let lprojURL = resourceURL.appendingPathComponent("\(language).lproj")
        guard let bundle = Bundle(url: lprojURL) else { return nil }

        Self.bundleCacheLock.lock()
        Self.bundleCache[language] = bundle
        Self.bundleCacheLock.unlock()
        return bundle
    }

    func localizedString(for key: String) -> String {
        if let bundle = cachedBundle(for: currentLanguage) {
            let result = bundle.localizedString(forKey: key, value: "__MISSING__", table: nil)
            if result != "__MISSING__" { return result }
        }
        // Last resort: return key so missing translations are visible
        return key
    }

    /// Typed-key shorthand. Prefer this over localizedString(for:) with raw strings.
    /// Example: vm.L(L10n.Mods.enabled)
    func L(_ key: String) -> String {
        localizedString(for: key)
    }
    
    func refresh() {
        // Run heavy file I/O off the main thread to keep the UI responsive.
        // Each sub-method dispatches its @Published mutations back to main.
        // `[weak self]` even though the VM is app-lifetime today, so a future
        // non-singleton refactoring (e.g. SwiftUI previews, scoped VMs) can't
        // turn into a retain cycle.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.scanMods()          // also kicks off parseSMAPILog internally
            self.reloadSaves()
            self.fetchSteamUser()
        }
        // Lightweight synchronous check (just reads a file/launches SMAPI -fast).
        self.checkSmapiVersion()
    }

    /// One-shot, idempotent migration from the legacy `Mods_disabled/`
    /// layout to the dot-prefix convention where disabled mods live as
    /// `Mods/.X` (SMAPI ignores dotted folders). Runs on the background
    /// queue from `performInitialLoad`, **before** the first `scanMods()`.
    ///
    /// Guards itself with a UserDefaults flag so it's a no-op on every
    /// subsequent launch, and is safe to call from anywhere. On a partial
    /// failure (e.g. a locked folder) it logs and still sets the flag: any
    /// leftover mods stay invisible to the app until the user reinstalls
    /// them (the permanent `Mods_disabled/` warning in `scanMods` covers
    /// this case and the cross-version-skip case described in the plan's
    /// step 17).
    ///
    /// No registry/timestamp/profile migration is needed: those maps key on
    /// the logical `folderName` (without the dot), which is unchanged.
    private func migrateDisabledModsToDotPrefix(gameDir: String) {
        guard !gameDir.isEmpty else { return }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: UDKey.disabledModsMigratedToDotPrefix) { return }

        let fm = FileManager.default
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let disabledPath = (gameDir as NSString).appendingPathComponent("Mods_disabled")

        // Fast path: no legacy folder → nothing to do.
        guard fm.fileExists(atPath: disabledPath) else {
            defaults.set(true, forKey: UDKey.disabledModsMigratedToDotPrefix)
            return
        }

        // Ensure Mods/ exists so moves below always have a destination.
        try? fm.createDirectory(atPath: modsPath, withIntermediateDirectories: true)


        guard let entries = try? fm.contentsOfDirectory(atPath: disabledPath) else {
            // Can't even read the folder — leave it and let the scanMods
            // warning surface it. Don't set the flag so we retry next launch.
            log("Migration: could not read Mods_disabled/ — skipping (will retry next launch).", level: .warning)
            return
        }

        var failed = 0
        var moved = 0
        for entry in entries {
            if OSJunk.isJunk(entry) { continue }

            let src = (disabledPath as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: src, isDirectory: &isDir)
            // Only migrate directories — a stray file at the root of
            // Mods_disabled/ is left in place (and surfaced by the warning).
            guard isDir.boolValue else { continue }

            let dotName = "." + entry
            let dst = (modsPath as NSString).appendingPathComponent(dotName)
            let finalDst: String
            if fm.fileExists(atPath: dst) {
                // Collision: a `.X` already exists in Mods/ (e.g. from a
                // crashed prior run, or a manual copy). Preserve the data by
                // moving under a unique suffix rather than overwriting.
                let uuid8 = String(UUID().uuidString.prefix(8))
                finalDst = "\(dst)_\(uuid8)"
                log("Migration: collision — Mods/.\(entry) already exists, moved Mods_disabled/\(entry) → Mods/.\(entry)_\(uuid8).", level: .warning)
            } else {
                finalDst = dst
            }

            do {
                try fm.moveItem(atPath: src, toPath: finalDst)
                moved += 1
            } catch {
                failed += 1
                log("Migration: failed to move Mods_disabled/\(entry) → \(finalDst): \(error.localizedDescription)", level: .error)
            }
        }

        // Remove Mods_disabled/ entirely if it's now empty or only holds junk.
        let remaining = (try? fm.contentsOfDirectory(atPath: disabledPath)) ?? []
        let onlyJunk = remaining.allSatisfy(OSJunk.isJunk)
        if onlyJunk {
            do {
                try fm.removeItem(atPath: disabledPath)
            } catch {
                // Non-fatal — the permanent warning will re-surface it.
                log("Migration: could not remove empty Mods_disabled/: \(error.localizedDescription)", level: .warning)
            }
        } else {
            log("Migration: Mods_disabled/ still contains \(remaining.count) non-junk entries (failed moves or stray files) — left in place; see the Mods_disabled warning.", level: .warning)
        }

        log("Migration: moved \(moved) disabled mod(s) to Mods/.X, \(failed) failure(s).", level: failed > 0 ? .warning : .info)
        defaults.set(true, forKey: UDKey.disabledModsMigratedToDotPrefix)
    }

    /// First-launch load tracked by the launch overlay. Mirrors `refresh()`
    /// but publishes a granular progress (0.0 → 1.0) + a localized step label
    /// so the user sees what the app is doing instead of an indeterminate
    /// spinner. Flips `isLaunching` to `false` once the background scan has
    /// finished AND published its results on the main thread, so the overlay
    /// stays up exactly until the first mod list is ready.
    ///
    /// Step weights are rough heuristics — the goal is visible progress, not
    /// precise timing. Heavy filesystem ops (scanMods) get the biggest slice.
    private func performInitialLoad() {
        // Step 0 — "Initializing": caches already seeded synchronously in
        // init (game dir, Nexus caches). Just publish the first frame.
        DispatchQueue.main.async { [weak self] in
            self?.launchStep = self?.L(L10n.Main.launchStepInit) ?? ""
            self?.launchProgress = 0.05
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Le champ `nexusVersion` du registre affirmait une version installée
            // que rien n'attestait. On le retire une fois pour toutes, avant que
            // rien d'autre ne touche le registre ; ce que l'app affirme vit
            // désormais dans les ancres.
            //
            // Hors du fil principal comme le reste de cette étape : c'est une
            // lecture UserDefaults suivie d'une désérialisation JSON complète du
            // registre (jusqu'à ~900 entrées), pas le genre de travail que le
            // commentaire au-dessus de `performInitialLoad` veut voir bloquer le
            // premier rendu de l'overlay.
            //
            // Un registre illisible se signale au lieu de se taire : c'est un
            // filet de récupération, pas un cache. Sans cette branche, un registre
            // corrompu ne serait jamais migré et rien ne le dirait. Naturellement
            // idempotente (rien à retirer une fois fait) : pas besoin d'un drapeau
            // UserDefaults dédié comme la migration voisine.
            switch ModVersionAnchorStore.migrateAwayFromNexusVersion() {
            case .stripped(let folders):
                // Ces dossiers verront leur version « changer » au prochain scan
                // sans que le disque ait bougé — le registre portait la version
                // Nexus, il portera celle du manifest. On les met en grâce pour
                // que `syncInstalledModRegistry` ne ré-estampille pas leur date
                // d'installation, seule trace qu'aucune autre source ne
                // reconstitue.
                UserDefaults.standard.set(folders, forKey: Self.installDateGraceKey)
                self.log("Registre nettoyé : \(folders.count) entrées portaient une version Nexus non constatée",
                    level: .info)
            case .registryUnreadable:
                self.log("Registre des mods illisible : la migration n'a pas pu retirer les versions Nexus non constatées",
                    level: .warning)
            case .nothingToDo:
                break
            }

            // Step 1 — Registry: warm the in-memory cache once. This is the
            // single JSON decode from UserDefaults that every subsequent
            // read depends on. Cheap (cached after this), but explicit so
            // the user knows the registry is part of the startup cost.
            DispatchQueue.main.async { [weak self] in
                self?.launchStep = self?.L(L10n.Main.launchStepRegistry) ?? ""
                self?.launchProgress = 0.15
            }
            _ = self.loadInstalledModRegistry()

            // Step 2 — Scanning mods: the big one. Walks the game's Mods/
            // folder (both enabled entries and `.X` disabled ones, which SMAPI
            // ignores), parses every manifest.json, builds groups, syncs the
            // registry. Published mutations land on main inside scanMods()
            // itself.
            DispatchQueue.main.async { [weak self] in
                self?.launchStep = self?.L(L10n.Main.launchStepScan) ?? ""
                self?.launchProgress = Self.launchScanProgressStart
            }
            // One-shot migration from the legacy Mods_disabled/ layout to the
            // dot-prefix convention (Mods/.X = disabled). Must run BEFORE the
            // first scanMods() so the scanner sees every mod — enabled and
            // disabled — in a single location. Idempotent and safe to call on
            // every launch (it self-guards with a UserDefaults flag).
            self.migrateDisabledModsToDotPrefix(gameDir: self.gameDir)
            self.scanMods()

            // Step 3 — Saves: read & parse the user's save XML files. Can be
            // slow when many saves exist.
            DispatchQueue.main.async { [weak self] in
                self?.launchStep = self?.L(L10n.Main.launchStepSaves) ?? ""
                self?.launchProgress = Self.launchScanProgressEnd
            }
            self.reloadSaves()

            // Step 4 — Steam user identity (lightweight NSUserName call) +
            // profiles (UserDefaults decode) + Nexus caches / overrides.
            // Grouped here because they don't block the mod list and can run
            // concurrently with the UI work that scanMods already published.
            DispatchQueue.main.async { [weak self] in
                self?.launchStep = self?.L(L10n.Main.launchStepProfile) ?? ""
                self?.launchProgress = 0.80
                // loadProfiles() mutates @Published (modProfiles/activeProfileId):
                // call it here, on main, rather than on the background queue below.
                self?.loadProfiles()
            }
            self.fetchSteamUser()

            // Step 4b — Seed the Nexus caches + user overrides (was blocking
            // the window's first paint when it ran in init).
            DispatchQueue.main.async { [weak self] in
                self?.launchStep = self?.L(L10n.Main.launchStepNexus) ?? ""
                self?.launchProgress = 0.90
            }
            self.seedNexusAndUserData()
            // Startup marker — confirms LogsView is receiving entries.
            self.log(self.L(L10n.VM.started), level: .info)

            // Step 5 — Done. Hop back to main *after* scanMods() has
            // published its own @Published mutations, so `isLaunching = false`
            // lands on the same runloop turn as the freshly-populated `mods`
            // array. Animate the bar to 100% then dismiss.
            DispatchQueue.main.async { [weak self] in
                self?.launchStep = self?.L(L10n.Main.launchStepDone) ?? ""
                self?.launchProgress = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                self.isLaunching = false
                if !self.autoCheckNexusUpdates {
                    self.log("Auto-check for Nexus updates skipped (disabled in Settings)", level: .info)
                    return
                }
                // Aucune garde sur la clé API : la vérification passe par
                // smapi.io, qui n'en demande pas. La clé ne sert qu'au
                // téléchargement intégré et aux métadonnées de la fiche. La
                // garde qui était ici privait de toute détection de mise à
                // jour quiconque n'avait pas de compte Nexus.
                self.checkNexusUpdates()
            }
        }
        // SMAPI version probe runs in parallel — it doesn't block the launch
        // overlay because it doesn't gate anything the user sees first.
        self.checkSmapiVersion()
    }
    
    func fetchSteamUser() {
        let home = NSHomeDirectory()
        let vdfPath = "\(home)/Library/Application Support/Steam/config/loginusers.vdf"
        guard let content = try? String(contentsOfFile: vdfPath, encoding: .utf8) else { return }
        
        // Very basic VDF parsing
        var currentSteamID = ""
        var personaName = ""
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let tLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if tLine.hasPrefix("\"7656") {
                currentSteamID = tLine.replacingOccurrences(of: "\"", with: "")
            }
            if tLine.hasPrefix("\"PersonaName\"") {
                let parts = tLine.components(separatedBy: "\"")
                if parts.count >= 4 { personaName = parts[3] }
            }
            if tLine.hasPrefix("\"MostRecent\"") && tLine.contains("\"1\"") {
                break
            }
        }
        
        let resolvedUsername: String
        if !personaName.isEmpty {
            resolvedUsername = personaName
        } else {
            let defaultName = NSFullUserName().components(separatedBy: " ").first ?? ""
            resolvedUsername = defaultName.isEmpty ? L(L10n.VM.defaultFarmerName) : defaultName
        }

        var resolvedAvatarPath: String?
        if !currentSteamID.isEmpty {
            let avatarPathPng = "\(home)/Library/Application Support/Steam/config/avatarcache/\(currentSteamID).png"
            let avatarPathJpg = "\(home)/Library/Application Support/Steam/config/avatarcache/\(currentSteamID).jpg"
            if FileManager.default.fileExists(atPath: avatarPathPng) {
                resolvedAvatarPath = avatarPathPng
            } else if FileManager.default.fileExists(atPath: avatarPathJpg) {
                resolvedAvatarPath = avatarPathJpg
            }
        }

        // `fetchSteamUser` is called from `refresh()`'s background dispatch
        // alongside `scanMods()`/`reloadSaves()` — unlike those two, this
        // used to mutate these @Published properties directly on that
        // background thread instead of hopping back to main.
        DispatchQueue.main.async {
            // Le fallback « Farmer » appartient ici, à côté de la publication
            // du vrai nom : un check `isEmpty` côté appelant (performInitialLoad)
            // s'exécutait avant cette fermeture main et voyait toujours "" → le
            // fallback écrasait le vrai nom (main FIFO). Audit 2026-08-05.
            self.steamUsername = resolvedUsername.isEmpty
                ? (self.L(L10n.VM.defaultFarmerName) ?? "Farmer")
                : resolvedUsername
            if let resolvedAvatarPath = resolvedAvatarPath {
                self.steamAvatarPath = resolvedAvatarPath
            }
        }
    }
    
    func checkSmapiVersion() {
        guard !gameDir.isEmpty else {
            self.smapiInstalledVersion = nil
            return
        }
        self.smapiInstalledVersion = SmapiInstaller.getInstalledVersion(gameDir: gameDir)
    }
    
    func scanMods(includeRepair: Bool = true) {
        guard !gameDir.isEmpty else {
            // scanMods est appelé depuis background (refresh, initialLoad…).
            // Muter @Published mods sur ce thread déclenche un warning SwiftUI —
            // dispatcher sur main, comme l'affectation principale plus bas.
            DispatchQueue.main.async { self.mods = [] }
            return
        }

        // Repair corrupt mod folders (orphans, OS junk, empty dirs) *before*
        // scanning so the scan sees a clean tree. Duplicates are reported but
        // not auto-resolved. The report is captured here on the background
        // thread and published on main below (next to self.mods assignment)
        // to avoid mutating @Published off the main thread.
        //
        // `includeRepair` skips this pass after a toggle: toggling only renames
        // a folder in place (Mods/X ↔ Mods/.X), which can't create orphans, OS
        // junk or X/.X duplicates — so the two recursive tree walks plus the
        // per-manifest JSON decode the repair performs were pure overhead on
        // the toggle path, and were the dominant cause of the 5–10s toggle
        // delay. Repairs still run on initial load, manual refresh, install,
        // delete and profile-apply, where they can actually find new problems.

        // Hoist the file manager + mods path so we can publish an early
        // (0/N) progress frame BEFORE the repair sweep. Without it the launch
        // overlay's bar sits frozen at the scan-start weight while the repair
        // walk + registry decode run with no per-mod name to show yet.
        let fm = FileManager.default
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        if let topCount = try? fm.contentsOfDirectory(atPath: modsPath).count, topCount > 0 {
            let preparing = self.L(L10n.Main.launchStepPreparing)
            DispatchQueue.main.async {
                self.scanProgress = ScanProgress(done: 0, total: topCount, currentName: preparing)
            }
        }

        var repairReport = ModFolderRepairer.Report()
        // detectDuplicates=false: the repairer's disk-walking duplicate pass
        // re-decodes every manifest, which is redundant since we scan them just
        // below. Duplicates are recomputed from `scannedMods` (O(N), in-memory)
        // after the scan. This removes the bulk of the old launch repair cost.
        if includeRepair {
            let repairer = ModFolderRepairer()
            repairReport = repairer.repairIfNeeded(gameDir: gameDir, detectDuplicates: false)
        }

        // Permanent safety net: if a legacy `Mods_disabled/` folder still
        // exists (recréé par un autre outil, ou un retardataire qui passe
        // d'une version pré-migration directement à la version actuelle),
        // the mods it holds are now invisible to the app and would otherwise
        // silently vanish from the list. Surface a single warning so the
        // user knows to reinstall them via drag-and-drop. Survives the N+1
        // removal of the one-shot migration method (plan step 17).
        let disabledModsPath = (gameDir as NSString).appendingPathComponent("Mods_disabled")
        if fm.fileExists(atPath: disabledModsPath) {
            // Source unique OSJunk.isJunk (files + folders + AppleDouble). La liste
            // inline précédente omettait Icon\r, .Spotlight-V100 et .Trashes → un
            // Mods_disabled/ ne contenant que ces résidus déclenchait un faux
            // warning « still contains mods » (divergence de copie).
            let hasNonJunk = (try? fm.contentsOfDirectory(atPath: disabledModsPath))?
                .contains { entry in !OSJunk.isJunk(entry) } ?? false
            if hasNonJunk {
                log("Mods_disabled/ still contains mods — they are now invisible to StarHubTH. Reinstall them via drag-and-drop to make them appear under Mods/.", level: .warning)
            }
        }

        var scannedMods: [ModItem] = []

        // Manifest decode cache hit-test helper. Returns the cached JSON when
        // the on-disk mtime matches the cached entry's mtime, nil otherwise
        // (cache miss, file changed, or unreadable). The actual decode + cache
        // fill happens inline in parseModFolder below. Reads the cache under
        // `manifestCacheLock` because two concurrent `scanMods()` runs (refresh
        // + initial load, or a profile activation racing a manual refresh)
        // would otherwise race on the dictionary's storage.
        func cachedManifest(at manifestPath: String) -> [String: Any]? {
            guard let attrs = try? fm.attributesOfItem(atPath: manifestPath),
                  let mtime = attrs[.modificationDate] as? Date else {
                return nil
            }
            manifestCacheLock.lock()
            let cached = manifestCache[manifestPath]
            manifestCacheLock.unlock()
            guard let cached, cached.mtime == mtime else {
                return nil
            }
            return cached.manifest
        }

        // Helper to parse a folder containing manifest.json
        func parseModFolder(at path: String, relativePath: String, isEnabled: Bool) -> ModItem? {
            let manifestPath = (path as NSString).appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestPath) else { return nil }

            // Logical on-disk leaf name, with the disabled dot-prefix stripped.
            // For a top-level disabled mod the physical folder is `Mods/.X`, so
            // `lastPathComponent` yields `.X`. `folderName` is the logical key
            // (registry, profiles, activation timestamps, backups) and must
            // NEVER carry the dot — otherwise `physicalFolderName` (= "." +
            // folderName) would compute `..X`, and every on-disk access
            // (toggle, open-in-Finder, config editor) would miss the folder.
            // This is exactly the bug that left disabled mods un-toggleable and
            // un-openable. `relativePath` is already computed against the
            // physical root, so nested/pack mods never carry the prefix and
            // need no stripping.
            let physicalLeaf = (path as NSString).lastPathComponent
            let logicalLeaf = physicalLeaf.hasPrefix(".") ? String(physicalLeaf.dropFirst()) : physicalLeaf

            // Resolve the folder name used as the registry key — mirrors the
            // logic that sets `folderName` on the ModItem below.
            let resolvedFolderName = relativePath.isEmpty
                ? logicalLeaf
                : relativePath

            // Install date: prefer the persistent registry (records the actual
            // installation timestamp on this machine), which is far more
            // reliable than the on-disk folder mtime — `copyItem` preserves the
            // archive's packaging date, and backup/restore operations can shift
            // it too. Fall back to the folder mtime only for mods installed
            // before the registry existed.
            let installedFileDate: Date? = installedModDate(for: resolvedFolderName)
                ?? {
                    if let attrs = try? fm.attributesOfItem(atPath: path) {
                        return attrs[.modificationDate] as? Date
                    }
                    return nil
                }()
            let hasConfigFile = fm.fileExists(atPath: (path as NSString).appendingPathComponent("config.json"))
            // Les langues que le mod livre, pour la fiche et le filtre FR.
            //
            // Ne lisait que `<mod>/i18n`, par nom de fichier. Deux angles morts,
            // mesurés sur le parc : un content pack range son `i18n` sous
            // `[CP] Nom/` (121 dossiers sur 550 sont à deux niveaux, un à
            // quatre), et une locale peut être un **sous-dossier** dont les
            // fichiers portent d'autres noms (`i18n/fr/gui.json`). Résultat :
            // 90 mods mal détectés, dont **81 dont le français était
            // invisible**. La règle vit désormais en Core avec ses tests.
            let languages = I18nLocaleResolver.languageCodes(
                inModDirectory: URL(fileURLWithPath: path))

            // `name` is overridden from the manifest below when a `Name` field
            // exists, but fall back to the logical (dot-stripped) leaf so a
            // disabled mod missing a `Name` field displays as `X`, not `.X`.
            var name = logicalLeaf
            var uniqueId = ""
            var version = "Unknown"
            var author = "Unknown"
            var description = ""
            var nexusUrl = ""
            var nexusModId = ""
            var updateKeys: [String] = []
            var dependencies: [ModDependency] = []

            // mtime-keyed decode cache: avoids re-reading and re-parsing every
            // manifest.json on a rescan that follows a toggle (which moved only
            // one folder). The cache lives across scans on the VM, so a no-op
            // rescan becomes ~N stat() calls and zero JSON decodes.
            if let cached = cachedManifest(at: manifestPath) {
                if let mName = cached.caseInsensitiveValue(forKey: "Name") as? String { name = mName }
                if let mUniqueId = cached.caseInsensitiveValue(forKey: "UniqueID") as? String { uniqueId = mUniqueId }

                if let read = ManifestVersionReader.version(from: cached) { version = read }

                if let mAuthor = cached.caseInsensitiveValue(forKey: "Author") as? String { author = mAuthor }
                if let mDesc = cached.caseInsensitiveValue(forKey: "Description") as? String { description = mDesc }

                dependencies = ModDependencyParser.parse(manifest: cached)
                updateKeys = cached.caseInsensitiveValue(forKey: "UpdateKeys") as? [String] ?? []

                if let nexus = ModManifest.parseNexusId(fromUpdateKeys: updateKeys) {
                    nexusModId = nexus.id
                    nexusUrl = nexus.url
                }
            } else if let rawData = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
                let rawString = String(data: rawData, encoding: .utf8) {

                // Strip block comments (/* ... */) often added by ModManifestBuilder
                let cleanString = rawString.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)

                var options: JSONSerialization.ReadingOptions = []
                if #available(macOS 12.0, *) {
                    options.insert(.json5Allowed)
                }

                if let data = cleanString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data, options: options) as? [String: Any] {

                    if let mName = json.caseInsensitiveValue(forKey: "Name") as? String { name = mName }
                if let mUniqueId = json.caseInsensitiveValue(forKey: "UniqueID") as? String { uniqueId = mUniqueId }

                let mVer = json.caseInsensitiveValue(forKey: "Version")
                if let vStr = mVer as? String {
                    version = vStr
                } else if let vDict = mVer as? [String: Any] {
                    let major = vDict.caseInsensitiveValue(forKey: "MajorVersion") as? Int ?? 1
                    let minor = vDict.caseInsensitiveValue(forKey: "MinorVersion") as? Int ?? 0
                    let patch = vDict.caseInsensitiveValue(forKey: "PatchVersion") as? Int ?? 0
                    version = "\(major).\(minor).\(patch)"
                }

                if let mAuthor = json.caseInsensitiveValue(forKey: "Author") as? String { author = mAuthor }
                if let mDesc = json.caseInsensitiveValue(forKey: "Description") as? String { description = mDesc }

                dependencies = ModDependencyParser.parse(manifest: json)
                updateKeys = json.caseInsensitiveValue(forKey: "UpdateKeys") as? [String] ?? []

                // Reuse the shared parser so scanning stays in sync with
                // `ModManifest.init` (single source of truth for the
                // `nexus:<id>[@variant]` UpdateKey convention).
                if let nexus = ModManifest.parseNexusId(fromUpdateKeys: updateKeys) {
                    nexusModId = nexus.id
                    nexusUrl = nexus.url
                }

                // Fill the cache so the next scan of an unchanged manifest
                // is a cheap mtime compare + dict reuse. Storing the raw
                // decoded JSON (not a narrowed subset) keeps the cache usable
                // for any future field added to the scan without rework.
                // Write under the lock — concurrent scans would otherwise race
                // on the dictionary subscript setter (EXC_BAD_ACCESS).
                if let mtime = (try? fm.attributesOfItem(atPath: manifestPath))?[.modificationDate] as? Date {
                    manifestCacheLock.lock()
                    manifestCache[manifestPath] = (mtime: mtime, manifest: json)
                    manifestCacheLock.unlock()
                }
            }
        }

            return ModItem(
                uniqueId: uniqueId,
                name: name,
                folderName: relativePath.isEmpty ? logicalLeaf : relativePath,
                version: version,
                author: author,
                description: description,
                nexusUrl: nexusUrl,
                nexusModId: nexusModId,
                updateKeys: updateKeys,
                isEnabled: isEnabled,
                dependencies: dependencies,
                installedFileDate: installedFileDate,
                hasConfigFile: hasConfigFile,
                languages: languages
            )
        }

        // Scan a single top-level entry (physicalRoot) for manifest.json files
        // and group them. `physicalRoot` is the on-disk folder name — which
        // for a disabled mod starts with `.` (e.g. `Mods/.CJBCheats`). The
        // `relativePath` passed to parseModFolder is computed relative to
        // `physicalRoot` so the dot prefix never leaks into `folderName`
        // (the registry/profile key) or into the pack grouping key.
        func scanEntryForMods(at physicalRoot: String, topLevelLogicalFolder: String, isEnabled: Bool) {
            let url = URL(fileURLWithPath: physicalRoot)
            var foundMods: [ModItem] = []

            // Sub-scan with `.skipsHiddenFiles` so nested junk (.DS_Store,
            // .git/, ._Foo) stays hidden — the dot-prefix classification of
            // *top-level* entries is handled by the caller, not here.
            // includingPropertiesForKeys: [] — we only filter by filename
            // ("manifest.json"), so prefetching isDirectory per file is pure
            // overhead on a tree with tens of thousands of files.
            if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent.lowercased() == "manifest.json" {
                        let modFolderURL = fileURL.deletingLastPathComponent()
                        // Chemin relatif canonique : on résout les symlinks des
                        // deux côtés (l'énumérateur macOS rapporte /private/var/…
                        // même si la racine était /var/…) puis on ne retire le
                        // préfixe racine qu'une fois. Un replacingOccurrences(of:
                        // url.path) l'amputait à nouveau si la racine réapparaissait
                        // plus loin dans le sous-chemin — jumeau du bug M6 dans
                        // ModFolderRepairer.collectUniqueIds.
                        let resolvedMod = modFolderURL.resolvingSymlinksInPath().path
                        let resolvedRoot = url.resolvingSymlinksInPath().path
                        let rootStd = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
                        let relFromTop = (resolvedMod.hasPrefix(rootStd)
                            ? String(resolvedMod.dropFirst(rootStd.count))
                            : "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        let fullRelPath = relFromTop.isEmpty ? topLevelLogicalFolder : "\(topLevelLogicalFolder)/\(relFromTop)"
                        if let mod = parseModFolder(at: modFolderURL.path, relativePath: fullRelPath, isEnabled: isEnabled) {
                            foundMods.append(mod)
                        }
                    }
                }
            }

            if foundMods.isEmpty {
                return
            } else if foundMods.count == 1 && foundMods[0].folderName == topLevelLogicalFolder {
                scannedMods.append(foundMods[0])
            } else {
                let groupMod = ModItem(
                    uniqueId: "",
                    name: topLevelLogicalFolder,
                    folderName: topLevelLogicalFolder,
                    version: "",
                    author: "Group",
                    description: "\(foundMods.count) mods",
                    nexusUrl: "",
                    nexusModId: "",
                    isEnabled: isEnabled,
                    dependencies: [],
                    children: foundMods,
                    isGroup: true,
                    languages: Set(foundMods.flatMap { $0.languages }).sorted()
                )
                scannedMods.append(groupMod)
            }
        }

        // Top-level enumeration of Mods/ WITHOUT `.skipsHiddenFiles` so the
        // dot-prefixed disabled entries (`.X`) are visible. Each entry is
        // classified exactly the same way `ModFolderRepairer.repairFolder`
        // classifies top-level entries, so the scanner and the repairer agree
        // on what counts as OS junk vs. a disabled mod.
        if fm.fileExists(atPath: modsPath),
           let topEntries = try? fm.contentsOfDirectory(atPath: modsPath) {
            let scanTotal = topEntries.count
            var scanDone = 0
            var lastProgressPublish: CFAbsoluteTime = 0
            for entry in topEntries {
                scanDone += 1
                if OSJunk.isJunk(entry) { continue }
                // Skip trash folders created by a prior repair run — the mods
                // quarantined inside are not active and must not appear in the
                // list nor in duplicate detection.
                if entry.hasPrefix(ModFolderRepairer.trashPrefix) { continue }

                // Dot prefix = disabled mod; strip it for the logical name.
                // Anything else = enabled mod (including the rare legitimate
                // dotted folder a user might have placed — treated as enabled
                // since SMAPI wouldn't load it anyway, but we don't break it).
                let isEnabled = !entry.hasPrefix(".")
                let topLevelLogicalFolder = entry.hasPrefix(".") ? String(entry.dropFirst()) : entry
                let physicalRoot = (modsPath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: physicalRoot, isDirectory: &isDir)
                guard isDir.boolValue else { continue }

                // Throttled progress publish (~12/s) so the launch overlay can
                // show "Analyse de <mod>… (done/total)" instead of a frozen
                // bar. Cheap relative to the per-folder scan that follows.
                let now = CFAbsoluteTimeGetCurrent()
                if now - lastProgressPublish > 0.08 {
                    lastProgressPublish = now
                    let d = scanDone, t = scanTotal
                    let nm = topLevelLogicalFolder
                    DispatchQueue.main.async {
                        self.scanProgress = ScanProgress(done: d, total: t, currentName: nm)
                    }
                }

                scanEntryForMods(at: physicalRoot, topLevelLogicalFolder: topLevelLogicalFolder, isEnabled: isEnabled)
            }
        }

        parseSMAPILog()

        // Synchronize the installed-mod registry with what's on disk. This
        // catches mods added by ANY means — drag-and-drop, manual copy into
        // Mods/, or the app's own installer. The rules:
        //   1. A mod whose version changed since last scan → record NOW.
        //   2. A mod on disk but absent from the registry (first time seen)
        //      → record with the folder mtime as a best-effort date.
        //   3. Registry entries whose folder no longer exists → pruned.
        syncInstalledModRegistry(scannedMods: scannedMods)

        // Detect X/.X duplicates from the just-scanned mods instead of the
        // repairer's separate disk walk — same result, no extra I/O or decode.
        if includeRepair {
            let duplicates = ModFolderRepairer().detectDuplicates(from: scannedMods)
            repairReport = ModFolderRepairer.Report(
                quarantined: repairReport.quarantined,
                duplicates: duplicates,
                trashPath: repairReport.trashPath
            )
        }

        DispatchQueue.main.async {
            // Scan finished — advance the coarse progress to the scan-end
            // weight BEFORE clearing the per-mod scanProgress, so the overlay
            // falls back to launchScanProgressEnd (not the stale scan-start
            // value) and the bar never visibly regresses before step 3 runs.
            self.launchProgress = Self.launchScanProgressEnd
            self.scanProgress = nil
            // Publish the repair report on the main thread (the scan itself
            // runs on a background queue via refresh()).
            // Only touch lastRepairReport when a repair actually ran. A
            // repair-skipped scan (after a toggle) must preserve the last real
            // report instead of clearing it to nil.
            if includeRepair {
                if repairReport.isEmpty {
                    self.lastRepairReport = nil
                } else {
                    self.lastRepairReport = repairReport
                    self.log("Folder repair: \(repairReport.quarantined.count) item(s) quarantined, \(repairReport.duplicates.count) duplicate(s) found.", level: .info)
                }
            }

            self.mods = scannedMods.sorted {
                if $0.isGroup != $1.isGroup {
                    return $0.isGroup
                }
                return $0.name.lowercased() < $1.name.lowercased()
            }
            self.rebuildDependencyIndexes()
            if self.selectedMod == nil, let first = self.mods.first {
                self.selectedMod = first
            }
            // Seed a default profile on first run (no-op after the first time,
            // and once mods have actually been scanned).
            self.ensureDefaultProfileIfNeeded()
        }
    }

    /// Rebuilds the lowercased UniqueID → enabled-state / mod lookup indexes
    /// used for O(1) dependency checks (`getMissingDependencies`, core-mod
    /// slots, …) from the current `mods`. Called at the end of every full
    /// `scanMods()` and after an in-memory toggle, which flips `isEnabled`
    /// without rescanning.
    private func rebuildDependencyIndexes() {
        var ids = Set<String>()
        var states: [String: Bool] = [:]
        var byId: [String: ModItem] = [:]
        for m in mods {
            if m.isGroup, let children = m.children {
                for c in children {
                    let k = c.uniqueId.lowercased()
                    ids.insert(k)
                    states[k] = c.isEnabled
                    byId[k] = c
                }
            } else {
                let k = m.uniqueId.lowercased()
                ids.insert(k)
                states[k] = m.isEnabled
                byId[k] = m
            }
        }
        installedUniqueIds = ids
        installedModStates = states
        installedModsByUniqueId = byId
    }
    
    // Parses the SMAPI-latest.txt log for updates and errors
    func parseSMAPILog() {
        guard !gameDir.isEmpty else { return }
        
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let logPath = (homeDir as NSString).appendingPathComponent(".config/StardewValley/ErrorLogs/SMAPI-latest.txt")
        guard FileManager.default.fileExists(atPath: logPath),
              let logContent = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.outOfDateMods = []
                self.smapiErrors = []
                self.smapiDiagnostics = nil
                self.smapiLogDate = nil
                self.smapiLogStale = false
            }
            return
        }
        
        let (smapiDiag, smapiDate, smapiStale) = computeSmapiDiagnostics(logContent: logContent, atPath: logPath)

        // Bloc « You can update N mods » — voir SmapiLogParser.updates(in:).
        let updates = SmapiLogParser.updates(in: logContent)
        var errors: [String] = []
        
        let lines = logContent.components(separatedBy: .newlines)
        var isParsingErrors = false
        
        for line in lines {
            // Check for Errors (Skipped mods or general red text)
            if line.contains("ERROR SMAPI") {
                if line.contains("Skipped mods") {
                    isParsingErrors = true
                    continue
                }
                
                if isParsingErrors {
                    if line.contains("-------------------------") || line.contains("These mods could not be added") {
                        continue
                    }
                    if line.contains("WARN ") || line.contains("INFO ") || line.contains("TRACE ") || line.contains("DEBUG ") {
                        isParsingErrors = false
                    } else {
                        let parts = line.components(separatedBy: "ERROR SMAPI]")
                        if parts.count > 1 {
                            let msg = parts[1].trimmingCharacters(in: .whitespaces)
                            if !msg.isEmpty {
                                errors.append(msg)
                            }
                        }
                    }
                } else {
                    // General error line not in "Skipped mods"
                    if !line.contains("Skipped mods") && !line.contains("-------------------------") {
                        let parts = line.components(separatedBy: "ERROR")
                        if parts.count > 1 {
                            let msg = parts[1].trimmingCharacters(in: .whitespaces)
                            // Filter out known empty or structural lines
                            if msg.hasPrefix("SMAPI]") {
                                let actualMsg = msg.replacingOccurrences(of: "SMAPI]", with: "").trimmingCharacters(in: .whitespaces)
                                if !actualMsg.isEmpty {
                                    errors.append(actualMsg)
                                }
                            }
                        }
                    }
                }
            } else if isParsingErrors && (line.contains("WARN ") || line.contains("INFO ") || line.contains("TRACE ") || line.contains("DEBUG ")) {
                isParsingErrors = false
            }
        }
        
        // Remove duplicates and limit error messages
        let uniqueErrors = Array(
            Array(NSOrderedSet(array: errors))
                .compactMap { $0 as? String }
                .prefix(10)
        )
        
        DispatchQueue.main.async {
            self.outOfDateMods = updates
            self.smapiErrors = uniqueErrors
            self.smapiDiagnostics = smapiDiag
            self.smapiLogDate = smapiDate
            self.smapiLogStale = smapiStale
            // Log only genuinely new SMAPI alerts (not seen in the previous
            // parse) so the Journaux tab stays clean across re-parses. Diff
            // by content — not count — to catch both added and replaced errors.
            let currentSet = Set(uniqueErrors)
            let newAlerts = currentSet.subtracting(self.lastLoggedSMAPIErrors)
            if !newAlerts.isEmpty {
                self.lastLoggedSMAPIErrors = currentSet
                self.log(
                    String(format: self.L(L10n.Logs.alertLogged), Int64(newAlerts.count)),
                    level: .warning
                )
                for err in uniqueErrors where newAlerts.contains(err) {
                    self.log(err, level: .warning)
                }
            }
        }
    }
    
    // Returns missing required unique IDs for a given mod
    func getMissingDependencies(for mod: ModItem) -> [String] {
        // Uses the precomputed index built in scanMods() — O(deps) per call,
        // safe to invoke from every ModListRow render.
        ModDependencyStatus.missing(for: mod, installedIds: installedUniqueIds)
    }

    /// Required dependency UniqueIDs that are installed but currently disabled.
    /// A disabled required dependency is just as problematic for an enabled mod
    /// as a missing one, so these are surfaced in the "Issues" filter too.
    func getDisabledDependencies(for mod: ModItem) -> [String] {
        ModDependencyStatus.disabled(for: mod, states: installedModStates)
    }

    /// Builds `mod`'s transitive dependency tree (see `DependencyTreeBuilder`).
    /// For a pack header (group, whose own `dependencies` are empty) it seeds the
    /// builder with the de-duplicated UNION of its children's dependencies, so a
    /// pack still shows a meaningful tree. Rebuilds from `@Published mods` state,
    /// so an "Enable" action (which republishes `mods`) makes the view re-resolve.
    func dependencyTree(for mod: ModItem) -> [DependencyNode] {
        let roots: [ModDependency]
        if mod.isGroup, let children = mod.children {
            var merged: [ModDependency] = []
            for child in children {
                for dep in child.dependencies {
                    let key = dep.uniqueId.lowercased()
                    if let idx = merged.firstIndex(where: { $0.uniqueId.lowercased() == key }) {
                        if dep.isRequired && !merged[idx].isRequired {
                            merged[idx] = ModDependency(uniqueId: merged[idx].uniqueId, isRequired: true)
                        }
                    } else {
                        merged.append(dep)
                    }
                }
            }
            roots = merged
        } else {
            roots = mod.dependencies
        }
        return DependencyTreeBuilder.build(roots) { [weak self] uid in
            guard let m = self?.installedModsByUniqueId[uid.lowercased()] else { return nil }
            return (m, m.isEnabled, m.dependencies)
        }
    }

    /// Pre-computed snapshot of the four "core extension" statuses shown on Home.
    /// Computed once per `mods` change (SwiftUI caches getter results within a
    /// single body evaluation) instead of flatMapping all mods 4× per render.
    var coreExtensionsSnapshot: CoreExtensionsSnapshot {
        let allMods = mods.flattenedMods

        func slot(matching keyword: String) -> CoreModSlot {
            CoreModSlot.resolve(keyword: keyword, among: allMods)
        }

        let thaiMod = allMods.first { $0.folderName.lowercased() == "stardew valley - thai" && $0.isEnabled }
            ?? allMods.first { $0.name.localizedCaseInsensitiveContains("thai") && $0.isEnabled }
            ?? allMods.first { $0.folderName.lowercased() == "stardew valley - thai" }
            ?? allMods.first { $0.name.localizedCaseInsensitiveContains("thai") }
        let thaiSlot: CoreModSlot = {
            guard let mod = thaiMod else { return CoreModSlot(status: .notInstalled, mod: nil) }
            return CoreModSlot(status: mod.isEnabled ? .enabledAndInstalled : .installedButDisabled, mod: mod)
        }()

        return CoreExtensionsSnapshot(
            contentPatcher: slot(matching: "content patcher"),
            spacecore: slot(matching: "spacecore"),
            thai: thaiSlot,
            sve: slot(matching: "stardew valley expanded"),
            unarTool: .init(installed: unarInstalled),
            sevenZipTool: .init(installed: sevenZipInstalled)
        )
    }

    /// `true` if `unar` (The Unarchiver) is available in PATH. Used by the
    /// home screen to display a status row for RAR extraction support.
    var unarInstalled: Bool {
        // Même recherche que l'extraction, pour que l'accueil ne puisse pas
        // annoncer une capacité que l'installation n'a pas — cette méthode
        // maintenait auparavant sa propre liste de chemins, plus étroite.
        ModZipInstaller.firstAvailableTool(named: ["unar"]) != nil
    }

    /// `true` si une archive `.7z` peut être extraite. Adossé à
    /// `ModZipInstaller.find7zTool()` — celui-là même qui choisit l'outil au
    /// moment d'extraire — pour que l'accueil ne puisse pas annoncer une
    /// capacité que l'installation n'a pas.
    var sevenZipInstalled: Bool { ModZipInstaller.find7zTool() != nil }
    
    private var isToggling = false
    private var pendingToggles: [(ModItem, (() -> Void)?)] = []

    /// Progress of an in-flight bulk enable/disable-all operation:
    /// `(done, total)`. `nil` when idle. Drives the progress overlay in
    /// `ModListView`. Published on the main thread after each individual move.
    @Published var bulkToggleProgress: (done: Int, total: Int)? = nil
    /// Direction of the in-flight bulk toggle: `true` = enabling all,
    /// `false` = disabling all. Meaningful only while
    /// `bulkToggleProgress` is non-nil.
    @Published var bulkToggleEnabling: Bool = false

    // Toggle Mod Status (Enabled / Disabled)
    //
    // Requests are queued and run one at a time: a queued call only reads
    // self.mods after the previous toggle's full cycle (file move +
    // background scanMods + syncActiveProfileIds) has landed. Without this,
    // two near-simultaneous toggles that share a chain-dependency folder
    // could each compute their move set from a stale isEnabled snapshot —
    // the second call could think a folder still needs moving after the
    // first call already moved it, tripping the "destination already
    // exists" path on a folder that no longer has a source. See performToggle.
    func toggleMod(_ mod: ModItem, completion: (() -> Void)? = nil) {
        // Refuse individual toggles while a bulk enable/disable-all is in
        // flight — concurrent moves on the same folders could lose a mod.
        guard bulkToggleProgress == nil else {
            completion?()
            return
        }
        pendingToggles.append((mod, completion))
        processNextToggleIfNeeded()
    }

    private func processNextToggleIfNeeded() {
        guard !isToggling, !pendingToggles.isEmpty else { return }
        isToggling = true
        let (mod, completion) = pendingToggles.removeFirst()
        pendingToggleFolder = mod.folderName
        performToggle(mod) {
            self.pendingToggleFolder = nil
            completion?()
            self.isToggling = false
            self.processNextToggleIfNeeded()
        }
    }

    private func performToggle(_ mod: ModItem, completion: (() -> Void)? = nil) {
        // Helper to find the top-level folder that contains a given uniqueId
        func getTopLevelFolder(for uniqueId: String) -> String? {
            for m in self.mods {
                if !m.isGroup && m.uniqueId.caseInsensitiveCompare(uniqueId) == .orderedSame {
                    return m.folderName
                } else if m.isGroup, let children = m.children {
                    if children.contains(where: { $0.uniqueId.caseInsensitiveCompare(uniqueId) == .orderedSame }) {
                        return m.folderName
                    }
                }
            }
            return nil
        }
        
        // Helper to get all dependencies of a top-level folder (including its children)
        func getDependencies(for folderName: String) -> [ModDependency] {
            guard let m = self.mods.first(where: { $0.folderName == folderName }) else { return [] }
            if m.isGroup, let children = m.children {
                return children.flatMap { $0.dependencies }
            } else {
                return m.dependencies
            }
        }
        
        // Everything below matches against TOP-LEVEL entries of `self.mods`,
        // so a mod that is a pack *child* has to be mapped to its owning
        // folder first. This matters because callers don't all pass top-level
        // items: the dependency tree resolves through `installedModsByUniqueId`,
        // which indexes children (a dependency usually lives inside a pack), so
        // its "Enable" button handed us a child whose folderName is
        // "Pack/Child". No top-level entry matches that, the apply loop hit
        // `continue`, and the button silently did nothing.
        let seedFolder: String = {
            // Already top-level (standalone mod or pack header) → unchanged.
            if self.mods.contains(where: { $0.folderName == mod.folderName }) {
                return mod.folderName
            }
            // Otherwise resolve the pack that owns this uniqueId — the same
            // mapping the dependency traversal below already relies on.
            return getTopLevelFolder(for: mod.uniqueId) ?? mod.folderName
        }()

        var foldersToToggle: Set<String> = [seedFolder]
        // Re-derive from the current snapshot rather than trusting
        // `mod.isEnabled` — `mod` was captured by value when this call was
        // enqueued (see `toggleMod`), so by the time a queued call actually
        // runs, `self.mods` may already reflect a state change from an
        // earlier queued toggle.
        let currentIsEnabled = self.mods.first(where: { $0.folderName == seedFolder })?.isEnabled ?? mod.isEnabled
        let targetState = !currentIsEnabled // True if we are enabling, false if disabling
        
        if chainToggleDependencies {
            if targetState == true {
                // Enabling: recursively enable all REQUIRED dependencies.
                // Traversal continues through dependencies that are already
                // enabled (tracked by `visited`, separate from
                // `foldersToToggle`) so that a disabled mod two levels down
                // an already-enabled chain still gets picked up.
                var queue = [seedFolder]
                var visited: Set<String> = [seedFolder]
                while !queue.isEmpty {
                    let currentFolder = queue.removeFirst()
                    let deps = getDependencies(for: currentFolder)

                    for dep in deps where dep.isRequired {
                        if let depFolder = getTopLevelFolder(for: dep.uniqueId), !visited.contains(depFolder) {
                            visited.insert(depFolder)
                            let isDepFolderEnabled = self.mods.first(where: { $0.folderName == depFolder })?.isEnabled ?? false
                            if !isDepFolderEnabled {
                                foldersToToggle.insert(depFolder)
                            }
                            queue.append(depFolder)
                        }
                    }
                }
            } else {
                // Disabling: recursively disable all enabled mods that REQUIRE this mod
                var queue = [seedFolder]
                while !queue.isEmpty {
                    let currentFolder = queue.removeFirst()
                    
                    var providedUniqueIds: [String] = []
                    if let m = self.mods.first(where: { $0.folderName == currentFolder }) {
                        if m.isGroup, let children = m.children {
                            providedUniqueIds = children.map { $0.uniqueId }
                        } else {
                            providedUniqueIds = [m.uniqueId]
                        }
                    }
                    
                    for otherMod in self.mods where otherMod.isEnabled && !foldersToToggle.contains(otherMod.folderName) {
                        let otherDeps = getDependencies(for: otherMod.folderName)
                        let requiresCurrent = otherDeps.contains { dep in
                            dep.isRequired && providedUniqueIds.contains { $0.caseInsensitiveCompare(dep.uniqueId) == .orderedSame }
                        }
                        if requiresCurrent {
                            foldersToToggle.insert(otherMod.folderName)
                            queue.append(otherMod.folderName)
                        }
                    }
                }
            }
        }
        // else: chainToggleDependencies == false → only toggle the single mod itself
        
        let fm = FileManager.default
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        var anyMoved = false

        for folderName in foldersToToggle {
            guard let m = self.mods.first(where: { $0.folderName == folderName }) else { continue }
            if m.isEnabled == targetState { continue }

            // Dot-prefix toggle: a rename WITHIN Mods/ flips enabled↔disabled.
            // `physicalFolderName` carries the current state's prefix; the
            // destination uses the opposite prefix. Both paths share the same
            // parent (Mods/), so the rename is atomic and O(1) — no folder
            // copy, no freeze on large mods.
            let srcPath = (modsPath as NSString).appendingPathComponent(m.physicalFolderName)
            let dstName = targetState ? m.folderName : "." + m.folderName
            let destPath = (modsPath as NSString).appendingPathComponent(dstName)

            // self.mods can be stale if another toggle's background scanMods()
            // (see the completion-driven dispatch below) hasn't landed yet.
            // Trust the filesystem over the cached isEnabled flag: if the
            // source is already gone, this mod was already renamed by a prior
            // call — skip instead of operating on a non-existent path.
            guard fm.fileExists(atPath: srcPath) else {
                log("Skipping toggle for \(m.name): source folder missing at \(srcPath) (likely already renamed by a concurrent toggle)", level: .warning)
                continue
            }

            do {
                // A pre-existing duplicate at destPath is set aside rather than
                // deleted outright, so a failed moveItem below can't leave the
                // mod lost from both locations. On a same-parent rename a
                // collision means a pre-existing `.X` (e.g. from a crashed
                // prior toggle) — keep the defensive set-aside + rollback.
                var staleDuplicateAside: String? = nil
                if fm.fileExists(atPath: destPath) {
                    let asidePath = destPath + ".stale_\(UUID().uuidString)"
                    try fm.moveItem(atPath: destPath, toPath: asidePath)
                    staleDuplicateAside = asidePath
                }

                do {
                    try fm.moveItem(atPath: srcPath, toPath: destPath)
                } catch {
                    if let asidePath = staleDuplicateAside {
                        do {
                            try fm.moveItem(atPath: asidePath, toPath: destPath)
                        } catch {
                            log("CRITICAL: toggle rollback failed — mod still in \(asidePath) (could not move back to \(destPath): \(error))", level: .error)
                        }
                    }
                    throw error
                }

                if let asidePath = staleDuplicateAside {
                    try? fm.removeItem(atPath: asidePath)
                }

                anyMoved = true
                if targetState {
                    self.modActivationTimestamps[folderName] = Date()
                }
            } catch {
                log("Failed to toggle \(m.name): \(error.localizedDescription)", level: .error)
            }
        }

        if anyMoved {
            if targetState {
                Self.saveModActivationTimestamps(self.modActivationTimestamps)
            }
            log("\(targetState ? L(L10n.Mods.enabled) : L(L10n.Mods.disabled)): \(mod.name)\(foldersToToggle.count > 1 ? " + Dependencies" : "")")
            // A toggle only renames Mods/X ↔ Mods/.X in place — every other
            // mod attribute (name, version, dependencies, …) is unchanged. So
            // instead of re-walking the whole Mods/ tree (O(total files), which
            // takes several seconds for large mod collections), flip the
            // affected mods' isEnabled in memory and rebuild the lightweight
            // dependency index. `physicalFolderName` is computed from
            // isEnabled, so it immediately reflects the renamed folder. The
            // next full scan (launch / refresh / install / delete) reconciles
            // against the disk. Done on the main thread: it's an O(toggled) map
            // over self.mods, cheaper than the UI refresh it triggers.
            let toggledFolders = foldersToToggle
            let target = targetState
            DispatchQueue.main.async {
                self.mods = self.mods.map { mod in
                    guard toggledFolders.contains(mod.folderName) else { return mod }
                    var m = mod
                    m.isEnabled = target
                    // A pack's children share their top-level folder's state.
                    if m.isGroup, var children = m.children {
                        for i in children.indices { children[i].isEnabled = target }
                        m.children = children
                    }
                    return m
                }
                self.rebuildDependencyIndexes()
                self.syncActiveProfileIds()
                completion?()
            }
        } else {
            completion?()
        }
    }
    
    /// Resolves a message key with an optional format detail — the
    /// counterpart to `SmapiInstaller`'s `(Bool, String, String?)`
    /// completion, since only this class (not `SmapiInstaller`) can
    /// translate.
    private func resolveSmapiMessage(_ key: String, _ detail: String?) -> String {
        guard let detail = detail else { return self.L(key) }
        return String(format: self.L(key), detail)
    }

    // Install SMAPI via Installer Helper
    func installSmapi() {
        smapiInstaller.install(gameDir: gameDir) { success, key, detail in
            self.checkSmapiVersion()
            let message = self.resolveSmapiMessage(key, detail)
            self.showModal(message: message)
            self.log(message)
        }
    }

    // Uninstall SMAPI
    func uninstallSmapi() {
        smapiInstaller.uninstall(gameDir: gameDir) { success, key, detail in
            self.checkSmapiVersion()
            let message = self.resolveSmapiMessage(key, detail)
            self.showModal(message: message)
            self.log(message)
        }
    }
    
    @Published var selectedMod: ModItem? = nil {
        didSet {
            if let mod = selectedMod, selectedModID != mod.folderName {
                selectedModID = mod.folderName
            }
        }
    }
    /// A mod the user asked to jump to (from a log line or the health card).
    ///
    /// Lives on the ViewModel rather than being handled by `ModListView`: tabs
    /// are built in an `if/else` chain, so when the request is made from the
    /// Logs tab `ModListView` doesn't exist yet and can't observe a
    /// notification. It reads and clears this on appear instead.
    @Published var pendingModFocus: String? = nil

    /// Cadrage de la liste des mods : recherche, filtres, tri, page courante.
    ///
    /// Ici et non en `@State` de `ModListView` pour la même raison que
    /// `pendingModFocus` : ouvrir une fiche mod *remplace* la liste (voir
    /// `MainView`), donc la vue est détruite et son état local avec. Tri,
    /// filtres et page repartaient à zéro dès qu'on ouvrait un mod.
    ///
    /// Objet observable à part, et **non** `@Published` ici : sinon chaque
    /// lettre tapée dans la recherche publierait à toute la fenêtre. Voir
    /// `ModListState`.
    let modList = ModListState()

    @Published var selectedModID: String? = nil {
        didSet {
            if let id = selectedModID, selectedMod?.folderName != id {
                selectedMod = mods.first { $0.folderName == id }
            }
        }
    }
    // Launch Stardew Valley (with selected profile)
    ///
    /// - Parameter honoringCloseAfterLaunch: whether the user's "quit StarHubFR
    ///   after launching" setting applies. Defaults to `true` — the Home button
    ///   behaves exactly as before. The guided search passes `false`: it starts
    ///   the game at *every* step and needs to still be running when the player
    ///   comes back to answer, otherwise the app would quit mid-search and leave
    ///   the mod list half-paused.
    func launchGame(honoringCloseAfterLaunch: Bool = true) {
        guard !gameDir.isEmpty else {
            showModal(message: L(L10n.Settings.gameDirNotSet))
            return
        }

        let profile = UserDefaults.standard.string(forKey: UDKey.launchProfile) ?? "SMAPI"
        let closeAfter = honoringCloseAfterLaunch
            && UserDefaults.standard.bool(forKey: UDKey.closeAfterLaunch)

        let originalPath = (gameDir as NSString).appendingPathComponent("StardewValley-original")
        
        if profile == "Vanilla" && FileManager.default.fileExists(atPath: originalPath) {
            log(L(L10n.VM.launchingVanilla))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [originalPath]
            process.currentDirectoryURL = URL(fileURLWithPath: gameDir)
            do {
                try process.run()
                log(L(L10n.VM.launchVanillaSuccess))
                if closeAfter { NSApplication.shared.terminate(nil) }
            } catch {
                log(String(format: L(L10n.VM.launchVanillaError), error.localizedDescription))
                showModal(message: L(L10n.VM.cannotStartVanilla))
            }
        } else {
            log(L(L10n.VM.launchingSmapi))
            // Route through Steam ONLY for an actual Steam install. NSWorkspace.open(steam://)
            // returns true whenever Steam is installed at all, so an unconditional attempt
            // hijacks direct/GOG launches (Steam opens, the game never starts). Detect a
            // Steam install by its path signature — matches detectDefaultGameDir() and holds
            // for custom Steam library folders too (they still contain `steamapps`).
            let isSteamInstall = gameDir.contains("steamapps")
            if isSteamInstall, let steamURL = URL(string: "steam://run/413150"),
               NSWorkspace.shared.open(steamURL) {
                log(L(L10n.VM.launchSteamSuccess))
                startSmapiLogWatcher()
                if closeAfter { NSApplication.shared.terminate(nil) }
                return
            }

            // Direct/GOG install: run SMAPI's launcher in place. SMAPI's installer replaced
            // `StardewValley` with its own launcher (vanilla backed up as
            // `StardewValley-original`), so invoking it starts SMAPI. Mirrors the
            // confirmed-working Vanilla branch above; using bash rather than
            // NSWorkspace.open(.app) also sidesteps the bundle code signature that SMAPI's
            // in-place replacement invalidates (which Gatekeeper can block).
            let smapiLauncher = (gameDir as NSString).appendingPathComponent("StardewValley")
            if FileManager.default.fileExists(atPath: smapiLauncher) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [smapiLauncher]
                process.currentDirectoryURL = URL(fileURLWithPath: gameDir)
                do {
                    try process.run()
                    log(L(L10n.VM.launchDirectSuccess))
                    startSmapiLogWatcher()
                    if closeAfter { NSApplication.shared.terminate(nil) }
                    return
                } catch {
                    log(String(format: L(L10n.VM.launchVanillaError), error.localizedDescription))
                }
            }

        // Last-resort fallback: open the app bundle via LaunchServices.
        let nsPath = gameDir as NSString
        var appPath = gameDir
        if nsPath.contains(".app") {
            var current = nsPath
            while current.length > 0 && !current.lastPathComponent.hasSuffix(".app") {
                current = current.deletingLastPathComponent as NSString
            }
            if current.length > 0 {
                appPath = current as String
            }
        }
        
        // Fallback: Open app directly
        let appURL = URL(fileURLWithPath: appPath)
            if NSWorkspace.shared.open(appURL) {
                log(L(L10n.VM.launchDirectSuccess))
                startSmapiLogWatcher()
                if closeAfter { NSApplication.shared.terminate(nil) }
            } else {
                log(L(L10n.VM.cannotStartDirect))
                showModal(message: L(L10n.VM.cannotStartGame))
            }
        }
    }
    
    /// Shared formatter (DateFormatter allocation is expensive when logging frequently).
    private static let logTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func appendLogEntry(_ entry: LogEntry) {
        logEntries.append(entry)
        // Cap memory usage: drop oldest entries when over the limit.
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
    }

    func log(_ message: String, level: LogLevel = .info) {
        let timestamp = Self.logTimeFormatter.string(from: Date())
        let entry = LogEntry(timestamp: timestamp, message: message, level: level, source: .app)

        if Thread.isMainThread {
            appendLogEntry(entry)
        } else {
            DispatchQueue.main.async {
                self.appendLogEntry(entry)
            }
        }
    }

    // MARK: - SMAPI Real-time Log Reader

    // MARK: - SMAPI Log Reader

    /// Load SMAPI-latest.txt once when Logs tab is opened.
    /// No live polling — SMAPI doesn't flush continuously anyway.
    /// Reading + line-by-line parsing of the SMAPI log runs off the main
    /// thread — the file can be large, and this used to block the UI on
    /// every call (refresh button, watcher start).
    /// Recharge le journal SMAPI. `completion` s'exécute sur le thread principal
    /// **après** publication des diagnostics : sans elle, un appelant qui lit
    /// `smapiDiagnostics` juste après jugerait encore sur la session précédente.
    func loadSmapiLog(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.parseAndAppendSmapiLog(completion: completion)
        }
    }

    private func parseAndAppendSmapiLog(completion: (() -> Void)? = nil) {
        let path = smapiLogPath
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return }

        let (smapiDiag, smapiDate, smapiStale) = computeSmapiDiagnostics(logContent: text, atPath: path)

        let entries = SmapiLogParser.parse(text)

        // Trim to the memory cap by dropping TRACE noise, not by cutting the
        // head of the file.
        //
        // A real log is ~90 % TRACE and can run past 4000 lines, while SMAPI
        // writes its whole diagnostic (skipped mods, save-serializer warnings,
        // failed integrations) at *startup* — i.e. at the top. Keeping the last
        // N lines therefore threw away exactly the lines that matter: they
        // stayed in the diagnostics card (which parses the full file) but
        // vanished from the log list, so the two disagreed.
        let trimmedEntries = Self.trimPreservingSignal(entries, cap: maxLogEntries)

        DispatchQueue.main.async {
            // Reload semantics: SMAPI-latest.txt is a single snapshot file, so
            // each load replaces the previously-loaded SMAPI entries instead of
            // stacking another full copy. Without this, every game launch
            // (startSmapiLogWatcher) and every tab open appended the whole log
            // again, producing N duplicate copies after N launches.
            self.logEntries.removeAll { $0.source == .smapi }
            // Budget the SMAPI block to whatever room is left after the app
            // entries, instead of trimming the *combined* array from the front.
            // The front holds the StarHubFR (app) entries, so a front-trim wiped
            // the whole app log whenever the SMAPI log was large (~2000 lines).
            let appCount = self.logEntries.count
            let smapiBudget = max(0, self.maxLogEntries - appCount)
            // Same rule as above: shed TRACE noise, never the startup
            // diagnostic at the head of the log.
            let cappedSmapi = Self.trimPreservingSignal(trimmedEntries, cap: smapiBudget)
            self.logEntries.append(contentsOf: cappedSmapi)
            self.smapiDiagnostics = smapiDiag
            self.smapiLogDate = smapiDate
            self.smapiLogStale = smapiStale
            // Fold this log into the per-version error history. Uses `entries`
            // (the full parse), not the capped list: the display cap must not
            // cost us recorded errors.
            self.recordErrorHistory(from: entries, logDate: smapiDate)
            completion?()
        }
    }

    // MARK: - Per-mod error history

    /// Per-mod, per-version error history (see `ModErrorHistory`). Loaded once,
    /// then kept in memory; the mod detail view reads it.
    @Published var modErrorHistory = ModErrorHistory()
    /// Log timestamp of the last fold, so the same log is never counted twice.
    private var lastErrorHistoryLogDate: Date?
    private var errorHistoryLoaded = false

    /// Folds a parsed SMAPI log into the error history and persists it.
    ///
    /// Skips logs already folded in: the same file is re-read on every tab open
    /// and refresh, which would otherwise inflate every count. A log with no
    /// date is skipped too — without one we can't tell repeats apart.
    private func recordErrorHistory(from entries: [LogEntry], logDate: Date?) {
        if !errorHistoryLoaded {
            let loaded = ModErrorHistoryStore.load()
            modErrorHistory = loaded.history
            lastErrorHistoryLogDate = loaded.lastLogDate
            errorHistoryLoaded = true
        }

        guard let logDate else { return }
        if let last = lastErrorHistoryLogDate, logDate <= last { return }

        let observations: [ModErrorHistory.Observation] = entries.compactMap { entry in
            guard entry.level == .error || entry.level == .warning,
                  let modName = entry.modName,
                  let mod = resolveModFolder(forLoggedName: modName) else { return nil }
            return .init(mod: mod.folderName,
                         version: mod.version,
                         message: entry.message,
                         isError: entry.level == .error)
        }
        guard !observations.isEmpty else {
            lastErrorHistoryLogDate = logDate
            ModErrorHistoryStore.save(modErrorHistory, lastLogDate: logDate)
            return
        }

        modErrorHistory.merge(observations, at: logDate)
        lastErrorHistoryLogDate = logDate
        ModErrorHistoryStore.save(modErrorHistory, lastLogDate: logDate)
    }

    /// Maps a name as SMAPI logged it to an installed mod. SMAPI logs the
    /// manifest's display name, which usually matches but isn't guaranteed to,
    /// hence the tolerant containment match used elsewhere for mod jumps.
    /// Relie le nom qu'un mod porte dans le journal au `ModItem` installé.
    /// Non privé : la recherche guidée croise les erreurs relevées avec les
    /// dossiers actifs, ce qui exige la même correspondance.
    func resolveModFolder(forLoggedName name: String) -> ModItem? {
        let all = mods.flattenedMods
        // Égalité exacte (insensible à la casse) d'abord — SMAPI journalise le
        // `Name` du manifeste, donc le cas courant se résout sans ambiguïté.
        if let exact = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return exact
        }
        // Repli tolérant : SMAPI peut tronquer ou orner le nom. Parmi ceux qui
        // le contiennent, le nom le plus court est le plus spécifique — un nom
        // long qui le contient (ex. « Farm » vs « FarmExpansion ») est
        // probablement un autre mod, que le premier-venu renvoyait à tort.
        let containing = all.filter { $0.name.localizedCaseInsensitiveContains(name) }
        return containing.min(by: { $0.name.count < $1.name.count })
    }

    /// Applies the memory cap to parsed SMAPI entries, dropping TRACE noise
    /// rather than the head of the log (see `LogNoise.trimIndices`).
    static func trimPreservingSignal(_ entries: [LogEntry], cap: Int) -> [LogEntry] {
        guard entries.count > cap else { return entries }
        let keep = LogNoise.trimIndices(
            count: entries.count,
            cap: cap,
            isNoise: { entries[$0].level == .trace }
        )
        return keep.map { entries[$0] }
    }

    /// Chemin du journal SMAPI. Non privé : la recherche guidée surveille sa
    /// date de modification pour rafraîchir l'affichage pendant une partie.
    var smapiLogPath: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return (homeDir as NSString).appendingPathComponent(
            ".config/StardewValley/ErrorLogs/SMAPI-latest.txt"
        )
    }

    /// Parses structured diagnostics + staleness from SMAPI-log content that was
    /// already read by the caller (no second file read). Safe off-main:
    /// `SmapiDiagnostics.parse` is pure and the mtime lookup is a single stat.
    /// Reused by both `parseSMAPILog` (scan/refresh) and `parseAndAppendSmapiLog`
    /// (reload button) so the health card refreshes on either path.
    private func computeSmapiDiagnostics(logContent: String, atPath path: String) -> (SmapiDiagnostics, Date?, Bool) {
        let diag = SmapiDiagnostics.parse(logContent: logContent)
        let mtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
        let stale = (mtime ?? .distantFuture) < sessionStart
        return (diag, mtime, stale)
    }

    /// Reveals SMAPI-latest.txt in a Finder window (U6 "Open in Finder").
    func revealSmapiLogInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: smapiLogPath)])
    }

    func startSmapiLogWatcher() { loadSmapiLog() }

    /// Retained for `LogsView.onDisappear`. SMAPI logs are loaded on demand via
    /// `loadSmapiLog()` (no live polling / file handle to tear down).
    func stopSmapiLogWatcher() {}

    // MARK: - Nexus Mods update checking

    /// Persists a Nexus Mods API key to Keychain and refreshes `hasNexusApiKey`.
    func setNexusApiKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Ne déclarer la clé configurée que si la Keychain l'a acceptée : sinon
        // l'UI affichait « configurée » et le prochain check partait en .noApiKey
        // (Keychain locked, quota, sandbox).
        if NexusUpdateChecker.shared.setApiKey(trimmed) {
            hasNexusApiKey = true
        }
    }

    /// Removes the stored Nexus Mods API key.
    func clearNexusApiKey() {
        NexusUpdateChecker.shared.clearApiKey()
        hasNexusApiKey = false
        // Les mises à jour restent : elles ne doivent rien à la clé, qui ne
        // sert plus qu'au téléchargement intégré et aux fiches.
        nexusCategories = [:]
        nexusModExtras = [:]
        nexusCheckError = nil
    }

    /// Demande à smapi.io, en un appel groupé, s'il existe plus récent.
    ///
    /// L'app ne compare plus de numéros : smapi.io le fait, en tenant compte
    /// des `UpdateKeys` du mod (Nexus, GitHub, CurseForge, ModDrop) et en
    /// jugeant chaque composant d'un pack sur *sa* version. Ce que l'app
    /// fournit, c'est la version qu'elle **affirme** installée — d'ancre s'il
    /// y en a une, de manifest sinon.
    func checkNexusUpdates() {
        guard !isCheckingNexusUpdates else { return }
        isCheckingNexusUpdates = true
        nexusCheckError = nil
        nexusCheckProgress = nil
        log("Vérification des mises à jour démarrée", level: .info)

        let anchors = anchorStore.all()
        let candidates = allInstalledMods().map { mod in
            SmapiUpdateRequest.Candidate(
                uniqueId: mod.uniqueId,
                manifestVersion: mod.version,
                updateKeys: mod.updateKeys,
                isPaused: !mod.isEnabled,
                manualNexusId: nexusCustomModIds[mod.folderName])
        }
        let entries = SmapiUpdateRequest.entries(from: candidates, anchors: anchors)

        SmapiUpdateClient.shared.fetch(
            entries: entries,
            // Passe par `sanitizedGameVersion` : la version vient d'une regex
            // sur le journal SMAPI, et une valeur qui ne s'analyse pas fait
            // rendre une liste vide à smapi.io — le lot entier disparaîtrait
            // sans erreur.
            gameVersion: SmapiUpdateRequest.sanitizedGameVersion(smapiDiagnostics?.gameVersion),
            progress: { [weak self] done, total in
                self?.nexusCheckProgress = (done, total)
            },
            completion: { [weak self] result in
                guard let self else { return }
                self.isCheckingNexusUpdates = false
                self.nexusCheckProgress = nil
                switch result {
                case .success(let mods):
                    self.applySmapiResults(mods, entries: entries)
                case .failure(let failure):
                    // On ne vide pas la liste : une panne réseau n'est pas une
                    // preuve que les mises à jour connues ont disparu.
                    //
                    // `"rate_limited"` est le seul code que `MainView` traduit
                    // en message dédié (les autres tombent sur le message
                    // générique) : un 429 mérite ce traitement particulier,
                    // les autres échecs gardent leur description brute.
                    if case .http(429) = failure {
                        self.nexusCheckError = "rate_limited"
                    } else {
                        self.nexusCheckError = "\(failure)"
                    }
                    self.log("Vérification des mises à jour en échec : \(failure)", level: .warning)
                }
            })
    }

    /// Transforme les verdicts de smapi.io en lignes affichables, et retient
    /// les motifs de non-vérifiabilité.
    private func applySmapiResults(_ mods: [SmapiUpdateResponse.Mod],
                                   entries: [SmapiUpdateRequest.Entry]) {
        let assertedVersion = Dictionary(entries.map { ($0.id, $0.installedVersion) },
                                         uniquingKeysWith: { first, _ in first })
        // Les `UpdateKeys` telles qu'envoyées — donc y compris la clé
        // synthétique construite depuis un identifiant saisi à la main. C'est
        // le repli quand smapi.io ne connaît pas le mod ; voir
        // `ModManifest.resolveNexusId`.
        let declaredKeys = Dictionary(entries.map { ($0.id, $0.updateKeys) },
                                      uniquingKeysWith: { first, _ in first })
        // Le nom que le mod déclare, celui que la liste des mods affiche : un
        // même mod ne doit pas changer de nom d'un écran à l'autre.
        let installedName = Dictionary(
            allInstalledMods().filter { !$0.uniqueId.isEmpty }.map { ($0.uniqueId, $0.name) },
            uniquingKeysWith: { first, _ in first })
        var updates: [NexusUpdateChecker.ModUpdate] = []
        var blockers: [String: SmapiUpdateResponse.Blocker] = [:]

        for mod in mods {
            if let first = mod.errors.first {
                blockers[mod.id] = SmapiUpdateResponse.blocker(for: first)
            }
            guard let suggested = mod.suggestedUpdate else { continue }
            updates.append(NexusUpdateChecker.ModUpdate(
                uniqueId: mod.id,
                name: ModManifest.resolveDisplayName(installedName: installedName[mod.id],
                                                     metadataName: mod.metadata?.name,
                                                     uniqueId: mod.id),
                installedVersion: assertedVersion[mod.id] ?? "",
                latestVersion: suggested.version,
                // `?? mod.id` reste la sentinelle : un mod suivi seulement par
                // GitHub ou CurseForge n'a pas de page Nexus, et sa ligne doit
                // légitimement rester sans bouton de téléchargement.
                nexusModId: ModManifest.resolveNexusId(
                    metadataNexusID: mod.metadata?.nexusID,
                    updateKeys: declaredKeys[mod.id]) ?? mod.id,
                url: suggested.url ?? "",
                uploadedTime: nil))
        }

        // Un mod ABSENT de la réponse n'a pas de verdict — il n'est pas « à
        // jour ». Le client rend ce qui a abouti même quand un lot échoue :
        // sur 7 lots, un 503 au quatrième laisse ~510 mods sans réponse.
        // Les traiter comme confirmés serait le défaut d'origine sous une
        // autre forme. On conserve donc leur ligne précédente.
        //
        // `ModUpdate.id` est désormais l'`UniqueID`, tout comme `Mod.id` de la
        // réponse et `Entry.id` de la requête : une seule forme d'identité de
        // bout en bout, plus de correspondance croisée à tenir.
        let answered = Set(mods.map(\.id))

        // …mais une ligne n'est conservée que si son mod est **encore
        // installé**. `NexusUpdateMerge` purgeait les mods disparus ; c'est la
        // seule de ses quatre règles à n'avoir pas eu de remplaçant, et sans
        // elle une ligne de mod désinstallé n'est jamais « répondue », donc
        // conservée à vie. `entries` décrit exactement le parc envoyé.
        let stillInstalled = Set(entries.map(\.id))
        // Les lignes précédentes viennent du **cache**, pas de `nexusUpdates`.
        // La liste affichée est consolidée par pack : une ligne de pack porte
        // le nom du pack et l'`UniqueID` d'un seul de ses composants. Fusionner
        // à partir d'elle, puis persister le résultat, écrivait cette ligne
        // hybride dans le cache — un pack y prenait la place de ses enfants.
        // Le cache est la vérité, à plat ; l'affichage n'en est qu'une vue.
        let previousRows = NexusUpdateChecker.shared.cachedUpdates()
        let unanswered = previousRows.filter {
            !answered.contains($0.id) && stillInstalled.contains($0.id)
        }
        let dropped = previousRows.filter {
            !answered.contains($0.id) && !stillInstalled.contains($0.id)
        }.count

        let merged = (updates + unanswered)
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        unverifiableMods = blockers

        // Persister, sinon tout ceci meurt à la fermeture et le lancement
        // suivant réaffiche `cachedUpdates()` — la liste écrite par le code que
        // cette branche remplace.
        NexusUpdateChecker.shared.replaceCachedUpdates(merged)
        // Puis republier depuis ce cache : une vérification manuelle affiche
        // désormais la même chose qu'un redémarrage. Le regroupement par pack
        // ne s'appliquait qu'au chargement, si bien que le même parc donnait
        // deux décomptes selon le chemin emprunté.
        republishUpdatesFromCache()

        let missing = entries.count - mods.count
        if missing > 0 {
            log("Vérification incomplète : \(mods.count) mods sur \(entries.count) ont répondu ; "
                + "\(unanswered.count) lignes conservées faute de verdict",
                level: .warning)
        }
        if dropped > 0 {
            log("\(dropped) lignes retirées : leur mod n'est plus installé", level: .info)
        }
        log("Mises à jour : \(updates.count) sur \(mods.count) mods interrogés, \(blockers.count) non vérifiables",
            level: .info)
    }

    /// « Je l'ai déjà » : l'utilisateur affirme avoir la version suggérée.
    ///
    /// C'est la seule échappatoire quand l'auteur a oublié d'incrémenter le
    /// champ `Version` de son manifest : smapi.io compare des chaînes, voit un
    /// retard qui n'existe pas, et le redira à chaque passe. L'ancre
    /// `.userAffirmed` fige la version envoyée et éteint la ligne pour de bon.
    func affirmInstalled(uniqueId: String, version: String) {
        anchorStore.put(ModVersionAnchorRules.afterUserAffirmation(
            uniqueId: uniqueId, version: version, now: Date()))
        // `$0.id` — c'est-à-dire l'`UniqueID`. Le prédicat comparait `name`,
        // un nom d'affichage, et `nexusModId`, une identité partagée : il ne
        // retirait donc jamais la bonne ligne, quand il en retirait une.
        // Le cache d'abord — sans persistance, le lancement suivant réaffiche
        // `cachedUpdates()` et la ligne revient : l'affirmation ne survivait
        // pas à la fermeture. L'affichage se recalcule ensuite depuis lui.
        NexusUpdateChecker.shared.dismissUpdate(uniqueId: uniqueId)
        republishUpdatesFromCache()
    }

    /// Pose une ancre `.install` pour chaque mod que l'installation vient de
    /// poser. C'est le seul moment où l'app sait avec certitude ce qui est sur
    /// le disque.
    ///
    /// - Returns: les `UniqueID` **constatés sur disque** — ceux dont le
    ///   manifest a pu être lu. Pas « ceux qui ont reçu une ancre » : c'est le
    ///   constat qui autorise à éteindre une ligne, pas le verdict de la règle
    ///   d'ancrage, qui peut légitimement s'abstenir. L'appelant s'en sert pour
    ///   n'éteindre que les lignes des mods qu'il vient de poser — une lecture
    ///   de manifest, une seule source d'identité.
    @discardableResult
    func anchorInstalledMods(installedFolderPaths: [String]) -> [String] {
        let now = Date()
        var anchored: [String] = []
        for path in installedFolderPaths {
            let manifestPath = (path as NSString).appendingPathComponent("manifest.json")
            // `FileManager.contents` + `String(data:encoding:)` plutôt que
            // `try? String(contentsOfFile:)` : même échec silencieux sur un
            // fichier illisible, sans ajouter de `try?` au cliquet des
            // conventions (§7.1 — déjà à sa base sur ce dépôt).
            guard let data = FileManager.default.contents(atPath: manifestPath),
                  let raw = String(data: data, encoding: .utf8),
                  let manifest = ManifestJSON.decode(raw),
                  let uniqueId = manifest.caseInsensitiveValue(forKey: "UniqueID") as? String,
                  !uniqueId.isEmpty,
                  // `ManifestVersionReader` et non `as? String` : SMAPI accepte
                  // aussi la forme objet, et l'abandon silencieux sur cette
                  // forme privait d'ancre le seul chemin où l'app sait avec
                  // certitude ce qu'elle vient d'écrire.
                  let version = ManifestVersionReader.version(from: manifest)
            else { continue }
            // `facts: nil` — le lot A ne va pas chercher `files.json`, donc il
            // ne connaît ni le `file_id` posé ni sa date de mise en ligne.
            // Inventer ces valeurs ferait déclencher à tort la règle de
            // re-publication du lot C sur toute page mise à jour après
            // l'installation. La spec §5.4 le dit : « ailleurs, on ne peut
            // rien dire, et on ne dit rien. »
            if let anchor = ModVersionAnchorRules.afterInstall(
                existing: anchorStore.anchor(for: uniqueId),
                uniqueId: uniqueId,
                installedVersion: version,
                facts: nil,
                isReferenceFile: true,
                now: now) {
                anchorStore.put(anchor)
            }
            anchored.append(uniqueId)
        }
        return anchored
    }

    /// **L'invariant de la liste des mises à jour** : ce qui est affiché est,
    /// toujours, la consolidation par pack de ce que porte le cache.
    ///
    /// Le cache est plat — une ligne par `UniqueID` — parce que c'est la forme
    /// dans laquelle les verdicts arrivent, celle qu'un retrait cible, et celle
    /// que la fusion sait comparer. Le regroupement par pack est une vue, et
    /// rien d'autre : il n'est jamais écrit.
    ///
    /// Passer par ici plutôt que d'écrire `nexusUpdates` à la main, sans quoi
    /// les chemins divergent — ce qu'ils faisaient : seul le chargement
    /// consolidait, et le même parc donnait deux décomptes selon qu'on venait
    /// de redémarrer ou de cliquer « Vérifier ».
    ///
    /// À appeler sur le fil principal (`nexusUpdates` est `@Published`), et
    /// après le scan : la table des packs se lit dans `mods`.
    private func republishUpdatesFromCache() {
        nexusUpdates = consolidateUpdatesByPack(NexusUpdateChecker.shared.cachedUpdates())
    }

    /// Consolidates the flat Nexus update list so each pack (mod group)
    /// appears as a single row instead of one row per child.
    ///
    /// For a pack with multiple children that have updates, the winning row is
    /// the child whose `latestVersion` is the highest (dotted-numeric
    /// comparison via `NexusUpdateChecker.compare`); when several children
    /// share that same highest version, the most recent Nexus `uploadedTime`
    /// wins. The consolidated row reuses the winning child's version/url/date
    /// but shows the pack's display name so the user sees the pack as a whole.
    ///
    /// Standalone mods (not part of a group) are returned unchanged. Mods whose
    /// effective Nexus id isn't found in the installed set are also passed
    /// through (defensive — shouldn't normally happen).
    /// Regroupe les mises à jour par pack avant affichage.
    ///
    /// Ne garde ici que ce qui dépend du ViewModel : la table « identifiant
    /// Nexus effectif → nom du pack parent ». Le regroupement, le choix du
    /// composant représentatif et le tri vivent dans `NexusUpdateConsolidation`
    /// (module testable).
    private func consolidateUpdatesByPack(_ updates: [NexusUpdateChecker.ModUpdate]) -> [NexusUpdateChecker.ModUpdate] {
        var parentPackName: [String: String] = [:]
        for mod in mods where mod.isGroup {
            for child in mod.children ?? [] {
                let id = effectiveNexusModId(for: child)
                if !id.isEmpty { parentPackName[id] = mod.name }
            }
        }
        return NexusUpdateConsolidation.consolidate(updates, parentPackName: parentPackName)
    }

    /// Formats a Nexus upload timestamp for display next to the latest version
    /// in the update window. Uses the user's locale so it reads naturally.
    func formatUploadedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return String(format: L(L10n.Updates.uploadedOn), formatter.string(from: date))
    }

    /// Returns the effective category for a mod.
    ///
    /// Precedence (first wins):
    /// 1. User-assigned override keyed by `mod.folderName` — lets the user
    ///    categorize mods that the API never returned a `category_id` for.
    ///    Also works for pack headers (whose `folderName` is the group name).
    /// 2. Category fetched from the Nexus API, keyed by `mod.nexusModId`.
    /// 3. For pack headers: the dominant category among the children.
    /// 4. `nil` — unknown.
    func category(for mod: ModItem) -> NexusCategory? {
        if let cached = categoryCache[mod.folderName] {
            return cached
        }
        let result = computeCategory(for: mod)
        categoryCache[mod.folderName] = result
        return result
    }

    /// Stable inferred type key for a mod. For a group, uses the primary
    /// (first) child — mirrors upstream's "group shows its primary child's tag".
    func inferredTagKey(for mod: ModItem) -> String {
        let target = (mod.isGroup ? (mod.children?.first ?? mod) : mod)
        return ModItem.inferTag(name: target.name, uniqueId: target.uniqueId, description: target.description)
    }

    private func computeCategory(for mod: ModItem) -> NexusCategory? {
        if let cid = nexusCustomCategories[mod.folderName],
           let cat = NexusCategory.from(id: cid) {
            return cat
        }
        // Use the effective id (custom override OR manifest) so categories
        // fetched via the per-mod editor apply to mods with no manifest id.
        let effectiveId = effectiveNexusModId(for: mod)
        if !effectiveId.isEmpty,
           let cid = nexusCategories[effectiveId],
           let cat = NexusCategory.from(id: cid) {
            return cat
        }
        // Pack header: fall back to the most common child category.
        if mod.isGroup, let children = mod.children {
            return dominantCategory(among: children)
        }
        return nil
    }

    /// Most frequent non-nil category among a set of (child) mods. Ties resolve
    /// to the lower category id for stable output. Returns `nil` when no child
    /// has a known category.
    private func dominantCategory(among children: [ModItem]) -> NexusCategory? {
        var counts: [Int: Int] = [:]
        for c in children {
            if let cat = category(for: c) {
                counts[cat.id, default: 0] += 1
            }
        }
        guard let dominantId = counts.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        })?.key else { return nil }
        return NexusCategory.from(id: dominantId)
    }

    /// The category id the user manually pinned on this mod, or `nil` when the
    /// mod relies on the automatic (API-fetched) category.
    func customCategoryId(for mod: ModItem) -> Int? {
        nexusCustomCategories[mod.folderName]
    }

    /// Pins a category on a mod. Pass `nil` to revert to the automatic category.
    func setCustomCategory(for mod: ModItem, categoryId: Int?) {
        if let cid = categoryId {
            nexusCustomCategories[mod.folderName] = cid
        } else {
            nexusCustomCategories.removeValue(forKey: mod.folderName)
        }
        Self.saveCustomCategories(nexusCustomCategories)
    }

    /// The effective Nexus mod id for a mod: user override first, then the id
    /// declared in the mod's manifest `UpdateKeys`. Empty when neither is set.
    func effectiveNexusModId(for mod: ModItem) -> String {
        if let custom = nexusCustomModIds[mod.folderName], !custom.isEmpty {
            return custom
        }
        return mod.nexusModId
    }

    /// Like `effectiveNexusModId(for:)`, but for a pack header with no own id
    /// falls back to the first child that has one — mirroring `nexusLink(for:)`
    /// and `modExtra(for:)`. The detail pane fetches against this id so a pack
    /// shows the same mod its header links to, instead of no Nexus content.
    func resolvedNexusModId(for mod: ModItem) -> String {
        let id = effectiveNexusModId(for: mod)
        if !id.isEmpty { return id }
        if mod.isGroup, let children = mod.children {
            for c in children {
                let cid = resolvedNexusModId(for: c)
                if !cid.isEmpty { return cid }
            }
        }
        return ""
    }

    /// The Nexus Mods URL for a mod derived from its effective mod id, or the
    /// manifest's `nexusUrl` when no effective id is available (they normally
    /// agree, but the manifest URL is the original source of truth). For pack
    /// headers with no own link, falls back to the first child that has one.
    /// Empty when neither the mod nor any child has a Nexus link.
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
        if !id.isEmpty, let extra = nexusModExtras[id], !extra.summary.isEmpty || !extra.pictureUrl.isEmpty {
            return extra
        }
        if mod.isGroup, let children = mod.children {
            for c in children {
                if let extra = modExtra(for: c) { return extra }
            }
        }
        return nil
    }

    /// Finds the installed mod corresponding to a Nexus update. Searches both
    /// standalone mods and pack children. Returns `nil` for orphaned updates
    /// (e.g. the mod was removed after the check ran).
    ///
    /// `update.nexusModId` porte l'identifiant Nexus quand smapi.io le connaît,
    /// l'`UniqueID` du mod sinon (voir `applySmapiResults`) — un mod publié sur
    /// GitHub, ou simplement absent de la base de smapi.io, n'a aucun
    /// identifiant Nexus du tout. Ne comparer qu'à `effectiveNexusModId(for:)`
    /// laisserait ces mods sans correspondance, avec pour effet un badge
    /// Activé/Désactivé faux sur leur ligne. D'où les deux passes ci-dessous
    /// plutôt qu'un unique prédicat combiné : un `UniqueID` pourrait en
    /// principe coïncider avec l'identifiant Nexus d'un AUTRE mod, et la
    /// correspondance par identifiant Nexus — celle que smapi.io a réellement
    /// vérifiée — doit l'emporter chaque fois qu'elle s'applique.
    func modForNexusUpdate(_ update: NexusUpdateChecker.ModUpdate) -> ModItem? {
        guard !update.nexusModId.isEmpty else { return nil }

        func find(_ matches: (ModItem) -> Bool) -> ModItem? {
            for mod in mods {
                if matches(mod) { return mod }
                if mod.isGroup, let children = mod.children,
                   let child = children.first(where: matches) {
                    return child
                }
            }
            return nil
        }

        if let byNexusId = find({ !effectiveNexusModId(for: $0).isEmpty
                                    && effectiveNexusModId(for: $0) == update.nexusModId }) {
            return byNexusId
        }
        return find({ $0.uniqueId == update.nexusModId })
    }

    /// Display author for a mod. For pack headers, aggregates the children:
    /// if every child shares the same author it is shown verbatim, otherwise a
    /// localized "multiple authors" placeholder is returned.
    func displayAuthor(for mod: ModItem) -> String {
        if mod.isGroup, let children = mod.children {
            let authors = Set(children.map { $0.author }
                                .filter { !$0.isEmpty && $0 != "Unknown" })
            if authors.count == 1 { return authors.first! }
            if authors.isEmpty { return "—" }
            return L(L10n.Mods.packMultipleAuthors)
        }
        return mod.author
    }

    /// Display version for a mod. For pack headers, shows the shared version
    /// when every child agrees, otherwise "—" (mixed versions are common in
    /// packs and a single number would be misleading).
    func displayVersion(for mod: ModItem) -> String {
        if mod.isGroup, let children = mod.children {
            // A pack is a single Nexus mod (its children are the installed
            // sub-mods). Prefer the pack's latest **Nexus** version — the Main
            // file / changelog version — once a Nexus check (or the per-mod
            // fetch) has retrieved it, since the children's own manifest
            // versions can differ or lag behind the pack release.
            if let v = nexusLatestVersion(for: mod), !v.isEmpty { return v }
            let versions = Set(children.map { $0.version }
                                .filter { !$0.isEmpty && $0 != "Unknown" })
            if versions.count == 1 { return versions.first! }
            return "—"
        }
        return mod.version
    }

    /// The latest Nexus version cached for a mod (or, for a pack, its resolved
    /// Nexus mod id), from the last update check / per-mod fetch. `nil` until a
    /// check has populated it, or when the mod has no resolvable Nexus id.
    func nexusLatestVersion(for mod: ModItem) -> String? {
        let id = resolvedNexusModId(for: mod)
        guard !id.isEmpty else { return nil }
        return nexusModExtras[id]?.version
    }

    /// When the mod was last updated on Nexus (from the last check / fetch), or
    /// nil until one has run / when there's no resolvable Nexus id.
    func nexusLastUpdated(for mod: ModItem) -> Date? {
        let id = resolvedNexusModId(for: mod)
        guard !id.isEmpty else { return nil }
        return nexusModExtras[id]?.uploadedTime
    }

    /// The mod's install date (its `manifest.json` mtime). For a pack, the most
    /// recent child's date (packs have no manifest of their own).
    func installedDate(for mod: ModItem) -> Date? {
        if mod.isGroup, let children = mod.children {
            return children.compactMap { $0.installedFileDate }.max()
        }
        return mod.installedFileDate
    }

    /// Sets a user-defined Nexus mod id for a mod (generates its link and lets
    /// it participate in update checks). Pass `nil`/empty to clear the override
    /// and fall back to the manifest-declared id.
    func setCustomNexusModId(for mod: ModItem, modId: String?) {
        let trimmed = (modId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            nexusCustomModIds.removeValue(forKey: mod.folderName)
        } else {
            nexusCustomModIds[mod.folderName] = trimmed
        }
        Self.saveCustomModIds(nexusCustomModIds)
    }

    /// Retient l'identifiant Nexus d'une installation venue de Nexus, quand le
    /// manifeste installé n'en déclare aucun.
    ///
    /// Sans ça, l'app connaissait l'identifiant (elle venait de télécharger
    /// depuis cette page) et le jetait : un mod dont l'auteur a oublié
    /// `UpdateKeys` n'était plus jamais interrogé, sans le moindre signal. Sur
    /// un parc de 966 mods, 111 étaient dans ce cas.
    ///
    /// Doit être appelé **avant** `reconcileManifestVersion`, qui consomme
    /// `pendingNexusSource`. La décision elle-même vit dans
    /// `NexusInstallIdRecording` (Core, testée).
    ///
    /// v1 : installations d'un seul mod. Un pack livre plusieurs dossiers pour
    /// une seule page Nexus — les relier tous au même identifiant ferait de
    /// chaque composant un faux candidat, avec sa propre version.
    func recordNexusModId(_ modId: Int, installedFolderPaths: [String]) {
        guard installedFolderPaths.count == 1,
              let folderPath = installedFolderPaths.first else { return }

        // Le dossier vient d'être installé, donc actif ; on retire quand même
        // un point de tête pour indexer sur le nom *logique*, celui que la
        // vérification utilise (un mod en pause est un dossier préfixé).
        let leaf = (folderPath as NSString).lastPathComponent
        let folderName = leaf.hasPrefix(".") ? String(leaf.dropFirst()) : leaf

        let manifestPath = (folderPath as NSString).appendingPathComponent("manifest.json")
        let updateKeys = (try? String(contentsOfFile: manifestPath, encoding: .utf8))
            .flatMap { ManifestJSON.decode($0) }
            .flatMap { $0.caseInsensitiveValue(forKey: "UpdateKeys") as? [String] }

        guard let id = NexusInstallIdRecording.idToRecord(
            downloadedModId: modId,
            manifestUpdateKeys: updateKeys,
            existingOverride: nexusCustomModIds[folderName]
        ) else { return }

        nexusCustomModIds[folderName] = id
        Self.saveCustomModIds(nexusCustomModIds)
        log(String(format: L(L10n.VM.nexusIdLearned), folderName, id))
    }

    /// Fetches a single mod's metadata (category + latest version + summary/
    /// picture) from Nexus and applies it to the published `nexusCategories`
    /// / `nexusModExtras` maps so the mods-list badge and popover preview
    /// update instantly. Intended for on-demand
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
                // `extra` already carries the latest version + upload date.
                self.nexusModExtras[modId] = extra
            }
            completion(result)
        }
    }

    /// Refuse un second téléchargement tant qu'un premier tourne, ou que son
    /// archive attend encore dans la feuille d'installation.
    ///
    /// Sans ce garde-fou, un second lien `nxm://` — livré par AppKit, donc
    /// insensible à la feuille ouverte — écrasait `pendingDownloadedZip` : la
    /// première archive restait dans le dossier temporaire sans que personne
    /// n'en connaisse plus le chemin. Supprimer l'ancienne à la place n'est pas
    /// une option : la feuille ouverte est peut-être en train d'en extraire.
    ///
    /// Aucun des deux verrous ne peut rester fermé pour la session — ce qui
    /// couperait le lien `nxm://`, seule voie de téléchargement d'un compte non
    /// premium. `pendingDownloadedZip` est remis à nil à la fermeture de la
    /// feuille (`MainView`, `.sheet(onDismiss:)`), quelle que soit la façon dont
    /// elle se ferme ; `isDownloadingFromNexus` est remis à false par
    /// `handleNexusDownloadResult`, et chaque branche de
    /// `NexusDownloader.download` appelle sa complétion exactement une fois.
    private func rejectNexusDownloadIfBusy() -> Bool {
        guard isDownloadingFromNexus || pendingDownloadedZip != nil else { return false }
        showModal(message: L(L10n.VM.nexusDlBusy))
        return true
    }

    /// Entry point for `nxm://` deep links (free-user "Mod Manager Download").
    func handleNxmURL(_ url: URL) {
        guard let link = NxmLink.parse(url) else {
            showModal(message: L(L10n.VM.nexusDlBadLink))
            return
        }
        if rejectNexusDownloadIfBusy() { return }
        isDownloadingFromNexus = true
        downloadingNexusModId = link.modId
        log(String(format: L(L10n.VM.nexusDlStarting), link.modId))
        nexusDownloader.download(modId: link.modId, fileId: link.fileId, game: link.gameDomain,
                                 key: link.key, expires: link.expires) { [weak self] result in
            self?.handleNexusDownloadResult(result, modId: link.modId)
        }
    }

    /// In-app download for the current game via the API key alone (Nexus
    /// Premium required for a direct link). fileId nil → main file resolved.
    func downloadModFromNexus(nexusId: Int) {
        if rejectNexusDownloadIfBusy() { return }
        isDownloadingFromNexus = true
        downloadingNexusModId = nexusId
        log(String(format: L(L10n.VM.nexusDlStarting), nexusId))
        nexusDownloader.download(modId: nexusId, fileId: nil, game: "stardewvalley",
                                 key: nil, expires: nil) { [weak self] result in
            self?.handleNexusDownloadResult(result, modId: nexusId)
        }
    }

    /// Shared completion for both Nexus download entry points: hops to main,
    /// clears the progress flag, and on success stashes the downloaded zip +
    /// its Nexus source for the install sheet, or surfaces a localized error.
    private func handleNexusDownloadResult(_ result: Result<URL, NexusDownloadError>, modId: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isDownloadingFromNexus = false
            self.downloadingNexusModId = nil
            switch result {
            case .success(let zipURL):
                self.pendingDownloadedZip = zipURL
                self.pendingNexusSource = NexusInstallSource(modId: modId)
                self.log(String(format: self.L(L10n.VM.nexusDlCompleted), modId))
            case .failure(let error):
                let message = self.nexusDownloadMessage(error)
                self.showModal(message: message)
                self.log(message, level: .warning)
            }
        }
    }

    /// Renders a `NexusDownloadError` through the app's live per-language bundle
    /// (`L(...)`) rather than `errorDescription`'s `NSLocalizedString`, which
    /// doesn't follow in-session language switching.
    private func nexusDownloadMessage(_ error: NexusDownloadError) -> String {
        switch error {
        case .noApiKey:            return L(L10n.VM.nexusDlNoApiKey)
        case .noValidFile:         return L(L10n.VM.nexusDlNoValidFile)
        case .noDownloadLink:      return L(L10n.VM.nexusDlNoLink)
        case .authFailed:          return L(L10n.VM.nexusDlAuthFailed)
        case .rateLimited:         return L(L10n.VM.nexusDlRateLimited)
        case .serverError(let code): return String(format: L(L10n.VM.nexusDlServerError), code)
        case .requestFailed(let msg): return String(format: L(L10n.VM.nexusDlRequestFailed), msg)
        }
    }

    /// Renders an installation-time error through the app's live per-language
    /// bundle, for the same reason as `nexusDownloadMessage(_:)` above:
    /// `errorDescription` goes through `NSLocalizedString`, which doesn't
    /// follow an in-session language switch.
    ///
    /// The two `as?` casts + exhaustive switches are deliberate: adding a case
    /// to either enum breaks the build here instead of silently falling back
    /// to an English string. Anything else (FileManager, `DroppedContentRecognizer`)
    /// keeps its system description, which macOS already localizes.
    ///
    /// Note the reasons carried by `.backupFailed` / `.installFailed` are built
    /// in English inside `ModZipInstaller`: the frame gets translated, the
    /// embedded technical detail doesn't.
    func installErrorMessage(_ error: Error) -> String {
        if let error = error as? InstallError {
            switch error {
            case .extractionFailed:       return L(L10n.ModInstall.errExtraction)
            case .unsafeContent:          return L(L10n.ModInstall.errUnsafe)
            case .gameDirEmpty:           return L(L10n.ModInstall.errGameDir)
            case .rarToolMissing:         return L(L10n.ModInstall.rarToolMissing)
            case .backupFailed(let reason):  return String(format: L(L10n.ModInstall.errBackup), reason)
            case .installFailed(let reason): return String(format: L(L10n.ModInstall.errInstall), reason)
            }
        }
        if let error = error as? ModInstallBackupManager.InstallBackupError {
            switch error {
            case .gameDirEmpty:           return L(L10n.ModInstall.errGameDir)
            case .modNotFound(let folder): return String(format: L(L10n.ModInstall.errModMissing), folder)
            case .backupCreationFailed(let reason): return String(format: L(L10n.ModInstall.errBackupCreate), reason)
            case .restoreFailed(let reason):        return String(format: L(L10n.ModInstall.errRestore), reason)
            }
        }
        return error.localizedDescription
    }

    /// Éteint les lignes de mise à jour des mods que l'installation vient de
    /// poser — eux seuls. À appeler sur le fil principal.
    ///
    /// Le retrait se faisait sur l'identifiant Nexus, que le parc réel montre
    /// non unique : 47 identifiants y sont déclarés par plusieurs `UniqueID`,
    /// et le 8828 par **trois mods sans rapport** du même auteur (A Cavalcade
    /// of Kombucha, From Source to Sea, Much Ado About Mushrooms), qui ont
    /// hérité du même `UpdateKeys`. Installer l'un effaçait la mise à jour des
    /// deux autres, qui repassaient pour à jour jusqu'à la vérification
    /// suivante.
    ///
    /// Les `UniqueID` viennent de `anchorInstalledMods`, c'est-à-dire des
    /// manifests réellement écrits : le même constat sert à ancrer et à
    /// éteindre. Une liste vide n'éteint rien — un manifest illisible ne
    /// prouve aucune installation, et une ligne conservée à tort coûte moins
    /// qu'une ligne effacée à tort.
    func dismissInstalledUpdates(uniqueIds: [String]) {
        guard !uniqueIds.isEmpty else { return }
        for uniqueId in uniqueIds {
            NexusUpdateChecker.shared.dismissUpdate(uniqueId: uniqueId)
        }
        // Recalculer plutôt que retirer de la liste affichée : sur un pack, le
        // retrait d'un composant ne fait pas forcément disparaître la ligne —
        // elle reste si d'autres composants ont encore une mise à jour, et
        // c'est la consolidation qui sait le dire.
        republishUpdatesFromCache()
    }

    /// After a Nexus-sourced install, log the version reconciliation outcome
    /// for the just-installed mod. Some mod authors forget to bump the manifest
    /// Version field, so the installed manifest can show an older version than
    /// what Nexus reports. This method only logs the discrepancy — it no
    /// longer writes anything to the registry (that write used to feed
    /// `nexusVersion`, removed 2026-08-12; see `InstalledModRegistry.swift`).
    ///
    /// Must run BEFORE `dismissInstalledUpdates` removes the entry (this method
    /// reads it to extract the version the checker flagged on).
    /// v1: single-mod installs only (packs are skipped upstream).
    func reconcileManifestVersion(installedFolderPaths: [String]) {
        guard let source = pendingNexusSource else { return }
        // Consume the source once: a later manual install in the same still-open
        // sheet must not reconcile against this download's mod.
        pendingNexusSource = nil
        guard installedFolderPaths.count == 1, let folderPath = installedFolderPaths.first else {
            return  // pack / ambiguous → abstain (v1)
        }
        // The update entry the checker computed for this mod (mod version + upload
        // date). If it isn't flagged, there's nothing to reconcile.
        let idStr = String(source.modId)
        guard let update = nexusUpdates.first(where: { $0.nexusModId == idStr }),
              !update.latestVersion.isEmpty else { return }

        let nexusVersion = update.latestVersion
        let folderName = (folderPath as NSString).lastPathComponent

        // Read the manifest's version to compare against the Nexus version.
        let manifestPath = (folderPath as NSString).appendingPathComponent("manifest.json")
        let manifestVersion = (try? String(contentsOfFile: manifestPath, encoding: .utf8))
            .flatMap { ManifestVersionPatcher.extractVersionValue(from: $0) }

        // Log the outcome: either the manifest was already correct, or it
        // lags behind what Nexus reports.
        if let mv = manifestVersion, NexusUpdateChecker.isNewer(nexusVersion, installed: mv) {
            log(String(format: L(L10n.VM.manifestVersionFixed), folderName, mv, nexusVersion))
        } else if let mv = manifestVersion {
            log(String(format: L(L10n.VM.manifestVersionSkipped), folderName, mv))
        }
    }

    // MARK: - Custom override persistence

    /// Ce que l'app affirme avoir installé, par `UniqueID`.
    let anchorStore = ModVersionAnchorStore()

    private static let customCategoriesKey = "nexusCustomCategories"
    private static let customModIdsKey = "nexusCustomModIds"

    private static func loadCustomCategories() -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: customCategoriesKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private static func saveCustomCategories(_ map: [String: Int]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: customCategoriesKey)
    }

    private static func loadCustomModIds() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: customModIdsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func saveCustomModIds(_ map: [String: String]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: customModIdsKey)
    }

    private static let modActivationTimestampsKey = "modActivationTimestamps"

    private static func loadModActivationTimestamps() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: modActivationTimestampsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    private static func saveModActivationTimestamps(_ map: [String: Date]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: modActivationTimestampsKey)
    }

    // MARK: - Installed mod registry (version + install date)

    /// Persistent record of when each mod was last installed/updated, keyed by
    /// folder name. Unlike the on-disk folder mtime (which `copyItem` preserves
    /// from the archive's packaging date and is therefore unreliable), this
    /// registry stores the *actual* installation timestamp on this machine.
    /// The update checker uses it for same-version detection: a Nexus upload
    /// newer than the registry date means the installed copy is stale.
    private static let installedModRegistryKey = UDKey.installedModRegistry
    /// Les dossiers dont la migration a retiré `nexusVersion`. Posée une fois
    /// par la migration, consommée et effacée par la synchronisation suivante :
    /// elle empêche que le changement de *lecture* de la version passe pour un
    /// changement sur le disque et écrase leur date d'installation.
    private static let installDateGraceKey = "installDateGraceFolders"
    private static let installedModRegistryBackupKey = UDKey.installedModRegistryBackup

    private var installedModRegistryCache: [String: InstalledModRecord]?
    private let installedModRegistryLock = NSLock()

    /// Loads the install registry from UserDefaults with automatic fallback:
    ///
    /// 1. **Primary key** — decode it. If valid, return it.
    /// 2. **Backup key** — if the primary is absent or corrupt, try the
    ///    backup. On success, promote the backup back to the primary key and
    ///    log a recovery notice.
    /// 3. **Neither is usable** — return `[:]`. The registry will be fully
    ///    rebuilt from disk by `syncInstalledModRegistry` on the next scan.
    ///
    /// Corrupt blobs (primary and/or backup) are purged so they don't block
    /// future saves.
    /// Returns the registry, populating the in-memory cache on first access.
    /// Subsequent calls read from the cache (no JSON decode, no UserDefaults
    /// I/O) — the cache is refreshed by `saveInstalledModRegistry` on writes.
    /// Thread-safe via `installedModRegistryLock`.
    private func loadInstalledModRegistry() -> [String: InstalledModRecord] {
        installedModRegistryLock.lock()
        defer { installedModRegistryLock.unlock() }
        if let cached = installedModRegistryCache {
            return cached
        }
        // Cold path: decode from UserDefaults (with backup fallback) exactly
        // once per session, then memoize.
        let loaded = Self.loadInstalledModRegistryFromDisk()
        installedModRegistryCache = loaded
        return loaded
    }

    /// Disk-level load with the primary/backup fallback chain. Static so it
    /// can run before the cache exists (called by `loadInstalledModRegistry`
    /// on the cold path, and by `clearInstalledModRegistryForTests` if a
    /// future test needs a disk-fresh copy).
    private static func loadInstalledModRegistryFromDisk() -> [String: InstalledModRecord] {
        let defaults = UserDefaults.standard

        // 1. Try the primary.
        if let primary = defaults.data(forKey: installedModRegistryKey),
           let decoded = try? JSONDecoder().decode([String: InstalledModRecord].self, from: primary) {
            return decoded
        }

        // Primary is absent or corrupt — purge it.
        if defaults.data(forKey: installedModRegistryKey) != nil {
            defaults.removeObject(forKey: installedModRegistryKey)
        }

        // 2. Try the backup.
        if let backup = defaults.data(forKey: installedModRegistryBackupKey),
           let decoded = try? JSONDecoder().decode([String: InstalledModRecord].self, from: backup) {
            // Promote the backup to the primary slot so subsequent loads are
            // fast and the (corrupt) primary is replaced.
            if let data = try? JSONEncoder().encode(decoded) {
                defaults.set(data, forKey: installedModRegistryKey)
            }
            NSLog("[StarHubFR] Install registry restored from backup (%d entries).",
                  decoded.count)
            return decoded
        }

        // Backup is also absent or corrupt — purge it too.
        if defaults.data(forKey: installedModRegistryBackupKey) != nil {
            defaults.removeObject(forKey: installedModRegistryBackupKey)
            NSLog("[StarHubFR] Install registry and backup both corrupt/unavailable — rebuilding from disk.")
        }

        // 3. Neither usable — empty; will be rebuilt on next scan.
        return [:]
    }

    /// Saves the registry to BOTH the primary and backup keys atomically. The
    /// backup guarantees that a corruption of one blob (e.g. a crashed write)
    /// can be recovered from the other on the next load.
    /// Updates the in-memory cache AND persists to BOTH the primary and backup
    /// keys. The `data` blob is encoded exactly once and reused for both keys
    /// (was encoded twice before). Thread-safe via `installedModRegistryLock`.
    private func saveInstalledModRegistry(_ map: [String: InstalledModRecord]) {
        installedModRegistryLock.lock()
        installedModRegistryCache = map
        installedModRegistryLock.unlock()
        persistInstalledModRegistry(map)
    }

    /// Persistance disque seule (primary + backup), hors lock. Extraite pour que
    /// `mutateInstalledModRegistry` puisse écrire après avoir relâché le lock
    /// (UserDefaults.set est lent : on ne tient pas le lock pendant l'écriture).
    private func persistInstalledModRegistry(_ map: [String: InstalledModRecord]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: Self.installedModRegistryKey)
        defaults.set(data, forKey: Self.installedModRegistryBackupKey)
    }

    /// RMW atomique sur le registre d'install : la séquence lecture du cache →
    /// mutation → écriture du cache se fait sous un seul lock, pour qu'un second
    /// scan concurrent ne puisse pas charger la même version, muter, et écraser
    /// nos changements (audit 2026-08-05 : faux « update available » perpétuel
    /// quand l'entrée nexusVersion était perdue dans la course).
    private func mutateInstalledModRegistry(_ body: (inout [String: InstalledModRecord]) -> Void) {
        installedModRegistryLock.lock()
        var map = installedModRegistryCache ?? Self.loadInstalledModRegistryFromDisk()
        body(&map)
        installedModRegistryCache = map
        installedModRegistryLock.unlock()
        persistInstalledModRegistry(map)
    }

    /// Returns the recorded install date for a mod folder, or nil if the mod
    /// was never registered (e.g. installed before this feature existed).
    func installedModDate(for folderName: String) -> Date? {
        loadInstalledModRegistry()[folderName]?.installedAt
    }

    /// Reconciles the persistent install registry with the mods found on disk
    /// during a scan. Called at the end of every `scanMods()` so that mods
    /// added by ANY means (app installer, drag-and-drop, manual copy into
    /// Mods/) are tracked.
    ///
    /// - A mod whose version differs from the registry (new install or update)
    ///   is recorded with `Date()` — the actual moment it was detected.
    /// - A mod on disk but absent from the registry (first time seen by the
    ///   app, e.g. manually copied) is recorded with its folder mtime as a
    ///   best-effort timestamp.
    /// - Registry entries for folders no longer on disk are pruned.
    /// One-shot migration flag. When false (first launch with the registry
    /// feature, or an upgrade from a version that used stale folder mtimes),
    /// the registry is wiped and rebuilt from scratch so every entry gets a
    /// clean `Date()` instead of the unreliable archive packaging date.
    private static let registryMigrationV2Key = "registryMigrationV2Done"

    /// Tous les mods, packs aplatis en leurs composants. Réutilise
    /// `flattenedMods` (module Core testé) plutôt que de réécrire le
    /// dépliage une 23e fois — voir son commentaire pour l'historique.
    private func allInstalledMods() -> [ModItem] {
        mods.flattenedMods
    }

    /// Constate sur disque les mises à jour que l'app n'a pas menées, et
    /// déplace l'ancre en conséquence.
    ///
    /// Sans cet appel, `ModVersionAnchorRules.afterDiskChange` n'avait aucun
    /// appelant et l'origine `.diskObserved` ne se produisait jamais : un mod
    /// ancré à la version X, puis mis à jour à la main (glisser-déposer, copie),
    /// continuait d'annoncer X comme version installée. smapi.io répondait
    /// « mise à jour disponible » indéfiniment — le défaut d'origine en miroir,
    /// une fausse mise à jour affirmée au lieu d'une vraie effacée.
    ///
    /// - Parameter excluding: les dossiers en grâce. Leur version « change »
    ///   parce que la lecture a changé, pas le disque : les ancrer ici
    ///   affirmerait une installation qui n'a pas eu lieu.
    private func anchorModsUpdatedOnDisk(_ allMods: [ModItem],
                                         previousVersions: [String: String],
                                         excluding graceFolders: Set<String>,
                                         now: Date) {
        // La version que smapi.io suggère, par `UniqueID` : c'est la cible que
        // le manifest doit rejoindre pour qu'on tienne l'installation pour
        // accomplie. Sans suggestion connue, la règle compare à la version du
        // manifest elle-même, donc l'atteint d'office.
        let suggested = Dictionary(nexusUpdates.map { ($0.uniqueId, $0.latestVersion) },
                                   uniquingKeysWith: { first, _ in first })
        for mod in allMods where !mod.uniqueId.isEmpty && !graceFolders.contains(mod.folderName) {
            guard let previous = previousVersions[mod.folderName] else { continue }
            guard let anchor = ModVersionAnchorRules.afterDiskChange(
                existing: anchorStore.anchor(for: mod.uniqueId),
                uniqueId: mod.uniqueId,
                previousManifestVersion: previous,
                currentManifestVersion: mod.version,
                suggestedVersion: suggested[mod.uniqueId] ?? mod.version,
                now: now) else { continue }
            anchorStore.put(anchor)
        }
    }

    private func syncInstalledModRegistry(scannedMods: [ModItem]) {
        // Flatten groups into individual mods so pack children are tracked too.
        let allMods = scannedMods.flatMap { mod -> [ModItem] in
            mod.isGroup ? (mod.children ?? []) : [mod]
        }

        let now = Date()

        // One-shot migration: wipe any pre-existing registry built with stale
        // folder mtimes. Runs exactly once.
        let migrationDone = UserDefaults.standard.bool(forKey: Self.registryMigrationV2Key)
        if !migrationDone {
            UserDefaults.standard.set(true, forKey: Self.registryMigrationV2Key)
        }

        let seen = allMods.map {
            InstalledModRegistry.Seen(folder: $0.folderName, version: $0.version)
        }

        // Les dossiers que la migration a nettoyés de leur `nexusVersion` : leur
        // version change à cette passe parce que la LECTURE a changé, pas le
        // disque. On les met en grâce pour cette passe seulement, puis on vide
        // le lot — un dossier absent de cette passe est de toute façon purgé du
        // registre, donc une passe suffit.
        let graceFolders = Set(
            UserDefaults.standard.stringArray(forKey: Self.installDateGraceKey) ?? [])

        // RMW atomique (load → sync → save sous un seul lock) : un scan
        // concurrent ne peut plus charger la même version du registre et
        // écraser nos changements (audit 2026-08-05 : faux « update available »
        // perpétuel quand l'entrée nexusVersion était perdue dans la course).
        // On perd la petite optimisation « n'écrire que si didChange », mais la
        // persistance d'un registre inchangé est idempotente et peu coûteuse.
        // La version que le registre portait AVANT cette passe. C'est le seul
        // endroit où l'app voit l'ancienne et la nouvelle version d'un dossier
        // côte à côte, donc le seul d'où l'on puisse constater qu'une
        // installation a eu lieu hors de l'app. À lire avant la mutation.
        let previousVersions = loadInstalledModRegistry().mapValues(\.version)

        var rebuiltCount = 0
        var wasEmpty = false
        mutateInstalledModRegistry { registry in
            if !migrationDone { registry = [:] }
            wasEmpty = registry.isEmpty
            let (synced, _) = InstalledModRegistry.sync(registry: registry,
                                                        seen: seen,
                                                        now: now,
                                                        installDateGrace: graceFolders)
            registry = synced
            if wasEmpty && !registry.isEmpty { rebuiltCount = registry.count }
        }

        anchorModsUpdatedOnDisk(allMods,
                                previousVersions: previousVersions,
                                excluding: graceFolders,
                                now: now)

        if !graceFolders.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.installDateGraceKey)
            log("Dates d'installation préservées pour \(graceFolders.count) mods dont seule la lecture de version avait changé",
                level: .info)
        }

        // Un mod supprimé ne doit pas laisser son affirmation derrière lui :
        // réinstallé plus tard, il hériterait d'une version qu'il n'a pas.
        anchorStore.pruneAnchors(keeping: Set(allMods.map(\.uniqueId).filter { !$0.isEmpty }))

        if wasEmpty && rebuiltCount > 0 {
            self.log(
                String(format: "Install registry rebuilt: %d mod(s) registered from disk.",
                       rebuiltCount),
                level: .info
            )
        }
    }

    func showModal(message: String) {
        self.alertMessage = message
        self.showAlert = true
    }
    
    // MARK: - Saves

    /// fetchSaves() scans the Saves directory and parses every save's XML —
    /// run off the main thread so it doesn't stall the UI when there are
    /// many saves.
    func reloadSaves() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let saves = SaveManager.shared.fetchSaves()
            DispatchQueue.main.async {
                self?.saves = saves
            }
        }
    }

    /// Whether Stardew Valley itself currently appears to be running.
    /// Best-effort process-name check (matches the launcher and the SMAPI-
    /// renamed process) — used to warn before writing save files, since the
    /// game's own autosave could conflict with an edit/restore made while
    /// it's open. Not a guarantee: a differently-named build wouldn't match.
    func isGameRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            guard let name = $0.localizedName else { return false }
            return name.caseInsensitiveCompare("Stardew Valley") == .orderedSame
        }
    }

    /// Whether `info`'s save file has been modified on disk since `info` was
    /// captured (e.g. the game was played while an editor was open on the
    /// stale snapshot). Callers use this to warn before writing — the editor
    /// forms don't diff individual fields, so a blind write would silently
    /// revert any progress made since the snapshot was taken.
    func isSaveStale(_ info: SaveGameInfo) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: info.fileURL.path),
              let currentModified = attrs[.modificationDate] as? Date else {
            return false
        }
        return currentModified > info.lastModified
    }

    func editSave(info: SaveGameInfo, newName: String, newFarm: String, newFav: String, newMoney: Int, newTotalMoneyEarned: Int, newMaxHealth: Int, newMaxStamina: Int, newGoldenWalnuts: Int, newQiGems: Int, newClubCoins: Int, newSpouse: String) {
        // `updateSave` parses and rewrites the full save XML — dispatched
        // off main so it doesn't block the UI on a large save file.
        DispatchQueue.global(qos: .userInitiated).async {
            let success = SaveManager.shared.updateSave(info: info, newName: newName, newFarm: newFarm, newFav: newFav, newMoney: newMoney, newTotalMoneyEarned: newTotalMoneyEarned, newMaxHealth: newMaxHealth, newMaxStamina: newMaxStamina, newGoldenWalnuts: newGoldenWalnuts, newQiGems: newQiGems, newClubCoins: newClubCoins, newSpouse: newSpouse)
            DispatchQueue.main.async {
                if success {
                    self.reloadSaves()
                    self.showModal(message: self.L(L10n.VM.saveSuccess))
                } else {
                    self.showModal(message: self.L(L10n.VM.saveError))
                }
            }
        }
    }

    func saveInventory() {
        guard let save = editingSave else { return }
        let items = inventoryToEdit
        // Same rationale as `editSave` — the save file read/write below
        // must not run on the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let success = SaveManager.shared.updateInventory(info: save, items: items)
            let refetched = success ? SaveManager.shared.fetchInventory(for: save) : nil
            DispatchQueue.main.async {
                if success {
                    self.showModal(message: self.L(L10n.Saves.inventorySuccess))
                    if let refetched = refetched {
                        self.inventoryToEdit = refetched
                    }
                } else {
                    self.showModal(message: self.L(L10n.Saves.inventoryError))
                }
            }
        }
    }
    /// Envoie le dossier de sauvegarde à la corbeille.
    ///
    /// **Hors du fil principal, obligatoirement** : une sauvegarde de fin de
    /// partie pèse des dizaines de mégaoctets répartis sur des centaines de
    /// fichiers, et le déplacement se faisait ici même, fenêtre figée.
    /// `@MainActor` sur la méthode : seul le corps du `Task.detached` quitte
    /// le fil principal, les `@Published` touchés après l'`await` y restent.
    @MainActor
    func deleteSave(info: SaveGameInfo) async {
        guard !isSaveOperationRunning else { return }
        isSaveOperationRunning = true
        let deleted = await Task.detached(priority: .userInitiated) {
            SaveManager.shared.deleteSave(info: info)
        }.value
        isSaveOperationRunning = false
        if deleted {
            // Fermer l'éditeur ici, pas côté vue : la suppression est
            // asynchrone, et un `editingSave = nil` enchaîné après l'appel
            // fermait la fiche même quand le `guard` ci-dessus avait renvoyé
            // sans rien supprimer. Ne ferme que la fiche de la sauvegarde
            // supprimée — on peut en éditer une autre depuis l'arbre.
            if editingSave?.id == info.id { editingSave = nil }
            reloadSaves()
            showModal(message: L(L10n.VM.deleteSaveSuccess))
        } else {
            showModal(message: L(L10n.VM.deleteSaveError))
        }
    }
    
    /// L'arbre des sauvegardes tel qu'il s'affiche.
    ///
    /// La filiation et le tri vivent dans `SaveTree` (module testable) ; ne
    /// reste ici que le filtre par étiquette, qui dépend d'un magasin sur
    /// disque. Le filtre s'applique aux racines seulement, comme avant.
    var savesHierarchy: [SaveNode] {
        var roots = SaveTree.build(from: saves, sortedBy: saveSortOption)
        if !saveFilterTag.isEmpty {
            roots = roots.filter {
                SaveNotesStore.shared.note(for: $0.info.folderName).tag == saveFilterTag
            }
        }
        return roots
    }

    var availableFilterTags: [String] {
        let allTags = saves.compactMap { SaveNotesStore.shared.note(for: $0.folderName).tag }.filter { !$0.isEmpty }
        return Array(Set(allTags)).sorted()
    }
    
    func setAvatar(forSave folderName: String, iconPath: String) {
        let note = SaveNotesStore.shared.note(for: folderName)
        SaveNotesStore.shared.setNote(for: folderName, tag: note.tag, note: note.note, customIconPath: iconPath)
        objectWillChange.send()
    }
    
    func selectCustomAvatar(forSave folderName: String, completion: ((String) -> Void)? = nil) {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = L(L10n.Saves.avatarPanelTitle)
        if panel.runModal() == .OK, let url = panel.url,
           let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            // Copy to app support dir to prevent broken paths
            let supportDir = appSupport.appendingPathComponent("StarHubTH/Avatars", isDirectory: true)
            try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
            let destURL = supportDir.appendingPathComponent("\(folderName)_\(url.lastPathComponent)")
            do {
                try FileManager.default.copyItem(at: url, to: destURL)
            } catch {
                log("selectCustomAvatar: copy failed — avatar path not set: \(error)", level: .error)
                return
            }
            setAvatar(forSave: folderName, iconPath: destURL.path)
            completion?(destURL.path)
        }
        #endif
    }
    
    /// Copie le dossier de sauvegarde puis réécrit les noms dans son XML.
    /// Même raison qu'`deleteSave` de tourner hors du fil principal — ici
    /// c'est une copie complète, l'opération la plus lente de l'onglet.
    @MainActor
    func duplicateSave(info: SaveGameInfo, newName: String, newFarm: String) async {
        guard !isSaveOperationRunning else { return }
        isSaveOperationRunning = true
        let duplicated = await Task.detached(priority: .userInitiated) {
            SaveManager.shared.duplicateSave(info: info, newName: newName, newFarm: newFarm)
        }.value
        isSaveOperationRunning = false
        if duplicated {
            reloadSaves()
            showModal(message: L(L10n.VM.duplicateSaveSuccess))
        } else {
            showModal(message: L(L10n.VM.duplicateSaveError))
        }
    }
    
    func openSaveInFinder(info: SaveGameInfo) {
        SaveManager.shared.openSaveInFinder(info: info)
    }

    // MARK: - Backup Timeline

    /// listBackups scans the backups folder on disk — run off the main
    /// thread so opening the timeline doesn't stall the UI when there are
    /// many backups.
    func listBackups(for info: SaveGameInfo, completion: @escaping ([SaveBackup]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let backups = SaveManager.shared.listBackups(for: info)
            DispatchQueue.main.async {
                completion(backups)
            }
        }
    }

    /// Copie la sauvegarde entière dans le dossier des backups. C'est la plus
    /// lourde des écritures de l'onglet ; elle tournait pourtant sur le fil
    /// principal, bouton « Sauvegarder » compris.
    @MainActor
    func createBackup(info: SaveGameInfo) async -> Bool {
        guard !isSaveOperationRunning else { return false }
        isSaveOperationRunning = true
        let created = await Task.detached(priority: .userInitiated) {
            SaveManager.shared.backupSave(info: info)
        }.value
        isSaveOperationRunning = false
        return created
    }

    @MainActor
    func branchFromBackup(backup: SaveBackup, newName: String, newFarm: String) async -> Bool {
        guard !isSaveOperationRunning else { return false }
        isSaveOperationRunning = true
        let branched = await Task.detached(priority: .userInitiated) {
            SaveManager.shared.branchFromBackup(backup: backup, newName: newName, newFarm: newFarm)
        }.value
        isSaveOperationRunning = false
        if branched {
            reloadSaves()
            showModal(message: L(L10n.VM.branchSuccess))
            return true
        } else {
            showModal(message: L(L10n.VM.branchError))
            return false
        }
    }

    @MainActor
    func restoreBackup(backup: SaveBackup, info: SaveGameInfo) async {
        guard !isSaveOperationRunning else { return }
        isSaveOperationRunning = true
        let restored = await Task.detached(priority: .userInitiated) {
            SaveManager.shared.restoreBackup(backup: backup, info: info)
        }.value
        isSaveOperationRunning = false
        if restored {
            reloadSaves()
            viewingSaveTimeline = nil
            editingSave = nil
            showModal(message: L(L10n.VM.restoreSuccess))
        } else {
            showModal(message: L(L10n.VM.restoreError))
        }
    }

    @MainActor
    func deleteBackup(_ backup: SaveBackup) async -> Bool {
        guard !isSaveOperationRunning else { return false }
        isSaveOperationRunning = true
        let deleted = await Task.detached(priority: .userInitiated) {
            SaveManager.shared.deleteBackup(backup)
        }.value
        isSaveOperationRunning = false
        return deleted
    }

    // MARK: - Save Notes

    func getNote(for folderName: String) -> SaveNote {
        SaveNotesStore.shared.note(for: folderName)
    }

    func setNote(for folderName: String, tag: String, note: String) {
        // Preserve existing customIconPath
        let existing = SaveNotesStore.shared.note(for: folderName)
        SaveNotesStore.shared.setNote(for: folderName, tag: tag, note: note, customIconPath: existing.customIconPath)
        objectWillChange.send()
    }

    // MARK: - Backup & Management
    /// Zips `sourceDir`'s contents to a timestamped file on the Desktop.
    /// Shared by backupAllSaves/backupAllMods, which differ only in the
    /// source directory, the output filename prefix, and their localized
    /// success/error messages.
    private func zipToDesktop(sourceDir: String, filePrefix: String, successKey: String, errorKey: String) {
        let desktopDir = "\(NSHomeDirectory())/Desktop"
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "")
        let zipPath = "\(desktopDir)/\(filePrefix)_\(timestamp).zip"

        // Zipping a whole Saves/Mods folder can take a while for large
        // libraries — run the process and block on its exit off the main
        // thread so the UI doesn't freeze for the duration.
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-r", zipPath, "."]
            process.currentDirectoryURL = URL(fileURLWithPath: sourceDir)

            do {
                try process.run()
                process.waitUntilExit()
                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        self.showModal(message: String(format: self.L(successKey), zipPath))
                    } else {
                        self.showModal(message: self.L(errorKey))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showModal(message: self.L(L10n.VM.cannotRunZip))
                }
            }
        }
    }

    func backupAllSaves() {
        let savesDir = "\(NSHomeDirectory())/.config/StardewValley/Saves"
        zipToDesktop(sourceDir: savesDir, filePrefix: "StardewSaves_Backup", successKey: L10n.VM.backupSavesSuccess, errorKey: L10n.VM.zipSavesError)
    }

    func backupAllMods() {
        guard !gameDir.isEmpty else {
            showModal(message: L(L10n.Settings.gameDirNotSet))
            return
        }
        let modsDir = (gameDir as NSString).appendingPathComponent("Mods")
        zipToDesktop(sourceDir: modsDir, filePrefix: "StardewMods_Backup", successKey: L10n.VM.backupModsSuccess, errorKey: L10n.VM.zipModsError)
    }
    
    func cleanDisabledMods() {
        guard !gameDir.isEmpty else { return }
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let fm = FileManager.default

        // Disabled mods now live as dot-prefixed folders inside Mods/
        // (Mods/.X). Enumerate the top level and remove every `.X` that
        // isn't OS junk.
        guard let entries = try? fm.contentsOfDirectory(atPath: modsPath) else {
            showModal(message: L(L10n.VM.cleanModsNotFound))
            return
        }


        var removed = 0
        var failed = 0
        var firstError: Error? = nil
        for entry in entries {
            // Only dot-prefixed entries that aren't OS junk are disabled mods.
            guard entry.hasPrefix(".") && !OSJunk.isJunk(entry) else { continue }
            let path = (modsPath as NSString).appendingPathComponent(entry)
            do {
                try fm.removeItem(atPath: path)
                removed += 1
            } catch {
                failed += 1
                if firstError == nil { firstError = error }
            }
        }

        if removed == 0 && failed == 0 {
            showModal(message: L(L10n.VM.cleanModsNotFound))
        } else if failed > 0 {
            showModal(message: String(format: L(L10n.VM.cleanModsError),
                                      firstError?.localizedDescription ?? ""))
        } else {
            showModal(message: L(L10n.VM.cleanModsSuccess))
        }

        if removed > 0 || failed > 0 {
            DispatchQueue.global(qos: .userInitiated).async {
                self.scanMods()
            }
        }
    }
    
    // MARK: - Thai Translation Hub Logic
    
    func fetchThaiTranslations() {
        guard let url = URL(string: "https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/README.md") else { return }

        DispatchQueue.main.async {
            self.thaiTranslationsError = nil
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            guard error == nil,
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let data = data, let content = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    self.thaiTranslationsError = self.L(L10n.ThaiHub.loadError)
                }
                return
            }

            let newTranslations = ThaiTranslationTable.parse(content)

            DispatchQueue.main.async {
                self.thaiTranslations = newTranslations
                self.evaluateThaiTranslationStatus()
            }
        }.resume()
    }
    
    func evaluateThaiTranslationStatus() {
        guard !gameDir.isEmpty else { return }
        let fm = FileManager.default
        let modsDir = (gameDir as NSString).appendingPathComponent("Mods")
        
        for i in 0..<thaiTranslations.count {
            // Very simple check: does any mod folder contain an i18n/th.json?
            // AND does the folder name sort of match the mod name?
            let nameToCheck = Self.strippingCPPrefix(thaiTranslations[i].name)
            var foundTranslation = false
            var foundOriginal = false
            for mod in mods {
                if mod.name.localizedCaseInsensitiveContains(nameToCheck) || nameToCheck.localizedCaseInsensitiveContains(mod.name) {
                    foundOriginal = true
                    
                    let thJsonPath = (modsDir as NSString).appendingPathComponent("\(mod.folderName)/i18n/th.json")
                    let cpThJsonPath = (modsDir as NSString).appendingPathComponent("\(mod.folderName)/[CP] \(mod.folderName)/i18n/th.json") // Handle nested [CP]
                    
                    if fm.fileExists(atPath: thJsonPath) || fm.fileExists(atPath: cpThJsonPath) {
                        foundTranslation = true
                    } else if mod.isGroup {
                        for child in mod.children ?? [] {
                            let childThJsonPath = (modsDir as NSString).appendingPathComponent("\(child.folderName)/i18n/th.json")
                            let childCpThJsonPath = (modsDir as NSString).appendingPathComponent("\(child.folderName)/[CP] \(child.folderName)/i18n/th.json")
                            if fm.fileExists(atPath: childThJsonPath) || fm.fileExists(atPath: childCpThJsonPath) {
                                foundTranslation = true
                                break
                            }
                        }
                    }
                }
            }
            thaiTranslations[i].isOriginalModInstalled = foundOriginal
            thaiTranslations[i].isInstalled = foundTranslation
        }
        
        // Sort installed mods first, then alphabetically
        thaiTranslations.sort { mod1, mod2 in
            if mod1.isInstalled != mod2.isInstalled {
                return mod1.isInstalled
            }
            return mod1.name.localizedStandardCompare(mod2.name) == .orderedAscending
        }
    }
    
    /// Retire un préfixe de catégorie `[CP]` d'un nom (avec ou sans espace
    /// suivant). La détection d'état et l'install du hub thaï normalisaient
    /// différemment (`[CP]` vs `[CP] `), ce qui désaccordait le nom du zip et
    /// le mod détecté pour un `[CP]Mod` sans espace — source unique désormais.
    private static func strippingCPPrefix(_ name: String) -> String {
        name.replacingOccurrences(of: "[CP]", with: "").trimmingCharacters(in: .whitespaces)
    }

    func installThaiTranslation(mod: ThaiTranslationMod) {
        guard !gameDir.isEmpty else { return }
        
        let modsDir = (gameDir as NSString).appendingPathComponent("Mods")
        let zipName = "\(Self.strippingCPPrefix(mod.name)) - Thai Translation.zip"
        
        showModal(message: String(format: L(L10n.VM.downloadingTranslation), mod.name))
        
        let apiUrl = URL(string: "https://api.github.com/repos/AppleBoiy/stardew-thai-translations/releases?per_page=100")!
        var request = URLRequest(url: apiUrl)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async { self.showModal(message: String(format: self.L(L10n.VM.downloadFailed), error.localizedDescription)) }
                return
            }
            
            guard let data = data,
                  let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                DispatchQueue.main.async { self.showModal(message: String(format: self.L(L10n.VM.downloadFailed), "Invalid API response")) }
                return
            }
            
            var targetDownloadUrl: URL? = nil
            
            for release in releases {
                if let assets = release["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String {
                            let normalizedAssetName = name.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
                            let normalizedZipName = zipName.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
                            
                            if normalizedAssetName == normalizedZipName,
                               let browserDownloadUrl = asset["browser_download_url"] as? String,
                               let url = URL(string: browserDownloadUrl) {
                                targetDownloadUrl = url
                                break
                            }
                        }
                    }
                }
                if targetDownloadUrl != nil { break }
            }
            
            guard let downloadUrl = targetDownloadUrl else {
                DispatchQueue.main.async { self.showModal(message: String(format: self.L(L10n.VM.downloadFailed), "Zip not found in releases")) }
                return
            }
            
            let task = URLSession.shared.downloadTask(with: downloadUrl) { localUrl, response, error in
                if let error = error {
                    DispatchQueue.main.async { self.showModal(message: String(format: self.L(L10n.VM.downloadFailed), error.localizedDescription)) }
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    DispatchQueue.main.async { self.showModal(message: String(format: self.L(L10n.VM.downloadFailed), "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")) }
                    return
                }
                
                guard let localUrl = localUrl else { return }
                // Extraction via le `ModZipInstaller` partagé (détection du
                // format par signature, outil adapté à rar/7z) plutôt qu'un
                // `/usr/bin/unzip` aveugle — une traduction en .7z/.rar
                // échouait silencieusement. Voir trust-bytes-not-filenames.
                do {
                    try ModZipInstaller.extractArchive(zipUrl: localUrl, to: URL(fileURLWithPath: modsDir))
                    ModZipInstaller.grantOwnerWriteAccess(in: URL(fileURLWithPath: modsDir))
                    DispatchQueue.main.async {
                        self.showModal(message: String(format: self.L(L10n.VM.installThaiSuccess), mod.name))
                        self.evaluateThaiTranslationStatus()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showModal(message: String(format: self.L(L10n.VM.unzipFailed), error.localizedDescription))
                    }
                }
            }
            task.resume()
        }.resume()
    }
    
    func openSavesFolder() {
        let home = NSHomeDirectory()
        let savesDir = URL(fileURLWithPath: "\(home)/.config/StardewValley/Saves")
        NSWorkspace.shared.open(savesDir)
    }
    
    // MARK: - Mod Profiles
    func loadProfiles() {
        // Must be called on the main actor: `modProfiles` and `activeProfileId`
        // are `@Published`, and mutating them off-main triggers a SwiftUI
        // runtime warning ("Publishing changes from background threads").
        // `performInitialLoad` honours this by calling us from its `main.async`
        // block (we're the only caller).
        if let data = UserDefaults.standard.data(forKey: UDKey.modProfiles),
           let profiles = try? JSONDecoder().decode([ModProfile].self, from: data) {
            self.modProfiles = profiles
        } else {
            self.modProfiles = []
        }

        if let activeIdStr = UserDefaults.standard.string(forKey: UDKey.activeProfileId),
           let activeId = UUID(uuidString: activeIdStr) {
            self.activeProfileId = activeId
        }
    }
    
    func saveProfiles() {
        if let data = try? JSONEncoder().encode(modProfiles) {
            UserDefaults.standard.set(data, forKey: UDKey.modProfiles)
        }
        if let activeId = activeProfileId {
            UserDefaults.standard.set(activeId.uuidString, forKey: UDKey.activeProfileId)
        } else {
            UserDefaults.standard.removeObject(forKey: UDKey.activeProfileId)
        }
    }
    
    /// The currently-active profile, if any (nil when none is applied).
    var activeProfile: ModProfile? {
        guard let id = activeProfileId else { return nil }
        return modProfiles.first { $0.id == id }
    }

    private let defaultProfileKey = "defaultProfileId"

    /// The id of the auto-created default profile (nil if none was seeded).
    var defaultProfileId: UUID? {
        UserDefaults.standard.string(forKey: defaultProfileKey).flatMap(UUID.init(uuidString:))
    }

    /// The default profile is protected from deletion (it's the always-present
    /// baseline). Everything else about it behaves like a normal profile.
    func isDefaultProfile(_ id: UUID) -> Bool { defaultProfileId == id }

    /// One-time: on a fresh install, create a starter profile capturing the
    /// current mod setup so there's always an active profile to work from.
    /// Guarded by a persisted flag so deleting every profile later never
    /// re-creates it, and deferred until a scan has actually found mods so the
    /// snapshot isn't empty.
    func ensureDefaultProfileIfNeeded() {
        let key = "didSeedDefaultProfile"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard !mods.isEmpty else { return }   // wait for a scan with mods; don't burn the flag yet
        if modProfiles.isEmpty {
            createProfile(name: L(L10n.Profiles.defaultName))
            // Record the seeded profile as the (undeletable) default.
            if let seeded = modProfiles.last {
                UserDefaults.standard.set(seeded.id.uuidString, forKey: defaultProfileKey)
            }
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    func createProfile(name: String) {
        // Snapshot the currently enabled mods into the new profile
        let currentEnabledIds = mods.enabledUniqueIds

        let newProfile = ModProfile(name: name, enabledModIds: currentEnabledIds)
        modProfiles.append(newProfile)
        // Mark it active immediately (its snapshot already matches the current
        // filesystem, so no file moves are needed — the user can edit it next).
        activeProfileId = newProfile.id
        saveProfiles()
        log(String(format: L(L10n.VM.profileCreated), name, currentEnabledIds.count))
    }

    func deleteProfile(id: UUID) {
        // The default profile is protected — never delete it.
        guard !isDefaultProfile(id) else { return }
        if let name = modProfiles.first(where: { $0.id == id })?.name {
            log(String(format: L(L10n.VM.profileDeleted), name))
        }
        modProfiles.removeAll { $0.id == id }
        if activeProfileId == id {
            activeProfileId = nil
        }
        saveProfiles()
    }
    
    func updateProfile(id: UUID, newName: String, enabledModIds: [String]) {
        if let index = modProfiles.firstIndex(where: { $0.id == id }) {
            modProfiles[index].name = newName
            modProfiles[index].enabledModIds = enabledModIds
            saveProfiles()

            // If this is the active profile, apply the new mod selection to the filesystem
            if activeProfileId == id {
                applyProfileToFilesystem(profile: modProfiles[index])
            }
        }
    }

    /// Renames a profile in place (its enabled-mod set is untouched).
    func renameProfile(id: UUID, newName: String) {
        guard let index = modProfiles.firstIndex(where: { $0.id == id }) else { return }
        modProfiles[index].name = newName
        saveProfiles()
    }

    // MARK: - Bissection (recherche du mod responsable)

    /// Pilote une recherche par moitiés. Créée à la demande : la grande majorité
    /// des sessions ne s'en sert jamais, inutile de l'instancier au démarrage.
    lazy var bisection = BisectionRunner(vm: self)

    /// Active exactement les dossiers de premier niveau donnés, met les autres
    /// en pause, puis rescane. Chemin dédié à la bissection : il réutilise le
    /// déplacement de dossiers éprouvé par les profils, mais neutralise
    /// `activeProfileId` le temps de l'application — sinon `syncActiveProfileIds`,
    /// lancé à la fin du rescane, réécrirait le profil actif de l'utilisateur
    /// avec l'état éphémère de la recherche.
    ///
    /// - Parameter completion: reçoit le **résultat** de l'application. Un
    ///   déplacement en échec (dossier tenu ouvert, jumeau déjà présent) laisse
    ///   la modlist à moitié en pause : l'appelant doit le savoir pour ne pas
    ///   jeter l'instantané qui permettrait de réessayer.
    func applyEnabledFolders(_ folders: [String],
                             completion: @escaping (BisectionRestoreOutcome) -> Void) {
        let target = Set(folders)
        let ephemeral = ModProfile(
            // Nom lisible : si un déplacement échoue, l'alerte d'application
            // nomme le « profil » concerné — un nom vide donnerait un message
            // parlant d'un profil « ».
            name: L(L10n.Bisect.profileName),
            enabledModIds: mods
                .filter { target.contains($0.folderName) }
                .flatMap { $0.isGroup ? ($0.children ?? []).map(\.uniqueId) : [$0.uniqueId] }
                .filter { !$0.isEmpty }
        )
        let savedActiveProfile = activeProfileId
        activeProfileId = nil
        applyProfileToFilesystem(profile: ephemeral) { [weak self] moveFailures in
            self?.activeProfileId = savedActiveProfile
            completion(BisectionRestoreOutcome(moveFailures: moveFailures))
        }
    }

    func applyProfile(id: UUID?) {
        // Serialize activations: refuse to start a new one while a previous
        // profile is still being applied (mod folders being renamed /
        // rescanned), so two activations can't race on the same paths.
        guard !isApplyingProfile else { return }

        guard let id = id, let profile = modProfiles.first(where: { $0.id == id }) else {
            activeProfileId = nil
            saveProfiles()
            return
        }

        // Activation is exclusive: setting activeProfileId below replaces any
        // previously-active profile (only one can be active at a time).
        // If already active, just sync stored list from current filesystem (no file moves)
        if activeProfileId == id {
            syncActiveProfileIds()
            return
        }

        activeProfileId = id
        saveProfiles()
        applyingProfileId = id
        applyProfileToFilesystem(profile: profile)
        self.log(String(format: L(L10n.VM.switchProfile), profile.name))
    }

    /// Actually move mod files to match the given profile's enabledModIds.
    ///
    /// Unlike `toggleMod`, the previous implementation swallowed every
    /// filesystem error with `try?`, so a partial failure (e.g. one mod
    /// folder locked by another process, a permission issue, a stale
    /// destination) left the Mods/ layout in an inconsistent
    /// state with no signal to the user. This version captures each move
    /// error, logs it, and surfaces a user-visible alert summarizing how
    /// many mods could not be relocated — while still rescanning so the UI
    /// reflects the actual on-disk state (whatever it is).
    ///
    /// - Parameter completion: appelé après le rescane, avec le **nombre de
    ///   dossiers qui n'ont pas pu être déplacés** (0 = application complète).
    ///   Sans cette information, un appelant ne peut pas distinguer un succès
    ///   d'une application partielle — et la bissection y jetterait l'instantané
    ///   qui aurait permis de rattraper une modlist restée à moitié en pause.
    private func applyProfileToFilesystem(profile: ModProfile,
                                          completion: ((_ moveFailures: Int) -> Void)? = nil) {
        // Mark an application in progress so `applyProfile` refuses to start a
        // second one and the UI disables the Activate/Manage buttons until the
        // move + rescan below completes.
        isApplyingProfile = true
        let fm = FileManager.default
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")

        // Records each mod that could not be moved, with the underlying
        // error for the log. Drives both the user-facing alert and the
        // per-mod log lines below.
        struct MoveFailure {
            let modName: String
            let direction: String   // "→ activé" / "→ désactivé"
            let error: Error
        }
        var failures: [MoveFailure] = []
        var attempted = 0
        var anyEnabled = false

        // Detect profile entries that don't match any installed mod. These
        // are silently skipped by the move loops below, but the user must be
        // told the profile references mods that aren't there (e.g. uninstalled
        // since the profile was saved). Compare every profile enabledId
        // against the set of uniqueIds present on disk (groups resolved to
        // their children's ids), so a pack mod isn't reported missing when
        // one of its children satisfies the id.
        let snapshotMods = mods
        let installedUniqueIds = snapshotMods.allUniqueIds
        let missingIds = profile.enabledModIds.filter { !installedUniqueIds.contains($0) }

        // Shared helper: rename a mod folder within Mods/ to flip its
        // enabled/disabled state via the dot-prefix convention. `srcPhysical`
        // is the current on-disk name (with dot if disabled), `dstPhysical`
        // is the target name (with dot to disable, without to enable).
        // Never throws so the loop can keep processing the remaining mods
        // instead of aborting at the first error.
        func renameModFolder(_ mod: ModItem, from srcPhysical: String, to dstPhysical: String, direction: String) {
            attempted += 1
            do {
                try fm.moveItem(atPath: srcPhysical, toPath: dstPhysical)
            } catch {
                failures.append(MoveFailure(modName: mod.name, direction: direction, error: error))
            }
        }

        // Check whether a mod (or any of its children) is covered by the profile's enabled list
        func isCoveredByProfile(_ mod: ModItem) -> Bool {
            if mod.isGroup, let children = mod.children {
                return children.contains { profile.enabledModIds.contains($0.uniqueId) }
            }
            return profile.enabledModIds.contains(mod.uniqueId)
        }

        // Whether a mod can be represented in a profile at all. Profiles key on
        // `UniqueID`, which the enabled list stores (empty ids are filtered out
        // when snapshotting), so a mod whose manifest has no `UniqueID` can
        // never be "covered". Without this guard, applying ANY profile would
        // sweep every such mod into the disabled set — a silent data loss.
        // Leave those mods exactly where they are instead.
        func isProfileManageable(_ mod: ModItem) -> Bool {
            if mod.isGroup, let children = mod.children {
                return children.contains { !$0.uniqueId.isEmpty }
            }
            return !mod.uniqueId.isEmpty
        }

        // Disable mods not in profile: rename Mods/X → Mods/.X
        for mod in mods.filter({ $0.isEnabled }) {
            guard isProfileManageable(mod) else { continue }
            guard !isCoveredByProfile(mod) else { continue }
            let src = (modsPath as NSString).appendingPathComponent(mod.physicalFolderName)
            let dst = (modsPath as NSString).appendingPathComponent("." + mod.folderName)
            renameModFolder(mod, from: src, to: dst, direction: "→ désactivé")
        }

        // Enable mods in profile: rename Mods/.X → Mods/X. Only stamp the
        // activation timestamp for mods that were actually moved — stamping
        // a mod that failed to rename would record a phantom "last
        // activation" for a folder that is still sitting disabled.
        for mod in mods.filter({ !$0.isEnabled }) {
            guard isCoveredByProfile(mod) else { continue }
            let src = (modsPath as NSString).appendingPathComponent(mod.physicalFolderName)
            let dst = (modsPath as NSString).appendingPathComponent(mod.folderName)
            let beforeCount = failures.count
            renameModFolder(mod, from: src, to: dst, direction: "→ activé")
            if failures.count == beforeCount {
                self.modActivationTimestamps[mod.folderName] = Date()
                anyEnabled = true
            }
        }
        if anyEnabled {
            Self.saveModActivationTimestamps(self.modActivationTimestamps)
        }

        // Log each move failure individually with a localized, structured
        // message so the Logs tab (source = StarHubFR) shows exactly which
        // mod(s) failed, in which direction, and why.
        for failure in failures {
            log(
                String(format: L(L10n.VM.applyProfileMoveFail),
                       failure.modName, failure.direction, failure.error.localizedDescription),
                level: .error
            )
        }

        // Log the profile entries that don't match any installed mod — these
        // were silently ignored by the move loops, so without a log line the
        // user would believe the profile is fully applied when expected mods
        // are missing from disk.
        if !missingIds.isEmpty {
            let listing = missingIds.joined(separator: ", ")
            log(
                String(format: L(L10n.VM.applyProfileMissing),
                       profile.name, missingIds.count, listing),
                level: .warning
            )
        }

        // Always rescan so the list reflects the real on-disk state,
        // whatever it is after partial failures. syncActiveProfileIds
        // runs after so the active profile's stored id list tracks the
        // actual enabled set (possibly fewer than expected if moves
        // failed).
        let profileName = profile.name
        let failedNames = failures.map { $0.modName }
        DispatchQueue.global(qos: .userInitiated).async {
            self.scanMods()
            DispatchQueue.main.async {
                self.syncActiveProfileIds()
                self.isApplyingProfile = false
                self.applyingProfileId = nil
                // Surface the outcome to the user. A partial application
                // is the dangerous case: the profile is "active" but the
                // filesystem doesn't fully match it, so the next toggle
                // cycle could compound the inconsistency. Build a message
                // that names the affected mods (capped to avoid a giant
                // alert) so the user knows exactly what to fix.
                if !failures.isEmpty || !missingIds.isEmpty {
                    let summary = self.profileApplyMessage(
                        profileName: profileName,
                        failedNames: failedNames,
                        missingIds: missingIds,
                        attempted: attempted,
                        failureCount: failures.count
                    )
                    self.showModal(message: summary)
                    self.log(
                        String(format: "Profile \"%@\" applied: %lld move failure(s), %lld missing mod(s)",
                               profileName, failures.count, missingIds.count),
                        level: .warning
                    )
                }
                // Signaler la fin de l'application une fois le rescane terminé :
                // la bissection lance le jeu dans ce completion, et ne doit pas le
                // faire tant qu'un rescane peut encore réécrire `mods`. Le nombre
                // d'échecs remonte avec, pour que l'appelant sache si l'état sur
                // disque correspond vraiment à ce qui était demandé.
                completion?(failedNames.count)
            }
        }
    }

    /// Builds the user-facing alert message for a profile application that
    /// had problems (move failures and/or missing mods). Names the affected
    /// mods so the user can act on them; caps the lists to keep the alert
    /// readable, with a "+N more" suffix when truncated.
    private func profileApplyMessage(profileName: String, failedNames: [String],
                                     missingIds: [String], attempted: Int,
                                     failureCount: Int) -> String {
        let listLimit = 8
        var sections: [String] = []

        // Move failures — lead with the headline (full-failure vs partial),
        // then enumerate the mod names.
        if !failedNames.isEmpty {
            let headline: String
            if attempted == failureCount {
                headline = String(format: L(L10n.VM.applyProfileError), profileName, failureCount)
            } else {
                headline = String(format: L(L10n.VM.applyProfilePartial), profileName, failureCount)
            }
            sections.append(self.truncatedList(headline: headline,
                                               names: failedNames, limit: listLimit))
        }

        // Missing mods — references in the profile that aren't installed.
        if !missingIds.isEmpty {
            let headline = String(format: L(L10n.VM.applyProfileMissing),
                                  profileName, missingIds.count,
                                  missingIds.prefix(listLimit).joined(separator: ", "))
            let extra = missingIds.count > listLimit
                ? " (+\(missingIds.count - listLimit))"
                : ""
            sections.append(headline + extra)
        }

        return sections.joined(separator: "\n\n")
    }

    /// Formats `headline` followed by a newline-separated, truncated list of
    /// `names`. After `limit` entries, a "+N more" suffix is appended instead
    /// of dumping the whole list into the alert.
    private func truncatedList(headline: String, names: [String], limit: Int) -> String {
        let shown = names.prefix(limit).joined(separator: " • ")
        let extra = names.count > limit ? " (+\(names.count - limit))" : ""
        return headline + "\n" + shown + extra
    }

    /// Enable or disable every installed mod at once. File operations run on a
    /// background queue so the UI (and the progress bar) stay responsive. Each
    /// move uses the same "stale duplicate aside" safety pattern as
    /// `performToggle`: a pre-existing destination folder is set aside first,
    /// and restored if the main move fails, so no mod can ever end up in
    /// neither location. Progress is published after every move. Activation
    /// timestamps are stamped only for mods that were actually moved.
    func toggleAllMods(enable: Bool) {
        // Guard against re-entry: a second tap while the first run is still
        // moving folders would race on the same source/destination paths.
        guard bulkToggleProgress == nil else { return }

        let modsToMove = mods.filter { $0.isEnabled != enable }
        guard !modsToMove.isEmpty else {
            log(enable ? L(L10n.Mods.allAlreadyEnabled) : L(L10n.Mods.allAlreadyDisabled))
            return
        }

        let total = modsToMove.count
        bulkToggleEnabling = enable
        bulkToggleProgress = (done: 0, total: total)

        let gameDir = self.gameDir
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default

            struct MoveFailure {
                let modName: String
                let direction: String
                let error: Error
            }
            var failures: [MoveFailure] = []
            var attempted = 0
            var movedCount = 0
            var anyEnabled = false

            for (index, mod) in modsToMove.enumerated() {
                attempted += 1
                // Dot-prefix rename: source uses the current physical name,
                // destination uses the target state's name (with/without dot).
                let src = (modsPath as NSString).appendingPathComponent(mod.physicalFolderName)
                let dstName = enable ? mod.folderName : "." + mod.folderName
                let dst = (modsPath as NSString).appendingPathComponent(dstName)
                let direction = enable ? "→ activé" : "→ désactivé"

                var didMove = false

                // Safety: trust the filesystem over the cached isEnabled flag.
                // If the source is already gone, this mod was already renamed —
                // skip instead of operating on a non-existent path.
                guard fm.fileExists(atPath: src) else {
                    DispatchQueue.main.async {
                        self.bulkToggleProgress = (done: index + 1, total: total)
                    }
                    continue
                }

                do {
                    // A pre-existing duplicate at dst is set aside rather than
                    // deleted outright, so a failed moveItem below can't leave
                    // the mod lost from both locations. Kept defensively even
                    // though a same-parent rename should only collide on a bug
                    // or a leftover from a crashed prior toggle.
                    var staleDuplicateAside: String? = nil
                    if fm.fileExists(atPath: dst) {
                        let asidePath = dst + ".stale_\(UUID().uuidString)"
                        try fm.moveItem(atPath: dst, toPath: asidePath)
                        staleDuplicateAside = asidePath
                    }

                    do {
                        try fm.moveItem(atPath: src, toPath: dst)
                        didMove = true
                    } catch {
                        // Restore the old destination so the mod isn't lost.
                        if let asidePath = staleDuplicateAside {
                            do {
                                try fm.moveItem(atPath: asidePath, toPath: dst)
                            } catch {
                                self.log("CRITICAL: toggle rollback failed — mod still in \(asidePath) (could not move back to \(dst): \(error))", level: .error)
                            }
                        }
                        throw error
                    }

                    // Main move succeeded — clean up the stale duplicate.
                    if let asidePath = staleDuplicateAside {
                        try? fm.removeItem(atPath: asidePath)
                    }
                } catch {
                    failures.append(MoveFailure(modName: mod.name, direction: direction, error: error))
                }

                if didMove {
                    movedCount += 1
                    if enable {
                        DispatchQueue.main.async {
                            self.modActivationTimestamps[mod.folderName] = Date()
                        }
                        anyEnabled = true
                    }
                }

                // Publish progress on the main thread after each move.
                DispatchQueue.main.async {
                    self.bulkToggleProgress = (done: index + 1, total: total)
                }
            }

            if anyEnabled {
                DispatchQueue.main.async {
                    Self.saveModActivationTimestamps(self.modActivationTimestamps)
                }
            }

            for failure in failures {
                DispatchQueue.main.async {
                    self.log(
                        String(format: "%@ %@: %@",
                               failure.modName, failure.direction, failure.error.localizedDescription),
                        level: .error
                    )
                }
            }

            // Rescan so the list reflects the real on-disk state, whatever it
            // is after partial failures. syncActiveProfileIds runs after so the
            // active profile's stored id list tracks the actual enabled set.
            self.scanMods()
            DispatchQueue.main.async {
                self.bulkToggleProgress = nil
                self.syncActiveProfileIds()
                if failures.isEmpty {
                    self.log(String(format: enable ? self.L(L10n.Mods.enabledAllCount) : self.L(L10n.Mods.disabledAllCount),
                                    movedCount))
                } else if attempted == failures.count {
                    self.showModal(message: String(format: self.L(L10n.Mods.bulkToggleFailed), failures.count))
                } else {
                    self.showModal(message: String(format: self.L(L10n.Mods.bulkTogglePartial), movedCount, failures.count))
                    self.log(String(format: enable ? self.L(L10n.Mods.enabledAllCount) : self.L(L10n.Mods.disabledAllCount),
                                    movedCount), level: .warning)
                }
            }
        }
    }

    /// Permanently delete a mod (or an entire mod pack) from disk. The mod's
    /// folder is removed from `Mods/` (disabled mods live there as `.X`,
    /// enabled ones as `X`). For a pack (`isGroup == true`), this deletes the
    /// single top-level folder that contains all child mods. The mod list is
    /// rescanned afterward so the UI reflects the real on-disk state. Surfaces
    /// a user-visible alert on failure.
    func deleteMod(_ mod: ModItem) {
        guard !gameDir.isEmpty else {
            showModal(message: L(L10n.Settings.gameDirNotSet))
            return
        }

        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        // A mod always lives under Mods/ now — disabled ones carry a leading
        // dot in their physical folder name. `physicalFolderName` resolves
        // the right on-disk path regardless of enabled state.
        let modPath = (modsPath as NSString).appendingPathComponent(mod.physicalFolderName)

        let fm = FileManager.default
        guard fm.fileExists(atPath: modPath) else {
            showModal(message: L(L10n.Mods.deleteNotFound))
            DispatchQueue.global(qos: .userInitiated).async {
                self.scanMods()
            }
            return
        }

        // Mark this row as deleting so its spinner shows until the rescan
        // that follows the folder removal has republished `mods`.
        pendingDeleteFolder = mod.folderName

        do {
            try fm.removeItem(atPath: modPath)
            // The registry entry is pruned by the next scanMods() (below),
            // which removes entries for folders no longer on disk.
            // Forget the mod's error history too, so the file doesn't keep
            // growing with mods that are no longer installed.
            if errorHistoryLoaded {
                modErrorHistory.remove(mod: mod.folderName)
                ModErrorHistoryStore.save(modErrorHistory, lastLogDate: lastErrorHistoryLogDate)
            }
            // TranslationBaseline picked up every convention
            // ModErrorHistoryStore follows except the one that bounds its
            // growth — without this, a deleted mod's reference store (every
            // English/French pair seen) stays on disk forever.
            if let store = TranslationBaseline.defaultDirectory() {
                try? TranslationBaseline.remove(modFolderName: mod.folderName, in: store)
            }
            // `invalidateFrenchCoverage` is `@MainActor` (three `@Published`
            // mutations); `deleteMod` isn't itself isolated, but both call
            // sites are button actions in a View, always on the main thread.
            // `assumeIsolated` keeps this synchronous and right after the
            // disk purge above — a `Task` hop here would reopen the very
            // race `d5deef5`/`8467e4a` closed for the index.
            MainActor.assumeIsolated {
                invalidateFrenchCoverage(for: mod.folderName)
            }
            log(String(format: L(L10n.Mods.deletedLog), mod.name))
            DispatchQueue.global(qos: .userInitiated).async {
                self.scanMods()
                DispatchQueue.main.async {
                    self.syncActiveProfileIds()
                    self.pendingDeleteFolder = nil
                }
            }
        } catch {
            pendingDeleteFolder = nil
            log(String(format: "%@: %@",
                       L(L10n.Mods.deleteFailed), error.localizedDescription),
                level: .error)
            showModal(message: String(format: L(L10n.Mods.deleteFailed),
                                      error.localizedDescription))
        }
    }

    /// Call this after any toggleMod so the profile stays up to date.
    func syncActiveProfileIds() {
        guard let id = activeProfileId,
              let index = modProfiles.firstIndex(where: { $0.id == id }) else { return }

        let actualEnabledIds = mods.enabledUniqueIds

        modProfiles[index].enabledModIds = actualEnabledIds
        saveProfiles()
    }
}
