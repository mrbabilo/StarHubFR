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
    /// Les conflits de chargement que Content Patcher a constatés lors de la
    /// **dernière partie** journalisée. La date de ce constat est `smapiLogDate`
    /// (mtime de `SMAPI-latest.txt`), pas maintenant : ce n'est pas l'état du
    /// parc aujourd'hui, un conflit rapporté peut concerner deux mods qui sont
    /// en pause à l'instant où on le lit.
    @Published private(set) var contentPatcherConflicts: [LoadConflict] = []
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
    /// Les mods que smapi.io n'a pas pu vérifier, avec le nom affiché partout
    /// ailleurs et le motif classé. 115 mods du parc réel sont dans ce cas :
    /// les taire laissait la fenêtre dire « tous à jour » alors qu'ils
    /// n'avaient de verdict d'aucune source — Powered Automation et sa mise à
    /// jour réelle invisible en sont la preuve levée le 2026-08-27.
    ///
    /// L'`UniqueID` accompagne le nom depuis B2-T10 : une ligne sur laquelle on
    /// veut agir — ici la retirer quand Nexus a fini par la trancher — doit
    /// pouvoir être désignée, et deux mods peuvent porter le même nom.
    @Published private(set) var unverifiableMods: [(uniqueId: String,
                                                    name: String,
                                                    blocker: SmapiUpdateResponse.Blocker)] = []
    /// Ce que smapi.io sait de la compatibilité de chaque mod, par `UniqueID`.
    ///
    /// Relu au lancement plutôt que reconstruit : l'avertissement le plus utile
    /// se déclenche à l'**activation** d'un mod, geste qui n'attend pas qu'une
    /// vérification ait abouti.
    ///
    /// Mesuré sur le parc : 281 mods `Ok`, 7 signalés, et **552 sans verdict**.
    /// Une absence n'est donc pas un satisfecit, et rien ne doit l'afficher
    /// comme tel.
    @Published private(set) var modCompatibility: [String: ModCompatibility] =
        ModCompatibilityStore.load() {
        didSet { compatibilityStatuses = modCompatibility.mapValues(\.status) }
    }
    /// Les mêmes verdicts réduits à leur statut, **tenus à jour plutôt que
    /// recalculés** : `anomaly(for:)` tourne sur chaque ligne du parc, deux
    /// fois — pour le compteur du cadrage et pour le filtrage. Reconstruire le
    /// dictionnaire à chaque appel rendrait la liste quadratique.
    private var compatibilityStatuses: [String: ModCompatibility.Status] = [:]
    /// True while a Nexus check is in flight.
    @Published var isCheckingNexusUpdates: Bool = false
    /// Last error message from a Nexus check (nil = none / not run yet).
    @Published var nexusCheckError: String? = nil
    /// Progress of the in-flight Nexus check: `(done, total)`. `nil` when idle.
    @Published var nexusCheckProgress: (done: Int, total: Int)? = nil
    /// Whether the user has provided a Nexus API key (kept in sync with Keychain).
    @Published var hasNexusApiKey: Bool = false
    /// Le compte Nexus, `nil` tant qu'on ne sait pas.
    ///
    /// Sert à ne pas proposer ce qui échouera : le téléchargement direct par
    /// l'API est réservé aux comptes premium.
    @Published private(set) var nexusAccount: NexusAccount? = nil

    /// `true` seulement quand on **sait** que le compte n'est pas premium.
    /// L'ignorance ne retire rien : mieux vaut un bouton qui échoue qu'un
    /// bouton absent chez quelqu'un qui y avait droit.
    var nexusDirectDownloadUnavailable: Bool { nexusAccount?.isPremium == false }

    /// Dernier quota Nexus relevé, `nil` tant qu'aucune réponse de l'API n'a été
    /// vue. Rafraîchi à l'ouverture des réglages et à chaque relevé (B2-T6).
    @Published private(set) var nexusQuota: NexusQuota? = nil
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

    /// Où en est le téléchargement Nexus en cours (B2-T1). `nil` au repos, et
    /// aussi pendant les deux appels d'API qui résolvent le lien : il n'y a
    /// alors rien à mesurer, seulement une attente — `isDownloadingFromNexus`
    /// la porte déjà.
    ///
    /// Un seul, jamais une liste : `rejectNexusDownloadIfBusy` sérialise les
    /// téléchargements à dessein (deux en vol se disputeraient
    /// `pendingDownloadedZip`). Un panneau de transferts concurrents n'aurait
    /// rien à lister.
    @Published private(set) var nexusDownloadProgress: DownloadProgress?

    /// Le téléchargement en vol, seul point d'annulation. Existe dès la
    /// demande, donc avant que le lien ne soit résolu.
    private var nexusDownloadInFlight: NexusFileDownload?
    /// Le débit, lissé sur trois secondes. Vit ici et non dans la vue : le
    /// téléchargement continue quand l'onglet change.
    private var nexusDownloadRate = DownloadRateEstimator()

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

    /// Nexus mod id overrides keyed by mod `folderName`. Used to give a Nexus
    /// link to mods that don't declare a `nexus:<id>` UpdateKey in their
    /// manifest. When present, it also feeds back into the update check so the
    /// linked mod can be checked for updates like any other.
    ///
    /// Trois sources l'alimentent, par ordre d'ancienneté : la saisie de
    /// l'utilisateur, l'identifiant d'une installation venue de Nexus
    /// (`recordNexusModId`), et le `metadata.nexusID` que smapi.io rend à
    /// chaque vérification (`learnNexusIds`). Les deux dernières ne recouvrent
    /// jamais la première.
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
    /// Les mods marqués comme favoris, par leur `folderName` **logique** —
    /// celui qui ne porte pas le point d'un dossier en pause, donc le marquage
    /// survit à une mise en pause. Même clé que `modActivationTimestamps`.
    @Published private(set) var favoriteMods: Set<String> = []
    /// Les mods dont le `config.json` suit le profil actif (B3-T5), par nom
    /// **logique** de dossier — même clé que `favoriteMods`.
    @Published private(set) var profileManagedConfigMods: Set<String> = []

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
            // Le parc est connu ici, avant même qu'on ouvre l'onglet Alertes
            // système — c'est ce qui rend le compte de la pastille (tâche 7)
            // vrai sans avoir ouvert la section. `scanIfNeeded` est sûr à
            // appeler souvent : il compare une signature du parc à celle de
            // son dernier scan et ne relance que si elle a changé, ou s'il
            // n'y a pas encore de rapport (il refuse déjà de scanner sans
            // `gameDir` — pas de deuxième garde ici). `Task { @MainActor … }`,
            // comme `recomputeFrenchCoverage()` juste au-dessus pour
            // `reloadOutdatedKeyIndex()` : cette classe n'est pas elle-même
            // `@MainActor`, et `KeybindScanService` l'est.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.keybindScanService.scanIfNeeded(mods: self.mods, gameDir: self.gameDir)
            }
        }
    }

    /// Compte les problèmes de raccourcis (collisions + conflits jeu) pour
    /// les pastilles de la barre latérale et de l'accueil (tâche 7) — les
    /// « non reconnus » n'y entrent pas, ce sont des valeurs illisibles, pas
    /// des problèmes avérés. Zéro tant qu'aucun rapport n'existe : une
    /// pastille qui n'a pas encore la réponse n'invente pas de chiffre.
    /// `@MainActor` explicite comme `reloadOutdatedKeyIndex()` juste en
    /// dessous : `keybindScanService` est isolé à l'acteur principal, cette
    /// classe ne l'est pas.
    @MainActor
    var keybindProblemCount: Int {
        keybindScanService.report?.problemCount ?? 0
    }

    /// La définition d'une « alerte » (pastille de la barre latérale et
    /// bande de l'accueil, tâche 7) : erreurs SMAPI plus problèmes de
    /// raccourcis — collisions et conflits jeu, les « non reconnus » exclus
    /// (illisibles, pas avérés ; voir `keybindProblemCount`) — plus conflits
    /// entre mods aux deux côtés actifs (voir `activeConflictCount`). Un
    /// seul endroit pour cette somme : barre latérale et accueil ne peuvent
    /// plus diverger.
    @MainActor
    var systemAlertCount: Int {
        smapiErrors.count + keybindProblemCount + activeConflictCount
    }

    /// Combien d'incompatibilités entre mods réclament une attention
    /// aujourd'hui (spec A5-T2, « Pastille ») : une par paire déclarée ou
    /// observée dans le journal, non écartée, dont les deux côtés sont actifs
    /// — une paire dormante ne compte pas, même règle que les raccourcis. La
    /// règle elle-même vit dans `ModConflictVerdicts.liveConflictCount`,
    /// pure et testée, comme `activationConflict` avant elle.
    @MainActor
    var activeConflictCount: Int {
        let activeFolders = Set(mods.flattenedMods.filter(\.isEnabled).map(\.folderName))
        let candidates = modConflictVerdicts.declared + contentPatcherConflicts.compactMap(conflictPair)
        return modConflictVerdicts.liveConflictCount(candidates: candidates, activeFolders: activeFolders)
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

    /// `true` quand URL validée **et** modèle nommé.
    var isLocalAIConfigured: Bool {
        localAIEndpoint != nil && !localAIModelName.isEmpty
    }

    /// Les identifiants du secours en ligne, `nil` si la case est décochée ou
    /// si aucune clé n'est enregistrée. Les deux conditions sont nécessaires :
    /// une clé sans accord ne sort pas, un accord sans clé n'a rien à envoyer.
    var deepLCredentials: DeepLClient.Credentials? {
        guard UserDefaults.standard.bool(forKey: UDKey.deepLFallbackEnabled),
              let key = KeychainSecret.deepLApiKey.read() else { return nil }
        return DeepLClient.Credentials(key: key)
    }

    /// Une clé de secours est-elle enregistrée ? **Mémorisé** : la question
    /// se pose à chaque passe de rendu de l'onglet Traduction, et interroger
    /// le trousseau à ce rythme se paie. Les deux écritures ci-dessous sont
    /// les seules qui la changent.
    @Published private(set) var hasDeepLKey = KeychainSecret.deepLApiKey.read() != nil

    /// Enregistre la clé du secours. Rend `false` si le trousseau refuse —
    /// l'appelant ne doit pas annoncer une clé enregistrée qui ne l'est pas.
    @discardableResult
    func setDeepLKey(_ key: String) -> Bool {
        let saved = KeychainSecret.deepLApiKey.write(key)
        hasDeepLKey = saved
        return saved
    }

    func clearDeepLKey() {
        KeychainSecret.deepLApiKey.clear()
        hasDeepLKey = false
    }

    /// `true` dès qu'**un** moteur peut traduire — ce qui rend le bouton de
    /// lot et le bouton « Pré-traduire » visibles (spec §7 : visibles s'il
    /// reste des clés à traduire et qu'une IA est configurée).
    ///
    /// Le secours seul suffit : sur une machine où aucun modèle local ne
    /// tourne confortablement, c'est la seule voie, et la lui cacher
    /// reviendrait à ne rien offrir du tout.
    var isTranslationAssistAvailable: Bool {
        isLocalAIConfigured || isFallbackEnabled
    }

    /// Le secours part-il vraiment ? Une case cochée sans clé n'envoie rien,
    /// et une clé sans case non plus : les deux conditions, jamais l'une.
    /// Ne touche pas au trousseau — c'est cette propriété que l'interface
    /// interroge, à chaque passe de rendu.
    var isFallbackEnabled: Bool {
        hasDeepLKey && UserDefaults.standard.bool(forKey: UDKey.deepLFallbackEnabled)
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
    /// Ce qu'une pré-traduction par clé a donné. Un `String?` suffisait tant
    /// que l'échec n'avait qu'une cause ; avec un service en ligne il en a
    /// trois, et le chemin par clé est justement celui où l'on reclique.
    /// Rendre `nil` pour un quota épuisé condamnait l'utilisateur à retenter
    /// sans jamais apprendre pourquoi.
    enum PreTranslation: Equatable {
        case proposal(String)
        case failed
        case fallbackStopped(BatchReport.FallbackStop)
    }

    @MainActor
    func preTranslate(mod: ModItem, locale: String,
                      row: TranslationCoverage.DiffRow) async -> PreTranslation {
        let credentials = deepLCredentials
        guard isLocalAIConfigured || credentials != nil else { return .failed }
        let request = LocalLLMClient.Request(
            model: localAIModelName,
            source: row.english,
            glossary: glossaryMatches(for: row.english, language: locale),
            sectionLabel: row.section)
        // Une seule session pour les deux moteurs : éphémère, sans proxy,
        // redirections refusées — des propriétés qu'on veut aussi côté DeepL.
        let session = LocalLLMEndpoint.makeSession()
        defer { session.finishTasksAndInvalidate() }
        let outcome = await TranslationEngine.translate(
            request, localBaseURL: localAIEndpoint, localSession: session,
            fallback: credentials, fallbackSession: session)
        log("Pré-traduction \(mod.folderName)/\(row.key) : \(outcome)", level: .info)
        switch outcome {
        case .translated(let proposal, _): return .proposal(proposal)
        case .quotaExhausted: return .fallbackStopped(.quotaExhausted)
        case .fallbackRateLimited: return .fallbackStopped(.rateLimited)
        case .fallbackUnauthorized: return .fallbackStopped(.unauthorized)
        case .refusedTokens, .endpointError: return .failed
        }
    }

    /// Ce qu'a donné la traduction d'une **sélection** de l'anglais.
    enum FragmentTranslation: Equatable {
        case proposal(String)
        /// La sélection emporte des marques du jeu, nommées pour que
        /// l'utilisateur sache autour de quoi resélectionner.
        case refusedMarkers([String])
        case nothingSelected
        /// Aucun secours en ligne réglé — cette voie n'a pas d'autre moteur.
        case noFallback
        case failed
        case fallbackStopped(BatchReport.FallbackStop)
    }

    /// Traduit un fragment de la source, la phrase entière servant de
    /// contexte — le canal que le service prévoit pour ça, et qu'il ne
    /// traduit pas.
    ///
    /// **Le service en ligne seulement, pas l'IA locale.** Le prompt local est
    /// bâti pour une valeur entière et rend volontiers la phrase là où on
    /// demandait un mot ; le paramètre `context` du service, lui, existe
    /// exactement pour cet usage. Sans clé, la voie n'est pas offerte plutôt
    /// que servie par un moteur qui ferait autre chose.
    @MainActor
    func translateFragment(_ selection: String,
                           inside sentence: String) async -> FragmentTranslation {
        let fragment: String
        switch TranslationFragment.prepare(selection) {
        case .ready(let prepared): fragment = prepared
        case .empty: return .nothingSelected
        case .containsMarkers(let markers): return .refusedMarkers(markers)
        }
        guard let credentials = deepLCredentials else { return .noFallback }
        let session = LocalLLMEndpoint.makeSession()
        defer { session.finishTasksAndInvalidate() }
        let outcome = await DeepLClient.translate(fragment, context: sentence,
                                                  credentials: credentials, session: session)
        log("Traduction d'un fragment (\(fragment.count) caractères) : \(outcome)", level: .info)
        switch outcome {
        case .translated(let text): return .proposal(text)
        case .quotaExhausted: return .fallbackStopped(.quotaExhausted)
        case .rateLimited: return .fallbackStopped(.rateLimited)
        case .unauthorized: return .fallbackStopped(.unauthorized)
        case .rejected, .transportError: return .failed
        }
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
        /// Combien de ces traductions viennent du secours en ligne — la
        /// provenance doit être visible, jamais devinée.
        let translatedByFallback: Int
        /// Le secours s'est arrêté en cours de lot, et pourquoi.
        let fallbackStop: FallbackStop?

        /// Ce qui a coupé le secours en ligne au milieu d'un lot. Deux
        /// causes, deux phrases : un quota épuisé se règle chez DeepL, un
        /// rythme refusé se règle en attendant.
        enum FallbackStop: Equatable {
            case quotaExhausted
            case rateLimited
            case unauthorized
        }
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
        // La garde admet le cas « pas d'IA locale, mais un secours réglé » :
        // sans ça, une machine sans modèle local n'aurait rien du tout.
        var fallbackCredentials = deepLCredentials
        guard isLocalAIConfigured || fallbackCredentials != nil else { return }
        // Jamais une valeur française existante (spec §8.2) : le planneur ne
        // retient que ce qui est absent ou vide.
        let eligible = TranslationBatchPlanner.eligibleRows(rows)
        var translated = 0
        var refused: [String] = []
        var errors = 0
        var softIgnored = 0
        var translatedByFallback = 0
        var fallbackStop: BatchReport.FallbackStop?
        var flags: [TranslationBaseline.ReviewFlag] = []
        // Une seule session pour tout le lot : `URLSession` retient fortement
        // son délégué jusqu'à invalidation, une par clé laissait autant de
        // sessions, de délégués et de pools de connexions vivants.
        let session = LocalLLMEndpoint.makeSession()
        defer { session.finishTasksAndInvalidate() }
        batchProgress = BatchProgress(done: 0, total: eligible.count)
        // La boucle porte un nom parce qu'on en sort depuis un `switch` :
        // un `break` nu y termine le `switch` et laisse la boucle courir.
        rowLoop: for (index, row) in eligible.enumerated() {
            // Le point d'arrêt : la clé en cours est déjà partie, la
            // suivante ne partira pas — son résultat, s'il arrive, n'est pas
            // écrit puisque l'écriture suit le retour.
            if Task.isCancelled { break }
            let matches = glossaryMatches(for: row.english, language: locale)
            let request = LocalLLMClient.Request(
                model: localAIModelName, source: row.english,
                glossary: matches, sectionLabel: row.section)
            let outcome = await TranslationEngine.translate(
                request, localBaseURL: localAIEndpoint, localSession: session,
                fallback: fallbackCredentials, fallbackSession: session)
            switch outcome {
            case .translated(let proposal, let by):
                if by == .fallback { translatedByFallback += 1 }
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
            case .quotaExhausted, .fallbackRateLimited, .fallbackUnauthorized:
                // Couper le secours pour le reste du lot : marteler un service
                // qui a déjà dit non ne le fera pas céder, et une clé refusée
                // le sera autant à la clé suivante.
                switch outcome {
                case .quotaExhausted: fallbackStop = .quotaExhausted
                case .fallbackRateLimited: fallbackStop = .rateLimited
                case .fallbackUnauthorized: fallbackStop = .unauthorized
                // Inatteignable : le `case` extérieur ne laisse passer que
                // les trois ci-dessus. Nommé plutôt que replié sur un
                // `default`, qui annoncerait un jour une clé refusée pour un
                // cas ajouté ailleurs — mauvais message, mauvais remède.
                case .translated, .refusedTokens, .endpointError: break
                }
                fallbackCredentials = nil
                errors += 1
                // Le local reste en course s'il est réglé. Sinon plus rien ne
                // peut traduire : continuer collectionnerait une erreur par
                // clé restante, là où le rapport a déjà dit ce qui s'est
                // passé et ce qu'il reste à faire.
                if !isLocalAIConfigured {
                    batchProgress = BatchProgress(done: index + 1, total: eligible.count)
                    break rowLoop
                }
            }
            batchProgress = BatchProgress(done: index + 1, total: eligible.count)
        }
        flushReviewFlags(&flags, mod: mod)   // le reliquat, arrêt compris
        batchReport = BatchReport(translated: translated, refusedRowIDs: refused,
                                  errors: errors, softGlossaryIgnored: softIgnored,
                                  translatedByFallback: translatedByFallback,
                                  fallbackStop: fallbackStop)
        log("Lot \(mod.folderName) : \(translated) traduites (dont \(translatedByFallback) "
            + "par le secours en ligne), \(refused.count) refusées (marques manquantes), "
            + "\(errors) erreurs, \(softIgnored) termes glossaire ignorés"
            + (fallbackStop.map { ", secours coupé : \($0)" } ?? ""),
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

    /// Ce qu'un export de lot produit : les données prêtes à écrire, ou
    /// pourquoi il n'y en a pas. Les deux « rien » ne se disent pas de la
    /// même façon à l'utilisateur — un mod fini et un encodage raté ne
    /// appellent pas la même suite.
    enum TranslationLotExport: Equatable {
        case nothingToTranslate
        case failed
        case data(Data)
    }

    /// Le lot d'un mod, prêt à être écrit sur disque.
    @MainActor
    func exportTranslationLot(mod: ModItem, locale: String,
                              rows: [TranslationCoverage.DiffRow]) -> TranslationLotExport {
        let lot = TranslationLot.build(mod: mod.folderName, language: locale,
                                       rows: rows, glossary: currentGlossary(language: locale))
        guard !lot.entries.isEmpty else { return .nothingToTranslate }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        do {
            return .data(try encoder.encode(lot))
        } catch {
            log("Lot non exporté pour \(mod.name) : \(error)", level: .warning)
            return .failed
        }
    }

    /// Ce qu'un import a produit, pour le dire à l'utilisateur.
    struct LotOutcome: Equatable {
        let written: Int
        let rejected: [TranslationLotImport.Rejection]
        /// Accepté par la relecture du lot, mais refusé par le chemin
        /// d'écriture lui-même (`saveTranslation`) — une divergence de
        /// marques dures, manquantes **ou en trop**, est déjà vue et nommée
        /// par la relecture ; ce qui reste ici, c'est l'échec propre à
        /// l'écriture : composant introuvable, disque. Compté à part de
        /// `rejected`, qui ne porte que les motifs de la relecture du lot.
        let writeFailures: Int
        /// Le fichier a été refusé en bloc — rien n'a été écrit.
        let refusal: TranslationLotImport.FileRefusal?

        /// Le fichier est passé, mais n'a rien produit : aucune écriture,
        /// aucun rejet — le cas ordinaire est un fichier rendu sans qu'aucune
        /// cible n'ait été remplie. Trois zéros ne se racontent pas en
        /// nombres : ça se dit.
        var producedNothing: Bool {
            refusal == nil && written == 0 && rejected.isEmpty && writeFailures == 0
        }
    }

    /// Écrit ce qu'un lot rapporte, par le chemin d'écriture existant (avec
    /// son `.bak` et son gate de marques), et pose « À relire » sur tout —
    /// une traduction machine reste une traduction machine.
    ///
    /// `sent` est **reconstruit** depuis `rows` — l'état courant du mod au
    /// moment de l'import, pas relu depuis le fichier reçu. C'est cette
    /// reconstruction qui fait toute la protection de `TranslationLotImport` :
    /// un lot exporté avant une mise à jour du mod ne peut pas écrire ses
    /// traductions sur des clés qui ont changé entretemps — chaque entrée
    /// rendue est appariée à cet état-là, et une clé changée ou disparue est
    /// écartée (`.sourceAltered`, `.unknownKey`).
    @MainActor
    func importTranslationLot(_ data: Data, mod: ModItem, locale: String,
                              rows: [TranslationCoverage.DiffRow]) -> LotOutcome {
        let sent = TranslationLot.build(mod: mod.folderName, language: locale,
                                        rows: rows, glossary: currentGlossary(language: locale))
        let report: TranslationLotImport.Report
        do {
            report = try TranslationLotImport.read(data, expecting: sent)
        } catch let refusal as TranslationLotImport.FileRefusal {
            log("Lot refusé pour \(mod.name) : \(refusal)", level: .warning)
            return LotOutcome(written: 0, rejected: [], writeFailures: 0, refusal: refusal)
        } catch {
            return LotOutcome(written: 0, rejected: [], writeFailures: 0,
                              refusal: .unreadable)
        }

        // Les rangées par identité, résolues par le même filtre que
        // `TranslationLot.build` — `writableRows` en est le miroir testé.
        let byIdentity = TranslationLotImport.writableRows(rows)

        var written = 0
        var writeFailures = 0
        var flags: [TranslationBaseline.ReviewFlag] = []
        for entry in report.accepted {
            guard let row = byIdentity[TranslationLotImport.identity(entry.component, entry.key)] else {
                // Ne devrait pas se produire : `TranslationLotImport.read` n'accepte
                // une entrée que si son identité correspond à une clé de `sent`, donc
                // à une rangée éligible de `rows` — mais un accepté qui se perd ici
                // serait compté nulle part, ni écrit ni écarté. Journalisé pour
                // rester visible si l'invariant se rompt un jour.
                log("Entrée acceptée introuvable parmi les rangées pour \(mod.name) — "
                    + "\(entry.key)", level: .warning)
                writeFailures += 1
                continue
            }
            let outcome = saveTranslation(mod: mod, locale: locale, row: row,
                                          value: entry.target,
                                          clearingReviewFlag: false)
            switch outcome {
            case .saved:
                written += 1
                flags.append(.init(component: entry.component, key: entry.key,
                                   source: entry.source, target: entry.target))
            case .blocked, .failed:
                // Accepté par la relecture, mais refusé par l'écriture. La
                // relecture et `saveTranslation` comparent désormais les
                // mêmes divergences de marques dures, dans les deux sens :
                // `.blocked` ne devrait donc plus survenir — il reste compté
                // plutôt que déclaré impossible, un invariant est plus utile
                // surveillé qu'affirmé. `saveTranslation` ne journalise pas
                // systématiquement ce refus (`.blocked` ne log rien) : le
                // faire ici explicitement, plutôt que de compter sur son
                // propre logging.
                log("Entrée acceptée mais non écrite pour \(mod.name) — "
                    + "\(entry.key) : \(outcome)", level: .warning)
                writeFailures += 1
            }
        }
        if !flags.isEmpty, let store = TranslationBaseline.defaultDirectory() {
            do {
                try TranslationBaseline.setReviewNeeded(flags, modFolderName: mod.folderName,
                                                        in: store)
            } catch {
                log("Drapeaux à relire non posés pour \(mod.name) : \(error)", level: .warning)
            }
        }
        log("Lot importé pour \(mod.folderName) : \(written) écrites, "
            + "\(report.rejected.count) écartées, \(writeFailures) refusées à l'écriture",
            level: .info)
        return LotOutcome(written: written, rejected: report.rejected,
                          writeFailures: writeFailures, refusal: nil)
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
        // Le store des profils est indexé par identifiant, pas par dossier :
        // sans cette traduction, traduire un mod ne changerait plus jamais le
        // pourcentage des profils qui le contiennent.
        if let uniqueId = mods.flattenedMods.first(where: { $0.folderName == folderName })?.uniqueId,
           !uniqueId.isEmpty {
            profileTranslationCoverage.removeValue(forKey: uniqueId.lowercased())
        }
    }

    // MARK: - Couverture française d'un profil (B3-T4)

    /// Ce que chaque profil affichera en français une fois appliqué.
    ///
    /// **Store séparé de `frenchCoverageByMod`, délibérément.** Ce dernier ne
    /// contient que les mods qui livrent *déjà* du français, et l'absence
    /// d'entrée y signifie « pas encore mesuré » — c'est le troisième état de
    /// la pastille de la liste (C1-T2). Or les mods qui font tout l'intérêt de
    /// cet écran sont ceux qui ont un `default.json` et **aucun** `fr.json` :
    /// 8, 28 et 15 sur ses trois profils. Les verser dans le cache commun
    /// ferait surgir une pastille « 0 % » sur autant de lignes de la liste des
    /// mods, dans un affichage déjà livré.
    ///
    /// Le grain diffère aussi : la pastille de la liste mesure un dossier de
    /// premier niveau **entier**, quand un profil raisonne par composant.
    @Published private(set) var profileTranslationSummaries: [UUID: ProfileTranslationSummary] = [:]

    /// `UniqueID` en minuscules → couverture propre au mod (mods imbriqués
    /// exclus, voir `ownDirectoriesOnly`). Mesuré une fois par mod : la passe
    /// lit tous les `default.json` et `fr.json` des mods concernés.
    private var profileTranslationCoverage: [String: TranslationCoverage.Coverage] = [:]
    private var profileTranslationTask: Task<Void, Never>?

    /// Le même travail, gardé **d'une session à l'autre** : sans lui, ouvrir
    /// la page des profils coûtait 15,7 s d'analyse à chaque lancement, mesuré
    /// sur le parc réel. Chaque entrée porte l'empreinte des fichiers de
    /// traduction du mod ; elle n'est réutilisée que si cette empreinte n'a pas
    /// bougé, et une entrée corrompue ne fait perdre que la mesure.
    private var profileTranslationCacheEntries: [String: TranslationCoverageCache.Entry] = [:]
    private var profileTranslationCacheLoaded = false

    /// Vrai pendant la passe de mesure : la page des profils montre un témoin
    /// plutôt qu'un pourcentage faux.
    @Published private(set) var isMeasuringProfileTranslation = false

    /// Mesure ce qui manque, puis republie les résumés.
    ///
    /// Appelée à l'affichage de la page des profils, pas au scan : lire les
    /// fichiers de traduction de 300 à 500 mods n'a pas sa place au lancement,
    /// et cette page n'est pas celle qu'on ouvre en premier.
    ///
    /// Seuls les mods qui **livrent une source** sont ouverts — `languages`
    /// contient `en` dès qu'un `default.json` existe, et il est déjà connu
    /// depuis le scan. C'est ce qui rend la passe abordable : sur son parc,
    /// plus de la moitié des mods n'ont aucun dossier `i18n`.
    ///
    /// Et ce qui reste est **mis en cache d'une session à l'autre**, validé par
    /// l'empreinte des fichiers de traduction : 15,7 s la première fois, 2,6 s
    /// ensuite — le prix du seul parcours des dossiers.
    @MainActor
    func refreshProfileTranslationCoverage() {
        guard !modProfiles.isEmpty, !gameDir.isEmpty else { return }
        // Une passe à la fois : la page peut réapparaître pendant la mesure.
        guard profileTranslationTask == nil else { return }

        let installed = mods.flattenedMods
        let profiles = modProfiles
        let byId = Dictionary(installed.map { ($0.uniqueId.lowercased(), $0) },
                              uniquingKeysWith: { first, _ in first })

        if !profileTranslationCacheLoaded, let url = TranslationCoverageCache.defaultFileURL() {
            profileTranslationCacheEntries = TranslationCoverageCache.load(from: url)
            profileTranslationCacheLoaded = true
        }

        let modsPath = URL(fileURLWithPath: (gameDir as NSString).appendingPathComponent("Mods"))
        var targets: [(id: String, directory: URL)] = []
        var queued = Set<String>()
        for profile in profiles {
            for uniqueId in profile.enabledModIds {
                let key = uniqueId.lowercased()
                guard !key.isEmpty, profileTranslationCoverage[key] == nil,
                      queued.insert(key).inserted, let mod = byId[key],
                      mod.languages.contains("en") || mod.languages.contains("fr")
                else { continue }
                targets.append((key, modsPath.appendingPathComponent(mod.physicalFolderName)))
            }
        }

        guard !targets.isEmpty else {
            publishProfileTranslationSummaries(profiles: profiles, installed: installed)
            return
        }

        isMeasuringProfileTranslation = true
        let cached = profileTranslationCacheEntries
        profileTranslationTask = Task.detached(priority: .utility) { [weak self] in
            var measured: [String: TranslationCoverage.Coverage] = [:]
            var freshEntries: [String: TranslationCoverageCache.Entry] = [:]
            for target in targets {
                if Task.isCancelled { break }
                // Les dossiers sont repérés **une seule fois** : ils servent à
                // l'empreinte comme à la mesure, et le parcours coûte à lui
                // seul 2,5 s sur le parc réel.
                //
                // `stoppingAtNestedMods` : un mod imbriqué dans un autre est
                // mesuré pour son propre compte, et ses clés compteraient deux
                // fois si son hôte les reprenait.
                let directories = I18nLocaleResolver.i18nDirectories(
                    inModDirectory: target.directory, stoppingAtNestedMods: true)
                let stamp = TranslationStamp.of(directories: directories)

                if let entry = TranslationCoverageCache.valid(cached[target.id], against: stamp) {
                    // Rien n'a bougé depuis la dernière mesure : on ne rouvre
                    // pas les fichiers. C'est tout l'intérêt du cache.
                    measured[target.id] = TranslationCoverage.Coverage(
                        total: entry.total, translated: entry.translated,
                        missing: [], empty: [], orphan: [], identicalToSource: [])
                    freshEntries[target.id] = entry
                    continue
                }

                guard let coverage = TranslationCoverage.coverage(inDirectories: directories,
                                                                  locale: "fr")
                else { continue }
                measured[target.id] = coverage
                if let stamp {
                    freshEntries[target.id] = TranslationCoverageCache.Entry(
                        stamp: stamp, total: coverage.total, translated: coverage.translated)
                }
            }
            await self?.finishProfileTranslationCoverage(measured,
                                                         entries: freshEntries,
                                                         profiles: profiles,
                                                         installed: installed)
        }
    }

    @MainActor
    private func finishProfileTranslationCoverage(_ measured: [String: TranslationCoverage.Coverage],
                                                  entries: [String: TranslationCoverageCache.Entry],
                                                  profiles: [ModProfile],
                                                  installed: [ModItem]) {
        profileTranslationCoverage.merge(measured) { _, new in new }
        profileTranslationCacheEntries.merge(entries) { _, new in new }
        profileTranslationTask = nil
        isMeasuringProfileTranslation = false
        persistProfileTranslationCache()
        // Les profils actuels, pas ceux capturés au départ : la page a pu en
        // voir renommer, dupliquer ou supprimer un pendant la mesure.
        publishProfileTranslationSummaries(profiles: modProfiles,
                                           installed: mods.flattenedMods)
    }

    /// Recalcule les résumés depuis le store — pur, sans disque.
    @MainActor
    private func publishProfileTranslationSummaries(profiles: [ModProfile],
                                                    installed: [ModItem]) {
        var summaries: [UUID: ProfileTranslationSummary] = [:]
        for profile in profiles {
            summaries[profile.id] = ProfileTranslationCoverage.summarize(
                profile: profile, installedMods: installed,
                coverageByUniqueId: profileTranslationCoverage)
        }
        profileTranslationSummaries = summaries
    }

    /// Écrit le cache sur disque, débarrassé des mods désinstallés — sans quoi
    /// le fichier ne ferait que grossir. Hors du fil principal : l'encodage et
    /// l'écriture n'ont pas à retenir l'interface.
    @MainActor
    private func persistProfileTranslationCache() {
        guard let url = TranslationCoverageCache.defaultFileURL() else { return }
        let installedIds = Set(mods.flattenedMods.map { $0.uniqueId }.filter { !$0.isEmpty })
        let entries = TranslationCoverageCache.pruned(profileTranslationCacheEntries,
                                                      keeping: installedIds)
        profileTranslationCacheEntries = entries
        Task.detached(priority: .utility) {
            TranslationCoverageCache.save(entries, to: url)
        }
    }

    /// Le résumé d'un profil, quand il a été mesuré.
    func translationSummary(for profile: ModProfile) -> ProfileTranslationSummary? {
        profileTranslationSummaries[profile.id]
    }

    /// Ouvre la fiche d'un mod **sur son onglet Traduction**, par dossier
    /// logique. Cherche dans les mods dépliés : un composant de pack se traduit
    /// comme un autre, et c'est lui que le profil désigne.
    @MainActor
    func openTranslation(forFolder folderName: String) {
        guard let mod = mods.flattenedMods.first(where: { $0.folderName == folderName })
        else { return }
        pendingTranslationFocus = folderName
        viewingModDetail = mod
    }

    /// Ouvre l'éditeur de configuration d'un mod **depuis un autre onglet**
    /// (le rapport de raccourcis, sur les Alertes système), par dossier
    /// logique. La bascule vers « Mods » remet `editingModConfig` à nil
    /// (piège documenté dans `MainView`) : la demande passe donc par
    /// `pendingConfigFocus`, reconstitué dans le `onChange` **après** la
    /// remise à zéro — même patron que `pendingTranslationFocus`. Rend
    /// `false` sans rien poser quand le mod n'est plus dans le parc : le
    /// rapport peut être périmé (mod désinstallé depuis le scan), et
    /// l'appelant n'a alors pas de raison de changer d'onglet.
    @MainActor
    func openModConfig(forFolder folderName: String) -> Bool {
        guard mods.flattenedMods.contains(where: { $0.folderName == folderName })
        else { return false }
        pendingConfigFocus = folderName
        return true
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
    /// Les mods installés plusieurs fois, reconstruit à chaque scan.
    ///
    /// Mesuré le 2026-08-25 : **7 identifiants sur 14 dossiers**, dont trois
    /// avec leurs deux copies actives (le mod Swim, à plat et dans son dossier
    /// de téléchargement). Rien ne le disait jusqu'ici.
    @Published private(set) var duplicateIndex: ModDuplicateIndex = .empty

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
    @Published var editingModConfig: ModItem? = nil {
        didSet {
            // Fermeture de l'éditeur ⇒ rescan du rapport de raccourcis
            // (ronde finale de revue). `saveConfig()` écrit le `config.json`
            // sans toucher `mods`, et la signature du scan ne couvre que
            // `folderName`/`isEnabled` : `scanIfNeeded` ne verrait rien, et
            // le rapport comme la pastille resteraient sur l'état d'avant —
            // le conflit que l'utilisateur vient de corriger encore affiché.
            // On force donc par `scan` (l'entrée sans condition de signature,
            // celle du bouton « Relancer l'analyse »). Transition vers nil
            // seulement : ouvrir l'éditeur n'a rien à rescanner, et un rescan
            // de trop après une annulation est sans coût (gardes
            // `isScanning`/`gameDir` dans `scan`, lecture détachée hors du
            // fil principal). `Task { @MainActor … }` comme le `didSet` de
            // `mods` : cette classe n'est pas `@MainActor`, le service l'est.
            guard oldValue != nil, editingModConfig == nil else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.keybindScanService.scan(mods: self.mods, gameDir: self.gameDir)
            }
        }
    }

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
    // Rangé sur le ViewModel — pas sur la vue — pour que le rapport survive
    // au changement d'onglet : `SystemAlertsView` vit dans une chaîne
    // if/else if de `MainView`, pas dans un `Group` à identité stable, donc
    // un `@StateObject` posé sur la section serait détruit et recréé à
    // chaque retour sur l'onglet (constat de revue C4-T2, ronde 1).
    // `KeybindScanService` porte désormais un `init()` explicite
    // `nonisolated` (même patron que `BisectionRunner.init(vm:)` juste en
    // dessous) : sans lui, l'init implicite d'une classe `@MainActor` est
    // elle-même isolée, et l'appeler ici — `StarHubTHViewModel` n'est pas
    // `@MainActor` au niveau de la classe — échoue à la compilation.
    let keybindScanService = KeybindScanService()
    
    init() {
        // `didSet` ne voit pas la valeur d'initialisation : sans cette ligne,
        // les verdicts relus au lancement seraient là sans que rien ne les
        // signale, jusqu'à la première vérification.
        compatibilityStatuses = modCompatibility.mapValues(\.status)
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
        // Le quota du dernier appel à Nexus : persisté justement parce que
        // l'app ne l'interroge plus qu'à la demande (B2-T6).
        let quota = NexusUpdateChecker.shared.cachedQuota()
        let account = NexusUpdateChecker.shared.cachedAccount()
        // User-saved overrides (per-mod custom categories / Nexus id links /
        // activation timestamps). Small dicts, but still UserDefaults I/O.
        let customCats = Self.loadCustomCategories()
        let customIds = Self.loadCustomModIds()
        let activationTs = Self.loadModActivationTimestamps()
        let favorites = Self.loadFavoriteMods()
        let managedConfigs = Self.loadProfileManagedConfigMods()
        let translations = InstalledTranslationStore.load()
        // Les verdicts d'incompatibilité (A5-T2) : même lot que les autres
        // registres utilisateur, lus ici hors fil principal.
        let conflictVerdicts = ModConflictVerdictsStore.load()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasNexusApiKey = hasKey
            self.nexusQuota = quota
            self.nexusAccount = account
            // Redemandé quand on ne sait pas, ou quand le renseignement a plus
            // d'une semaine : un compte peut devenir premium, ou cesser de
            // l'être.
            if account == nil || account?.isStale() == true { self.refreshNexusAccount() }
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
            self.favoriteMods = favorites
            self.profileManagedConfigMods = managedConfigs
            self.installedTranslations = translations
            self.modConflictVerdicts = conflictVerdicts
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

    /// `true` pendant qu'un `refreshSmapiLog()` tourne — piloter le bouton de
    /// la page des alertes système (spinner, anti double-clic).
    @Published private(set) var isRefreshingSmapiLog = false

    /// Relit le journal SMAPI et recalcule ce qui en découle : alertes
    /// système, diagnostics, mods signalés à jour. Sortie ciblée de
    /// `refresh()` pour la page des alertes — elle ne montre que ce que dit
    /// le journal, et rescanner le parc entier pour relire un fichier serait
    /// un contresens.
    ///
    /// `parseSMAPILog` est pensée pour un thread d'arrière-plan (`scanMods`
    /// l'appelle depuis le sien) : ses mutations `@Published` repartent sur
    /// main en interne. Le drapeau s'abaisse après son retour, donc après les
    /// mutations qu'elle a mises en file sur main — l'ordre est celui de la
    /// file.
    func refreshSmapiLog() {
        guard !isRefreshingSmapiLog else { return }
        isRefreshingSmapiLog = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.parseSMAPILog()
            DispatchQueue.main.async { self.isRefreshingSmapiLog = false }
        }
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

            // Ordre alphabétique unique, packs et mods simples mêlés — le
            // tri d'origine plaçait les packs en tête (retour du 2026-08-26).
            // C'est aussi l'ordre que le tri « Nom » de la liste suppose
            // déjà établi (voir le cas `.name` de ModListView).
            self.mods = scannedMods.alphabeticalListOrder
            self.rebuildDependencyIndexes()
            if self.selectedMod == nil, let first = self.mods.first {
                self.selectedMod = first
            }
            // Seed a default profile on first run (no-op after the first time,
            // and once mods have actually been scanned).
            self.ensureDefaultProfileIfNeeded()
        }

        // Le poids du parc, après la publication de la liste : c'est une
        // seconde traversée de `Mods/` (~3 s sur 100 000 fichiers), et elle ne
        // doit retarder l'affichage d'aucun mod.
        measureModsFolderSize()
    }

    // MARK: - Poids du parc (B2-T2)

    /// Ce que pèsent les mods, `nil` tant qu'aucune mesure n'a abouti.
    @Published private(set) var modsFolderSizes: ModsFolderSizes? = nil
    /// `true` pendant la traversée. Le pied de barre l'annonce : sans ça, il
    /// reste vide quelques secondes au lancement, ce qui se lit comme un bug.
    @Published private(set) var isMeasuringModsFolder: Bool = false

    /// Sérialise les mesures : `scanMods()` est appelé depuis 29 endroits
    /// (installation, suppression, bascule, application de profil…) et deux
    /// traversées simultanées de 100 000 fichiers ne serviraient à rien.
    private let modsSizeLock = NSLock()
    private var isModsSizeMeasureInFlight = false
    /// Une demande arrivée pendant une mesure n'est pas perdue : elle relance
    /// une passe à la fin, sinon le chiffre resterait celui d'avant l'action.
    private var modsSizeMeasureRequestedAgain = false

    /// Mesure le poids du parc en tâche de fond, en une passe à la fois.
    ///
    /// Accrochée à `scanMods()` plutôt qu'à un cache invalidé à la main : le
    /// scan est déjà le point de passage de tout ce qui change `Mods/`, et un
    /// schéma d'invalidation maison finirait par mentir sur un chemin oublié.
    func measureModsFolderSize() {
        // Sans jeu désigné, il n'y a rien à mesurer et rien à annoncer : même
        // le « Mesure en cours… » du pied de barre serait un clignotement pour
        // rien.
        guard !gameDir.isEmpty else { return }
        let alreadyRunning: Bool = modsSizeLock.withLock {
            if isModsSizeMeasureInFlight {
                modsSizeMeasureRequestedAgain = true
                return true
            }
            isModsSizeMeasureInFlight = true
            return false
        }
        guard !alreadyRunning else { return }

        let dir = gameDir
        DispatchQueue.main.async { self.isMeasuringModsFolder = true }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let sizes = ModsFolderSizer.measure(
                modsFolder: URL(fileURLWithPath: dir).appendingPathComponent("Mods"))
            let again: Bool = self.modsSizeLock.withLock {
                self.isModsSizeMeasureInFlight = false
                defer { self.modsSizeMeasureRequestedAgain = false }
                return self.modsSizeMeasureRequestedAgain
            }
            DispatchQueue.main.async {
                // Une mesure ratée (dossier absent) n'efface pas la précédente
                // pendant qu'une nouvelle passe est en route.
                if sizes != nil || !again { self.modsFolderSizes = sizes }
                self.isMeasuringModsFolder = again
                if again { self.measureModsFolderSize() }
            }
        }
    }

    /// Le poids d'un mod, `nil` s'il n'a pas été mesuré.
    ///
    /// **Sur le nom physique** : un mod en pause vit dans un dossier préfixé
    /// d'un point, et sur le parc réel cinq des huit plus gros mods sont en
    /// pause. Joindre sur `folderName` les afficherait tous à 0 octet.
    func sizeOnDisk(of mod: ModItem) -> Int64? {
        modsFolderSizes?.bytes(forPhysicalFolder: mod.physicalFolderName)
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
        var entries: [(uniqueId: String, folderName: String, isEnabled: Bool)] = []
        for m in mods {
            if m.isGroup, let children = m.children {
                for c in children {
                    let k = c.uniqueId.lowercased()
                    ids.insert(k)
                    states[k] = c.isEnabled
                    byId[k] = c
                    // `folderName` d'un composant **porte déjà** le nom du
                    // pack (`scanEntryForMods` construit
                    // `{pack}/{sous-chemin}`) : c'est lui qui distingue
                    // « Swim » de « Swim Mod-23169…/Swim ». Le préfixer une
                    // seconde fois donnerait un chemin qui n'existe pas.
                    entries.append((c.uniqueId, c.folderName, c.isEnabled))
                }
            } else {
                let k = m.uniqueId.lowercased()
                ids.insert(k)
                states[k] = m.isEnabled
                byId[k] = m
                entries.append((m.uniqueId, m.folderName, m.isEnabled))
            }
        }
        installedUniqueIds = ids
        installedModStates = states
        installedModsByUniqueId = byId
        // Les doublons sortent du **même parcours** : `states` et `byId` en
        // écrasent silencieusement un sur deux (le dernier gagne), si bien que
        // le seul endroit où l'information existe encore est ici, avant
        // l'aplatissement.
        duplicateIndex = ModDuplicateIndex.build(from: entries)
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
                // Même trou que `smapiLogDate` : sans ce reset, un journal
                // disparu laisserait les conflits de la lecture précédente
                // affichés à côté d'une date à `nil` — la même désynchronisation
                // que celle évitée plus bas entre date et liste.
                self.contentPatcherConflicts = []
            }
            return
        }

        let (smapiDiag, smapiDate, smapiStale) = computeSmapiDiagnostics(logContent: logContent, atPath: logPath)

        // Bloc « You can update N mods » — voir SmapiLogParser.updates(in:).
        let updates = SmapiLogParser.updates(in: logContent)
        // Ce scan (rafraîchissement ordinaire du parc, déclenché à chaque
        // `scanMods()`) alimente aussi `contentPatcherConflicts`, en plus de
        // `parseAndAppendSmapiLog` (onglet Journaux / veilleur) : la section
        // « Conflits » vit dans Alertes système, qui n'ouvre ni l'un ni
        // l'autre chemin explicitement. Sans ce second câblage, elle
        // afficherait une liste vide à côté d'une `smapiLogDate` fraîche —
        // « vérifié, aucun conflit » alors que rien n'a été lu pour cet axe.
        // Réutilise le même analyseur que l'autre chemin (`SmapiLogParser.parse`)
        // plutôt que d'écrire un second parseur de conflits.
        let conflictEntries = SmapiLogParser.parse(logContent)
        let conflicts = ContentPatcherConflicts.read(from: conflictEntries)
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
            // Par ordre alphabétique, et non dans celui du journal : SMAPI les
            // liste dans son ordre de chargement, qui n'a pas de sens pour qui
            // cherche un mod précis — et qui change d'un lancement à l'autre.
            // La liste des mises à jour Nexus est triée de même, dans
            // `republishUpdatesFromCache`.
            self.outOfDateMods = updates.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            self.smapiErrors = uniqueErrors
            self.smapiDiagnostics = smapiDiag
            self.smapiLogDate = smapiDate
            self.smapiLogStale = smapiStale
            // Publié dans le même bloc `main.async` que `smapiLogDate` :
            // date et liste doivent changer ensemble, jamais l'une sans
            // l'autre — voir le commentaire au-dessus de `conflictEntries`.
            self.contentPatcherConflicts = conflicts
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
    /// « Ce mod compte sur quelque chose qui n'est pas là » : une dépendance
    /// requise absente, ou installée mais en pause.
    ///
    /// Portée par le ViewModel et non par la liste, parce que deux écrans s'en
    /// servent désormais — le cadrage « Problèmes » et la pastille d'anomalie —
    /// et que deux définitions de « ce mod a un problème » finiraient par ne
    /// plus dire la même chose.
    ///
    /// Un mod en pause est écarté : il ne compte sur rien pour l'instant.
    func hasDependencyIssue(_ mod: ModItem) -> Bool {
        mod.isEnabled
            && (!getMissingDependencies(for: mod).isEmpty
                || !getDisabledDependencies(for: mod).isEmpty)
    }

    /// Ce qu'il faut signaler sur la ligne d'un mod, `nil` s'il n'y a rien.
    /// Voir `ModAnomalyReport` — les compteurs ne portent que sur la version
    /// installée.
    func anomaly(for mod: ModItem) -> ModAnomaly? {
        ModAnomalyReport.anomaly(for: mod, history: modErrorHistory,
                                 dependencyIssue: { self.hasDependencyIssue($0) },
                                 duplicates: duplicateIndex,
                                 compatibility: compatibilityStatuses)
    }



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

    /// Les deux temps d'une application de profil. Le second n'est pas de la
    /// décoration : le rescane d'un parc de près de mille mods dure, et sans
    /// lui la barre restait pleine, immobile, sans dire qu'il se passait encore
    /// quelque chose.
    enum ProfileApplyPhase: Equatable {
        /// Déplacement des dossiers de mods — un compte connu d'avance.
        case movingFolders
        /// Relecture de `Mods/` une fois les dossiers en place. L'avancement
        /// détaillé est celui que `scanMods` publie déjà dans `scanProgress`.
        case rescanning
    }

    struct ProfileApplyProgress: Equatable {
        let done: Int
        let total: Int
        let phase: ProfileApplyPhase
    }

    /// L'avancement de l'application d'un profil, `nil` au repos.
    ///
    /// Distinct de `bulkToggleProgress`, qui sert aussi de verrou de réentrance
    /// à `toggleAllMods` : les partager ferait qu'activer un profil bloquerait
    /// « tout activer », un couplage que personne n'a demandé. L'application
    /// d'un profil a son propre verrou, `isApplyingProfile`.
    @Published private(set) var profileApplyProgress: ProfileApplyProgress? = nil
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
                // Le poids mesuré suit le renommement : la clé physique
                // change, le contenu non. `m` est encore à son ancien état —
                // sa clé physique est l'ancienne, `dstName` la nouvelle.
                // Sans ce déplacement, fiche et rangées perdraient le poids
                // jusqu'au prochain scan complet.
                self.modsFolderSizes = self.modsFolderSizes?
                    .renamingFolder(from: m.physicalFolderName, to: dstName)
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

    /// Le mod dont la fiche doit s'ouvrir **sur son onglet Traduction**, par
    /// dossier logique. Posé par la couverture française d'un profil (B3-T4),
    /// où le geste attendu n'est pas « regarde ce mod » mais « traduis-le ».
    /// La fiche le consomme à son apparition ; il ne survit pas au passage
    /// d'un mod à l'autre.
    @Published var pendingTranslationFocus: String? = nil

    /// Le mod dont l'**éditeur de configuration** doit s'ouvrir après un
    /// changement d'onglet, par dossier logique. Posé par le rapport de
    /// raccourcis (Alertes système, T8) ; consommé et effacé par le
    /// `onChange` de `MainView` après sa remise à zéro des états de détail —
    /// poser `editingModConfig` avant la bascule ne sert à rien, la remise à
    /// zéro l'efface aussitôt (même piège que `pendingTranslationFocus`).
    @Published var pendingConfigFocus: String? = nil

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
            // Même raisonnement pour les conflits Content Patcher : `entries`
            // (non écrêté), pas `trimmedEntries`. Le cap sacrifie les TRACE en
            // premier donc les ERROR de conflit survivraient sans doute, mais
            // lire la liste complète retire la question — elle est déjà sous
            // la main ici. `smapiLogDate` (publié juste au-dessus) porte déjà
            // la date de ce journal, pas besoin d'un second champ.
            self.contentPatcherConflicts = ContentPatcherConflicts.read(from: entries)
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

    /// Les `folderName` logiques des packs d'un conflit, dans l'ordre du message.
    ///
    /// Content Patcher imprime des **noms d'affichage** (« Unlockable Bundles »),
    /// pas des `folderName` — sans ce pont, un conflit ne peut pas être comparé
    /// à `mods`. **Un nom non résolu est conservé tel quel**, pas jeté : mieux
    /// vaut un conflit approximativement nommé qu'un conflit tu. L'appelant
    /// distingue les deux en testant l'appartenance à `mods`.
    func conflictFolderNames(_ conflict: LoadConflict) -> [String] {
        conflict.packs.map { resolveModFolder(forLoggedName: $0)?.folderName ?? $0 }
    }

    /// La paire canonique d'un conflit du journal, quand il en représente
    /// une. `nil` pour un `betweenPacks` à plus de deux packs (forme
    /// « Multiple content packs want to load… ») : `ModConflictPair` ne
    /// modélise qu'une paire de deux, et choisir laquelle des C(n,2) paires
    /// internes représenterait le groupe serait une décision de
    /// modélisation que rien n'impose. Un tel conflit n'est donc jamais
    /// filtré par un verdict, dans aucun des deux sens (voir le commentaire
    /// de tête de `ModConflictSection`, qui documente ce cas limite).
    ///
    /// Extrait ici (tâche 9, ex-`ModConflictSection.pair(_:)`) : `Signaler`/
    /// `Écarter` sur la fiche d'un mod et `conflictWarning(for:)` en ont
    /// aussi besoin — deux copies de cette correspondance auraient fini par
    /// diverger (le dépôt en a déjà payé le prix ailleurs, voir la fiche
    /// mémoire sur les copies d'`isOsJunk`).
    func conflictPair(for conflict: LoadConflict) -> ModConflictPair? {
        let names = conflictFolderNames(conflict)
        switch conflict.kind {
        case .withinOnePack:
            guard let only = names.first else { return nil }
            return ModConflictPair(only, only)
        case .betweenPacks:
            guard names.count == 2 else { return nil }
            return ModConflictPair(names[0], names[1])
        }
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
            // Le statut appartient à la clé : une nouvelle clé, un nouveau
            // compte, éventuellement d'un autre type.
            nexusAccount = nil
            refreshNexusAccount()
        }
    }

    /// Relit le dernier quota Nexus relevé. Appelé à l'ouverture des réglages
    /// et sur `NexusUpdateChecker.quotaDidChange` : l'app ne parle à l'API Nexus
    /// qu'à la demande, la valeur ne bouge donc qu'après une action.
    func refreshNexusQuota() {
        nexusQuota = NexusUpdateChecker.shared.cachedQuota()
    }

    /// Redemande à Nexus si ce compte est premium.
    func refreshNexusAccount() {
        guard hasNexusApiKey || NexusUpdateChecker.shared.apiKey()?.isEmpty == false else { return }
        NexusUpdateChecker.shared.fetchAccount { [weak self] account in
            guard let account else { return }
            self?.nexusAccount = account
        }
    }

    /// Removes the stored Nexus Mods API key.
    func clearNexusApiKey() {
        NexusUpdateChecker.shared.clearApiKey()
        hasNexusApiKey = false
        nexusQuota = nil
        nexusAccount = nil
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
        let installed = allInstalledMods()
        let candidates = installed.map { mod in
            SmapiUpdateRequest.Candidate(
                uniqueId: mod.uniqueId,
                manifestVersion: mod.version,
                updateKeys: mod.updateKeys,
                isPaused: !mod.isEnabled,
                manualNexusId: nexusCustomModIds[mod.folderName])
        }
        let entries = SmapiUpdateRequest.entries(from: candidates, anchors: anchors)
        // Le parc **tel qu'interrogé**, figé avec la requête. Un scan peut
        // survenir entre l'envoi et la réponse (installation, activation,
        // profil appliqué) : relire la liste vivante à l'arrivée ferait
        // dépendre ce qu'on apprend d'un état que la réponse ne décrit pas.
        let folders = installed.map {
            NexusIdLearning.Folder(folderName: $0.folderName,
                                   uniqueId: $0.uniqueId,
                                   updateKeys: $0.updateKeys)
        }

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
                    self.applySmapiResults(mods, entries: entries, folders: folders)
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

    /// Le verdict de compatibilité qui **demande une décision** pour ce mod,
    /// et le composant qui le porte.
    ///
    /// Un pack rend celui du plus grave de ses composants, avec le composant
    /// lui-même : c'est le dossier de premier niveau qu'on active ou qu'on met
    /// en pause, mais c'est l'enfant qu'il faut nommer pour que l'utilisateur
    /// sache où regarder.
    ///
    /// `nil` couvre **deux cas très différents** — le mod est sain, ou
    /// smapi.io ne le connaît pas (552 mods du parc sur 840). Aucun appelant ne
    /// doit rendre l'un pour l'autre : ce qui s'affiche ici est un
    /// avertissement, jamais un satisfecit.
    func compatibilityWarning(for mod: ModItem) -> (component: ModItem,
                                                    verdict: ModCompatibility)? {
        let components = mod.isGroup ? (mod.children ?? []) : [mod]
        return components
            .compactMap { component -> (component: ModItem, verdict: ModCompatibility)? in
                guard let verdict = modCompatibility[component.uniqueId],
                      verdict.status.needsAttention else { return nil }
                return (component, verdict)
            }
            .max { $0.verdict.status.severity < $1.verdict.status.severity }
    }

    /// Les mods installés que smapi.io signale, par nom, du plus grave au moins.
    var compatibilityFlaggedMods: [(name: String, verdict: ModCompatibility)] {
        allInstalledMods()
            .compactMap { mod -> (name: String, verdict: ModCompatibility)? in
                guard let verdict = modCompatibility[mod.uniqueId],
                      verdict.status.needsAttention else { return nil }
                return (mod.name, verdict)
            }
            .sorted {
                $0.verdict.status.severity != $1.verdict.status.severity
                    ? $0.verdict.status.severity > $1.verdict.status.severity
                    : $0.name.lowercased() < $1.name.lowercased()
            }
    }

    /// Combien de mods installés smapi.io ne sait **pas** juger.
    ///
    /// Le chiffre qui donne sa mesure à tout le reste : 552 sur 840 au relevé
    /// du 2026-08-25. Une absence de signalement ne vaut pas quitus, et le dire
    /// est la seule façon honnête de présenter les sept qui le sont.
    var compatibilityUnknownCount: Int {
        allInstalledMods().filter { !$0.uniqueId.isEmpty && modCompatibility[$0.uniqueId] == nil }
            .count
    }

    /// L'avertissement à montrer **avant d'activer** ce mod, s'il y a lieu.
    ///
    /// `nil` quand le mod est déjà actif : mettre en pause un mod cassé est
    /// précisément ce qu'il faut faire, et le confirmer serait une friction
    /// pure. C'est aussi ce qui protège l'application d'un profil, qui bascule
    /// des centaines de dossiers sans qu'aucune alerte n'ait à s'ouvrir — elle
    /// passe par `toggleMod`, pas par cette porte.
    func activationWarning(for mod: ModItem) -> (component: ModItem,
                                                 verdict: ModCompatibility)? {
        guard !mod.isEnabled else { return nil }
        return compatibilityWarning(for: mod)
    }

    /// Le mod **déjà actif** avec lequel activer `mod` formerait un conflit
    /// connu, s'il y a lieu d'avertir. `nil` sinon.
    ///
    /// Fonction **séparée** d'`activationWarning` (décision du contrôleur,
    /// tâche 9), pas une extension de celle-ci : `activationWarning` rend un
    /// tuple `(component, verdict: ModCompatibility)` taillé pour le verdict
    /// de smapi.io et déjà consommé par `compatibilityGate`, un dialogue en
    /// production. Changer son type de retour ferait rippler cet écran pour
    /// aucun gain — les vues interrogent donc les deux séparément, et
    /// peuvent montrer l'une puis l'autre pour un même geste.
    ///
    /// Ne teste que l'état **actuel** du parc (`mods`), jamais le journal :
    /// un conflit du journal dit ce qui s'est passé à une partie précédente,
    /// pas si l'autre mod est encore actif aujourd'hui. Se déclenche sur une
    /// paire déclarée par l'utilisateur comme sur un conflit observé dans le
    /// journal, jamais sur une paire écartée — la décision elle-même vit
    /// dans `ModConflictVerdicts.activationConflict`, pure et testée.
    func conflictWarning(for mod: ModItem) -> ModItem? {
        guard !mod.isEnabled else { return nil }
        // Un pack s'active par son en-tête, mais un conflit du journal cite
        // ses composants (`SVE/Farm`, pas `SVE`) — sans les deux dans
        // `activating`, la moitié « journal » de la règle ne se
        // déclencherait jamais pour aucun pack.
        let activating = Set([mod.folderName] + (mod.children ?? []).map(\.folderName))
        let activeFolders = Set(mods.flattenedMods.filter(\.isEnabled).map(\.folderName))
        let candidates = modConflictVerdicts.declared + contentPatcherConflicts.compactMap(conflictPair)
        guard let otherFolder = modConflictVerdicts.activationConflict(
            activating: activating, candidates: candidates, activeFolders: activeFolders
        ) else { return nil }
        return mods.flattenedMods.first(where: { $0.folderName == otherFolder })
    }

    /// Transforme les verdicts de smapi.io en lignes affichables, et retient
    /// les motifs de non-vérifiabilité.
    private func applySmapiResults(_ mods: [SmapiUpdateResponse.Mod],
                                   entries: [SmapiUpdateRequest.Entry],
                                   folders: [NexusIdLearning.Folder]) {
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
        var unverifiable: [(uniqueId: String, name: String,
                            blocker: SmapiUpdateResponse.Blocker)] = []
        // Le matériau de la reprise Nexus (B2-T10). Seuls les mods **sans
        // suggestion** y entrent : une mise à jour trouvée est un verdict,
        // quoi qu'ait dit l'une des autres clés du mod.
        var blocked: [NexusFallbackCheck.Blocked] = []

        for mod in mods {
            if let first = mod.errors.first {
                // Même résolution de nom que les lignes de mise à jour : un
                // mod ne doit pas changer de nom d'un écran à l'autre.
                let name = ModManifest.resolveDisplayName(
                    installedName: installedName[mod.id],
                    metadataName: mod.metadata?.name,
                    uniqueId: mod.id)
                unverifiable.append((uniqueId: mod.id, name: name,
                                     blocker: SmapiUpdateResponse.blocker(for: first)))
                if mod.suggestedUpdate == nil {
                    blocked.append(NexusFallbackCheck.Blocked(
                        uniqueId: mod.id,
                        name: name,
                        // La version **affirmée**, celle qu'on a envoyée : d'ancre
                        // s'il y en a une. Comparer une autre valeur ferait
                        // reparaître une ligne que l'utilisateur a éteinte.
                        installedVersion: assertedVersion[mod.id] ?? "",
                        declaredKeys: declaredKeys[mod.id] ?? [],
                        metadataNexusId: mod.metadata?.nexusID,
                        errors: mod.errors))
                }
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
        // Même ordre que les mises à jour, et pour la même raison : la
        // réponse smapi.io suit l'ordre d'envoi, pas un ordre lisible.
        // Un seul tri, départagé par l'`UniqueID` : deux mods peuvent porter le
        // même nom, et `sorted` n'est pas stable en Swift — l'ordre de deux
        // homonymes changerait alors d'une vérification à l'autre.
        unverifiableMods = unverifiable.sorted {
            let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
            return byName == .orderedSame ? $0.uniqueId < $1.uniqueId : byName == .orderedAscending
        }

        // Les verdicts de compatibilité, que la réponse portait déjà et que
        // personne ne lisait. Fusionnés et non remplacés, pour la raison qui
        // vaut pour les lignes de mise à jour : un lot en échec laisse des mods
        // sans réponse, et les oublier effacerait un « cassé depuis la 1.6 »
        // que rien ne contredit.
        var verdicts = modCompatibility
        for mod in mods {
            guard let metadata = mod.metadata else { continue }
            if let verdict = ModCompatibility.from(status: metadata.compatibilityStatus,
                                                   brokeIn: metadata.brokeIn,
                                                   summary: metadata.compatibilitySummary) {
                verdicts[mod.id] = verdict
            } else {
                // smapi.io ne sait rien de ce mod : retirer un verdict devenu
                // caduc vaut mieux que d'afficher celui d'avant.
                verdicts.removeValue(forKey: mod.id)
            }
        }
        // Un mod désinstallé n'a plus de verdict à porter.
        verdicts = verdicts.filter { stillInstalled.contains($0.key) }
        modCompatibility = verdicts
        if !ModCompatibilityStore.save(verdicts) {
            // Les verdicts valent pour cette session, mais l'avertissement à
            // l'activation ne se rouvrira pas au prochain lancement.
            log("Verdicts de compatibilité non enregistrés : l'avertissement à "
                + "l'activation ne survivra pas à la fermeture", level: .warning)
        }

        // Le `metadata.nexusID` de la réponse ne servait qu'aux lignes de mise
        // à jour — pour leur bouton de téléchargement — et disparaissait pour
        // tous les autres mods. Il est désormais retenu.
        learnNexusIds(from: mods, folders: folders)

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
        log("Mises à jour : \(updates.count) sur \(mods.count) mods interrogés, \(unverifiable.count) non vérifiables",
            level: .info)

        recheckBlockedViaNexus(blocked)
    }

    /// B2-T10 — reprend par Nexus les mods que smapi.io n'a pas su juger.
    ///
    /// Le verdict de mise à jour est délégué à smapi.io ; quand elle répond une
    /// erreur, le mod reste sans verdict de **toute** source, et la fenêtre le
    /// taisait. Preuve levée le 2026-08-27 : *Powered Automation*, installé en
    /// 1.0.0, publié en 1.025, refusé par smapi.io faute de version indexable.
    ///
    /// Ce que la reprise coûte, mesuré sur le parc réel : sur 122 mods bloqués,
    /// **51 sont repris**, et ils se ramènent à **41 pages** — autant de
    /// requêtes, une fois par vérification manuelle. Le quota mesuré
    /// est de 2 000 requêtes par heure : la dépense est marginale, et elle
    /// reste **à la demande** — rien ici ne part sans que l'utilisateur ait
    /// lancé une vérification.
    ///
    /// Sans clé d'API, la reprise ne fait rien et ne signale aucune erreur : la
    /// clé ne sert qu'au téléchargement intégré et aux fiches, et un bandeau
    /// rouge sur une fonction d'appoint dirait le contraire.
    ///
    /// Les requêtes partent **en série**, pour la raison qui vaut déjà pour les
    /// lots smapi.io : une rafale de 39 requêtes parallèles ne gagnerait que le
    /// risque d'un 429. Un 429 arrête la reprise sur place — `fetchModInfo`
    /// refuse localement les suivantes de toute façon, mais les compter comme
    /// des échecs salirait le journal.
    private func recheckBlockedViaNexus(_ blocked: [NexusFallbackCheck.Blocked]) {
        let targets = NexusFallbackCheck.plan(blocked)
        guard !targets.isEmpty else { return }
        guard NexusUpdateChecker.shared.apiKey()?.isEmpty == false else {
            log("Reprise Nexus non tentée (aucune clé d'API) : \(blocked.count) mods "
                + "restent sans verdict", level: .info)
            return
        }
        let modCount = targets.reduce(0) { $0 + $1.mods.count }
        log("Reprise Nexus : \(modCount) mods sans verdict, \(targets.count) pages à interroger",
            level: .info)
        isCheckingNexusUpdates = true
        nexusCheckProgress = (0, targets.count)
        fetchNexusFallback(targets, index: 0, found: [], settled: [], failures: 0)
    }

    /// Une page après l'autre. `settled` retient les mods dont Nexus a bien
    /// rendu un verdict — mise à jour trouvée **ou** confirmation qu'il n'y en
    /// a pas : dans les deux cas le mod n'est plus « non vérifiable ».
    private func fetchNexusFallback(_ targets: [NexusFallbackCheck.Target],
                                    index: Int,
                                    found: [NexusUpdateChecker.ModUpdate],
                                    settled: Set<String>,
                                    failures: Int) {
        guard index < targets.count else {
            finishNexusFallback(found: found, settled: settled,
                                failures: failures, attempted: targets.count)
            return
        }
        let target = targets[index]
        NexusUpdateChecker.shared.fetchSingleMod(modId: target.nexusId) { [weak self] result in
            guard let self else { return }
            var found = found
            var settled = settled
            var failures = failures
            switch result {
            case .success(let version, _, let extra):
                // Une page **sans version** n'est pas un verdict. L'API Nexus
                // exige seulement que le champ existe, et une chaîne vide s'y
                // décode sans broncher : la tenir pour « à jour » retirerait le
                // mod des invérifiables sur un quitus inventé — le défaut même
                // que cette reprise existe pour supprimer.
                let page = version.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !page.isEmpty else {
                    failures += 1
                    self.log("Reprise Nexus : la page \(target.nexusId) ne publie aucune "
                             + "version — \(target.mods.count) mod(s) toujours sans verdict",
                             level: .warning)
                    break
                }
                let rows = NexusFallbackCheck.rows(for: target,
                                                   pageVersion: page,
                                                   uploadedTime: extra.uploadedTime)
                self.logNexusFallbackVerdicts(target, pageVersion: page, updates: rows)
                found += rows
                settled.formUnion(target.mods.map(\.uniqueId))
            case .rateLimited(let retryAfter):
                // Inutile d'insister : les suivantes seraient refusées
                // localement, et ce qui a abouti reste acquis.
                self.log("Reprise Nexus interrompue par la limitation de débit "
                         + "(\(Int(retryAfter)) s) après \(index) page(s)", level: .warning)
                self.finishNexusFallback(found: found, settled: settled,
                                         failures: failures, attempted: index)
                return
            case .noApiKey, .error:
                failures += 1
            }
            self.nexusCheckProgress = (index + 1, targets.count)
            self.fetchNexusFallback(targets, index: index + 1,
                                    found: found, settled: settled, failures: failures)
        }
    }

    /// Nomme, mod par mod, ce que la page vient de trancher.
    ///
    /// Les compteurs seuls ne répondaient pas à la seule question qui se pose
    /// devant eux : *lequel ?* Une mise à jour se retrouve dans la fenêtre,
    /// mais un mod **confirmé à jour** n'apparaît nulle part ailleurs — et
    /// c'est précisément le verdict qu'on venait de gagner, sur des mods qui
    /// n'en avaient d'aucune source. Le taire refaisait, en plus petit, le
    /// défaut que toute cette reprise corrige.
    ///
    /// Une ligne par mod plutôt qu'une liste sur une seule : le journal en
    /// tient 2 000 et sait chercher, si bien qu'un nom se retrouve à coup sûr
    /// — ce qu'une ligne de cinquante noms rendrait illisible. Les deux
    /// versions figurent dans les deux cas, pour que la comparaison soit
    /// vérifiable plutôt que crue sur parole.
    private func logNexusFallbackVerdicts(_ target: NexusFallbackCheck.Target,
                                          pageVersion: String,
                                          updates: [NexusUpdateChecker.ModUpdate]) {
        let outdated = Set(updates.map(\.uniqueId))
        for mod in target.mods {
            // Un manifeste sans champ `Version` existe : ne pas afficher un
            // blanc là où le lecteur attend un numéro.
            let installed = mod.installedVersion.isEmpty ? "version inconnue" : mod.installedVersion
            if outdated.contains(mod.uniqueId) {
                log("Reprise Nexus : \(mod.name) — \(installed) → \(pageVersion) "
                    + "(page \(target.nexusId))")
            } else {
                log("Reprise Nexus : \(mod.name) à jour (installé \(installed), "
                    + "page \(pageVersion))")
            }
        }
    }

    /// Publie ce que la reprise a trouvé, et retire de la liste des « non
    /// vérifiables » les mods qu'elle a tranchés.
    private func finishNexusFallback(found: [NexusUpdateChecker.ModUpdate],
                                     settled: Set<String>,
                                     failures: Int,
                                     attempted: Int) {
        isCheckingNexusUpdates = false
        nexusCheckProgress = nil

        if !found.isEmpty {
            // Les lignes Nexus se **substituent** aux lignes précédentes des
            // mêmes mods plutôt que de s'y ajouter : le cache est indexé par
            // `UniqueID`, et deux lignes de même identité donneraient des
            // doublons à un `ForEach`.
            let replaced = Set(found.map(\.uniqueId))
            let kept = NexusUpdateChecker.shared.cachedUpdates()
                .filter { !replaced.contains($0.uniqueId) }
            NexusUpdateChecker.shared.replaceCachedUpdates(
                (kept + found).sorted { $0.name.lowercased() < $1.name.lowercased() })
            republishUpdatesFromCache()
        }
        if !settled.isEmpty {
            unverifiableMods = unverifiableMods.filter { !settled.contains($0.uniqueId) }
        }

        // Un décompte honnête : ce qui a été tenté, ce qui a été trouvé, ce qui
        // a été confirmé à jour, ce qui a échoué. Une reprise silencieuse
        // laisserait croire qu'elle n'a rien trouvé alors qu'elle n'a pas
        // abouti.
        log("Reprise Nexus : \(attempted) page(s) interrogée(s), "
            + "\(found.count) mise(s) à jour trouvée(s), "
            + "\(settled.count - found.count) mod(s) confirmé(s) à jour, "
            + "\(failures) échec(s)", level: failures > 0 ? .warning : .info)
    }

    /// Retient l'identifiant Nexus que smapi.io connaît, pour les mods dont le
    /// manifeste n'en déclare aucun.
    ///
    /// Sans page Nexus, un mod n'a ni suivi de version, ni bouton vers sa page,
    /// ni recherche de traduction — et rien ne le disait. Mesuré sur le parc
    /// réel : **148 mods sans clé Nexus dans leur manifeste, dont 30 que
    /// smapi.io identifie**. Dix avaient déjà été renseignés à la main, et les
    /// dix concordent exactement ; restent **20 identifiants gratuits perdus**.
    ///
    /// La décision vit dans `NexusIdLearning` (Core, testé) : le manifeste fait
    /// foi, une saisie manuelle ne se fait jamais écraser, et rien n'est
    /// réécrit à l'identique — sinon chaque vérification toucherait les
    /// préférences pour rien.
    /// - Parameter folders: le parc **tel qu'interrogé**, figé avec la requête.
    private func learnNexusIds(from responses: [SmapiUpdateResponse.Mod],
                               folders: [NexusIdLearning.Folder]) {
        var knownIds: [String: Int] = [:]
        for response in responses {
            if let id = response.metadata?.nexusID { knownIds[response.id] = id }
        }
        guard !knownIds.isEmpty else { return }

        let plan = NexusIdLearning.plan(knownIds: knownIds,
                                        folders: folders,
                                        existingOverrides: nexusCustomModIds)
        guard !plan.isEmpty else { return }

        // Une seule assignation : `nexusCustomModIds` vide le cache de
        // catégories à chaque écriture, et le plan en porte parfois vingt.
        var updated = nexusCustomModIds
        for (folderName, id) in plan.sorted(by: { $0.key < $1.key }) {
            updated[folderName] = id
            log(String(format: L(L10n.VM.nexusIdLearned), folderName, id))
        }
        nexusCustomModIds = updated
        Self.saveCustomModIds(updated)
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
        // L'ordre alphabétique vient de `NexusUpdateConsolidation`, où il
        // est testé — pas d'un second tri ici, qui divergerait un jour.
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
    /// Le nom du mod derrière un identifiant Nexus, quand l'app le connaît.
    ///
    /// Un journal qui ne dit que « mod 41318 » oblige à ouvrir Nexus pour
    /// savoir de quoi il parle — or l'app a le nom sous la main, par trois
    /// chemins. Ils sont essayés du plus sûr au plus lointain :
    ///
    /// 1. **un mod installé** qui porte cet identifiant — c'est le nom que
    ///    l'utilisateur voit dans sa liste, donc celui qu'il reconnaîtra ;
    /// 2. **la liste des mises à jour**, qui porte le nom Nexus.
    ///
    /// Pas de troisième chemin par le cache sur disque : `nexusUpdates` en est
    /// justement rempli au lancement, et le relire ici n'aurait fait qu'ajouter
    /// un accès au singleton pour la même réponse.
    ///
    /// `nil` quand aucun ne répond : un `nxm://` pour un mod qu'on n'a jamais
    /// vu ne peut pas être nommé avant son téléchargement, et inventer un nom
    /// serait pire que l'identifiant nu.
    func nexusModDisplayName(for modId: Int) -> String? {
        let wanted = String(modId)
        // Les mods de premier niveau d'abord : pour un composant de pack, le
        // nom du pack est celui qui parle — c'est lui qui a une page Nexus.
        for mod in mods where effectiveNexusModId(for: mod) == wanted {
            return mod.name
        }
        for mod in mods.flattenedMods where effectiveNexusModId(for: mod) == wanted {
            return mod.name
        }
        if let update = nexusUpdates.first(where: { $0.nexusModId == wanted }), !update.name.isEmpty {
            return update.name
        }
        return nil
    }

    /// Un message de journal qui nomme le mod quand c'est possible, et se
    /// rabat sur l'identifiant seul sinon. Les deux formats sont fournis par
    /// l'appelant : seule une vue résout `L(…)`, et les deux phrases n'ont pas
    /// le même nombre de substitutions.
    private func nexusDownloadLogMessage(named: String, plain: String, modId: Int) -> String {
        guard let name = nexusModDisplayName(for: modId) else {
            return String(format: L(plain), Int64(modId))
        }
        return String(format: L(named), name, Int64(modId))
    }

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
    func installedDate(for mod: ModItem) -> Date? { mod.effectiveInstallDate }

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
        // **Avant** les deux refus qui suivent — pack multi-dossiers,
        // manifeste qui fait foi. Aucun des deux ne change le fait qui
        // intéresse la vitrine : ce mod vient d'être installé depuis cette
        // page, et sa pastille ne doit pas attendre le prochain scan.
        recentNexusInstalls.insert(modId)

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
            sourceModId: modId,
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
        log(nexusDownloadLogMessage(named: L10n.VM.nexusDlStartingNamed,
                                    plain: L10n.VM.nexusDlStarting, modId: link.modId))
        nexusDownloadInFlight = nexusDownloader.download(
            modId: link.modId, fileId: link.fileId, game: link.gameDomain,
            key: link.key, expires: link.expires,
            onProgress: { [weak self] received, expected in
                self?.noteNexusDownloadProgress(received: received, expected: expected,
                                                modId: link.modId)
            }) { [weak self] result in
            self?.handleNexusDownloadResult(result, modId: link.modId)
        }
    }

    /// In-app download for the current game via the API key alone (Nexus
    /// Premium required for a direct link). fileId nil → main file resolved.
    func downloadModFromNexus(nexusId: Int) {
        if rejectNexusDownloadIfBusy() { return }
        isDownloadingFromNexus = true
        downloadingNexusModId = nexusId
        log(nexusDownloadLogMessage(named: L10n.VM.nexusDlStartingNamed,
                                    plain: L10n.VM.nexusDlStarting, modId: nexusId))
        nexusDownloadInFlight = nexusDownloader.download(
            modId: nexusId, fileId: nil, game: "stardewvalley", key: nil, expires: nil,
            onProgress: { [weak self] received, expected in
                self?.noteNexusDownloadProgress(received: received, expected: expected,
                                                modId: nexusId)
            }) { [weak self] result in
            self?.handleNexusDownloadResult(result, modId: nexusId)
        }
    }

    /// Shared completion for both Nexus download entry points: hops to main,
    /// clears the progress flag, and on success stashes the downloaded zip +
    /// its Nexus source for the install sheet, or surfaces a localized error.
    private func handleNexusDownloadResult(_ result: Result<URL, NexusDownloadError>, modId: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.clearNexusDownloadState()
            switch result {
            case .success(let zipURL):
                self.pendingDownloadedZip = zipURL
                self.pendingNexusSource = NexusInstallSource(modId: modId)
                self.log(self.nexusDownloadLogMessage(named: L10n.VM.nexusDlCompletedNamed,
                                                      plain: L10n.VM.nexusDlCompleted,
                                                      modId: modId))
            case .failure(.cancelled):
                // Annuler son propre téléchargement n'est pas une panne : une
                // alerte sur un geste volontaire serait du bruit. La ligne de
                // journal, elle, garde la trace de ce qui n'a pas été installé.
                self.log(self.nexusDownloadLogMessage(named: L10n.VM.nexusDlCancelledNamed,
                                                      plain: L10n.VM.nexusDlCancelled,
                                                      modId: modId))
            case .failure(let error):
                let message = self.nexusDownloadMessage(error)
                self.showModal(message: message)
                self.log(message, level: .warning)
            }
        }
    }

    /// Relève la progression du téléchargement en cours.
    ///
    /// Appelée depuis la file de délégué d'`URLSession`, donc **hors du fil
    /// principal** : le saut est explicite, sans quoi trois `@Published`
    /// seraient mutés depuis un autre fil.
    ///
    /// `expected` vaut `-1` quand le serveur n'annonce pas la taille — le cas
    /// est fréquent sur un CDN. `DownloadProgress` le traduit en « taille
    /// inconnue » : ni pourcentage, ni temps restant, seulement le volume et
    /// le débit, qui sont vrais.
    nonisolated private func noteNexusDownloadProgress(received: Int64, expected: Int64,
                                                       modId: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.nexusDownloadRate.record(totalBytes: received, at: Date())
            self.nexusDownloadProgress = DownloadProgress(
                bytesReceived: received,
                totalBytes: expected,
                bytesPerSecond: self.nexusDownloadRate.bytesPerSecond,
                nexusModId: modId)
        }
    }

    /// Remet les quatre témoins du téléchargement au repos.
    ///
    /// Une seule fonction pour les quatre : ils étaient déjà remis à zéro à
    /// trois endroits différents, et le jour où l'un d'eux serait oublié,
    /// `rejectNexusDownloadIfBusy` condamnerait le bouton pour la session.
    @MainActor
    private func clearNexusDownloadState() {
        isDownloadingFromNexus = false
        downloadingNexusModId = nil
        nexusDownloadProgress = nil
        nexusDownloadInFlight = nil
        nexusDownloadRate.reset()
    }

    /// Annule le téléchargement en cours. Sans effet s'il n'y en a pas.
    ///
    /// Ne remet rien à zéro ici : `URLSession` rapportera l'annulation par le
    /// chemin d'échec habituel, et c'est lui qui doit conclure. Le faire des
    /// deux côtés rouvrirait la porte à un état remis au repos pendant qu'un
    /// transfert continue.
    @MainActor
    func cancelNexusDownload() {
        nexusDownloadInFlight?.cancel()
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
        // Ne devrait jamais s'afficher : les appelants traitent `.cancelled`
        // avant d'en arriver là, une alerte sur un geste volontaire étant du
        // bruit. Le cas est là pour que le switch reste exhaustif — c'est lui
        // qui a fait échouer la compilation quand ce cas est apparu, plutôt
        // que de laisser passer une chaîne anglaise en silence.
        case .cancelled:           return L(L10n.VM.nexusDlCancelledError)
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
        // **Le détail technique part au journal**, que la modale ne montre pas :
        // le statut de l'extracteur, son « Illegal byte sequence », le chemin
        // qu'il n'a pas su créer. Sans cela, un échec d'installation ne laissait
        // aucune trace consultable — il fallait relancer l'app depuis un
        // terminal pour voir ce que l'outil avait dit.
        //
        // Ici, et non chez les sept appelants : un seul aurait fini par
        // l'oublier. Cette fonction est appelée une fois par erreur affichée.
        log(Self.technicalInstallDetail(error), level: .error)

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

    /// Ce qu'on écrit au journal pour une erreur d'installation : la
    /// description **technique**, en anglais, celle que porte l'erreur
    /// elle-même. Le message localisé, lui, va à l'utilisateur ; le journal
    /// sert à comprendre, et à être recopié dans un rapport.
    private static func technicalInstallDetail(_ error: Error) -> String {
        let detail = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        return "Installation: \(detail)"
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

    // MARK: - Traductions communautaires (A3-T3)

    /// Ce qui est posé sur quel mod. Relu au lancement, réécrit à chaque dépôt
    /// ou retrait — c'est la seule trace : la perdre rendrait toute
    /// désinstallation impossible.
    @Published private(set) var installedTranslations = InstalledTranslationRegistry()
    /// Les traductions françaises trouvées pour un mod, par `folderName`.
    /// Vidé à chaque nouvelle recherche : ce n'est pas un cache, c'est le
    /// résultat de la dernière question posée.
    @Published private(set) var translationHits: [String: [NexusModSearch.Hit]] = [:]
    /// Les résultats **correspondant à ce qui est déjà posé**, retirés des
    /// propositions mais gardés : c'est là que se lit une version plus récente,
    /// et c'est vers eux que rattache le menu.
    @Published private(set) var translationInstalledHits: [String: [NexusModSearch.Hit]] = [:]
    /// Les mods dont une recherche est en cours.
    ///
    /// Un ensemble, pas un seul nom : la fiche désactive ses boutons **mod par
    /// mod**, si bien qu'un verrou unique rendait muet le clic sur un second
    /// mod — le bouton restait actif et ne faisait rien.
    @Published private(set) var searchingTranslations: Set<String> = []
    /// Les mods dont une traduction s'installe ou se retire.
    @Published private(set) var busyTranslations: Set<String> = []

    /// La traduction posée sur ce mod, s'il y en a une.
    func translation(for mod: ModItem) -> InstalledTranslation? {
        installedTranslations.translation(forHost: mod.folderName)
    }

    /// `true` quand une version plus récente que celle en place a été trouvée.
    ///
    /// Sur les **dates Nexus**, jamais sur les numéros de version : beaucoup de
    /// traducteurs reprennent le numéro du mod traduit, ou ne le bougent pas.
    func translationUpdateAvailable(for mod: ModItem) -> NexusModSearch.Hit? {
        guard let installed = translation(for: mod) else { return nil }
        // L'union des deux moitiés : le résultat qui porte la mise à jour est
        // par nature celui qu'on a retiré des propositions.
        let seen = (translationHits[mod.folderName] ?? [])
            + (translationInstalledHits[mod.folderName] ?? [])
        return seen.first {
            $0.modId == installed.nexusModId
                && InstalledTranslationRegistry.isNewer($0.updatedAt, than: installed.updatedAt)
        }
    }

    /// Ce qu'une recherche de suppléments a rendu — **et ce qu'elle n'a pas vu**.
    ///
    /// Trois nombres, parce qu'aucun ne suffit seul à dire la vérité :
    /// - `hits` sont les candidats retenus après avoir écarté les traductions ;
    /// - `received` est ce que la page portait, plafonné par la requête ;
    /// - `serverTotal` est ce que Nexus annonce pour ce nom, traductions
    ///   comprises — 428 pour « Content Patcher ».
    ///
    /// Annoncer `hits.count` seul ferait passer une poignée pour une
    /// exhaustivité ; annoncer `serverTotal` seul promettrait des suppléments
    /// là où il n'y a que des traductions. Il faut les deux.
    struct SupplementSearch {
        let hits: [NexusModSearch.Hit]
        /// Ceux que le parc porte déjà — montrés à part plutôt que proposés.
        let alreadyInstalled: [NexusModSearch.Hit]
        let received: Int
        let serverTotal: Int

        /// `true` quand Nexus en avait plus que la page n'en a rapporté.
        var isCapped: Bool { serverTotal > received }
    }
    /// Les suppléments trouvés pour un mod, par `folderName`.
    @Published private(set) var supplementSearches: [String: SupplementSearch] = [:]
    /// Les mods dont une recherche de suppléments est en cours.
    @Published private(set) var searchingSupplements: Set<String> = []

    /// Ce qu'une recherche d'identité a rendu — voir
    /// `NexusModSearch.identityCandidates`.
    ///
    /// `received` et `serverTotal` sont là pour la même raison que dans
    /// `SupplementSearch` : la liste est plafonnée par la requête, et taire le
    /// total ferait passer une poignée pour une réponse complète.
    struct IdentitySearch {
        let candidates: [NexusModSearch.IdentityCandidate]
        let received: Int
        let serverTotal: Int

        var isCapped: Bool { serverTotal > received }
    }
    /// Les fiches Nexus candidates pour un mod sans identifiant, par `folderName`.
    @Published private(set) var identitySearches: [String: IdentitySearch] = [:]
    /// Les mods dont une recherche d'identité est en cours.
    @Published private(set) var searchingIdentity: Set<String> = []

    /// Cherche sur Nexus la fiche d'un mod qui n'en déclare aucune.
    ///
    /// Sans tag : c'est le mod lui-même qu'on cherche, pas ce qui gravite
    /// autour. Tout le tri est au retour — les traductions écartées, l'auteur
    /// en indice, rien d'écrit d'autorité.
    ///
    /// ⚠️ **Deux mods sur trois ne rendront rien**, et c'est la réponse la plus
    /// fréquente : mesuré sur les 83 mods du parc encore sans identifiant, 55
    /// sont introuvables par leur nom. La vue doit le dire, sans quoi le bouton
    /// passera pour cassé.
    func searchNexusIdentity(for mod: ModItem) {
        guard !searchingIdentity.contains(mod.folderName) else { return }
        searchingIdentity.insert(mod.folderName)
        NexusSearchClient.search(name: mod.name) { [weak self] result in
            guard let self else { return }
            self.searchingIdentity.remove(mod.folderName)
            switch result {
            case .success(let page):
                self.identitySearches[mod.folderName] = IdentitySearch(
                    candidates: NexusModSearch.identityCandidates(among: page.hits,
                                                                  modName: mod.name,
                                                                  modAuthor: mod.author),
                    received: page.hits.count,
                    serverTotal: page.totalCount)
            case .failure(let error):
                // Une panne n'est pas une absence : ne rien afficher vaut mieux
                // qu'afficher « aucun résultat » pour une requête qui a échoué.
                self.identitySearches[mod.folderName] = nil
                self.log("Recherche de la fiche Nexus : \(error)", level: .warning)
                self.showModal(message: self.L(L10n.Mods.translationSearchFailed))
            }
        }
    }

    /// Referme les propositions de fiche Nexus d'un mod.
    func dismissIdentityResults(for mod: ModItem) {
        identitySearches[mod.folderName] = nil
    }

    /// Retient la fiche que l'utilisateur a désignée, et va chercher ce qu'elle
    /// dit du mod.
    ///
    /// Passe par `setCustomNexusModId`, le chemin d'une saisie manuelle : c'en
    /// est une, faite d'un clic au lieu du clavier. La liste se referme, sans
    /// quoi elle continuerait de proposer ce qui vient d'être choisi.
    ///
    /// `loadModDetail`, pour la même raison que dans `commitDraft` : la
    /// description et le changelog n'ont été chargés qu'en ouvrant le volet,
    /// sous l'ancien identifiant (vide — donc texte du manifeste local, sans
    /// chargement distant). Sans ce rechargement, la fiche nouvellement liée
    /// resterait muette jusqu'à la prochaine navigation.
    func adoptNexusIdentity(_ candidate: NexusModSearch.IdentityCandidate, for mod: ModItem) {
        setCustomNexusModId(for: mod, modId: String(candidate.hit.modId))
        dismissIdentityResults(for: mod)
        fetchMetadata(forNexusModId: String(candidate.hit.modId)) { _ in }
        loadModDetail(for: mod)
        log(String(format: L(L10n.VM.nexusIdLearned), mod.folderName, String(candidate.hit.modId)))
    }

    /// Referme les propositions de traduction d'un mod.
    ///
    /// **Ne jette que ce qui est affiché.** `translationInstalledHits` reste :
    /// il ne se voit pas, mais c'est lui qui porte la pastille « une version
    /// plus récente existe » sur la ligne en place. Refermer une liste veut
    /// dire « j'ai fini de chercher », pas « oublie ce que tu as appris ».
    func dismissTranslationResults(for mod: ModItem) {
        translationHits[mod.folderName] = nil
    }

    /// Referme les propositions de suppléments d'un mod.
    ///
    /// Les greffes du registre continuent de s'afficher : elles ne viennent pas
    /// de la recherche, elles viennent de ce qui est posé sur le disque.
    func dismissSupplementResults(for mod: ModItem) {
        supplementSearches[mod.folderName] = nil
    }

    /// Les identifiants Nexus que le parc déclare, pour reconnaître un
    /// supplément **installé comme un mod à part entière**.
    ///
    /// Calculé à la demande : une recherche part sur un clic, pas sur un rendu
    /// de liste. En faire un index permanent coûterait à chaque scan pour un
    /// usage rare.
    private func installedNexusIds() -> Set<Int> {
        Set(allInstalledMods().compactMap { Int(resolvedNexusModId(for: $0)) })
            .union(recentNexusInstalls)
    }

    /// Retire des propositions la traduction déjà en place.
    ///
    /// Sur son identifiant Nexus quand il est connu, sur son nom sinon — et le
    /// nom est le cas courant : sur un compte gratuit tout s'installe à la
    /// main, donc sans identifiant.
    private func withoutInstalledTranslation(_ hits: [NexusModSearch.Hit],
                                             for mod: ModItem) -> [NexusModSearch.Hit] {
        guard let installed = translation(for: mod) else {
            translationInstalledHits[mod.folderName] = []
            return hits
        }
        // **Retirée des propositions, pas jetée.** C'est dans cette moitié que
        // vit le résultat correspondant à la traduction posée — celui qui dit
        // qu'une version plus récente existe, et celui vers lequel rattacher.
        // La jeter faisait disparaître la pastille de mise à jour, qui
        // fonctionnait avant, et vidait le menu de rattachement de son seul
        // bon choix.
        let split = NexusModSearch.partition(
            hits,
            installedNexusIds: installed.nexusModId > 0 ? [installed.nexusModId] : [],
            installedTitles: [installed.nexusName])
        translationInstalledHits[mod.folderName] = split.installed
        // Rattacher sans rien demander quand deux signaux concordent : le titre
        // et l'identifiant lu dans le nom du fichier téléchargé.
        adoptConfirmedNexusId(for: installed, among: split.installed,
                              isTranslation: true, host: mod)
        return split.available
    }

    /// Rattache un dépôt à sa fiche Nexus **quand il n'y a pas de doute**.
    ///
    /// Sur un compte gratuit tout s'installe à la main, donc sans identifiant —
    /// et sans identifiant aucune mise à jour ne peut être vue. Plutôt que de
    /// demander à l'utilisateur de désigner la fiche, on la reconnaît : le nom
    /// du fichier téléchargé porte l'identifiant Nexus dans 14 cas sur 15, et
    /// le titre le confirme. Deux signaux qui concordent, ou rien.
    ///
    /// La date retenue reste celle du dépôt : c'est ce qu'on sait vraiment, et
    /// prendre celle du résultat déclarerait la ligne à jour par construction.
    private func adoptConfirmedNexusId(for entry: InstalledTranslation,
                                       among hits: [NexusModSearch.Hit],
                                       isTranslation: Bool, host: ModItem) {
        guard entry.nexusModId == 0,
              let confirmed = NexusModSearch.confirmedNexusId(forDeposit: entry.nexusName,
                                                              among: hits)
        else { return }
        let linked = InstalledTranslation(
            hostFolderName: entry.hostFolderName, nexusModId: confirmed.modId,
            nexusName: confirmed.name, version: confirmed.version,
            updatedAt: entry.installedAt, installedAt: entry.installedAt,
            files: entry.files, replacedFiles: entry.replacedFiles)
        if isTranslation {
            installedTranslations.record(linked)
        } else {
            installedTranslations.forgetAddon(entry)
            installedTranslations.recordAddon(linked)
        }
        if !InstalledTranslationStore.save(installedTranslations) {
            log("Rattachement Nexus non enregistré : le suivi ne survivra pas à la fermeture",
                level: .warning)
        }
    }

    /// Les greffes posées sur ce mod.
    func addons(for mod: ModItem) -> [InstalledTranslation] {
        installedTranslations.addons(forHost: mod.folderName)
    }

    /// Une version plus récente de cette greffe a-t-elle été trouvée ?
    ///
    /// Même règle que pour les traductions : sur les **dates Nexus**, et
    /// seulement quand la greffe porte un identifiant. Une greffe déposée à la
    /// main n'en a pas — c'est ce que `linkToNexus` répare.
    func addonUpdateAvailable(_ addon: InstalledTranslation,
                              for mod: ModItem) -> NexusModSearch.Hit? {
        guard addon.nexusModId > 0 else { return nil }
        let seen = (supplementSearches[mod.folderName].map { $0.hits + $0.alreadyInstalled }) ?? []
        return seen.first {
            $0.modId == addon.nexusModId
                && InstalledTranslationRegistry.isNewer($0.updatedAt, than: addon.updatedAt)
        }
    }

    /// Rattache une traduction ou une greffe déposée à la main à sa page Nexus.
    ///
    /// **Sans cela, le suivi des mises à jour ne peut jamais se déclencher.**
    /// Le téléchargement intégré demande un compte premium ; sur un compte
    /// gratuit, tout passe par la feuille d'installation, donc sans identifiant
    /// Nexus — et c'est l'identifiant qui dit qu'une version plus récente
    /// existe. Le lien se fait donc après coup, sur la ligne installée.
    func linkToNexus(_ entry: InstalledTranslation, hit: NexusModSearch.Hit,
                     isTranslation: Bool, for mod: ModItem) {
        // **La date retenue est celle du dépôt, pas celle du résultat.** Copier
        // `hit.updatedAt` ferait déclarer la ligne à jour par construction : on
        // comparerait la date Nexus à elle-même, et aucune mise à jour ne
        // pourrait jamais apparaître — le défaut qu'on est en train de réparer,
        // sous une autre forme. Ce qu'on sait vraiment, c'est **quand il l'a
        // posée** ; tout ce que Nexus a publié depuis est plus récent.
        let linked = InstalledTranslation(
            hostFolderName: entry.hostFolderName, nexusModId: hit.modId, nexusName: hit.name,
            version: hit.version, updatedAt: entry.installedAt, installedAt: entry.installedAt,
            files: entry.files, replacedFiles: entry.replacedFiles)
        if isTranslation {
            installedTranslations.record(linked)
        } else {
            installedTranslations.forgetAddon(entry)
            installedTranslations.recordAddon(linked)
        }
        if !InstalledTranslationStore.save(installedTranslations) {
            showModal(message: L(L10n.Mods.translationNotTracked))
        }
        // La liste des propositions perd ce qui vient d'être reconnu — **sans
        // repartir sur le réseau** : on sait déjà lequel des résultats c'était,
        // et relancer la recherche ferait tourner un compteur d'API pour
        // retirer une ligne qu'on tient sous la main.
        // Le résultat **change de moitié** : il quitte les propositions et
        // rejoint ce qui est en place. L'y oublier ferait disparaître la mise à
        // jour qu'il annonce jusqu'à la recherche suivante.
        if isTranslation {
            translationHits[mod.folderName] =
                (translationHits[mod.folderName] ?? []).filter { $0.modId != hit.modId }
            translationInstalledHits[mod.folderName] =
                (translationInstalledHits[mod.folderName] ?? []) + [hit]
        } else if let previous = supplementSearches[mod.folderName] {
            supplementSearches[mod.folderName] = SupplementSearch(
                hits: previous.hits.filter { $0.modId != hit.modId },
                alreadyInstalled: previous.alreadyInstalled + [hit],
                received: previous.received,
                serverTotal: previous.serverTotal)
        }
    }

    /// Retire une greffe posée sur ce mod, et **rend** ce qu'elle avait recouvert.
    func removeAddon(_ addon: InstalledTranslation, from mod: ModItem) {
        guard !busyTranslations.contains(mod.folderName) else { return }
        busyTranslations.insert(mod.folderName)
        defer { busyTranslations.remove(mod.folderName) }
        let hostPath = URL(fileURLWithPath: gameDir)
            .appendingPathComponent("Mods")
            .appendingPathComponent(mod.physicalFolderName)
        let failures = ManifestlessInstaller.uninstall(addon, hostPath: hostPath)
        if failures.isEmpty {
            installedTranslations.forgetAddon(addon)
            if !InstalledTranslationStore.save(installedTranslations) {
                showModal(message: L(L10n.Mods.translationRemoveNotTracked))
            }
        } else {
            // Même règle que pour une traduction : un retrait à moitié fait
            // garde sa ligne, seule à porter la liste des fichiers restants.
            showModal(message: String(format: L(L10n.Mods.translationRemovePartial),
                                      failures.joined(separator: ", ")))
        }
        // Une greffe mixte emporte des fichiers de langue : la couverture
        // française mesurée est périmée, exactement comme après un dépôt ou le
        // retrait d'une traduction. Appelée depuis un bouton, donc sur le fil
        // principal.
        MainActor.assumeIsolated { invalidateFrenchCoverage(for: mod.folderName) }
        refresh()
    }

    /// Cherche sur Nexus ce qui se greffe sur ce mod : bagages, compatibilités,
    /// packs de contenu qui le citent.
    ///
    /// Même requête que les traductions, sans le tag : le nom du mod suffit,
    /// `WILDCARD` cherchant une sous-chaîne du titre. Tout le travail est au
    /// retour — voir `NexusModSearch.supplements(among:excluding:)`.
    func searchSupplements(for mod: ModItem) {
        guard !searchingSupplements.contains(mod.folderName) else { return }
        searchingSupplements.insert(mod.folderName)
        let host = Int(mod.nexusModId)
        NexusSearchClient.search(name: mod.name) { [weak self] result in
            guard let self else { return }
            self.searchingSupplements.remove(mod.folderName)
            switch result {
            case .success(let page):
                let found = NexusModSearch.supplements(among: page.hits, excluding: host,
                                                       hostName: mod.name)
                // Ce qui est déjà là ne se propose pas : il se **montre**, à
                // part, avec ce qu'on peut en faire.
                let split = NexusModSearch.partition(
                    found,
                    installedNexusIds: self.installedNexusIds(),
                    installedTitles: Set(self.installedTranslations
                        .addons(forHost: mod.folderName).map(\.nexusName)))
                // Rattacher les greffes reconnues, sans rien demander.
                for addon in self.installedTranslations.addons(forHost: mod.folderName) {
                    self.adoptConfirmedNexusId(for: addon, among: split.installed,
                                               isTranslation: false, host: mod)
                }
                self.supplementSearches[mod.folderName] = SupplementSearch(
                    hits: split.available,
                    alreadyInstalled: split.installed,
                    received: page.hits.count,
                    serverTotal: page.totalCount)
            case .failure(let error):
                // Une panne n'est pas une absence, comme pour les traductions.
                self.supplementSearches[mod.folderName] = nil
                self.log("Recherche de suppléments : \(error)", level: .warning)
                self.showModal(message: self.L(L10n.Mods.translationSearchFailed))
            }
        }
    }

    /// Cherche sur Nexus les traductions françaises de ce mod.
    ///
    /// Le filtre est le **tag** `French` de Nexus, pas le titre : sur 80
    /// traductions relevées, 77 le portent, et le serveur fait alors le tri.
    /// Le titre ne sert que de filet pour les trois autres.
    func searchTranslations(for mod: ModItem) {
        guard !searchingTranslations.contains(mod.folderName) else { return }
        searchingTranslations.insert(mod.folderName)
        let host = Int(mod.nexusModId)
        NexusSearchClient.search(name: mod.name, tag: NexusModSearch.frenchTag) { [weak self] result in
            guard let self else { return }
            self.searchingTranslations.remove(mod.folderName)
            switch result {
            case .success(let page):
                // Le filet : si le tag n'a rien rendu, on retente large et on
                // lit les titres. Trois traductions sur quatre-vingts ne
                // portent pas le tag.
                if page.hits.isEmpty {
                    self.searchTranslationsByTitle(for: mod)
                } else {
                    // **Le titre classe, il ne filtre pas.** Le serveur a déjà
                    // trié sur le tag ; rejeter ici les titres muets perdrait
                    // les traductions bien taguées que le tag venait de rendre.
                    // La traduction déjà posée n'a rien à faire dans la liste
                    // des propositions : elle a sa propre ligne, qui porte son
                    // retrait et sa mise à jour.
                    self.translationHits[mod.folderName] = self.withoutInstalledTranslation(
                        NexusModSearch.ranked(page.hits, excluding: host), for: mod)
                }
            case .failure(let error):
                // Une panne n'est pas une absence : `[]` ferait afficher
                // « aucune traduction trouvée » pour une recherche cassée.
                self.translationHits[mod.folderName] = nil
                self.log("Recherche de traduction : \(error)", level: .warning)
                self.showModal(message: self.L(L10n.Mods.translationSearchFailed))
            }
        }
    }

    private func searchTranslationsByTitle(for mod: ModItem) {
        searchingTranslations.insert(mod.folderName)
        let host = Int(mod.nexusModId)
        NexusSearchClient.search(name: mod.name) { [weak self] result in
            guard let self else { return }
            self.searchingTranslations.remove(mod.folderName)
            switch result {
            case .success(let page):
                // Recherche large : ici rien d'autre que le titre ne distingue
                // une traduction, le filtre est à sa place.
                self.translationHits[mod.folderName] = self.withoutInstalledTranslation(
                    NexusModSearch.frenchTranslations(among: page.hits, excluding: host),
                    for: mod)
            case .failure(let error):
                // Une panne n'est pas une absence : afficher « aucune traduction
                // trouvée » ici ferait passer une recherche cassée pour un
                // résultat, exactement ce que le décodeur refuse de faire sur
                // les erreurs GraphQL.
                self.translationHits[mod.folderName] = nil
                self.log("Recherche de traduction (titre) : \(error)", level: .warning)
                self.showModal(message: self.L(L10n.Mods.translationSearchFailed))
            }
        }
    }

    /// Télécharge une traduction, la dépose dans le mod, et l'enregistre.
    ///
    /// Le dépôt ne crée rien dans `Mods/` : il écrit **dans** un mod existant,
    /// après avoir mis à l'abri chaque fichier recouvert.
    func installTranslation(_ hit: NexusModSearch.Hit, into mod: ModItem) {
        guard !busyTranslations.contains(mod.folderName) else { return }
        // Un seul téléchargement Nexus à la fois, traductions comprises : elles
        // passent par le même téléchargeur que les mods, et deux en vol se
        // disputeraient `pendingDownloadedZip`.
        if rejectNexusDownloadIfBusy() { return }
        busyTranslations.insert(mod.folderName)
        isDownloadingFromNexus = true
        downloadingNexusModId = hit.modId
        nexusDownloadInFlight = nexusDownloader.download(
            modId: hit.modId, fileId: nil, game: NexusRequestBuilder.gameDomain,
            key: nil, expires: nil,
            onProgress: { [weak self] received, expected in
                self?.noteNexusDownloadProgress(received: received, expected: expected,
                                                modId: hit.modId)
            }) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.clearNexusDownloadState()
                switch result {
                case .success(let archive):
                    self.depositTranslation(archive: archive, hit: hit, into: mod)
                case .failure(.cancelled):
                    // Geste volontaire : rien à annoncer.
                    self.busyTranslations.remove(mod.folderName)
                case .failure(let error):
                    self.busyTranslations.remove(mod.folderName)
                    // Sans lien direct, la voie manuelle reste ouverte : le
                    // message nomme le bouton qui y mène plutôt que de laisser
                    // l'utilisateur devant une impasse.
                    var hint = ""
                    if case .noDownloadLink = error {
                        hint = "\n\n" + self.L(L10n.Mods.translationManualHint)
                    }
                    self.showModal(message: self.nexusDownloadMessage(error) + hint)
                }
            }
        }
    }

    private func depositTranslation(archive: URL, hit: NexusModSearch.Hit, into mod: ModItem) {
        defer { busyTranslations.remove(mod.folderName) }
        // L'archive téléchargée n'a plus d'usage passé ce point : la laisser
        // derrière nous encombrerait le dossier temporaire d'un fichier dont
        // plus personne ne connaît le chemin.
        defer { try? FileManager.default.removeItem(at: archive) }
        let installer = ModZipInstaller()
        do {
            let extracted = try installer.extractToTemp(zipUrl: archive)
            defer { try? FileManager.default.removeItem(at: extracted) }
            let paths = Self.archivePaths(under: extracted)
            let outcome = ManifestlessArchive.classify(
                paths: paths, installedFolderNames: [mod.folderName])
            // La traduction vise **ce** mod : quel que soit le nom du dossier
            // qu'elle porte, c'est lui l'hôte. On ne redemande pas ce que
            // l'utilisateur vient de désigner en ouvrant cette fiche.
            let entries: [ManifestlessArchive.Entry]
            switch outcome {
            case .plan(let plan): entries = plan.entries
            case .needsHost(_, _, let found): entries = found
            case .unrecognised:
                showModal(message: L(L10n.Mods.translationUnrecognised))
                return
            }
            let plan = ManifestlessArchive.Plan(hostFolderName: mod.folderName,
                                                kind: .translation, entries: entries)
            let result = depositIntoMod(plan: plan, extractedRoot: extracted, host: mod,
                                        sourceName: hit.name, nexus: hit)
            if let message = result.message { showModal(message: message) }
            guard result.outcome != nil else { return }
            log(String(format: L(L10n.Mods.translationInstalled), hit.name, mod.name))
            refresh()
        } catch {
            showModal(message: L(L10n.Mods.translationInstallFailed))
            log("Dépôt de traduction : \(error)", level: .error)
        }
    }

    /// Dépose les fichiers d'un plan dans un mod, puis inscrit au registre ce
    /// qui doit pouvoir être retiré ensuite.
    ///
    /// **L'ordre compte.** La traduction déjà en place n'est rendue qu'une fois
    /// le plan établi : l'écarter plus tôt ferait perdre une traduction qui
    /// marchait à la première archive illisible. Elle doit l'être quand même —
    /// son entrée de registre est le seul pointeur vers les fichiers d'origine
    /// du mod, et la remplacer sans la défaire les perdrait pour de bon.
    ///
    /// - Parameters:
    ///   - sourceName: le nom sous lequel nommer ce qui est posé — le titre
    ///     Nexus, ou le nom de l'archive pour un dépôt à la main.
    ///   - nexus: la fiche Nexus quand il y en a une. Sans elle, la traduction
    ///     est enregistrée sans identifiant : elle se retire, mais aucune mise
    ///     à jour ne lui sera proposée.
    /// - Returns: ce qui a été écrit (`nil` si rien ne l'a été), et le message
    ///   à montrer le cas échéant — un dépôt peut réussir *et* avoir quelque
    ///   chose à dire.
    func depositIntoMod(plan: ManifestlessArchive.Plan, extractedRoot: URL, host: ModItem,
                        sourceName: String, nexus: NexusModSearch.Hit?)
        -> (outcome: ManifestlessInstaller.Outcome?, message: String?) {
        // Le refus se dit dans les mots de ce qu'on déposait : « la traduction »
        // n'a pas de sens quand l'utilisateur a glissé un lot de sacs.
        let failed = plan.kind == .translation
            ? L(L10n.Mods.translationInstallFailed) : L(L10n.ModInstall.depositFailed)
        guard let backupRoot = InstalledTranslationStore.backupRoot else {
            return (nil, failed)
        }
        // Nom **physique** : un mod en pause vit dans un dossier préfixé d'un
        // point, et le plan ne connaît que le nom logique.
        let hostPath = URL(fileURLWithPath: gameDir)
            .appendingPathComponent("Mods")
            .appendingPathComponent(host.physicalFolderName)

        // Ce qu'on remplace, on le rend d'abord. Une greffe n'écarte pas la
        // traduction du même mod — elles ne déposent pas les mêmes fichiers —
        // mais elle écarte **la greffe de même identité**, sans quoi redéposer
        // un lot laisserait derrière lui les fichiers de l'ancienne version.

        // **Ce que le nom du fichier sait de sa provenance.** Un dépôt venu du
        // glisser-déposer n'a pas de fiche Nexus derrière lui : sans
        // identifiant, la ligne affiche « aucune vérification de mise à jour »
        // et attend un rattachement à la main. Or le nom porte l'identifiant
        // six fois sur dix sur le parc réel. Le navigateur intégré, lui, garde
        // la main entière : ce qu'il sait vient de Nexus, pas d'une lecture.
        let now = Date()
        let learned = nexus == nil ? NexusArchiveName.parse(sourceName) : nil
        // La date retenue est celle du dépôt, jamais celle que porte le nom :
        // c'est la règle de `linkToNexus`, et pour la même raison — on sait
        // quand il l'a posée, tout ce que Nexus a publié depuis est plus récent.
        // Sans elle, `isNewer` refuse de conclure et l'identifiant appris ne
        // servirait à rien.
        let entry = InstalledTranslation(
            hostFolderName: host.folderName,
            nexusModId: nexus?.modId ?? learned?.modId ?? 0,
            nexusName: sourceName, version: nexus?.version ?? learned?.version ?? "",
            updatedAt: nexus?.updatedAt ?? (learned == nil ? nil : now),
            installedAt: now, files: [], replacedFiles: [:])
        let incumbent: InstalledTranslation? = plan.kind == .translation
            ? installedTranslations.translation(forHost: host.folderName)
            : installedTranslations.addons(forHost: host.folderName)
                .first { InstalledTranslationRegistry.sameAddon($0, entry) }
        if let incumbent {
            let failures = ManifestlessInstaller.uninstall(incumbent, hostPath: hostPath)
            guard failures.isEmpty else {
                return (nil, String(format: L(L10n.Mods.translationRemovePartial),
                                    failures.joined(separator: ", ")))
            }
            if plan.kind == .translation {
                installedTranslations.forget(host: host.folderName)
            } else {
                installedTranslations.forgetAddon(incumbent)
            }
        }

        let written: ManifestlessInstaller.Outcome
        do {
            written = try ManifestlessInstaller.install(plan: plan, extractedRoot: extractedRoot,
                                                        hostPath: hostPath, backupRoot: backupRoot)
        } catch ManifestlessInstaller.InstallError
                    .rollBackIncomplete(let reason, let leftBehind) {
            // Nommer les fichiers restés en l'état est la seule raison d'être de
            // cette erreur : les fondre dans « installation impossible »
            // laisserait croire le mod intact alors qu'il ne l'est pas.
            log("Dépôt sans manifeste, annulation incomplète : \(reason)", level: .error)
            return (nil, String(format: L(L10n.ModInstall.depositRollbackIncomplete),
                                leftBehind.joined(separator: ", ")))
        } catch {
            log("Dépôt sans manifeste : \(error)", level: .error)
            return (nil, failed)
        }

        // Des fichiers de langue ont pu bouger — une greffe mixte en porte
        // aussi : la couverture française mesurée est périmée dans tous les
        // cas. Ici et non chez l'appelant, sinon le dépôt depuis la feuille
        // d'installation laisserait la liste des mods dire « À traduire » sur
        // un mod qui vient d'être traduit.
        //
        // `invalidateFrenchCoverage` est `@MainActor` ; les deux appelants
        // écrivent depuis le fil principal. Même geste que `deleteMod`, et pour
        // la même raison : un `Task` rouvrirait une course entre la purge de
        // l'index et le rescan qui suit.
        MainActor.assumeIsolated { invalidateFrenchCoverage(for: host.folderName) }

        // **Les greffes entrent au registre elles aussi.** Elles n'y entraient
        // pas : le message de dépôt devait donc prévenir que leur retrait se
        // ferait à la main. Elles se retirent maintenant comme une traduction,
        // depuis la fiche du mod.
        // Même provenance que la sonde `entry` ci-dessus — c'est **cette
        // ligne-ci** qui entre au registre, et deux lectures du même nom qui
        // divergeraient donneraient une identité au comparateur et une autre à
        // ce qui est gardé.
        let recorded = InstalledTranslation(
            hostFolderName: host.folderName,
            nexusModId: nexus?.modId ?? learned?.modId ?? 0,
            nexusName: sourceName, version: nexus?.version ?? learned?.version ?? "",
            updatedAt: nexus?.updatedAt ?? (learned == nil ? nil : now), installedAt: now,
            files: written.written, replacedFiles: written.replaced)
        if plan.kind == .translation {
            installedTranslations.record(recorded)
        } else {
            installedTranslations.recordAddon(recorded)
        }
        guard InstalledTranslationStore.save(installedTranslations) else {
            // Les fichiers sont posés mais rien ne les retient : le dire,
            // sinon la traduction ne pourra plus être retirée.
            return (written, L(L10n.Mods.translationNotTracked))
        }
        return (written, nil)
    }

    /// Retire la traduction posée sur ce mod et **rend** ce qu'elle avait
    /// recouvert.
    func removeTranslation(from mod: ModItem) {
        guard !busyTranslations.contains(mod.folderName),
              let translation = translation(for: mod) else { return }
        busyTranslations.insert(mod.folderName)
        defer { busyTranslations.remove(mod.folderName) }
        let hostPath = URL(fileURLWithPath: gameDir)
            .appendingPathComponent("Mods")
            .appendingPathComponent(mod.physicalFolderName)
        let failures = ManifestlessInstaller.uninstall(translation, hostPath: hostPath)
        if failures.isEmpty {
            installedTranslations.forget(host: mod.folderName)
            if !InstalledTranslationStore.save(installedTranslations) {
                showModal(message: L(L10n.Mods.translationRemoveNotTracked))
            }
        } else {
            // **Un retrait à moitié fait garde son entrée.** Elle porte la liste
            // des fichiers restants et l'endroit où dorment les originaux du
            // mod : l'oublier ici rendrait la seconde tentative impossible.
            showModal(message: String(format: L(L10n.Mods.translationRemovePartial),
                                      failures.joined(separator: ", ")))
        }
        // Des fichiers ont bougé même quand tout n'a pas été retiré : la
        // couverture française doit être remesurée dans les deux cas.
        // Appelée depuis un bouton, donc sur le fil principal.
        MainActor.assumeIsolated { invalidateFrenchCoverage(for: mod.folderName) }
        refresh()
    }

    /// Pour chaque nom de fichier présent **à la racine** d'un mod installé,
    /// les mods qui le portent.
    ///
    /// Sert à reconnaître un remplacement de configuration — `bagconfig.json`
    /// déposé seul appartient à `ItemBags`, et à lui seul. **Mesuré sur le
    /// parc : 76 des 91 noms de fichiers JSON de premier niveau n'ont qu'un
    /// propriétaire**, quand `config.json` en a 544 et `content.json` 522 :
    /// c'est l'unicité qui autorise à conclure, jamais le nom seul.
    ///
    /// Calculé à la demande, au moment d'analyser une archive : c'est un
    /// parcours du disque, et il n'a rien à faire dans un rendu de liste.
    func rootFileOwners() -> [String: [String]] {
        let root = URL(fileURLWithPath: gameDir).appendingPathComponent("Mods")
        var owners: [String: [String]] = [:]
        var unreadable = 0
        for mod in allInstalledMods() {
            let folder = root.appendingPathComponent(mod.physicalFolderName)
            // `contentsOfDirectory` et non un parcours récursif : la forme ne
            // vaut que pour la **racine** du mod. Un `config.json` enfoui trois
            // niveaux plus bas n'est pas ce qu'on remplace.
            do {
                for name in try FileManager.default.contentsOfDirectory(atPath: folder.path)
                where !name.hasPrefix(".") {
                    owners[name.lowercased(), default: []].append(mod.folderName)
                }
            } catch {
                // Un dossier qu'on ne sait pas lire ne portera aucun candidat :
                // une archive de remplacement qui le visait sera refusée sans
                // qu'on sache pourquoi. Compté et dit une fois, plutôt que 863
                // lignes ou aucune.
                unreadable += 1
            }
        }
        if unreadable > 0 {
            log("Reconnaissance des remplacements : \(unreadable) dossier(s) de mod illisible(s), "
                + "un fichier qui les visait ne sera pas reconnu", level: .warning)
        }
        return owners.mapValues { Array(Set($0)).sorted() }
    }

    /// Les chemins d'une archive dépliée, relatifs à sa racine.
    static func archivePaths(under root: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        else { return [] }
        var paths: [String] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let full = url.resolvingSymlinksInPath().path
            let base = root.resolvingSymlinksInPath().path + "/"
            if full.hasPrefix(base) { paths.append(String(full.dropFirst(base.count))) }
        }
        return paths
    }

    // MARK: - Découverte (axe G)

    /// Une carte de la vitrine : le hit Nexus, et s'il est déjà dans le parc.
    struct DiscoveryRow: Identifiable {
        let hit: NexusModSearch.Hit
        let installed: Bool
        var id: Int { hit.modId }
    }

    /// Le résultat d'une recherche par nom dans la vitrine : les cartes et le
    /// total serveur — la poignée affichée n'est jamais tout ce qui existe.
    struct DiscoverySearchResult {
        let rows: [DiscoveryRow]
        let totalCount: Int
        /// Le terme qui a produit ces lignes — « voir plus » redemande la
        /// tranche suivante du **même** terme, pas de ce que le champ de
        /// recherche contient au moment du clic.
        let term: String
        /// Les résultats reçus, doublons compris — ce sur quoi se calcule la
        /// tranche suivante.
        let loaded: Int
    }

    /// Où en est une fiche demandée depuis la vitrine.
    enum DiscoveryDetailState { case idle, loading, loaded, failed }

    @Published private(set) var discovery: [ModCatalog.SectionKind: ModCatalog.SectionState] = [:]
    @Published private(set) var discoveryLoading = false
    @Published private(set) var discoverySearch: DiscoverySearchResult?
    @Published private(set) var discoveryDetail: NexusModSearch.Detail?
    @Published private(set) var discoveryDetailState: DiscoveryDetailState = .idle
    /// La dernière panne réseau des sections — un seul message en haut de
    /// l'onglet, chaque section n'a pas à répéter (spec §8).
    @Published private(set) var lastDiscoveryError: NexusSearchClient.SearchError?
    /// La catégorie à laquelle les trois sections sont restreintes, `nil`
    /// pour toutes. Le filtre part au **serveur** : sur 50 mods de tendances
    /// on compte déjà 15 catégories, trier la page reçue n'aurait rien rendu.
    @Published private(set) var discoveryCategory: NexusCategory?

    private var pendingSectionFetches = 0

    /// Les mods installés depuis Nexus **pendant cette session**, par leur
    /// identifiant de page.
    ///
    /// Une installation ne devient visible dans `mods` qu'au terme d'un scan
    /// du parc — passe de réparation comprise, deux parcours récursifs de
    /// 104 000 fichiers, plusieurs secondes. La pastille « installé » de la
    /// vitrine attendait donc tout ce temps, et l'utilisateur concluait
    /// qu'elle ne s'allumait qu'après un rafraîchissement manuel. Ce que
    /// l'app vient d'installer, elle le sait tout de suite : elle le dit tout
    /// de suite. Rien à persister — au prochain lancement, le scan porte
    /// l'identifiant.
    @Published private(set) var recentNexusInstalls: Set<Int> = []

    /// Cache sur disque : `~/Library/Caches/StarHubFR/discovery/` (spec §6).
    private let discoveryCatalog: ModCatalog = {
        let dir = URL.cachesDirectory.appendingPathComponent("StarHubFR/discovery",
                                                             isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ModCatalog(
            load: { key in try? Data(contentsOf: dir.appendingPathComponent("\(key).json")) },
            save: { key, data in try? data.write(to: dir.appendingPathComponent("\(key).json")) })
    }()

    /// Charge les trois sections : le cache d'abord, une requête par section
    /// périmée ou absente (spec §5.3). `force` re-demande tout — le bouton
    /// de rafraîchissement, seule chose qui déclenche une requête hors
    /// ouverture périmée.
    /// Restreint la vitrine à une catégorie — ou la rouvre en grand. Chaque
    /// catégorie a son propre cache : rebasculer sur « toutes » ne relance
    /// aucune requête si la liste complète est encore fraîche.
    ///
    /// Le filtre ne touche **pas** la recherche par nom : on y cherche un mod
    /// précis, le lui cacher parce qu'il est rangé ailleurs rendrait un vide
    /// inexplicable.
    func setDiscoveryCategory(_ category: NexusCategory?) {
        guard category?.id != discoveryCategory?.id else { return }
        discoveryCategory = category
        loadDiscovery()
        // Une recherche affichée se refait sous la nouvelle catégorie : la
        // laisser telle quelle montrerait des résultats que le filtre visible
        // dit avoir écartés.
        if let search = discoverySearch { searchDiscovery(name: search.term) }
    }

    func loadDiscovery(force: Bool = false) {
        // La panne d'avant ne parle pas de la tentative qui commence : sans
        // cette remise à zéro, un bandeau d'erreur restait en haut de
        // l'onglet pour toujours, y compris après un chargement réussi.
        lastDiscoveryError = nil
        for kind in ModCatalog.SectionKind.allCases {
            let state = discoveryCatalog.state(kind, category: discoveryCategory?.id)
            discovery[kind] = state
            switch state {
            case .fresh where !force: continue
            default: fetchDiscoverySection(kind)
            }
        }
    }

    private func fetchDiscoverySection(_ kind: ModCatalog.SectionKind) {
        pendingSectionFetches += 1
        discoveryLoading = true
        // La catégorie demandée est retenue ici : la réponse peut arriver
        // après que l'utilisateur en a choisi une autre. Elle est alors
        // rangée dans **son** cache mais n'est pas affichée — sinon la
        // vitrine montrerait des mods d'une catégorie qu'on vient de quitter.
        let category = discoveryCategory
        NexusSearchClient.listing(sort: kind.defaultSort, tag: kind.defaultTag,
                                  category: category?.englishName) { [weak self] result in
            guard let self else { return }
            self.pendingSectionFetches = max(0, self.pendingSectionFetches - 1)
            if self.pendingSectionFetches == 0 { self.discoveryLoading = false }
            let stillWanted = self.discoveryCategory?.id == category?.id
            switch result {
            case .success(let page):
                self.discoveryCatalog.record(kind, category: category?.id, page: page)
                // Relu depuis le cache : c'est la page dédoublonnée qui
                // s'affiche.
                guard stillWanted else { return }
                self.discovery[kind] = self.discoveryCatalog.state(kind,
                                                                   category: category?.id)
            case .failure(let error):
                guard stillWanted else { return }
                // La panne est dite dans tous les cas (spec §8) : garder des
                // lignes de la veille sans prévenir qu'elles n'ont pas pu
                // être rafraîchies, c'est mentir en silence.
                self.lastDiscoveryError = error
                // Le stale reste affiché pendant la panne (spec §6) — le
                // bandeau suffit, on ne blanchit pas la section.
                if case .stale = self.discovery[kind] ?? .empty(.neverLoaded) { return }
                self.discovery[kind] = .empty(.failed)
            }
        }
    }

    /// Les cartes d'une liste de hits : adulte exclu (spec §8), « installé »
    /// calculé par identifiant **et** par titre — les deux clés du
    /// partitionnement des traductions (A3-T5).
    /// `francophoneOnly` ne vaut que pour les **sections** : la vitrine est
    /// une sélection, on y écarte les traductions d'autres langues. Une
    /// recherche par nom, elle, rend ce qu'on lui a demandé — filtrer ce que
    /// l'utilisateur vient de taper serait un résultat vide inexplicable.
    private func discoveryRows(in hits: [NexusModSearch.Hit],
                               hidingInstalled: Bool,
                               francophoneOnly: Bool) -> [DiscoveryRow] {
        let installedIds = installedNexusIds()
        let installedTitles = Set(mods.map(\.name))
        // Trois écarts, une seule passe : contenu adulte (spec §8),
        // traductions non françaises en vitrine, et « masquer installés ».
        return hits.filter {
            !$0.adultContent && (!francophoneOnly || NexusModSearch.vitrineEligible($0))
        }
            .map { hit in
            let installed = installedIds.contains(hit.modId)
                || installedTitles.contains { NexusModSearch.namesMatch($0, hit.name) }
            return DiscoveryRow(hit: hit, installed: installed)
        }
        .filter { !(hidingInstalled && $0.installed) }
    }

    /// Les cartes visibles d'une section, ce qui a été **reçu** pour elle, et
    /// ce que le serveur dit avoir en tout.
    ///
    /// Le compte se lit « x affichés sur y chargés » : un filtre ne doit pas
    /// masquer qu'il a filtré (spec §7.1), mais l'annoncer sur le total du
    /// catalogue — « 20 affichés sur 33 204 » — ne comparait rien à rien. Le
    /// total serveur ne sert plus qu'à savoir s'il reste une tranche à
    /// demander.
    func discoveryRows(for kind: ModCatalog.SectionKind,
                       hidingInstalled: Bool)
    -> (rows: [DiscoveryRow], shown: Int, loaded: Int, total: Int) {
        guard let page = discovery[kind]?.page else { return ([], 0, 0, 0) }
        let rows = discoveryRows(in: page.hits, hidingInstalled: hidingInstalled,
                                 francophoneOnly: true)
        return (rows, rows.count, page.hits.count, page.totalCount)
    }

    /// Demande la tranche suivante d'une section — « voir plus ».
    ///
    /// L'offset est le nombre de mods **déjà reçus**, pas le nombre affiché :
    /// compter les cartes visibles ferait redemander sans fin ce que les
    /// filtres viennent d'écarter.
    func loadMoreDiscovery(_ kind: ModCatalog.SectionKind) {
        guard let page = discovery[kind]?.page,
              page.hits.count < page.totalCount else { return }
        let category = discoveryCategory
        pendingSectionFetches += 1
        discoveryLoading = true
        NexusSearchClient.listing(sort: kind.defaultSort, tag: kind.defaultTag,
                                  category: category?.englishName,
                                  offset: page.hits.count) { [weak self] result in
            guard let self else { return }
            self.pendingSectionFetches = max(0, self.pendingSectionFetches - 1)
            if self.pendingSectionFetches == 0 { self.discoveryLoading = false }
            guard self.discoveryCategory?.id == category?.id else { return }
            switch result {
            case .success(let next):
                self.discoveryCatalog.append(kind, category: category?.id, page: next)
                self.discovery[kind] = self.discoveryCatalog.state(kind,
                                                                   category: category?.id)
            case .failure(let error):
                // La bande déjà là ne bouge pas : seule la suite manque, et
                // le bandeau dit pourquoi.
                self.lastDiscoveryError = error
            }
        }
    }

    /// Recherche par nom dans la vitrine : même client que la liaison
    /// d'identité, présentation propre à l'onglet (spec §7.1). Elle montre
    /// tout, badge « installé » compris — on cherche un mod précis, installé
    /// ou non.
    func searchDiscovery(name: String) {
        let term = NexusModSearch.searchTerm(for: name)
        guard !term.isEmpty else { discoverySearch = nil; return }
        NexusSearchClient.search(name: name,
                                 category: discoveryCategory?.englishName) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let page):
                self.lastDiscoveryError = nil
                self.discoverySearch = DiscoverySearchResult(
                    rows: self.discoveryRows(in: page.hits, hidingInstalled: false,
                                             francophoneOnly: false),
                    totalCount: page.totalCount,
                    term: name,
                    loaded: page.hits.count)
            case .failure(let error):
                self.lastDiscoveryError = error
                self.discoverySearch = nil
            }
        }
    }

    /// La tranche suivante des résultats de recherche.
    ///
    /// Le terme redemandé est celui qui a produit la liste, retenu au
    /// résultat : reprendre le champ de saisie servirait la suite d'une autre
    /// recherche à qui aurait retapé entre-temps.
    func loadMoreDiscoverySearch() {
        guard let current = discoverySearch, current.loaded < current.totalCount else { return }
        NexusSearchClient.search(name: current.term,
                                 category: discoveryCategory?.englishName,
                                 offset: current.loaded) { [weak self] result in
            guard let self else { return }
            // La recherche a pu être quittée ou relancée pendant la requête.
            guard let now = self.discoverySearch, now.term == current.term,
                  now.loaded == current.loaded else { return }
            switch result {
            case .success(let page):
                var seen = Set(now.rows.map(\.hit.modId))
                let fresh = page.hits.filter { seen.insert($0.modId).inserted }
                self.lastDiscoveryError = nil
                self.discoverySearch = DiscoverySearchResult(
                    rows: now.rows + self.discoveryRows(in: fresh, hidingInstalled: false,
                                                        francophoneOnly: false),
                    totalCount: page.totalCount,
                    term: current.term,
                    loaded: now.loaded + page.hits.count)
            case .failure(let error):
                // Les résultats déjà là restent : seule la suite manque.
                self.lastDiscoveryError = error
            }
        }
    }

    /// Quitte les résultats : les sections reprennent la place. Sans cette
    /// porte de sortie, une recherche remplacerait définitivement la vitrine.
    func clearDiscoverySearch() {
        discoverySearch = nil
    }

    /// Fiche : le cache 24 h d'abord, le réseau ensuite (spec §5.3).
    func loadDiscoveryDetail(modId: Int) {
        discoveryDetailState = .loading
        if let cached = discoveryCatalog.detail(for: modId) {
            discoveryDetail = cached
            discoveryDetailState = .loaded
            return
        }
        NexusSearchClient.detail(modId: modId) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let detail):
                self.discoveryCatalog.recordDetail(detail)
                self.discoveryDetail = detail
                self.discoveryDetailState = .loaded
            case .failure:
                self.discoveryDetail = nil
                self.discoveryDetailState = .failed
            }
        }
    }

    func closeDiscoveryDetail() {
        discoveryDetail = nil
        discoveryDetailState = .idle
    }

    // MARK: - Mods favoris (B3-T2)

    private static let favoriteModsKey = "favoriteMods"

    private static func loadFavoriteMods() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: favoriteModsKey) else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    private static func saveFavoriteMods(_ names: Set<String>) {
        guard let data = try? JSONEncoder().encode(names) else { return }
        UserDefaults.standard.set(data, forKey: favoriteModsKey)
    }

    // MARK: - Configs par profil (B3-T5)

    private static func loadProfileManagedConfigMods() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: UDKey.profileManagedConfigMods)
        else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    private static func saveProfileManagedConfigMods(_ names: Set<String>) {
        guard let data = try? JSONEncoder().encode(names) else { return }
        UserDefaults.standard.set(data, forKey: UDKey.profileManagedConfigMods)
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

        sweepOrphanProfileConfigStores()
    }

    /// Retire les magasins de configs dont plus aucun profil ne réclame la
    /// propriété (B3-T7).
    ///
    /// `deleteProfile` s'en charge désormais au moment du geste ; ce balayage
    /// est là pour les profils supprimés **avant** cette version, dont le
    /// magasin serait resté sur le disque à jamais — plus rien ne le lit, rien
    /// ne le nomme, rien ne l'effaçait.
    ///
    /// Le garde-fou vit dans `orphanFileNames` : une liste de profils vide ne
    /// rend jamais d'orphelin. Des préférences illisibles donnent exactement
    /// cette liste, et le balayage viderait alors tout le dossier.
    private func sweepOrphanProfileConfigStores() {
        guard let dir = ProfileConfigStore.directoryURL(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return }
        let orphans = ProfileConfigStore.orphanFileNames(
            in: names, knownProfileIds: Set(modProfiles.map(\.id)))
        var removed = 0
        for name in orphans
        where (try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))) != nil {
            removed += 1
        }
        guard removed > 0 else { return }
        log(String(format: L(L10n.VM.profileConfigsSwept), Int64(removed)))
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

    /// Les profils dont la dernière application n'a **pas** abouti : un
    /// déplacement en échec, ou un mod référencé absent du disque.
    ///
    /// Tant qu'un profil y figure, son contenu ne doit pas être réécrit depuis
    /// le disque — ce que le disque porte est l'accident, pas ce que
    /// l'utilisateur a demandé. Un profil en sort dès qu'une application
    /// aboutit, ou que l'utilisateur adopte délibérément l'état du disque
    /// (bascule d'un mod, suppression) : il n'y a plus alors d'écart en
    /// suspens. Non persisté : au prochain démarrage, le dossier tenu ouvert
    /// ne l'est plus, et l'utilisateur réapplique.
    private var incompletelyAppliedProfileIds: Set<UUID> = []

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
            // Amorçage : ce profil doit décrire l'installation telle qu'elle
            // est trouvée — c'est la base de référence, et elle est protégée
            // de la suppression. Vide, elle ne servirait à rien.
            createProfile(name: L(L10n.Profiles.defaultName), seed: .currentlyEnabledMods)
            // Record the seeded profile as the (undeletable) default.
            if let seeded = modProfiles.last {
                UserDefaults.standard.set(seeded.id.uuidString, forKey: defaultProfileKey)
            }
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// - Parameter seed: vide, ou l'instantané des mods actifs. Sans valeur
    ///   par défaut : le choix change ce que l'utilisateur obtient, et chaque
    ///   appelant doit le trancher explicitement.
    func createProfile(name: String, seed: ProfileSeed) {
        let made = ProfileFactory.make(name: name,
                                       seed: seed,
                                       enabledMods: mods.flattenedMods.filter(\.isEnabled))
        modProfiles.append(made.profile)
        // Un instantané peut devenir actif sur-le-champ : il décrit déjà l'état
        // du disque, aucun dossier à déplacer. Un profil vide, non — voir
        // `ProfileFactory.make`.
        if made.activate {
            activeProfileId = made.profile.id
        }
        saveProfiles()
        log(String(format: L(L10n.VM.profileCreated), name, made.profile.enabledModIds.count))
    }

    // MARK: - Récupérer un fichier isolé depuis une sauvegarde (B4-T4)

    /// Ce qu'une mise à jour de mod a emporté et qu'une sauvegarde peut rendre.
    /// Vide tant que `scanRecoverableFiles()` n'a pas tourné.
    @Published private(set) var recoverableFiles: [RecoverableFile] = []
    @Published private(set) var isScanningRecoverableFiles = false

    /// Balaye les sauvegardes d'installation à la recherche des fichiers perdus.
    ///
    /// En tâche de fond, et jamais automatiquement au démarrage : le balayage
    /// ouvre et décode plusieurs centaines de fichiers JSON.
    func scanRecoverableFiles() {
        guard !isScanningRecoverableFiles else { return }
        isScanningRecoverableFiles = true
        let backups = ModInstallBackupManager.shared.loadBackups()
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        // Le chemin **physique** de chaque mod, résolu depuis le scan : un mod
        // en pause vit sous `.Nom`, et un enfant de pack sous le dossier de son
        // pack. `physicalFolderName` porte déjà cette règle.
        let physicalPaths = Dictionary(
            mods.flattenedMods.map {
                ($0.folderName, (modsPath as NSString).appendingPathComponent($0.physicalFolderName))
            },
            uniquingKeysWith: { first, _ in first })

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = RecoverableFileScanner.scan(
                backups: backups,
                installedFolder: { physicalPaths[$0] },
                jsonKeys: { Self.topLevelJSONKeys(atPath: $0) },
                translationEntries: { Self.parseTranslation(atPath: $0) })
            DispatchQueue.main.async {
                self?.recoverableFiles = found
                self?.isScanningRecoverableFiles = false
            }
        }
    }

    /// Les clés de premier niveau d'un fichier JSON, `nil` s'il n'existe pas ou
    /// ne se décode pas.
    ///
    /// Le nettoyage passe par `ManifestJSON.sanitize` : les `config.json` et
    /// les `i18n/*.json` du parc portent commentaires et virgules traînantes
    /// comme les manifestes, et un décapage naïf couperait les URL en deux.
    private static func topLevelJSONKeys(atPath path: String) -> [String]? {
        guard let data = FileManager.default.contents(atPath: path),
              let raw = String(data: data, encoding: .utf8) else { return nil }
        guard let object = ManifestJSON.decode(raw) else { return nil }
        return Array(object.keys)
    }

    /// Réécrit un fichier perdu depuis sa sauvegarde.
    ///
    /// Le fichier encore en place — cas des clés perdues — est **sauvegardé
    /// d'abord** par le système de sauvegardes de configs : on n'écrase jamais
    /// sans filet ce que l'utilisateur a réglé depuis.
    @discardableResult
    func recoverFile(_ file: RecoverableFile) -> Bool {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: file.installedPath),
               let mod = mods.flattenedMods.first(where: { $0.folderName == file.folderName }) {
                _ = try ModConfigBackupManager.shared.createBackup(gameDir: gameDir, mods: [mod])
            }
            // L'écriture passe par `RecoveredFileWriter` : les dossiers de mods
            // sont souvent en lecture seule (`unzip`/`unrar` restituent les
            // modes de l'archive), et une copie directe échoue dessus.
            try RecoveredFileWriter.write(from: file.backupPath,
                                          to: file.installedPath,
                                          modRoot: file.installedRoot)
            log(String(format: L(L10n.Recovery.recovered), file.relativePath, file.modName))
            recoverableFiles.removeAll { $0.id == file.id }
            return true
        } catch {
            showModal(message: installErrorMessage(error))
            return false
        }
    }

    /// Le détail clé à clé entre la traduction d'une sauvegarde et celle du mod
    /// installé.
    ///
    /// C'est ce qui permet de récupérer une traduction **sans écraser** le
    /// travail fait depuis : une mise à jour rend souvent le fichier à sa
    /// version anglaise, le traducteur en refait une partie, et le reste dort
    /// dans la sauvegarde.
    func translationDiff(for file: RecoverableFile) -> [TranslationKeyDiff] {
        let backup = Self.parseTranslation(atPath: file.backupPath) ?? [:]
        let installed = Self.parseTranslation(atPath: file.installedPath) ?? [:]
        return TranslationRecoveryDiff.compare(backup: backup, installed: installed)
    }

    /// Lit un fichier de traduction comme le fait l'éditeur : décodage tolérant
    /// à l'encodage, puis analyse indulgente (commentaires, virgules
    /// traînantes, clés en double).
    private static func parseTranslation(atPath path: String) -> [String: String]? {
        guard let data = FileManager.default.contents(atPath: path),
              let text = I18nFileDecoder.decode(data)?.text,
              let parsed = try? I18nLenientParser.parse(text) else { return nil }
        return parsed
    }

    /// Réinjecte les clés choisies dans le fichier installé.
    ///
    /// Ne réécrit que les clés que l'installé **n'a plus** — `edits(for:)` le
    /// garantit une dernière fois — et passe par `TranslationDocument`, qui
    /// conserve l'ordre et la forme du fichier plutôt que de le réécrire à
    /// plat. Le `.bak` de `TranslationFileStore` reste le filet.
    @discardableResult
    func recoverTranslationKeys(_ diffs: [TranslationKeyDiff], in file: RecoverableFile) -> Bool {
        let edits = TranslationRecoveryDiff.edits(for: diffs)
        guard !edits.isEmpty else { return false }

        let target = URL(fileURLWithPath: file.installedPath)
        // La source donne le rang des clés neuves. Elle vit dans le même
        // dossier `i18n` que la cible ; sans elle, `TranslationDocument` ne
        // sait pas où ranger une clé absente du fichier.
        let i18nDirectory = target.deletingLastPathComponent()
        let sourceFiles = I18nLocaleResolver.files(in: i18nDirectory, locale: "default")
        let sourceFile = sourceFiles.first { $0.lastPathComponent == target.lastPathComponent }
            ?? sourceFiles.first
        guard let sourceFile,
              let sourceData = FileManager.default.contents(atPath: sourceFile.path),
              let sourceText = I18nFileDecoder.decode(sourceData)?.text else {
            showModal(message: L(L10n.Recovery.noSource))
            return false
        }

        do {
            let text: String
            if let data = FileManager.default.contents(atPath: file.installedPath),
               let existing = I18nFileDecoder.decode(data)?.text {
                text = try TranslationDocument.apply(edits: edits, toTarget: existing,
                                                     sourceText: sourceText)
            } else {
                text = try TranslationDocument.create(fromSource: sourceText, translations: edits)
            }
            // Le dossier du mod est souvent en lecture seule : même remède que
            // pour la copie d'un fichier entier.
            try RecoveredFileWriter.withWriteAccess(to: file.installedPath,
                                                    modRoot: file.installedRoot) {
                try TranslationFileStore.write(text, to: target)
            }
            log(String(format: L(L10n.Recovery.keysRecovered), Int64(edits.count), file.modName))
            scanRecoverableFiles()
            return true
        } catch {
            showModal(message: error.localizedDescription)
            return false
        }
    }

    /// Les mods qu'un profil réclame et qui ne sont plus installés, enrichis de
    /// tout ce que l'app sait encore d'eux.
    ///
    /// Trois sources, dans cet ordre : ce que le profil a retenu (le seul qui
    /// couvre vraiment, depuis le 2026-08-24), le cache des mises à jour Nexus,
    /// et l'index des sauvegardes — qui donne un nom, et surtout la possibilité
    /// de restaurer le mod sans réseau.
    func missingMods(in profile: ModProfile) -> [MissingProfileMod] {
        var backupNames: [String: String] = [:]
        for backup in ModInstallBackupManager.shared.loadBackups() {
            let key = backup.modMetadata.uniqueId.lowercased()
            guard !key.isEmpty, backupNames[key] == nil else { continue }
            backupNames[key] = backup.modMetadata.name
        }
        var hints: [String: ProfileModMetadata] = [:]
        for update in nexusUpdates where !update.uniqueId.isEmpty {
            hints[update.uniqueId.lowercased()] = ProfileModMetadata(name: update.name,
                                                                     nexusModId: update.nexusModId)
        }
        return ProfileDiagnostics.missingMods(in: profile,
                                              installedUniqueIds: mods.allUniqueIds,
                                              backupNames: backupNames,
                                              nexusHints: hints)
    }

    /// Restaure un mod absent depuis sa sauvegarde la plus récente, s'il en
    /// existe une. Rend faux quand il n'y en a pas.
    @discardableResult
    func restoreMissingModFromBackup(uniqueId: String) -> Bool {
        let manager = ModInstallBackupManager.shared
        guard let backup = manager.loadBackups()
            .filter({ $0.modMetadata.uniqueId.lowercased() == uniqueId.lowercased() })
            .max(by: { $0.timestamp < $1.timestamp }) else { return false }
        do {
            let report = try manager.restoreBackup(backup, gameDir: gameDir)
            log(String(format: L(L10n.ModInstall.restoreReportWritten),
                       report.modName, report.version, report.displayPath))
            refresh()
            return true
        } catch {
            showModal(message: installErrorMessage(error))
            return false
        }
    }

    /// Ajoute un mod installé au profil — le geste de réparation d'une
    /// dépendance requise que le profil laissait de côté.
    ///
    /// Passe par `updateProfile`, donc l'ajout est appliqué au disque
    /// immédiatement si le profil est actif : c'est bien ce qu'on demande en
    /// ajoutant une dépendance manquante, que le mod se remette à tourner.
    func addModToProfile(id: UUID, uniqueId: String) {
        guard let index = modProfiles.firstIndex(where: { $0.id == id }) else { return }
        let key = uniqueId.lowercased()
        guard !modProfiles[index].enabledModIds.contains(where: { $0.lowercased() == key }) else { return }

        // Ce qu'on sait du mod entre dans le profil avec lui : c'est tout ce
        // qui restera le jour où il aura été désinstallé.
        if let mod = mods.flattenedMods.first(where: { $0.uniqueId.lowercased() == key }) {
            modProfiles[index].modMetadata[mod.uniqueId] = ProfileModMetadata(name: mod.name,
                                                                             nexusModId: mod.nexusModId)
        }
        var ids = modProfiles[index].enabledModIds
        ids.append(uniqueId)
        updateProfile(id: id, newName: modProfiles[index].name, enabledModIds: ids)
        log(String(format: L(L10n.VM.profileCreated), modProfiles[index].name, ids.count))
    }

    /// Marque ou démarque un mod comme favori. Persisté aussitôt : c'est un
    /// geste isolé, il n'a pas d'enregistrement différé où se raccrocher.
    func toggleFavorite(_ mod: ModItem) {
        if favoriteMods.contains(mod.folderName) {
            favoriteMods.remove(mod.folderName)
        } else {
            favoriteMods.insert(mod.folderName)
        }
        Self.saveFavoriteMods(favoriteMods)
    }

    func isFavorite(_ mod: ModItem) -> Bool { favoriteMods.contains(mod.folderName) }

    /// Un mod peut-il porter des configs par profil ?
    ///
    /// Un **en-tête de pack** ne le peut pas : il n'a pas de réglages propres,
    /// ses composants en ont chacun les leurs et se marquent eux-mêmes. Même
    /// arbitrage que les notes (F4), pour une raison différente — là c'était
    /// l'absence d'identité, ici l'absence de config.
    ///
    /// L'absence d'`UniqueID` n'exclut rien, contrairement aux profils : le
    /// magasin est indexé par dossier. Un tel mod reste actif dans tous les
    /// profils, et son config peut légitimement y changer.
    func canManageProfileConfig(_ mod: ModItem) -> Bool { !mod.isGroup }

    func isProfileConfigManaged(_ mod: ModItem) -> Bool {
        profileManagedConfigMods.contains(mod.folderName)
    }

    /// Pose ou retire la marque. Persisté aussitôt, comme les favoris : c'est
    /// un geste isolé, il n'a pas d'enregistrement différé où se raccrocher.
    ///
    /// **Prend la valeur voulue, ne bascule pas.** Un `Toggle` SwiftUI appelle
    /// le `set` de sa liaison avec la valeur affichée lors d'un re-rendu ou
    /// d'une animation ; un setter qui ignorerait son argument pour basculer
    /// démarquerait alors le mod tout seul, en silence. Même forme que
    /// `setCustomCategory`, le patron du dépôt pour ce cas.
    ///
    /// Retirer la marque **ne détruit rien** : les textes mémorisés restent
    /// dans les magasins des profils, et remarquer le mod les reprend.
    func setProfileConfigManaged(_ mod: ModItem, _ on: Bool) {
        guard canManageProfileConfig(mod) else { return }
        let changed = on
            ? profileManagedConfigMods.insert(mod.folderName).inserted
            : (profileManagedConfigMods.remove(mod.folderName) != nil)
        guard changed else { return }
        Self.saveProfileManagedConfigMods(profileManagedConfigMods)
    }

    /// Ce que chaque profil a mémorisé pour ce mod, et si cela correspond
    /// encore au fichier sur disque.
    ///
    /// `matchesDisk` est le renseignement qui empêche de croire à une panne :
    /// après un aller-retour entre deux profils, les deux mémorisent le même
    /// texte et rien ne diffère tant que le mod n'a pas été réglé dans l'un des
    /// deux. Comparaison d'octets — le décompte des clés viendra avec l'écran
    /// de comparaison.
    func profileConfigHolders(for mod: ModItem)
        -> [(profileName: String, capturedAt: Date, bytes: Int, matchesDisk: Bool)] {
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let url = ProfileConfigStore.configURL(modsPath: modsPath,
                                               physicalFolderName: mod.physicalFolderName)
        let onDisk = try? String(contentsOf: url, encoding: .utf8)
        return modProfiles.compactMap { profile in
            guard let storeURL = ProfileConfigStore.fileURL(profileId: profile.id),
                  let entry = ProfileConfigStore.load(from: storeURL)[mod.folderName]
            else { return nil }
            return (profileName: profile.name,
                    capturedAt: entry.capturedAt,
                    bytes: entry.text.utf8.count,
                    matchesDisk: entry.text == onDisk)
        }
    }

    /// Le texte qu'un profil a mémorisé pour ce mod, ou `nil`.
    func profileConfigText(mod: ModItem, profile: ModProfile) -> String? {
        guard let url = ProfileConfigStore.fileURL(profileId: profile.id) else { return nil }
        return ProfileConfigStore.load(from: url)[mod.folderName]?.text
    }

    /// Ce qu'un profil retient, et ce qui n'a plus de dossier installé.
    ///
    /// Les orphelins sont **gardés, pas purgés** (spec §6.5) : réinstaller
    /// le mod doit lui rendre ses réglages. Cette fonction est la seule à
    /// les nommer — la fiche d'un mod part d'un `ModItem`, qu'un mod
    /// désinstallé n'a pas.
    func profileConfigSummary(for profile: ModProfile) -> (total: Int, orphans: [String]) {
        guard let url = ProfileConfigStore.fileURL(profileId: profile.id) else {
            return (0, [])
        }
        let entries = ProfileConfigStore.load(from: url)
        // `folderName` reste logique : un mod en pause porte un point sur le
        // disque, pas dans son identité — sans quoi mettre un mod en pause
        // le ferait passer pour désinstallé.
        let installed = Set(mods
            .flatMap { $0.isGroup ? ($0.children ?? []) : [$0] }
            .map(\.folderName))
        let orphans = entries.keys
            .filter { !installed.contains($0) }
            .sorted()
        return (entries.count, orphans)
    }

    /// Les écarts entre ce que deux profils retiennent de ce mod. `nil` :
    /// un des deux textes ne se parse pas — l'écran affiche l'explication,
    /// jamais un diff inventé.
    func profileConfigDiffs(mod: ModItem, other: ModProfile) -> [ConfigKeyDiff]? {
        guard let active = modProfiles.first(where: { $0.id == activeProfileId }),
              let textA = profileConfigText(mod: mod, profile: active),
              let textB = profileConfigText(mod: mod, profile: other),
              let treeA = ConfigJSONTree.parse(textA),
              let treeB = ConfigJSONTree.parse(textB) else { return nil }
        return ConfigJSONDiff.compare(treeA, treeB)
    }

    /// Supprime le `config.json` du mod — pas de « réinitialisation » possible,
    /// l'app ne connaît pas les valeurs par défaut : elles vivent dans la classe
    /// C# du mod. SMAPI n'en réécrit un fichier neuf au prochain lancement que
    /// pour les mods qui appellent `helper.ReadConfig<T>()` ; un mod qui n'en lit
    /// jamais un n'en récrira jamais un non plus — mesuré sur le parc réel :
    /// seuls 547 dossiers de mods sur 1015 portent un `config.json`, soit
    /// environ 46 %.
    ///
    /// - Returns: `true` si un fichier a bien été supprimé.
    @discardableResult
    func resetModConfigToDefaults(_ mod: ModItem) -> Bool {
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let url = ProfileConfigStore.configURL(modsPath: modsPath,
                                               physicalFolderName: mod.physicalFolderName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Seulement 169 mods sur ~900 portent un config.json, et le bouton
            // reste actif pour tous les mods non-groupes : sans ce log, un clic
            // sur un mod qui n'en a pas ne laisse aucune trace nulle part.
            log(String(format: L(L10n.VM.profileConfigResetAbsent), mod.folderName), level: .info)
            return false
        }
        // Le dossier du mod est souvent en lecture seule (`unzip`/`unrar`
        // restituent les modes de l'archive — X7). Même remède que
        // `recoverFile` : ouvrir les droits d'écriture jusqu'à la racine du
        // mod, jamais au-delà, puis les rendre tels qu'on les a trouvés.
        let modRoot = url.deletingLastPathComponent().path
        do {
            try RecoveredFileWriter.withWriteAccess(to: url.path, modRoot: modRoot) {
                try ModZipInstaller.removeItemGrantingWriteAccess(atPath: url.path)
            }
            log(String(format: L(L10n.VM.profileConfigResetDone), mod.folderName))
            return true
        } catch {
            log(String(format: "config.json: %@ — %@", mod.folderName,
                       error.localizedDescription), level: .error)
            return false
        }
    }

    /// Ce que donnerait un import des favoris dans ce profil, sans rien
    /// écrire. Sert à l'écran : dire combien de mods entreraient, et lesquels
    /// ne le peuvent pas, **avant** de toucher au disque.
    func favoriteImportPreview(profileId: UUID) -> FavoriteResolution.Result {
        guard let profile = modProfiles.first(where: { $0.id == profileId }) else {
            return FavoriteResolution.Result(ids: [], unresolved: [])
        }
        return FavoriteResolution.profileIds(favorites: favoriteMods, in: mods,
                                             existing: profile.enabledModIds)
    }

    /// Ajoute tous les favoris à un profil, **en une seule mutation**.
    ///
    /// Surtout pas une boucle sur `addModToProfile` : chacun de ses appels
    /// passe par `updateProfile`, qui réapplique le profil au disque quand il
    /// est actif. Importer trente favoris déclencherait trente passes de
    /// renommage de dossiers sur un parc de 863 mods.
    ///
    /// `modMetadata` est renseigné dans la même passe : c'est la seule source
    /// qui permette encore de **nommer** un mod du profil une fois qu'il aura
    /// été désinstallé (voir le diagnostic de profil). L'omettre ici
    /// dégraderait ce diagnostic pour les seuls mods entrés par cet import,
    /// sans que rien ne le montre avant des mois.
    ///
    /// - Returns: ce qui a été fait, pour que l'appelant le dise.
    @discardableResult
    func importFavorites(into profileId: UUID) -> FavoriteResolution.Result {
        guard let index = modProfiles.firstIndex(where: { $0.id == profileId }) else {
            return FavoriteResolution.Result(ids: [], unresolved: [])
        }
        let resolution = FavoriteResolution.profileIds(
            favorites: favoriteMods, in: mods,
            existing: modProfiles[index].enabledModIds)
        guard !resolution.ids.isEmpty else { return resolution }

        let byId = Dictionary(mods.flattenedMods.map { ($0.uniqueId.lowercased(), $0) },
                              uniquingKeysWith: { first, _ in first })
        for id in resolution.ids {
            guard let mod = byId[id.lowercased()] else { continue }
            modProfiles[index].modMetadata[id] = ProfileModMetadata(name: mod.name,
                                                                    nexusModId: mod.nexusModId)
        }
        // Capturés **avant** `updateProfile` : sur un profil actif, il
        // réapplique le profil au disque, et le rescan qui suit fait passer
        // `syncActiveProfileIds`, qui réécrit `enabledModIds` depuis les mods
        // réellement activés. Relire la ligne après coup, c'est risquer de
        // journaliser l'état du disque plutôt que le résultat de l'import.
        let name = modProfiles[index].name
        let newIds = modProfiles[index].enabledModIds + resolution.ids
        updateProfile(id: profileId, newName: name, enabledModIds: newIds)
        log(String(format: L(L10n.VM.profileCreated), name, newIds.count))
        return resolution
    }

    /// Copie un profil existant, sous le nom « <original> (copie) ».
    ///
    /// La copie n'est **pas** activée : dupliquer sert à partir d'une base pour
    /// la modifier, et une activation déplacerait aussitôt des dossiers de mods
    /// que personne n'a demandé de bouger.
    func duplicateProfile(id: UUID) {
        guard let source = modProfiles.first(where: { $0.id == id }) else { return }
        let copy = ProfileFactory.duplicate(source, nameFormat: L(L10n.Profiles.copyNameFormat))
        modProfiles.append(copy)
        saveProfiles()
        log(String(format: L(L10n.VM.profileCreated), copy.name, copy.enabledModIds.count))
    }

    func deleteProfile(id: UUID) {
        // The default profile is protected — never delete it.
        guard !isDefaultProfile(id) else { return }
        if let name = modProfiles.first(where: { $0.id == id })?.name {
            log(String(format: L(L10n.VM.profileDeleted), name))
        }
        modProfiles.removeAll { $0.id == id }
        // Le magasin de configs part avec le profil (B3-T7) : plus aucun
        // écran ne pourrait le nommer, et rien ne le relirait jamais. Le
        // dialogue de confirmation prévient quand il y a quelque chose à
        // perdre — c'est là que la décision se prend, pas ici.
        ProfileConfigStore.delete(profileId: id)
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

    // MARK: - Mod notes (B3-T6)

    /// La note du mod dans le **profil actif** — la note vit au profil, elle
    /// change avec lui. Nil sans note comme sans profil actif.
    func modNote(for mod: ModItem) -> String? {
        activeProfile?.note(forModId: mod.uniqueId)
    }

    /// Écrit la note du mod sur le profil actif (sauvegarde immédiate). La
    /// règle — note vidée retirée, identifiant vide ignoré — vit dans
    /// `ModProfile.setNote` (Core, testée) ; le VM ne fait que router.
    func setModNote(_ text: String?, for mod: ModItem) {
        guard let activeId = activeProfileId,
              let index = modProfiles.firstIndex(where: { $0.id == activeId }) else { return }
        modProfiles[index].setNote(text, forModId: mod.uniqueId)
        saveProfiles()
    }

    /// Renames a profile in place (its enabled-mod set is untouched).
    func renameProfile(id: UUID, newName: String) {
        guard let index = modProfiles.firstIndex(where: { $0.id == id }) else { return }
        modProfiles[index].name = newName
        saveProfiles()
    }

    // MARK: - Incompatibilités entre mods (A5-T2)

    /// Les incompatibilités que l'utilisateur a déclarées ou écartées.
    /// Chargé au démarrage (dans `seedNexusAndUserData`, avec les autres
    /// registres utilisateur), réécrit à chaque décision. Fichier :
    /// `Application Support/StarHubTH/mod_conflicts.json`.
    @Published private(set) var modConflictVerdicts = ModConflictVerdicts()

    /// Écrit le magasin, et **le dit quand il n'a pas pu** — même patron que
    /// `InstalledTranslationStore` : un verdict qui ne survit pas à la
    /// fermeture doit se voir, pas se taire.
    func saveConflictVerdicts() {
        if !ModConflictVerdictsStore.save(modConflictVerdicts) {
            log("Verdict non enregistré : il ne survivra pas à la fermeture", level: .warning)
        }
    }

    /// Déclare une incompatibilité entre deux mods, saisie par l'utilisateur
    /// depuis la fiche (tâche 9). `modConflictVerdicts` est `@Published
    /// private(set)` : ce mutateur vit ici, dans le corps de la classe — pas
    /// dans une extension ni dans la vue — pour garder l'écriture au même
    /// endroit que la lecture.
    func declareConflict(_ pair: ModConflictPair, note: String) {
        modConflictVerdicts.declare(pair, note: note, at: Date())
        saveConflictVerdicts()
    }

    /// Écarte une paire — un constat du journal jugé faux, ou un signalement
    /// que l'utilisateur reprend. Même mutateur pour les deux usages : le
    /// magasin ne distingue pas la source, seulement le verdict courant.
    func dismissConflict(_ pair: ModConflictPair, note: String = "") {
        modConflictVerdicts.dismiss(pair, note: note, at: Date())
        saveConflictVerdicts()
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

    // MARK: - Configs par profil : capture et restauration (B3-T5)

    /// Le profil actif dont le disque ne porte **pas** les configs (§6.3) :
    /// une bascule antérieure faite jeu ouvert a sauté capture et/ou
    /// restauration, et le disque tient encore les réglages d'un autre
    /// profil que celui qui est actif. `nil` si aucun profil n'est dans ce
    /// cas. Persisté dans `UserDefaults` : quitter l'application entre les
    /// deux bascules incriminées ne doit pas effacer le trou.
    private static var profileConfigsDesyncedProfileId: UUID? {
        get {
            UserDefaults.standard.string(forKey: UDKey.profileConfigsDesyncedProfileId)
                .flatMap(UUID.init(uuidString:))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString,
                                          forKey: UDKey.profileConfigsDesyncedProfileId)
            } else {
                UserDefaults.standard.removeObject(forKey: UDKey.profileConfigsDesyncedProfileId)
            }
        }
    }

    /// Pose ou lève la marque de désynchronisation. `entering` est
    /// l'identifiant du profil qui devient actif — `nil` quand on ne fait que
    /// quitter le profil courant, sans en prendre un autre.
    ///
    /// Jeu ouvert : la capture du sortant (et, pour une vraie bascule, la
    /// restauration de l'entrant, plus tard dans le completion) sont
    /// sautées, chacune se gardant elle-même. Un `entering` connu est marqué
    /// désynchronisé, pour que la prochaine capture le concernant refuse
    /// d'attribuer à son magasin un disque qui n'est pas le sien. Sans
    /// `entering` (on ne fait que quitter), il n'y a personne à marquer — la
    /// marque existante, si elle porte sur un autre profil, n'a pas à
    /// bouger.
    ///
    /// Jeu fermé : la bascule tient sa promesse normalement, la marque n'a
    /// plus lieu d'être.
    private func syncProfileConfigsDesyncMarker(entering: UUID?) {
        guard isGameRunning() else {
            Self.profileConfigsDesyncedProfileId = nil
            return
        }
        if let entering {
            Self.profileConfigsDesyncedProfileId = entering
        }
    }

    /// Les mods marqués, présents dans le parc courant, avec leur chemin de
    /// config sur disque. Le nom **physique** est employé pour le chemin (un
    /// mod en pause vit dans un dossier préfixé par un point) et le nom
    /// **logique** comme clé du magasin.
    private func managedConfigTargets() -> [(key: String, url: URL)] {
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        return mods
            .flatMap { $0.isGroup ? ($0.children ?? []) : [$0] }
            .filter { profileManagedConfigMods.contains($0.folderName) }
            .map { (key: $0.folderName,
                    url: ProfileConfigStore.configURL(modsPath: modsPath,
                                                      physicalFolderName: $0.physicalFolderName)) }
    }

    /// Mémorise le `config.json` de chaque mod marqué au crédit de ce profil.
    ///
    /// **N'appeler que sur une transition réelle de profil** (§6.3 de la
    /// spec) : jamais à la reprise d'une application incomplète, jamais dans
    /// `syncActiveProfileIds`. À la reprise, le disque porte déjà les réglages
    /// du profil *entrant* ; les capturer au crédit du sortant écraserait son
    /// config dans le geste même censé rattraper une erreur.
    func captureProfileConfigs(for profileId: UUID) {
        guard !isGameRunning() else {
            log(L(L10n.VM.profileConfigsSkippedGame), level: .warning)
            return
        }
        // Une bascule antérieure, faite jeu ouvert, a laissé ce profil actif
        // sans que son disque en porte les réglages (§6.3) — il tient encore
        // ceux d'un autre profil. Capturer ici attribuerait ce contenu
        // étranger au magasin de ce profil ; mieux vaut laisser le trou
        // visible que le maquiller en donnée fausse.
        guard Self.profileConfigsDesyncedProfileId != profileId else {
            let name = modProfiles.first(where: { $0.id == profileId })?.name ?? ""
            log(String(format: L(L10n.VM.profileConfigsDesynced), name), level: .warning)
            return
        }
        guard let url = ProfileConfigStore.fileURL(profileId: profileId) else { return }
        var entries = ProfileConfigStore.load(from: url)
        let before = entries
        let now = Date()
        for target in managedConfigTargets() {
            // Le texte, lu depuis le disque et non depuis un cache de scan :
            // c'est l'état réel du fichier au moment de la bascule qui compte.
            let text = try? String(contentsOf: target.url, encoding: .utf8)
            entries = ProfileConfigStore.captured(entries, folderName: target.key,
                                                  diskText: text, now: now)
        }
        guard entries != before else { return }
        ProfileConfigStore.save(entries, to: url)
        // Ce que cette passe a changé, pas le total du magasin : « 12 configs
        // mémorisés » quand un seul a bougé donnerait une fausse idée de ce
        // que la bascule vient de faire. Symétrique du compte de restauration.
        let touched = Set(entries.keys).symmetricDifference(before.keys).count
            + entries.filter { before[$0.key]?.text != nil && before[$0.key]?.text != $0.value.text }.count
        let name = modProfiles.first(where: { $0.id == profileId })?.name ?? ""
        log(String(format: L(L10n.VM.profileConfigsCaptured), name, touched))
    }

    /// Réécrit dans chaque mod marqué le `config.json` que ce profil avait
    /// mémorisé. Un mod sans texte mémorisé n'est **pas touché** — c'est la
    /// règle du premier passage : le profil entrant adoptera le fichier tel
    /// quel à la capture suivante.
    ///
    /// Rejouable sans dommage à la reprise d'une application incomplète :
    /// réécrire le même texte est idempotent, contrairement à la capture.
    func restoreProfileConfigs(for profileId: UUID) {
        guard !isGameRunning() else {
            log(L(L10n.VM.profileConfigsSkippedGame), level: .warning)
            return
        }
        guard let url = ProfileConfigStore.fileURL(profileId: profileId) else { return }
        let entries = ProfileConfigStore.load(from: url)
        guard !entries.isEmpty else { return }
        var verbatim = 0
        var merged = 0
        var reintroducedKeys = 0
        for target in managedConfigTargets() {
            guard let entry = entries[target.key] else { continue }
            // Le dossier a pu disparaître entre-temps : ne rien écrire, et
            // garder l'entrée — réinstaller le mod doit lui rendre ses
            // réglages.
            let modRoot = target.url.deletingLastPathComponent().path
            guard FileManager.default.fileExists(atPath: modRoot) else { continue }
            // Le merge d'abord (spec §5.3) : le fichier sur disque peut avoir
            // gagné des clés depuis la mémorisation — le mod a été mis à jour.
            // Le verbatim les écrasait ; le merge les garde et réapplique les
            // réglages du profil par-dessus. Tout ce qui ne se parse pas
            // retombe sur le verbatim, qui reste le comportement de base.
            let diskText = try? String(contentsOf: target.url, encoding: .utf8)
            let result = diskText.flatMap {
                ConfigJSONMerge.mergedText(disk: $0, memorized: entry.text)
            }
            do {
                // Le dossier du mod est souvent en lecture seule — même remède
                // que `recoverFile` : cette écriture rejoue à chaque bascule de
                // profil, pour chaque mod marqué, bien plus souvent que le
                // bouton « Repartir des réglages par défaut ».
                try RecoveredFileWriter.withWriteAccess(to: target.url.path, modRoot: modRoot) {
                    try (result?.text ?? entry.text)
                        .write(to: target.url, atomically: true, encoding: .utf8)
                }
                if let result {
                    merged += 1
                    reintroducedKeys += result.addedKeyPaths
                } else {
                    verbatim += 1
                }
            } catch {
                log(String(format: "config.json: %@ — %@",
                           target.key, error.localizedDescription), level: .error)
            }
        }
        guard verbatim + merged > 0 else { return }
        let name = modProfiles.first(where: { $0.id == profileId })?.name ?? ""
        // Deux comptes plutôt qu'un : « restaurés » masquerait qu'une partie
        // l'a été sans merge, faute d'un texte lisible — la seule information
        // qui distingue une restauration fidèle d'un repli.
        if merged > 0 {
            log(String(format: L(L10n.VM.profileConfigsMerged), name,
                       Int64(verbatim), Int64(merged), Int64(reintroducedKeys)))
        } else {
            log(String(format: L(L10n.VM.profileConfigsRestored), name, verbatim))
        }
    }

    func applyProfile(id: UUID?) {
        // Serialize activations: refuse to start a new one while a previous
        // profile is still being applied (mod folders being renamed /
        // rescanned), so two activations can't race on the same paths.
        guard !isApplyingProfile else { return }

        guard let id = id, let profile = modProfiles.first(where: { $0.id == id }) else {
            // Quitter un profil sans en prendre un autre est une transition
            // réelle : le config est capturé au crédit du profil qu'on quitte,
            // même si aucun dossier ne bouge.
            if let leaving = activeProfileId { captureProfileConfigs(for: leaving) }
            syncProfileConfigsDesyncMarker(entering: nil)
            activeProfileId = nil
            saveProfiles()
            return
        }

        // Activation is exclusive: setting activeProfileId below replaces any
        // previously-active profile (only one can be active at a time).
        if activeProfileId == id {
            if incompletelyAppliedProfileIds.contains(id) {
                // La dernière application s'est arrêtée en chemin. Re-cliquer
                // le profil actif est le seul geste de reprise offert (le
                // bouton « Activer » est masqué pour lui) : reprendre les
                // déplacements, plutôt qu'enregistrer l'état où l'échec les a
                // laissés — ce qui effacerait justement ce qu'il restait à
                // faire.
                applyingProfileId = id
                applyProfileToFilesystem(profile: profile)
            } else {
                // Cas courant : le profil actif adopte les bascules faites à
                // la main depuis la page des mods.
                syncActiveProfileIds()
            }
            return
        }

        // Capture AVANT tout : le disque porte encore les réglages du profil
        // sortant. C'est la seule fenêtre où ils existent.
        if let leaving = activeProfileId { captureProfileConfigs(for: leaving) }
        syncProfileConfigsDesyncMarker(entering: id)
        activeProfileId = id
        saveProfiles()
        applyingProfileId = id
        // Restauration dans le completion : après les déplacements de dossiers
        // et après le rescane, quand les chemins sont ceux du profil entrant.
        applyProfileToFilesystem(profile: profile) { [weak self] _ in
            self?.restoreProfileConfigs(for: id)
        }
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
        // Detect profile entries that don't match any installed mod. These
        // are silently skipped by the move loops below, but the user must be
        // told the profile references mods that aren't there (e.g. uninstalled
        // since the profile was saved). Compare every profile enabledId
        // against the set of uniqueIds present on disk (groups resolved to
        // their children's ids), so a pack mod isn't reported missing when
        // one of its children satisfies the id.
        let snapshotMods = mods
        // Même calcul que l'écran des mods manquants : une seule définition de
        // « le profil réclame un mod qui n'est plus là », sinon l'alerte de fin
        // d'application et l'écran finissent par ne plus dire la même chose.
        let missingIds = ProfileDiagnostics.missingMods(in: profile,
                                                        installedUniqueIds: snapshotMods.allUniqueIds,
                                                        backupNames: [:],
                                                        nexusHints: [:]).map(\.uniqueId)

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

        // Les deux listes de travail sont arrêtées **ici**, sur l'instantané,
        // et pas relues dans la boucle : les déplacements tournent en tâche de
        // fond, et `mods` est réécrit par `scanMods` — le parcourir de là
        // serait lire un tableau en cours de mutation.
        let toDisable = snapshotMods.filter {
            $0.isEnabled && isProfileManageable($0) && !isCoveredByProfile($0)
        }
        let toEnable = snapshotMods.filter { !$0.isEnabled && isCoveredByProfile($0) }

        let profileName = profile.name
        let profileId = profile.id
        // Le total est connu d'avance : la barre est déterminée dès le premier
        // dossier. Publié avant le dispatch pour que le voile soit là au
        // premier rendu, sans clignotement.
        let total = toDisable.count + toEnable.count
        profileApplyProgress = ProfileApplyProgress(done: 0, total: total, phase: .movingFolders)

        DispatchQueue.global(qos: .userInitiated).async {
            var failures: [MoveFailure] = []
            var attempted = 0
            var anyEnabled = false
            var done = 0

            // Rename a mod folder within Mods/ to flip its enabled/disabled
            // state via the dot-prefix convention. `srcPhysical` is the current
            // on-disk name (with dot if disabled), `dstPhysical` is the target
            // name. Never throws, so the loop keeps processing the remaining
            // mods instead of aborting at the first error.
            func renameModFolder(_ mod: ModItem, from srcPhysical: String, to dstPhysical: String, direction: String) {
                attempted += 1
                do {
                    try fm.moveItem(atPath: srcPhysical, toPath: dstPhysical)
                } catch {
                    failures.append(MoveFailure(modName: mod.name, direction: direction, error: error))
                }
            }

            // Un pas sur 1 %, et le dernier dossier quoi qu'il arrive : publier
            // à chaque dossier ferait redessiner toute la fenêtre près de mille
            // fois pour une barre large de 280 points — le voile coûterait plus
            // cher que les déplacements qu'il annonce.
            let publishStep = max(1, total / 100)
            func publishProgress() {
                done += 1
                let current = done
                guard current == total || current % publishStep == 0 else { return }
                DispatchQueue.main.async {
                    self.profileApplyProgress = ProfileApplyProgress(done: current,
                                                                     total: total,
                                                                     phase: .movingFolders)
                }
            }

            // Disable mods not in profile: rename Mods/X → Mods/.X
            for mod in toDisable {
                let src = (modsPath as NSString).appendingPathComponent(mod.physicalFolderName)
                let dst = (modsPath as NSString).appendingPathComponent("." + mod.folderName)
                renameModFolder(mod, from: src, to: dst, direction: "→ désactivé")
                publishProgress()
            }

            // Enable mods in profile: rename Mods/.X → Mods/X. Only stamp the
            // activation timestamp for mods that were actually moved — stamping
            // a mod that failed to rename would record a phantom "last
            // activation" for a folder that is still sitting disabled.
            for mod in toEnable {
                let src = (modsPath as NSString).appendingPathComponent(mod.physicalFolderName)
                let dst = (modsPath as NSString).appendingPathComponent(mod.folderName)
                let beforeCount = failures.count
                renameModFolder(mod, from: src, to: dst, direction: "→ activé")
                if failures.count == beforeCount {
                    // `modActivationTimestamps` appartient au thread principal,
                    // comme dans `toggleAllMods` : les écritures y arrivent dans
                    // l'ordre, et l'enregistrement plus bas les voit toutes.
                    DispatchQueue.main.async {
                        self.modActivationTimestamps[mod.folderName] = Date()
                    }
                    anyEnabled = true
                }
                publishProgress()
            }
            if anyEnabled {
                DispatchQueue.main.async {
                    Self.saveModActivationTimestamps(self.modActivationTimestamps)
                }
            }

            // Log each move failure individually with a localized, structured
            // message so the Logs tab (source = StarHubFR) shows exactly which
            // mod(s) failed, in which direction, and why.
            for failure in failures {
                self.log(
                    String(format: self.L(L10n.VM.applyProfileMoveFail),
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
                self.log(
                    String(format: self.L(L10n.VM.applyProfileMissing),
                           profileName, missingIds.count, listing),
                    level: .warning
                )
            }

            let failedNames = failures.map { $0.modName }
            // Les dossiers sont en place ; ce qui suit est la relecture du
            // parc. Le voile le dit, sinon la barre reste pleine et figée
            // pendant tout le rescane — c'est le moment où l'utilisateur croit
            // que l'app a fini alors qu'elle travaille encore.
            DispatchQueue.main.async {
                self.profileApplyProgress = ProfileApplyProgress(done: total,
                                                                 total: total,
                                                                 phase: .rescanning)
            }
            // Always rescan so the list reflects the real on-disk state,
            // whatever it is after partial failures.
            self.scanMods()
            DispatchQueue.main.async {
                self.profileApplyProgress = nil
                // Le profil actif ne suit le disque que si l'application a
                // abouti. Un déplacement en échec — dossier tenu ouvert,
                // permissions — n'est pas une décision de l'utilisateur :
                // adopter l'état du disque écrirait l'accident dans le profil.
                // Le mod resté actif faute d'avoir pu bouger deviendrait un mod
                // que le profil *demande*, et réessayer l'activation n'aurait
                // plus rien à faire. On laisse le profil dire ce qui était
                // voulu ; l'alerte ci-dessous dit, elle, ce qui s'est passé.
                if failures.isEmpty && missingIds.isEmpty {
                    self.incompletelyAppliedProfileIds.remove(profileId)
                    self.syncActiveProfileIds()
                } else {
                    self.incompletelyAppliedProfileIds.insert(profileId)
                }
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
            // Le favori part avec le mod : le garder gonflerait indéfiniment
            // le compteur de la pastille de cadrage avec des dossiers qui
            // n'existent plus.
            if favoriteMods.remove(mod.folderName) != nil {
                Self.saveFavoriteMods(favoriteMods)
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

        let enabledMods = mods.flattenedMods.filter(\.isEnabled).filter { !$0.uniqueId.isEmpty }

        modProfiles[index].enabledModIds = enabledMods.map(\.uniqueId)
        // Le nom et l'identifiant Nexus sont rafraîchis en même temps : ce sont
        // les seules traces qui resteront le jour où l'un de ces mods aura été
        // désinstallé. Ce qui était su des mods **sortis** du profil est
        // abandonné avec eux — le profil ne les réclame plus.
        modProfiles[index].modMetadata = ProfileFactory.metadata(of: enabledMods)
        saveProfiles()
        // Le profil vient d'adopter l'état du disque : il n'y a plus d'écart
        // en suspens à protéger.
        incompletelyAppliedProfileIds.remove(id)
    }
}
