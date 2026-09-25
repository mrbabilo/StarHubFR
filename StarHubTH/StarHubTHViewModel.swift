import Foundation
import Observation
import Combine
import Cocoa
import SwiftUI

@MainActor
@Observable
final class StarHubTHViewModel {
    // MARK: Sauvegardes — le store du domaine (cadrage §4, domaine 1). Les
    // étiquettes arrivent en closure (le store ignore `SaveNotesStore`) ;
    // exposé pour son verrou d'écriture (A1-T10).
    let savesStore = SavesStore(
        tagForSave: { SaveNotesStore.shared.note(for: $0).tag }
    )

    var saveViewMode: SaveViewMode {
        get { savesStore.viewMode }
        set { savesStore.viewMode = newValue }
    }
    var saveSortOption: SaveSortOption {
        get { savesStore.sortOption }
        set { savesStore.sortOption = newValue }
    }
    var saveFilterTag: String {
        get { savesStore.filterTag }
        set { savesStore.filterTag = newValue }
    }
    var saves: [SaveGameInfo] { savesStore.saves }
    var isSaveOperationRunning: Bool { savesStore.isOperationRunning }

    // MARK: Environnement — le store du domaine (REFACTORING §6), et ses
    // façades de lecture (condition 1).
    //
    // `gameDir` ne se rafraîchit pas seul : qui le change (init,
    // selectGameDir) relance `refresh()` une fois — l'ancien auto-refresh
    // lançait deux scans concurrents sur `gameDir` et `mods`.
    private let environment = GameEnvironmentStore(picker: LiveFilePicker())
    private let imagePicker: ImagePicking = LiveImagePicker()

    var gameDir: String { environment.gameDir }
    var steamUsername: String { environment.steamUsername }
    var steamAvatarPath: String? { environment.steamAvatarPath }
    var smapiInstalledVersion: String? { environment.smapiInstalledVersion }

    // MARK: Localisation — le store du domaine (REFACTORING §6). Il
    // appartient à l'App (init + menus) ; les vues le reçoivent en paramètre.
    let localization: LocalizationStore
    
    /// Mods que **SMAPI** signale périmés (même lecture que la date).
    var outOfDateMods: [ModUpdateInfo] { smapiHealth.outOfDateMods }
    // MARK: Santé SMAPI — le store du domaine (cadrage §4, domaine 2,
    // tranche 2) : ce que le journal dit de l'installation ; les lignes
    // affichées vivent dans `logStore`.
    private let smapiHealth = SmapiHealthStore()

    /// Les alertes système de la dernière lecture.
    var smapiErrors: [String] { smapiHealth.errors }
    /// SMAPI health card diagnostics (nil until first parse).
    var smapiDiagnostics: SmapiDiagnostics? { smapiHealth.diagnostics }
    /// mtime of the parsed SMAPI log (nil if unread); used for the "stale" badge.
    var smapiLogDate: Date? { smapiHealth.logDate }
    /// True when the log predates this app session (no launch since opening).
    var smapiLogStale: Bool { smapiHealth.isStale }
    /// Conflits constatés par Content Patcher lors de la **dernière partie**
    /// journalisée (date : `smapiLogDate`), pas l'état actuel du parc.
    var contentPatcherConflicts: [LoadConflict] { smapiHealth.contentPatcherConflicts }
    /// App-session start; reference for SMAPI-log staleness.
    private let sessionStart = Date()

    /// Folder being toggled, or nil. Drives the ModListRow spinner.
    var pendingToggleFolder: String? = nil

    /// Folder being deleted, or nil. Drives the per-row spinner and dimming.
    var pendingDeleteFolder: String? = nil

    // MARK: Mises à jour — le store du domaine (cadrage §4, domaine 7,
    // tranche 1) : lignes + verrou à deux détenteurs ; cache plat chez
    // `NexusUpdateChecker.shared`.
    private let updateStore = ModUpdateStore()

    /// Mods with an available update on Nexus Mods (from last user-triggered check).
    var nexusUpdates: [NexusUpdateChecker.ModUpdate] { updateStore.updates }
    /// R3 — mises à jour repoussées par un snooze vivant. Repliées sous la
    /// liste ; hors badge sidebar.
    var snoozedUpdates: [NexusUpdateChecker.ModUpdate] { updateStore.snoozed }
    /// R3 — snoozes (UserDefaults, expiration paresseuse).
    let updateSnoozer = ModUpdateSnoozer()
    /// Mods que smapi.io n'a pas pu vérifier (115 sur le parc) : les taire
    /// faisait dire « tous à jour » sans verdict (Powered Automation,
    /// 2026-08-27). `UniqueID` joint (B2-T10) : deux mods peuvent porter le
    /// même nom.
    var unverifiableMods: [SmapiVerdicts.Unverifiable] { updateStore.unverifiable }
    /// Mods tus par « Je l'ai déjà » (X12). **Publié, pas calculé** : le
    /// construire décode les ancres, et un calculé se réévalue à chaque rendu
    /// (F3). Rafraîchi après scan, affirmation, réaffichage.
    var affirmedUpdates: [AffirmedUpdates.Row] { updateStore.affirmed }

    /// Compatibilité smapi.io par `UniqueID`, relue au lancement :
    /// l'avertissement d'**activation** n'attend pas de vérification.
    /// Parc : 281 `Ok`, 7 signalés, **552 sans verdict** — absence ≠ satisfecit.
    private(set) var modCompatibility: [String: ModCompatibility] =
        ModCompatibilityStore.load() {
        didSet { compatibilityStatuses = modCompatibility.mapValues(\.status) }
    }
    /// Avertissements Pathoschild **sans verdict cassé**, par `UniqueID`,
    /// tamisés par `ModPlatformWarnings`. Cache lu **quel que soit son âge** :
    /// sinon ces lignes disparaîtraient 18 h par jour. Parc 2026-09-05 : zéro.
    private(set) var modWarnings: [String: [String]] = [:]
    /// A2-T7 — mods installés sur la **liste noire SMAPI** (malveillants).
    /// ⚠️ **Rien à voir avec `blacklistedMods`** (choix de l'utilisateur) :
    /// les confondre ferait passer un choix pour une alerte, ou l'inverse.
    private(set) var maliciousMods: [String: SmapiBlacklist.Entry] = [:]

    /// Statuts **tenus à jour** : `anomaly(for:)` tourne deux fois par ligne ;
    /// reconstruire à chaque appel rendrait la liste quadratique.
    private var compatibilityStatuses: [String: ModCompatibility.Status] = [:]
    /// Source et date des derniers verdicts affichés : le bandeau de la fiche
    /// distingue cache disque et réponse fraîche (A2-T3).
    public enum CompatibilitySource: Equatable {
        case live
        case pathoschildDump
        case diskCache
        case none
    }
    private(set) var compatibilitySource: CompatibilitySource = .none
    /// Date (`fetchedAt`) du dump Pathoschild utilisé, `nil` si jamais posé.
    private(set) var pathoschildDumpDate: Date? = nil
    /// True while a Nexus check is in flight.
    var isCheckingNexusUpdates: Bool { updateStore.isChecking }
    /// Last error message from a Nexus check (nil = none / not run yet).
    var nexusCheckError: String? { updateStore.checkError }
    /// Progress of the in-flight Nexus check. `nil` when idle.
    var nexusCheckProgress: UpdateCheckProgress? { updateStore.progress }
    // MARK: Compte Nexus — le store du domaine (cadrage §4, domaine 7,
    // tranche 2). Le Trousseau reste chez `NexusUpdateChecker.shared` ; le
    // store ne retient que « clé acceptée ».
    private let accountStore = NexusAccountStore()

    /// Whether the user has provided a Nexus API key (kept in sync with Keychain).
    var hasNexusApiKey: Bool { accountStore.hasApiKey }
    /// `true` seulement si on **sait** le compte non premium : mieux vaut un
    /// bouton qui échoue qu'un bouton absent.
    var nexusDirectDownloadUnavailable: Bool { accountStore.directDownloadUnavailable }

    /// Dernier quota Nexus relevé (B2-T6), `nil` avant toute réponse.
    var nexusQuota: NexusQuota? { accountStore.quota }
    /// Set when a Nexus download finishes; MainView opens the install sheet.
    var pendingDownloadedZip: URL?
    /// Ce que l'app sait du téléchargement qui attend sa feuille. `facts`
    /// seulement si l'app a **choisi** le fichier : l'ancre juge alors « plus
    /// récent », pas « libellé plus grand » (X9).
    struct NexusInstallSource: Equatable {
        let modId: Int
        let facts: NexusInstallFacts?

        init(modId: Int, facts: NexusInstallFacts? = nil) {
            self.modId = modId
            self.facts = facts
        }
    }
    /// Set with pendingDownloadedZip for a Nexus download (manifest reconcile).
    var pendingNexusSource: NexusInstallSource?
    /// X103-C — archives Nexus ; inerte tant que `keepNexusArchives` est éteint.
    let nexusArchiveStore = NexusArchiveStore(
        root: NexusArchiveStore.defaultRoot(
            applicationSupport: AppSupport.directory
                ?? URL(fileURLWithPath: NSTemporaryDirectory())))
    // MARK: Téléchargement Nexus — le store du domaine (cadrage §4, domaine
    // 7, tranche 3) : cycle, file, lissage du débit. « Suis-je occupé ? »
    // reste ici (`NexusDownloadFlow` lit aussi `pendingDownloadedZip`).
    // `nonisolated(unsafe)` : la progression part du fil de délégué
    // `URLSession` et ne traverse que la référence ; écritures sur main.
    private nonisolated(unsafe) let downloadStore = NexusDownloadStore()

    // MARK: Navigation — le store du domaine (chantier B, cadrage P8). Les
    // vues de détail remises à nil au changement d'onglet, et requêtes entre
    // vues. La règle vit dans `TabChangePlan` (Core) ; le store tient l'état.
    let navigationStore = NavigationStore()

    // MARK: Scan & parc — le store du domaine (cadrage §3, domaine 8). Le
    // lourd vit dans `ModScanner` (cache mtime + verrou) ; ce store porte
    // l'état publié. Poser le parc prévient les trois consommateurs de l'init.
    let scanStore = ScanStore()

    var isDownloadingFromNexus: Bool { downloadStore.isDownloading }
    /// Nexus mod id being downloaded, or nil. Drives the Updates row spinner.
    var downloadingNexusModId: Int? { downloadStore.downloadingModId }
    private let nexusDownloader = NexusDownloader()

    /// Téléchargement Nexus en cours (B2-T1) ; `nil` au repos et pendant la
    /// résolution du lien. Un seul en vol (ils se disputeraient
    /// `pendingDownloadedZip`) ; les suivants attendent dans la file
    /// (`drainQueuedNexusDownloads`).
    var nexusDownloadProgress: DownloadProgress? { downloadStore.progress }

    /// Rich detail state for the mod shown in the detail pane.
    // Transitions en Core (`Models/ModDetailState.swift`, testées).
    var modDetailState: ModDetailState?

    /// Cached detail shown instantly, then background refresh; offline falls
    /// back to the manifest. Result dropped if `viewingModDetail` changed.
    func loadModDetail(for mod: ModItem) {
        let modId = Int(resolvedNexusModId(for: mod)) ?? -1
        // Immediate: cache if any, else local manifest description.
        let cached = modId > 0 ? ModDetailCache.load(modId: modId) : nil
        modDetailState = ModDetailState.initial(modId: modId, cached: cached,
                                                localDescription: mod.description)
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
                guard self.navigationStore.viewingModDetail.map({ Int(self.resolvedNexusModId(for: $0)) }) == modId else { return }
                self.modDetailState = ModDetailState.refreshed(modId: modId, raw: raw)
            }
        }
    }

    private func markDetailNotLoading(modId: Int) {
        modDetailState?.stopLoading(ifShowing: modId)
    }

    /// Description + full changelog: v1, then v2 without key (A3-T7). `nil`
    /// if both fail, so the local fallback stays. Rule in Core, tested.
    private func fetchModDetailRemote(modId: Int, completion: @escaping (ModDetailRaw?) -> Void) {
        ModDetailRefresh.fetch(
            modId: modId,
            fetchDescription: { NexusUpdateChecker.shared.fetchRawDescription(modId: $0, completion: $1) },
            fetchChangelogs: { NexusUpdateChecker.shared.fetchChangelogs(modId: $0, completion: $1) },
            fallback: { id, done in NexusSearchClient.modDetailRaw(modId: id) {
                if case .success(let raw) = $0 { done(raw) } else { done(nil) } } },
            completion: completion)
    }
    /// `{ nexusModId: categoryId }`, persisted so the category filter works
    /// before a re-check.
    var nexusCategories: [String: Int] = [:] {
        didSet { invalidateCategoryCache() }
    }

    /// `{ nexusModId: NexusModExtra }` (summary + picture), persisted; powers
    /// the details popover.
    var nexusModExtras: [String: NexusUpdateChecker.NexusModExtra] = [:]

    // Overrides **utilisateur** (catégorie, id Nexus) dans
    // `NexusMetadataStore` (Core) ; façades de lecture ci-dessous.
    var nexusCustomCategories: [String: Int] { nexusMetadata.customCategories }
    var nexusCustomModIds: [String: String] { nexusMetadata.customModIds }

    /// Store des métadonnées utilisateur.
    private let nexusMetadata = NexusMetadataStore()

    /// `{ folderName: lastActivatedDate }` — stamped on disabled → enabled
    /// (`toggleMod`, `applyProfileToFilesystem`), never on disable. Drives the
    /// "Activation order" sort. Persisted.
    var modActivationTimestamps: [String: Date] = [:]
    /// Favoris par `folderName` **logique** (sans le point de pause) : le
    /// marquage survit à une pause.
    private(set) var favoriteMods: Set<String> = []
    /// Mods « à écarter », même clé que `favoriteMods`. Restent installés et
    /// activables, **grisés** dans la liste.
    private(set) var blacklistedMods: Set<String> = []
    /// Mods dont le `config.json` suit le profil actif (B3-T5), nom logique.
    private(set) var profileManagedConfigMods: Set<String> = []

    // MARK: Entretien & corbeille — le store du domaine (cadrage §4,
    // domaine 4). Calculs en Core (`MaintenanceInventory`,
    // `ModFolderRepairer`, `ModTrash`) ; ici l'état et le verrou.
    let maintenanceStore = MaintenanceStore()

    /// Inventaire « Entretien » (X25). `nil` = pas construit ≠ rapport vide.
    var maintenanceReport: MaintenanceInventory.Report? { maintenanceStore.report }
    var isBuildingMaintenanceReport: Bool { maintenanceStore.isBuilding }

    /// True during the initial launch load; drives the launch overlay.
    var isLaunching: Bool = true
    /// Launch progress 0.0 → 1.0 (determinate bar).
    var launchProgress: Double = 0.0
    /// Localized launch step label, updated with `launchProgress`.
    var launchStep: String = ""

    /// Per-mod scan progress (throttled), mapped onto the
    /// [`launchScanProgressStart`…`launchScanProgressEnd`] slice. `nil` outside a scan.
    // `ScanProgress` vit en Core (`Models/ModScanner.swift`).
    /// Launch-bar slice for the "Scanning mods" phase.
    static let launchScanProgressStart: Double = 0.25
    /// Fin de la boucle par mod (0,60) : laisse une tranche aux phases
    /// suivantes, qui figeaient la barre plusieurs secondes.
    static let launchScanProgressEnd: Double = 0.60
    /// Fin des phases post-boucle, à l'intérieur de `scanMods`.
    static let launchScanPhasesEnd: Double = 0.70
    /// Poids proportionnels au coût mesuré (journal de 9,8 Mo) ; la lecture du
    /// journal avance en continu entre ces bornes. `nonisolated` : `Double`
    /// immuables lus hors acteur (L2).
    nonisolated static let launchSmapiLogStart: Double = 0.60
    nonisolated static let launchSmapiLogEnd: Double = 0.66
    nonisolated static let launchRegistrySyncProgress: Double = 0.68
    nonisolated static let launchDuplicatesProgress: Double = 0.69

    /// Annonce une phase qui suit la boucle par mod. Affiche `modsFound`, pas
    /// `total/total` (qui comptait les dossiers sans manifeste, écart du
    /// 2026-09-10). `nonisolated` (P5) : le corps dispatche vers main.
    nonisolated private func publishLaunchPhase(_ stepKey: String, progress: Double,
                                    entries: (done: Int, total: Int),
                                    modsFound: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let label = self.localization.L(stepKey)
            self.launchStep = label
            // `max` : la barre ne recule jamais.
            self.launchProgress = max(self.launchProgress, progress)
            guard entries.total > 0 else { return }
            self.scanStore.scanProgress = ScanProgress(done: entries.done, total: entries.total,
                                             currentName: "", phase: label,
                                             modsFound: modsFound)
        }
    }

    /// Même annonce à une fraction de la tranche, pour une phase longue.
    nonisolated private func publishLaunchPhaseProgress(_ stepKey: String, fraction: Double,
                                            from: Double, to: Double,
                                            entries: (done: Int, total: Int),
                                            modsFound: Int) {
        let clamped = min(max(fraction, 0), 1)
        publishLaunchPhase(stepKey, progress: from + (to - from) * clamped,
                           entries: entries, modsFound: modsFound)
    }

    /// Façade de **lecture** assumée (§6, cond. 1). Écritures :
    /// `scanStore.setMods(...)`, jamais par ici.
    var mods: [ModItem] { scanStore.mods }

    /// Problèmes de santé du parc, résolus une fois : accueil, badge et écran
    /// d'alertes lisent **cette** liste, sinon les nombres divergent.
    @MainActor
    var healthIssues: [HealthIssue] {
        let activeFolders = Set(mods.flattenedMods.filter(\.isEnabled).map(\.folderName))
        let candidates = modConflictVerdicts.declared
            + contentPatcherConflicts.compactMap(conflictPair)
        let live = modConflictVerdicts.liveConflicts(candidates: candidates,
                                                    activeFolders: activeFolders)
        // Seul le VM connaît `[ModItem]` ; la règle (repli sur le dossier) est
        // dans `HealthIssueResolver`.
        let installedMods = mods.flattenedMods
        // X13 — deux mods peuvent réclamer le même nom logique (`X` et `.X`) ;
        // `ModItem.id` = `folderName` en cache un : cette ligne l'explique.
        let collisions = ModFolderCollision.collisions(installedMods.map {
            ModFolderCollision.Claim(folderName: $0.folderName, uniqueId: $0.uniqueId,
                                     physicalFolderName: $0.physicalFolderName)
        })
        let collisionIssues = HealthIssueResolver.folderCollisionIssues(
            collisions,
            modsPath: (gameDir as NSString).appendingPathComponent("Mods"),
            title: { String(format: self.localization.L(L10n.Health.folderCollisionTitle), $0.folderName) },
            detail: { String(format: self.localization.L(L10n.Health.folderCollisionDetail),
                             $0.uniqueIds.joined(separator: " · ")) })
        // X58 — signalé sans être cassé. Nom tiré du parc, celui que
        // `ModFocusResolver` résout.
        let nameByUniqueId = Dictionary(installedMods.map { ($0.uniqueId, $0.name) },
                                        uniquingKeysWith: { first, _ in first })
        let warningIssues = HealthIssueResolver.modWarningIssues(
            modWarnings.keys.sorted().compactMap { uniqueId in
                guard let name = nameByUniqueId[uniqueId],
                      let texts = modWarnings[uniqueId] else { return nil }
                return (uniqueId: uniqueId, name: name, warnings: texts)
            },
            title: { name, _ in String(format: self.localization.L(L10n.Health.modWarningTitle), name) },
            detail: { joined in joined + " " + self.localization.L(L10n.Health.modWarningSource) })

        // A2-T7 — les mods malveillants. Le montage vit en Core (F1-T2).
        let maliciousIssues = HealthIssueResolver.maliciousModIssues(
            SmapiBlacklist.issueInputs(
                matches: maliciousMods,
                nameByUniqueId: nameByUniqueId,
                physicalFolderByUniqueId: Dictionary(
                    installedMods.map { ($0.uniqueId, $0.physicalFolderName) },
                    uniquingKeysWith: { first, _ in first }),
                modsRoot: (gameDir as NSString).appendingPathComponent("Mods")),
            title: { String(format: self.localization.L(L10n.Health.maliciousTitle), $0) },
            detail: { String(format: self.localization.L(L10n.Health.maliciousDetail), $0)
                      + " " + self.localization.L(L10n.Health.maliciousSource) })

        return HealthIssueResolver.resolve(diagnostics: smapiDiagnostics,
                                           keybindReport: keybindReport,
                                           conflicts: live,
                                           folderCollisions: collisionIssues + warningIssues
                                               + maliciousIssues,
                                           displayName: { folderName in
            installedMods.first(where: { $0.folderName == folderName })?.name ?? folderName
        })
    }

    /// Définition d'une « alerte » (pastille, accueil) : dérive de
    /// `healthIssues`. Compte **actionnable** : `.info` exclu, sinon la
    /// pastille sonne sur un parc sain (7 notices bénignes mesurées). Même
    /// règle que `SystemAlertsView` (`actionableCount`).
    @MainActor
    var systemAlertCount: Int { healthIssues.actionableCount }

    /// Incompatibilités actives (A5-T2, H-T6) : dérive de `healthIssues`
    /// (`.modConflict`) ; un second calcul divergerait de l'écran d'alertes.
    @MainActor
    var activeConflictCount: Int {
        healthIssues.filter { $0.source == .modConflict }.count
    }

    /// Couverture FR par `folderName`, absente tant que non calculée. `Coverage`
    /// entière : la fiche dit **ce qui** manque, dont les vides qui cassent
    /// l'affichage en jeu.
    private(set) var frenchCoverageByMod: [String: TranslationCoverage.Coverage] = [:]

    /// Index des clés obsolètes, relu après chaque diff (évite un fichier par
    /// ligne).
    private(set) var outdatedKeysByMod: [String: Int] = [:]

    /// Mods dont l'anglais est plus récent que le FR, mesuré au scan (deux
    /// lectures d'attributs par `i18n`).
    private(set) var staleTranslationMods: Set<String> = []

    /// `@MainActor` explicite : la reprise après `await` d'une tâche détachée
    /// ne revient pas seule sur main (voir `scanMods()`).
    @MainActor
    func reloadOutdatedKeyIndex() {
        guard let store = TranslationBaseline.defaultDirectory() else { return }
        outdatedKeysByMod = TranslationBaseline.loadIndex(in: store)
    }

    /// Le calcul en cours, annulé dès qu'un nouveau scan le rend caduc.
    private var frenchCoverageTask: Task<Void, Never>?

    /// Recalcule la couverture FR **hors du fil principal**, jamais pendant le
    /// scan (coût dominant au lancement). Seuls les mods détectés traduits.
    /// **Incrémental** : la passe complète coûte ~13 s (424 mods, 159 503
    /// clés) et `mods` est republié à chaque pause/activation ; seuls les
    /// inconnus sont mesurés. Une pause ne change pas les fichiers ;
    /// `invalidateFrenchCoverage(for:)` couvre les vrais changements.
    private func recomputeFrenchCoverage() {
        frenchCoverageTask?.cancel()
        // Charge en bloc l'index des clés obsolètes (`TranslationBaseline`) :
        // sans ça, « À revoir » repartirait de zéro à chaque lancement. Coût
        // négligeable. `Task { @MainActor … }` : fonction non isolée.
        Task { @MainActor [weak self] in
            self?.reloadOutdatedKeyIndex()
        }
        let root = gameDir
        guard !root.isEmpty else { return }
        // Lot figé avant la tâche détachée : relire `mods` déplacerait la course.
        let snapshot = FrenchCoveragePass.targets(in: mods,
                                                  known: Set(frenchCoverageByMod.keys))
        guard !snapshot.isEmpty else { return }

        frenchCoverageTask = Task.detached(priority: .utility) { [weak self] in
            let modsPath = (root as NSString).appendingPathComponent("Mods")
            var batch: [String: TranslationCoverage.Coverage] = [:]
            var staleBatch: Set<String> = []
            for target in snapshot {
                if Task.isCancelled { return }
                let directory = URL(fileURLWithPath: modsPath)
                    .appendingPathComponent(target.physicalFolder)
                guard let coverage = TranslationCoverage.coverage(forModAt: directory,
                                                                  locale: "fr") else { continue }
                batch[target.key] = coverage
                if TranslationFreshness.staleness(forModAt: directory, locale: "fr") != nil {
                    staleBatch.insert(target.key)
                }
                if batch.count >= FrenchCoveragePass.batchSize {
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
        // Garde de génération non câblée à dessein (F6-T1) — voir
        // `FrenchCoveragePass.merging`.
        guard let next = FrenchCoveragePass.merging(
            batch, stale: stale,
            into: .init(coverage: frenchCoverageByMod, stale: staleTranslationMods))
        else { return }
        frenchCoverageByMod = next.coverage
        staleTranslationMods = next.stale
    }

    /// Le taux à afficher sur la pastille de la liste, si mesuré.
    func frenchCoverage(for mod: ModItem) -> Int? {
        frenchCoverageByMod[mod.folderName]?.displayPercent
    }

    /// Détail de la couverture pour la fiche mod.
    func frenchCoverageDetail(for mod: ModItem) -> TranslationCoverage.Coverage? {
        frenchCoverageByMod[mod.folderName]
    }

    /// Diff EN/FR clé par clé, **hors fil principal** (`East Scarp NPCs` :
    /// 11 021 clés ; un `.task` synchrone figerait la fenêtre).
    /// Cache des rangées (F7) : trois entrées de 1,1–2,3 Mo.
    private let translationDiffCache = TranslationDiffCache()

    func translationDiff(for mod: ModItem) async -> [TranslationCoverage.DiffRow] {
        let directory = URL(fileURLWithPath: (gameDir as NSString)
            .appendingPathComponent("Mods"))
            .appendingPathComponent(mod.physicalFolderName)
        let folderName = mod.folderName
        let cache = translationDiffCache
        let rows = await Task.detached(priority: .userInitiated) {
            // Gardé tant que les fichiers `i18n` ne changent pas : le calcul
            // coûte 1,2 à 2,6 s sur le parc réel, l'empreinte 0,3 ms (F7).
            // **Seul `diffRows` est gardé** — ce qui suit adopte et réancre la
            // référence et réécrit l'index, et doit rejouer à chaque appel.
            let rows = TranslationCoverage.diffRows(forModAt: directory, locale: "fr",
                                                    cache: cache)
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
        // Plus de `await` depuis L2 : la classe est `@MainActor`, l'appel est
        // même acteur — le hop d'entrée que l'`await` portait n'existe plus.
        reloadOutdatedKeyIndex()
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
        // Racines portées par les managers eux-mêmes : reconstruire
        // « ModInstalls/backups » par littéraux ici divergerait en silence
        // le jour où un manager change de layout, et le finder chercherait
        // dans le vide. Les managers partent sur le dossier temporaire si
        // Application Support est introuvable — chercher là où ils
        // écrivent réellement, pas retourner nil.
        let roots = [ModInstallBackupManager.shared.backupsDirectory,
                     ModConfigBackupManager.shared.backupsDirectory]
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

    /// Le glossaire en mémoire — une langue à la fois : le hub FR n'en charge
    /// qu'une, et recharger le JSON à chaque clé traduite serait payer le
    /// même fichier des centaines de fois dans un lot.
    private var glossaryCache: (language: String, glossary: Glossary)?
    /// Le contrôle de fraîcheur du glossaire n'a lieu qu'une fois par
    /// lancement — voir `refreshGlossaryIfSourcesChanged`.
    private var checkedGlossaryFreshness = false

    /// Le dossier racine du glossaire en Application Support — même règle de
    /// placement que `TranslationBaseline`, jamais Caches.
    nonisolated private static func glossaryAppSupport() -> URL? {
        AppSupport.directory
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
    /// n'est pas du loopback admissible. **Miroir** : la clé est écrite par
    /// `SettingsView` en `@AppStorage`, hors du VM — lire `UserDefaults` dans
    /// un corps calculé ne serait pas suivi sous `@Observable` (cadrage §3
    /// bis, cas 6). La valeur stockée est resynchronisée par
    /// `resyncMirroredDefaults()`, branchée sur `didChangeNotification`.
    private(set) var localAIEndpoint: URL? =
        StarHubTHViewModel.readLocalAIEndpoint()

    /// Le nom de modèle choisi, chaîne vide si non configuré. **Miroir** (voir
    /// `localAIEndpoint`).
    private(set) var localAIModelName: String =
        StarHubTHViewModel.readLocalAIModelName()

    /// `true` quand URL validée **et** modèle nommé.
    var isLocalAIConfigured: Bool {
        localAIEndpoint != nil && !localAIModelName.isEmpty
    }

    /// Les identifiants du secours en ligne, `nil` si la case est décochée ou
    /// si aucune clé n'est enregistrée. Les deux conditions sont nécessaires :
    /// une clé sans accord ne sort pas, un accord sans clé n'a rien à envoyer
    /// — les trois lecteurs (actions d'envoi et de test, aucun rendu)
    /// dépendent de ce `nil`. **Calculée à dessein**, après revue : elle lit
    /// le trousseau EN DIRECT — une rotation de clé hors de l'app est servie
    /// fraîche, là où un miroir aurait servi du périmé indéfiniment pendant
    /// que le bouton « Tester » (qui lit en direct) validait la nouvelle. Le
    /// suivi de la case passe par le miroir `deepLFallbackEnabled` ; aucune
    /// vue ne lit celle-ci, donc rien à suivre dessus.
    var deepLCredentials: DeepLClient.Credentials? {
        deepLFallbackEnabled ? DeepLClient.Credentials.fromKeychain() : nil
    }

    /// Une clé de secours est-elle enregistrée ? **Mémorisé** : la question
    /// se pose à chaque passe de rendu de l'onglet Traduction, et interroger
    /// le trousseau à ce rythme se paie. Les deux écritures ci-dessous sont
    /// les seules qui la changent.
    private(set) var hasDeepLKey = KeychainSecret.deepLApiKey.read() != nil

    /// Enregistre la clé du secours ; `false` si le trousseau refuse — ne pas
    /// annoncer une clé non enregistrée.
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

    /// `true` dès qu'**un** moteur peut traduire (boutons lot et
    /// « Pré-traduire », spec §7). Le secours seul suffit : sans modèle local,
    /// c'est la seule voie.
    var isTranslationAssistAvailable: Bool {
        isLocalAIConfigured || isFallbackEnabled
    }

    /// Case « secours DeepL ». **Miroir** (voir `localAIEndpoint`), écrit par
    /// `SettingsView`.
    private(set) var deepLFallbackEnabled: Bool =
        StarHubTHViewModel.readDeepLFallbackEnabled()

    /// Lectures des miroirs en **un seul endroit**, partagées par les
    /// initialisateurs et `resyncMirroredDefaults()`, sinon elles divergent.
    private static func readLocalAIEndpoint() -> URL? {
        UserDefaults.standard.string(forKey: UDKey.localAIBaseURL)
            .flatMap(LocalLLMEndpoint.validate)
    }

    private static func readLocalAIModelName() -> String {
        UserDefaults.standard.string(forKey: UDKey.localAIModel) ?? ""
    }

    private static func readDeepLFallbackEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: UDKey.deepLFallbackEnabled)
    }

    /// Resynchronise les miroirs écrits par `SettingsView`. Sans garde, toute
    /// écriture defaults du processus republierait.
    private func resyncMirroredDefaults() {
        let endpoint = Self.readLocalAIEndpoint()
        if localAIEndpoint != endpoint { localAIEndpoint = endpoint }
        let model = Self.readLocalAIModelName()
        if localAIModelName != model { localAIModelName = model }
        let fallback = Self.readDeepLFallbackEnabled()
        if deepLFallbackEnabled != fallback { deepLFallbackEnabled = fallback }
    }

    /// Le secours part seulement avec case cochée **et** clé. L'interface lit
    /// cette propriété.
    var isFallbackEnabled: Bool {
        hasDeepLKey && deepLFallbackEnabled
    }

    /// Proposition IA locale pour une ligne du diff, ou `nil` — **rien n'est
    /// écrit** : seul « Enregistrer » écrit, et la voie par clé ne pose jamais
    /// « à relire » (spec §2.4). Sans IA, la vue n'appelle pas ; la garde reste.
    /// Résultat d'une pré-traduction par clé : trois causes d'échec avec un
    /// service en ligne, et `nil` taisait pourquoi (quota épuisé…).
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
        // Une session pour les deux moteurs : éphémère, sans proxy, sans
        // redirection.
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
        /// Marques du jeu emportées par la sélection, nommées pour resélectionner.
        case refusedMarkers([String])
        case nothingSelected
        /// Aucun secours en ligne réglé — cette voie n'a pas d'autre moteur.
        case noFallback
        case failed
        case fallbackStopped(BatchReport.FallbackStop)
    }

    /// Traduit un fragment, la phrase entière servant de `context` (non
    /// traduit). **Service en ligne seulement** : le prompt local rend la
    /// phrase au lieu du mot. Sans clé, la voie n'est pas offerte.
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

    /// Types du lot en Core (`TranslationBatchRun`) ; les alias gardent les
    /// vues en place.
    typealias BatchProgress = TranslationBatchRun.Progress
    typealias BatchReport = TranslationBatchRun.Report

    private(set) var batchProgress: BatchProgress?
    private(set) var batchReport: BatchReport?
    private var batchTask: Task<Void, Never>?

    /// Lance le lot, **une requête à la fois** (GPU local, spec §7). Chaque
    /// résultat est persisté aussitôt (spec §8.4) : annuler ne perd rien,
    /// relancer reprend.
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

    /// Clés « à relire » d'un mod, au format `DiffRow.id`.
    func reviewNeededRowIDs(for mod: ModItem) async -> Set<String> {
        guard let store = TranslationBaseline.defaultDirectory() else { return [] }
        let folder = mod.folderName
        return await Task.detached(priority: .utility) {
            TranslationBaseline.reviewNeededRowIDs(modFolderName: folder, in: store)
        }.value
    }

    // MARK: - Glossaire (réglages)

    /// Suffixe d'asset du jeu (`fr-FR`) pour une langue du hub (`fr`).
    private static func gameAssetSuffix(for language: String) -> String {
        switch language {
        case "fr": "fr-FR"
        default: language
        }
    }

    /// Reconstruit le glossaire depuis le jeu et sauve le cache. `nil` si
    /// aucune source : l'appelant le dit plutôt qu'afficher « 0 termes ».
    @MainActor
    @discardableResult
    func rebuildGlossary(language: String = "fr") async -> Int? {
        let folder = gameDir
        let suffix = Self.gameAssetSuffix(for: language)
        let (entries, saved, unreadable) = await Task.detached(priority: .utility) {
            guard let kind = GlossarySource.resolve(gameFolder: URL(fileURLWithPath: folder))
            else { return ([GlossaryEntry](), false, [String]()) }
            // Asset illisible = table manquante en silence : on le nomme. Absent
            // reste normal (spec §5).
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

    /// Reconstruit le glossaire si `Content/Strings` a bougé (mise à jour du
    /// jeu), une fois par lancement. Sans glossaire en cache, rien : c'est
    /// « Reconstruire » qui pose le premier.
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

    /// Date du glossaire en cache, pour les réglages.
    func glossaryBuiltDate(language: String = "fr") -> Date? {
        guard let appSupport = Self.glossaryAppSupport() else { return nil }
        return GlossaryStore.builtDate(language: language, appSupport: appSupport)
    }

    /// Drapeaux « à relire » gardés avant écriture : borne la perte d'un arrêt
    /// brutal, divise les réécritures du sidecar.
    private static let reviewFlagFlushSize = 25

    /// Écrit les drapeaux accumulés et vide la liste (rien si vide).
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
        // Admet « pas d'IA locale, secours réglé ».
        var fallbackCredentials = deepLCredentials
        guard isLocalAIConfigured || fallbackCredentials != nil else { return }
        // Jamais une valeur FR existante (spec §8.2) : absent ou vide seulement.
        let eligible = TranslationBatchPlanner.eligibleRows(rows)
        // Comptabilité et arrêts dans `TranslationBatchRun` (Core, 15 tests).
        var run = TranslationBatchRun(hasLocalEngine: isLocalAIConfigured)
        var flags: [TranslationBaseline.ReviewFlag] = []
        // Une session pour tout le lot : `URLSession` retient son délégué ; une
        // par clé laissait autant de sessions vivantes.
        let session = LocalLLMEndpoint.makeSession()
        defer { session.finishTasksAndInvalidate() }
        batchProgress = BatchProgress(done: 0, total: eligible.count)
        for (index, row) in eligible.enumerated() {
            // Arrêt : la clé en cours est partie, son résultat ne sera pas écrit.
            if Task.isCancelled { break }
            let matches = glossaryMatches(for: row.english, language: locale)
            let request = LocalLLMClient.Request(
                model: localAIModelName, source: row.english,
                glossary: matches, sectionLabel: row.section)
            let outcome = await TranslationEngine.translate(
                request, localBaseURL: localAIEndpoint, localSession: session,
                fallback: fallbackCredentials, fallbackSession: session)

            var writeSucceeded = false
            if case .translated(let proposal, _) = outcome {
                // Chemin d'écriture existant (`.bak`, gate de marques) ; le gate reste
                // juge. Retrait du drapeau sauté : la clé était vide.
                if case .saved = saveTranslation(mod: mod, locale: locale,
                                                 row: row, value: proposal,
                                                 clearingReviewFlag: false) {
                    writeSucceeded = true
                    flags.append(.init(component: row.component, key: row.key,
                                       source: row.english, target: proposal))
                    // Drapeaux par paquets : tout garder pour la fin laisserait un arrêt
                    // brutal présenter des valeurs machine comme relues. Perte bornée à 25.
                    if flags.count >= Self.reviewFlagFlushSize {
                        flushReviewFlags(&flags, mod: mod)
                    }
                }
            }

            let step = run.record(rowID: row.id, outcome: outcome,
                                  glossaryMatches: matches,
                                  writeSucceeded: writeSucceeded,
                                  cancelled: Task.isCancelled)
            if step.dropsFallback { fallbackCredentials = nil }
            batchProgress = BatchProgress(done: index + 1, total: eligible.count)
            if step.stopsLoop { break }
        }
        flushReviewFlags(&flags, mod: mod)   // le reliquat, arrêt compris
        batchReport = run.report
        log(run.summary(mod: mod.folderName), level: .info)
    }

    /// Enregistre une valeur traduite. Bloque sur une divergence de tokens
    /// **dure** non acceptée ni dérogée (un token dur perdu casse le mod en
    /// jeu) ; les souples passent. La référence anglaise n'est pas écrite ici
    /// (`TranslationBaselineRules` l'adopte) : pas de second chemin vers le
    /// magasin. `@MainActor` : requis par `invalidateFrenchCoverage(for:)`.
    @MainActor
    @discardableResult
    func saveTranslation(mod: ModItem, locale: String,
                         row: TranslationCoverage.DiffRow,
                         value: String,
                         acceptingTokenMismatch: Bool = false,
                         clearingReviewFlag: Bool = true) -> SaveOutcome {
        let blocking = TranslationTokenCheck.mismatches(source: row.english, target: value)
            .filter(\.isHard)

        // Un accord existant pour ce couple source/cible vaut réponse. Magasin lu
        // seulement si un blocage est en jeu (rare).
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
        // Rendues à l'appelant, qui demandera confirmation.
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

        // Cible et clé : `TranslationTarget` décide (layouts A/B, casse
        // existante, refus plutôt que deviner) — 14 tests.
        let target: URL
        let realKey: String
        let sourceText: String
        switch TranslationTarget.resolve(inI18nDirectory: i18n, locale: locale, key: row.key) {
        case .success(let destination):
            target = destination.file
            realKey = destination.key
            sourceText = destination.sourceText
        case .failure(let refusal):
            let message = "Traduction non enregistrée : \(refusal.reason)"
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

            // Consigner l'accord seul (le reste est adopté par
            // `TranslationBaselineRules`) ; un accord déjà tenu n'est pas réécrit.
            if !blocking.isEmpty, accepted, !waived, let store = baselineStore {
                var baseline = existingBaseline
                baseline[TranslationBaseline.key(component: row.component, key: row.key)] =
                    TranslationWaiver.accepting(source: row.english, target: value)
                do {
                    try TranslationBaseline.save(baseline, modFolderName: mod.folderName, in: store)
                } catch {
                    // Traduction déjà écrite ; seul l'accord est perdu — journalisé, pas de
                    // `try?` muet.
                    log("Accord de dérogation non enregistré pour \(mod.name) — \(row.key) : \(error)",
                        level: .warning)
                }
            }

            // Enregistrer retire « à relire » (spec §7). Sans drapeau, rien n'est
            // réécrit.
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

            // Fichier changé : couverture en cache périmée.
            invalidateFrenchCoverage(for: mod.folderName)

            // Remesure ciblée, hors fil principal : rien ne republie `mods`, et le
            // filtre `languages.contains("fr")` date du scan (faux au premier
            // `fr.json`). Sans elle, carte de couverture et pastille restent vides
            // jusqu'à la fin de la session.
            let root = gameDir
            let folderName = mod.folderName
            let physicalFolderName = mod.physicalFolderName
            Task.detached(priority: .utility) { [weak self] in
                let directory = URL(fileURLWithPath: (root as NSString)
                    .appendingPathComponent("Mods"))
                    .appendingPathComponent(physicalFolderName)
                guard let coverage = TranslationCoverage.coverage(forModAt: directory,
                                                                   locale: locale) else {
                    // Sans ce journal, l'échec rendrait le même défaut sans trace.
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

    /// Résultat d'un export de lot : données, ou pourquoi aucune (mod fini ≠
    /// encodage raté).
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


    /// Oublie la couverture d'un mod dont les fichiers ont pu changer
    /// (installation, mise à jour, restauration). Sinon il garde pourcentage,
    /// clés obsolètes et place dans « À revoir » de sa version précédente.
    /// **Purge disque d'abord, synchrone** : sinon le prochain
    /// `reloadOutdatedKeyIndex()` relit `index.json` et réinjecte l'ancien
    /// compte. Quelques centaines d'entiers : la justesse prime.
    @MainActor
    func invalidateFrenchCoverage(for folderName: String) {
        if let store = TranslationBaseline.defaultDirectory() {
            try? TranslationBaseline.removeFromIndex(modFolderName: folderName, in: store)
        }
        frenchCoverageByMod.removeValue(forKey: folderName)
        staleTranslationMods.remove(folderName)
        outdatedKeysByMod.removeValue(forKey: folderName)
        // Store des profils indexé par identifiant, pas par dossier.
        if let uniqueId = mods.flattenedMods.first(where: { $0.folderName == folderName })?.uniqueId,
           !uniqueId.isEmpty {
            profileTranslationStore.invalidate(uniqueId: uniqueId)
        }
        // Rangées gardées (F7) : une correction de même longueur dans la même
        // seconde garde l'empreinte. Voir `TranslationDiffCache.removeAll()`.
        translationDiffCache.removeAll()
    }

    // MARK: - Couverture française d'un profil (B3-T4)

    /// Ce que chaque profil affichera en français une fois appliqué.
    /// **Séparé de `frenchCoverageByMod`** : là, absence = « pas mesuré »
    /// (C1-T2) ; les mods sans `fr.json` (8, 28, 15 par profil) y feraient
    /// surgir des pastilles « 0 % ». Grain différent : dossier entier contre
    /// composant.
    // MARK: Couverture par profil — le store du domaine (cadrage §4,
    // domaine 6, tranche 2) : verrou de passe et cache de session.
    private let profileTranslationStore = ProfileTranslationStore()

    var profileTranslationSummaries: [UUID: ProfileTranslationSummary] { profileTranslationStore.summaries }

    /// Cache **entre sessions** (sinon 15,7 s à chaque ouverture), validé par
    /// l'empreinte des fichiers de traduction.
    /// Vrai pendant la mesure : témoin plutôt que pourcentage faux.
    var isMeasuringProfileTranslation: Bool { profileTranslationStore.isMeasuring }

    /// Mesure ce qui manque puis republie. À l'affichage de la page, pas au
    /// scan. Seuls les mods avec `default.json` (`languages` contient `en`).
    /// Cache entre sessions : 15,7 s puis 2,6 s.
    @MainActor
    func refreshProfileTranslationCoverage() {
        guard !modProfiles.isEmpty, !gameDir.isEmpty else { return }
        // Une passe à la fois (verrou du store) ; `Task` non retenue, jamais
        // annulée.
        guard profileTranslationStore.beginMeasure() else { return }

        let installed = mods.flattenedMods
        let profiles = modProfiles

        profileTranslationStore.loadCacheIfNotLoaded(
            from: TranslationCoverageCache.defaultFileURL())

        let modsPath = URL(fileURLWithPath: (gameDir as NSString).appendingPathComponent("Mods"))
        let targets = ProfileCoveragePass.targets(
            profiles: profiles, installed: installed,
            known: Set(profileTranslationStore.coverage.keys))

        guard !targets.isEmpty else {
            // Rien à mesurer : le verrou ne doit pas rester pris.
            profileTranslationStore.endMeasure()
            publishProfileTranslationSummaries(profiles: profiles, installed: installed)
            return
        }

        let cached = profileTranslationStore.cacheEntries
        Task.detached(priority: .utility) { [weak self] in
            var measured: [String: TranslationCoverage.Coverage] = [:]
            var freshEntries: [String: TranslationCoverageCache.Entry] = [:]
            for target in targets {
                if Task.isCancelled { break }
                // Dossiers repérés **une fois** (empreinte + mesure ; 2,5 s).
                // `stoppingAtNestedMods` : sinon clés comptées deux fois.
                let directories = I18nLocaleResolver.i18nDirectories(
                    inModDirectory: modsPath.appendingPathComponent(target.physicalFolder),
                    stoppingAtNestedMods: true)
                let stamp = TranslationStamp.of(directories: directories)

                if let entry = TranslationCoverageCache.valid(cached[target.id], against: stamp) {
                    // Rien n'a bougé : fichiers non rouverts.
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
        profileTranslationStore.mergeMeasured(measured, entries: entries)
        profileTranslationStore.endMeasure()
        persistProfileTranslationCache()
        // Profils actuels : renommés ou supprimés pendant la mesure possibles.
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
                coverageByUniqueId: profileTranslationStore.coverage)
        }
        profileTranslationStore.setSummaries(summaries)
    }

    /// Écrit le cache sans les mods désinstallés, hors fil principal.
    @MainActor
    private func persistProfileTranslationCache() {
        guard let url = TranslationCoverageCache.defaultFileURL() else { return }
        let installedIds = Set(mods.flattenedMods.map { $0.uniqueId }.filter { !$0.isEmpty })
        let entries = profileTranslationStore.pruneCache(keeping: installedIds)
        Task.detached(priority: .utility) {
            TranslationCoverageCache.save(entries, to: url)
        }
    }

    /// Le résumé d'un profil, quand il a été mesuré.
    func translationSummary(for profile: ModProfile) -> ProfileTranslationSummary? {
        profileTranslationStore.summary(for: profile.id)
    }

    /// Ouvre la fiche **sur l'onglet Traduction**, par dossier logique, mods
    /// dépliés compris (composants de pack).
    @MainActor
    func openTranslation(forFolder folderName: String) {
        guard let mod = mods.flattenedMods.first(where: { $0.folderName == folderName })
        else { return }
        navigationStore.pendingTranslationFocus = folderName
        navigationStore.setViewingModDetail(mod)
    }

    /// Ouvre l'éditeur de config **depuis un autre onglet**, via
    /// `pendingConfigFocus` (la bascule remet `editingModConfig` à nil, voir
    /// `MainView`). `false` si le mod n'est plus au parc (rapport périmé).
    @MainActor
    func openModConfig(forFolder folderName: String) -> Bool {
        guard mods.flattenedMods.contains(where: { $0.folderName == folderName })
        else { return false }
        navigationStore.pendingConfigFocus = folderName
        return true
    }
    /// Cache for `category(for:)` (dominant-category scan per render).
    /// ⚠️ Hors suivi, **doublé d'une révision suivie** : suivi, il réveillait
    /// toute la liste (six `body`) ; ignoré seul, l'épinglage cessait de
    /// rafraîchir. Même forme que `deltaReadCache`.
    @ObservationIgnored
    private var categoryCache: [String: NexusCategory?] = [:]
    /// Révision **suivie** du cache : passer par `invalidateCategoryCache()`,
    /// jamais `categoryCache.removeAll()` nu.
    private var categoryCacheRevision = 0

    /// Vide le cache **et** publie.
    private func invalidateCategoryCache() {
        categoryCache.removeAll()
        categoryCacheRevision += 1
    }

    /// Dépendance de suivi, à appeler à **chaque** lecture du cache : sans
    /// elle, la vue cesse de se rafraîchir sans erreur.
    private func trackCategoryCache() {
        _ = categoryCacheRevision
    }

    /// Top-level enabled mods (packs as header); fed to `ModConfigBackupManager`.
    var enabledMods: [ModItem] {
        mods.filter { $0.isEnabled }
    }

    /// Index de dépendances (`DependencyIndex`, Core), reconstruits à chaque
    /// scan ; `duplicateIndex` nourrit les anomalies de ligne.
    private var dependencyIndex = DependencyIndex.empty
    /// Scanner (cache mtime des manifestes + verrou dedans). **Une classe** :
    /// deux `scanMods()` concurrents doivent partager le même cache verrouillé
    /// (subscript non protégé = `EXC_BAD_ACCESS`, juillet 2026).
    private let scanner = ModScanner()

    /// **Toute écriture de `config.json` périme le rapport de raccourcis**
    /// (X66) : `scanIfNeeded` ne voit que `folderName`/`isEnabled`. Appelé par
    /// l'éditeur, la restauration de configs, `restoreProfileConfigs` et
    /// `recoverFile`. `scan` (sans condition) : sûr même sans changement, et
    /// rejoué s'il arrive pendant un scan.
    func rescanKeybindsAfterConfigWrite() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.keybindScanService.scan(mods: self.mods, gameDir: self.gameDir)
        }
    }

    // MARK: Journal — le store du domaine (cadrage §4, domaine 2). Il porte
    // les deux sources (lignes de l'app, bloc de `SMAPI-latest.txt`) ;
    // plafond mémoire dans `LogBudget` (Core).
    private let logStore = LogStore()

    var logEntries: [LogEntry] { logStore.entries }

    /// « Vider les journaux » : lignes de StarHubFR seulement.
    func clearAppLog() { logStore.clearApp() }
    let alertStore = AlertStore()

    var saveToDuplicate: SaveGameInfo? = nil
    var backupToBranch: SaveBackup? = nil

    // MARK: Profils — le store du domaine (cadrage §4, domaine 5). Les
    // décisions en Core (`ProfileActivation`, `ProfileConfigCapture`,
    // `ProfileRecovery`) ; le store est l'état.
    private let profilesStore = ProfileStore()

    var modProfiles: [ModProfile] { profilesStore.profiles }
    var activeProfileId: UUID? { profilesStore.activeProfileId }

    /// True while a profile is applied (moves + rescan); blocks another.
    var isApplyingProfile: Bool { profilesStore.isApplying }

    /// Profile being applied, or nil; drives the row spinner.
    var applyingProfileId: UUID? { profilesStore.applyingId }

    /// Anti double-lancement (R2bis) : couvre le délai avant que le jeu
    /// apparaisse dans `runningApplications`.
    private var launchGate = GameLaunchGate()

    /// When true, toggling a mod also cascades to its dependencies / dependents.
    var chainToggleDependencies: Bool = UserDefaults.standard.object(forKey: UDKey.chainToggleDependencies) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(chainToggleDependencies, forKey: UDKey.chainToggleDependencies)
        }
    }
    var autoCheckNexusUpdates: Bool = UserDefaults.standard.object(forKey: UDKey.autoCheckNexusUpdates) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoCheckNexusUpdates, forKey: UDKey.autoCheckNexusUpdates)
        }
    }
    
    let smapiInstaller = SmapiInstaller()
    // Sur le VM pour survivre au changement d'onglet : `SystemAlertsView`
    // n'a pas d'identité stable (C4-T2).
    let keybindScanService = KeybindScanService()

    /// Miroir du rapport de `KeybindScanService` (`ObservableObject`) : sous
    /// `@Observable`, sa lecture ne serait pas suivie. Abonné à `$report`
    /// (valeur neuve, ré-émise à la souscription) ; `removeDuplicates()`.
    private(set) var keybindReport: KeybindScanner.KeybindReport?
    private var keybindCancellable: AnyCancellable?
    private var defaultsCancellable: AnyCancellable?
    
    init(localization: LocalizationStore) {
        self.localization = localization
        // `didSet` ne voit pas l'initialisation : sans cette ligne, les verdicts
        // relus resteraient muets jusqu'à la première vérification.
        compatibilityStatuses = modCompatibility.mapValues(\.status)
        // A2-T3 : un dump en cache vaut « source disque » jusqu'à une
        // vérification smapi.io ; sa date suffit au bandeau.
        if let cached = PathoschildCompatibilityList.dumpFetchedAt() {
            pathoschildDumpDate = cached
            compatibilitySource = .diskCache
        }
        // Seul chemin des avertissements de l'installateur SMAPI vers le
        // journal : une installation peut réussir avec un défaut.
        smapiInstaller.onWarning = { [weak self] message in
            self?.log(message, level: .warning)
        }
        // Navigation (P8) : plomberie des poses à effet — fiche, rescan
        // raccourcis (X66), inventaire hors fil principal (~40 Mo).
        navigationStore.wireEffects(
            onModDetailOpen: { [weak self] in self?.loadModDetail(for: $0) },
            onConfigEditorClosed: { [weak self] in self?.rescanKeybindsAfterConfigWrite() },
            loadInventory: { save, done in
                DispatchQueue.global(qos: .userInitiated).async {
                    let items = SaveManager.shared.fetchInventory(for: save) ?? []
                    // `done` est `@MainActor` : `assumeIsolated` évite un second saut.
                    DispatchQueue.main.async { MainActor.assumeIsolated { done(items) } }
                }
            })
        // Scan (domaine 8) : poser le parc enchaîne cache de catégories Nexus,
        // couverture FR et rapport de raccourcis (`scanIfNeeded`).
        scanStore.wireEffects(onModsChanged: { [weak self] _ in
            guard let self else { return }
            self.invalidateCategoryCache()
            self.recomputeFrenchCoverage()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.keybindScanService.scanIfNeeded(mods: self.mods, gameDir: self.gameDir)
            }
        })
        // `AppleLanguages` is resynced by `LocalizationStore`; no write here.
        
        // Restore the saved game path, or detect the default Steam one.
        environment.restoreGameDir()
        // Remède §3 bis : `$report` est isolé au main ; l'init du VM est
        // construit sur main (`StarHubTHApp.init`), d'où `assumeIsolated`.
        // ⚠️ Le `Publisher` n'est pas `Sendable` : tout le câblage reste
        // **dans** l'assertion (erreur Swift 6 sinon).
        MainActor.assumeIsolated {
            // `AnyCancellable` non `Sendable` : assigné dans le bloc.
            self.keybindCancellable = keybindScanService.$report
                .removeDuplicates()
                .sink { [weak self] in self?.keybindReport = $0 }
        }
        // Réglages IA/DeepL écrits en `@AppStorage` hors VM : la notification
        // est le seul signal. Garde de différence : elle porte TOUTES les
        // écritures defaults.
        defaultsCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.resyncMirroredDefaults() }
        // L'invalidation du cache de catégories passe par cette closure
        // (appelée par `persistCategories`/`persistModIds`) ; sans elle, une
        // catégorie épinglée laisserait des lignes périmées.
        nexusMetadata.setOnInvalidate { [weak self] in self?.invalidateCategoryCache() }
        // L'historique d'erreurs ne se rebâtit pas : une panne d'écriture ne se
        // verrait qu'au lancement suivant, par une perte.
        errorHistory.setOnWriteFailure { [weak self] in
            self?.log("Historique d'erreurs non enregistré : il ne survivra pas à la fermeture",
                      level: .warning)
        }
        // Seed the first step label so the overlay never shows an empty string.
        self.launchStep = self.localization.L(L10n.Main.launchStepInit)
        // R2 : journal d'application interrompue lu ici, **présenté** après
        // révélation de la fenêtre (`surfaceApplyRecoveryIfNeeded`).
        unresolvedApplyJournal = ProfileApplyJournalStore.load(from: applyJournalDirectory)
        // IMPORTANT: `performInitialLoad()` work runs in background; `init()`
        // returns fast so the launch overlay renders without waiting on I/O.
        self.performInitialLoad()   // launches the overlay-tracked first load
    }

    /// Seeds last-known Nexus data + user overrides, off `init()`, on the
    /// background launch task; publishes on main. Not needed for first frame.
    private func seedNexusAndUserData() {
        // Keychain lookup: a security-daemon round-trip, kept out of init.
        let hasKey = NexusUpdateChecker.shared.apiKey()?.isEmpty == false
        // Two UserDefaults JSON decodes, front-loaded. (Le cache des mises à
        // jour se relit sur main : sa consolidation lit `mods`.)
        let categories = NexusUpdateChecker.shared.cachedCategories()
        let extras = NexusUpdateChecker.shared.cachedExtras()
        // Quota du dernier appel Nexus, persisté : interrogé à la demande (B2-T6).
        let quota = NexusUpdateChecker.shared.cachedQuota()
        let account = NexusUpdateChecker.shared.cachedAccount()
        // User overrides (categories, Nexus ids, activation timestamps).

        let activationTs = Self.loadModActivationTimestamps()
        let favorites = Self.loadFavoriteMods()
        let blacklisted = Self.loadBlacklistedMods()
        let managedConfigs = Self.loadProfileManagedConfigMods()
        let translations = InstalledTranslationStore.load()
        // Verdicts d'incompatibilité (A5-T2), lus hors fil principal.
        let conflictVerdicts = ModConflictVerdictsStore.load()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.accountStore.apply(hasApiKey: hasKey, quota: quota, account: account)
            // Redemandé si inconnu ou vieux d'une semaine (règle dans le store).
            if self.accountStore.needsAccountRefresh() { self.refreshNexusAccount() }
            // Sur main via `republishUpdatesFromCache` : lire `mods` depuis la file
            // de fond était non synchronisé.
            self.republishUpdatesFromCache()
            self.nexusCategories = categories
            self.nexusModExtras = extras
            self.modActivationTimestamps = activationTs
            self.favoriteMods = favorites
            self.blacklistedMods = blacklisted
            self.profileManagedConfigMods = managedConfigs
            self.translationHub.setInstalled(translations)
            self.modConflictVerdicts = conflictVerdicts

            // Pré-charge le dump Pathoschild pendant le splash, pour que ses lignes
            // de journal précèdent la fin de `isLaunching`. Sans attente (1-2 s au
            // premier lancement ; TTL 6 h).
            PathoschildCompatibilityList.fetch(
                onEvent: { [weak self] message in
                    // `PathoschildCompatibilityList` invoque déjà sur main.
                    self?.log(message, level: .info)
                },
                completion: { [weak self] _ in
                    // Les lignes « à savoir » n'ont pas d'autre déclencheur au **premier**
                    // lancement (cache absent au scan) : sinon alertes muettes.
                    self?.refreshModWarnings()
                }
            )
            // A2-T7 — liste des mods malveillants, séparée du dump : deux TTL
            // (1 h / 6 h), l'une qui tombe n'emporte pas l'autre.
            self.refreshMaliciousMods()
        }
    }

    /// A2-T7 — récupère la liste noire SMAPI et la croise au parc. Un échec
    /// **n'efface pas** ce qu'on savait.
    func refreshMaliciousMods() {
        SmapiBlacklist.fetch(
            onEvent: { [weak self] message in self?.log(message, level: .info) },
            completion: { [weak self] result in
                Task { @MainActor in
                    guard let self, let dump = try? result.get() else { return }
                    let uniqueIds = SmapiBlacklist.uniqueIds(
                        ofTopLevel: self.mods.map(\.uniqueId),
                        children: self.mods.map { ($0.children ?? []).map(\.uniqueId) })
                    let hits = SmapiBlacklist.matches(uniqueIds: uniqueIds, in: dump)
                    self.maliciousMods = hits
                    if hits.isEmpty {
                        self.log("Liste noire SMAPI : aucun mod malveillant sur "
                                 + "\(uniqueIds.count) identifiants installés", level: .info)
                    } else {
                        // `error` : seule ligne qui parle de code hostile.
                        self.log("Liste noire SMAPI : \(hits.count) mod(s) malveillant(s) "
                                 + "installé(s) — " + hits.keys.sorted().joined(separator: ", "),
                                 level: .error)
                    }
                }
            })
    }
    
    /// Façade provisoire (REFACTORING §6, cond. 1) — HomeView et
    /// SettingsView. Décision dans `GameEnvironmentStore.selectGameDir` ;
    /// `refresh()` et le message restent ici.
    func selectGameDir() {
        let previousGameDir = gameDir
        environment.selectGameDir { [weak self] problem in
            guard let self else { return }
            switch problem {
            case .notAGameFolder:
                self.showModal(message: self.localization.L(L10n.VM.gameDirNotRecognised))
            case .modsFolderUnavailable:
                self.showModal(message: self.localization.L(L10n.VM.modsFolderUnavailable))
            case nil:
                break
            }
            // Le panneau est modal : `gameDir` porte déjà le nouveau choix ici.
            let changed = self.gameDir != previousGameDir
            self.refresh(onScanned: { [weak self] in
                guard let self, problem == nil else { return }
                self.autoCheckUpdatesIfDue(gameFolderChanged: changed)
            })
        }
    }

    /// Vérification automatique des mises à jour, **un seul endroit** : fin du
    /// lancement et choix du dossier de jeu. Décision : `UpdateCheckPolicy`
    /// (Core) ; ici réglages et trace (une passe sautée doit se voir).
    private func autoCheckUpdatesIfDue(gameFolderChanged: Bool) {
        guard UpdateCheckPolicy.shouldCheckAfterSelection(
                gameFolderChanged: gameFolderChanged,
                autoCheckEnabled: autoCheckNexusUpdates,
                lastSuccess: NexusUpdateChecker.shared.lastSuccessfulCheck,
                now: Date(), ttl: 12 * 3600) else {
            log("Vérification des mises à jour sautée : "
                + (autoCheckNexusUpdates ? "dernière réussie il y a moins de 12 h" : "désactivée dans les Réglages"),
                level: .info)
            return
        }
        checkNexusUpdates()
    }
    
    /// `onScanned` part sur main **après** la publication de `scanMods`
    /// (FIFO) : seul moment où `mods` décrit le nouveau dossier.
    func refresh(onScanned: (@MainActor () -> Void)? = nil) {
        // Heavy I/O off main; sub-methods publish back on main.
        // Repli « Farmer » résolu **ici**, sur main (P5-L5).
        let farmerFallback = localization.L(L10n.VM.defaultFarmerName)
        // Dossier de jeu résolu ici aussi, même raison.
        let resolvedGameDir = gameDir
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.scanMods(gameDir: resolvedGameDir)  // also kicks off parseSMAPILog internally
            self.reloadSaves()
            self.environment.fetchSteamUser(fallbackFarmerName: farmerFallback)
            guard let onScanned else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { onScanned() } }
        }
        // Synchronous: install marker or first 256 bytes of the log, no process
        // (`SmapiVersionEvidence.installedVersion`).
        self.environment.checkSmapiVersion()
    }

    /// `true` pendant `refreshSmapiLog()` (spinner, anti double-clic).
    var isRefreshingSmapiLog: Bool { smapiHealth.isRefreshing }

    /// Relit le journal SMAPI (alertes, diagnostics, mods périmés) sans
    /// rescanner le parc. `parseSMAPILog` publie sur main ; le drapeau
    /// s'abaisse après, dans l'ordre de la file.
    func refreshSmapiLog() {
        guard smapiHealth.beginRefresh() else { return }
        let resolvedGameDir = gameDir
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.parseSMAPILog(gameDir: resolvedGameDir)
            DispatchQueue.main.async { self.smapiHealth.endRefresh() }
        }
    }

    /// One-shot, idempotent migration from `Mods_disabled/` to `Mods/.X`,
    /// before the first `scanMods()`. Flag set even on partial failure:
    /// leftovers are covered by the permanent `Mods_disabled/` warning. Maps
    /// key on the logical `folderName`, so nothing else to migrate.
    nonisolated private func migrateDisabledModsToDotPrefix(gameDir: String) {
        // Règle en Core (`DisabledModsMigration`).
        DisabledModsMigration.runIfNeeded(gameDir: gameDir) { [weak self] message, level in
            self?.log(message, level: level)
        }
    }

    /// First load behind the launch overlay: progress + step label;
    /// `isLaunching` flips once the first mod list is published on main.
    /// Step weights are rough heuristics.
    private func performInitialLoad() {
        // Repli « Farmer » résolu sur main (P5-L5).
        let farmerFallback = localization.L(L10n.VM.defaultFarmerName)
        // Dossier de jeu aussi.
        let resolvedGameDir = gameDir
        // Step 0 — "Initializing": publish the first frame.
        DispatchQueue.main.async { [weak self] in
            self?.launchStep = self?.localization.L(L10n.Main.launchStepInit) ?? ""
            self?.launchProgress = 0.05
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Retire `nexusVersion` du registre (version non attestée ; l'app
            // affirme via les ancres), avant tout autre accès, hors fil principal.
            // Illisible = signalé. Idempotente, sans drapeau.
            switch ModVersionAnchorStore.migrateAwayFromNexusVersion() {
            case .stripped(let folders):
                // Leur version « changera » au prochain scan sans que le disque bouge :
                // la grâce empêche `syncInstalledModRegistry` d'écraser leur date
                // d'installation, irremplaçable.
                self.installedModRegistryStore.setInstallDateGrace(folders)
                self.log("Registre nettoyé : \(folders.count) entrées portaient une version Nexus non constatée",
                    level: .info)
            case .registryUnreadable:
                self.log("Registre des mods illisible : la migration n'a pas pu retirer les versions Nexus non constatées",
                    level: .warning)
            case .nothingToDo:
                break
            }

            // Step 1 — Registry: warm the in-memory cache (one decode).
            DispatchQueue.main.async { [weak self] in
                self?.launchStep = self?.localization.L(L10n.Main.launchStepRegistry) ?? ""
                self?.launchProgress = 0.15
            }
            self.installedModRegistryStore.warmCache()

            // Step 2 — Scanning mods (enabled and `.X`); publishes inside scanMods().
            DispatchQueue.main.async { [weak self] in
                self?.launchStep = self?.localization.L(L10n.Main.launchStepScan) ?? ""
                self?.launchProgress = Self.launchScanProgressStart
            }
            // Legacy `Mods_disabled/` migration; must run BEFORE the first scan.
            self.migrateDisabledModsToDotPrefix(gameDir: resolvedGameDir)
            self.scanMods(gameDir: resolvedGameDir)

            // Step 3 — Saves (can be slow with many saves).
            DispatchQueue.main.async { [weak self] in
                self?.launchStep = self?.localization.L(L10n.Main.launchStepSaves) ?? ""
                self?.launchProgress = Self.launchScanPhasesEnd
            }
            self.reloadSaves()

            // Step 4 — Steam user + profiles + Nexus caches; don't block the list.
            DispatchQueue.main.async { [weak self] in
                self?.launchStep = self?.localization.L(L10n.Main.launchStepProfile) ?? ""
                self?.launchProgress = 0.80
                // loadProfiles() mutates published state: on main.
                self?.loadProfiles()
            }
            self.environment.fetchSteamUser(fallbackFarmerName: farmerFallback)

            // Step 4b — Nexus caches + user overrides.
            DispatchQueue.main.async { [weak self] in
                self?.launchStep = self?.localization.L(L10n.Main.launchStepNexus) ?? ""
                self?.launchProgress = 0.90
            }
            self.seedNexusAndUserData()
            // Startup marker — confirms LogsView is receiving entries.
            self.log(self.localization.L(L10n.VM.started), level: .info)

            // Step 5 — Done, after scanMods() published, so `isLaunching = false`
            // lands with the populated `mods`.
            DispatchQueue.main.async { [weak self] in
                self?.launchStep = self?.localization.L(L10n.Main.launchStepDone) ?? ""
                self?.launchProgress = 1.0
            }
            // 0,45 s : laisse voir le remplissage final (~0,25 s) de la barre.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self else { return }
                self.isLaunching = false
                // Pas de garde sur la clé API : smapi.io n'en demande pas ; la garde
                // privait sans compte Nexus de toute détection. Dossier inchangé :
                // A2-T4 (TTL 12 h).
                self.autoCheckUpdatesIfDue(gameFolderChanged: false)
            }
        }
        // SMAPI version probe, synchronous (two tiny reads).
        self.environment.checkSmapiVersion()
    }
    
    /// - Parameter gameDir: résolu **sur main par l'appelant** (L5), d'où
    ///   `nonisolated` ; masque la propriété à dessein. ⚠️ **Pas de lecture
    ///   hors acteur des préférences** : `restoreGameDir` écrit avant que son
    ///   `didSet` persiste, l'ancien chemin reviendrait.
    nonisolated func scanMods(gameDir: String, includeRepair: Bool = true) {
        guard !gameDir.isEmpty else {
            // Called from background: publish on main.
            DispatchQueue.main.async { [weak self] in
                self?.scanStore.setMods([], modsFolderWasReadable: false)
                // Reset selection (the mod may have disappeared).
                self?.selectedMod = nil
            }
            return
        }

        // Repair corrupt folders *before* scanning; report published on main
        // below. `includeRepair` false after a toggle: a rename can't create
        // orphans or duplicates, and this pass caused the 5–10 s toggle delay.

        // Early (0/N) frame before the repair sweep, so the bar isn't frozen.
        let fm = FileManager.default
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        if let topCount = try? fm.contentsOfDirectory(atPath: modsPath).count, topCount > 0 {
            // Libellé résolu **dans** le saut, sur l'acteur.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let preparing = self.localization.L(L10n.Main.launchStepPreparing)
                    self.scanStore.scanProgress = ScanProgress(done: 0, total: topCount,
                                                               currentName: preparing)
                }
            }
        }

        let repairer = ModFolderRepairer()
        var repairReport = includeRepair
 ? repairer.repairIfNeeded(gameDir: gameDir, detectDuplicates: false)
            : ModFolderRepairer.Report()

        // Balayage dans `ModScanner` (Core) ; ici ce qui touche d'autres
        // domaines : réparation, journal SMAPI, registre, doublons, publication.
        let scanned = scanner.scan(
            gameDir: gameDir,
            installedModDate: { installedModDate(for: $0) },
            onProgress: { [weak self] progress in
                DispatchQueue.main.async {
                    self?.scanStore.scanProgress = progress
                }
            },
            log: { [weak self] message in
                self?.log(message, level: .warning)
            }
        )
        let scannedMods = scanned.mods

        // **Compte complet** : le throttle (80 ms, avant traitement) laissait
        // « 949/957 » affiché pendant les phases suivantes.
        publishLaunchPhase(L10n.Main.launchStepSmapiLog,
                           progress: Self.launchSmapiLogStart, entries: scanned.scannedEntries, modsFound: scanned.mods.count)
        parseSMAPILog(gameDir: gameDir, onProgress: { [weak self] fraction in
            self?.publishLaunchPhaseProgress(L10n.Main.launchStepSmapiLog,
                                             fraction: fraction,
                                             from: Self.launchSmapiLogStart,
                                             to: Self.launchSmapiLogEnd,
                                             entries: scanned.scannedEntries, modsFound: scanned.mods.count)
        })

        // Sync the installed-mod registry with disk (any install path):
        //   1. version changed → record NOW;
        //   2. first seen → record with folder mtime;
        //   3. folder gone → pruned — sauf si `Mods/` illisible (X71).
        publishLaunchPhase(L10n.Main.launchStepRegistrySync,
                           progress: Self.launchRegistrySyncProgress, entries: scanned.scannedEntries, modsFound: scanned.mods.count)
        syncInstalledModRegistry(scannedMods: scannedMods,
                                 modsFolderWasReadable: scanned.modsFolderWasReadable)
        if !scanned.modsFolderWasReadable {
            log("Dossier Mods/ introuvable ou illisible : registre d'install et ancres de version conservés en l'état",
                level: .warning)
        }

        // X/.X duplicates from the scanned mods, no extra disk walk.
        if includeRepair {
            publishLaunchPhase(L10n.Main.launchStepDuplicates,
                               progress: Self.launchDuplicatesProgress, entries: scanned.scannedEntries, modsFound: scanned.mods.count)
            let duplicates = repairer.detectDuplicates(from: scannedMods)
            repairReport = ModFolderRepairer.Report(
                quarantined: repairReport.quarantined,
                duplicates: duplicates,
                trashPath: repairReport.trashPath
            )
        }

        let modsFolderWasReadable = scanned.modsFolderWasReadable
        DispatchQueue.main.async {
            // Advance to scan-end weight BEFORE clearing scanProgress: no regression.
            self.launchProgress = Self.launchScanPhasesEnd
            self.scanStore.scanProgress = nil
            // Publish the repair report on main, only if a repair ran (a
            // toggle scan keeps the last real report).
            if includeRepair {
                // Dossiers sans manifeste « à voir » : jamais déplacés, donc jamais
                // dans `quarantined`.
                var published = repairReport
                published.reviewItems = scanned.entriesWithoutMods.map {
                    ModFolderRepairer.Item(kind: .orphanFolder, relativePath: $0,
                                           reason: "No manifest.json found — not listable as a mod. Left in place.")
                }
                if published.isEmpty && published.reviewItems.isEmpty {
                    self.maintenanceStore.setRepairReport(nil)
                } else {
                    self.maintenanceStore.setRepairReport(published)
                    if !repairReport.isEmpty {
                        self.log("Folder repair: \(repairReport.quarantined.count) item(s) quarantined, \(repairReport.duplicates.count) duplicate(s) found.", level: .info)
                    }
                }
                // X114 — le badge lit le disque, pas ce rapport.
                self.refreshTrash()
            }

            // Ordre alphabétique, packs et mods mêlés (2026-08-26) ; le tri « Nom »
            // le suppose.
            self.scanStore.setMods(scannedMods.alphabeticalListOrder, modsFolderWasReadable: modsFolderWasReadable)
            self.rebuildDependencyIndexes()
            if self.selectedMod == nil, let first = self.mods.first {
                self.selectedMod = first
            }
            // Seed a default profile on first run.
            self.ensureDefaultProfileIfNeeded()
        }

        // Poids du parc après publication (~3 s sur 100 000 fichiers). Le saut
        // par main sérialise deux demandes ; ⚠️ l'atomicité de
        // `beginSizeMeasure` tient au verrou, pas au fil.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.measureModsFolderSize() }
        }
    }

    // MARK: - Poids du parc (B2-T2)

    // ⚠️ Façades provisoires (P8, domaine 8) — état et sérialisation dans
    // `scanStore` ; ici l'orchestration des files.
    var modsFolderSizes: ModsFolderSizes? { scanStore.modsFolderSizes }
    var isMeasuringModsFolder: Bool { scanStore.isMeasuringModsFolder }

    /// Poids du parc en fond, une passe à la fois, accroché à `scanMods()` :
    /// une invalidation maison mentirait sur un chemin oublié.
    func measureModsFolderSize() {
        // Sans jeu, rien à mesurer ni à annoncer.
        guard !gameDir.isEmpty else { return }
        let alreadyRunning = scanStore.beginSizeMeasure()
        guard !alreadyRunning else { return }

        let dir = gameDir
        DispatchQueue.main.async { self.scanStore.setSizeMeasureRunning(true) }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let sizes = ModsFolderSizer.measure(
                modsFolder: URL(fileURLWithPath: dir).appendingPathComponent("Mods"))
            DispatchQueue.main.async {
                // `endSizeMeasure` publie sur main (L2) ; la mesure reste sur la file.
                let again = self.scanStore.endSizeMeasure()
                self.scanStore.setSizeMeasureResult(sizes, again: again)
                if again { self.measureModsFolderSize() }
            }
        }
    }

    /// Poids d'un mod, `nil` si non mesuré. **Nom physique** : 5 des 8 plus
    /// gros mods sont en pause ; `folderName` les donnerait à 0.
    func sizeOnDisk(of mod: ModItem) -> Int64? {
        modsFolderSizes?.bytes(forPhysicalFolder: mod.physicalFolderName)
    }

    /// Rebuilds dependency lookup indexes from `mods`; after each full scan
    /// and each in-memory toggle.
    private func rebuildDependencyIndexes() {
        let index = DependencyIndex.build(from: mods)
        dependencyIndex = index
        scanStore.setDuplicateIndex(index.duplicateIndex)
    }
    
    // Parses the SMAPI-latest.txt log for updates and errors
    /// - Parameter onProgress: fraction de **son** travail (0…1). Poids
    ///   mesurés (9,8 Mo) : diagnostic 5,4 s sur ~7,1 s.
    nonisolated func parseSMAPILog(gameDir: String, onProgress: ((Double) -> Void)? = nil) {
        // Bornes des quatre passes, proportionnelles à leur coût mesuré.
        let wDiagnostics = 0.76, wUpdates = 0.83, wConflicts = 0.93
        guard !gameDir.isEmpty else { onProgress?(1.0); return }
        
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let logPath = (homeDir as NSString).appendingPathComponent(".config/StardewValley/ErrorLogs/SMAPI-latest.txt")
        guard FileManager.default.fileExists(atPath: logPath),
              let logContent = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            DispatchQueue.main.async {
                // Journal disparu : reset, sinon anciens conflits à côté d'une date `nil`.
                self.smapiHealth.reset()
            }
            return
        }

        let (smapiDiag, smapiDate, smapiStale) = computeSmapiDiagnostics(
            logContent: logContent, atPath: logPath,
            onProgress: onProgress.map { report in { report($0 * wDiagnostics) } })

        // Bloc « You can update N mods » — voir SmapiLogParser.updates(in:).
        let updates = SmapiLogParser.updates(in: logContent)
        onProgress?(wUpdates)
        // Alimente aussi `contentPatcherConflicts` : Alertes système n'ouvre pas
        // `parseAndAppendSmapiLog`, et dirait sinon « aucun conflit » sans avoir
        // lu. Même parseur (`SmapiLogParser.parse`).
        let conflictEntries = SmapiLogParser.parse(logContent)
        onProgress?(wConflicts)
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
            // Même lecture, publiées ensemble par le store (tri par nom).
            self.smapiHealth.apply(diagnostics: smapiDiag, logDate: smapiDate,
                                   isStale: smapiStale, conflicts: conflicts,
                                   outOfDate: updates)
            // Seules les alertes **neuves** s'écrivent (`SmapiHealthFold`) ; la
            // localisation reste au VM.
            let newAlerts = self.smapiHealth.apply(errors: uniqueErrors)
            if !newAlerts.isEmpty {
                self.log(
                    String(format: self.localization.L(L10n.Logs.alertLogged), Int64(newAlerts.count)),
                    level: .warning
                )
                for err in newAlerts {
                    self.log(err, level: .warning)
                }
            }
        }
    }
    
    // Returns missing required unique IDs for a given mod
    /// Dépendance requise absente ou en pause. Au VM : cadrage « Problèmes »
    /// et pastille partagent une seule définition. Mod en pause écarté.
    func hasDependencyIssue(_ mod: ModItem) -> Bool {
        mod.isEnabled
            && (!getMissingDependencies(for: mod).isEmpty
                || !getDisabledDependencies(for: mod).isEmpty)
    }

    /// Anomalie de ligne, ou `nil` (voir `ModAnomalyReport`).
    func anomaly(for mod: ModItem) -> ModAnomaly? {
        ModAnomalyReport.anomaly(for: mod, history: modErrorHistory,
                                 dependencyIssue: { self.hasDependencyIssue($0) },
                                 duplicates: scanStore.duplicateIndex,
                                 compatibility: compatibilityStatuses)
    }



    func getMissingDependencies(for mod: ModItem) -> [String] {
        // Precomputed index — safe per row render.
        dependencyIndex.missing(for: mod)
    }

    /// Required dependencies installed but disabled (also in "Issues").
    func getDisabledDependencies(for mod: ModItem) -> [String] {
        dependencyIndex.disabled(for: mod)
    }

    /// Transitive dependency tree; a pack header uses the union of its
    /// children's dependencies. Reads `mods`, so "Enable" re-resolves.
    func dependencyTree(for mod: ModItem) -> [DependencyNode] {
        let roots = DependencyIndex.mergedPackRoots(of: mod)
        return DependencyTreeBuilder.build(roots, excluding: mod.components.map(\.uniqueId)) { [weak self] uid in
            self?.dependencyIndex.resolve(uid)
        }
    }

    /// Core-extension statuses shown in Settings.
    var coreExtensionsSnapshot: CoreExtensionsSnapshot {
        let allMods = mods.flattenedMods

        func slot(matching keyword: String) -> CoreModSlot {
            CoreModSlot.resolve(keyword: keyword, among: allMods)
        }

        return CoreExtensionsSnapshot(
            contentPatcher: slot(matching: "content patcher"),
            spacecore: slot(matching: "spacecore"),
            sve: slot(matching: "stardew valley expanded"),
            unarTool: .init(installed: unarInstalled),
            sevenZipTool: .init(installed: sevenZipInstalled)
        )
    }

    /// `true` if `unar` is available (RAR support row on home).
    var unarInstalled: Bool {
        // Même recherche que l'extraction : l'accueil n'annonce que ce que
        // l'installation sait faire.
        ModZipInstaller.firstAvailableTool(named: ["unar"]) != nil
    }

    /// `true` si `.7z` extractible, via `ModZipInstaller.find7zTool()` (même
    /// outil que l'extraction).
    var sevenZipInstalled: Bool { ModZipInstaller.find7zTool() != nil }
    
    private var isToggling = false
    private var pendingToggles: [(ModItem, (() -> Void)?)] = []

    /// A1-T8 — état de l'avertissement d'empreintes dans son store ; le VM
    /// intercepte la pause dans `performToggle` et relance au confirm.
    let saveFingerprintPauseStore = SaveFingerprintPauseStore()

    /// Bulk enable/disable progress `(done, total)`, nil when idle.
    var bulkToggleProgress: (done: Int, total: Int)? = nil

    /// Deux temps d'une application de profil : le rescan de ~1 000 mods
    /// dure, et la barre pleine semblait figée.
    enum ProfileApplyPhase: Equatable {
        /// Déplacement des dossiers de mods — un compte connu d'avance.
        case movingFolders
        /// Relecture de `Mods/` ; détail dans `scanProgress`.
        case rescanning
    }

    struct ProfileApplyProgress: Equatable {
        let done: Int
        let total: Int
        let phase: ProfileApplyPhase
    }

    /// Avancement d'une application de profil, `nil` au repos. Distinct de
    /// `bulkToggleProgress` (verrou de `toggleAllMods`) : sinon activer un
    /// profil bloquerait « tout activer ».
    private(set) var profileApplyProgress: ProfileApplyProgress? = nil
    /// Bulk toggle direction (`true` = enabling); valid while in progress.
    var bulkToggleEnabling: Bool = false

    // Toggle Mod Status. Requests run one at a time: a queued call reads
    // `mods` only after the previous full cycle (move + scan + profile sync),
    // else a shared chain-dependency folder could be moved twice ("destination
    // already exists"). See performToggle. `@MainActor` guards
    // `pendingToggles`/`isToggling`.
    @MainActor
    func toggleMod(_ mod: ModItem, completion: (() -> Void)? = nil) {
        // Refused during a bulk toggle (concurrent moves could lose a mod), and
        // during a « Tout désactiver » estimate (it would overwrite the pending
        // suspension).
        guard bulkToggleProgress == nil,
              isToggling || !saveFingerprintPauseStore.isBusy else {
            completion?()
            return
        }
        pendingToggles.append((mod, completion))
        processNextToggleIfNeeded()
    }

    @MainActor
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

    @MainActor
    private func performToggle(
        _ mod: ModItem,
        completion: (() -> Void)? = nil,
        fingerprintChecked: Bool = false
    ) {
        // Le QUOI dans `TogglePlan` (Core) : dossier de premier niveau, état
        // re-dérivé de `mods`, chaînage des dépendances. Ici le COMMENT.
        let plan = TogglePlan.make(mod: mod, mods: mods, chain: chainToggleDependencies)
        let targetState = plan.targetState
        let foldersToToggle = plan.folders

        // A1-T8 — une pause n'efface pas les traces dans les sauvegardes : avant
        // le premier renommage, chiffrer les empreintes ; le store suspend
        // derrière une confirmation. La reprise revient avec
        // `fingerprintChecked: true` — jamais deux scans.
        if !targetState && !fingerprintChecked {
            // Composants compris : l'en-tête d'un pack n'a pas d'uid.
            let planIDs = mods.uniqueIds(inTopFolders: Set(foldersToToggle))
            if !planIDs.isEmpty {
                saveFingerprintPauseStore.checkBeforePause(
                    subject: .mod(mod),
                    modIDs: planIDs,
                    resume: { [weak self] in
                        self?.performToggle(mod, completion: completion, fingerprintChecked: true)
                    },
                    abort: { completion?() })
                return
            }
        }

        let fm = FileManager.default
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        var anyMoved = false

        for folderName in foldersToToggle {
            guard let m = self.mods.first(where: { $0.folderName == folderName }) else { continue }
            if m.isEnabled == targetState { continue }

            // Defensive: an empty folderName would rename to ".", which fails.
            guard !m.folderName.isEmpty else {
                log("Skipping toggle: empty folderName for \(m.name)", level: .error)
                continue
            }

            // Dot-prefix toggle: an atomic, O(1) rename within Mods/.
            let srcPath = (modsPath as NSString).appendingPathComponent(m.physicalFolderName)
            let dstName = targetState ? m.folderName : "." + m.folderName
            let destPath = (modsPath as NSString).appendingPathComponent(dstName)

            // `mods` can be stale: trust the filesystem; a missing source was
            // already renamed by a prior call.
            guard fm.fileExists(atPath: srcPath) else {
                log("Skipping toggle for \(m.name): source folder missing at \(srcPath) (likely already renamed by a concurrent toggle)", level: .warning)
                continue
            }

            do {
                // ⚠️ Une collision n'est PAS forcément un résidu : `X` actif et `.X` en
                // pause peuvent coexister. Règle et retour arrière dans
                // `renameModFolder` (partagé).
                try renameModFolder(from: srcPath, to: destPath,
                                    destinationName: dstName,
                                    uniqueId: m.uniqueId, fm: fm)

                anyMoved = true
                // Le poids suit le renommage (clé physique change, contenu non) ; `m`
                // porte l'ancienne clé.
                self.scanStore.renameSizeKey(from: m.physicalFolderName, to: dstName)
                if targetState {
                    self.modActivationTimestamps[folderName] = Date()
                }
            } catch {
                // P5-T9 : l'échec d'un rollback remonte ; la ligne CRITICAL vit dans
                // `rollbackCriticalLog`.
                if let critical = (error as? ModFolderRenameFailure)?.rollbackCriticalLog {
                    log(critical, level: .error)
                }
                log("Failed to toggle \(m.name): \(error.localizedDescription)", level: .error)
            }
        }

        if anyMoved {
            if targetState {
                Self.saveModActivationTimestamps(self.modActivationTimestamps)
            }
            log("\(targetState ? localization.L(L10n.Mods.enabled) : localization.L(L10n.Mods.disabled)): \(mod.name)\(foldersToToggle.count > 1 ? " + Dependencies" : "")")
            // A toggle only renames in place: flip `isEnabled` in memory and rebuild
            // the dependency index instead of re-walking Mods/ (seconds). The next
            // full scan reconciles. On main: O(toggled).
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    // Self is gone: still honour the completion so callers don't hang.
                    completion?()
                    return
                }
                scanStore.setMods(TogglePlan.flipped(scanStore.mods, folders: foldersToToggle, target: targetState))
                self.rebuildDependencyIndexes()
                self.syncActiveProfileIds()
                completion?()
            }
        } else {
            completion?()
        }
    }

    /// Resolves a message key + detail for `SmapiInstaller` (only the VM
    /// translates).
    private func resolveSmapiMessage(_ key: String, _ detail: String?) -> String {
        guard let detail = detail else { return self.localization.L(key) }
        return String(format: self.localization.L(key), detail)
    }

    // Install SMAPI via Installer Helper. Complétion `@Sendable` (P5-L4) :
    // les touches au VM passent par `Task { @MainActor in }`.
    func installSmapi() {
        smapiInstaller.install(gameDir: gameDir) { success, key, detail in
            Task { @MainActor in
                self.environment.checkSmapiVersion()
                let message = self.resolveSmapiMessage(key, detail)
                self.showModal(message: message)
                self.log(message)
            }
        }
    }

    // Uninstall SMAPI — même hop `@MainActor` que `installSmapi`.
    func uninstallSmapi() {
        smapiInstaller.uninstall(gameDir: gameDir) { success, key, detail in
            Task { @MainActor in
                self.environment.checkSmapiVersion()
                let message = self.resolveSmapiMessage(key, detail)
                self.showModal(message: message)
                self.log(message)
            }
        }
    }
    
    var selectedMod: ModItem? = nil {
        didSet {
            if let mod = selectedMod, selectedModID != mod.folderName {
                selectedModID = mod.folderName
            }
        }
    }

    /// Cadrage de la liste (recherche, filtres, tri, page) : ici, pas en
    /// `@State`, car ouvrir une fiche détruit `ModListView`. Objet à part :
    /// sinon chaque lettre tapée publierait à toute la fenêtre.
    let modList = ModListState()

    var selectedModID: String? = nil {
        didSet {
            if let id = selectedModID, selectedMod?.folderName != id {
                selectedMod = mods.first { $0.folderName == id }
            }
        }
    }
    // Launch Stardew Valley (with selected profile)
    ///
    /// - Parameter honoringCloseAfterLaunch: the guided search passes `false`
    ///   so the app keeps running between its steps.
    func launchGame(honoringCloseAfterLaunch: Bool = true) {
        guard !gameDir.isEmpty else {
            showModal(message: localization.L(L10n.Settings.gameDirNotSet))
            return
        }
        // Couche 1 : jeu déjà lancé — refus (deux processus corrompraient les
        // sauvegardes). Rouvre aussi le gate.
        guard !isGameRunning() else {
            let message = self.localization.L(L10n.VM.launchRefusedRunning)
            log(message, level: .warning)
            showModal(message: message)
            return
        }
        // Couche 2 : fenêtre aveugle avant `runningApplications` ; le délai
        // retient un double-clic.
        guard launchGate.admit() else {
            let message = self.localization.L(L10n.VM.launchRefusedRecent)
            log(message, level: .warning)
            showModal(message: message)
            return
        }

        let profile = UserDefaults.standard.string(forKey: UDKey.launchProfile) ?? "SMAPI"
        let closeAfter = honoringCloseAfterLaunch
            && UserDefaults.standard.bool(forKey: UDKey.closeAfterLaunch)

        let originalPath = (gameDir as NSString).appendingPathComponent("StardewValley-original")
        
        if profile == "Vanilla" && FileManager.default.fileExists(atPath: originalPath) {
            log(localization.L(L10n.VM.launchingVanilla))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [originalPath]
            process.currentDirectoryURL = URL(fileURLWithPath: gameDir)
            do {
                try process.run()
                log(localization.L(L10n.VM.launchVanillaSuccess))
                if closeAfter { NSApplication.shared.terminate(nil) }
            } catch {
                log(String(format: localization.L(L10n.VM.launchVanillaError), error.localizedDescription))
                showModal(message: localization.L(L10n.VM.cannotStartVanilla))
            }
        } else {
            log(localization.L(L10n.VM.launchingSmapi))
            // Steam only for an actual Steam install (`steamapps` in the path):
            // `steam://` succeeds whenever Steam exists and would hijack GOG/direct.
            let isSteamInstall = gameDir.contains("steamapps")
            if isSteamInstall, let steamURL = URL(string: "steam://run/413150"),
               NSWorkspace.shared.open(steamURL) {
                log(localization.L(L10n.VM.launchSteamSuccess))
                startSmapiLogWatcher()
                if closeAfter { NSApplication.shared.terminate(nil) }
                return
            }

            // Direct/GOG: run SMAPI's launcher in place (it replaced `StardewValley`)
            // via bash, avoiding the code signature SMAPI invalidates.
            let smapiLauncher = (gameDir as NSString).appendingPathComponent("StardewValley")
            if FileManager.default.fileExists(atPath: smapiLauncher) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [smapiLauncher]
                process.currentDirectoryURL = URL(fileURLWithPath: gameDir)
                do {
                    try process.run()
                    log(localization.L(L10n.VM.launchDirectSuccess))
                    startSmapiLogWatcher()
                    if closeAfter { NSApplication.shared.terminate(nil) }
                    return
                } catch {
                    log(String(format: localization.L(L10n.VM.launchVanillaError), error.localizedDescription))
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
                log(localization.L(L10n.VM.launchDirectSuccess))
                startSmapiLogWatcher()
                if closeAfter { NSApplication.shared.terminate(nil) }
            } else {
                log(localization.L(L10n.VM.cannotStartDirect))
                showModal(message: localization.L(L10n.VM.cannotStartGame))
            }
        }
    }
    
    /// Shared formatter. `nonisolated(unsafe)` : `DateFormatter` est
    /// thread-safe en formatage ; configuré une fois ici, puis seulement lu.
    nonisolated(unsafe) private static let logTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func appendLogEntry(_ entry: LogEntry) {
        logStore.append(entry)
    }

    /// `nonisolated` (P5) : corps écrit pour le hors-main
    /// (`Thread.isMainThread`) ; les appelants du scan journalisent depuis
    /// une file de fond.
    nonisolated func log(_ message: String, level: LogLevel = .info) {
        let timestamp = Self.logTimeFormatter.string(from: Date())
        let entry = LogEntry(timestamp: timestamp, message: message, level: level, source: .app)

        if Thread.isMainThread {
            // Sur main sans preuve statique : écriture **synchrone** pour garder
            // l'ordre du journal.
            MainActor.assumeIsolated { appendLogEntry(entry) }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.appendLogEntry(entry) }
            }
        }
    }

    // MARK: - SMAPI Real-time Log Reader

    // MARK: - SMAPI Log Reader

    /// Loads SMAPI-latest.txt off main, on demand (no polling). `completion`
    /// runs on main **after** diagnostics are published.
    func loadSmapiLog(completion: (@Sendable () -> Void)? = nil) {
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

        // Trim by dropping TRACE, not the head: SMAPI writes its diagnostic at
        // startup, so cutting the head hid the lines that matter. Borne le
        // travail ; le plafond d'affichage vit dans `LogStore`.
        let trimmedEntries = LogBudget.trimPreservingSignal(entries, cap: LogStore.defaultCap)

        DispatchQueue.main.async {
            // Imputations **devinées** confrontées au parc ici (`mods` illisible
            // dans le parseur) : sinon pastilles vers nulle part (3 faux cas). Le
            // crochet de SMAPI n'est jamais remis en cause. Parc vide : on ne juge
            // rien.
            let displayed = self.mods.isEmpty
                ? trimmedEntries
                : SmapiLogParser.dismissingUnknownInferredMods(trimmedEntries) { name in
                    self.resolveModFolder(forLoggedName: name) != nil
                }
            // Remplace et budgète le bloc SMAPI (`LogBudget`).
            self.logStore.replaceSmapi(with: displayed)
            // Conflits lus sur `entries` (parse complet) ; date et conflits publiés
            // ensemble par le store. ⚠️ `outOfDate` relu **ici aussi** (fichier
            // entier) : sinon date fraîche, liste du dernier scan.
            self.smapiHealth.apply(diagnostics: smapiDiag, logDate: smapiDate,
                                   isStale: smapiStale,
                                   conflicts: ContentPatcherConflicts.read(from: entries),
                                   outOfDate: SmapiLogParser.updates(in: text))
            // Error history from the full parse: the display cap must not drop errors.
            self.recordErrorHistory(from: entries, logDate: smapiDate)
            completion?()
        }
    }

    // MARK: - Per-mod error history

    // MARK: Historique d'erreurs — le store du sous-domaine (cadrage §4,
    // domaine 2, tranche 3) : garde « rien avant le chargement » dans le store.
    private let errorHistory = ErrorHistoryStore()

    /// Per-mod, per-version error history, loaded once.
    var modErrorHistory: ModErrorHistory { errorHistory.history }

    /// Folds a SMAPI log into the error history and persists it. Skips logs
    /// already folded (re-read on every open) and undated ones.
    private func recordErrorHistory(from entries: [LogEntry], logDate: Date?) {
        errorHistory.loadIfNeeded()
        guard let logDate,
              SmapiHealthFold.shouldFold(logDate: logDate,
                                         lastFolded: errorHistory.lastFoldedDate) else { return }
        // `resolveModFolder` a besoin du parc ; la règle est en Core.
        let observations = SmapiHealthFold.observations(from: entries) { name in
            guard let mod = resolveModFolder(forLoggedName: name) else { return nil }
            return .init(folderName: mod.folderName, version: mod.version)
        }
        errorHistory.fold(observations, at: logDate)
    }

    /// Relie un nom journalisé au `ModItem` installé. Non privé : la
    /// recherche guidée l'utilise aussi.
    func resolveModFolder(forLoggedName name: String) -> ModItem? {
        let all = mods.flattenedMods
        // Égalité exacte (insensible à la casse) d'abord.
        if let exact = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return exact
        }
        // Repli : le plus court des noms contenant — « FarmExpansion » est
        // sûrement un autre mod que « Farm ».
        let containing = all.filter { $0.name.localizedCaseInsensitiveContains(name) }
        return containing.min(by: { $0.name.count < $1.name.count })
    }

    /// `folderName` logiques d'un conflit, dans l'ordre du message (CP imprime
    /// des noms d'affichage). **Non résolu = gardé tel quel** : mieux qu'un
    /// conflit tu ; l'appelant teste l'appartenance à `mods`.
    func conflictFolderNames(_ conflict: LoadConflict) -> [String] {
        conflict.packs.map { resolveModFolder(forLoggedName: $0)?.folderName ?? $0 }
    }

    /// Paire canonique d'un conflit ; `nil` au-delà de deux packs (aucune
    /// paire ne représente le groupe, jamais filtré par un verdict — voir
    /// `ModConflictSection`). Une seule copie : fiche et
    /// `conflictWarning(for:)` s'en servent aussi.
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

    /// Chemin du journal SMAPI ; la recherche guidée surveille sa date.
    var smapiLogPath: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return (homeDir as NSString).appendingPathComponent(
            ".config/StardewValley/ErrorLogs/SMAPI-latest.txt"
        )
    }

    /// Diagnostics + staleness from already-read log content; safe off-main.
    /// Shared by `parseSMAPILog` and `parseAndAppendSmapiLog`.
    nonisolated private func computeSmapiDiagnostics(logContent: String, atPath path: String,
                                        onProgress: ((Double) -> Void)? = nil)
    -> (SmapiDiagnostics, Date?, Bool) {
        let diag = SmapiDiagnostics.parse(logContent: logContent, onProgress: onProgress)
        let mtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
        let stale = (mtime ?? .distantFuture) < sessionStart
        return (diag, mtime, stale)
    }

    /// Reveals SMAPI-latest.txt in a Finder window (U6 "Open in Finder").
    func revealSmapiLogInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: smapiLogPath)])
    }

    func startSmapiLogWatcher() { loadSmapiLog() }

    /// Kept for `LogsView.onDisappear`; nothing to tear down.
    func stopSmapiLogWatcher() {}

    // MARK: - Nexus Mods update checking

    /// Persists a Nexus Mods API key to Keychain and refreshes `hasNexusApiKey`.
    func setNexusApiKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // « Configurée » seulement si la Keychain accepte.
        if NexusUpdateChecker.shared.setApiKey(trimmed) {
            // Nouvelle clé, nouveau compte : `keyAccepted()` pose les deux.
            accountStore.keyAccepted()
            refreshNexusAccount()
        }
    }

    /// Relit le dernier quota (réglages, `quotaDidChange`) ; il ne bouge
    /// qu'après une action.
    func refreshNexusQuota() {
        accountStore.setQuota(NexusUpdateChecker.shared.cachedQuota())
    }

    /// Redemande à Nexus si ce compte est premium.
    func refreshNexusAccount() {
        guard hasNexusApiKey || NexusUpdateChecker.shared.apiKey()?.isEmpty == false else { return }
        // Complétion `@Sendable` (P5-L4) : hop `Task { @MainActor in }`.
        NexusUpdateChecker.shared.fetchAccount { [weak self] account in
            guard let account else { return }
            Task { @MainActor in self?.accountStore.setAccount(account) }
        }
    }

    /// Removes the stored Nexus Mods API key.
    func clearNexusApiKey() {
        NexusUpdateChecker.shared.clearApiKey()
        // Clé, compte et quota partent ensemble — les mises à jour n'en dépendent
        // pas.
        accountStore.clearKey()
        nexusCategories = [:]
        nexusModExtras = [:]
        updateStore.setCheckError(nil)
    }

    /// Demande à smapi.io, en un appel groupé, s'il existe plus récent.
    /// smapi.io compare (`UpdateKeys`, composant par composant) ; l'app fournit
    /// la version **affirmée** (ancre, sinon manifest). Composition des deux
    /// requêtes (filet Pathoschild en parallèle) dans `NexusUpdateCheck`
    /// (Core) ; ici gardes, candidats, effets et relâchement.
    func checkNexusUpdates() {
        guard !isCheckingNexusUpdates else { return }
        updateStore.beginCheck()
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
        // Une version illisible vide **tout son lot** (150 mods, HTTP 200 muet) ;
        // le repli (`SmapiUpdateRequest`) se journalise.
        let entries = SmapiUpdateRequest.entries(
            from: candidates, anchors: anchors,
            reportingSubstitution: { [weak self] uniqueId, refused, sent in
                self?.log("Version affirmée inutilisable pour \(uniqueId) : « \(refused) » "
                          + "n'est pas analysable par smapi.io, envoi de "
                          + (sent.isEmpty ? "rien" : "« \(sent) »"), level: .warning)
            })
        // Parc **tel qu'interrogé**, figé avec la requête : un scan peut survenir
        // avant la réponse.
        let folders = installed.map {
            NexusIdLearning.Folder(folderName: $0.folderName,
                                   uniqueId: $0.uniqueId,
                                   updateKeys: $0.updateKeys)
        }

        NexusUpdateCheck.run(
            entries: entries, folders: folders,
            gameVersion: smapiDiagnostics?.gameVersion,
            smapiFetch: { entries, gameVersion, progress, completion in
                SmapiUpdateClient.shared.fetch(
                    entries: entries, gameVersion: gameVersion,
                    progress: { done, total in progress(done, total) },
                    completion: { result in
                        // Progression smapi.io close dès son retour, sans attendre le dump.
                        Task { @MainActor in
                            self.updateStore.setProgress(nil)
                            completion(result)
                        }
                    })
            },
            pathoschildFetch: { [weak self] done in
                PathoschildCompatibilityList.fetch { result in
                    switch result {
                    case .failure:
                        done(true)
                    case .success:
                        done(false)
                    }
                    // Dump posé : les lignes « à savoir » peuvent changer. `done` **avant**
                    // le hop.
                    Task { @MainActor in self?.refreshModWarnings() }
                }
            },
            progress: { [weak self] done, total in
                Task { @MainActor in
                    self?.updateStore.setProgress(.init(done: done, total: total))
                }
            },
            completion: { [weak self] composition in
                guard let self else { return }
                for line in composition.journal {
                    self.log(line.text, level: line.level)
                }
                switch composition.resolution {
                case .applied(let isComplete):
                    guard case .success(let outcome) = composition.smapiResult else { return }
                    self.applySmapiResults(outcome.mods, entries: composition.entries,
                                           folders: composition.folders)
                    self.compatibilitySource = .live
                    // Passe amputée ≠ succès : l'enregistrer couperait l'auto-vérification
                    // 12 h (`UpdateCheckPolicy`) et reporterait ces mods sur le quota Nexus.
                    // Depuis X47 : lot échoué deux fois ou budget de re-découpage épuisé (X64).
                    if isComplete {
                        NexusUpdateChecker.shared.recordSuccessfulCheck()
                    }
                case .failed:
                    self.updateStore.setCheckError(composition.checkError)
                    self.applyPathoschildFallback(entries: composition.entries)
                case .noResult:
                    break
                }
                // Reset AFTER the heavy work, else a fast user re-triggers a check. Sauf
                // reprise Nexus en cours (lancée par `applySmapiResults`) :
                // `finishNexusFallback` relâche alors. Décision dans le store.
                self.updateStore.endCheck()
            })
    }

    /// Verdict qui **demande une décision** et le composant qui le porte (le
    /// plus grave d'un pack). `nil` = sain, réglé par la version installée,
    /// **ou** inconnu (552/840) — jamais un satisfecit.
    func compatibilityWarning(for mod: ModItem) -> (component: ModItem,
                                                    verdict: ModCompatibility)? {
        let components = mod.components
        return components
            .compactMap { component -> (component: ModItem, verdict: ModCompatibility)? in
                guard let verdict = modCompatibility[component.uniqueId], verdict.status.needsAttention,
                      !isSettledCompatibility(verdict, for: component) else { return nil }
                return (component, verdict)
            }
            .max { $0.verdict.status.severity < $1.verdict.status.severity }
    }

    /// smapi.io juge par `UniqueID`, pas par version (`CompatibilityResolution`).
    func isSettledCompatibility(_ verdict: ModCompatibility, for mod: ModItem) -> Bool {
        CompatibilityResolution.resolution(of: verdict, installedVersion: mod.version,
                                           installedNexusId: effectiveNexusModId(for: mod)) != nil
    }

    /// État de page Nexus le plus grave d'un mod ou composant (A2-T6), pour
    /// badge et bandeau.
    func nexusPageState(for mod: ModItem) -> (component: ModItem,
                                              state: NexusPageState)? {
        mod.components
            .compactMap { component -> (component: ModItem, NexusPageState)? in
                guard let state = updateStore.nexusPageStates[component.uniqueId] else { return nil }
                return (component, state)
            }
            .max { $0.state.severity < $1.state.severity }
    }

    /// Les mods installés que smapi.io signale, par nom, du plus grave au moins.
    var compatibilityFlaggedMods: [(name: String, folderName: String, verdict: ModCompatibility)] {
        allInstalledMods()
            .compactMap { mod -> (name: String, folderName: String, verdict: ModCompatibility)? in
                guard let verdict = modCompatibility[mod.uniqueId], verdict.status.needsAttention,
                      !isSettledCompatibility(verdict, for: mod) else { return nil }
                return (mod.name, mod.folderName, verdict)
            }
            .sorted {
                $0.verdict.status.severity != $1.verdict.status.severity
                    ? $0.verdict.status.severity > $1.verdict.status.severity
                    : $0.name.lowercased() < $1.name.lowercased()
            }
    }

    /// Mods que smapi.io ne sait **pas** juger (552/840, 2026-08-25) : une
    /// absence de signalement ne vaut pas quitus.
    var compatibilityUnknownCount: Int {
        allInstalledMods().filter { !$0.uniqueId.isEmpty && modCompatibility[$0.uniqueId] == nil }
            .count
    }

    /// Avertissement **avant d'activer**. `nil` si déjà actif (pause d'un mod
    /// cassé = geste voulu) ; l'application d'un profil passe par `toggleMod`.
    func activationWarning(for mod: ModItem) -> (component: ModItem,
                                                 verdict: ModCompatibility)? {
        guard !mod.isEnabled else { return nil }
        return compatibilityWarning(for: mod)
    }

    /// Mod **actif** avec lequel activer `mod` formerait un conflit connu.
    /// **Séparée** d'`activationWarning` (type de retour taillé pour smapi.io,
    /// déjà consommé par `compatibilityGate`). État **actuel** du parc
    /// seulement ; paire déclarée ou observée, jamais écartée — règle dans
    /// `ModConflictVerdicts.activationConflict`.
    func conflictWarning(for mod: ModItem) -> ModItem? {
        guard !mod.isEnabled else { return nil }
        // Un conflit du journal cite les composants (`SVE/Farm`) : en-tête et
        // composants dans `activating`.
        let activating = Set([mod.folderName] + (mod.children ?? []).map(\.folderName))
        let activeFolders = Set(mods.flattenedMods.filter(\.isEnabled).map(\.folderName))
        let candidates = modConflictVerdicts.declared + contentPatcherConflicts.compactMap(conflictPair)
        guard let otherFolder = modConflictVerdicts.activationConflict(
            activating: activating, candidates: candidates, activeFolders: activeFolders
        ) else { return nil }
        return mods.flattenedMods.first(where: { $0.folderName == otherFolder })
    }

    /// Verdicts smapi.io en lignes affichables. Décisions dans `SmapiVerdicts`
    /// (Core) ; ici publication, persistance, journal et reprise Nexus.
    private func applySmapiResults(_ mods: [SmapiUpdateResponse.Mod],
                                   entries: [SmapiUpdateRequest.Entry],
                                   folders: [NexusIdLearning.Folder]) {
        // Nom déclaré, le même que dans la liste.
        let installedName = Dictionary(
            allInstalledMods().filter { !$0.uniqueId.isEmpty }.map { ($0.uniqueId, $0.name) },
            uniquingKeysWith: { first, _ in first })
        let app = SmapiVerdicts.apply(
            mods, entries: entries,
            installedNames: installedName,
            anchors: anchorStore.all(),
            pathoschildIndex: PathoschildNexusIndex.loadFromCache(),
            previousRows: NexusUpdateChecker.shared.cachedUpdates(),
            previousVerdicts: modCompatibility)

        updateStore.setUnverifiable(app.unverifiable)
        modCompatibility = app.verdicts
        if !ModCompatibilityStore.save(app.verdicts) {
            // Verdicts valables pour la session seulement.
            log("Verdicts de compatibilité non enregistrés : l'avertissement à "
                + "l'activation ne survivra pas à la fermeture", level: .warning)
        }
        // A2-T3 : smapi.io a parlé ; le dump reste en cache pour la prochaine
        // panne.
        compatibilitySource = .live
        pathoschildDumpDate = PathoschildCompatibilityList.dumpFetchedAt()

        // `metadata.nexusID` retenu pour tous les mods.
        learnNexusIds(from: mods, folders: folders)

        // Persister, sinon le lancement suivant réaffiche l'ancienne liste.
        NexusUpdateChecker.shared.replaceCachedUpdates(app.merged)
        // Republier depuis le cache : vérification et redémarrage donnent le
        // même décompte.
        republishUpdatesFromCache()

        for trigger in app.report.resumeTriggered {
            log("Reprise Nexus déclenchée sans verdict smapi.io : \(trigger.uniqueId) → \(trigger.resolvedId)",
                level: .info)
        }
        let missing = entries.count - mods.count
        if missing > 0 {
            log("Vérification incomplète : \(mods.count) mods sur \(entries.count) ont répondu ; "
                + "\(app.report.unansweredCount) lignes conservées faute de verdict",
                level: .warning)
        }
        if app.report.droppedCount > 0 {
            log("\(app.report.droppedCount) lignes retirées : leur mod n'est plus installé", level: .info)
        }
        log("[MAJ] Mises à jour : \(app.updates.count) trouvée(s) sur \(mods.count) mods interrogés, \(app.unverifiable.count) non vérifiables",
            level: app.updates.isEmpty ? .info : .warning)

        recheckBlockedViaNexus(app.blocked)
    }

    /// A2-T3 — smapi.io muet : dump Pathoschild. **Silencieux** sans rien à
    /// dire ; jointure sur les `UniqueID` envoyés ; n'écrit que les verdicts
    /// **inconnus** (smapi.io prime). TTL 6 h ; hors ligne, cache périmé.
    private func applyPathoschildFallback(entries: [SmapiUpdateRequest.Entry]) {
        let uniqueIds = entries.map(\.id).filter { !$0.isEmpty }
        guard !uniqueIds.isEmpty else { return }
        PathoschildCompatibilityList.fetch { [weak self] result in
            guard let self else { return }
            // Complétion `@Sendable` (P5-L5) : le hop le **prouve** au compilateur.
            Task { @MainActor in
                let entries = (try? result.get()) ?? []
                guard !entries.isEmpty else {
                    // Dire **pourquoi** : réponse illisible ≠ panne réseau.
                    switch result {
                    case .failure(.decoding(let detail)):
                        self.log("Filet Pathoschild : dump reçu mais illisible (\(detail)) — "
                                 + "cache conservé", level: .warning)
                    case .failure(.http(let code)):
                        self.log("Filet Pathoschild : HTTP \(code), et aucun cache lisible",
                                 level: .info)
                    case .failure(.transport(let detail)):
                        self.log("Filet Pathoschild : réseau indisponible (\(detail)) et aucun "
                                 + "cache lisible", level: .info)
                    case .success:
                        self.log("Filet Pathoschild : dump vide", level: .info)
                    }
                    return
                }
                let verdicts = PathoschildCompatibilityList.verdicts(for: uniqueIds, from: entries)
                guard !verdicts.isEmpty else {
                    self.log("Filet Pathoschild : 0 verdict applicable sur \(uniqueIds.count) mods", level: .info)
                    self.compatibilitySource = .diskCache
                    self.pathoschildDumpDate = PathoschildCompatibilityList.dumpFetchedAt()
                    return
                }
                // Pathoschild **secondaire** : ne remplace pas un verdict smapi.io.
                var merged = self.modCompatibility
                var added = 0
                for (uniqueId, verdict) in verdicts where merged[uniqueId] == nil {
                    merged[uniqueId] = verdict
                    added += 1
                }
                if added == 0 {
                    self.log("Filet Pathoschild : aucun verdict à ajouter (les \(verdicts.count) "
                             + "troués sont déjà couverts)", level: .info)
                    return
                }
                // Purge des désinstallés : `stillInstalled` = parc figé à l'envoi.
                let stillInstalled = Set(uniqueIds)
                merged = merged.filter { stillInstalled.contains($0.key) }
                self.modCompatibility = merged
                if ModCompatibilityStore.save(merged) {
                    self.log("Filet Pathoschild : \(added) verdicts ajoutés sur "
                             + "\(uniqueIds.count) mods interrogés", level: .info)
                } else {
                    self.log("Filet Pathoschild : verdicts non enregistrés (\(added) ajoutés en mémoire)",
                             level: .warning)
                }
                self.compatibilitySource = .pathoschildDump
                self.pathoschildDumpDate = PathoschildCompatibilityList.dumpFetchedAt()
            }
        }
    }

    /// B2-T10 — reprend par Nexus les mods que smapi.io n'a pas su juger
    /// (*Powered Automation*, 2026-08-27). Parc : 122 bloqués, 51 repris,
    /// 41 pages ; quota 2 000/h, et **à la demande** seulement. Sans clé :
    /// rien, sans erreur. **En série** : une rafale risquerait un 429, qui
    /// arrête la reprise sans compter d'échecs.
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
        updateStore.beginFallback(pages: targets.count)
        fetchNexusFallback(targets, index: 0, found: [], settled: [], failures: 0, notFound: 0,
                           pageStates: [:])
    }

    /// Une page après l'autre. `settled` = mods tranchés par Nexus (mise à
    /// jour trouvée **ou** absente). Décisions d'une page dans `NexusResume`
    /// (Core) ; récursion, progression et journal ici.
    private func fetchNexusFallback(_ targets: [NexusFallbackCheck.Target],
                                    index: Int,
                                    found: [NexusUpdateChecker.ModUpdate],
                                    settled: Set<String>,
                                    failures: Int,
                                    notFound: Int,
                                    pageStates: [String: NexusPageState]) {
        guard index < targets.count else {
            finishNexusFallback(found: found, settled: settled,
                                failures: failures, attempted: targets.count,
                                notFound: notFound, pageStates: pageStates)
            return
        }
        let target = targets[index]
        // Complétion `@Sendable` (P5-L4) : hop `Task { @MainActor in }` ; ordre
        // journal → progression → page suivante intact.
        NexusUpdateChecker.shared.fetchSingleMod(modId: target.nexusId) { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                let outcome = NexusResume.applyPage(result, target: target,
                                                    pageIndex: index,
                                                    found: found, settled: settled,
                                                    failures: failures)
                for line in outcome.journal {
                    self.log(line.text, level: line.level)
                }
                if outcome.rateLimitedRetryAfter != nil {
                    self.finishNexusFallback(found: outcome.found, settled: outcome.settled,
                                             failures: outcome.failures, attempted: index,
                                             notFound: notFound + outcome.notFoundPages,
                                             pageStates: pageStates.merging(outcome.pageStates) { _, new in new })
                    return
                }
                self.updateStore.setProgress(.init(done: index + 1, total: targets.count))
                self.fetchNexusFallback(targets, index: index + 1,
                                        found: outcome.found, settled: outcome.settled,
                                        failures: outcome.failures,
                                        notFound: notFound + outcome.notFoundPages,
                                        pageStates: pageStates.merging(outcome.pageStates) { _, new in new })
            }
        }
    }

    /// Publie la reprise et retire les mods tranchés des « non vérifiables ».
    /// Substitution et bilan dans `NexusResume.settle` (Core).
    private func finishNexusFallback(found: [NexusUpdateChecker.ModUpdate],
                                     settled: Set<String>,
                                     failures: Int,
                                     attempted: Int,
                                     notFound: Int,
                                     pageStates: [String: NexusPageState]) {
        // Baissé **en premier** : les deux sorties passent ici, et un drapeau
        // levé bloquerait la vérification pour la session.
        updateStore.endFallback()

        let settlement = NexusResume.settle(
            found: found, settled: settled, failures: failures,
            attempted: attempted,
            cachedRows: NexusUpdateChecker.shared.cachedUpdates(),
            notFoundPages: notFound, pageStates: pageStates)

        // Les états de page **remplacent** les anciens (A2-T6) ; purge des
        // désinstallés avant publication.
        let installedIds = Set(allInstalledMods().filter { !$0.uniqueId.isEmpty }
            .map(\.uniqueId))
        let states = NexusPageState.prune(settlement.pageStates, keeping: installedIds)
        updateStore.setNexusPageStates(states)
        if !NexusPageStateStore.save(states) {
            log("États de page Nexus non enregistrés : les badges de fiche "
                + "repartiront du cache précédent", level: .warning)
        }
        if !found.isEmpty {
            NexusUpdateChecker.shared.replaceCachedUpdates(settlement.merged)
            republishUpdatesFromCache()
        }
        if !settled.isEmpty {
            updateStore.settle(settled)
        }
        for line in settlement.journal {
            log(line.text, level: line.level)
        }
    }

    /// Retient l'id Nexus que smapi.io connaît pour les mods dont le manifeste
    /// n'en déclare pas (parc : 148 sans clé, 30 identifiés, 20 gagnés).
    /// Règle dans `NexusIdLearning` (Core) : le manifeste fait foi, saisie
    /// manuelle jamais écrasée, rien réécrit à l'identique.
    /// - Parameter folders: le parc **tel qu'interrogé**.
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

        // Journal par entrée, trié ; fusion + persistance en un bloc (store).
        for (folderName, id) in plan.sorted(by: { $0.key < $1.key }) {
            log(String(format: localization.L(L10n.VM.nexusIdLearned), folderName, id))
        }
        nexusMetadata.mergeCustomModIds(plan)
    }

    /// « Je l'ai déjà » : l'utilisateur affirme avoir la version suggérée —
    /// seule issue quand l'auteur n'a pas incrémenté `Version`. L'ancre
    /// `.userAffirmed` éteint la ligne pour de bon.
    /// ⚠️ Version enregistrée = celle **affichée**, parfois une étiquette
    /// Nexus libre (« 5 ») : voulu, ne pas « corriger ». `NexusFallbackCheck`
    /// compare l'ancre à la page ; la traduction pour smapi.io se fait à la
    /// requête (`SmapiUpdateRequest.isExpressibleVersion`).
    func affirmInstalled(uniqueId: String, version: String) {
        anchorStore.put(ModVersionAnchorRules.afterUserAffirmation(
            uniqueId: uniqueId, version: version, now: Date()))
        refreshAffirmedUpdates()
        // Par `UniqueID` (`$0.id`), pas `name` ni `nexusModId` (partagé). Cache
        // d'abord : sinon la ligne revient au lancement suivant.
        NexusUpdateChecker.shared.dismissUpdate(uniqueId: uniqueId)
        republishUpdatesFromCache()
    }

    /// Relit les avertissements du dump (disque seul) pour les mods installés.
    /// Cache absent : table vide, sans effet.
    func refreshModWarnings() {
        let installed = allInstalledMods().map(\.uniqueId).filter { !$0.isEmpty }
        guard !installed.isEmpty,
              let data = PathoschildCompatibilityList.loadFreshCache()
                ?? PathoschildCompatibilityList.cachedAnyAgeNow(),
              let entries = PathoschildCompatibilityList.decode(data) else {
            modWarnings = [:]
            return
        }
        modWarnings = PathoschildCompatibilityList.warnings(for: installed, from: entries)
    }

    // MARK: - Renommer le dossier d'un mod (X60)

    /// Ce que le renommage a donné.
    enum ModFolderRenameOutcome: Equatable {
        case renamed(newFolderName: String)
        case refused(ModFolderRename.Verdict)
        /// Renommage disque échoué ; aucun magasin n'a bougé.
        case failed(String)
    }

    /// Renomme le dossier d'un mod et emmène tout ce qui s'indexe dessus.
    /// `ModItem.id` = `folderName` : `X` et `.X` (deux `[CP] Seaside Sounds`
    /// du parc) partagent identité, favori, catégorie, id Nexus, horodatage et
    /// config de profil. Renommer supprime **la cause**.
    /// ⚠️ **Liste exhaustive obligatoire** : un magasin oublié perd en silence
    /// favori, note ou sauvegarde (relevé 2026-09-05 : X55, `UDKey`,
    /// gestionnaires de fichiers). Ce qui suit l'`UniqueID` n'y est pas.
    @discardableResult
    func renameModFolder(_ mod: ModItem, to rawName: String) -> ModFolderRenameOutcome {
        let old = mod.folderName
        let existing = mods.map(\.folderName)
        let verdict = ModFolderRename.validate(rawName, renaming: old, existing: existing)
        guard verdict == .ok else { return .refused(verdict) }
        let new = ModFolderRename.sanitized(rawName)

        // Le disque d'abord : si le renommage échoue, aucun magasin n'a bougé.
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let src = (modsPath as NSString).appendingPathComponent(mod.physicalFolderName)
        let newPhysical = ModFolderRename.physicalName(new, pausedLike: mod.physicalFolderName)
        let dst = (modsPath as NSString).appendingPathComponent(newPhysical)
        do {
            try FileManager.default.moveItem(atPath: src, toPath: dst)
        } catch {
            return .failed(error.localizedDescription)
        }

        // Un **autre** mod réclame-t-il l'ancien nom ? Voir
        // `ModFolderRename.SharedKeyPolicy`.
        let stillClaimed = mods.contains { $0.folderName == old && $0.uniqueId != mod.uniqueId }
        migrateFolderKeyedStores(from: old, to: new, shared: stillClaimed)

        log(String(format: localization.L(L10n.Mods.renamedLog), old, new))
        let resolvedGameDir = gameDir
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.scanMods(gameDir: resolvedGameDir)
        }
        return .renamed(newFolderName: new)
    }

    /// Les douze surfaces indexées par nom de dossier — cœur du geste.
    private func migrateFolderKeyedStores(from old: String, to new: String,
                                          shared: Bool) {
        // 1-5. Préférences câblées par X55 (hors id Nexus, voir plus bas).
        if ModFolderRename.migrate(&favoriteMods, from: old, to: new,
                                   shared: shared) {
            Self.saveFavoriteMods(favoriteMods)
        }
        if ModFolderRename.migrate(&blacklistedMods, from: old, to: new,
                                   shared: shared, policy: .leaveBehind) {
            Self.saveBlacklistedMods(blacklistedMods)
        }
        if ModFolderRename.migrate(&profileManagedConfigMods, from: old, to: new,
                                   shared: shared) {
            Self.saveProfileManagedConfigMods(profileManagedConfigMods)
        }
        if ModFolderRename.migrate(&modActivationTimestamps, from: old, to: new,
                                   shared: shared) {
            Self.saveModActivationTimestamps(modActivationTimestamps)
        }
        // Id Nexus saisi = **affirmation**, pas préférence : en collision, gardé
        // par celui qui reste (sinon mises à jour et X62 sur la page d'un autre) ;
        // le renommé le réapprend de ses `UpdateKeys`.
        nexusMetadata.migrateFolderName(from: old, to: new, shared: shared)

        // 6. Registre : sinon « vu pour la première fois », date perdue. En
        // collision, le renommé repart neuf (date copiée = inventée).
        // Sous verrou (`mutateIfChanged`, course du 2026-08-05) ; `_ =` : le
        // `Bool` rendu ne sert pas.
        _ = installedModRegistryStore.mutateIfChanged {
            ModFolderRename.migrate(&$0, from: old, to: new,
                                    shared: shared, policy: .leaveBehind)
        }

        // 7. L'historique d'erreurs par version.
        errorHistory.rename(from: old, to: new, shared: shared)

        // 8-9. Sauvegardes de config et d'installation : affirmations, gardées
        // par celui qui garde le nom en collision.
        ModConfigBackupManager.shared.renameMod(from: old, to: new, shared: shared)
        ModInstallBackupManager.shared.renameMod(from: old, to: new, shared: shared)

        // 10. La référence de traduction et son index de clés obsolètes.
        if let store = TranslationBaseline.defaultDirectory() {
            try? TranslationBaseline.rename(modFolderName: old, to: new, in: store)
        }

        // 11. Les configurations retenues par chaque profil.
        for profile in modProfiles {
            guard let url = ProfileConfigStore.fileURL(profileId: profile.id) else { continue }
            var entries = ProfileConfigStore.load(from: url)
            if ModFolderRename.migrate(&entries, from: old, to: new,
                                       shared: shared) {
                ProfileConfigStore.save(entries, to: url)
            }
        }

        // 12. Les traductions et greffes posées sur ce mod.
        var renamed = false
        translationHub.mutateInstalled { renamed = $0.rename(host: old, to: new) }
        if renamed {
            if !InstalledTranslationStore.save(installedTranslations) {
                log("Suivi des traductions non enregistré après renommage : il ne survivra pas à la fermeture",
                    level: .warning)
            }
        }

        // Deux caches de session ; le poids est sur le nom **physique**.
        scanStore.renameSizeKey(from: old, to: new)
        scanStore.renameSizeKey(from: "." + old, to: "." + new)
        // `invalidateFrenchCoverage` est `@MainActor` ; `assumeIsolated` la
        // garde **synchrone**, avant le rescan (un `Task` passerait après).
        MainActor.assumeIsolated {
            invalidateFrenchCoverage(for: old)
        }
    }

    /// Recompose les affirmations depuis ancres et parc (voir
    /// `affirmedUpdates`). `allInstalledMods()` déplie les packs : une
    /// affirmation porte sur un composant.
    func refreshAffirmedUpdates() {
        updateStore.setAffirmed(AffirmedUpdates.rows(
            anchors: anchorStore.all(),
            installed: allInstalledMods().map {
                AffirmedUpdates.InstalledMod(uniqueId: $0.uniqueId, name: $0.name,
                                             version: $0.version,
                                             folderName: $0.folderName)
            }))
    }

    /// « Réafficher » : retire l'affirmation d'un mod (seul appelant de
    /// `remove(uniqueId:)`). **La ligne ne revient pas sur-le-champ**, assumé :
    /// une passe complète sur un clic serait disproportionnée ; l'aide le dit.
    func revealAffirmedUpdate(uniqueId: String) {
        anchorStore.remove(uniqueId: uniqueId)
        refreshAffirmedUpdates()
        log("Affirmation « je l'ai déjà » retirée pour \(uniqueId) — "
            + "la ligne reviendra à la prochaine vérification", level: .info)
    }

    /// Voir `ModVersionAnchorStore.anchorInstalled`.
    @discardableResult
    func anchorInstalledMods(installedFolderPaths: [String],
                             nexusFacts: NexusInstallFacts? = nil) -> [String] {
        anchorStore.anchorInstalled(folderPaths: installedFolderPaths, nexusFacts: nexusFacts)
    }

    /// **Invariant** : la liste affichée est toujours la consolidation par pack
    /// du cache plat (une ligne par `UniqueID`, jamais regroupé à l'écriture).
    /// Passer par ici, sinon redémarrage et « Vérifier » divergent. Sur main,
    /// après le scan (lit `mods`).
    private func republishUpdatesFromCache() {
        // Ordre alphabétique testé dans `NexusUpdateConsolidation`, pas retrié.
        let consolidated = consolidateUpdatesByPack(NexusUpdateChecker.shared.cachedUpdates())
        // R3 — partition actifs / en veille, **après** consolidation, sans
        // toucher le cache plat (une passe partielle doit y fusionner,
        // 2026-09-03). Version du jeu brute, comme au snooze.
        let gameVersion = smapiDiagnostics?.gameVersion
        var active: [NexusUpdateChecker.ModUpdate] = []
        var sleeping: [NexusUpdateChecker.ModUpdate] = []
        for row in consolidated {
            if updateSnoozer.isSnoozed(uniqueId: row.uniqueId,
                                       currentModVersion: row.latestVersion,
                                       currentGameVersion: gameVersion) {
                sleeping.append(row)
            } else {
                active.append(row)
            }
        }
        // Publiées ensemble : sinon un mod dans les deux listes, ou aucune.
        updateStore.setPartition(active: active, sleeping: sleeping)
    }

    /// R3 — met en veille : la ligne quitte la liste et le badge, revient à
    /// l'échéance. Inventaire intact.
    func snoozeUpdate(_ update: NexusUpdateChecker.ModUpdate,
                      mode: ModUpdateSnoozeEntry.Mode) {
        updateSnoozer.snooze(uniqueId: update.uniqueId, mode: mode,
                             currentModVersion: update.latestVersion,
                             currentGameVersion: smapiDiagnostics?.gameVersion)
        republishUpdatesFromCache()
    }

    /// R3 — réveille : retour immédiat dans l'ordre de consolidation.
    func unsnoozeUpdate(uniqueId: String) {
        updateSnoozer.clear(uniqueId: uniqueId)
        republishUpdatesFromCache()
    }

    /// R3 — motif affiché : échéance (horloge) ou condition (événement).
    func snoozeExpiryLabel(for update: NexusUpdateChecker.ModUpdate) -> String {
        guard let entry = updateSnoozer.entry(for: update.uniqueId) else { return "" }
        switch entry.mode {
        case .oneWeek:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return String(format: self.localization.L(L10n.Updates.snoozedUntilDate),
                          formatter.string(from: entry.expiresAt ?? entry.snoozedAt))
        case .untilModVersion:
            return self.localization.L(L10n.Updates.snoozedUntilModVersion)
        case .untilGameVersion:
            return self.localization.L(L10n.Updates.snoozedUntilGameVersion)
        }
    }

    /// Regroupe les mises à jour par pack. Ici la table « id Nexus effectif →
    /// pack » ; regroupement, choix et tri dans `NexusUpdateConsolidation`.
    private func consolidateUpdatesByPack(_ updates: [NexusUpdateChecker.ModUpdate]) -> [NexusUpdateChecker.ModUpdate] {
        // Par `UniqueID`, pas par id Nexus : quatre ids du parc sont partagés
        // entre un enfant de pack et un mod extérieur, absorbé à tort.
        var packNameByUniqueId: [String: String] = [:]
        for mod in mods where mod.isGroup {
            for child in mod.children ?? [] where !child.uniqueId.isEmpty {
                packNameByUniqueId[child.uniqueId] = mod.name
            }
        }
        return NexusUpdateConsolidation.consolidate(updates,
                                                    packNameByUniqueId: packNameByUniqueId)
    }

    /// Localized Nexus upload date for the update window.
    func formatUploadedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return String(format: localization.L(L10n.Updates.uploadedOn), formatter.string(from: date))
    }

    /// Effective category: user override (by `folderName`, pack headers too)
    /// > Nexus API category > pack's dominant child category > `nil`.
    func category(for mod: ModItem) -> NexusCategory? {
        trackCategoryCache()
        if let cached = categoryCache[mod.folderName] {
            return cached
        }
        let result = NexusCategoryResolver.resolveCategory(
            for: mod, customCategories: nexusCustomCategories,
            categoriesByNexusId: nexusCategories, customModIds: nexusCustomModIds)
        categoryCache[mod.folderName] = result
        return result
    }

    /// Inferred type key; a group uses its primary child.
    func inferredTagKey(for mod: ModItem) -> String {
        ModListScoping.inferredTagKey(for: mod)
    }

    /// User-pinned category id, or `nil` (automatic).
    func customCategoryId(for mod: ModItem) -> Int? {
        nexusCustomCategories[mod.folderName]
    }

    /// Pins a category on a mod. Pass `nil` to revert to the automatic category.
    func setCustomCategory(for mod: ModItem, categoryId: Int?) {
        nexusMetadata.setCustomCategory(categoryId, for: mod.folderName)
    }

    /// Effective Nexus id: user override, then manifest `UpdateKeys`.
    /// Façade provisoire (REFACTORING §6, cond. 1) — règle dans
    /// `NexusModIdentity`.
    func effectiveNexusModId(for mod: ModItem) -> String {
        NexusModIdentity.effectiveId(for: mod, customIds: nexusCustomModIds)
    }

    /// Like `effectiveNexusModId`, but a pack header falls back to its first
    /// child with an id (same as the link).
    /// Façade provisoire (§6, cond. 1) — règle dans `NexusModIdentity`.
    func resolvedNexusModId(for mod: ModItem) -> String {
        NexusModIdentity.resolvedId(for: mod, customIds: nexusCustomModIds)
    }

    /// Nexus URL from the effective id, else the manifest's `nexusUrl`; pack
    /// headers fall back to a child. Empty if none.
    /// Façade provisoire (§6, cond. 1) — règle dans `NexusModIdentity`.
    func nexusLink(for mod: ModItem) -> String {
        NexusModIdentity.link(for: mod, customIds: nexusCustomModIds)
    }

    /// Cached Nexus summary + picture, or `nil`; pack headers fall back to a
    /// child.
    /// Façade provisoire (§6, cond. 1) — règle dans `NexusModIdentity`.
    func modExtra(for mod: ModItem) -> NexusUpdateChecker.NexusModExtra? {
        NexusModIdentity.extra(for: mod, customIds: nexusCustomModIds, extras: nexusModExtras)
    }

    /// Nom du mod derrière un id Nexus : mod installé d'abord (nom de la
    /// liste), puis liste des mises à jour. `nil` sinon — mieux que d'inventer.
    func nexusModDisplayName(for modId: Int) -> String? {
        let wanted = String(modId)
        // Premier niveau d'abord : pour un composant, le pack a la page Nexus.
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

    /// Message qui nomme le mod si possible, sinon l'id ; l'appelant fournit
    /// les deux formats (substitutions différentes).
    private func nexusDownloadLogMessage(named: String, plain: String, modId: Int) -> String {
        guard let name = nexusModDisplayName(for: modId) else {
            return String(format: localization.L(plain), Int64(modId))
        }
        return String(format: localization.L(named), name, Int64(modId))
    }

    /// Installed mod (standalone or pack child) for a Nexus update, `nil` if
    /// orphaned. Deux passes : id Nexus d'abord (vérifié par smapi.io), puis
    /// `UniqueID` (mods hors Nexus) — sinon badge Activé/Désactivé faux.
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

    /// Display author; a pack shows the shared author or "multiple authors".
    func displayAuthor(for mod: ModItem) -> String {
        if mod.isGroup, let children = mod.children {
            let authors = Set(children.map { $0.author }
                                .filter { !$0.isEmpty && $0 != "Unknown" })
            if authors.count == 1 { return authors.first! }
            if authors.isEmpty { return "—" }
            return localization.L(L10n.Mods.packMultipleAuthors)
        }
        return mod.author
    }

    /// Display version; a pack shows the shared version or "—".
    func displayVersion(for mod: ModItem) -> String {
        if mod.isGroup, let children = mod.children {
            // A pack is one Nexus mod: prefer its latest Nexus version once known;
            // children's manifests can lag.
            if let v = nexusLatestVersion(for: mod), !v.isEmpty { return v }
            let versions = Set(children.map { $0.version }
                                .filter { !$0.isEmpty && $0 != "Unknown" })
            if versions.count == 1 { return versions.first! }
            return "—"
        }
        return mod.version
    }

    /// Latest cached Nexus version (pack: resolved id), `nil` before a check.
    func nexusLatestVersion(for mod: ModItem) -> String? {
        let id = resolvedNexusModId(for: mod)
        guard !id.isEmpty else { return nil }
        return nexusModExtras[id]?.version
    }

    /// Last Nexus update date, `nil` before a check.
    func nexusLastUpdated(for mod: ModItem) -> Date? {
        let id = resolvedNexusModId(for: mod)
        guard !id.isEmpty else { return nil }
        return nexusModExtras[id]?.uploadedTime
    }

    /// Install date (manifest mtime; pack: most recent child).
    func installedDate(for mod: ModItem) -> Date? { mod.effectiveInstallDate }

    /// Sets or clears (`nil`/empty) a user Nexus id override.
    func setCustomNexusModId(for mod: ModItem, modId: String?) {
        nexusMetadata.setCustomModId(modId, for: mod.folderName)
    }

    /// X103-C — garde l'archive Nexus si demandé. **Au succès de
    /// l'installation**, pas à la fermeture de la feuille (qui suit aussi
    /// annulation et échec). **S'abstient sur un pack** : une archive,
    /// plusieurs `UniqueID`.
    func keepNexusArchiveIfEnabled(archive: URL?, uniqueId: String?,
                                   version: String?, modName: String?) {
        guard UserDefaults.standard.bool(forKey: UDKey.keepNexusArchives),
              let archive, let uniqueId, let version, let modName,
              !uniqueId.isEmpty, !version.isEmpty else { return }
        do {
            try nexusArchiveStore.keep(archive: archive, uniqueId: uniqueId,
                                       version: version, modName: modName)
            // Rétention à chaque dépôt : sinon aucune borne avant l'écran Entretien.
            let purged = nexusArchiveStore.applyRetention()
            if purged > 0 {
                log("Archives Nexus : \(purged) ancienne(s) archive(s) retirée(s) par la rétention.",
                    level: .info)
            }
        } catch {
            // N'échoue jamais l'installation : le mod est posé.
            log("Archive Nexus non conservée : \(error.localizedDescription)", level: .warning)
        }
    }

    /// X103-C — réinstalle depuis l'archive conservée.
    /// ⚠️ **Une copie, jamais l'archive** : la feuille efface le fichier
    /// confié à sa fermeture (`discardDownloaded`) ; la copie va dans un
    /// dossier au préfixe du téléchargeur, nettoyé comme un téléchargement.
    func reinstallFromArchive(_ entry: NexusArchiveEntry) {
        let source = nexusArchiveStore.fileURL(of: entry)
        guard FileManager.default.fileExists(atPath: source.path) else {
            log("Archive introuvable pour \(entry.modName) — elle a dû être effacée hors de l'app.",
                level: .warning)
            refreshNexusArchives()
            return
        }
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(NexusFileDownload.downloadFolderPrefix)\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent(entry.fileName)
            try FileManager.default.copyItem(at: source, to: copy)
            pendingDownloadedZip = copy
        } catch {
            log("Réinstallation impossible : \(error.localizedDescription)", level: .error)
        }
    }

    /// Archives conservées ; rechargées par `refreshNexusArchives()` seulement.
    private(set) var nexusArchives: [NexusArchiveEntry] = []

    func refreshNexusArchives() {
        nexusArchives = nexusArchiveStore.entries()
    }

    func deleteNexusArchive(_ entry: NexusArchiveEntry) {
        nexusArchiveStore.remove(entry)
        refreshNexusArchives()
    }

    func purgeNexusArchives() {
        nexusArchiveStore.removeAll()
        refreshNexusArchives()
    }

    /// Retient l'id Nexus d'une installation venue de Nexus quand le manifeste
    /// n'en déclare pas (111 mods sur 966). **Avant**
    /// `reconcileManifestVersion`, qui consomme `pendingNexusSource`. Règle
    /// dans `NexusInstallIdRecording` (Core). Mono-dossier : un pack ferait de
    /// chaque composant un faux candidat.
    func recordNexusModId(_ modId: Int, installedFolderPaths: [String]) {
        // **Avant** les deux refus : la pastille de la vitrine n'attend pas le
        // scan.
        recentNexusInstalls.insert(modId)

        guard installedFolderPaths.count == 1,
              let folderPath = installedFolderPaths.first else { return }

        // Nom *logique* (sans point de tête), celui de la vérification.
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

        nexusMetadata.setCustomModId(id, for: folderName)
        log(String(format: localization.L(L10n.VM.nexusIdLearned), folderName, id))
    }

    /// Fetches one mod's metadata and updates `nexusCategories` /
    /// `nexusModExtras` at once (per-mod id editor). `completion` est
    /// `@MainActor @Sendable` (P5-L4) : reste synchrone sur main pour ses
    /// appelants.
    func fetchMetadata(forNexusModId modId: String,
                       completion: @escaping @MainActor @Sendable (NexusUpdateChecker.SingleFetchResult) -> Void) {
        NexusUpdateChecker.shared.fetchSingleMod(modId: modId) { [weak self] result in
            guard let self = self else { return }
            Task { @MainActor in
                if case .success(_, let catId, let extra, _) = result {
                    if let cid = catId, cid > 0 {
                        self.nexusCategories[modId] = cid
                    }
                    // `extra` already carries the latest version + upload date.
                    self.nexusModExtras[modId] = extra
                }
                completion(result)
            }
        }
    }

    /// Refuse un téléchargement concurrent (dépôt de traduction seulement ;
    /// les mods passent par la file). Sinon un second `nxm://` écrasait
    /// `pendingDownloadedZip` et perdait la première archive. Les deux verrous
    /// se rouvrent toujours : `pendingDownloadedZip` à la fermeture de la
    /// feuille, `isDownloadingFromNexus` dans `handleNexusDownloadResult`.
    private func rejectNexusDownloadIfBusy() -> Bool {
        guard NexusDownloadFlow.isBusy(isDownloading: isDownloadingFromNexus,
                                       hasPendingZip: pendingDownloadedZip != nil)
        else { return false }
        showModal(message: localization.L(L10n.VM.nexusDlBusy))
        return true
    }

    /// Entry point for `nxm://` deep links (free-user "Mod Manager Download").
    func handleNxmURL(_ url: URL) {
        guard let link = NxmLink.parse(url) else {
            showModal(message: localization.L(L10n.VM.nexusDlBadLink))
            return
        }
        enqueueOrStartNexusDownload(.init(modId: link.modId, fileId: link.fileId,
                                          game: link.gameDomain, key: link.key,
                                          expires: link.expires))
    }

    /// In-app download (Premium); fileId nil → main file resolved.
    func downloadModFromNexus(nexusId: Int) {
        enqueueOrStartNexusDownload(.init(modId: nexusId, fileId: nil,
                                          game: "stardewvalley", key: nil, expires: nil))
    }

    /// Point unique des demandes : démarre au repos, sinon en file
    /// (dédupliquée par `NexusDownloadQueue`).
    private func enqueueOrStartNexusDownload(_ entry: NexusDownloadQueue.Entry) {
        switch NexusDownloadFlow.route(
            entry,
            isBusy: NexusDownloadFlow.isBusy(isDownloading: isDownloadingFromNexus,
                                             hasPendingZip: pendingDownloadedZip != nil)) {
        case .enqueue(let entry):
            if downloadStore.enqueue(entry) {
                log(nexusDownloadLogMessage(named: L10n.VM.nexusDlQueuedNamed,
                                            plain: L10n.VM.nexusDlQueued, modId: entry.modId))
            }
        case .start(let entry):
            startNexusDownload(entry)
        }
    }

    /// Lance le téléchargement ; repos garanti par l'appelant.
    private func startNexusDownload(_ entry: NexusDownloadQueue.Entry) {
        downloadStore.beginDownload(modId: entry.modId)
        log(nexusDownloadLogMessage(named: L10n.VM.nexusDlStartingNamed,
                                    plain: L10n.VM.nexusDlStarting, modId: entry.modId))
        downloadStore.track(nexusDownloader.download(
            modId: entry.modId, fileId: entry.fileId, game: entry.game,
            key: entry.key, expires: entry.expires,
            onProgress: { [weak self] received, expected in
                self?.noteNexusDownloadProgress(received: received, expected: expected,
                                                modId: entry.modId)
            }) { [weak self] result in
            self?.handleNexusDownloadResult(result, modId: entry.modId)
        })
    }

    /// Démarre le suivant de la file au repos. Appelé aux trois bascules :
    /// fin sans feuille, fin de traduction, fermeture de la feuille.
    func drainQueuedNexusDownloads() {
        guard !NexusDownloadFlow.isBusy(isDownloading: isDownloadingFromNexus,
                                        hasPendingZip: pendingDownloadedZip != nil),
              let next = downloadStore.dequeue() else { return }
        startNexusDownload(next)
    }

    /// Shared completion for both download entry points: on main, clears
    /// progress; success stashes zip + source for the sheet, else a
    /// localized error.
    private func handleNexusDownloadResult(_ result: Result<NexusDownloadOutcome, NexusDownloadError>,
                                           modId: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.clearNexusDownloadState()
            switch NexusDownloadFlow.completion(for: result, modId: modId) {
            case .installable(let zip, let modId, let facts):
                self.pendingDownloadedZip = zip
                self.pendingNexusSource = NexusInstallSource(modId: modId, facts: facts)
                self.log(self.nexusDownloadLogMessage(named: L10n.VM.nexusDlCompletedNamed,
                                                      plain: L10n.VM.nexusDlCompleted,
                                                      modId: modId))
            case .cancelled:
                // Annulation volontaire : pas d'alerte, une ligne de journal.
                self.log(self.nexusDownloadLogMessage(named: L10n.VM.nexusDlCancelledNamed,
                                                      plain: L10n.VM.nexusDlCancelled,
                                                      modId: modId))
            case .failed(let message):
                // Bundle **vivant** : suit un changement de langue en session.
                let text = message.resolved { self.localization.L($0) }
                self.showModal(message: text)
                self.log(text, level: .warning)
            }
            // Fin sans feuille : la file reprend. Sur succès, le garde attend la
            // fermeture de la feuille.
            self.drainQueuedNexusDownloads()
        }
    }

    /// Progression, appelée **hors du fil principal** (délégué
    /// `URLSession`) : saut explicite. `expected == -1` (taille inconnue,
    /// fréquent sur CDN) : volume et débit seulement.
    nonisolated private func noteNexusDownloadProgress(received: Int64, expected: Int64,
                                                       modId: Int) {
        // Seule la référence traverse ; `nonisolated(unsafe)` sur la propriété.
        nonisolated(unsafe) let store = self.downloadStore
        DispatchQueue.main.async {
            store.noteProgress(received: received, expected: expected, modId: modId)
        }
    }

    /// Remet les quatre témoins au repos, en un seul endroit : un oubli
    /// condamnerait le bouton pour la session.
    @MainActor
    private func clearNexusDownloadState() {
        downloadStore.endDownload()
    }

    /// Annule le téléchargement en cours. Ne remet rien à zéro : le chemin
    /// d'échec de `URLSession` conclut (sinon repos pendant un transfert).
    @MainActor
    func cancelNexusDownload() {
        downloadStore.cancel()
    }

    /// Rend un `NexusDownloadError` avec le bundle **vivant**. Table des neuf
    /// cas dans `NexusDownloadFlow.message(for:)` (une copie, deux résolveurs).
    private func nexusDownloadMessage(_ error: NexusDownloadError) -> String {
        NexusDownloadFlow.message(for: error).resolved { localization.L($0) }
    }

    /// Install error via the live bundle (same reason as above). Exhaustive
    /// switches on purpose: a new case breaks the build instead of falling
    /// back to English. Embedded technical details stay in English.
    func installErrorMessage(_ error: Error) -> String {
        // **Détail technique au journal** (la modale ne le montre pas), ici et
        // non chez les sept appelants.
        log(Self.technicalInstallDetail(error), level: .error)

        if let error = error as? InstallError {
            switch error {
            case .extractionFailed:       return localization.L(L10n.ModInstall.errExtraction)
            case .unsafeContent:          return localization.L(L10n.ModInstall.errUnsafe)
            case .gameDirEmpty:           return localization.L(L10n.ModInstall.errGameDir)
            case .rarToolMissing:         return localization.L(L10n.ModInstall.rarToolMissing)
            case .backupFailed(let reason):  return String(format: localization.L(L10n.ModInstall.errBackup), reason)
            case .installFailed(let reason): return String(format: localization.L(L10n.ModInstall.errInstall), reason)
            }
        }
        if let error = error as? ModInstallBackupManager.InstallBackupError {
            switch error {
            case .gameDirEmpty:           return localization.L(L10n.ModInstall.errGameDir)
            case .modNotFound(let folder): return String(format: localization.L(L10n.ModInstall.errModMissing), folder)
            case .backupCreationFailed(let reason): return String(format: localization.L(L10n.ModInstall.errBackupCreate), reason)
            case .restoreFailed(let reason):        return String(format: localization.L(L10n.ModInstall.errRestore), reason)
            }
        }
        return error.localizedDescription
    }

    /// Journal : description **technique** anglaise, à recopier dans un
    /// rapport ; le message localisé va à l'utilisateur.
    private static func technicalInstallDetail(_ error: Error) -> String {
        let detail = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        return "Installation: \(detail)"
    }

    /// Éteint les lignes des mods que l'installation vient de poser, eux
    /// seuls ; sur main. Par `UniqueID` : l'id Nexus n'est pas unique (47
    /// partagés ; 8828 par trois mods sans rapport). `UniqueID` issus de
    /// `anchorInstalledMods` ; liste vide n'éteint rien.
    func dismissInstalledUpdates(uniqueIds: [String]) {
        guard !uniqueIds.isEmpty else { return }
        for uniqueId in uniqueIds {
            NexusUpdateChecker.shared.dismissUpdate(uniqueId: uniqueId)
        }
        // Recalculer : un pack garde sa ligne si d'autres composants ont une
        // mise à jour.
        republishUpdatesFromCache()
    }

    /// After a Nexus install, logs manifest vs Nexus version (authors forget
    /// to bump `Version`). Log only; no registry write since 2026-08-12. Must
    /// run BEFORE `dismissInstalledUpdates`. v1: single-mod installs.
    func reconcileManifestVersion(installedFolderPaths: [String]) {
        guard let source = pendingNexusSource else { return }
        // Consume once: a later install in the same sheet must not reconcile.
        pendingNexusSource = nil
        guard installedFolderPaths.count == 1, let folderPath = installedFolderPaths.first else {
            return  // pack / ambiguous → abstain (v1)
        }
        // The checker's entry for this mod; nothing flagged, nothing to do.
        let idStr = String(source.modId)
        guard let update = nexusUpdates.first(where: { $0.nexusModId == idStr }),
              !update.latestVersion.isEmpty else { return }

        let nexusVersion = update.latestVersion
        let folderName = (folderPath as NSString).lastPathComponent

        // Read the manifest's version to compare against the Nexus version.
        let manifestPath = (folderPath as NSString).appendingPathComponent("manifest.json")
        let manifestVersion = (try? String(contentsOfFile: manifestPath, encoding: .utf8))
            .flatMap { ManifestVersionPatcher.extractVersionValue(from: $0) }

        // Log: manifest correct, or lagging behind Nexus.
        if let mv = manifestVersion, NexusUpdateChecker.isNewer(nexusVersion, installed: mv) {
            log(String(format: localization.L(L10n.VM.manifestVersionFixed), folderName, mv, nexusVersion))
        } else if let mv = manifestVersion {
            log(String(format: localization.L(L10n.VM.manifestVersionSkipped), folderName, mv))
        }
    }

    // MARK: - Custom override persistence

    /// Ce que l'app affirme avoir installé, par `UniqueID`.
    let anchorStore = ModVersionAnchorStore()

    // MARK: - Traductions communautaires (A3-T3)

    // MARK: Hub de traduction FR — le store du domaine (cadrage §4,
    // domaine 6, tranche 1). Registre et règles en Core
    // (`InstalledTranslationRegistry`) ; le store publie.
    let translationHub = TranslationHubStore()
    /// C5-T1 — la recherche des traductions FR sur tout le parc (page « Traductions FR »).
    let translationSweep = FrenchTranslationSweepStore()

    /// Ce qui est posé sur quel mod — seule trace : la perdre rendrait toute
    /// désinstallation impossible.
    var installedTranslations: InstalledTranslationRegistry { translationHub.installed }
    /// Traductions FR trouvées par `folderName` : résultat de la dernière
    /// recherche, pas un cache.
    var translationHits: [String: [NexusModSearch.Hit]] { translationHub.hits }
    /// Résultats **déjà posés**, retirés des propositions mais gardés : ils
    /// portent la version plus récente et le rattachement.
    var translationInstalledHits: [String: [NexusModSearch.Hit]] { translationHub.installedHits }
    /// Mods en recherche. Un ensemble : un verrou unique rendait muet le clic
    /// sur un second mod.
    var searchingTranslations: Set<String> { translationHub.searching }
    /// Les mods dont une traduction s'installe ou se retire.
    var busyTranslations: Set<String> { translationHub.busy }

    /// La traduction posée sur ce mod, s'il y en a une.
    func translation(for mod: ModItem) -> InstalledTranslation? {
        installedTranslations.translation(forHost: mod.folderName)
    }

    /// Déclaration manuelle (A3-T6) : identité Nexus seule, sans fichiers.
    func declaredTranslation(for mod: ModItem) -> DeclaredTranslation? {
        installedTranslations.declaredTranslation(forHost: mod.folderName)
    }

    /// `true` si un `fr.json` (layouts A/B) existe sur disque **sans trace**
    /// (ni posé, ni déclaré) : bandeau « origine inconnue ». Un
    /// `fileExists` par appel, sans cache (voulu).
    func hasUndeclaredFrenchTranslation(for mod: ModItem) -> Bool {
        guard installedTranslations.translation(forHost: mod.folderName) == nil,
              installedTranslations.declaredTranslation(forHost: mod.folderName) == nil
        else { return false }
        return Self.modFolderHasFrenchTranslation(mod: mod, basePath: gameDir)
    }

    /// Test disque isolé (testable sans VM), par `physicalFolderName`. Règle
    /// dans `TranslationPresence` (Core), avec « la racine gagne ».
    static func modFolderHasFrenchTranslation(mod: ModItem, basePath: String) -> Bool {
        guard !basePath.isEmpty else { return false }
        let hostURL = URL(fileURLWithPath: basePath, isDirectory: true)
            .appendingPathComponent("Mods", isDirectory: true)
            .appendingPathComponent(mod.physicalFolderName, isDirectory: true)
        return TranslationPresence.hasFrench(inModDirectory: hostURL)
    }

    /// Déclaration manuelle (A3-T6) : bascule la fiche vers « déclarée », avec
    /// suivi de version. `nexusModId <= 0` rejeté en silence (aucun suivi
    /// possible).
    func declareTranslation(modId: Int, name: String, version: String?,
                            updatedAt: Date?, for mod: ModItem) {
        guard modId > 0, !name.isEmpty else { return }
        let decl = DeclaredTranslation(nexusModId: modId, nexusName: name,
                                       version: version, updatedAt: updatedAt,
                                       declaredAt: Date())
        translationHub.mutateInstalled { $0.declare(decl, forHost: mod.folderName) }
        if InstalledTranslationStore.save(installedTranslations) {
            log("Traduction déclarée sur \(mod.folderName) : \(name) (#\(modId))", level: .info)
        } else {
            log("Déclaration non enregistrée : la fiche affichera encore « origine inconnue »",
                level: .warning)
        }
    }

    /// Retire une déclaration. **Disque intact** : l'utilisateur a écrit,
    /// l'utilisateur enlève.
    func undeclareTranslation(for mod: ModItem) {
        var undeclared = false
        translationHub.mutateInstalled { undeclared = $0.undeclare(forHost: mod.folderName) }
        guard undeclared else { return }
        if InstalledTranslationStore.save(installedTranslations) {
            log("Déclaration de traduction retirée pour \(mod.folderName)", level: .info)
        } else {
            log("Retrait de la déclaration non enregistré", level: .warning)
        }
    }

    /// Version plus récente trouvée ? Sur les **dates Nexus**, jamais les
    /// numéros (souvent recopiés).
    func translationUpdateAvailable(for mod: ModItem) -> NexusModSearch.Hit? {
        guard let installed = translation(for: mod) else { return nil }
        return TranslationPresence.update(
            for: installed,
            amongAvailable: translationHits[mod.folderName] ?? [],
            andInstalled: translationInstalledHits[mod.folderName] ?? [])
    }

    /// Cherche sur Nexus la fiche d'un mod qui n'en déclare aucune, sans tag.
    /// ⚠️ **Deux fois sur trois, rien** (55/83 introuvables) : la vue doit le
    /// dire.
    func searchNexusIdentity(for mod: ModItem) {
        guard !translationHub.isIdentitySearching(mod.folderName) else { return }
        translationHub.setIdentitySearching(true, for: mod.folderName)
        NexusSearchClient.search(name: mod.name) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.translationHub.setIdentitySearching(false, for: mod.folderName)
                switch result {
                case .success(let page):
                    self.translationHub.setIdentitySearch(
                        IdentitySearch(
                            candidates: NexusModSearch.identityCandidates(among: page.hits,
                                                                          modName: mod.name,
                                                                          modAuthor: mod.author),
                            received: page.hits.count,
                            serverTotal: page.totalCount),
                        for: mod.folderName)
                case .failure(let error):
                    // Panne ≠ absence : rien plutôt que « aucun résultat ».
                    self.translationHub.setIdentitySearch(nil, for: mod.folderName)
                    self.log("Recherche de la fiche Nexus : \(error)", level: .warning)
                    self.showModal(message: self.localization.L(L10n.Mods.translationSearchFailed))
                }
            }
        }
    }

    /// Referme les propositions de fiche Nexus d'un mod.
    func dismissIdentityResults(for mod: ModItem) {
        translationHub.setIdentitySearch(nil, for: mod.folderName)
    }

    /// Adopte la fiche désignée via `setCustomNexusModId` (saisie par clic),
    /// referme la liste, et recharge `loadModDetail` : sinon la fiche liée
    /// reste muette.
    func adoptNexusIdentity(_ candidate: NexusModSearch.IdentityCandidate, for mod: ModItem) {
        setCustomNexusModId(for: mod, modId: String(candidate.hit.modId))
        dismissIdentityResults(for: mod)
        fetchMetadata(forNexusModId: String(candidate.hit.modId)) { _ in }
        loadModDetail(for: mod)
        log(String(format: localization.L(L10n.VM.nexusIdLearned), mod.folderName, String(candidate.hit.modId)))
    }

    /// Referme les propositions. **Seulement l'affiché** :
    /// `translationInstalledHits` porte la pastille « plus récente ».
    func dismissTranslationResults(for mod: ModItem) {
        translationHub.setHits(nil, for: mod.folderName)
    }

    /// Referme les suppléments ; les greffes du registre restent (disque).
    func dismissSupplementResults(for mod: ModItem) {
        translationHub.setSupplementSearch(nil, for: mod.folderName)
    }

    /// Ids Nexus du parc, pour reconnaître un supplément installé comme mod.
    /// À la demande : usage rare.
    private func installedNexusIds() -> Set<Int> {
        Set(allInstalledMods().compactMap { Int(resolvedNexusModId(for: $0)) })
            .union(recentNexusInstalls)
    }

    /// Retire la traduction déjà en place : par id Nexus, sinon par nom (cas
    /// courant sur compte gratuit).
    private func withoutInstalledTranslation(_ hits: [NexusModSearch.Hit],
                                             for mod: ModItem) -> [NexusModSearch.Hit] {
        guard let installed = translation(for: mod) else {
            translationHub.setInstalledHits([], for: mod.folderName)
            return hits
        }
        // **Retirée, pas jetée** : cette moitié porte la mise à jour et le seul
        // bon choix de rattachement.
        let split = NexusModSearch.partition(
            hits,
            installedNexusIds: installed.nexusModId > 0 ? [installed.nexusModId] : [],
            installedTitles: [installed.nexusName])
        translationHub.setInstalledHits(split.installed, for: mod.folderName)
        // Rattacher sans demander si titre et id du nom de fichier concordent.
        adoptConfirmedNexusId(for: installed, among: split.installed,
                              isTranslation: true, host: mod)
        return split.available
    }

    /// Rattache un dépôt à sa fiche **sans doute possible** : id dans le nom
    /// du fichier (14/15) + titre concordant, sinon rien. Date = celle du
    /// dépôt (celle du résultat déclarerait à jour).
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
        translationHub.mutateInstalled {
            if isTranslation {
                $0.record(linked)
            } else {
                $0.forgetAddon(entry)
                $0.recordAddon(linked)
            }
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

    /// Greffe plus récente ? Dates Nexus, et seulement avec un id (voir
    /// `linkToNexus`).
    func addonUpdateAvailable(_ addon: InstalledTranslation,
                              for mod: ModItem) -> NexusModSearch.Hit? {
        let search = translationHub.supplementSearches[mod.folderName]
        return TranslationPresence.update(for: addon,
                                          amongAvailable: search?.hits ?? [],
                                          andInstalled: search?.alreadyInstalled ?? [])
    }

    /// Rattache une traduction ou greffe posée à la main à sa page Nexus :
    /// **sans id, aucun suivi de mise à jour** (compte gratuit).
    func linkToNexus(_ entry: InstalledTranslation, hit: NexusModSearch.Hit,
                     isTranslation: Bool, for mod: ModItem) {
        // **Date du dépôt, pas du résultat** : `hit.updatedAt` comparerait la
        // date Nexus à elle-même.
        let linked = InstalledTranslation(
            hostFolderName: entry.hostFolderName, nexusModId: hit.modId, nexusName: hit.name,
            version: hit.version, updatedAt: entry.installedAt, installedAt: entry.installedAt,
            files: entry.files, replacedFiles: entry.replacedFiles)
        translationHub.mutateInstalled {
            if isTranslation {
                $0.record(linked)
            } else {
                $0.forgetAddon(entry)
                $0.recordAddon(linked)
            }
        }
        if !InstalledTranslationStore.save(installedTranslations) {
            showModal(message: localization.L(L10n.Mods.translationNotTracked))
        }
        // Sans repartir sur le réseau. Le résultat **change de moitié** :
        // oublié, sa mise à jour disparaîtrait.
        if isTranslation {
            translationHub.setHits(
                (translationHits[mod.folderName] ?? []).filter { $0.modId != hit.modId },
                for: mod.folderName)
            translationHub.setInstalledHits(
                (translationInstalledHits[mod.folderName] ?? []) + [hit],
                for: mod.folderName)
        } else if let previous = translationHub.supplementSearches[mod.folderName] {
            translationHub.setSupplementSearch(
                SupplementSearch(
                    hits: previous.hits.filter { $0.modId != hit.modId },
                    alreadyInstalled: previous.alreadyInstalled + [hit],
                    received: previous.received,
                    serverTotal: previous.serverTotal),
                for: mod.folderName)
        }
    }

    /// Retire une greffe posée sur ce mod, et **rend** ce qu'elle avait recouvert.
    func removeAddon(_ addon: InstalledTranslation, from mod: ModItem) {
        guard !translationHub.isBusy(mod.folderName) else { return }
        translationHub.setBusy(true, for: mod.folderName)
        defer { translationHub.setBusy(false, for: mod.folderName) }
        let hostPath = URL(fileURLWithPath: gameDir)
            .appendingPathComponent("Mods")
            .appendingPathComponent(mod.physicalFolderName)
        let failures = ManifestlessInstaller.uninstall(addon, hostPath: hostPath)
        if failures.isEmpty {
            translationHub.mutateInstalled { $0.forgetAddon(addon) }
            if !InstalledTranslationStore.save(installedTranslations) {
                showModal(message: localization.L(L10n.Mods.translationRemoveNotTracked))
            }
        } else {
            // Retrait partiel : la ligne reste, avec les fichiers restants.
            showModal(message: String(format: localization.L(L10n.Mods.translationRemovePartial),
                                      failures.joined(separator: ", ")))
        }
        // Greffe mixte : couverture FR périmée. Sur main (bouton).
        MainActor.assumeIsolated { invalidateFrenchCoverage(for: mod.folderName) }
        refresh()
    }

    /// Cherche ce qui se greffe sur ce mod (même requête sans tag, `WILDCARD`).
    /// Tri au retour : `NexusModSearch.supplements(among:excluding:)`.
    func searchSupplements(for mod: ModItem) {
        guard !translationHub.isSupplementsSearching(mod.folderName) else { return }
        translationHub.setSupplementsSearching(true, for: mod.folderName)
        let host = Int(mod.nexusModId)
        NexusSearchClient.search(name: mod.name) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.translationHub.setSupplementsSearching(false, for: mod.folderName)
                switch result {
                case .success(let page):
                    let found = NexusModSearch.supplements(among: page.hits, excluding: host,
                                                           hostName: mod.name)
                    // Déjà là : **montré** à part, pas proposé.
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
                    self.translationHub.setSupplementSearch(
                        SupplementSearch(hits: split.available,
                                         alreadyInstalled: split.installed,
                                         received: page.hits.count,
                                         serverTotal: page.totalCount),
                        for: mod.folderName)
                case .failure(let error):
                    // Une panne n'est pas une absence, comme pour les traductions.
                    self.translationHub.setSupplementSearch(nil, for: mod.folderName)
                    self.log("Recherche de suppléments : \(error)", level: .warning)
                    self.showModal(message: self.localization.L(L10n.Mods.translationSearchFailed))
                }
            }
        }
    }

    /// Cherche les traductions FR d'un mod — chemin partagé avec « Traductions
    /// FR » (`FrenchTranslationLookup` : « requis par », puis nom).
    func searchTranslations(for mod: ModItem) {
        guard !translationHub.isSearching(mod.folderName) else { return }
        translationHub.setSearching(true, for: mod.folderName)
        let host = Int(resolvedNexusModId(for: mod)).flatMap { $0 > 0 ? $0 : nil }
        Task { @MainActor [weak self] in
            let result = await FrenchTranslationLookup.find(name: mod.name, hostModId: host)
            guard let self else { return }
            self.translationHub.setSearching(false, for: mod.folderName)
            switch result {
            case .success(let entry):
                // La traduction posée a sa propre ligne.
                self.translationHub.setHits(self.withoutInstalledTranslation(entry.hits, for: mod),
                                            for: mod.folderName)
            case .failure(let error):
                // Panne ≠ absence : `[]` dirait « aucune traduction ».
                self.translationHub.setHits(nil, for: mod.folderName)
                self.log("Recherche de traduction : \(error)", level: .warning)
                self.showModal(message: self.localization.L(L10n.Mods.translationSearchFailed))
            }
        }
    }

    /// Télécharge une traduction, la dépose **dans** un mod existant (fichiers
    /// recouverts mis à l'abri) et l'enregistre.
    func installTranslation(_ hit: NexusModSearch.Hit, into mod: ModItem) {
        guard !translationHub.isBusy(mod.folderName) else { return }
        // Un seul téléchargement à la fois (`pendingDownloadedZip`).
        if rejectNexusDownloadIfBusy() { return }
        translationHub.setBusy(true, for: mod.folderName)
        downloadStore.beginDownload(modId: hit.modId)
        downloadStore.track(nexusDownloader.download(
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
                case .success(let outcome):
                    // Pas de faits X9 : seule l'archive compte.
                    self.depositTranslation(archive: outcome.zip, hit: hit, into: mod)
                case .failure(.cancelled):
                    // Geste volontaire : rien à annoncer.
                    self.translationHub.setBusy(false, for: mod.folderName)
                case .failure(let error):
                    self.translationHub.setBusy(false, for: mod.folderName)
                    // Sans lien direct, le message nomme la voie manuelle.
                    var hint = ""
                    if case .noDownloadLink = error {
                        hint = "\n\n" + self.localization.L(L10n.Mods.translationManualHint)
                    }
                    self.showModal(message: self.nexusDownloadMessage(error) + hint)
                }
                // Créneau libéré : la file reprend.
                self.drainQueuedNexusDownloads()
            }
        })
    }

    private func depositTranslation(archive: URL, hit: NexusModSearch.Hit, into mod: ModItem) {
        defer { translationHub.setBusy(false, for: mod.folderName) }
        // `discardDownloaded` emporte le dossier `StarHubFR-download-*` entier
        // (X104 : un dossier vide restait par traduction).
        defer { NexusFileDownload.discardDownloaded(at: archive) }
        let installer = ModZipInstaller()
        do {
            let extracted = try installer.extractToTemp(zipUrl: archive)
            defer { try? FileManager.default.removeItem(at: extracted) }
            let paths = ManifestlessArchive.paths(under: extracted)
            let outcome = ManifestlessArchive.classify(
                paths: paths, installedFolderNames: [mod.folderName])
            // L'hôte est **ce** mod, quel que soit le nom du dossier de l'archive.
            let entries: [ManifestlessArchive.Entry]
            switch outcome {
            case .plan(let plan): entries = plan.entries
            case .needsHost(_, _, let found): entries = found
            case .unrecognised:
                showModal(message: localization.L(L10n.Mods.translationUnrecognised))
                return
            }
            let plan = ManifestlessArchive.Plan(hostFolderName: mod.folderName,
                                                kind: .translation, entries: entries)
            let result = depositIntoMod(plan: plan, extractedRoot: extracted, host: mod,
                                        sourceName: hit.name, nexus: hit)
            if let message = result.message { showModal(message: message) }
            guard result.outcome != nil else { return }
            log(String(format: localization.L(L10n.Mods.translationInstalled), hit.name, mod.name))
            refresh()
        } catch {
            showModal(message: localization.L(L10n.Mods.translationInstallFailed))
            log("Dépôt de traduction : \(error)", level: .error)
        }
    }

    /// Dépose un plan dans un mod et inscrit au registre ce qui devra se
    /// retirer. **Ordre** : la traduction en place n'est rendue qu'après le
    /// plan établi, mais elle doit l'être (son entrée est le seul pointeur
    /// vers les originaux).
    /// - Parameters:
    ///   - sourceName: titre Nexus, ou nom de l'archive.
    ///   - nexus: la fiche ; sans elle, retrait possible mais aucun suivi.
    ///   - downloadedModId: id de la page d'un téléchargement de l'app —
    ///     filet si le nom du fichier ne le porte pas.
    /// - Returns: ce qui a été écrit (`nil` sinon) et un message éventuel.
    func depositIntoMod(plan proposed: ManifestlessArchive.Plan, extractedRoot: URL, host: ModItem,
                        sourceName: String, nexus: NexusModSearch.Hit?,
                        downloadedModId: Int? = nil)
        -> (outcome: ManifestlessInstaller.Outcome?, message: String?) {
        // Refus dit selon ce qu'on déposait (traduction ou lot).
        let failed = proposed.kind == .translation
            ? localization.L(L10n.Mods.translationInstallFailed) : localization.L(L10n.ModInstall.depositFailed)
        guard let backupRoot = InstalledTranslationStore.backupRoot else {
            return (nil, failed)
        }
        // Nom **physique** (mod en pause).
        let hostPath = URL(fileURLWithPath: gameDir)
            .appendingPathComponent("Mods")
            .appendingPathComponent(host.physicalFolderName)
        // Le rangement du mod hôte décide où va un `fr.json` à plat.
        let plan = ManifestlessArchive.adaptingLocaleLayout(proposed, to: .read(modDirectory: hostPath))

        // On rend d'abord ce qu'on remplace : une greffe écarte la greffe de même
        // identité, pas la traduction.

        // Id lu dans le nom du fichier (6/10 sur le parc) pour un
        // glisser-déposer ; le navigateur intégré garde ce que Nexus sait.
        let now = Date()
        // **Une seule lecture de l'identité**, pour la sonde et le registre. Règle
        // dans `DepositIdentity` (Core, 13 tests).
        let identity = DepositIdentity.resolve(nexus: nexus, sourceName: sourceName,
                                               downloadedModId: downloadedModId, at: now)
        let entry = identity.entry(hostFolderName: host.folderName, sourceName: sourceName,
                                   installedAt: now, files: [], replacedFiles: [:])
        let incumbent = DepositIdentity.incumbent(in: installedTranslations, kind: plan.kind,
                                                  host: host.folderName, probe: entry)
        if let incumbent {
            let failures = ManifestlessInstaller.uninstall(incumbent, hostPath: hostPath)
            guard failures.isEmpty else {
                return (nil, String(format: localization.L(L10n.Mods.translationRemovePartial),
                                    failures.joined(separator: ", ")))
            }
            translationHub.mutateInstalled {
                if plan.kind == .translation {
                    $0.forget(host: host.folderName)
                } else {
                    $0.forgetAddon(incumbent)
                }
            }
        }

        let written: ManifestlessInstaller.Outcome
        do {
            written = try ManifestlessInstaller.install(plan: plan, extractedRoot: extractedRoot,
                                                        hostPath: hostPath, backupRoot: backupRoot)
        } catch ManifestlessInstaller.InstallError
                    .rollBackIncomplete(let reason, let leftBehind) {
            // Nommer les fichiers restés : sinon le mod paraîtrait intact.
            log("Dépôt sans manifeste, annulation incomplète : \(reason)", level: .error)
            return (nil, String(format: localization.L(L10n.ModInstall.depositRollbackIncomplete),
                                leftBehind.joined(separator: ", ")))
        } catch {
            log("Dépôt sans manifeste : \(error)", level: .error)
            return (nil, failed)
        }

        // Couverture FR périmée dans tous les cas, invalidée ici (sinon « À
        // traduire » après dépôt depuis la feuille). Synchrone via
        // `assumeIsolated`, comme `deleteMod` : un `Task` rouvrirait la course
        // avec le rescan.
        MainActor.assumeIsolated { invalidateFrenchCoverage(for: host.folderName) }

        // Les greffes entrent au registre et se retirent comme une traduction.
        // Même provenance que la sonde `entry` : une seule identité.
        let recorded = identity.entry(hostFolderName: host.folderName, sourceName: sourceName,
                                      installedAt: now, files: written.written,
                                      replacedFiles: written.replaced)
        translationHub.mutateInstalled {
            if plan.kind == .translation {
                $0.record(recorded)
            } else {
                $0.recordAddon(recorded)
            }
        }
        guard InstalledTranslationStore.save(installedTranslations) else {
            // Fichiers posés mais non retenus : le dire (retrait impossible).
            return (written, localization.L(L10n.Mods.translationNotTracked))
        }
        return (written, nil)
    }

    /// Retire la traduction du mod et **rend** ce qu'elle recouvrait.
    func removeTranslation(from mod: ModItem) {
        guard !translationHub.isBusy(mod.folderName),
              let translation = translation(for: mod) else { return }
        translationHub.setBusy(true, for: mod.folderName)
        defer { translationHub.setBusy(false, for: mod.folderName) }
        let hostPath = URL(fileURLWithPath: gameDir)
            .appendingPathComponent("Mods")
            .appendingPathComponent(mod.physicalFolderName)
        let failures = ManifestlessInstaller.uninstall(translation, hostPath: hostPath)
        if failures.isEmpty {
            translationHub.mutateInstalled { $0.forget(host: mod.folderName) }
            if !InstalledTranslationStore.save(installedTranslations) {
                showModal(message: localization.L(L10n.Mods.translationRemoveNotTracked))
            }
        } else {
            // **Retrait partiel : l'entrée reste** (fichiers restants, originaux).
            showModal(message: String(format: localization.L(L10n.Mods.translationRemovePartial),
                                      failures.joined(separator: ", ")))
        }
        // Fichiers bougés : remesurer dans les deux cas. Sur main.
        MainActor.assumeIsolated { invalidateFrenchCoverage(for: mod.folderName) }
        refresh()
    }

    /// Pour chaque nom de fichier **à la racine** d'un mod, ses propriétaires :
    /// reconnaît un remplacement de config (`bagconfig.json` → `ItemBags`).
    /// Parc : 76/91 noms JSON n'ont qu'un propriétaire, `config.json` 544 —
    /// seule l'unicité autorise à conclure. À la demande (parcours disque).
    func rootFileOwners() -> [String: [String]] {
        let root = URL(fileURLWithPath: gameDir).appendingPathComponent("Mods")
        var owners: [String: [String]] = [:]
        var unreadable = 0
        for mod in allInstalledMods() {
            let folder = root.appendingPathComponent(mod.physicalFolderName)
            // Racine seulement, pas de parcours récursif.
            do {
                for name in try FileManager.default.contentsOfDirectory(atPath: folder.path)
                where !name.hasPrefix(".") {
                    owners[name.lowercased(), default: []].append(mod.folderName)
                }
            } catch {
                // Dossier illisible : compté et dit une fois.
                unreadable += 1
            }
        }
        if unreadable > 0 {
            log("Reconnaissance des remplacements : \(unreadable) dossier(s) de mod illisible(s), "
                + "un fichier qui les visait ne sera pas reconnu", level: .warning)
        }
        return owners.mapValues { Array(Set($0)).sorted() }
    }


    // MARK: - Découverte (axe G)

    /// Carte de la vitrine en Core (`DiscoveryScoping.Row`) ; l'alias garde
    /// les vues en place.
    typealias DiscoveryRow = DiscoveryScoping.Row

    // MARK: Le store du domaine (cadrage §4, domaine 3). Il porte l'état de
    // la vitrine ; le réseau, le cache disque et le calcul des cartes restent
    // ici — `discoveryRows` lit `mods`, donc le domaine Scan.
    private let discoveryStore = DiscoveryStore()

    var discovery: [ModCatalog.SectionKind: ModCatalog.SectionState] { discoveryStore.sections }
    var discoveryLoading: Bool { discoveryStore.loading }
    var discoverySearch: DiscoverySearchResult? { discoveryStore.search }
    var discoveryDetail: NexusModSearch.Detail? { discoveryStore.detail }
    var discoveryDetailState: DiscoveryDetailState { discoveryStore.detailState }
    var lastDiscoveryError: NexusSearchError? { discoveryStore.lastError }
    var discoveryCategory: NexusCategory? { discoveryStore.category }

    /// Réponse de recherche encore attendue ? Orchestration réseau, reste au VM.
    private var discoveryEpoch = RequestEpoch()
    /// Même rôle pour la fiche (fermée et rouverte plus vite qu'une requête).
    private var discoveryDetailEpoch = RequestEpoch()

    /// Mods installés depuis Nexus **cette session**, par id de page : la
    /// pastille « installé » s'allume sans attendre le scan (plusieurs
    /// secondes). Non persisté.
    private(set) var recentNexusInstalls: Set<Int> = []

    /// Cache sur disque : `~/Library/Caches/StarHubFR/discovery/` (spec §6).
    private let discoveryCatalog: ModCatalog = {
        let dir = URL.cachesDirectory.appendingPathComponent("StarHubFR/discovery",
                                                             isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ModCatalog(
            load: { key in try? Data(contentsOf: dir.appendingPathComponent("\(key).json")) },
            save: { key, data in try? data.write(to: dir.appendingPathComponent("\(key).json")) })
    }()

    /// Restreint la vitrine à une catégorie, ou la rouvre ; un cache par
    /// catégorie. Ne filtre **pas** la recherche par nom (vide inexplicable).
    func setDiscoveryCategory(_ category: NexusCategory?) {
        guard discoveryStore.setCategory(category) else { return }
        loadDiscovery()
        // Recherche affichée refaite sous la nouvelle catégorie.
        if let search = discoverySearch { searchDiscovery(name: search.term) }
    }

    /// Charge les trois sections : cache d'abord, une requête par section
    /// périmée ou absente (spec §5.3). `force` (bouton) redemande tout.
    func loadDiscovery(force: Bool = false) {
        // Remet la panne précédente à zéro : sinon bandeau d'erreur permanent.
        discoveryStore.startLoad()
        for kind in ModCatalog.SectionKind.allCases {
            let state = discoveryCatalog.state(kind, category: discoveryCategory?.id)
            discoveryStore.setSection(kind, to: state)
            switch state {
            case .fresh where !force: continue
            default: fetchDiscoverySection(kind)
            }
        }
    }

    private func fetchDiscoverySection(_ kind: ModCatalog.SectionKind) {
        discoveryStore.beginFetch()
        // Catégorie retenue : une réponse tardive va dans **son** cache sans
        // s'afficher.
        let category = discoveryCategory
        NexusSearchClient.listing(sort: kind.defaultSort, tag: kind.defaultTag,
                                  category: category?.englishName) { [weak self] result in
                                      Task { @MainActor in
                guard let self else { return }
                self.discoveryStore.finishFetch()
                let stillWanted = self.discoveryStore.isStillWanted(category: category)
                switch result {
                case .success(let page):
                    self.discoveryCatalog.record(kind, category: category?.id, page: page)
                    // Relu du cache : page dédoublonnée.
                    guard stillWanted else { return }
                    self.discoveryStore.setSection(kind,
                                                   to: self.discoveryCatalog.state(kind,
                                                                                   category: category?.id))
                case .failure(let error):
                    guard stillWanted else { return }
                    // Panne toujours dite (spec §8) : sinon des lignes de la veille mentent.
                    self.discoveryStore.recordFailure(error)
                    // Stale gardé pendant la panne (spec §6), le bandeau suffit.
                    if case .stale = self.discovery[kind] ?? .empty(.neverLoaded) { return }
                    self.discoveryStore.setSection(kind, to: .empty(.failed))
                }
                                      }
        }
    }

    /// Cartes d'une liste : adulte exclu (spec §8), « installé » par id **et**
    /// titre (A3-T5). `francophoneOnly` pour les **sections** seulement : une
    /// recherche rend ce qu'on a tapé.
    private func discoveryRows(in hits: [NexusModSearch.Hit],
                               hidingInstalled: Bool,
                               francophoneOnly: Bool) -> [DiscoveryRow] {
        // Écarts dans `DiscoveryScoping` (Core, 14 tests) ; ici les deux
        // ensembles que seul le VM connaît.
        DiscoveryScoping.rows(from: hits,
                              installedNexusIds: installedNexusIds(),
                              installedTitles: Set(mods.map(\.name)),
                              hidingInstalled: hidingInstalled,
                              francophoneOnly: francophoneOnly)
    }

    /// Cartes visibles, mods **reçus** et total serveur. « x affichés sur y
    /// chargés » (spec §7.1) ; le total dit seulement s'il reste à demander.
    func discoveryRows(for kind: ModCatalog.SectionKind,
                       hidingInstalled: Bool)
    -> (rows: [DiscoveryRow], shown: Int, loaded: Int, total: Int) {
        guard let page = discovery[kind]?.page else { return ([], 0, 0, 0) }
        let rows = discoveryRows(in: page.hits, hidingInstalled: hidingInstalled,
                                 francophoneOnly: true)
        return (rows, rows.count, page.hits.count, page.totalCount)
    }

    /// « Voir plus » : offset = mods **reçus**, pas affichés (sinon redemande
    /// sans fin ce que les filtres écartent).
    func loadMoreDiscovery(_ kind: ModCatalog.SectionKind) {
        guard let page = discovery[kind]?.page,
              DiscoveryScoping.hasMore(received: page.hits.count,
                                       serverTotal: page.totalCount) else { return }
        let category = discoveryCategory
        discoveryStore.beginFetch()
        NexusSearchClient.listing(sort: kind.defaultSort, tag: kind.defaultTag,
                                  category: category?.englishName,
                                  offset: DiscoveryScoping.nextOffset(received: page.hits.count)) { [weak self] result in
                                      Task { @MainActor in
                guard let self else { return }
                self.discoveryStore.finishFetch()
                guard self.discoveryStore.isStillWanted(category: category) else { return }
                switch result {
                case .success(let next):
                    self.discoveryCatalog.append(kind, category: category?.id, page: next)
                    self.discoveryStore.setSection(kind,
                                                   to: self.discoveryCatalog.state(kind,
                                                                                   category: category?.id))
                case .failure(let error):
                    // Bande déjà là inchangée ; le bandeau dit pourquoi.
                    self.discoveryStore.recordFailure(error)
                }
                                      }
        }
    }

    /// Recherche par nom : montre tout, « installé » compris (spec §7.1).
    func searchDiscovery(name: String) {
        let term = NexusModSearch.searchTerm(for: name)
        guard !term.isEmpty else {
            // Champ vidé : périmer l'en-vol, sinon la liste revient.
            discoveryEpoch.abandonAll()
            discoveryStore.setSearch(nil)
            return
        }
        let token = discoveryEpoch.open()
        NexusSearchClient.search(name: name,
                                 category: discoveryCategory?.englishName) { [weak self] result in
                                     Task { @MainActor in
                guard let self, self.discoveryEpoch.isCurrent(token) else { return }
                switch result {
                case .success(let page):
                    self.discoveryStore.clearFailure()
                    self.discoveryStore.setSearch(DiscoverySearchResult(
                        rows: self.discoveryRows(in: page.hits, hidingInstalled: false,
                                                 francophoneOnly: false),
                        totalCount: page.totalCount,
                        term: name,
                        loaded: page.hits.count))
                case .failure(let error):
                    self.discoveryStore.recordFailure(error)
                    self.discoveryStore.setSearch(nil)
                }
                                     }
        }
    }

    /// Tranche suivante, sur le terme retenu au résultat (pas le champ).
    func loadMoreDiscoverySearch() {
        guard let current = discoverySearch, current.loaded < current.totalCount else { return }
        // Jeton courant : la suite prolonge la recherche.
        let token = discoveryEpoch.currentToken
        NexusSearchClient.search(name: current.term,
                                 category: discoveryCategory?.englishName,
                                 offset: current.loaded) { [weak self] result in
                                     Task { @MainActor in
                guard let self, self.discoveryEpoch.isCurrent(token) else { return }
                // La liste a pu grandir par ailleurs pendant la requête.
                guard let now = self.discoverySearch, now.term == current.term,
                      now.loaded == current.loaded else { return }
                switch result {
                case .success(let page):
                    var seen = Set(now.rows.map(\.hit.modId))
                    let fresh = page.hits.filter { seen.insert($0.modId).inserted }
                    self.discoveryStore.clearFailure()
                    self.discoveryStore.setSearch(DiscoverySearchResult(
                        rows: now.rows + self.discoveryRows(in: fresh, hidingInstalled: false,
                                                            francophoneOnly: false),
                        totalCount: page.totalCount,
                        term: current.term,
                        loaded: now.loaded + page.hits.count))
                case .failure(let error):
                    // Les résultats déjà là restent : seule la suite manque.
                    self.discoveryStore.recordFailure(error)
                }
                                     }
        }
    }

    /// Quitte les résultats ; les sections reviennent.
    func clearDiscoverySearch() {
        // Périmer d'abord, sinon une réponse repeuple la liste fermée.
        discoveryEpoch.abandonAll()
        discoveryStore.setSearch(nil)
    }

    /// Fiche : le cache 24 h d'abord, le réseau ensuite (spec §5.3).
    func loadDiscoveryDetail(modId: Int) {
        discoveryStore.setDetail(discoveryDetail, state: .loading)
        if let cached = discoveryCatalog.detail(for: modId) {
            discoveryStore.setDetail(cached, state: .loaded)
            return
        }
        let token = discoveryDetailEpoch.open()
        NexusSearchClient.detail(modId: modId) { [weak self] result in
            Task { @MainActor in
                // Sans jeton, la réponse d'une fiche fermée s'affichait dans la suivante.
                guard let self, self.discoveryDetailEpoch.isCurrent(token) else { return }
                switch result {
                case .success(let detail):
                    self.discoveryCatalog.recordDetail(detail)
                    self.discoveryStore.setDetail(detail, state: .loaded)
                case .failure:
                    self.discoveryStore.setDetail(nil, state: .failed)
                }
            }
        }
    }

    func closeDiscoveryDetail() {
        discoveryDetailEpoch.abandonAll()
        discoveryStore.setDetail(nil, state: .idle)
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

    // MARK: - Mise à jour de l'app (release GitHub du fork)

    /// Alerte à présenter (`nil` = rien) : lancement seulement, tag non
    /// acquitté.
    private(set) var availableAppRelease: GitHubRelease?
    /// Dernière release connue (À propos), indépendante de l'acquittement.
    private(set) var lastKnownRelease: GitHubRelease?
    private(set) var releaseCheckInFlight = false
    /// Échec dit **seulement** au check manuel.
    private(set) var releaseCheckFailedMessage: String?

    private static let appReleaseURL = URL(string:
        "https://api.github.com/repos/mrbabilo/StarHubFR/releases/latest")!

    func checkForAppRelease(bypassThrottle: Bool = false) {
        guard !releaseCheckInFlight else { return }
        let lastChecked = UserDefaults.standard.object(forKey: UDKey.frReleaseLastCheckedAt) as? Date
        guard bypassThrottle
                || UpdateCheckPolicy.shouldAutoCheck(lastSuccess: lastChecked,
                                                     now: Date(),
                                                     ttl: AppReleasePolicy.checkTTL) else { return }
        releaseCheckInFlight = true
        if bypassThrottle { releaseCheckFailedMessage = nil }
        Task { [weak self] in
            await self?.performReleaseCheck(lastChecked: lastChecked,
                                            bypassThrottle: bypassThrottle)
        }
    }

    /// `@MainActor` explicite : une `func async` non isolée tournerait hors
    /// main.
    @MainActor
    private func performReleaseCheck(lastChecked: Date?, bypassThrottle: Bool) async {
        // Le drapeau retombe par **tous** les chemins : sinon « Vérifier »
        // inopérant et « Vérification… » infini.
        defer { releaseCheckInFlight = false }
        var request = URLRequest(url: Self.appReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Session éphémère (X83).
        let session = URLSession(configuration: .ephemeral)
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                recordReleaseCheckFailure(status: status, bypassThrottle: bypassThrottle)
                return
            }
            applyReleaseCheck(data: data, lastChecked: lastChecked,
                              bypassThrottle: bypassThrottle)
        } catch {
            recordReleaseCheckFailure(status: nil, bypassThrottle: bypassThrottle,
                                      underlying: error)
        }
    }

    /// Échec : `lastCheckedAt` non repoussé. Le manuel dit pourquoi.
    @MainActor
    private func recordReleaseCheckFailure(status: Int?, bypassThrottle: Bool,
                                           underlying: Error? = nil) {
        guard bypassThrottle else { return }
        releaseCheckFailedMessage = String(
            format: self.localization.L(L10n.Settings.appCheckFailed),
            underlying?.localizedDescription ?? "HTTP \(status ?? 0)")
    }

    /// Réponse 200, séparée du transport ; décision testée en Core.
    @MainActor
    private func applyReleaseCheck(data: Data, lastChecked: Date?, bypassThrottle: Bool) {
        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            // 200 illisible = échec, jamais « à jour ».
            recordReleaseCheckFailure(status: 200, bypassThrottle: bypassThrottle,
                                      underlying: error)
            return
        }
        let defaults = UserDefaults.standard
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let decision = AppReleasePolicy.decide(
            current: current, latest: release,
            lastSeenTag: defaults.string(forKey: UDKey.frReleaseLastSeenTag),
            lastCheckedAt: lastChecked, now: Date(), bypassThrottle: bypassThrottle)
        switch decision {
        case .throttled:
            return
        case .unavailable, .unparseable:
            if bypassThrottle {
                releaseCheckFailedMessage = String(
                    format: self.localization.L(L10n.Settings.appCheckFailed), "HTTP 200")
            }
        case .upToDate:
            // Succès : la date de check est repoussée, même sans nouveauté.
            defaults.set(Date(), forKey: UDKey.frReleaseLastCheckedAt)
            releaseCheckFailedMessage = nil
        case .updateAvailable(let knownRelease, let alreadySeen):
            defaults.set(Date(), forKey: UDKey.frReleaseLastCheckedAt)
            if let json = encodeRelease(knownRelease) {
                defaults.set(json, forKey: UDKey.frReleaseLastKnown)
            }
            lastKnownRelease = knownRelease
            releaseCheckFailedMessage = nil
            // Alerte : lancement + tag jamais acquitté. Le manuel met À propos à
            // jour sans feuille (spec §7.5).
            if !bypassThrottle && !alreadySeen {
                availableAppRelease = knownRelease
            }
        }
    }

    func acknowledgeRelease(_ release: GitHubRelease) {
        // Les deux boutons acquittent (spec §7.4) : une fois par tag.
        UserDefaults.standard.set(release.tagName, forKey: UDKey.frReleaseLastSeenTag)
        availableAppRelease = nil
    }

    private func encodeRelease(_ release: GitHubRelease) -> String? {
        do {
            return String(data: try JSONEncoder().encode(release), encoding: .utf8)
        } catch {
            log("Release : encodage impossible, l'état d'À propos garde l'ancienne valeur : \(error.localizedDescription)",
                level: .warning)
            return nil
        }
    }

    /// État d'À propos au lancement, relu du disque.
    func loadLastKnownRelease() {
        guard let json = UserDefaults.standard.string(forKey: UDKey.frReleaseLastKnown),
              let data = json.data(using: .utf8) else { return }
        do {
            lastKnownRelease = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            // JSON corrompu : nil ; le prochain check réécrit.
            lastKnownRelease = nil
        }
    }

    // MARK: - Bilan d'installation (fenêtre dédiée)

    /// Posé au succès de l'installation (fenêtre de bilan) ; remis à nil à sa
    /// fermeture.
    private(set) var pendingInstallReport: InstallReport?
    /// File de dépôt multiple (ex-`@State` de `ModInstallView`) : survit entre
    /// deux zips.
    private(set) var pendingDropQueue = InstallDropQueue()

    func dropQueuePush(_ urls: [URL]) { pendingDropQueue.push(urls) }
    @discardableResult func dropQueueAdvance() -> URL? { pendingDropQueue.advance() }
    var nextQueuedDropURL: URL? { pendingDropQueue.current }

    /// Appelé par la feuille au succès : publie le bilan figé, sans ménage.
    /// ⚠️ **Ne dépile pas** : c'est celui qui présente qui dépile
    /// (`analyzeNextQueuedArchive`, `queueNextDropArchive`) ; dépiler ici
    /// sautait une archive en silence.
    func completeInstall(installedNames: [String]) {
        pendingInstallReport = InstallReport(
            installedNames: installedNames,
            deltas: lastInstallKeyDeltas,
            remainingInQueue: pendingDropQueue.count,
            preserved: lastInstallPreserved)
    }

    /// Referme le bilan — bouton « Terminé » de la fenêtre.
    func dismissInstallReport() {
        pendingInstallReport = nil
    }

    /// Réouverture de la feuille sur l'archive suivante. ⚠️ JAMAIS par le
    /// `onDismiss` qui discard : fichiers originaux de l'utilisateur.
    private(set) var pendingDropPresentation: URL?

    /// « Archive suivante (n) » : **dépile**, pose, referme le bilan.
    func queueNextDropArchive() {
        pendingDropPresentation = pendingDropQueue.advance()
        pendingInstallReport = nil
    }

    /// Lot abandonné (feuille fermée sans installer) : vider la file, sinon
    /// des archives ressurgissent plus tard.
    func abandonDropQueue() {
        guard !pendingDropQueue.isEmpty else { return }
        pendingDropQueue = InstallDropQueue()
    }

    /// Bilan fermé à la main : le reste du lot part avec lui.
    func abandonInstallReport() {
        pendingInstallReport = nil
        abandonDropQueue()
    }

    /// Feuille refermée : canal consommé.
    func clearDropPresentation() {
        pendingDropPresentation = nil
    }

    // ⚠️ Façades provisoires (P8) — état dans `navigationStore`.
    // `reportDetailFocus` : « voir la fiche » depuis le bilan.
    // `pendingTabRequest` : onglet demandé par le menu « Aller » ou ⌘K
    // (I-T1 / I-T2 ; patron B3-T4).
    var reportDetailFocus: String? { navigationStore.reportDetailFocus }

    func consumeReportDetailFocus() {
        navigationStore.consumeReportDetailFocus()
    }

    func openReportDetail(for folderName: String) {
        navigationStore.openReportDetail(for: folderName)
    }

    // MARK: - Navigation demandée depuis la scène App (I-T1 / I-T2)

    var pendingTabRequest: SidebarDestination? { navigationStore.pendingTabRequest }

    func requestTab(_ destination: SidebarDestination) {
        navigationStore.requestTab(destination)
    }

    /// Consommé par MainView une fois l'onglet appliqué.
    func consumePendingTabRequest() {
        navigationStore.consumePendingTabRequest()
    }

    /// Palette demandée depuis le menu (⌘K) ; la superposition est un
    /// `@State` de MainView.
    private(set) var paletteRequested = false

    func requestPalette() {
        paletteRequested = true
    }

    /// Consommé que la palette s'ouvre **ou non** (refus sous une feuille,
    /// spec §10) : un canal resté armé bloquerait la suivante.
    func consumePaletteRequest() {
        paletteRequested = false
    }

    // MARK: - Delta de clés de mise à jour (C2-T4)

    /// Les deltas de la dernière installation, pour l'écran de succès.
    private(set) var lastInstallKeyDeltas: [ModUpdateKeyDelta] = []
    /// A1-T7 — ce que la dernière installation a remis en place, pour le bilan.
    private(set) var lastInstallPreserved: [PreservedDataOutcome] = []

    /// Écrit le store des deltas AVANT l'écran de succès (survit à un crash) ;
    /// échec journalisé, jamais bloquant.
    func persistUpdateKeyDeltas(_ paths: [InstalledModPath]) {
        lastInstallKeyDeltas = paths.compactMap(\.keyDelta)
        // A1-T7 — préservation dite au journal **et** au bilan.
        lastInstallPreserved = paths.map {
            PreservedDataOutcome(modFolder: ($0.path as NSString).lastPathComponent,
                                 restored: $0.extrasRestored, failed: $0.extrasFailed,
                                 paths: $0.extrasRestoredPaths, skipped: $0.extrasSkipped)
        }.filter { !$0.isSilent }
        for outcome in lastInstallPreserved {
            for m in PreservedModData.messages(restored: outcome.restored,
                                               failed: outcome.failed,
                                               restoredPaths: outcome.paths,
                                               skipped: outcome.skipped,
                                               modFolder: outcome.modFolder) {
                log(m.text, level: m.isFailure ? .warning : .info)
            }
        }
        // Store changé : invalider les caches de lecture.
        updateKeyDeltasRevision += 1
        guard let dir = ModUpdateKeyDeltaStore.defaultDirectory() else {
            log("Delta de mise à jour : dossier Application Support indisponible, non persisté",
                level: .warning)
            return
        }
        for path in paths {
            guard let delta = path.keyDelta else { continue }
            do {
                try ModUpdateKeyDeltaStore.save(delta, directory: dir)
            } catch {
                log("Delta de mise à jour (\(delta.folderName)) : \(error.localizedDescription)",
                    level: .warning)
            }
        }
    }

    /// Révision du store (magasin non observé) : rafraîchit la fiche et
    /// invalide les caches.
    private(set) var updateKeyDeltasRevision = 0

    /// Caches de lecture de la fiche (delta + matcher O(retirées × ajoutées)) :
    /// sans eux, chaque republication rejouait disque + Levenshtein sur main.
    /// Une entrée ; fil principal seulement.
    /// ⚠️ `@ObservationIgnored` **obligatoire** : sous `@Observable`, un cache
    /// à créneau unique réécrit pendant un rendu invalide les vues sœurs —
    /// deux vues bouclent à l'infini (mesuré 2026-09-11). Sûr car
    /// l'invalidation lit `updateKeyDeltasRevision` (suivi) à **chaque** appel.
    @ObservationIgnored
    private var deltaReadCache: (uniqueId: String, revision: Int, delta: ModUpdateKeyDelta?)?
    @ObservationIgnored
    private var renamePairsCache: (uniqueId: String, revision: Int,
                                   result: (translation: [RenamePair], config: [RenamePair]))?

    /// Le delta persisté du mod, pour la fiche — nil si aucun.
    func updateKeyDelta(for mod: ModItem) -> ModUpdateKeyDelta? {
        if let cached = deltaReadCache,
           cached.uniqueId == mod.uniqueId,
           cached.revision == updateKeyDeltasRevision {
            return cached.delta
        }
        let delta = ModUpdateKeyDeltaStore.defaultDirectory()
            .flatMap { ModUpdateKeyDeltaStore.load(uniqueId: mod.uniqueId, directory: $0) }
        deltaReadCache = (mod.uniqueId, updateKeyDeltasRevision, delta)
        return delta
    }

    /// Paires de renommage : valeur EN identique (sûr) ∪ similarité de nom (à
    /// vérifier), moins le déjà réconcilié.
    func renamePairs(for delta: ModUpdateKeyDelta) -> (translation: [RenamePair], config: [RenamePair]) {
        if let cached = renamePairsCache,
           cached.uniqueId == delta.uniqueId,
           cached.revision == updateKeyDeltasRevision {
            return cached.result
        }
        let byValue = KeyRenameMatcher.pairsByValue(old: delta.translation.removedKeys,
                                                    new: delta.translation.addedUntranslated)
        let valueOlds = Set(byValue.map(\.oldKey))
        let valueNews = Set(byValue.map(\.newKey))
        let doneTradOlds = Set(delta.translation.reconciled.map(\.oldKey))
        // Signal sûr d'abord ; la similarité de nom ne voit que le reste.
        let left = delta.translation.removedKeys.keys
            .filter { !valueOlds.contains($0) && !doneTradOlds.contains($0) }
        let byNameTrad = KeyRenameMatcher.pairsBySimilarity(
            removed: left,
            added: delta.translation.addedUntranslated.keys
                .filter { !valueNews.contains($0) })
        let doneConfigKeys = Set((delta.config?.reconciled ?? []).map(\.oldKey))
        let byNameConfig = KeyRenameMatcher.pairsBySimilarity(
            removed: (delta.config?.removed ?? [:]).keys.filter { !doneConfigKeys.contains($0) },
            added: (delta.config?.added ?? [:]).keys.filter { !doneConfigKeys.contains($0) })
        let result = (byValue + byNameTrad, byNameConfig)
        renamePairsCache = (delta.uniqueId, updateKeyDeltasRevision, result)
        return result
    }

    /// Reporte des paires dans le(s) `fr.json`. `"Composant/clé"` = chemin
    /// relatif sous le mod ; routage dans `RenameReport.routeByOldComponent`.
    @MainActor
    func applyRenameReportTranslation(_ pairs: [RenamePair], to mod: ModItem) -> KeyRenameReportOutcome {
        guard !pairs.isEmpty, let dir = ModUpdateKeyDeltaStore.defaultDirectory(),
              var delta = ModUpdateKeyDeltaStore.load(uniqueId: mod.uniqueId, directory: dir)
        else { return .nothingLeft(skippedCrossComponent: 0) }

        let modsRoot = (gameDir as NSString).appendingPathComponent("Mods")
        // Composants = descendants dans l'arbre scanné, PAS `mod.children` (à
        // plat sous l'en-tête ; sinon « Rien à reporter »). Préfixe relatif,
        // disque physique (point de pause inclus).
        var descendants: [ModItem] = []
        func collect(_ items: [ModItem]) {
            for item in items {
                if item.folderName.hasPrefix(mod.folderName + "/") {
                    descendants.append(item)
                }
                collect(item.children ?? [])
            }
        }
        collect(mods)
        let componentFolders: [(prefix: String, physical: String)] =
            [("", mod.physicalFolderName)]
            + descendants.compactMap { item in
                guard item.folderName.hasPrefix(mod.folderName + "/") else { return nil }
                let rel = String(item.folderName.dropFirst(mod.folderName.count + 1))
                return (rel, item.physicalFolderName)
            }
        let prefixes = componentFolders.map(\.prefix)
        let physicalByPrefix = Dictionary(componentFolders.map { ($0.prefix, $0.physical) },
                                          uniquingKeysWith: { first, _ in first })

        // Désqualifier et router (sinon aucune clé ne matche, en silence). Les
        // paires qui changent de composant sont comptées, non reportées.
        let routed = RenameReport.routeByOldComponent(pairs, known: prefixes)
        let skipped = routed.crossComponent.count

        var applied: [RenamePair] = []
        for (prefix, routedPairs) in routed.byComponent.sorted(by: { $0.key < $1.key }) {
            guard let physical = physicalByPrefix[prefix] else { continue }
            let i18nDir = URL(fileURLWithPath: modsRoot)
                .appendingPathComponent(physical, isDirectory: true)
                .appendingPathComponent("i18n", isDirectory: true)
            // **Tous** les fichiers de la locale (layout B) : l'ancien
            // `i18n/fr.json` en dur abandonnait sans trace (5 mods).
            let frFiles = I18nLocaleResolver.files(in: i18nDir, locale: "fr")
                .compactMap { url -> RenameReport.FrenchFile? in
                    guard let data = try? Data(contentsOf: url),
                          let text = I18nFileDecoder.decode(data)?.text else { return nil }
                    return RenameReport.FrenchFile(id: url.path, text: text)
                }
            guard !frFiles.isEmpty else {
                log("Report de traduction (\(mod.name)) : aucun fichier français lisible "
                    + "dans \(i18nDir.path)", level: .warning)
                continue
            }

            let spread = RenameReport.applyToFrenchFiles(frFiles, pairs: routedPairs.map(\.raw))
            guard !spread.files.isEmpty else { continue }

            // X7 : ouvrir les droits avant d'écrire dans le dossier du mod.
            ModZipInstaller.grantOwnerWriteAccess(in: i18nDir)
            for rewrite in spread.files {
                do {
                    try rewrite.text.write(toFile: rewrite.id, atomically: true, encoding: .utf8)
                    // Seules les paires de CE fichier entrent au bilan.
                    for d in rewrite.applied {
                        if let q = routedPairs.first(where: { $0.raw == d })?.pair {
                            applied.append(q)
                        }
                    }
                } catch {
                    log("Report de traduction (\(mod.name)) : \(error.localizedDescription)",
                        level: .warning)
                }
            }
        }

        guard !applied.isEmpty else {
            return .nothingLeft(skippedCrossComponent: skipped)
        }
        // Paires appliquées → reconciled.
        let appliedSet = Set(applied)
        delta.translation.reconciled += applied
        delta.translation.addedUntranslated = delta.translation.addedUntranslated
            .filter { entry in !appliedSet.contains { $0.newKey == entry.key } }
        delta.translation.removedKeys = delta.translation.removedKeys
            .filter { entry in !appliedSet.contains { $0.oldKey == entry.key } }
        do { try ModUpdateKeyDeltaStore.save(delta, directory: dir) } // un échec muet rejouerait « rien à reporter »
        catch { log("Delta (\(mod.name)) non enregistré après report : \(error.localizedDescription)", level: .warning) }
        updateKeyDeltasRevision += 1
        // Sinon la pastille de couverture ment jusqu'au prochain scan.
        invalidateFrenchCoverage(for: mod.folderName)
        log(String(format: localization.L(L10n.Mods.updateDeltaRenamedDone), applied.count))
        return .applied(count: applied.count, skippedCrossComponent: skipped)
    }

    /// Reporte des paires dans le `config.json` racine, avec backup et garde
    /// anti-écrasement (patron de l'éditeur).
    @MainActor
    func applyRenameReportConfig(_ pairs: [RenamePair], to mod: ModItem) -> KeyRenameReportOutcome {
        guard !pairs.isEmpty, let dir = ModUpdateKeyDeltaStore.defaultDirectory(),
              var delta = ModUpdateKeyDeltaStore.load(uniqueId: mod.uniqueId, directory: dir)
        else { return .nothingLeft(skippedCrossComponent: 0) }

        let configURL = URL(fileURLWithPath: gameDir)
            .appendingPathComponent("Mods", isDirectory: true)
            .appendingPathComponent(mod.physicalFolderName, isDirectory: true)
            .appendingPathComponent("config.json")

        // Premier jet : ce qu'on applique au texte lu maintenant.
        guard let loadedText = try? String(contentsOf: configURL, encoding: .utf8)
        else { return .cancelled }
        let (rewritten, done) = RenameReport.applyToConfig(loadedText, pairs: pairs)
        guard !done.isEmpty else { return .nothingLeft(skippedCrossComponent: 0) }

        // Relecture juste avant d'écrire : pas d'écrasement silencieux.
        let onDisk: ModConfigWriteGuard.DiskState
        if !FileManager.default.fileExists(atPath: configURL.path) {
            onDisk = .missing
        } else if let reread = try? String(contentsOf: configURL, encoding: .utf8) {
            onDisk = .content(reread)
        } else {
            onDisk = .unreadable
        }
        switch ModConfigWriteGuard.decide(loaded: loadedText, onDisk: onDisk, pending: rewritten) {
        case .proceed:
            break
        case .externallyChanged, .unverifiable:
            // Journalisé ; `.cancelled` porté à l'écran (« rien à reporter »
            // tromperait).
            log("Report de réglages (\(mod.name)) : config.json a changé sous nos pieds, report annulé",
                level: .warning)
            return .cancelled
        }

        // Backup avant écriture, `onlyEnabled: false` (mod en pause possible).
        do { try ModConfigBackupManager.shared.backUpConfigOncePerDay(for: mod, gameDir: gameDir) } catch {
            log(String(format: localization.L(L10n.Settings.configBackupFailed),
                       mod.name, error.localizedDescription), level: .warning)
        }
        // X7 : ouvrir les droits avant d'écrire dans le dossier du mod.
        ModZipInstaller.grantOwnerWriteAccess(in: configURL.deletingLastPathComponent())
        do {
            try rewritten.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            log("Report de réglages (\(mod.name)) : \(error.localizedDescription)", level: .warning)
            return .cancelled
        }

        let appliedSet = Set(done)
        if var config = delta.config {
            config.reconciled += done
            config.added = config.added
                .filter { entry in !appliedSet.contains { $0.newKey == entry.key } }
            config.removed = config.removed
                .filter { entry in !appliedSet.contains { $0.oldKey == entry.key } }
            delta.config = config
        }
        do { try ModUpdateKeyDeltaStore.save(delta, directory: dir) } // un échec muet rejouerait « rien à reporter »
        catch { log("Delta (\(mod.name)) non enregistré après report : \(error.localizedDescription)", level: .warning) }
        updateKeyDeltasRevision += 1
        log(String(format: localization.L(L10n.Mods.updateDeltaRenamedDone), done.count))
        // Premier niveau seulement : rien en cross.
        return .applied(count: done.count, skippedCrossComponent: 0)
    }


    // MARK: - Mods à écarter (blacklist)

    private static let blacklistedModsKey = "blacklistedMods"

    private static func loadBlacklistedMods() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: blacklistedModsKey) else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    private static func saveBlacklistedMods(_ names: Set<String>) {
        guard let data = try? JSONEncoder().encode(names) else { return }
        UserDefaults.standard.set(data, forKey: blacklistedModsKey)
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

    private static let modActivationTimestampsKey = UDKey.modActivationTimestamps

    private static func loadModActivationTimestamps() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: modActivationTimestampsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    private static func saveModActivationTimestamps(_ map: [String: Date]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: modActivationTimestampsKey)
    }

    // MARK: - Installed mod registry (version + install date)

    /// Registre des mods installés ; persistance, sûreté et règle dans
    /// `InstalledModRegistryStore` (Core). Ici câblage et journal.
    private let installedModRegistryStore = InstalledModRegistryStore()

    /// Mods, packs aplatis (`flattenedMods`, Core).
    private func allInstalledMods() -> [ModItem] {
        mods.flattenedMods
    }

    /// Date d'installation enregistrée, `nil` sinon.
    nonisolated func installedModDate(for folderName: String) -> Date? {
        installedModRegistryStore.installedDate(for: folderName)
    }

    /// Rapproche le registre du scan et journalise le rapport du store.
    /// - Parameter modsFolderWasReadable: faux si `Mods/` illisible : les deux
    ///   purges (registre, ancres) sont suspendues ; l'enregistrement continue.
    nonisolated private func syncInstalledModRegistry(scannedMods: [ModItem],
                                          modsFolderWasReadable: Bool = true) {
        // Version suggérée par `UniqueID`, depuis le cache plat sous lock : lire
        // `nexusUpdates` ici serait une course, et la liste consolidée perd les
        // enfants perdants.
        let suggested = Dictionary(
            NexusUpdateChecker.shared.cachedUpdates().map { ($0.uniqueId, $0.latestVersion) },
            uniquingKeysWith: { first, _ in first })

        let report = installedModRegistryStore.sync(
            scannedMods: scannedMods,
            modsFolderWasReadable: modsFolderWasReadable,
            anchorStore: anchorStore,
            suggestedVersions: suggested)

        if report.gracePreserved > 0 {
            log("Dates d'installation préservées pour \(report.gracePreserved) mods dont seule la lecture de version avait changé",
                level: .info)
        }

        // Parc changé : affirmations (ancre, manifest) et avertissements du dump
        // à recomposer.
        Task { @MainActor [weak self] in
            self?.refreshAffirmedUpdates()
            self?.refreshModWarnings()
        }

        if report.rebuiltFromDisk > 0 {
            self.log(
                String(format: "Install registry rebuilt: %d mod(s) registered from disk.",
                       report.rebuiltFromDisk),
                level: .info
            )
        }
    }

    func showModal(message: String) {
        alertStore.show(message)
    }
    
    // MARK: - Saves

    /// Scans and parses every save's XML, off main.
    nonisolated func reloadSaves() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let saves = SaveManager.shared.fetchSaves()
            DispatchQueue.main.async {
                self?.savesStore.replace(saves: saves)
            }
        }
    }

    /// Best-effort check that the game runs (launcher or SMAPI process name),
    /// to warn before writing saves. A differently-named build won't match.
    func isGameRunning() -> Bool {
        let running = NSWorkspace.shared.runningApplications.contains {
            guard let name = $0.localizedName else { return false }
            return name.caseInsensitiveCompare("Stardew Valley") == .orderedSame
        }
        if running {
            // Jeu visible : le garde système suffit, le délai ne doit plus retenir un
            // relancement légitime.
            launchGate.noticeGameRunning()
        }
        return running
    }

    /// True if the save changed on disk since `info` was captured: forms
    /// don't diff fields, so a blind write would revert newer progress.
    func isSaveStale(_ info: SaveGameInfo) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: info.fileURL.path),
              let currentModified = attrs[.modificationDate] as? Date else {
            return false
        }
        return currentModified > info.lastModified
    }

    func editSave(info: SaveGameInfo, newName: String, newFarm: String, newFav: String, newMoney: Int, newTotalMoneyEarned: Int, newMaxHealth: Int, newMaxStamina: Int, newGoldenWalnuts: Int, newQiGems: Int, newClubCoins: Int, newSpouse: String) {
        // Même verrou que `duplicateSave`/`deleteSave` : deux
        // lecture-modification-écriture entrelacées perdent des changements
        // (audit 2026-08-05).
        guard savesStore.beginOperation() else { return }
        // Full save XML rewrite, off main.
        DispatchQueue.global(qos: .userInitiated).async {
            let success = SaveManager.shared.updateSave(info: info, newName: newName, newFarm: newFarm, newFav: newFav, newMoney: newMoney, newTotalMoneyEarned: newTotalMoneyEarned, newMaxHealth: newMaxHealth, newMaxStamina: newMaxStamina, newGoldenWalnuts: newGoldenWalnuts, newQiGems: newQiGems, newClubCoins: newClubCoins, newSpouse: newSpouse)
            DispatchQueue.main.async {
                self.savesStore.endOperation()
                if success {
                    self.reloadSaves()
                    self.showModal(message: self.localization.L(L10n.VM.saveSuccess))
                } else {
                    self.showModal(message: self.localization.L(L10n.VM.saveError))
                }
            }
        }
    }

    func saveInventory() {
        guard let save = navigationStore.editingSave else { return }
        let items = navigationStore.inventoryToEdit
        // Même verrou qu'`editSave` (audit 2026-08-05).
        guard savesStore.beginOperation() else { return }
        // Same as `editSave`: off main.
        DispatchQueue.global(qos: .userInitiated).async {
            let success = SaveManager.shared.updateInventory(info: save, items: items)
            let refetched = success ? SaveManager.shared.fetchInventory(for: save) : nil
            DispatchQueue.main.async {
                self.savesStore.endOperation()
                if success {
                    self.showModal(message: self.localization.L(L10n.Saves.inventorySuccess))
                    if let refetched = refetched {
                        self.navigationStore.inventoryToEdit = refetched
                    }
                } else {
                    self.showModal(message: self.localization.L(L10n.Saves.inventoryError))
                }
            }
        }
    }
    /// Envoie la sauvegarde à la corbeille, **hors fil principal** (dizaines
    /// de Mo). Seul le `Task.detached` quitte main.
    @MainActor
    func deleteSave(info: SaveGameInfo) async {
        guard savesStore.beginOperation() else { return }
        let deleted = await Task.detached(priority: .userInitiated) {
            SaveManager.shared.deleteSave(info: info)
        }.value
        savesStore.endOperation()
        if deleted {
            // Fermer l'éditeur ici (suppression asynchrone), et seulement pour la
            // sauvegarde supprimée.
            if navigationStore.editingSave?.id == info.id { navigationStore.setEditingSave(nil) }
            reloadSaves()
            showModal(message: localization.L(L10n.VM.deleteSaveSuccess))
        } else {
            showModal(message: localization.L(L10n.VM.deleteSaveError))
        }
    }
    
    /// Façades de lecture ; composition prouvée dans `SavesStoreTests`.
    var savesHierarchy: [SaveNode] { savesStore.hierarchy }
    var availableFilterTags: [String] { savesStore.availableFilterTags }
    
    func setAvatar(forSave folderName: String, iconPath: String) {
        let note = SaveNotesStore.shared.note(for: folderName)
        SaveNotesStore.shared.setNote(for: folderName, tag: note.tag, note: note.note, customIconPath: iconPath)
    }
    
    /// Copie le portrait dans le dossier de données (l'original peut
    /// disparaître). `CustomAvatarStaging` ; panneau `ImagePicking`.
    func selectCustomAvatar(forSave folderName: String, completion: ((String) -> Void)? = nil) {
        guard let chosen = imagePicker.pickImage(title: localization.L(L10n.Saves.avatarPanelTitle)),
              let avatars = AppSupport.avatarsDirectory else { return }
        let fm = FileManager.default, source = URL(fileURLWithPath: chosen)
        try? fm.createDirectory(at: avatars, withIntermediateDirectories: true)
        let plan = CustomAvatarStaging.plan(forSave: folderName, source: source, in: avatars,
                                            fileExists: { fm.fileExists(atPath: $0.path) })
        do {
            // Sans ce retrait, deux images de même nom échouaient (516) ; le préfixe
            // porte l'identité de la sauvegarde.
            if plan.replacesExisting { try fm.removeItem(at: plan.destination) }
            try fm.copyItem(at: source, to: plan.destination)
        } catch {
            log("selectCustomAvatar: copy failed — avatar path not set: \(error)", level: .error)
            return
        }
        setAvatar(forSave: folderName, iconPath: plan.destination.path)
        completion?(plan.destination.path)
    }
    
    /// Copie la sauvegarde et réécrit les noms, hors fil principal (copie
    /// complète, la plus lente). Rend le succès : la feuille ne se ferme que
    /// sur réussite (audit 2026-08-05).
    @MainActor
    func duplicateSave(info: SaveGameInfo, newName: String, newFarm: String) async -> Bool {
        guard savesStore.beginOperation() else { return false }
        let duplicated = await Task.detached(priority: .userInitiated) {
            SaveManager.shared.duplicateSave(info: info, newName: newName, newFarm: newFarm)
        }.value
        savesStore.endOperation()
        if duplicated {
            reloadSaves()
            showModal(message: localization.L(L10n.VM.duplicateSaveSuccess))
        } else {
            showModal(message: localization.L(L10n.VM.duplicateSaveError))
        }
        return duplicated
    }
    
    func openSaveInFinder(info: SaveGameInfo) {
        SaveManager.shared.openSaveInFinder(info: info)
    }

    // MARK: - Backup Timeline

    /// Lists backups off main.
    func listBackups(for info: SaveGameInfo, completion: @escaping @Sendable ([SaveBackup]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let backups = SaveManager.shared.listBackups(for: info)
            DispatchQueue.main.async {
                completion(backups)
            }
        }
    }

    /// Copie la sauvegarde entière dans les backups, hors fil principal.
    @MainActor
    func createBackup(info: SaveGameInfo) async -> Bool {
        guard savesStore.beginOperation() else { return false }
        let created = await Task.detached(priority: .userInitiated) {
            SaveManager.shared.backupSave(info: info)
        }.value
        savesStore.endOperation()
        return created
    }

    @MainActor
    func branchFromBackup(backup: SaveBackup, newName: String, newFarm: String) async -> Bool {
        guard savesStore.beginOperation() else { return false }
        let branched = await Task.detached(priority: .userInitiated) {
            SaveManager.shared.branchFromBackup(backup: backup, newName: newName, newFarm: newFarm)
        }.value
        savesStore.endOperation()
        if branched {
            reloadSaves()
            showModal(message: localization.L(L10n.VM.branchSuccess))
            return true
        } else {
            showModal(message: localization.L(L10n.VM.branchError))
            return false
        }
    }

    @MainActor
    func restoreBackup(backup: SaveBackup, info: SaveGameInfo) async {
        guard savesStore.beginOperation() else { return }
        let restored = await Task.detached(priority: .userInitiated) {
            SaveManager.shared.restoreBackup(backup: backup, info: info)
        }.value
        savesStore.endOperation()
        if restored {
            reloadSaves()
            navigationStore.viewingSaveTimeline = nil
            navigationStore.setEditingSave(nil)
            showModal(message: localization.L(L10n.VM.restoreSuccess))
        } else {
            showModal(message: localization.L(L10n.VM.restoreError))
        }
    }

    @MainActor
    func deleteBackup(_ backup: SaveBackup) async -> Bool {
        guard savesStore.beginOperation() else { return false }
        let deleted = await Task.detached(priority: .userInitiated) {
            SaveManager.shared.deleteBackup(backup)
        }.value
        savesStore.endOperation()
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
    }

    // MARK: - Backup & Management
    /// Zips `sourceDir` to a timestamped Desktop file (saves and mods).
    private func zipToDesktop(sourceDir: String, filePrefix: String, successKey: String, errorKey: String) {
        let desktopDir = "\(NSHomeDirectory())/Desktop"
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "")
        let zipPath = "\(desktopDir)/\(filePrefix)_\(timestamp).zip"

        // Zipping can take long: off main.
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
                        self.showModal(message: String(format: self.localization.L(successKey), zipPath))
                    } else {
                        self.showModal(message: self.localization.L(errorKey))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showModal(message: self.localization.L(L10n.VM.cannotRunZip))
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
            showModal(message: localization.L(L10n.Settings.gameDirNotSet))
            return
        }
        let modsDir = (gameDir as NSString).appendingPathComponent("Mods")
        zipToDesktop(sourceDir: modsDir, filePrefix: "StardewMods_Backup", successKey: L10n.VM.backupModsSuccess, errorKey: L10n.VM.zipModsError)
    }
    
    /// Cibles de « Vider les mods désactivés », relevées une fois pour la
    /// confirmation et `cleanDisabledMods(targets:)`.
    func disabledModTargets() -> [String] {
        guard !gameDir.isEmpty else { return [] }
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: modsPath) else {
            return []
        }
        return DisabledModsCleanup.targets(in: entries)
    }

    /// Met en corbeille (X103-B) les mods en pause, en **un** événement
    /// (721 dossiers au parc) ; l'espace ne revient qu'au vidage.
    func cleanDisabledMods(targets: [String]) {
        guard !gameDir.isEmpty else { return }
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let result = ModTrash.trash(modsPath: modsPath, trashRoot: ModTrash.root(gameDir: gameDir), stamp: ModTrash.makeStamp(), items: targets.map {
            ModTrash.Item(physical: $0, logicalLeaf: String($0.drop { $0 == "." }))
        })
        // Pas de `forgetStores` : « Tout remettre » rend le lot avec ses données.
        let firstError = result.failed.first?.error

        let outcome = DisabledModsCleanup.outcome(removed: result.moved.count,
                                                  failed: result.failed.count)
        switch outcome {
        case .nothingFound:
            showModal(message: localization.L(L10n.VM.cleanModsNotFound))
        case .partial:
            showModal(message: String(format: localization.L(L10n.VM.cleanModsError),
                                      firstError?.localizedDescription ?? ""))
        case .removed:
            showModal(message: localization.L(L10n.VM.cleanModsSuccess))
        }

        if outcome.needsRescan {
            let resolvedGameDir = gameDir
            DispatchQueue.global(qos: .userInitiated).async {
                self.scanMods(gameDir: resolvedGameDir)
            }
        }
    }

    func openSavesFolder() {
        let home = NSHomeDirectory()
        let savesDir = URL(fileURLWithPath: "\(home)/.config/StardewValley/Saves")
        NSWorkspace.shared.open(savesDir)
    }
    
    // MARK: - Mod Profiles
    func loadProfiles() {
        // Sur main (`performInitialLoad`) : l'UI suppose cet ordre.
        if let data = UserDefaults.standard.data(forKey: UDKey.modProfiles),
           let profiles = try? JSONDecoder().decode([ModProfile].self, from: data) {
            self.profilesStore.setProfiles(profiles)
        } else {
            self.profilesStore.setProfiles([])
        }

        if let activeIdStr = UserDefaults.standard.string(forKey: UDKey.activeProfileId),
           let activeId = UUID(uuidString: activeIdStr) {
            self.profilesStore.setActiveProfile(activeId)
        }

        sweepOrphanProfileConfigStores()
    }

    /// Retire les magasins de configs sans profil propriétaire (B3-T7), pour
    /// les profils supprimés avant que `deleteProfile` le fasse. Garde-fou
    /// dans `orphanFileNames` : liste de profils vide (préférences illisibles)
    /// = aucun orphelin.
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
        log(String(format: localization.L(L10n.VM.profileConfigsSwept), Int64(removed)))
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
    
    /// Active profile, or nil (an orphaned id yields nothing).
    var activeProfile: ModProfile? { profilesStore.activeProfile }

    private static let defaultProfileKey = "defaultProfileId"

    /// Profil par défaut auto-créé. **Miroir** écrit seulement par le seed,
    /// d'où son absence de `resyncMirroredDefaults()`. Seed par la constante
    /// **statique**.
    private(set) var defaultProfileId: UUID? =
        UserDefaults.standard.string(forKey: StarHubTHViewModel.defaultProfileKey).flatMap(UUID.init(uuidString:))

    /// Protected from deletion; otherwise a normal profile.
    func isDefaultProfile(_ id: UUID) -> Bool { defaultProfileId == id }

    /// Profils dont la dernière application a échoué : leur contenu ne se
    /// réécrit pas depuis le disque (l'accident). Sortie à la prochaine
    /// application réussie ou adoption délibérée. Non persisté.
    private var incompletelyAppliedProfileIds: Set<UUID> = []

    /// R2 — journal d'une application interrompue (crash) : **survit** au
    /// redémarrage et empêche `syncActiveProfileIds` d'adopter l'état
    /// partiel. Présenté via `pendingApplyRecovery`.
    private(set) var unresolvedApplyJournal: ProfileApplyJournal?

    /// R2 — dossier du journal, relevé **une fois** (quatre appels, un seul
    /// fichier). Pas de défaut dans le store : aucun test n'écrit ici.
    private let applyJournalDirectory: URL? = AppSupport.directory

    /// R2 — dialogue de reprise, après révélation de la fenêtre, jamais
    /// pendant le splash.
    private(set) var pendingApplyRecovery: ProfileApplyJournal?

    /// One-time starter profile on a fresh install, guarded by a persisted
    /// flag and deferred until a scan found mods.
    func ensureDefaultProfileIfNeeded() {
        let key = "didSeedDefaultProfile"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard !mods.isEmpty else { return }   // wait for a scan with mods; don't burn the flag yet
        if modProfiles.isEmpty {
            // Amorçage : décrit l'installation trouvée (base protégée).
            createProfile(name: localization.L(L10n.Profiles.defaultName), seed: .currentlyEnabledMods)
            // Record the seeded profile as the (undeletable) default.
            if let seeded = modProfiles.last {
                defaultProfileId = seeded.id
                UserDefaults.standard.set(seeded.id.uuidString, forKey: Self.defaultProfileKey)
            }
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// - Parameter seed: vide ou instantané des mods actifs, sans défaut :
    ///   chaque appelant tranche.
    func createProfile(name: String, seed: ProfileSeed) {
        let made = ProfileFactory.make(name: name,
                                       seed: seed,
                                       enabledMods: mods.flattenedMods.filter(\.isEnabled))
        profilesStore.add(made.profile)
        // Un instantané peut s'activer tout de suite ; un profil vide, non
        // (`ProfileFactory.make`).
        if made.activate {
            profilesStore.setActiveProfile(made.profile.id)
        }
        saveProfiles()
        log(String(format: localization.L(L10n.VM.profileCreated), name, made.profile.enabledModIds.count))
    }

    // MARK: - Récupérer un fichier isolé depuis une sauvegarde (B4-T4)

    /// Fichiers qu'une mise à jour a emportés et qu'une sauvegarde peut
    /// rendre ; vide avant `scanRecoverableFiles()`.
    private(set) var recoverableFiles: [RecoverableFile] = []
    private(set) var isScanningRecoverableFiles = false

    /// Balaye les sauvegardes d'installation, en fond, jamais au démarrage
    /// (centaines de JSON).
    func scanRecoverableFiles() {
        guard !isScanningRecoverableFiles else { return }
        isScanningRecoverableFiles = true
        let backups = ModInstallBackupManager.shared.loadBackups()
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        // Chemin **physique** (`physicalFolderName`) : pause et enfants de pack.
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

    /// Clés de premier niveau d'un JSON, `nil` si absent ou illisible, via
    /// `ManifestJSON.sanitize` (un décapage naïf coupe les URL).
    nonisolated private static func topLevelJSONKeys(atPath path: String) -> [String]? {
        guard let data = FileManager.default.contents(atPath: path),
              let raw = String(data: data, encoding: .utf8) else { return nil }
        guard let object = ManifestJSON.decode(raw) else { return nil }
        return Array(object.keys)
    }

    /// Réécrit un fichier perdu ; le fichier en place est **sauvegardé
    /// d'abord**.
    @discardableResult
    func recoverFile(_ file: RecoverableFile) -> Bool {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: file.installedPath),
               let mod = mods.flattenedMods.first(where: { $0.folderName == file.folderName }) {
                // `onlyEnabled: false` : sinon un mod en pause faisait échouer la
                // récupération (527/593 mods à `config.json` sont en pause).
                _ = try ModConfigBackupManager.shared.createBackup(gameDir: gameDir, mods: [mod],
                                                                   onlyEnabled: false)
            }
            // `RecoveredFileWriter` : dossiers de mods souvent en lecture seule.
            try RecoveredFileWriter.write(from: file.backupPath,
                                          to: file.installedPath,
                                          modRoot: file.installedRoot)
            log(String(format: localization.L(L10n.Recovery.recovered), file.relativePath, file.modName))
            recoverableFiles.removeAll { $0.id == file.id }
            // Rescan sans distinguer le fichier (X66) : un scan de trop est gratuit.
            rescanKeybindsAfterConfigWrite()
            // Protection de l'Entretien peut-être levée (I-T8).
            if maintenanceStore.report != nil { buildMaintenanceReport() }
            return true
        } catch {
            showModal(message: installErrorMessage(error))
            return false
        }
    }

    /// Diff clé à clé entre traduction sauvegardée et installée : récupérer
    /// **sans écraser** le travail fait depuis.
    func translationDiff(for file: RecoverableFile) -> [TranslationKeyDiff] {
        let backup = Self.parseTranslation(atPath: file.backupPath) ?? [:]
        let installed = Self.parseTranslation(atPath: file.installedPath) ?? [:]
        return TranslationRecoveryDiff.compare(backup: backup, installed: installed)
    }

    /// Lecture comme l'éditeur : décodage tolérant, analyse indulgente.
    nonisolated private static func parseTranslation(atPath path: String) -> [String: String]? {
        guard let data = FileManager.default.contents(atPath: path),
              let text = I18nFileDecoder.decode(data)?.text,
              let parsed = try? I18nLenientParser.parse(text) else { return nil }
        return parsed
    }

    /// Réinjecte les clés que l'installé **n'a plus** (`edits(for:)`), via
    /// `TranslationDocument` (ordre et forme conservés) ; `.bak` en filet.
    @discardableResult
    func recoverTranslationKeys(_ diffs: [TranslationKeyDiff], in file: RecoverableFile) -> Bool {
        let edits = TranslationRecoveryDiff.edits(for: diffs)
        guard !edits.isEmpty else { return false }

        let target = URL(fileURLWithPath: file.installedPath)
        // La source donne le rang des clés neuves.
        let i18nDirectory = target.deletingLastPathComponent()
        let sourceFiles = I18nLocaleResolver.files(in: i18nDirectory, locale: "default")
        let sourceFile = sourceFiles.first { $0.lastPathComponent == target.lastPathComponent }
            ?? sourceFiles.first
        guard let sourceFile,
              let sourceData = FileManager.default.contents(atPath: sourceFile.path),
              let sourceText = I18nFileDecoder.decode(sourceData)?.text else {
            showModal(message: localization.L(L10n.Recovery.noSource))
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
            // Lecture seule fréquente : même remède.
            try RecoveredFileWriter.withWriteAccess(to: file.installedPath,
                                                    modRoot: file.installedRoot) {
                try TranslationFileStore.write(text, to: target)
            }
            log(String(format: localization.L(L10n.Recovery.keysRecovered), Int64(edits.count), file.modName))
            // Vider le cache F7 directement (même taille, même seconde) ;
            // `invalidateFrenchCoverage` effacerait les baselines.
            translationDiffCache.removeAll()
            scanRecoverableFiles()
            return true
        } catch {
            showModal(message: error.localizedDescription)
            return false
        }
    }

    /// Mods réclamés par un profil et absents : ce que le profil a retenu,
    /// puis cache Nexus, puis index des sauvegardes (restauration hors ligne).
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

    /// Restaure un mod absent depuis sa dernière sauvegarde ; faux sinon.
    @discardableResult
    func restoreMissingModFromBackup(uniqueId: String) -> Bool {
        let manager = ModInstallBackupManager.shared
        guard let backup = manager.loadBackups()
            .filter({ $0.modMetadata.uniqueId.lowercased() == uniqueId.lowercased() })
            .max(by: { $0.timestamp < $1.timestamp }) else { return false }
        do {
            let report = try manager.restoreBackup(backup, gameDir: gameDir)
            log(String(format: localization.L(L10n.ModInstall.restoreReportWritten),
                       report.modName, report.version, report.displayPath))
            refresh()
            return true
        } catch {
            showModal(message: installErrorMessage(error))
            return false
        }
    }

    /// Ajoute un mod installé au profil (dépendance manquante), appliqué au
    /// disque si le profil est actif.
    func addModToProfile(id: UUID, uniqueId: String) {
        guard let index = modProfiles.firstIndex(where: { $0.id == id }) else { return }
        // R2 : mêmes gardes que l'activation.
        guard guardProfileApply(for: id, name: modProfiles[index].name) else { return }
        let key = uniqueId.lowercased()
        guard !modProfiles[index].enabledModIds.contains(where: { $0.lowercased() == key }) else { return }

        // Métadonnées retenues : seule trace après désinstallation.
        let added = mods.flattenedMods.first(where: { $0.uniqueId.lowercased() == key })
        if let added {
            profilesStore.mutateProfile(with: id) {
                $0.modMetadata[added.uniqueId] = ProfileModMetadata(name: added.name,
                                                                    nexusModId: added.nexusModId)
            }
        }
        var ids = modProfiles[index].enabledModIds
        ids.append(uniqueId)
        // Nom si connu, sinon l'identifiant.
        let addedName = added?.name ?? uniqueId
        updateProfile(id: id, newName: modProfiles[index].name, enabledModIds: ids)
        log(String(format: localization.L(L10n.VM.profileModAdded),
                   addedName, modProfiles[index].name, ids.count))
    }

    /// Bascule le favori, persisté aussitôt.
    func toggleFavorite(_ mod: ModItem) {
        if favoriteMods.contains(mod.folderName) {
            favoriteMods.remove(mod.folderName)
        } else {
            favoriteMods.insert(mod.folderName)
        }
        Self.saveFavoriteMods(favoriteMods)
    }

    func isFavorite(_ mod: ModItem) -> Bool { favoriteMods.contains(mod.folderName) }

    /// Bascule « à écarter », symétrique de `toggleFavorite` ; affichage et
    /// filtre seulement.
    func toggleBlacklist(_ mod: ModItem) {
        if blacklistedMods.contains(mod.folderName) {
            blacklistedMods.remove(mod.folderName)
        } else {
            blacklistedMods.insert(mod.folderName)
        }
        Self.saveBlacklistedMods(blacklistedMods)
    }

    func isBlacklisted(_ mod: ModItem) -> Bool {
        blacklistedMods.contains(mod.folderName)
    }

    /// Configs par profil possibles ? Pas pour un **en-tête de pack** (pas de
    /// réglages propres). Sans `UniqueID`, oui : magasin indexé par dossier.
    func canManageProfileConfig(_ mod: ModItem) -> Bool { !mod.isGroup }

    func isProfileConfigManaged(_ mod: ModItem) -> Bool {
        profileManagedConfigMods.contains(mod.folderName)
    }

    /// Pose ou retire la marque, persisté aussitôt. **Prend la valeur, ne
    /// bascule pas** : un `Toggle` rappelle `set` au re-rendu (patron
    /// `setCustomCategory`). Retirer ne détruit rien.
    func setProfileConfigManaged(_ mod: ModItem, _ on: Bool) {
        guard canManageProfileConfig(mod) else { return }
        let changed = on
            ? profileManagedConfigMods.insert(mod.folderName).inserted
            : (profileManagedConfigMods.remove(mod.folderName) != nil)
        guard changed else { return }
        Self.saveProfileManagedConfigMods(profileManagedConfigMods)
    }

    /// Ce que chaque profil a mémorisé et si ça correspond au disque
    /// (`matchesDisk`, comparaison d'octets) : explique l'absence d'écart.
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

    /// Ce qu'un profil retient et ses orphelins, **gardés** (spec §6.5).
    /// Seule fonction à les nommer.
    func profileConfigSummary(for profile: ModProfile) -> (total: Int, orphans: [String]) {
        guard let url = ProfileConfigStore.fileURL(profileId: profile.id) else {
            return (0, [])
        }
        let entries = ProfileConfigStore.load(from: url)
        // `folderName` logique : une pause ne vaut pas désinstallation.
        let installed = Set(mods.flattenedMods.map(\.folderName))
        let orphans = entries.keys
            .filter { !installed.contains($0) }
            .sorted()
        return (entries.count, orphans)
    }

    /// Écarts entre deux profils ; `nil` si un texte ne se parse pas (pas de
    /// diff inventé).
    func profileConfigDiffs(mod: ModItem, other: ModProfile) -> [ConfigKeyDiff]? {
        guard let active = profilesStore.activeProfile,
              let textA = profileConfigText(mod: mod, profile: active),
              let textB = profileConfigText(mod: mod, profile: other),
              let treeA = ConfigJSONTree.parse(textA),
              let treeB = ConfigJSONTree.parse(textB) else { return nil }
        return ConfigJSONDiff.compare(treeA, treeB)
    }

    /// Supprime le `config.json` (valeurs par défaut inconnues, dans le C#).
    /// SMAPI n'en réécrit un que pour les mods qui appellent
    /// `helper.ReadConfig<T>()` (547/1015 en portent un).
    /// - Returns: `true` si un fichier a été supprimé.
    @discardableResult
    func resetModConfigToDefaults(_ mod: ModItem) -> Bool {
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let url = ProfileConfigStore.configURL(modsPath: modsPath,
                                               physicalFolderName: mod.physicalFolderName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Sans ce log, un clic sur un mod sans config ne laisse aucune trace.
            log(String(format: localization.L(L10n.VM.profileConfigResetAbsent), mod.folderName), level: .info)
            return false
        }
        // Lecture seule (X7) : droits ouverts jusqu'à la racine du mod, puis
        // rendus.
        let modRoot = url.deletingLastPathComponent().path
        do {
            try RecoveredFileWriter.withWriteAccess(to: url.path, modRoot: modRoot) {
                try ModZipInstaller.removeItemGrantingWriteAccess(atPath: url.path)
            }
            log(String(format: localization.L(L10n.VM.profileConfigResetDone), mod.folderName))
            return true
        } catch {
            log(String(format: "config.json: %@ — %@", mod.folderName,
                       error.localizedDescription), level: .error)
            return false
        }
    }

    /// Aperçu d'un import des favoris, sans rien écrire : combien entrent,
    /// lesquels ne le peuvent pas.
    func favoriteImportPreview(profileId: UUID) -> FavoriteResolution.Result {
        guard let profile = profilesStore.profile(with: profileId) else {
            return FavoriteResolution.Result(ids: [], unresolved: [])
        }
        return FavoriteResolution.profileIds(favorites: favoriteMods, in: mods,
                                             existing: profile.enabledModIds)
    }

    /// Ajoute tous les favoris à un profil **en une mutation** (une boucle sur
    /// `addModToProfile` réappliquerait le profil au disque à chaque mod).
    /// `modMetadata` renseigné dans la même passe : seule source pour
    /// **nommer** un mod désinstallé.
    /// - Returns: ce qui a été fait.
    @discardableResult
    func importFavorites(into profileId: UUID) -> FavoriteResolution.Result {
        guard let index = modProfiles.firstIndex(where: { $0.id == profileId }) else {
            return FavoriteResolution.Result(ids: [], unresolved: [])
        }
        // R2 : avant toute mutation, sinon demi-état en mémoire.
        guard guardProfileApply(for: profileId, name: modProfiles[index].name) else {
            return FavoriteResolution.Result(ids: [], unresolved: [])
        }
        let resolution = FavoriteResolution.profileIds(
            favorites: favoriteMods, in: mods,
            existing: modProfiles[index].enabledModIds)
        guard !resolution.ids.isEmpty else { return resolution }

        // Résolution dans `ProfileFactory.metadata(forIds:in:)` (une copie).
        profilesStore.mutateProfile(with: profileId) {
            $0.modMetadata.merge(
                ProfileFactory.metadata(forIds: resolution.ids, in: mods)) { _, new in new }
        }
        // Capturés **avant** `updateProfile` : le rescan réécrit
        // `enabledModIds` depuis le disque.
        let name = modProfiles[index].name
        let newIds = modProfiles[index].enabledModIds + resolution.ids
        let importedCount = resolution.ids.count
        updateProfile(id: profileId, newName: name, enabledModIds: newIds)
        log(String(format: localization.L(L10n.VM.profileFavoritesImported),
                   importedCount, name, newIds.count))
        return resolution
    }

    /// Aperçu d'un import des « à écarter », symétrique de
    /// `favoriteImportPreview`.
    func blacklistImportPreview(profileId: UUID) -> BlacklistResolution.Result {
        guard let profile = profilesStore.profile(with: profileId) else {
            return BlacklistResolution.Result(ids: [], unresolved: [])
        }
        return BlacklistResolution.profileIds(blacklist: blacklistedMods, in: mods,
                                              existing: profile.enabledModIds)
    }

    /// Ajoute tous les « à écarter », symétrique d'`importFavorites(into:)`
    /// (une mutation, `modMetadata`, garde R2, journal).
    @discardableResult
    func importBlacklisted(into profileId: UUID) -> BlacklistResolution.Result {
        guard let index = modProfiles.firstIndex(where: { $0.id == profileId }) else {
            return BlacklistResolution.Result(ids: [], unresolved: [])
        }
        guard guardProfileApply(for: profileId, name: modProfiles[index].name) else {
            return BlacklistResolution.Result(ids: [], unresolved: [])
        }
        let resolution = BlacklistResolution.profileIds(
            blacklist: blacklistedMods, in: mods,
            existing: modProfiles[index].enabledModIds)
        guard !resolution.ids.isEmpty else { return resolution }

        // Résolution dans `ProfileFactory.metadata(forIds:in:)` (une copie).
        profilesStore.mutateProfile(with: profileId) {
            $0.modMetadata.merge(
                ProfileFactory.metadata(forIds: resolution.ids, in: mods)) { _, new in new }
        }
        let name = modProfiles[index].name
        let newIds = modProfiles[index].enabledModIds + resolution.ids
        let importedCount = resolution.ids.count
        updateProfile(id: profileId, newName: name, enabledModIds: newIds)
        log(String(format: localization.L(L10n.VM.profileBlacklistedImported),
                   importedCount, name, newIds.count))
        return resolution
    }

    /// Copie un profil sous « <original> (copie) », **non activée** (pas de
    /// déplacement non demandé).
    func duplicateProfile(id: UUID) {
        guard let source = profilesStore.profile(with: id) else { return }
        let copy = ProfileFactory.duplicate(source, nameFormat: localization.L(L10n.Profiles.copyNameFormat))
        profilesStore.add(copy)
        saveProfiles()
        log(String(format: localization.L(L10n.VM.profileCreated), copy.name, copy.enabledModIds.count))
    }

    func deleteProfile(id: UUID) {
        // The default profile is protected — never delete it.
        guard !isDefaultProfile(id) else { return }
        if let name = profilesStore.profile(with: id)?.name {
            log(String(format: localization.L(L10n.VM.profileDeleted), name))
        }
        profilesStore.removeProfile(with: id)
        // Le magasin de configs part avec le profil (B3-T7) ; la confirmation
        // prévient.
        ProfileConfigStore.delete(profileId: id)
        if activeProfileId == id {
            profilesStore.setActiveProfile(nil)
        }
        saveProfiles()
    }
    
    func updateProfile(id: UUID, newName: String, enabledModIds: [String]) {
        // R2 : un profil actif édité s'applique au disque ; inactif, la garde
        // laisse passer.
        guard guardProfileApply(for: id, name: newName) else { return }
        if profilesStore.mutateProfile(with: id, {
            $0.name = newName
            $0.enabledModIds = enabledModIds
        }) {
            saveProfiles()

            // If this is the active profile, apply the new mod selection to the filesystem
            if activeProfileId == id, let updated = profilesStore.profile(with: id) {
                applyProfileToFilesystem(profile: updated)
            }
        }
    }

    // MARK: - Mod notes (B3-T6)

    /// Note du mod dans le **profil actif** ; nil sans note ou sans profil.
    func modNote(for mod: ModItem) -> String? {
        activeProfile?.note(forModId: mod.uniqueId)
    }

    /// Écrit la note sur le profil actif ; règle dans `ModProfile.setNote`.
    func setModNote(_ text: String?, for mod: ModItem) {
        guard let activeId = activeProfileId,
              modProfiles.contains(where: { $0.id == activeId }) else { return }
        profilesStore.mutateProfile(with: activeId) {
            $0.setNote(text, forModId: mod.uniqueId)
        }
        saveProfiles()
    }

    /// Renames a profile in place (its enabled-mod set is untouched).
    func renameProfile(id: UUID, newName: String) {
        guard modProfiles.firstIndex(where: { $0.id == id }) != nil else { return }
        profilesStore.mutateProfile(with: id) { $0.name = newName }
        saveProfiles()
    }

    // MARK: - Incompatibilités entre mods (A5-T2)

    /// Incompatibilités déclarées ou écartées, chargées au démarrage,
    /// réécrites à chaque décision (`mod_conflicts.json`).
    private(set) var modConflictVerdicts = ModConflictVerdicts()

    /// Écrit le magasin et **dit l'échec** (patron
    /// `InstalledTranslationStore`).
    func saveConflictVerdicts() {
        if !ModConflictVerdictsStore.save(modConflictVerdicts) {
            log("Verdict non enregistré : il ne survivra pas à la fermeture", level: .warning)
        }
    }

    /// Déclare une incompatibilité (fiche). Mutateur dans le corps de la
    /// classe (`private(set)`).
    func declareConflict(_ pair: ModConflictPair, note: String) {
        modConflictVerdicts.declare(pair, note: note, at: Date())
        saveConflictVerdicts()
    }

    /// Écarte une paire (constat faux ou signalement repris) ; même mutateur.
    func dismissConflict(_ pair: ModConflictPair, note: String = "") {
        modConflictVerdicts.dismiss(pair, note: note, at: Date())
        saveConflictVerdicts()
    }

    // MARK: - Bissection (recherche du mod responsable)

    /// Recherche par moitiés, créée à la demande. `lazy` refusé par
    /// `@Observable`, d'où stockage + accesseur. **Non suivi** : les vues
    /// observent le runner.
    @ObservationIgnored
    private var _bisection: BisectionRunner?
    var bisection: BisectionRunner {
        if let _bisection { return _bisection }
        let created = BisectionRunner(vm: self)
        _bisection = created
        return created
    }

    /// Active exactement ces dossiers, met les autres en pause, rescane
    /// (bissection). `activeProfileId` neutralisé : sinon
    /// `syncActiveProfileIds` écraserait le profil de l'utilisateur.
    /// - Parameter completion: le **résultat** ; un échec partiel doit garder
    ///   l'instantané de reprise.
    func applyEnabledFolders(_ folders: [String],
                             completion: @escaping (BisectionRestoreOutcome) -> Void) {
        let target = Set(folders)
        let ephemeral = ModProfile(
            // Nom lisible dans l'alerte d'échec.
            name: localization.L(L10n.Bisect.profileName),
            enabledModIds: mods
                .filter { target.contains($0.folderName) }
                .flatMap { $0.components.map(\.uniqueId) }
                .filter { !$0.isEmpty }
        )
        let savedActiveProfile = activeProfileId
        profilesStore.setActiveProfile(nil)
        applyProfileToFilesystem(profile: ephemeral, journaling: false) { [weak self] moveFailures in
            self?.profilesStore.setActiveProfile(savedActiveProfile)
            completion(BisectionRestoreOutcome(moveFailures: moveFailures))
        }
    }

    // MARK: - Configs par profil : capture et restauration (B3-T5)

    /// Profil actif dont le disque ne porte **pas** les configs (§6.3 :
    /// bascule faite jeu ouvert), ou `nil`. Persisté : survit à une fermeture.
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

    /// Pose ou lève la marque de désynchronisation ; `entering` = profil qui
    /// devient actif (`nil` si on ne fait que quitter). Jeu ouvert : capture
    /// et restauration sautées, `entering` marqué pour que la prochaine
    /// capture refuse ce disque. Jeu fermé : marque levée.
    private func syncProfileConfigsDesyncMarker(entering: UUID?) {
        guard isGameRunning() else {
            Self.profileConfigsDesyncedProfileId = nil
            return
        }
        if let entering {
            Self.profileConfigsDesyncedProfileId = entering
        }
    }

    /// Mods marqués présents, avec chemin **physique** et clé **logique**.
    private func managedConfigTargets() -> [(key: String, url: URL)] {
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        return mods
            .flattenedMods
            .filter { profileManagedConfigMods.contains($0.folderName) }
            .map { (key: $0.folderName,
                    url: ProfileConfigStore.configURL(modsPath: modsPath,
                                                      physicalFolderName: $0.physicalFolderName)) }
    }

    /// Mémorise le `config.json` de chaque mod marqué pour ce profil.
    /// **Seulement sur une vraie transition** (§6.3), jamais à la reprise ni
    /// dans `syncActiveProfileIds` : sinon on écrase le sortant avec l'entrant.
    func captureProfileConfigs(for profileId: UUID) {
        // Trois abstentions (jeu ouvert, désynchronisé, R2) dans
        // `ProfileConfigCapture` (Core) : trou visible plutôt que donnée fausse.
        if let abstention = ProfileConfigCapture.abstention(
            capturing: profileId, profiles: modProfiles,
            gameRunning: isGameRunning(),
            desyncedProfileId: Self.profileConfigsDesyncedProfileId,
            journal: unresolvedApplyJournal) {
            switch abstention {
            case .gameRunning:
                log(localization.L(L10n.VM.profileConfigsSkippedGame), level: .warning)
            case .desynced(let name):
                log(String(format: localization.L(L10n.VM.profileConfigsDesynced), name),
                    level: .warning)
            case .interruptedApply(let name):
                log(String(format: localization.L(L10n.VM.profileConfigsSkippedRecovery), name),
                    level: .warning)
            }
            return
        }
        guard let url = ProfileConfigStore.fileURL(profileId: profileId) else { return }
        var entries = ProfileConfigStore.load(from: url)
        let before = entries
        let now = Date()
        for target in managedConfigTargets() {
            // Lu depuis le disque : l'état réel au moment de la bascule.
            let text = try? String(contentsOf: target.url, encoding: .utf8)
            entries = ProfileConfigStore.captured(entries, folderName: target.key,
                                                  diskText: text, now: now)
        }
        guard entries != before else { return }
        ProfileConfigStore.save(entries, to: url)
        // Ce que cette passe a changé, pas le total.
        let touched = ProfileConfigCapture.touchedCount(before: before, after: entries)
        let name = profilesStore.profile(with: profileId)?.name ?? ""
        log(String(format: localization.L(L10n.VM.profileConfigsCaptured), name, touched))
    }

    /// Réécrit le `config.json` mémorisé de chaque mod marqué ; sans texte,
    /// **pas touché** (adopté à la capture suivante). Idempotent, rejouable.
    func restoreProfileConfigs(for profileId: UUID) {
        guard !isGameRunning() else {
            log(localization.L(L10n.VM.profileConfigsSkippedGame), level: .warning)
            // R2 (spec §3.5) : desync marqué, sinon trou invisible.
            Self.profileConfigsDesyncedProfileId = profileId
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
            // Dossier disparu : rien écrit, entrée gardée.
            let modRoot = target.url.deletingLastPathComponent().path
            guard FileManager.default.fileExists(atPath: modRoot) else { continue }
            // Merge d'abord (spec §5.3) : garde les clés gagnées par une mise à jour
            // du mod ; illisible = verbatim.
            let diskText = try? String(contentsOf: target.url, encoding: .utf8)
            let result = diskText.flatMap {
                ConfigJSONMerge.mergedText(disk: $0, memorized: entry.text)
            }
            do {
                // Lecture seule fréquente (même remède que `recoverFile`).
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
        // Configs réécrits : rapport de raccourcis périmé (X66), même parc
        // inchangé.
        rescanKeybindsAfterConfigWrite()
        let name = profilesStore.profile(with: profileId)?.name ?? ""
        // Deux comptes : restauration fidèle (merge) contre repli.
        if merged > 0 {
            log(String(format: localization.L(L10n.VM.profileConfigsMerged), name,
                       Int64(verbatim), Int64(merged), Int64(reintroducedKeys)))
        } else {
            log(String(format: localization.L(L10n.VM.profileConfigsRestored), name, verbatim))
        }
    }

    // MARK: - R2 : reprise d'une application interrompue

    /// Après révélation de la fenêtre (point des liens `nxm://`) ;
    /// idempotent.
    func surfaceApplyRecoveryIfNeeded() {
        guard pendingApplyRecovery == nil else { return }
        pendingApplyRecovery = unresolvedApplyJournal
    }

    /// Fermer sans trancher : le journal reste, l'alerte revient.
    func dismissApplyRecovery() {
        pendingApplyRecovery = nil
    }

    /// Trancher **sans reprendre** (choix explicite) : disque intact, journal
    /// effacé, choix journalisé.
    func clearUnresolvedJournal(implicitKeepNamed name: String) {
        ProfileApplyJournalStore.clear(in: applyJournalDirectory)
        unresolvedApplyJournal = nil
        pendingApplyRecovery = nil
        log(String(format: self.localization.L(L10n.VM.profileRecoveryImplicitKeep), name), level: .warning)
    }

    /// Texte du dialogue : profil, date, mention d'un profil supprimé.
    var applyRecoveryDialogText: String? {
        guard let journal = unresolvedApplyJournal else { return nil }
        var text = String(format: self.localization.L(L10n.VM.profileRecoveryMessage),
                          journal.profileName,
                          journal.startedAt.formatted(date: .abbreviated, time: .shortened))
        if !recoveryProfileExists {
            text += " " + self.localization.L(L10n.VM.profileRecoveryProfileGone)
        }
        return text
    }

    var recoveryProfileExists: Bool {
        guard let journal = unresolvedApplyJournal else { return false }
        return modProfiles.contains { $0.id == journal.profileId }
    }

    /// « Reprendre l'application » avec la **restauration** des configs de
    /// l'entrant que le crash a avalée (la capture avait déjà couru).
    func resumeInterruptedApply() {
        let journal = pendingApplyRecovery ?? unresolvedApplyJournal
        // Dialogue fermé dès un geste, même refusé.
        if journal != nil { pendingApplyRecovery = nil }
        // Gardes dans `ProfileRecovery` (Core, 11 tests).
        switch ProfileRecovery.resume(journal: journal, profiles: modProfiles,
                                      isApplying: isApplyingProfile,
                                      gameRunning: { self.isGameRunning() }) {
        case .nothingToResume, .refused:
            return

        case .clearJournal(let name):
            clearUnresolvedJournal(implicitKeepNamed: name)

        case .refusedGameRunning(let name):
            let message = String(format: localization.L(L10n.VM.profileApplyRefusedGame), name)
            log(message, level: .warning)
            showModal(message: message)

        case .resume(let profileId):
            guard let profile = profilesStore.profile(with: profileId) else { return }
            profilesStore.setApplyingId(profileId)
            applyProfileToFilesystem(profile: profile) { [weak self] _ in
                self?.restoreProfileConfigs(for: profileId)
            }
        }
    }

    /// « Garder l'état actuel » : adoption explicite du disque.
    func keepCurrentDiskState() {
        let journal = pendingApplyRecovery ?? unresolvedApplyJournal
        guard case .settle(let name, let adopting) = ProfileRecovery.keepDiskState(
            journal: journal, active: activeProfileId) else { return }
        pendingApplyRecovery = nil
        clearUnresolvedJournal(implicitKeepNamed: name)
        if adopting { syncActiveProfileIds() }
    }

    /// Garde des entrées qui **appliquent un profil au disque** : refus jeu
    /// ouvert, et refus si le profil a un journal d'interruption. Permissif
    /// sans déplacement prévu.
    private func guardProfileApply(for profileId: UUID, name: String) -> Bool {
        guard activeProfileId == profileId || unresolvedApplyJournal?.profileId == profileId else {
            return true
        }
        if isGameRunning() {
            let message = String(format: self.localization.L(L10n.VM.profileApplyRefusedGame), name)
            log(message, level: .warning)
            showModal(message: message)
            return false
        }
        if let journal = unresolvedApplyJournal, journal.profileId == profileId {
            let message = String(format: self.localization.L(L10n.VM.profileEditBlockedRecovery), name)
            log(message, level: .warning)
            showModal(message: message)
            return false
        }
        return true
    }

    func applyProfile(id: UUID?, fingerprintChecked: Bool = false) {
        // Aiguillage dans `ProfileActivation` (Core, 16 tests).
        // ⚠️ `isGameRunning()` **en closure** : il informe le garde anti
        // double-lancement ; un test épingle cette paresse.
        let decision = ProfileActivation.decide(requested: id, profiles: modProfiles,
                                                active: activeProfileId,
                                                isApplying: isApplyingProfile,
                                                gameRunning: { self.isGameRunning() },
                                                journal: unresolvedApplyJournal,
                                                incomplete: incompletelyAppliedProfileIds)
        switch decision {
        case .refused:
            return

        case .refusedGameRunning(let name):
            let message = String(format: localization.L(L10n.VM.profileApplyRefusedGame), name)
            log(message, level: .warning)
            showModal(message: message)

        case .leave(let capturing, let clearingJournalNamed):
            if let capturing { captureProfileConfigs(for: capturing) }
            if let clearingJournalNamed {
                clearUnresolvedJournal(implicitKeepNamed: clearingJournalNamed)
            }
            syncProfileConfigsDesyncMarker(entering: nil)
            profilesStore.setActiveProfile(nil)
            saveProfiles()

        case .presentRecovery:
            pendingApplyRecovery = unresolvedApplyJournal

        case .resume(let profileId):
            guard let profile = profilesStore.profile(with: profileId) else { return }
            profilesStore.setApplyingId(profileId)
            applyProfileToFilesystem(profile: profile)

        case .adoptManualToggles:
            syncActiveProfileIds()

        case .activate(let profileId, let capturing, let clearingJournalNamed):
            guard let profile = profilesStore.profile(with: profileId) else { return }
            // A1-T9 — chiffrer les mises en pause avant tout effet.
            let pausedIDs = ProfileApplyPlan.pausedModIDs(applying: profile, to: mods)
            if !fingerprintChecked, !pausedIDs.isEmpty {
                guard !saveFingerprintPauseStore.isBusy else { return }
                profilesStore.setApplying(true)
                return saveFingerprintPauseStore.checkBeforePause(
                    subject: .profile(name: profile.name), modIDs: pausedIDs,
                    resume: { [weak self] in self?.profilesStore.setApplying(false)
                        self?.applyProfile(id: id, fingerprintChecked: true) },
                    abort: { [weak self] in self?.profilesStore.setApplying(false) })
            }
            // Capture AVANT tout : seule fenêtre où les réglages du sortant existent.
            if let capturing { captureProfileConfigs(for: capturing) }
            if let clearingJournalNamed {
                clearUnresolvedJournal(implicitKeepNamed: clearingJournalNamed)
            }
            syncProfileConfigsDesyncMarker(entering: profileId)
            profilesStore.setActiveProfile(profileId)
            saveProfiles()
            profilesStore.setApplyingId(profileId)
            // Restauration après déplacements et rescan.
            applyProfileToFilesystem(profile: profile) { [weak self] _ in
                self?.restoreProfileConfigs(for: profileId)
            }
            log(String(format: localization.L(L10n.VM.switchProfile), profile.name))
        }
    }

    /// Move mod folders to match the profile. Every move error is captured,
    /// logged and summarized in an alert, and the rescan still runs.
    /// - Parameter completion: après le rescan, avec le **nombre d'échecs**
    ///   (0 = complet) ; la bissection en dépend.
    private func applyProfileToFilesystem(profile: ModProfile,
                                          journaling: Bool = true,
                                          completion: ((_ moveFailures: Int) -> Void)? = nil) {
        // Application in progress: blocks a second one and the buttons.
        profilesStore.setApplying(true)
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")

        // Profile entries not installed (packs resolved to children) are
        // skipped by the moves but reported to the user.
        let snapshotMods = mods
        // Même définition que l'écran des mods manquants.
        let missingIds = ProfileDiagnostics.missingMods(in: profile,
                                                        installedUniqueIds: snapshotMods.allUniqueIds,
                                                        backupNames: [:],
                                                        nexusHints: [:]).map(\.uniqueId)

        // Plan arrêté **ici** sur l'instantané (`mods` est réécrit par le
        // scan) ; règle testée dans `ProfileApplyPlan`.
        let moves = ProfileApplyPlan.moves(applying: profile, to: snapshotMods)

        let profileName = profile.name
        let profileId = profile.id

        // R2 : journal écrit avant le premier déplacement, effacé au completion ;
        // présent = boucle morte en route. Bissection : `journaling: false`.
        if journaling {
            let journal = ProfileApplyJournal(profileId: profileId,
                                              profileName: profileName,
                                              startedAt: Date(),
                                              moves: moves)
            // Écriture échouée : journalisée ; la **prochaine** session perd le filet.
            if let err = ProfileApplyJournalStore.save(journal, in: applyJournalDirectory) {
                log(String(format: localization.L(L10n.VM.profileApplyJournalWriteFailed),
                           profileName, err.localizedDescription), level: .error)
            }
            unresolvedApplyJournal = journal
        }
        // Total connu : barre déterminée, publiée avant le dispatch.
        let total = moves.count
        profileApplyProgress = ProfileApplyProgress(done: 0, total: total, phase: .movingFolders)

        let events = ModFolderBulkMove.execute(moves, in: modsPath,
                                               skipMissingSource: false,
                                               progressStep: max(1, total / 100))
        Task { [weak self] in
            var anyEnabled = false
            var outcome: BulkMoveOutcome?
            for await event in events {
                guard let self else { continue }
                switch event {
                case .progress(let done, let totalMoves):
                    self.profileApplyProgress = ProfileApplyProgress(done: done,
                                                                     total: totalMoves,
                                                                     phase: .movingFolders)
                case .activated(let folderName):
                    self.modActivationTimestamps[folderName] = Date()
                    anyEnabled = true
                case .finished(let final):
                    outcome = final
                }
            }
            guard let self, let outcome else { return }
            let failedNames = outcome.failures.map(\.modName)
            if anyEnabled {
                Self.saveModActivationTimestamps(self.modActivationTimestamps)
            }
            for failure in outcome.failures {
                if let critical = failure.criticalLog { self.log(critical, level: .error) }
                let direction = failure.direction == .enable ? "→ activé" : "→ désactivé"
                self.log(String(format: self.localization.L(L10n.VM.applyProfileMoveFail),
                               failure.modName, direction, failure.message),
                         level: .error)
            }
            if !missingIds.isEmpty {
                let listing = missingIds.joined(separator: ", ")
                self.log(String(format: self.localization.L(L10n.VM.applyProfileMissing),
                               profileName, missingIds.count, listing), level: .warning)
            }
            // Phase de relecture du parc annoncée.
            self.profileApplyProgress = ProfileApplyProgress(done: total,
                                                             total: total,
                                                             phase: .rescanning)
            // Scan lourd HORS main (T10) ; reprise sur main dans l'ordre d'origine.
            // Dossier de jeu résolu ici, sur l'acteur.
            let resolvedGameDir = gameDir
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.scanMods(gameDir: resolvedGameDir)
                    continuation.resume()
                }
            }
            if journaling {
                ProfileApplyJournalStore.clear(in: self.applyJournalDirectory)
                self.unresolvedApplyJournal = nil
            }
            self.profileApplyProgress = nil
            if outcome.failures.isEmpty && missingIds.isEmpty {
                self.incompletelyAppliedProfileIds.remove(profileId)
                self.syncActiveProfileIds()
            } else {
                self.incompletelyAppliedProfileIds.insert(profileId)
            }
            self.profilesStore.endApplying()
            if !outcome.failures.isEmpty || !missingIds.isEmpty {
                let summary = self.profileApplyMessage(
                    profileName: profileName,
                    failedNames: failedNames,
                    missingIds: missingIds,
                    attempted: outcome.attempted,
                    failureCount: outcome.failures.count)
                self.showModal(message: summary)
                self.log(String(format: "Profile \"%@\" applied: %lld move failure(s), %lld missing mod(s)",
                               profileName, outcome.failures.count, missingIds.count),
                        level: .warning)
            }
            completion?(failedNames.count)
        }
    }

    /// Alert text for a problematic profile application, naming mods (lists
    /// capped with "+N more").
    private func profileApplyMessage(profileName: String, failedNames: [String],
                                     missingIds: [String], attempted: Int,
                                     failureCount: Int) -> String {
        let listLimit = 8
        var sections: [String] = []

        // Move failures: headline, then names.
        if !failedNames.isEmpty {
            let headline: String
            if attempted == failureCount {
                headline = String(format: localization.L(L10n.VM.applyProfileError), profileName, failureCount)
            } else {
                headline = String(format: localization.L(L10n.VM.applyProfilePartial), profileName, failureCount)
            }
            sections.append(self.truncatedList(headline: headline,
                                               names: failedNames, limit: listLimit))
        }

        // Missing mods — references in the profile that aren't installed.
        if !missingIds.isEmpty {
            let headline = String(format: localization.L(L10n.VM.applyProfileMissing),
                                  profileName, missingIds.count,
                                  missingIds.prefix(listLimit).joined(separator: ", "))
            let extra = missingIds.count > listLimit
                ? " (+\(missingIds.count - listLimit))"
                : ""
            sections.append(headline + extra)
        }

        return sections.joined(separator: "\n\n")
    }

    /// `headline` + truncated list ("+N more" after `limit`).
    private func truncatedList(headline: String, names: [String], limit: Int) -> String {
        let shown = names.prefix(limit).joined(separator: " • ")
        let extra = names.count > limit ? " (+\(names.count - limit))" : ""
        return headline + "\n" + shown + extra
    }

    /// Renomme un dossier dans `Mods/`, destination occupée comprise, pour les
    /// trois chemins de bascule. Travail disque dans
    /// `ModFolderRename.moveReplacingStaleDestination` (Core, P5-T9) ; l'échec
    /// d'un rollback **remonte** (`rollbackFailed`, `strandedAt`) et les
    /// appelants le journalisent.
    /// - Throws: `FolderToggleRefusal.folderClaimedByAnotherMod` si la
    ///   destination est à un **autre** mod ; `ModFolderRenameFailure` pour un
    ///   déplacement ou rollback en échec.
    nonisolated private func renameModFolder(from srcPath: String, to dstPath: String,
                                 destinationName: String, uniqueId: String,
                                 fm: FileManager) throws {
        try ModFolderRename.moveReplacingStaleDestination(from: srcPath, to: dstPath,
                                                          destinationName: destinationName,
                                                          uniqueId: uniqueId, fm: fm)
    }

    // MARK: - Règle de cadrage de la liste des mods
    //
    // Règle des mods montrés — et, depuis X57, de ceux sur lesquels agit la
    // bascule en masse : « what the user is looking at is what they act on »
    // (Stardrop). Une seule copie (X45). Pagination exclue : la bascule agit
    // sur tout le résultat filtré.

    /// `mod` or, for a group, any child satisfies `predicate`; shared by
    /// search and the issues filter.
    /// Façade **provisoire** vers `ModListScoping` (six sites dans
    /// `ModListView`).
    func matchesSelfOrAnyChild(_ mod: ModItem, _ predicate: (ModItem) -> Bool) -> Bool {
        ModListScoping.matchesSelfOrAnyChild(mod, predicate)
    }

    /// Même règle que la pastille d'anomalie (dépendances, erreurs du journal,
    /// manifestes sans identifiant).
    func hasIssues(_ mod: ModItem) -> Bool {
        anomaly(for: mod) != nil || nexusPageState(for: mod) != nil
    }

    func matchesSearch(_ mod: ModItem, filters: ModListFilters) -> Bool {
        ModListScoping.matchesSearch(mod, filters: filters)
    }

    func matchesCategory(_ mod: ModItem, filters: ModListFilters) -> Bool {
        ModListScoping.matchesCategory(mod, filters: filters,
                                       category: { self.category(for: $0) })
    }

    func matchesConfig(_ mod: ModItem, filters: ModListFilters) -> Bool {
        ModListScoping.matchesConfig(mod, filters: filters)
    }

    func matchesFavorites(_ mod: ModItem, filters: ModListFilters) -> Bool {
        ModListScoping.matchesFavorites(mod, filters: filters, favorites: favoriteMods)
    }

    func matchesBlacklisted(_ mod: ModItem, filters: ModListFilters) -> Bool {
        ModListScoping.matchesBlacklisted(mod, filters: filters, blacklisted: blacklistedMods)
    }

    func matchesTranslation(_ mod: ModItem, _ scope: FrenchTranslationScope) -> Bool {
        ModListScoping.matchesTranslation(mod, scope, state: translationScopingState)
    }

    /// Les trois magasins de couverture (copies de références, pas un
    /// parcours).
    private var translationScopingState: ModListScoping.TranslationState {
        .init(coverage: frenchCoverageByMod, stale: staleTranslationMods,
              outdatedKeys: outdatedKeysByMod)
    }

    /// Entrées du cadrage, assemblées **ici seulement** (en vue, un `@State`
    /// retiendrait le VM). Capture **forte** voulue : consommées dans un appel
    /// synchrone ; un `weak` changerait un plantage impossible en réponses
    /// fausses et muettes.
    private var scopingInputs: ModListScoping.Inputs {
        .init(category: { self.category(for: $0) },
              sizeOnDisk: { self.sizeOnDisk(of: $0) },
              favorites: favoriteMods,
              blacklisted: blacklistedMods,
              translation: translationScopingState,
              activationDates: modActivationTimestamps)
    }

    /// Liste cadrée : six filtres composés, puis triée — source de
    /// `ModListView.filteredMods` et de `toggleAllMods` ; scope et pagination
    /// par-dessus.
    func mods(matching filters: ModListFilters) -> [ModItem] {
        let inputs = scopingInputs
        let filtered = mods.filter { ModListScoping.matches($0, filters: filters, inputs: inputs) }
        return ModListScoping.sorted(filtered, by: filters.sort, inputs: inputs)
    }

    /// Liste cadrée restreinte au scope (« Tous / Activés / En pause /
    /// Problèmes ») : l'ensemble exact de la bascule en masse (X57). **Pas**
    /// de partition actifs/pause sous « Tous » : elle écraserait le tri.
    func scopedMods(from filtered: [ModItem], scope: ModFilter) -> [ModItem] {
        ModListScoping.scoped(filtered, scope: scope, hasAnomaly: { self.hasIssues($0) }, pendingUpdates: { .current(self) })
    }


    /// Enable or disable every mod of the current framing
    /// (`modList.filters`, pas les 949 dossiers du parc), off main. Same
    /// collision guard as `performToggle` : un dossier à destination n'est
    /// écarté que s'il porte l'identité du mod, sinon refus compté. Progress
    /// after every move; timestamps only for moved mods.
    @MainActor
    func toggleAllMods(enable: Bool, fingerprintChecked: Bool = false) {
        // No re-entry (same paths), and not while unit toggles are queued: the
        // guard prevents the collision the disk checks would only contain.
        guard bulkToggleProgress == nil, !isToggling, pendingToggles.isEmpty,
              !saveFingerprintPauseStore.isBusy else { return }

        // X57 : ensemble du cadrage courant, figé ici sur main.
        let framing = modList.filters
        let modsToMove = scopedMods(from: mods(matching: framing), scope: framing.scope)
            .filter { $0.isEnabled != enable }
        guard !modsToMove.isEmpty else {
            log(enable ? localization.L(L10n.Mods.allAlreadyEnabled) : localization.L(L10n.Mods.allAlreadyDisabled))
            return
        }

        // A1-T9 — chiffrer ce que l'ensemble mis en pause laisse dans les saves.
        if !enable, !fingerprintChecked, !modsToMove.allUniqueIds.isEmpty {
            return saveFingerprintPauseStore.checkBeforePause(
                subject: .mods(count: modsToMove.count), modIDs: modsToMove.allUniqueIds,
                resume: { [weak self] in self?.toggleAllMods(enable: false, fingerprintChecked: true) },
                abort: {})
        }
        let total = modsToMove.count
        bulkToggleEnabling = enable
        bulkToggleProgress = (done: 0, total: total)

        let gameDir = self.gameDir
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")

        // Moves depuis l'instantané (même primitive que le plan de profil).
        let moves = modsToMove.map { mod in
            ProfileApplyPlan.Move(
                folderName: mod.folderName, modName: mod.name,
                uniqueId: mod.uniqueId,
                source: mod.physicalFolderName,
                destination: enable ? mod.folderName : "." + mod.folderName,
                direction: enable ? .enable : .disable)
        }
        let events = ModFolderBulkMove.execute(moves, in: modsPath,
                                               skipMissingSource: true,
                                               progressStep: 1)

        // `Task` hérite de `@MainActor` ; l'arrière-plan vit dans l'exécutant.
        Task { [weak self] in
            var anyEnabled = false
            var outcome: BulkMoveOutcome?
            for await event in events {
                guard let self else { continue }
                switch event {
                case .progress(let doneSoFar, _):
                    self.bulkToggleProgress = (done: doneSoFar, total: total)
                case .activated(let folderName):
                    self.modActivationTimestamps[folderName] = Date()
                    anyEnabled = true
                case .finished(let final):
                    outcome = final
                }
            }
            guard let self, let outcome else { return }
            let movedCount = outcome.movedCount

            if anyEnabled {
                Self.saveModActivationTimestamps(self.modActivationTimestamps)
            }
            for failure in outcome.failures {
                if let critical = failure.criticalLog { self.log(critical, level: .error) }
                let direction = failure.direction == .enable ? "→ activé" : "→ désactivé"
                self.log(String(format: "%@ %@: %@", failure.modName, direction, failure.message),
                         level: .error)
            }
            // Rescan to reflect disk after partial failures, then
            // syncActiveProfileIds. Scan hors main (T10), dossier de jeu résolu ici.
            let resolvedGameDir = gameDir
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.scanMods(gameDir: resolvedGameDir)
                    continuation.resume()
                }
            }
            self.bulkToggleProgress = nil
            self.syncActiveProfileIds()
            if outcome.failures.isEmpty {
                self.log(String(format: enable ? self.localization.L(L10n.Mods.enabledAllCount) : self.localization.L(L10n.Mods.disabledAllCount),
                               movedCount))
            } else if outcome.attempted == outcome.failures.count {
                self.showModal(message: String(format: self.localization.L(L10n.Mods.bulkToggleFailed), outcome.failures.count))
            } else {
                self.showModal(message: String(format: self.localization.L(L10n.Mods.bulkTogglePartial), movedCount, outcome.failures.count))
                self.log(String(format: enable ? self.localization.L(L10n.Mods.enabledAllCount) : self.localization.L(L10n.Mods.disabledAllCount),
                               movedCount), level: .warning)
            }
        }
    }

    /// Oublie ce que les magasins persistés savaient d'un mod supprimé (X55) :
    /// **on efface tout** (2026-09-04). Sinon « Je l'ai » dans la vitrine, et
    /// un dossier réutilisé héritait du drapeau de config par profil. Un pack
    /// emporte ses composants, pas le voisin au nom proche
    /// (`ModRemovalPurge`). Chaque magasin réécrit **seulement s'il change**.
    private func forgetStores(of mod: ModItem) {
        let folder = mod.folderName
        // X107 — ici, pas dans la seule branche de succès : un dossier déjà
        // absent laissait favori et « à écarter » orphelins.
        if ModRemovalPurge.purge(&favoriteMods, removing: folder) {
            Self.saveFavoriteMods(favoriteMods)
        }
        if ModRemovalPurge.purge(&blacklistedMods, removing: folder) {
            Self.saveBlacklistedMods(blacklistedMods)
        }
        // Sinon croissance indéfinie.
        errorHistory.forget(mod: folder)
        if let store = TranslationBaseline.defaultDirectory() {
            try? TranslationBaseline.remove(modFolderName: folder, in: store)
        }
        invalidateFrenchCoverage(for: folder)
        if ModRemovalPurge.purge(&profileManagedConfigMods, removing: folder) {
            Self.saveProfileManagedConfigMods(profileManagedConfigMods)
        }
        if ModRemovalPurge.purge(&modActivationTimestamps, removing: folder) {
            Self.saveModActivationTimestamps(modActivationTimestamps)
        }
        nexusMetadata.purgeMod(folderName: folder)
        // Retrait sûr même avec un id Nexus partagé (58 cas) :
        // `installedNexusIds()` fait l'union avec le disque.
        if let id = Int(resolvedNexusModId(for: mod)) {
            recentNexusInstalls.remove(id)
        }
        forgetTranslations(of: folder)

        // C2-T4 — deltas du mod et de ses composants (fichiers `<uniqueId>.json`),
        // sinon un composant réinstallé ressusciterait un delta mort (X55).
        if let dir = ModUpdateKeyDeltaStore.defaultDirectory() {
            ModUpdateKeyDeltaStore.removeAll(
                uniqueIds: [mod.uniqueId] + (mod.children ?? []).map(\.uniqueId),
                directory: dir)
            // Invalider les caches (deux dossiers d'un même UniqueID au parc).
            updateKeyDeltasRevision += 1
        }
    }

    /// X69 — oublie aussi le registre des traductions et greffes
    /// (`forgetEverything` : l'orphelin du parc vivait dans `addonsByHost`).
    /// **Les originaux mis à l'abri partent avec** (seuls pointeurs), mais
    /// seulement **sous la racine des sauvegardes**.
    private func forgetTranslations(of folder: String) {
        let strandedOriginals = installedTranslations.entries(forHost: folder)
            .flatMap { $0.replacedFiles.values }
        var forgotten = false
        translationHub.mutateInstalled { forgotten = $0.forgetEverything(host: folder) }
        guard forgotten else { return }
        if !InstalledTranslationStore.save(installedTranslations) {
            log("Registre des traductions : \(folder) retiré en mémoire seulement",
                level: .warning)
        }
        guard let root = InstalledTranslationStore.backupRoot?.standardizedFileURL.path else { return }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        // Échec dit une fois, jamais avalé.
        var failed: [String] = []
        for path in strandedOriginals
        where URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(prefix) {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch CocoaError.fileNoSuchFile {
                // Déjà parti : c'est le résultat voulu.
            } catch {
                failed.append((path as NSString).lastPathComponent)
            }
        }
        if !failed.isEmpty {
            log("Originaux de traduction non retirés pour \(folder) : "
                + failed.joined(separator: ", "), level: .warning)
        }
    }

    func deleteMod(_ mod: ModItem) {
        guard !gameDir.isEmpty else {
            showModal(message: localization.L(L10n.Settings.gameDirNotSet))
            return
        }

        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        // Physical path (dot prefix when disabled).
        let modPath = (modsPath as NSString).appendingPathComponent(mod.physicalFolderName)

        let fm = FileManager.default
        guard fm.fileExists(atPath: modPath) else {
            showModal(message: localization.L(L10n.Mods.deleteNotFound))
            // Dossier disparu hors de l'app : purge ici aussi. Pas le balayage que
            // X25 interdit : l'utilisateur a demandé cette suppression nommément.
            forgetStores(of: mod)
            let resolvedGameDir = gameDir
            DispatchQueue.global(qos: .userInitiated).async {
                self.scanMods(gameDir: resolvedGameDir)
            }
            return
        }

        // Row spinner until the rescan republishes `mods`.
        pendingDeleteFolder = mod.folderName

        do {
            // X103-B — « supprimer » met en corbeille, hors de `Mods/` (X115).
            // Purge = geste explicite de l'Entretien (X25). Feuille **logique**.
            let leaf = (mod.folderName as NSString).lastPathComponent
            if let failure = ModTrash.trash(
                modsPath: modsPath, trashRoot: ModTrash.root(gameDir: gameDir), stamp: ModTrash.makeStamp(),
                items: [.init(physical: mod.physicalFolderName, logicalLeaf: leaf)]).failed.first {
                throw failure.error
            }
            // Registry pruned by the next scan; other stores by `forgetStores` (X107).
            forgetStores(of: mod)
            log(String(format: localization.L(L10n.Mods.deletedLog), mod.name))
            let resolvedGameDir = gameDir
            DispatchQueue.global(qos: .userInitiated).async {
                self.scanMods(gameDir: resolvedGameDir)
                DispatchQueue.main.async {
                    self.syncActiveProfileIds()
                    self.pendingDeleteFolder = nil
                }
            }
        } catch {
            // `ModTrash.trash` a déjà retiré l'événement resté vide.
            pendingDeleteFolder = nil
            log(String(format: "%@: %@",
                       localization.L(L10n.Mods.deleteFailed), error.localizedDescription),
                level: .error)
            showModal(message: String(format: localization.L(L10n.Mods.deleteFailed),
                                      error.localizedDescription))
        }
    }

    // MARK: - Corbeille des mods supprimés (X103-B)

    /// Événements de corbeille, récents d'abord, lus à la demande.
    var trashEvents: [ModTrash.Event] { maintenanceStore.trashEvents }

    func refreshTrash() {
        guard !gameDir.isEmpty else { return }
        let gameDir = self.gameDir
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = ModTrash.snapshot(gameDir: gameDir)
            DispatchQueue.main.async {
                guard let self else { return }
                if !snapshot.migrationFailures.isEmpty {
                    self.log("Trash migration: \(snapshot.migrationFailures.joined(separator: ", ")) left in Mods/.",
                             level: .warning)
                }
                self.maintenanceStore.setTrashEvents(snapshot.events)
                self.maintenanceStore.setQuarantineItemCount(snapshot.quarantined)
            }
        }
    }

    /// Remet un mod en `Mods/.<nom>`, **désactivé** (§5.6).
    func restoreTrashEntry(event: String, entry: String) {
        restoreFromTrash(event: event) {
            ModTrash.restoreEvent(modsPath: $0, trashRoot: $1, event: event, entries: [entry],
                                  stamp: ModTrash.makeStamp())
        }
    }

    /// « Tout remettre » : l'événement revient en pause, un rescan (X112).
    func restoreTrashEvent(_ event: String) {
        restoreFromTrash(event: event) {
            ModTrash.restoreEvent(modsPath: $0, trashRoot: $1, event: event, stamp: ModTrash.makeStamp())
        }
    }

    /// Trajet commun des remises, hors main (gel ~960 mods, 2026-09-14).
    private func restoreFromTrash(event: String,
                                  _ work: @escaping @Sendable (String, String) -> ModTrash.TrashResult) {
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let trashRoot = ModTrash.root(gameDir: gameDir)
        // Event non marqué (quarantaine, nom forgé) : pas une corbeille.
        guard ModTrash.isUserEvent(trashRoot: trashRoot, event: event) else {
            showModal(message: String(format: localization.L(L10n.Maintenance.trashFailed2), event))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = work(modsPath, trashRoot)
            DispatchQueue.main.async {
                guard let self else { return }
                let loc = self.localization
                if result.moved.count > 1 {
                    self.log(String(format: loc.L(L10n.Maintenance.trashRestoredEventLog),
                                    Int64(result.moved.count)))
                } else if let entry = result.moved.first {
                    self.log(String(format: loc.L(L10n.Maintenance.trashRestoredLog), entry))
                }
                if let failure = result.failed.first {
                    self.showModal(message: String(
                        format: self.localization.L(L10n.Maintenance.trashFailed),
                        failure.error.localizedDescription))
                }
                guard !result.moved.isEmpty else { return }
                self.refreshTrash()
                let resolvedGameDir = self.gameDir
                DispatchQueue.global(qos: .userInitiated).async {
                    self.scanMods(gameDir: resolvedGameDir)
                }
            }
        }
    }

    /// Purge nominative, toujours après confirmation.
    func purgeTrashEntry(event: String, entry: String) {
        let trashRoot = ModTrash.root(gameDir: gameDir)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try ModTrash.purgeEntry(trashRoot: trashRoot, event: event, entry: entry)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.log(String(format: self.localization.L(L10n.Maintenance.trashPurgedLog),
                                    entry))
                    self.refreshTrash()
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.showModal(message: String(
                        format: self.localization.L(L10n.Maintenance.trashFailed),
                        error.localizedDescription))
                }
            }
        }
    }

    /// Vide la corbeille ; compte annoncé tiré du même `trashEvents`.
    func purgeAllTrash() {
        let trashRoot = ModTrash.root(gameDir: gameDir)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let removed = try ModTrash.purgeAll(trashRoot: trashRoot)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.log(String(format: self.localization.L(L10n.Maintenance.trashEmptiedLog), removed))
                    self.refreshTrash()
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.showModal(message: String(
                        format: self.localization.L(L10n.Maintenance.trashFailed),
                        error.localizedDescription))
                }
            }
        }
    }

    /// Call this after any toggleMod so the profile stays up to date.
    func syncActiveProfileIds() {
        let decision = ProfileRecovery.adoptDiskState(active: activeProfileId, profiles: modProfiles, // R2, X109
            journal: unresolvedApplyJournal, modsFolderWasReadable: scanStore.modsFolderWasReadable)
        guard case .adopt(let id) = decision else {
            if case .blockedByJournal(let name) = decision {
                log(String(format: localization.L(L10n.VM.profileAdoptionBlockedJournal), name), level: .warning)
            } else if decision == .blockedUnreadable {
                log("Dossier Mods/ illisible : le profil actif n'adopte pas une liste vide", level: .warning)
            }
            return
        }

        let enabledMods = mods.flattenedMods.filter(\.isEnabled).filter { !$0.uniqueId.isEmpty }

        profilesStore.mutateProfile(with: id) {
            $0.enabledModIds = enabledMods.map(\.uniqueId)
        }
        // Nom et id Nexus rafraîchis (traces après désinstallation) ; les mods
        // sortis du profil sont oubliés.
        profilesStore.mutateProfile(with: id) {
            $0.modMetadata = ProfileFactory.metadata(of: enabledMods)
        }
        saveProfiles()
        // État du disque adopté : plus d'écart à protéger.
        incompletelyAppliedProfileIds.remove(id)
    }

    // MARK: - Entretien (X25)

    /// Inventaire d'entretien, **une** traversée des sauvegardes (0,86 s pour
    /// 17 628 fichiers) : hors main, avec témoin.
    func buildMaintenanceReport() {
        guard maintenanceStore.beginBuilding() else { return }
        // X74 — en-têtes de packs compris : id Nexus et catégorie se posent sur
        // la fiche d'un pack.
        let installedFolders = mods.preferenceKeyableFolders
        // X70 — parc vide : le dire, sinon « rien à nettoyer » cache « rien lu ».
        if installedFolders.isEmpty {
            log("Entretien : aucun mod lu (dossier de jeu introuvable, ou "
                + "balayage en cours) — les clés de préférences ne sont pas jugées",
                level: .warning)
        }
        // X76 — état de lecture de l'index relevé **avant** la passe, même raison.
        let installRead = ModInstallBackupManager.shared.loadBackupsWithIndexState()
        if !installRead.indexWasReadable {
            log(self.localization.L(L10n.Maintenance.indexUnreadable), level: .warning)
        }
        let translationPathsByHost = installedTranslationRelativePaths()
        // Valeurs lues sur l'acteur avant la file (L2) ; lecture lourde dedans.
        let modsRoot = (gameDir as NSString).appendingPathComponent("Mods")
        let preferenceKeys = maintenancePreferenceKeys()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let report = Self.readMaintenanceReport(
                installBackups: installRead.backups,
                installIndexWasReadable: installRead.indexWasReadable,
                installBackupsRoot: ModInstallBackupManager.shared.backupsDirectory,
                configBackups: ModConfigBackupManager.shared.loadBackups(),
                configBackupsRoot: ModConfigBackupManager.shared.backupsDirectory,
                modsRoot: modsRoot,
                installedFolders: installedFolders,
                userTranslationPathsByHost: translationPathsByHost,
                preferenceKeys: preferenceKeys)
            DispatchQueue.main.async {
                self.maintenanceStore.setReport(report)
                self.maintenanceStore.endBuilding()
            }
        }
    }

    /// Clés des six magasins indexés par dossier (quatre de X55, + favoris et
    /// « à écarter », X107).
    private func maintenancePreferenceKeys() -> Set<String> {
        MaintenanceInventory.folderKeyedPreferenceKeys(
            favorites: favoriteMods,
            blacklisted: blacklistedMods,
            profileManagedConfigs: profileManagedConfigMods,
            activationTimestamps: modActivationTimestamps.keys,
            nexusModIds: nexusCustomModIds.keys,
            nexusCategories: nexusCustomCategories.keys)
    }

    /// Chemins des traductions et greffes posées par **l'app**, par hôte (une
    /// traduction d'auteur ne protège rien). ⚠️ Relatifs à **`Mods/`**, contre
    /// une sauvegarde relative à sa racine : comparaison par suffixe,
    /// **bornée à l'hôte** (X75 : 59 faux). Voir
    /// `MaintenanceInventory.classifyUserFile`.
    private func installedTranslationRelativePaths() -> [String: Set<String>] {
        let registry = InstalledTranslationStore.load()
        var paths: [String: Set<String>] = [:]
        for (host, entry) in registry.byHost {
            paths[host, default: []].formUnion(entry.files)
        }
        for (host, addons) in registry.addonsByHost {
            for addon in addons {
                paths[host, default: []].formUnion(addon.files)
            }
        }
        return paths
    }

    /// Lecture statique, sans `self` ; `nonisolated` (L2).
    nonisolated private static func readMaintenanceReport(
        installBackups: [ModInstallBackup],
        installIndexWasReadable: Bool,
        installBackupsRoot: URL,
        configBackups: [ModConfigBackup],
        configBackupsRoot: URL,
        modsRoot: String,
        installedFolders: Set<String>,
        userTranslationPathsByHost: [String: Set<String>],
        preferenceKeys: Set<String>
    ) -> MaintenanceInventory.Report {
        let fm = FileManager.default
        var entries: [MaintenanceInventory.BackupEntry] = []
        var protections: [String: MaintenanceInventory.Protection] = [:]
        var missingMods: Set<String> = []

        for backup in installBackups {
            let root = URL(fileURLWithPath: backup.backupPath)
            guard let (bytes, files) = Self.walkBackup(
                root: root,
                hostTranslationPaths: userTranslationPathsByHost[backup.originalFolderName] ?? [])
            else { continue }
            // Nom de session via le manager : même règle que la suppression.
            let session = ModInstallBackupManager.shared
                .backupDirectory(of: backup).lastPathComponent
            let entry = MaintenanceInventory.BackupEntry(
                id: session, modFolder: backup.originalFolderName,
                timestamp: backup.timestamp, sizeBytes: bytes, userFiles: files)
            entries.append(entry)
            let installed = Self.installedState(of: backup.originalFolderName,
                                                modsRoot: modsRoot, userFiles: files)
            protections[session] = MaintenanceInventory.protection(of: entry,
                                                                   installed: installed)
            if installed.presentFiles == nil { missingMods.insert(session) }
        }

        let onDisk = Set((try? fm.contentsOfDirectory(atPath: installBackupsRoot.path))?
            .filter { !$0.hasPrefix(".") } ?? [])
        let configBytes = configBackups.reduce(Int64(0)) { total, backup in
            total + (Self.walkBackup(root: configBackupsRoot
                .appendingPathComponent(backup.folderName),
                hostTranslationPaths: [])?.0 ?? 0)
        }

        return MaintenanceInventory.Report(
            backups: entries,
            protections: protections,
            configBackupCount: configBackups.count,
            configBackupBytes: configBytes,
            orphanSessions: MaintenanceInventory.orphanSessions(
                onDisk: onDisk, referenced: Set(entries.map(\.id)),
                indexWasReadable: installIndexWasReadable),
            stalePreferenceKeys: MaintenanceInventory.stalePreferenceKeys(
                preferenceKeys, installedFolders: installedFolders),
            missingMods: missingMods)
    }

    /// Taille et fichiers utilisateur en **une** traversée, `nil` si absent.
    /// Classification bornée à l'hôte (X75). `nonisolated` (L2).
    nonisolated private static func walkBackup(root: URL, hostTranslationPaths: Set<String>)
    -> (Int64, [MaintenanceInventory.UserFile])? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue
        else { return nil }
        guard let walker = fm.enumerator(at: root,
                                         includingPropertiesForKeys: [.fileSizeKey,
                                                                      .isRegularFileKey])
        else { return nil }
        var bytes: Int64 = 0
        var files: [MaintenanceInventory.UserFile] = []
        // ⚠️ `resolvingSymlinksInPath()` d'abord : l'énumérateur rend
        // `/private/var…`.
        let base = root.resolvingSymlinksInPath().path + "/"
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            bytes += Int64(values?.fileSize ?? 0)
            let relative = url.resolvingSymlinksInPath().path
                .replacingOccurrences(of: base, with: "")
            if let kind = MaintenanceInventory.classifyUserFile(
                relativePath: relative, hostTranslationPaths: hostTranslationPaths) {
                files.append(.init(relativePath: relative, kind: kind))
            }
        }
        return (bytes, files)
    }

    /// État actuel du mod, restreint aux chemins utiles ; `nil` si absent
    /// (actif ou en pause). `nonisolated` (L2).
    nonisolated private static func installedState(of folderName: String, modsRoot: String,
                                       userFiles: [MaintenanceInventory.UserFile])
    -> MaintenanceInventory.InstalledState {
        let fm = FileManager.default
        guard let current = ModRootResolver.physicalRoot(of: folderName, modsRoot: modsRoot) else {
            return .init(presentFiles: nil)
        }
        let present = userFiles.filter {
            fm.fileExists(atPath: (current as NSString).appendingPathComponent($0.relativePath))
        }
        return .init(presentFiles: Set(present.map(\.relativePath)))
    }

    /// Met à la corbeille les sauvegardes écartées par `keepPerMod` (règle
    /// dans `MaintenanceInventory.plan`), rend leur nombre. **Corbeille** :
    /// l'écran dit que l'espace revient après vidage.
    @discardableResult
    func purgeInstallBackups(keepPerMod: Int) -> Int {
        guard let report = maintenanceReport else { return 0 }
        let plan = MaintenanceInventory.plan(keepPerMod: keepPerMod,
                                             entries: report.backups,
                                             protections: report.protections)
        guard !plan.doomed.isEmpty else { return 0 }
        let doomedIds = Set(plan.doomed.map(\.id))
        var removed = 0
        // Via le manager : l'index est la source de vérité.
        let manager = ModInstallBackupManager.shared
        for backup in manager.loadBackups() {
            let sessionDir = manager.backupDirectory(of: backup)
            guard doomedIds.contains(sessionDir.lastPathComponent) else { continue }
            do {
                try ModZipInstaller.trashItemGrantingWriteAccess(atPath: sessionDir.path)
                try? manager.deleteBackup(backup)
                removed += 1
            } catch {
                log(String(format: localization.L(L10n.Maintenance.trashFailed),
                           backup.modMetadata.name, error.localizedDescription),
                    level: .warning)
            }
        }
        log(String(format: localization.L(L10n.Maintenance.purgedLog), removed,
                   ByteCountFormatter.string(fromByteCount: plan.freedBytes,
                                             countStyle: .file)))
        buildMaintenanceReport()
        return removed
    }

    /// Retire sessions sans index et clés sans mod — le « nettoyage explicite »
    /// de **X25** (bouton, jamais au lancement).
    @discardableResult
    func cleanStaleMaintenanceEntries() -> Int {
        guard let report = maintenanceReport else { return 0 }
        var removed = 0
        let root = ModInstallBackupManager.shared.backupsDirectory
        for session in report.orphanSessions {
            do {
                try ModZipInstaller.trashItemGrantingWriteAccess(
                    atPath: root.appendingPathComponent(session).path)
                removed += 1
            } catch {
                log(String(format: localization.L(L10n.Maintenance.trashFailed), session,
                           error.localizedDescription), level: .warning)
            }
        }
        for key in report.stalePreferenceKeys {
            if ModRemovalPurge.purge(&favoriteMods, removing: key) {
                Self.saveFavoriteMods(favoriteMods)
            }
            if ModRemovalPurge.purge(&blacklistedMods, removing: key) {
                Self.saveBlacklistedMods(blacklistedMods)
            }
            if ModRemovalPurge.purge(&profileManagedConfigMods, removing: key) {
                Self.saveProfileManagedConfigMods(profileManagedConfigMods)
            }
            if ModRemovalPurge.purge(&modActivationTimestamps, removing: key) {
                Self.saveModActivationTimestamps(modActivationTimestamps)
            }
            nexusMetadata.purgeMod(folderName: key)
            removed += 1
        }
        log(String(format: localization.L(L10n.Maintenance.cleanedLog), removed))
        buildMaintenanceReport()
        return removed
    }

    /// Mod absent : pas de dossier à fabriquer ; montrer le fichier dans le
    /// Finder.
    func revealProtectedBackup(atPath path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Retire une sauvegarde protégée à la demande, par la corbeille (seule
    /// copie).
    @discardableResult
    func purgeProtectedBackup(session: String) -> Bool {
        let manager = ModInstallBackupManager.shared
        do {
            try ModZipInstaller.trashItemGrantingWriteAccess(
                atPath: manager.backupsDirectory.appendingPathComponent(session).path)
        } catch {
            log(String(format: localization.L(L10n.Maintenance.trashFailed), session,
                       error.localizedDescription), level: .warning)
            return false
        }
        for backup in manager.loadBackups()
        where manager.backupDirectory(of: backup).lastPathComponent == session {
            try? manager.deleteBackup(backup)
        }
        buildMaintenanceReport()
        return true
    }

    /// Sauvegardes d'origine par session (le `Report` n'a que l'essentiel).
    private func maintenanceBackupsBySession() -> [String: ModInstallBackup] {
        let manager = ModInstallBackupManager.shared
        return Dictionary(manager.loadBackups().map {
            (manager.backupDirectory(of: $0).lastPathComponent, $0)
        }, uniquingKeysWith: { first, _ in first })
    }

    /// Seules copies remettables (mod encore là), par `SoleCopyFile.id`.
    /// Absente si sauvegarde ou mod a disparu : Finder seulement.
    func maintenanceRecoverableFiles(_ files: [MaintenanceInventory.SoleCopyFile])
    -> [String: RecoverableFile] {
        let bySession = maintenanceBackupsBySession()
        let modsRoot = (gameDir as NSString).appendingPathComponent("Mods")
        var found: [String: RecoverableFile] = [:]
        for file in files where !file.isGone {
            guard let backup = bySession[file.session],
                  let installedRoot = ModRootResolver.physicalRoot(
                      of: backup.originalFolderName, modsRoot: modsRoot) else { continue }
            found[file.id] = RecoverableFile(
                folderName: backup.originalFolderName,
                modName: backup.modMetadata.name,
                relativePath: file.relativePath,
                backupPath: (backup.backupPath as NSString).appendingPathComponent(file.relativePath),
                installedPath: (installedRoot as NSString).appendingPathComponent(file.relativePath),
                installedRoot: installedRoot,
                reason: .absentFromInstall)
        }
        return found
    }

    /// Chemin dans la sauvegarde, pour le Finder.
    func maintenanceProtectedFilePath(session: String, relativePath: String) -> String? {
        guard let backup = maintenanceBackupsBySession()[session] else { return nil }
        return (backup.backupPath as NSString).appendingPathComponent(relativePath)
    }
}

// MARK: - L10nResolver
//
// `SaveFarmNameResolver` consomme un `L10nResolver` (Core) ; la
// conformité vit sur `LocalizationStore`.
