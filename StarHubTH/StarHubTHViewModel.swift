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

    /// Description (`mods/{id}.json`) + full changelog (`changelogs.json`) via
    /// the existing Nexus client. `nil` if the description fails, so the
    /// fallback stays; an empty changelog is fine.
    private func fetchModDetailRemote(modId: Int, completion: @escaping (ModDetailRaw?) -> Void) {
        // Règle de composition en Core, testée.
        ModDetailRefresh.fetch(
            modId: modId,
            fetchDescription: { NexusUpdateChecker.shared.fetchRawDescription(modId: $0, completion: $1) },
            fetchChangelogs: { NexusUpdateChecker.shared.fetchChangelogs(modId: $0, completion: $1) },
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
        return DependencyTreeBuilder.build(roots) { [weak self] uid in
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

    /// Shared completion for both Nexus download entry points: hops to main,
    /// clears the progress flag, and on success stashes the downloaded zip +
    /// its Nexus source for the install sheet, or surfaces a localized error.
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
                // Annuler son propre téléchargement n'est pas une panne : une
                // alerte sur un geste volontaire serait du bruit. La ligne de
                // journal, elle, garde la trace de ce qui n'a pas été installé.
                self.log(self.nexusDownloadLogMessage(named: L10n.VM.nexusDlCancelledNamed,
                                                      plain: L10n.VM.nexusDlCancelled,
                                                      modId: modId))
            case .failed(let message):
                // Résolu avec le bundle **vivant** du ViewModel, qui suit un
                // changement de langue en session — là où `errorDescription`
                // passe par `NSLocalizedString`. Même table, deux résolveurs.
                let text = message.resolved { self.localization.L($0) }
                self.showModal(message: text)
                self.log(text, level: .warning)
            }
            // Fin d'un téléchargement sans feuille ouverte (échec,
            // annulation) : le créneau est libre, la file peut reprendre.
            // Sur succès, `pendingDownloadedZip` est déjà posé et le garde
            // retient le suivant jusqu'à la fermeture de la feuille.
            self.drainQueuedNexusDownloads()
        }
    }

    /// Relève la progression du téléchargement en cours.
    ///
    /// Appelée depuis la file de délégué d'`URLSession`, donc **hors du fil
    /// principal** : le saut est explicite, sans quoi l'état du store de
    /// téléchargement serait muté depuis un autre fil.
    ///
    /// `expected` vaut `-1` quand le serveur n'annonce pas la taille — le cas
    /// est fréquent sur un CDN. `DownloadProgress` le traduit en « taille
    /// inconnue » : ni pourcentage, ni temps restant, seulement le volume et
    /// le débit, qui sont vrais.
    nonisolated private func noteNexusDownloadProgress(received: Int64, expected: Int64,
                                                       modId: Int) {
        // Seule la référence du store traverse (écritures toutes sur main) :
        // le `nonisolated(unsafe)` vit désormais sur la propriété (L2).
        nonisolated(unsafe) let store = self.downloadStore
        DispatchQueue.main.async {
            store.noteProgress(received: received, expected: expected, modId: modId)
        }
    }

    /// Remet les quatre témoins du téléchargement au repos.
    ///
    /// Une seule fonction pour les quatre : ils étaient déjà remis à zéro à
    /// trois endroits différents, et le jour où l'un d'eux serait oublié,
    /// `rejectNexusDownloadIfBusy` condamnerait le bouton pour la session.
    @MainActor
    private func clearNexusDownloadState() {
        downloadStore.endDownload()
    }

    /// Annule le téléchargement en cours. Sans effet s'il n'y en a pas.
    ///
    /// Ne remet rien à zéro ici : `URLSession` rapportera l'annulation par le
    /// chemin d'échec habituel, et c'est lui qui doit conclure. Le faire des
    /// deux côtés rouvrirait la porte à un état remis au repos pendant qu'un
    /// transfert continue.
    @MainActor
    func cancelNexusDownload() {
        downloadStore.cancel()
    }

    /// Renders a `NexusDownloadError` through the app's live per-language bundle
    /// (`localization.L(...)`) rather than `errorDescription`'s `NSLocalizedString`, which
    /// doesn't follow in-session language switching.
    /// Rend un `NexusDownloadError` avec le bundle **vivant** de l'app
    /// (`localization.L`) plutôt qu'avec `errorDescription`, dont le
    /// `NSLocalizedString` ne suit pas un changement de langue en session.
    ///
    /// La table des neuf cas vit dans `NexusDownloadFlow.message(for:)` — elle
    /// était ici **en double** de celle d'`errorDescription`, deux copies
    /// d'une même règle. Il n'en reste qu'une, et deux résolveurs.
    private func nexusDownloadMessage(_ error: NexusDownloadError) -> String {
        NexusDownloadFlow.message(for: error).resolved { localization.L($0) }
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
    // domaine 6, tranche 1). Le registre et ses règles sont en Core
    // (`InstalledTranslationRegistry`) ; le store les publie, avec les deux
    // moitiés de la recherche et les vols mod par mod.
    let translationHub = TranslationHubStore()
    /// C5-T1 — la recherche des traductions FR sur tout le parc (page « Traductions FR »).
    let translationSweep = FrenchTranslationSweepStore()

    /// Ce qui est posé sur quel mod. Relu au lancement, réécrit à chaque dépôt
    /// ou retrait — c'est la seule trace : la perdre rendrait toute
    /// désinstallation impossible.
    var installedTranslations: InstalledTranslationRegistry { translationHub.installed }
    /// Les traductions françaises trouvées pour un mod, par `folderName`.
    /// Vidé à chaque nouvelle recherche : ce n'est pas un cache, c'est le
    /// résultat de la dernière question posée.
    var translationHits: [String: [NexusModSearch.Hit]] { translationHub.hits }
    /// Les résultats **correspondant à ce qui est déjà posé**, retirés des
    /// propositions mais gardés : c'est là que se lit une version plus récente,
    /// et c'est vers eux que rattache le menu.
    var translationInstalledHits: [String: [NexusModSearch.Hit]] { translationHub.installedHits }
    /// Les mods dont une recherche est en cours.
    ///
    /// Un ensemble, pas un seul nom : la fiche désactive ses boutons **mod par
    /// mod**, si bien qu'un verrou unique rendait muet le clic sur un second
    /// mod — le bouton restait actif et ne faisait rien.
    /// Un ensemble, pas un seul nom : la fiche désactive ses boutons **mod par
    /// mod**, si bien qu'un verrou unique rendait muet le clic sur un second
    /// mod — le bouton restait actif et ne faisait rien.
    var searchingTranslations: Set<String> { translationHub.searching }
    /// Les mods dont une traduction s'installe ou se retire.
    var busyTranslations: Set<String> { translationHub.busy }

    /// La traduction posée sur ce mod, s'il y en a une.
    func translation(for mod: ModItem) -> InstalledTranslation? {
        installedTranslations.translation(forHost: mod.folderName)
    }

    /// La déclaration manuelle d'une traduction sur ce mod (A3-T6).
    /// Distincte de `translation(for:)` : une déclaration ne porte pas la
    /// liste des fichiers déposés, juste l'identité Nexus.
    func declaredTranslation(for mod: ModItem) -> DeclaredTranslation? {
        installedTranslations.declaredTranslation(forHost: mod.folderName)
    }

    /// `true` quand un fichier `i18n/fr.json` (ou layout B équivalent) est
    /// présent sur le disque **sans** qu'aucune trace n'en soit gardée —
    /// ni `InstalledTranslation` (l'app ne l'a pas posé), ni
    /// `DeclaredTranslation` (l'utilisateur ne l'a pas déclaré).
    ///
    /// C'est le signal qui fait apparaître le bandeau « traduction présente,
    /// origine inconnue » sur la fiche. **Disque seul** : un `i18n/fr.json`
    /// copié manuellement ne fait pas la différence.
    ///
    /// Coût : un `FileManager.fileExists` par appel. Pas de cache : la fiche
    /// n'est pas un écran appelé en boucle, et un fichier qui apparaît ou
    /// disparaît veut être vu tout de suite.
    func hasUndeclaredFrenchTranslation(for mod: ModItem) -> Bool {
        guard installedTranslations.translation(forHost: mod.folderName) == nil,
              installedTranslations.declaredTranslation(forHost: mod.folderName) == nil
        else { return false }
        return Self.modFolderHasFrenchTranslation(mod: mod, basePath: gameDir)
    }

    /// Le test disque, isolé pour pouvoir être appelé sans traîner le VM.
    /// `mod` est résolu via son `physicalFolderName` pour respecter le toggle
    /// point (un mod en pause vit dans `Mods/.X`). `basePath` est le `gameDir`
    /// côté UI, ou un dossier jetable côté test.
    ///
    /// La règle elle-même vit dans `TranslationPresence` (Core, testé) : elle
    /// était réimplémentée ici, **sans** la règle « la racine gagne » que
    /// `I18nLocaleResolver` porte déjà.
    static func modFolderHasFrenchTranslation(mod: ModItem, basePath: String) -> Bool {
        guard !basePath.isEmpty else { return false }
        let hostURL = URL(fileURLWithPath: basePath, isDirectory: true)
            .appendingPathComponent("Mods", isDirectory: true)
            .appendingPathComponent(mod.physicalFolderName, isDirectory: true)
        return TranslationPresence.hasFrench(inModDirectory: hostURL)
    }

    /// Enregistre une déclaration manuelle pour ce mod (A3-T6). Le geste
    /// suffit à faire basculer la fiche du bandeau « origine inconnue » à la
    /// ligne « traduction présente, déclarée », avec le suivi de version.
    ///
    /// `nexusModId <= 0` est rejeté en silence : sans identifiant Nexus,
    /// la déclaration ne sert qu'à l'utilisateur, pas à l'app — l'avertissement
    /// resterait juste, mais aucune mise à jour ne pourrait être détectée.
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

    /// Retire une déclaration manuelle. **N'altère pas le disque** : les
    /// fichiers posés par l'utilisateur restent en place, seul le registre
    /// perd la ligne. C'est l'utilisateur qui a écrit, c'est lui qui enlève.
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

    /// `true` quand une version plus récente que celle en place a été trouvée.
    ///
    /// Sur les **dates Nexus**, jamais sur les numéros de version : beaucoup de
    /// traducteurs reprennent le numéro du mod traduit, ou ne le bougent pas.
    func translationUpdateAvailable(for mod: ModItem) -> NexusModSearch.Hit? {
        guard let installed = translation(for: mod) else { return nil }
        return TranslationPresence.update(
            for: installed,
            amongAvailable: translationHits[mod.folderName] ?? [],
            andInstalled: translationInstalledHits[mod.folderName] ?? [])
    }

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
                    // Une panne n'est pas une absence : ne rien afficher vaut mieux
                    // qu'afficher « aucun résultat » pour une requête qui a échoué.
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
        log(String(format: localization.L(L10n.VM.nexusIdLearned), mod.folderName, String(candidate.hit.modId)))
    }

    /// Referme les propositions de traduction d'un mod.
    ///
    /// **Ne jette que ce qui est affiché.** `translationInstalledHits` reste :
    /// il ne se voit pas, mais c'est lui qui porte la pastille « une version
    /// plus récente existe » sur la ligne en place. Refermer une liste veut
    /// dire « j'ai fini de chercher », pas « oublie ce que tu as appris ».
    func dismissTranslationResults(for mod: ModItem) {
        translationHub.setHits(nil, for: mod.folderName)
    }

    /// Referme les propositions de suppléments d'un mod.
    ///
    /// Les greffes du registre continuent de s'afficher : elles ne viennent pas
    /// de la recherche, elles viennent de ce qui est posé sur le disque.
    func dismissSupplementResults(for mod: ModItem) {
        translationHub.setSupplementSearch(nil, for: mod.folderName)
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
            translationHub.setInstalledHits([], for: mod.folderName)
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
        translationHub.setInstalledHits(split.installed, for: mod.folderName)
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

    /// Une version plus récente de cette greffe a-t-elle été trouvée ?
    ///
    /// Même règle que pour les traductions : sur les **dates Nexus**, et
    /// seulement quand la greffe porte un identifiant. Une greffe déposée à la
    /// main n'en a pas — c'est ce que `linkToNexus` répare.
    func addonUpdateAvailable(_ addon: InstalledTranslation,
                              for mod: ModItem) -> NexusModSearch.Hit? {
        let search = translationHub.supplementSearches[mod.folderName]
        return TranslationPresence.update(for: addon,
                                          amongAvailable: search?.hits ?? [],
                                          andInstalled: search?.alreadyInstalled ?? [])
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
        // La liste des propositions perd ce qui vient d'être reconnu — **sans
        // repartir sur le réseau** : on sait déjà lequel des résultats c'était,
        // et relancer la recherche ferait tourner un compteur d'API pour
        // retirer une ligne qu'on tient sous la main.
        // Le résultat **change de moitié** : il quitte les propositions et
        // rejoint ce qui est en place. L'y oublier ferait disparaître la mise à
        // jour qu'il annonce jusqu'à la recherche suivante.
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
            // Même règle que pour une traduction : un retrait à moitié fait
            // garde sa ligne, seule à porter la liste des fichiers restants.
            showModal(message: String(format: localization.L(L10n.Mods.translationRemovePartial),
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

    /// Cherche sur Nexus les traductions françaises de ce mod.
    ///
    /// Le filtre est le **tag** `French` de Nexus, pas le titre : sur 80
    /// traductions relevées, 77 le portent, et le serveur fait alors le tri.
    /// Le titre ne sert que de filet pour les trois autres.
    /// Cherche les traductions françaises d'un mod — le chemin partagé avec
    /// la page « Traductions FR » (`FrenchTranslationLookup` : lien « requis
    /// par » puis recherche par nom).
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
                // La traduction déjà posée n'a rien à faire dans la liste des
                // propositions : elle a sa propre ligne, qui porte son retrait
                // et sa mise à jour.
                self.translationHub.setHits(self.withoutInstalledTranslation(entry.hits, for: mod),
                                            for: mod.folderName)
            case .failure(let error):
                // Une panne n'est pas une absence : `[]` ferait afficher
                // « aucune traduction trouvée » pour une recherche cassée.
                self.translationHub.setHits(nil, for: mod.folderName)
                self.log("Recherche de traduction : \(error)", level: .warning)
                self.showModal(message: self.localization.L(L10n.Mods.translationSearchFailed))
            }
        }
    }

    /// Télécharge une traduction, la dépose dans le mod, et l'enregistre.
    ///
    /// Le dépôt ne crée rien dans `Mods/` : il écrit **dans** un mod existant,
    /// après avoir mis à l'abri chaque fichier recouvert.
    func installTranslation(_ hit: NexusModSearch.Hit, into mod: ModItem) {
        guard !translationHub.isBusy(mod.folderName) else { return }
        // Un seul téléchargement Nexus à la fois, traductions comprises : elles
        // passent par le même téléchargeur que les mods, et deux en vol se
        // disputeraient `pendingDownloadedZip`.
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
                    // Le dépôt d'une traduction n'installe pas de mod : les
                    // faits du fichier résolu (X9) ne le concernent pas, seule
                    // l'archive compte.
                    self.depositTranslation(archive: outcome.zip, hit: hit, into: mod)
                case .failure(.cancelled):
                    // Geste volontaire : rien à annoncer.
                    self.translationHub.setBusy(false, for: mod.folderName)
                case .failure(let error):
                    self.translationHub.setBusy(false, for: mod.folderName)
                    // Sans lien direct, la voie manuelle reste ouverte : le
                    // message nomme le bouton qui y mène plutôt que de laisser
                    // l'utilisateur devant une impasse.
                    var hint = ""
                    if case .noDownloadLink = error {
                        hint = "\n\n" + self.localization.L(L10n.Mods.translationManualHint)
                    }
                    self.showModal(message: self.nexusDownloadMessage(error) + hint)
                }
                // Une traduction occupait l'unique créneau de téléchargement
                // : les mods mis en file derrière elle peuvent reprendre.
                self.drainQueuedNexusDownloads()
            }
        })
    }

    private func depositTranslation(archive: URL, hit: NexusModSearch.Hit, into mod: ModItem) {
        defer { translationHub.setBusy(false, for: mod.folderName) }
        // L'archive téléchargée n'a plus d'usage passé ce point : la laisser
        // derrière nous encombrerait le dossier temporaire d'un fichier dont
        // plus personne ne connaît le chemin. `discardDownloaded` emporte le
        // dossier `StarHubFR-download-*` qui l'isolait — un `removeItem` du
        // seul fichier y laissait un dossier vide par traduction déposée
        // (X104), là où le flux des mods passe déjà par MainView:onDismiss.
        defer { NexusFileDownload.discardDownloaded(at: archive) }
        let installer = ModZipInstaller()
        do {
            let extracted = try installer.extractToTemp(zipUrl: archive)
            defer { try? FileManager.default.removeItem(at: extracted) }
            let paths = ManifestlessArchive.paths(under: extracted)
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
    ///   - downloadedModId: l'identifiant de la page dont l'archive vient,
    ///     quand elle vient d'un téléchargement de l'app (lien `nxm://` ou
    ///     téléchargement intégré). **Ceinture et bretelles** : le nom du
    ///     fichier le porte déjà, mais si Nexus ne l'avait pas nommé, ce
    ///     serait la seule occasion où l'app le connaît — la branche
    ///     d'installation d'un mod le retient depuis toujours
    ///     (`ModInstallView`, `recordNexusModId`), celle du dépôt le jetait.
    /// - Returns: ce qui a été écrit (`nil` si rien ne l'a été), et le message
    ///   à montrer le cas échéant — un dépôt peut réussir *et* avoir quelque
    ///   chose à dire.
    func depositIntoMod(plan proposed: ManifestlessArchive.Plan, extractedRoot: URL, host: ModItem,
                        sourceName: String, nexus: NexusModSearch.Hit?,
                        downloadedModId: Int? = nil)
        -> (outcome: ManifestlessInstaller.Outcome?, message: String?) {
        // Le refus se dit dans les mots de ce qu'on déposait : « la traduction »
        // n'a pas de sens quand l'utilisateur a glissé un lot de sacs.
        let failed = proposed.kind == .translation
            ? localization.L(L10n.Mods.translationInstallFailed) : localization.L(L10n.ModInstall.depositFailed)
        guard let backupRoot = InstalledTranslationStore.backupRoot else {
            return (nil, failed)
        }
        // Nom **physique** : un mod en pause vit dans un dossier préfixé d'un
        // point, et le plan ne connaît que le nom logique.
        let hostPath = URL(fileURLWithPath: gameDir)
            .appendingPathComponent("Mods")
            .appendingPathComponent(host.physicalFolderName)
        // Le rangement du mod hôte décide où va un `fr.json` à plat.
        let plan = ManifestlessArchive.adaptingLocaleLayout(proposed, to: .read(modDirectory: hostPath))

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
        // **Une seule lecture de l'identité**, pour la sonde de doublon
        // ci-dessous comme pour la ligne qui entrera au registre : deux
        // lectures qui divergeraient donneraient une identité au comparateur
        // et une autre à ce qui est gardé. La règle — fiche Nexus, puis nom du
        // fichier, puis identifiant du téléchargement ; date du dépôt et non
        // celle que porte le nom — vit dans `DepositIdentity` (Core, 13 tests).
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
            // Nommer les fichiers restés en l'état est la seule raison d'être de
            // cette erreur : les fondre dans « installation impossible »
            // laisserait croire le mod intact alors qu'il ne l'est pas.
            log("Dépôt sans manifeste, annulation incomplète : \(reason)", level: .error)
            return (nil, String(format: localization.L(L10n.ModInstall.depositRollbackIncomplete),
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
            // Les fichiers sont posés mais rien ne les retient : le dire,
            // sinon la traduction ne pourra plus être retirée.
            return (written, localization.L(L10n.Mods.translationNotTracked))
        }
        return (written, nil)
    }

    /// Retire la traduction posée sur ce mod et **rend** ce qu'elle avait
    /// recouvert.
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
            // **Un retrait à moitié fait garde son entrée.** Elle porte la liste
            // des fichiers restants et l'endroit où dorment les originaux du
            // mod : l'oublier ici rendrait la seconde tentative impossible.
            showModal(message: String(format: localization.L(L10n.Mods.translationRemovePartial),
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


    // MARK: - Découverte (axe G)

    /// La carte de la vitrine vit en Core (`DiscoveryScoping.Row`), avec les
    /// trois écarts qui décident de ce qu'elle contient. L'alias tient les
    /// vues en place — elles nomment encore `StarHubTHViewModel.DiscoveryRow`
    /// — et tombera au découpage des vues (REFACTORING §5, P8). Il reste ici
    /// exprès : `DiscoverySearchResult` a rejoint Core sans lui, pour ne pas
    /// toucher trois lignes de `DiscoverView` au passage.
    typealias DiscoveryRow = DiscoveryScoping.Row

    /// Le résultat d'une recherche par nom dans la vitrine : les cartes et le
    /// total serveur — la poignée affichée n'est jamais tout ce qui existe.
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

    /// Ce qui dit si une réponse de recherche est encore attendue. Les
    /// réponses arrivent sur le fil principal (`NexusSearchClient`), comme les
    /// mutations d'ici. Reste au ViewModel : c'est l'orchestration réseau qui
    /// l'ouvre et le vérifie, pas l'état affiché.
    private var discoveryEpoch = RequestEpoch()
    /// Même rôle que `discoveryEpoch`, pour la fiche : la feuille se ferme et
    /// s'ouvre sur un autre mod plus vite qu'une requête ne revient.
    private var discoveryDetailEpoch = RequestEpoch()

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
        guard discoveryStore.setCategory(category) else { return }
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
        // La catégorie demandée est retenue ici : la réponse peut arriver
        // après que l'utilisateur en a choisi une autre. Elle est alors
        // rangée dans **son** cache mais n'est pas affichée — sinon la
        // vitrine montrerait des mods d'une catégorie qu'on vient de quitter.
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
                    // Relu depuis le cache : c'est la page dédoublonnée qui
                    // s'affiche.
                    guard stillWanted else { return }
                    self.discoveryStore.setSection(kind,
                                                   to: self.discoveryCatalog.state(kind,
                                                                                   category: category?.id))
                case .failure(let error):
                    guard stillWanted else { return }
                    // La panne est dite dans tous les cas (spec §8) : garder des
                    // lignes de la veille sans prévenir qu'elles n'ont pas pu
                    // être rafraîchies, c'est mentir en silence.
                    self.discoveryStore.recordFailure(error)
                    // Le stale reste affiché pendant la panne (spec §6) — le
                    // bandeau suffit, on ne blanchit pas la section.
                    if case .stale = self.discovery[kind] ?? .empty(.neverLoaded) { return }
                    self.discoveryStore.setSection(kind, to: .empty(.failed))
                }
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
        // Les trois écarts et la reconnaissance du parc vivent dans
        // `DiscoveryScoping` (Core, 14 tests) ; ici ne restent que les deux
        // ensembles que seul le VM connaît.
        DiscoveryScoping.rows(from: hits,
                              installedNexusIds: installedNexusIds(),
                              installedTitles: Set(mods.map(\.name)),
                              hidingInstalled: hidingInstalled,
                              francophoneOnly: francophoneOnly)
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
                    // La bande déjà là ne bouge pas : seule la suite manque, et
                    // le bandeau dit pourquoi.
                    self.discoveryStore.recordFailure(error)
                }
                                      }
        }
    }

    /// Recherche par nom dans la vitrine : même client que la liaison
    /// d'identité, présentation propre à l'onglet (spec §7.1). Elle montre
    /// tout, badge « installé » compris — on cherche un mod précis, installé
    /// ou non.
    func searchDiscovery(name: String) {
        let term = NexusModSearch.searchTerm(for: name)
        guard !term.isEmpty else {
            // Vider le champ périme ce qui est en vol : sinon la réponse
            // arrivée une seconde plus tard ferait revenir la liste.
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

    /// La tranche suivante des résultats de recherche.
    ///
    /// Le terme redemandé est celui qui a produit la liste, retenu au
    /// résultat : reprendre le champ de saisie servirait la suite d'une autre
    /// recherche à qui aurait retapé entre-temps.
    func loadMoreDiscoverySearch() {
        guard let current = discoverySearch, current.loaded < current.totalCount else { return }
        // Le jeton de la recherche en cours, pas un neuf : demander la suite
        // prolonge la recherche, il ne la remplace pas.
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

    /// Quitte les résultats : les sections reprennent la place. Sans cette
    /// porte de sortie, une recherche remplacerait définitivement la vitrine.
    func clearDiscoverySearch() {
        // Périmer d'abord : une réponse en vol repeuplerait sinon la liste
        // que l'utilisateur vient de fermer.
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
                // Sans ce jeton, la réponse d'une fiche fermée entre-temps
                // s'affichait sous le titre de celle qu'on venait d'ouvrir.
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

    /// L'alerte à présenter — `nil` = rien. Posé seulement pour le chemin
    /// du lancement, et seulement si le tag n'a pas déjà été acquitté.
    private(set) var availableAppRelease: GitHubRelease?
    /// La dernière release connue — l'état de Réglages → À propos en
    /// dérive, indépendant du tag acquitté : vue mais non installée, une
    /// release reste « disponible ».
    private(set) var lastKnownRelease: GitHubRelease?
    private(set) var releaseCheckInFlight = false
    /// L'échec du check — dit **seulement** sur le check manuel ; au
    /// lancement, une app hors-ligne ne doit pas brair à chaque ouverture.
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

    /// `@MainActor` explicite : la classe ne l'est pas, et une `func async`
    /// non isolée exécuterait son corps hors du fil principal — or tout ce
    /// qui suit mute des `@Published`.
    @MainActor
    private func performReleaseCheck(lastChecked: Date?, bypassThrottle: Bool) async {
        // Le drapeau retombe par **tous** les chemins, succès comme échec.
        // Sans ce `defer`, le check du lancement le laissait à `true` pour
        // la session : « Vérifier les mises à jour » devenait inopérant
        // (le garde de `checkForAppRelease`) et À propos affichait
        // « Vérification… » indéfiniment, bouton grisé.
        defer { releaseCheckInFlight = false }
        var request = URLRequest(url: Self.appReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Session éphémère comme la lookup SMAPI (X83) : un blip réseau ne
        // doit pas laisser traîner une connexion.
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

    /// Échec : `lastCheckedAt` n'est PAS repoussé — on retente au prochain
    /// lancement. Le manuel, lui, dit pourquoi ; le lancement se tait.
    @MainActor
    private func recordReleaseCheckFailure(status: Int?, bypassThrottle: Bool,
                                           underlying: Error? = nil) {
        guard bypassThrottle else { return }
        releaseCheckFailedMessage = String(
            format: self.localization.L(L10n.Settings.appCheckFailed),
            underlying?.localizedDescription ?? "HTTP \(status ?? 0)")
    }

    /// Le traitement d'une réponse 200 — séparé du transport pour la
    /// lisibilité ; la décision est déjà testée en Core.
    @MainActor
    private func applyReleaseCheck(data: Data, lastChecked: Date?, bypassThrottle: Bool) {
        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            // Une réponse 200 illisible se traite comme un échec — jamais
            // comme « à jour » (leçon du cache d'octets étrangers).
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
            // L'alerte n'est posée que pour le chemin du lancement et un
            // tag jamais acquitté. Le check manuel met à jour l'état
            // d'À propos sans présenter de sheet (spec §7.5).
            if !bypassThrottle && !alreadySeen {
                availableAppRelease = knownRelease
            }
        }
    }

    func acknowledgeRelease(_ release: GitHubRelease) {
        // « Voir la release » comme « Plus tard » acquittent (spec §7.4) :
        // l'alerte se montre une fois par tag, point.
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

    /// L'état d'À propos au lancement, avant tout check : la dernière
    /// release connue relue du disque.
    func loadLastKnownRelease() {
        guard let json = UserDefaults.standard.string(forKey: UDKey.frReleaseLastKnown),
              let data = json.data(using: .utf8) else { return }
        do {
            lastKnownRelease = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            // JSON corrompu : repartir de nil plutôt qu'un état fantôme —
            // le prochain check réussi réécrira la clé.
            lastKnownRelease = nil
        }
    }

    // MARK: - Bilan d'installation (fenêtre dédiée)

    /// Posé au succès de l'installation ; la `MainView` l'observe pour
    /// ouvrir la fenêtre de bilan. Sa remise à nil se fait à la fermeture
    /// de la fenêtre (ou avant réouverture de la feuille).
    private(set) var pendingInstallReport: InstallReport?
    /// La file de dépôt multiple, migrée du `@State` de `ModInstallView` :
    /// la fenêtre de bilan vit entre deux zips, un état de feuille serait
    /// perdu à sa fermeture.
    private(set) var pendingDropQueue = InstallDropQueue()

    func dropQueuePush(_ urls: [URL]) { pendingDropQueue.push(urls) }
    @discardableResult func dropQueueAdvance() -> URL? { pendingDropQueue.advance() }
    var nextQueuedDropURL: URL? { pendingDropQueue.current }

    /// Appelé par la feuille AU succès de l'installation — les noms restent
    /// apportés par la vue, qui les possède. Publie le bilan figé. Ne touche
    /// à aucun ménage : le `onDismiss` de la feuille (archive, X103-C, file
    /// nxm) s'exécute ensuite à l'identique.
    ///
    /// ⚠️ **Ne dépile pas.** L'invariant de la file est : *elle porte les
    /// archives qui n'ont pas encore été présentées, et c'est celui qui
    /// présente qui dépile* (`analyzeNextQueuedArchive`,
    /// `queueNextDropArchive`). Dépiler ici en plus sautait une archive en
    /// silence sur un dépôt multiple — l'archive suivant celle qu'on venait
    /// d'installer n'était jamais analysée, et le compte annoncé était faux.
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

    /// Le canal de réouverture de la feuille sur l'archive suivante —
    /// observé par la MainView. ⚠️ Ne passe JAMAIS par le `onDismiss` qui
    /// discard : ce sont les fichiers originaux de l'utilisateur, pas des
    /// téléchargements.
    private(set) var pendingDropPresentation: URL?

    /// « Archive suivante (n) » : dépile la prochaine archive, la pose pour
    /// réouverture de la feuille et referme le bilan. **Dépile** — voir
    /// l'invariant de `completeInstall`.
    func queueNextDropArchive() {
        pendingDropPresentation = pendingDropQueue.advance()
        pendingInstallReport = nil
    }

    /// Le lot est abandonné : la feuille a été refermée sans installer.
    /// L'ancienne file vivait en `@State` sur la feuille et mourait avec
    /// elle — ce que ce `@Published` ne fait plus tout seul. Sans ce ménage,
    /// des archives d'un dépôt délaissé resurgissent à une installation
    /// ultérieure, en pointant peut-être sur des fichiers disparus.
    func abandonDropQueue() {
        guard !pendingDropQueue.isEmpty else { return }
        pendingDropQueue = InstallDropQueue()
    }

    /// La fenêtre de bilan a été fermée à la main, sans « Archive suivante » :
    /// le reste du lot part avec elle.
    func abandonInstallReport() {
        pendingInstallReport = nil
        abandonDropQueue()
    }

    /// La feuille est refermée (onDismiss MainView) : le canal de
    /// réouverture a été consommé.
    func clearDropPresentation() {
        pendingDropPresentation = nil
    }

    // ⚠️ Les deux canaux de navigation demandée sont des façades provisoires
    // (P8) — l'état, ses verbes et leur documentation vivent dans
    // `navigationStore` ; la reprise des vues les appellera directement.
    // `reportDetailFocus` : « voir la fiche » depuis la fenêtre de bilan.
    // `pendingTabRequest` : l'onglet demandé depuis le menu « Aller » ou la
    // palette ⌘K (I-T1 / I-T2) — `.commands` vit dans la scène App,
    // `currentTab` est un `@State` de MainView (patron B3-T4).
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

    /// Ouverture de la palette demandée depuis le menu — ⌘K y est déclaré pour
    /// être visible et découvrable. Même problème, même remède : la
    /// superposition est un `@State` de MainView.
    private(set) var paletteRequested = false

    func requestPalette() {
        paletteRequested = true
    }

    /// Consommé par MainView — que la palette s'ouvre **ou non** : elle refuse
    /// de s'ouvrir sous une feuille (spec §10), et le canal doit retomber quand
    /// même. Un canal resté armé ferait voir la demande suivante comme « déjà
    /// en cours » : la famille de bugs de `releaseCheckInFlight`.
    func consumePaletteRequest() {
        paletteRequested = false
    }

    // MARK: - Delta de clés de mise à jour (C2-T4)

    /// Les deltas de la dernière installation, pour l'écran de succès.
    private(set) var lastInstallKeyDeltas: [ModUpdateKeyDelta] = []
    /// A1-T7 — ce que la dernière installation a remis en place, pour le bilan.
    private(set) var lastInstallPreserved: [PreservedDataOutcome] = []

    /// Écrit le store pour chaque chemin installé portant un delta. Appelé
    /// dans le completion de `performInstall` AVANT l'écran de succès : un
    /// crash ne perd pas le delta, et la feuille comme la fiche lisent la
    /// même chose. Échec journalisé, jamais bloquant.
    func persistUpdateKeyDeltas(_ paths: [InstalledModPath]) {
        lastInstallKeyDeltas = paths.compactMap(\.keyDelta)
        // A1-T7 — une préservation muette serait le défaut qu'on corrige : elle
        // part au journal **et** au bilan. Le journal garde la trace quand la
        // fenêtre a été fermée ; le bilan la met sous les yeux.
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
        // Le store vient de changer sous les caches de lecture : une mise à
        // jour du MÊME mod dans la session ne doit pas resservir l'ancien
        // delta mémorisé.
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

    /// Incrémenté à chaque mutation du store (report, nouvelle capture,
    /// suppression) : la section fiche relit le delta et rejoue le matcher
    /// (le magasin n'est pas `@Published` — sans ce compteur, ni le
    /// rafraîchissement ni l'invalidation des caches ci-dessous ne marchent).
    private(set) var updateKeyDeltasRevision = 0

    /// Caches de lecture de la fiche. Le body relit le delta à CHAQUE rendu
    /// et le matcher de renommage est O(retirées × ajoutées) — sans
    /// mémoïsation, chaque republication du VM (scan, journal, Nexus)
    /// rejouait lecture disque + Levenshtein sur le fil principal tant que
    /// la fiche est ouverte, la classe exacte de gel corrigée deux fois
    /// (index glossaire, LazyVStack). Une entrée suffit : la fiche ne
    /// montre qu'un mod, et la révision invalide à toute mutation du store.
    /// Touchés du fil principal seulement (body, actions de boutons,
    /// completion d'installation sur `DispatchQueue.main`).
    ///
    /// ⚠️ `@ObservationIgnored` est **obligatoire** ici, et c'est un piège
    /// propre à `@Observable` : sous `ObservableObject`, écrire un stocké non
    /// publié pendant un rendu ne réveillait personne ; désormais **tout**
    /// stocké est suivi. Un cache à créneau unique lu depuis un `body` et
    /// réécrit à chaque manque invalide alors les vues **sœurs** qui l'avaient
    /// lu — mesuré le 2026-09-11 sur `withObservationTracking` : deux vues
    /// lisant deux clés bouclent **à l'infini** (60 rendus, garde atteinte),
    /// là où un cache-dictionnaire converge en deux passes. Aujourd'hui
    /// `ModUpdateDeltaSection` n'est instanciée qu'une fois (la fiche d'un
    /// mod) — la boucle est à une liste près, pas dans le code livré.
    /// Retirer le suivi est sûr parce que l'invalidation ne passe pas par le
    /// cache : les deux lisent `updateKeyDeltasRevision`, un stocké suivi, à
    /// **chaque** appel — succès de cache compris.
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

    /// Les paires de renommage proposées pour ce delta : fusion des deux
    /// signaux (valeur EN identique = sûr ; similarité de nom = à vérifier
    /// à l'œil), moins ce qui est déjà réconcilié.
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

    /// Reporte des paires renommées dans le(s) `fr.json` du mod. Les clés
    /// qualifiées `"Composant/clé"` désignent le fr.json du composant — le
    /// préfixe est le **chemin relatif sous le mod**, ce que le snapshot
    /// nomme ; le routage et la désqualification vivent dans
    /// `RenameReport.routeByOldComponent` (Core, testé).
    @MainActor
    func applyRenameReportTranslation(_ pairs: [RenamePair], to mod: ModItem) -> KeyRenameReportOutcome {
        guard !pairs.isEmpty, let dir = ModUpdateKeyDeltaStore.defaultDirectory(),
              var delta = ModUpdateKeyDeltaStore.load(uniqueId: mod.uniqueId, directory: dir)
        else { return .nothingLeft(skippedCrossComponent: 0) }

        let modsRoot = (gameDir as NSString).appendingPathComponent("Mods")
        // Les composants du mod = ses descendants dans l'arbre scanné — PAS
        // mod.children : les descendants d'un groupe vivent À PLAT sous
        // l'en-tête (scanMods), la fiche d'un enfant imbriqué a children nil
        // alors que son delta peut porter les clés qualifiées de ses propres
        // sous-mods — « Rien à reporter » à jamais, sinon. Le préfixe est le
        // chemin relatif sous le mod, ce que le snapshot a nommé ; le disque,
        // le chemin physique réel (point de pause inclus).
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

        // Désqualifier et router : le fr.json ne voit que des clés brutes —
        // une clé qualifiée cherchée dedans ne matcherait rien, en silence.
        // Les paires qui CHANGENT de composant ne sont pas reportables
        // (RenameReport.routeByOldComponent) : comptées, rendues à l'écran.
        let routed = RenameReport.routeByOldComponent(pairs, known: prefixes)
        let skipped = routed.crossComponent.count

        var applied: [RenamePair] = []
        for (prefix, routedPairs) in routed.byComponent.sorted(by: { $0.key < $1.key }) {
            guard let physical = physicalByPrefix[prefix] else { continue }
            let i18nDir = URL(fileURLWithPath: modsRoot)
                .appendingPathComponent(physical, isDirectory: true)
                .appendingPathComponent("i18n", isDirectory: true)
            // **Tous** les fichiers de la locale, jamais un `i18n/fr.json`
            // composé à la main : un mod rangé en layout B (`i18n/fr/
            // dialogue.json`…) n'en a aucun, et cette boucle abandonnait ici
            // sans rien journaliser — 5 mods du parc dans ce cas.
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
                    // Seules les paires de CE fichier entrent au bilan : une
                    // écriture ratée ne doit pas emporter celles des autres
                    // sections, ni les faire compter comme reportées.
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
        // Le delta persisté : les paires appliquées passent en reconciled et
        // quittent les compteurs.
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

    /// Reporte des paires renommées dans le `config.json` racine du mod —
    /// le seul que le delta décrit (les composants n'y figurent pas).
    /// Backup avant écriture et garde anti-écrasement : le patron de
    /// l'éditeur de config, repris tel quel.
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

        // Garde : relecture fraîche juste avant d'écrire — un fichier que le
        // mod ou le jeu vient de toucher ne se fait pas écraser en silence.
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
            // On ne décide pas à sa place : journalisé, le report attendra.
            // Le `.cancelled` est porté jusqu'à l'écran : « rien à reporter »
            // ferait conclure que les paires étaient fantaisistes.
            log("Report de réglages (\(mod.name)) : config.json a changé sous nos pieds, report annulé",
                level: .warning)
            return .cancelled
        }

        // Backup avant écriture — le patron de l'éditeur, `onlyEnabled:
        // false` pareil (le mod peut être en pause).
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
        // Le delta config ne décrit que des clés de premier niveau : pas de
        // notion de composant, donc rien à annoncer en cross.
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

    /// Le registre des mods installés — version vue sur disque et date de ce
    /// constat. Sa persistance, ses trois mécanismes de sûreté et la règle de
    /// rapprochement vivent dans `InstalledModRegistryStore` (Core, testé) ;
    /// le ViewModel ne garde ici que le câblage et le journal.
    private let installedModRegistryStore = InstalledModRegistryStore()

    /// Tous les mods, packs aplatis en leurs composants. Réutilise
    /// `flattenedMods` (module Core testé) plutôt que de réécrire le
    /// dépliage une 23e fois — voir son commentaire pour l'historique.
    private func allInstalledMods() -> [ModItem] {
        mods.flattenedMods
    }

    /// La date d'installation enregistrée pour un dossier, ou `nil` si le mod
    /// n'a jamais été enregistré. Façade : les vues et le reste du ViewModel
    /// l'appellent, le store la calcule.
    nonisolated func installedModDate(for folderName: String) -> Date? {
        installedModRegistryStore.installedDate(for: folderName)
    }

    /// Rapproche le registre de ce que le scan a vu, puis dit à l'utilisateur ce
    /// qui s'est passé. Le store ne journalise pas lui-même : il rend un
    /// rapport, et c'est ici qu'on sait écrire dans le journal de l'app.
    ///
    /// - Parameter modsFolderWasReadable: faux quand le scan n'a pas pu lire
    ///   `Mods/`. Les deux purges de cette passe — le registre lui-même et les
    ///   ancres de version — sont alors suspendues : elles répondent à « ce
    ///   dossier a disparu », question à laquelle un lot qu'on n'a pas pu lire
    ///   ne répond pas. L'enregistrement, lui, continue.
    nonisolated private func syncInstalledModRegistry(scannedMods: [ModItem],
                                          modsFolderWasReadable: Bool = true) {
        // La version que smapi.io suggère, par `UniqueID`. Source : le cache
        // plat sous son lock, pas `nexusUpdates`. La propriété @Published ne
        // s'écrit que sur le fil principal (`republishUpdatesFromCache`) — la
        // lire ici, sur le fil du scan, est une course. Et la liste consolidée
        // par pack ne garde que l'enfant gagnant de chaque pack : un enfant
        // perdant avec mise à jour y perd sa suggestion. Le cache plat, lui, a
        // une ligne par mod.
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

        // Le parc vient de changer : la liste des affirmations en dépend par
        // ses deux bouts — l'ancre et la version du manifest. Les
        // avertissements du dump aussi : ils ne portent que sur les mods
        // réellement installés.
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

    /// fetchSaves() scans the Saves directory and parses every save's XML —
    /// run off the main thread so it doesn't stall the UI when there are
    /// many saves.
    nonisolated func reloadSaves() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let saves = SaveManager.shared.fetchSaves()
            DispatchQueue.main.async {
                self?.savesStore.replace(saves: saves)
            }
        }
    }

    /// Whether Stardew Valley itself currently appears to be running.
    /// Best-effort process-name check (matches the launcher and the SMAPI-
    /// renamed process) — used to warn before writing save files, since the
    /// game's own autosave could conflict with an edit/restore made while
    /// it's open. Not a guarantee: a differently-named build wouldn't match.
    func isGameRunning() -> Bool {
        let running = NSWorkspace.shared.runningApplications.contains {
            guard let name = $0.localizedName else { return false }
            return name.caseInsensitiveCompare("Stardew Valley") == .orderedSame
        }
        if running {
            // Le jeu est visible : le garde système protège désormais seul,
            // et le délai anti double-lancement ne doit plus retenir un
            // relancement légitime (crash immédiat, puis nouvelle tentative).
            launchGate.noticeGameRunning()
        }
        return running
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
        // Même verrou que `duplicateSave`/`deleteSave` : une réécriture de
        // sauvegarde est un lecture-modification-écriture entier — deux
        // opérations qui s'entrelacent valent « dernier gagne », les
        // changements de l'autre perdus (audit 2026-08-05).
        guard savesStore.beginOperation() else { return }
        // `updateSave` parses and rewrites the full save XML — dispatched
        // off main so it doesn't block the UI on a large save file.
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
        // Same rationale as `editSave` — the save file read/write below
        // must not run on the main thread.
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
    /// Envoie le dossier de sauvegarde à la corbeille.
    ///
    /// **Hors du fil principal, obligatoirement** : une sauvegarde de fin de
    /// partie pèse des dizaines de mégaoctets répartis sur des centaines de
    /// fichiers, et le déplacement se faisait ici même, fenêtre figée.
    /// `@MainActor` sur la méthode : seul le corps du `Task.detached` quitte
    /// le fil principal, les `@Published` touchés après l'`await` y restent.
    @MainActor
    func deleteSave(info: SaveGameInfo) async {
        guard savesStore.beginOperation() else { return }
        let deleted = await Task.detached(priority: .userInitiated) {
            SaveManager.shared.deleteSave(info: info)
        }.value
        savesStore.endOperation()
        if deleted {
            // Fermer l'éditeur ici, pas côté vue : la suppression est
            // asynchrone, et un `setEditingSave(nil)` enchaîné après l'appel
            // fermait la fiche même quand le `guard` ci-dessus avait renvoyé
            // sans rien supprimer. Ne ferme que la fiche de la sauvegarde
            // supprimée — on peut en éditer une autre depuis l'arbre.
            if navigationStore.editingSave?.id == info.id { navigationStore.setEditingSave(nil) }
            reloadSaves()
            showModal(message: localization.L(L10n.VM.deleteSaveSuccess))
        } else {
            showModal(message: localization.L(L10n.VM.deleteSaveError))
        }
    }
    
    /// Façades de lecture vers le store du domaine — le suivi d'observation
    /// les traverse (cadrage §2, cas 1), la composition (filiation, tri,
    /// filtre par étiquette) est prouvée dans `SavesStoreTests`.
    var savesHierarchy: [SaveNode] { savesStore.hierarchy }
    var availableFilterTags: [String] { savesStore.availableFilterTags }
    
    func setAvatar(forSave folderName: String, iconPath: String) {
        let note = SaveNotesStore.shared.note(for: folderName)
        SaveNotesStore.shared.setNote(for: folderName, tag: note.tag, note: note.note, customIconPath: iconPath)
    }
    
    /// Copie le portrait choisi dans le dossier de données — le chemin d'origine
    /// disparaîtrait au premier rangement. Nommage : `CustomAvatarStaging` ; panneau : `ImagePicking`.
    func selectCustomAvatar(forSave folderName: String, completion: ((String) -> Void)? = nil) {
        guard let chosen = imagePicker.pickImage(title: localization.L(L10n.Saves.avatarPanelTitle)),
              let avatars = AppSupport.avatarsDirectory else { return }
        let fm = FileManager.default, source = URL(fileURLWithPath: chosen)
        try? fm.createDirectory(at: avatars, withIntermediateDirectories: true)
        let plan = CustomAvatarStaging.plan(forSave: folderName, source: source, in: avatars,
                                            fileExists: { fm.fileExists(atPath: $0.path) })
        do {
            // Sans ce retrait, deux images de même nom de fichier faisaient
            // échouer `copyItem` (`NSFileWriteFileExists`, 516, mesuré) et le
            // choix du joueur restait sans effet. Le préfixe de destination
            // porte l'identité de la sauvegarde : le fichier retiré est le sien.
            if plan.replacesExisting { try fm.removeItem(at: plan.destination) }
            try fm.copyItem(at: source, to: plan.destination)
        } catch {
            log("selectCustomAvatar: copy failed — avatar path not set: \(error)", level: .error)
            return
        }
        setAvatar(forSave: folderName, iconPath: plan.destination.path)
        completion?(plan.destination.path)
    }
    
    /// Copie le dossier de sauvegarde puis réécrit les noms dans son XML.
    /// Même raison qu'`deleteSave` de tourner hors du fil principal — ici
    /// c'est une copie complète, l'opération la plus lente de l'onglet.
    /// Rend le succès : la feuille de duplication ne se ferme que sur une
    /// copie réussie (audit 2026-08-05), l'échec laisse l'utilisateur
    /// réessayer sous le modal d'erreur.
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

    /// listBackups scans the backups folder on disk — run off the main
    /// thread so opening the timeline doesn't stall the UI when there are
    /// many backups.
    func listBackups(for info: SaveGameInfo, completion: @escaping @Sendable ([SaveBackup]) -> Void) {
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
    
    /// Les dossiers que « Vider les mods désactivés » supprimerait, relevés
    /// **une fois**.
    ///
    /// L'écran s'en sert pour chiffrer sa confirmation, puis passe la **même**
    /// liste à `cleanDisabledMods(targets:)` : ce qui est annoncé est
    /// exactement ce qui part. Deux relevés à deux instants laisseraient un
    /// dossier mis en pause entre-temps être supprimé sans avoir été compté.
    func disabledModTargets() -> [String] {
        guard !gameDir.isEmpty else { return [] }
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: modsPath) else {
            return []
        }
        return DisabledModsCleanup.targets(in: entries)
    }

    /// Met en corbeille (X103-B) les mods en pause désignés par
    /// `DisabledModsCleanup` (Core) — en **un** événement, que l'Entretien
    /// remet ou purge d'un bloc. Sur le parc de référence, 721 dossiers : ce
    /// geste était le seul à les effacer sans retour. L'espace ne revient
    /// qu'au vidage de la corbeille.
    func cleanDisabledMods(targets: [String]) {
        guard !gameDir.isEmpty else { return }
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let result = ModTrash.trash(modsPath: modsPath, stamp: ModTrash.makeStamp(), items: targets.map {
            ModTrash.Item(physical: $0, logicalLeaf: String($0.drop { $0 == "." }))
        })
        // Pas de `forgetStores` ici, à la différence de `deleteMod` : « Tout
        // remettre » doit rendre le lot avec ses données (configs par profil,
        // traductions, identifiants saisis) — choix de l'auteur, 2026-09-24.
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
        // Les mutations se font sur le fil principal — `performInitialLoad`
        // appelle d'ici son bloc `main.async`. ⚠️ Ce commentaire disait
        // autrefois que SwiftUI émet un diagnostic sur une écriture hors fil :
        // sous `@Observable`, plus aucun diagnostic n'est émis — mais l'ordre
        // des publications reste ce que l'UI suppose.
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
    
    /// The currently-active profile, if any (nil when none is applied).
    /// Un identifiant orphelin (profil supprimé) ne rend rien.
    var activeProfile: ModProfile? { profilesStore.activeProfile }

    private static let defaultProfileKey = "defaultProfileId"

    /// L'id du profil par défaut auto-créé (`nil` si aucun n'a été seedé).
    /// **Miroir** : la seule écriture est le seed du VM
    /// (`ensureDefaultProfileIfNeeded`), qui met la stockée et `UserDefaults`
    /// à jour ensemble — c'est pourquoi il ne participe pas à
    /// `resyncMirroredDefaults()` : aucune écriture extérieure à resuivre.
    /// La seed lit la constante **statique** : un initialisateur de propriété
    /// ne peut pas lire un `let` d'instance.
    private(set) var defaultProfileId: UUID? =
        UserDefaults.standard.string(forKey: StarHubTHViewModel.defaultProfileKey).flatMap(UUID.init(uuidString:))

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

    /// R2 — le journal d'une application morte en route (crash, force-quit),
    /// chargé au lancement et maintenu par écriture/effacement dans
    /// `applyProfileToFilesystem`. Contrairement au set ci-dessus, il
    /// **survit** au redémarrage : c'est lui qui empêche l'adoption
    /// silencieuse de l'état partiel par `syncActiveProfileIds`. Non publié :
    /// sa présentation passe par `pendingApplyRecovery`, différée à la
    /// révélation de la fenêtre.
    private(set) var unresolvedApplyJournal: ProfileApplyJournal?

    /// R2 — où vit ce journal sur disque. Relevé **une fois** : les quatre
    /// points d'appel du ViewModel doivent désigner le même fichier, sans quoi
    /// un `clear` n'effacerait rien et le garde d'adoption resterait armé sur
    /// un journal fantôme. Le store, lui, n'a plus de valeur par défaut — c'est
    /// ce qui garantit qu'aucun test ne peut écrire ici par inadvertance.
    private let applyJournalDirectory: URL? = AppSupport.directory

    /// R2 — le dialogue de reprise, présenté une fois la fenêtre révélée —
    /// jamais pendant le splash : un dialogue attaché à une fenêtre hors
    /// écran ne se présente pas, et le cycle de lancement est un terrain
    /// documenté comme meurtrier.
    private(set) var pendingApplyRecovery: ProfileApplyJournal?

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
            createProfile(name: localization.L(L10n.Profiles.defaultName), seed: .currentlyEnabledMods)
            // Record the seeded profile as the (undeletable) default.
            if let seeded = modProfiles.last {
                defaultProfileId = seeded.id
                UserDefaults.standard.set(seeded.id.uuidString, forKey: Self.defaultProfileKey)
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
        profilesStore.add(made.profile)
        // Un instantané peut devenir actif sur-le-champ : il décrit déjà l'état
        // du disque, aucun dossier à déplacer. Un profil vide, non — voir
        // `ProfileFactory.make`.
        if made.activate {
            profilesStore.setActiveProfile(made.profile.id)
        }
        saveProfiles()
        log(String(format: localization.L(L10n.VM.profileCreated), name, made.profile.enabledModIds.count))
    }

    // MARK: - Récupérer un fichier isolé depuis une sauvegarde (B4-T4)

    /// Ce qu'une mise à jour de mod a emporté et qu'une sauvegarde peut rendre.
    /// Vide tant que `scanRecoverableFiles()` n'a pas tourné.
    private(set) var recoverableFiles: [RecoverableFile] = []
    private(set) var isScanningRecoverableFiles = false

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
    nonisolated private static func topLevelJSONKeys(atPath path: String) -> [String]? {
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
                // `onlyEnabled: false` : le mod est nommément désigné, le
                // filtre n'a rien à trancher ici — et sans ça, un mod en pause
                // faisait **échouer la récupération elle-même** (le filet
                // levait « aucun mod actif à sauvegarder », capté plus bas, et
                // le fichier n'était jamais réécrit). 527 des 593 mods à
                // `config.json` du parc sont en pause.
                _ = try ModConfigBackupManager.shared.createBackup(gameDir: gameDir, mods: [mod],
                                                                   onlyEnabled: false)
            }
            // L'écriture passe par `RecoveredFileWriter` : les dossiers de mods
            // sont souvent en lecture seule (`unzip`/`unrar` restituent les
            // modes de l'archive), et une copie directe échoue dessus.
            try RecoveredFileWriter.write(from: file.backupPath,
                                          to: file.installedPath,
                                          modRoot: file.installedRoot)
            log(String(format: localization.L(L10n.Recovery.recovered), file.relativePath, file.modName))
            recoverableFiles.removeAll { $0.id == file.id }
            // Le fichier rendu peut être un `config.json` — le cas le plus
            // courant du parc — comme un `i18n/fr.json`, qui ne concerne pas
            // les raccourcis. On rescanne sans distinguer : un scan de trop
            // est sans coût (lecture détachée hors du fil principal), et
            // trancher sur le nom du fichier serait une règle de plus à tenir
            // en accord avec celle du scanner (X66).
            rescanKeybindsAfterConfigWrite()
            // Un fichier remis lève peut-être une protection de l'Entretien,
            // que le segment « Fichiers récupérables » lit aussi (I-T8).
            if maintenanceStore.report != nil { buildMaintenanceReport() }
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
    nonisolated private static func parseTranslation(atPath path: String) -> [String: String]? {
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
            // Le dossier du mod est souvent en lecture seule : même remède que
            // pour la copie d'un fichier entier.
            try RecoveredFileWriter.withWriteAccess(to: file.installedPath,
                                                    modRoot: file.installedRoot) {
                try TranslationFileStore.write(text, to: target)
            }
            log(String(format: localization.L(L10n.Recovery.keysRecovered), Int64(edits.count), file.modName))
            // Une écriture de même taille dans la même seconde laisse
            // l'empreinte intacte : les rangées gardées (F7) serviraient
            // l'état d'avant récupération. On ne repasse pas par
            // `invalidateFrenchCoverage(for:)` — son retrait d'index effacerait
            // les baselines que le mod conserve — c'est le cache qu'on vide
            // directement. Voir `TranslationDiffCache.removeAll()`.
            translationDiffCache.removeAll()
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
            log(String(format: localization.L(L10n.ModInstall.restoreReportWritten),
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
        // R2 : le geste « ajouter la dépendance manquante » applique au
        // disque quand le profil est actif — mêmes gardes que l'activation.
        guard guardProfileApply(for: id, name: modProfiles[index].name) else { return }
        let key = uniqueId.lowercased()
        guard !modProfiles[index].enabledModIds.contains(where: { $0.lowercased() == key }) else { return }

        // Ce qu'on sait du mod entre dans le profil avec lui : c'est tout ce
        // qui restera le jour où il aura été désinstallé.
        let added = mods.flattenedMods.first(where: { $0.uniqueId.lowercased() == key })
        if let added {
            profilesStore.mutateProfile(with: id) {
                $0.modMetadata[added.uniqueId] = ProfileModMetadata(name: added.name,
                                                                    nexusModId: added.nexusModId)
            }
        }
        var ids = modProfiles[index].enabledModIds
        ids.append(uniqueId)
        // Le nom du mod quand on le connaît, son identifiant sinon : un ajout
        // peut porter sur un mod que le parc n'a plus (dépendance réclamée par
        // un profil importé), et « ajouté » sans dire quoi n'apprend rien.
        let addedName = added?.name ?? uniqueId
        updateProfile(id: id, newName: modProfiles[index].name, enabledModIds: ids)
        log(String(format: localization.L(L10n.VM.profileModAdded),
                   addedName, modProfiles[index].name, ids.count))
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

    /// Marque ou démarque un mod comme « à écarter ». Symétrique de
    /// `toggleFavorite` : persistance immédiate, même clé logique, même
    /// idempotence. Le mod reste installé — la marque n'agit que sur
    /// l'affichage et le filtre.
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
        let installed = Set(mods.flattenedMods.map(\.folderName))
        let orphans = entries.keys
            .filter { !installed.contains($0) }
            .sorted()
        return (entries.count, orphans)
    }

    /// Les écarts entre ce que deux profils retiennent de ce mod. `nil` :
    /// un des deux textes ne se parse pas — l'écran affiche l'explication,
    /// jamais un diff inventé.
    func profileConfigDiffs(mod: ModItem, other: ModProfile) -> [ConfigKeyDiff]? {
        guard let active = profilesStore.activeProfile,
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
            log(String(format: localization.L(L10n.VM.profileConfigResetAbsent), mod.folderName), level: .info)
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
            log(String(format: localization.L(L10n.VM.profileConfigResetDone), mod.folderName))
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
        guard let profile = profilesStore.profile(with: profileId) else {
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
        // R2 : avant la moindre mutation — ce flux écrit `modMetadata` avant
        // d'appeler `updateProfile`, qui réapplique au disque sur un profil
        // actif ; un refus après coup laisserait un demi-état en mémoire.
        guard guardProfileApply(for: profileId, name: modProfiles[index].name) else {
            return FavoriteResolution.Result(ids: [], unresolved: [])
        }
        let resolution = FavoriteResolution.profileIds(
            favorites: favoriteMods, in: mods,
            existing: modProfiles[index].enabledModIds)
        guard !resolution.ids.isEmpty else { return resolution }

        // La résolution (casse, composants de pack, doublons d'identifiant)
        // vit dans `ProfileFactory.metadata(forIds:in:)` — elle était écrite
        // ici en deux exemplaires, un par import.
        profilesStore.mutateProfile(with: profileId) {
            $0.modMetadata.merge(
                ProfileFactory.metadata(forIds: resolution.ids, in: mods)) { _, new in new }
        }
        // Capturés **avant** `updateProfile` : sur un profil actif, il
        // réapplique le profil au disque, et le rescan qui suit fait passer
        // `syncActiveProfileIds`, qui réécrit `enabledModIds` depuis les mods
        // réellement activés. Relire la ligne après coup, c'est risquer de
        // journaliser l'état du disque plutôt que le résultat de l'import.
        let name = modProfiles[index].name
        let newIds = modProfiles[index].enabledModIds + resolution.ids
        let importedCount = resolution.ids.count
        updateProfile(id: profileId, newName: name, enabledModIds: newIds)
        log(String(format: localization.L(L10n.VM.profileFavoritesImported),
                   importedCount, name, newIds.count))
        return resolution
    }

    /// Ce que donnerait un import des mods « à écarter » dans ce profil. Voir
    /// `favoriteImportPreview` pour l'esprit — la résolution est strictement
    /// symétrique (folders → UniqueIDs, dédupliqué contre `existing`).
    func blacklistImportPreview(profileId: UUID) -> BlacklistResolution.Result {
        guard let profile = profilesStore.profile(with: profileId) else {
            return BlacklistResolution.Result(ids: [], unresolved: [])
        }
        return BlacklistResolution.profileIds(blacklist: blacklistedMods, in: mods,
                                              existing: profile.enabledModIds)
    }

    /// Ajoute tous les mods « à écarter » à un profil. Symétrique d'
    /// `importFavorites(into:)` : les mêmes raisons d'éviter la boucle sur
    /// `addModToProfile`, le même enrichissement de `modMetadata`, le même
    /// filet `guardProfileApply` (R2) avant la moindre mutation, et le même
    /// journal qui distingue le geste d'une passe de ré-application disque.
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

        // La résolution (casse, composants de pack, doublons d'identifiant)
        // vit dans `ProfileFactory.metadata(forIds:in:)` — elle était écrite
        // ici en deux exemplaires, un par import.
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

    /// Copie un profil existant, sous le nom « <original> (copie) ».
    ///
    /// La copie n'est **pas** activée : dupliquer sert à partir d'une base pour
    /// la modifier, et une activation déplacerait aussitôt des dossiers de mods
    /// que personne n'a demandé de bouger.
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
        // Le magasin de configs part avec le profil (B3-T7) : plus aucun
        // écran ne pourrait le nommer, et rien ne le relirait jamais. Le
        // dialogue de confirmation prévient quand il y a quelque chose à
        // perdre — c'est là que la décision se prend, pas ici.
        ProfileConfigStore.delete(profileId: id)
        if activeProfileId == id {
            profilesStore.setActiveProfile(nil)
        }
        saveProfiles()
    }
    
    func updateProfile(id: UUID, newName: String, enabledModIds: [String]) {
        // R2 : l'édition d'un profil actif se termine par une application au
        // disque (branche ci-dessous) — mêmes gardes que l'activation. Sur un
        // profil non actif, `guardProfileApply` est permissif : rien ne
        // bouge, l'édition passe.
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

    /// Les incompatibilités que l'utilisateur a déclarées ou écartées.
    /// Chargé au démarrage (dans `seedNexusAndUserData`, avec les autres
    /// registres utilisateur), réécrit à chaque décision. Fichier :
    /// `Application Support/StarHubFR/mod_conflicts.json`.
    private(set) var modConflictVerdicts = ModConflictVerdicts()

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

    /// Pilote une recherche par moitiés. Créée à la demande : la grande
    /// majorité des sessions ne s'en sert jamais. La paresse d'origine
    /// (`lazy`) est refusée par la macro `@Observable` — sa transformation
    /// fait de la propriété un calcul — d'où le stockage privé et
    /// l'accesseur. Volontairement **non suivi** : les vues qui l'affichent
    /// (`HomeView`, `BisectionCard`) observent le runner lui-même ; le
    /// suivre ici n'invaliderait que le VM entier à chaque état de
    /// bissection.
    @ObservationIgnored
    private var _bisection: BisectionRunner?
    var bisection: BisectionRunner {
        if let _bisection { return _bisection }
        let created = BisectionRunner(vm: self)
        _bisection = created
        return created
    }

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
            .flattenedMods
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
        // Les trois abstentions — jeu ouvert, profil désynchronisé (§6.3),
        // application interrompue (R2) — vivent dans `ProfileConfigCapture`
        // (Core, 14 tests). Elles partagent une règle : laisser le trou
        // visible plutôt que maquiller une donnée fausse.
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
        let touched = ProfileConfigCapture.touchedCount(before: before, after: entries)
        let name = profilesStore.profile(with: profileId)?.name ?? ""
        log(String(format: localization.L(L10n.VM.profileConfigsCaptured), name, touched))
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
            log(localization.L(L10n.VM.profileConfigsSkippedGame), level: .warning)
            // R2 (spec §3.5) : le disque ne portera pas les configs de ce
            // profil — c'est la définition même du desync (doc de
            // `profileConfigsDesyncedProfileId`). Sans marqueur, le trou
            // restait invisible jusqu'à ce qu'une capture future maquille le
            // disque en donnée du profil actif.
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
        // Des `config.json` viennent d'être réécrits : le rapport de
        // raccourcis les lit, il est périmé (X66). Deux profils peuvent
        // n'avoir *que* leurs configurations de différent — le parc ne bouge
        // alors pas, et la signature de `scanIfNeeded` ne verrait rien.
        rescanKeybindsAfterConfigWrite()
        let name = profilesStore.profile(with: profileId)?.name ?? ""
        // Deux comptes plutôt qu'un : « restaurés » masquerait qu'une partie
        // l'a été sans merge, faute d'un texte lisible — la seule information
        // qui distingue une restauration fidèle d'un repli.
        if merged > 0 {
            log(String(format: localization.L(L10n.VM.profileConfigsMerged), name,
                       Int64(verbatim), Int64(merged), Int64(reintroducedKeys)))
        } else {
            log(String(format: localization.L(L10n.VM.profileConfigsRestored), name, verbatim))
        }
    }

    // MARK: - R2 : reprise d'une application interrompue

    /// À appeler une fois la fenêtre principale révélée — le point établi
    /// qui délivre aussi les liens `nxm://` en attente. Idempotent : ne
    /// re-présente pas un dialogue déjà là.
    func surfaceApplyRecoveryIfNeeded() {
        guard pendingApplyRecovery == nil else { return }
        pendingApplyRecovery = unresolvedApplyJournal
    }

    /// Fermer le dialogue sans trancher : le journal reste, l'alerte reviendra
    /// au prochain lancement, l'adoption demeure bloquée en attendant.
    func dismissApplyRecovery() {
        pendingApplyRecovery = nil
    }

    /// Trancher une interruption **sans la reprendre** : l'utilisateur vient
    /// de faire un choix explicite sur ce profil (quitter, activer un autre,
    /// « Garder l'état actuel ») — le disque reste tel quel, le journal part,
    /// le choix est journalisé.
    func clearUnresolvedJournal(implicitKeepNamed name: String) {
        ProfileApplyJournalStore.clear(in: applyJournalDirectory)
        unresolvedApplyJournal = nil
        pendingApplyRecovery = nil
        log(String(format: self.localization.L(L10n.VM.profileRecoveryImplicitKeep), name), level: .warning)
    }

    /// Le texte du dialogue : profil, date, et le cas échéant la mention
    /// d'un profil supprimé (« Reprendre » n'a alors plus de sens — le
    /// dialogue n'offre que d'effacer le signalement).
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

    /// « Reprendre l'application ». Même branche que le re-clic de reprise,
    /// à une différence près : le completion que le crash a avalé portait
    /// aussi la **restauration** des configs du profil entrant (la capture,
    /// elle, avait déjà couru à l'entrée d'`applyProfile`, avant le
    /// dispatch). Reprendre sans restaurer laisserait sur disque les configs
    /// du profil sortant sans aucun marqueur.
    func resumeInterruptedApply() {
        let journal = pendingApplyRecovery ?? unresolvedApplyJournal
        // Le dialogue se ferme dès qu'un geste est fait, y compris sur un
        // refus : c'est l'alerte qui reprendra la main au prochain lancement.
        if journal != nil { pendingApplyRecovery = nil }
        // Les quatre gardes vivent dans `ProfileRecovery` (Core, 11 tests),
        // `isGameRunning()` en closure paresseuse comme pour l'activation.
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

    /// « Garder l'état actuel » — l'adoption explicite de l'état du disque,
    /// celle que `syncActiveProfileIds` refuse tant que le journal vit.
    func keepCurrentDiskState() {
        let journal = pendingApplyRecovery ?? unresolvedApplyJournal
        guard case .settle(let name, let adopting) = ProfileRecovery.keepDiskState(
            journal: journal, active: activeProfileId) else { return }
        pendingApplyRecovery = nil
        clearUnresolvedJournal(implicitKeepNamed: name)
        if adopting { syncActiveProfileIds() }
    }

    /// Le garde des entrées qui **appliquent un profil au disque**.
    ///
    /// Deux refus, chacun avec son message : le jeu ouvert (une application
    /// déplace des centaines de dossiers d'un coup — la bissection refuse
    /// pour la même raison), et le journal d'interruption du profil lui-même
    /// (éditer un profil à moitié appliqué, c'est appliquer un état neuf sur
    /// un accident). Permissif et silencieux quand l'appelant ne déclenchera
    /// de toute façon pas de déplacement (profil non actif, non journalisé).
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
        // L'aiguillage — six branches, dont trois qui ne se rencontrent
        // qu'après un crash ou une application partielle — vit dans
        // `ProfileActivation` (Core, 16 tests). Ici ne restent que les effets.
        //
        // ⚠️ `isGameRunning()` est passé **en closure** : il informe au
        // passage le garde anti double-lancement, et le consulter pour un
        // départ ou un refus déplacerait ce garde sans qu'aucune activation
        // soit en jeu. Un test épingle cette paresse.
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
            // A1-T9 — chiffrer ce que le profil met en pause avant tout effet
            // (verrou posé pendant le scan) ; la reprise redécide.
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
            // Capture AVANT tout : le disque porte encore les réglages du
            // profil sortant. C'est la seule fenêtre où ils existent.
            if let capturing { captureProfileConfigs(for: capturing) }
            if let clearingJournalNamed {
                clearUnresolvedJournal(implicitKeepNamed: clearingJournalNamed)
            }
            syncProfileConfigsDesyncMarker(entering: profileId)
            profilesStore.setActiveProfile(profileId)
            saveProfiles()
            profilesStore.setApplyingId(profileId)
            // Restauration dans le completion : après les déplacements de
            // dossiers et après le rescane, quand les chemins sont ceux du
            // profil entrant.
            applyProfileToFilesystem(profile: profile) { [weak self] _ in
                self?.restoreProfileConfigs(for: profileId)
            }
            log(String(format: localization.L(L10n.VM.switchProfile), profile.name))
        }
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
                                          journaling: Bool = true,
                                          completion: ((_ moveFailures: Int) -> Void)? = nil) {
        // Mark an application in progress so `applyProfile` refuses to start a
        // second one and the UI disables the Activate/Manage buttons until the
        // move + rescan below completes.
        profilesStore.setApplying(true)
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")

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

        // Le plan des renommages est arrêté **ici**, sur l'instantané, et pas
        // relu dans la boucle : les déplacements tournent en tâche de fond, et
        // `mods` est réécrit par `scanMods` — le parcourir de là serait lire un
        // tableau en cours de mutation. La règle elle-même (qui bouge, qui
        // reste, dans quel ordre) vit dans `ProfileApplyPlan`, où elle est
        // testable — ici elle n'aurait aucun test possible.
        let moves = ProfileApplyPlan.moves(applying: profile, to: snapshotMods)

        let profileName = profile.name
        let profileId = profile.id

        // R2 : le journal dit « cette boucle existe » à tout lancement futur.
        // Écrit avant le moindre déplacement, effacé dans le completion — sa
        // présence ne signifie qu'une chose : la boucle est morte en route.
        // La bissection passe `journaling: false` : profil éphémère, et son
        // propre BisectionSnapshotStore couvre ses interruptions.
        if journaling {
            let journal = ProfileApplyJournal(profileId: profileId,
                                              profileName: profileName,
                                              startedAt: Date(),
                                              moves: moves)
            // Une écriture échouée (disque plein, droits refusés) prive le
            // prochain lancement du filet de reprise après crash : la boucle
            // mourrait en route, le journal n'existerait pas, et l'app ne
            // proposerait pas de récupérer. On logue et on continue — la
            // session courante reste correcte, c'est la **prochaine** qui
            // perdra la mémoire.
            if let err = ProfileApplyJournalStore.save(journal, in: applyJournalDirectory) {
                log(String(format: localization.L(L10n.VM.profileApplyJournalWriteFailed),
                           profileName, err.localizedDescription), level: .error)
            }
            unresolvedApplyJournal = journal
        }
        // Le total est connu d'avance : la barre est déterminée dès le premier
        // dossier. Publié avant le dispatch pour que le voile soit là au
        // premier rendu, sans clignotement.
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
            // Les dossiers sont en place ; ce qui suit est la relecture du
            // parc. Le voile le dit, sinon la barre reste pleine et figée
            // pendant tout le rescane.
            self.profileApplyProgress = ProfileApplyProgress(done: total,
                                                             total: total,
                                                             phase: .rescanning)
            // Le scan est lourd (parcours du parc, décodage des manifestes,
            // journal SMAPI — des secondes sur un grand parc) : il tourne
            // HORS main, comme l'appelaient la file globale d'avant et
            // `refresh()` (T10). La suspension laisse le voile se rendre ;
            // la reprise revient sur main, et la suite garde l'ordre
            // d'origine. `scanMods` est `nonisolated` depuis la tranche
            // d'isolation : le saut par la file globale reste, c'est lui qui
            // porte le travail lourd hors main — et le dossier de jeu se
            // résout ici, sur l'acteur, pour ne pas se lire au fond.
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

    /// Formats `headline` followed by a newline-separated, truncated list of
    /// `names`. After `limit` entries, a "+N more" suffix is appended instead
    /// of dumping the whole list into the alert.
    private func truncatedList(headline: String, names: [String], limit: Int) -> String {
        let shown = names.prefix(limit).joined(separator: " • ")
        let extra = names.count > limit ? " (+\(names.count - limit))" : ""
        return headline + "\n" + shown + extra
    }

    /// Renomme un dossier de mod dans `Mods/`, en traitant le cas où la
    /// destination est déjà occupée.
    ///
    /// La règle vivait en **deux exemplaires** (bascule unitaire, bascule en
    /// masse) et manquait au **troisième** chemin, l'application d'un profil,
    /// qui se contentait d'échouer avec le message brut du système. Les deux
    /// exemplaires divergeaient déjà : l'un préfixait d'un point le dossier
    /// écarté, l'autre non — cf. `ModFolderCollision.asideName`.
    ///
    /// Le travail disque vit dans `ModFolderRename.moveReplacingStaleDestination`
    /// (Core, testé) — P5-T9 l'y a porté avec les deux types d'erreur
    /// (`FolderToggleRefusal`, `ModFolderRenameFailure`) : une fonction
    /// fichier ne journalise plus sur place, l'échec d'un rollback raté
    /// **remonte** dans l'erreur (`ModFolderRenameFailure.rollbackFailed`,
    /// avec `strandedAt`) et ce sont les trois appelants, qui savent écrire
    /// au journal, qui le disent. Cette façade reste pour les trois chemins
    /// de bascule ; elle ne touche à rien d'autre, et ne deviendra que plus
    /// légère à l'heure du `@MainActor`.
    ///
    /// - Throws: `FolderToggleRefusal.folderClaimedByAnotherMod` quand la
    ///   destination appartient à un **autre** mod (le déplacer lui ferait
    ///   perdre favori, note, config de profil et identifiant Nexus, sans un
    ///   mot) ; `ModFolderRenameFailure` pour un déplacement ou un rollback
    ///   en échec.
    nonisolated private func renameModFolder(from srcPath: String, to dstPath: String,
                                 destinationName: String, uniqueId: String,
                                 fm: FileManager) throws {
        try ModFolderRename.moveReplacingStaleDestination(from: srcPath, to: dstPath,
                                                          destinationName: destinationName,
                                                          uniqueId: uniqueId, fm: fm)
    }

    // MARK: - Règle de cadrage de la liste des mods
    //
    // La règle qui décide quels mods la liste montre — et, depuis X57, ceux
    // sur lesquels la bascule en masse agit. Elle vivait dans `ModListView` :
    // « Tout activer » parcourait alors `mods` en entier (949 dossiers sur le
    // parc de référence), filtré ou non. La liste et la bascule la partagent
    // désormais au lieu de la recopier — deux pipelines jumeaux divergent à
    // la première retouche, X45 en compte dix. Formulation de Stardrop
    // (`c630c11`, 2026-09-01) : « what the user is looking at is what they
    // act on ». La pagination n'entre pas dans la règle : c'est un artefact
    // d'affichage, pas une intention — la bascule agit sur tout le résultat
    // filtré, pas sur la page visible.

    /// Whether `mod` itself satisfies `predicate`, or — for a group — any of
    /// its children do. Standalone mods just apply the predicate directly.
    /// The single "does this row match X" test shared by search and the
    /// issues filter, so the two can't independently drift out of sync (a
    /// group's own `dependencies`/`uniqueId` are empty, so checking the
    /// group itself before its children is always safe and often a no-op).
    /// Façade **provisoire** vers `ModListScoping` : les vues appellent encore
    /// ces prédicats sur le ViewModel (six sites dans `ModListView`). Elles
    /// passeront directement au type extrait quand la vue sera découpée (§P8) ;
    /// d'ici là, la règle n'a qu'une définition, ici comme là-bas.
    func matchesSelfOrAnyChild(_ mod: ModItem, _ predicate: (ModItem) -> Bool) -> Bool {
        ModListScoping.matchesSelfOrAnyChild(mod, predicate)
    }

    /// La même règle que la pastille d'anomalie. Elle ne l'était pas : le
    /// cadrage ne regardait que les dépendances quand la pastille couvrait
    /// aussi les erreurs du journal et les manifestes sans identifiant — un
    /// mod portant une pastille pouvait manquer à l'onglet censé les réunir.
    /// Mesuré avant de les réunir : sur les versions installées du parc,
    /// cela n'ajoute qu'une erreur et cinq avertissements.
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

    /// Les trois magasins de couverture, rassemblés pour le cadrage. Construit à
    /// chaque appel : ce sont trois copies de références (`Dictionary` et `Set`
    /// sont à copie sur écriture), pas un parcours.
    private var translationScopingState: ModListScoping.TranslationState {
        .init(coverage: frenchCoverageByMod, stale: staleTranslationMods,
              outdatedKeys: outdatedKeysByMod)
    }

    /// La liste cadrée : les cinq filtres composés, puis triée. C'est la
    /// source dont `ModListView.filteredMods` et `toggleAllMods` dérivent
    /// tous deux — le scope (`scopedMods(from:scope:)`) et la pagination
    /// (vue) s'appliquent par-dessus.
    /// Les entrées du cadrage, assemblées **ici et nulle part ailleurs** : les
    /// deux closures capturent `self`, et les faire construire par une vue les
    /// ferait vivre dans un `@State` retenant le ViewModel.
    ///
    /// Capture **forte**, à dessein. La règle du dépôt (`weak self` obligatoire)
    /// vise les closures confiées à `DispatchQueue.global().async`, qui
    /// survivent à leur appelant ; celles-ci sont construites et consommées dans
    /// un seul appel synchrone. Un `weak` n'y protégerait rien et changerait un
    /// plantage impossible en réponses fausses et muettes : « aucune catégorie »,
    /// « aucun poids mesuré ».
    private var scopingInputs: ModListScoping.Inputs {
        .init(category: { self.category(for: $0) },
              sizeOnDisk: { self.sizeOnDisk(of: $0) },
              favorites: favoriteMods,
              blacklisted: blacklistedMods,
              translation: translationScopingState,
              activationDates: modActivationTimestamps)
    }

    /// La liste cadrée : les six filtres composés, puis triée. C'est la source
    /// dont `ModListView.filteredMods` et `toggleAllMods` dérivent tous deux —
    /// le cadrage (`scopedMods(from:scope:)`) et la pagination (vue)
    /// s'appliquent par-dessus.
    func mods(matching filters: ModListFilters) -> [ModItem] {
        let inputs = scopingInputs
        let filtered = mods.filter { ModListScoping.matches($0, filters: filters, inputs: inputs) }
        return ModListScoping.sorted(filtered, by: filters.sort, inputs: inputs)
    }

    /// La liste cadrée restreinte au scope courant — ce que la section
    /// « Tous / Activés / En pause / Problèmes » montre, et l'ensemble
    /// exact sur lequel la bascule en masse agit (X57).
    ///
    /// **Pas** de partition actifs/en pause sous « Tous » : grouper d'abord
    /// par état écraserait le tri choisi — trier par poids remontait le plus
    /// gros mod *actif*, jamais le plus gros du parc, alors que les trois
    /// quarts du poids dorment dans des mods en pause. L'état reste lisible
    /// ligne à ligne dans la liste ; ici, l'ordre du tri passe tel quel.
    func scopedMods(from filtered: [ModItem], scope: ModFilter) -> [ModItem] {
        ModListScoping.scoped(filtered, scope: scope, hasAnomaly: { self.hasIssues($0) }, pendingUpdates: { .current(self) })
    }


    /// Enable or disable every installed mod at once. File operations run on a
    /// background queue so the UI (and the progress bar) stay responsive. Each
    /// move uses the same "stale duplicate aside" safety pattern as
    /// `performToggle` — **garde de collision comprise** : un dossier déjà
    /// présent à destination n'est mis de côté que s'il porte l'identité du mod
    /// qu'on bascule, sans quoi le mod est refusé et compté dans le bilan.
    /// Progress is published after every move. Activation
    /// timestamps are stamped only for mods that were actually moved.

    /// `modList.filters`. Filtrer puis « Tout désactiver » ne touche que
    /// l'ensemble cadré, pas les 949 dossiers du parc.
    @MainActor
    func toggleAllMods(enable: Bool, fingerprintChecked: Bool = false) {
        // Guard against re-entry: a second tap while the first run is still
        // moving folders would race on the same source/destination paths.
        // Et contre la file des toggles unitaires : un performToggle en vol
        // croiserait les moves bulk sur les mêmes dossiers (l'unitaire renomme
        // sur main, la masse en background) — les gardes disque contiennent
        // la collision, ce garde l'empêche d'exister.
        guard bulkToggleProgress == nil, !isToggling, pendingToggles.isEmpty,
              !saveFingerprintPauseStore.isBusy else { return }

        // X57 : l'ensemble vient du cadrage courant de la liste — la même
        // règle qui la rend (filtres, catégorie, traduction, scope), pas le
        // parc entier. Instantané pris ici, sur le main thread : les filtres
        // ne peuvent plus changer l'ensemble une fois la bascule partie en
        // arrière-plan.
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

        // La bascule en masse construit ses moves depuis l'instantané :
        // la source porte le nom physique actuel, la destination l'état
        // visé — la même primitive que le plan de profil.
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

        // Le Task hérite de @MainActor : les écritures d'état sont directes.
        // L'arrière-plan vit DANS l'exécutant — plus aucune closure lourde ici.
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
            // Rescan so the list reflects the real on-disk state, whatever it
            // is after partial failures. syncActiveProfileIds runs after so the
            // active profile's stored id list tracks the actual enabled set.
            // Le scan est lourd : il vit hors main (T10) — la suspension
            // laisse la barre de bascule se rendre avant le blocage, la
            // reprise revient sur main et la suite garde l'ordre d'origine.
            // `scanMods` est `nonisolated` depuis la tranche d'isolation :
            // le saut par la file globale porte le travail lourd hors main, et
            // le dossier de jeu se résout ici, sur l'acteur.
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

    /// Permanently delete a mod (or an entire mod pack) from disk. The mod's
    /// folder is removed from `Mods/` (disabled mods live there as `.X`,
    /// enabled ones as `X`). For a pack (`isGroup == true`), this deletes the
    /// single top-level folder that contains all child mods. The mod list is
    /// rescanned afterward so the UI reflects the real on-disk state. Surfaces
    /// a user-visible alert on failure.
    /// Oublie tout ce que les magasins persistés savaient d'un mod supprimé
    /// (X55). Politique tranchée le 2026-09-04 : **on efface tout** — ce qu'on
    /// supprime disparaît, et une réinstallation repart d'une page blanche.
    ///
    /// Quatre magasins étaient indexés sur le nom de dossier et survivaient à
    /// la suppression. Le plus visible : la vitrine Découverte affichait
    /// encore « Je l'ai ». Le plus coûteux, quoique rare : un dossier
    /// **réutilisé par un autre mod** héritait du drapeau « sa config suit le
    /// profil », et le changement de profil suivant lui restaurait la
    /// configuration du disparu.
    ///
    /// Un pack emporte ses composants — leur `folderName` est le chemin
    /// relatif sous lui — sans toucher au voisin dont le nom commence pareil :
    /// la règle vit dans `ModRemovalPurge`, avec ses tests.
    ///
    /// Chaque magasin n'est réécrit **que s'il a changé** : réécrire les
    /// préférences pour rien à chaque suppression n'apporte rien.
    private func forgetStores(of mod: ModItem) {
        let folder = mod.folderName
        // X107 — le favori et la marque « à écarter » partent ici, pas dans la
        // seule branche de succès de `deleteMod` : la branche « dossier déjà
        // absent » (le mod a quitté le disque hors de l'app) les laissait
        // orphelins, et le badge Favoris comptait un mod qu'aucune ligne ne
        // montrait. `ModRemovalPurge` emporte aussi les composants d'un pack.
        if ModRemovalPurge.purge(&favoriteMods, removing: folder) {
            Self.saveFavoriteMods(favoriteMods)
        }
        if ModRemovalPurge.purge(&blacklistedMods, removing: folder) {
            Self.saveBlacklistedMods(blacklistedMods)
        }
        // L'historique d'erreurs et la référence de traduction grossiraient
        // sinon indéfiniment avec des mods qui ne sont plus installés.
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
        // « Je l'ai déjà » dans la vitrine : `installedNexusInstalls` n'est
        // qu'un complément de ce que le disque dit (`installedNexusIds()` en
        // fait l'union avec les mods réellement installés). Le retrait est
        // donc sans risque même quand deux mods partagent un identifiant
        // Nexus — 58 cas sur le parc : celui qui reste installé continue de
        // se voir par l'autre moitié de l'union.
        if let id = Int(resolvedNexusModId(for: mod)) {
            recentNexusInstalls.remove(id)
        }
        forgetTranslations(of: folder)

        // C2-T4 — le delta du mod n'a plus de titulaire. Un pack emporte
        // ceux de ses composants : l'en-tête de groupe n'a pas d'identifiant
        // (""), ce sont les enfants qui portent les fichiers <uniqueId>.json.
        // Sans eux, la fiche d'un composant réinstallé ressusciterait le
        // delta d'un install qui ne décrit plus rien (promesse X55).
        if let dir = ModUpdateKeyDeltaStore.defaultDirectory() {
            ModUpdateKeyDeltaStore.removeAll(
                uniqueIds: [mod.uniqueId] + (mod.children ?? []).map(\.uniqueId),
                directory: dir)
            // Le store a changé : les caches de lecture (delta, paires) ne
            // doivent pas ressusciter un fichier qui vient de partir — cas
            // réel du parc, deux dossiers partageant un même UniqueID.
            updateKeyDeltasRevision += 1
        }
    }

    /// X69 — le registre des traductions et des greffes, oublié lui aussi.
    ///
    /// Le renommage le migre (`installedTranslations.rename(host:to:)`, un des
    /// douze magasins de X60) ; la suppression, elle, ne le touchait pas. Sur
    /// le parc de référence, il gardait une greffe posée sur
    /// `[CP] Make Gunther Real`, un mod absent du disque : l'entrée affirme
    /// qu'une traduction est installée sur un mod qui n'existe plus.
    ///
    /// `forgetEverything` et non `forget(host:)` : ce dernier ne vide que
    /// `byHost`, et l'orphelin du parc vivait justement dans `addonsByHost` —
    /// le câblage seul n'aurait pas suffi.
    ///
    /// **Les originaux mis à l'abri partent avec.** Les valeurs de
    /// `replacedFiles` sont les seuls pointeurs vers eux, et rien ne balaie
    /// `TranslationBackups/` : les oublier sans les retirer échangerait une
    /// entrée fausse contre des octets que plus personne ne désigne. On ne
    /// retire que ce qui vit **sous la racine des sauvegardes** — un chemin
    /// venu d'ailleurs ne s'efface pas sur la foi d'un registre.
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
        // Un échec se dit, mais une fois : huit fichiers récalcitrants ne
        // valent pas huit lignes de journal. Et il ne s'avale pas non plus —
        // c'est la seule occasion de savoir que des octets sont restés.
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
        // A mod always lives under Mods/ now — disabled ones carry a leading
        // dot in their physical folder name. `physicalFolderName` resolves
        // the right on-disk path regardless of enabled state.
        let modPath = (modsPath as NSString).appendingPathComponent(mod.physicalFolderName)

        let fm = FileManager.default
        guard fm.fileExists(atPath: modPath) else {
            showModal(message: localization.L(L10n.Mods.deleteNotFound))
            // Le dossier a disparu hors de l'app (Finder, mise à jour ratée,
            // autre gestionnaire) : c'est **le** producteur de traces mortes,
            // parce que ce chemin ne touchait aucun magasin. On purge ici
            // aussi — et ce n'est pas le balayage que X25 interdit : là-bas
            // une absence *déciderait seule* d'une suppression, ici
            // l'utilisateur vient de demander la suppression de ce mod
            // nommément. Le consentement fait toute la différence.
            forgetStores(of: mod)
            let resolvedGameDir = gameDir
            DispatchQueue.global(qos: .userInitiated).async {
                self.scanMods(gameDir: resolvedGameDir)
            }
            return
        }

        // Mark this row as deleting so its spinner shows until the rescan
        // that follows the folder removal has republished `mods`.
        pendingDeleteFolder = mod.folderName

        do {
            // X103-B — « supprimer » met en corbeille : le dossier déménage
            // sous `Mods/_Trash_<horodatage>/<feuille logique>`, le préfixe
            // que le scanner saute déjà au niveau 1. Rien n'est effacé ici :
            // la purge est un geste explicite de l'écran Entretien, jamais
            // une heuristique (leçon X25). La feuille est le nom **logique**
            // (jamais le point) — un composant de pack supprimé un à un
            // atterrit à plat, sous son propre nom.
            let leaf = (mod.folderName as NSString).lastPathComponent
            if let failure = ModTrash.trash(
                modsPath: modsPath, stamp: ModTrash.makeStamp(),
                items: [.init(physical: mod.physicalFolderName, logicalLeaf: leaf)]).failed.first {
                throw failure.error
            }
            // The registry entry is pruned by the next scanMods() (below),
            // which removes entries for folders no longer on disk. Every
            // other folder-keyed store is forgotten by `forgetStores` — the
            // one purge both branches of this function share (X107).
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

    /// Les événements de corbeille, du plus récent au plus ancien. Lu à la
    /// demande (ouverture de l'écran Entretien, geste de remise/purge) — pas
    /// un état que le scan entretient, la corbeille est hors liste par
    /// construction.
    var trashEvents: [ModTrash.Event] { maintenanceStore.trashEvents }

    func refreshTrash() {
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let events = ModTrash.events(modsPath: modsPath)
            // X114 — même passe : la quarantaine du réparateur (les
            // `_Trash_*` sans marqueur) se lit sur le même listing.
            let quarantined = ModTrash.quarantineItemCount(modsPath: modsPath)
            DispatchQueue.main.async {
                guard let self else { return }
                self.maintenanceStore.setTrashEvents(events)
                self.maintenanceStore.setQuarantineItemCount(quarantined)
            }
        }
    }

    /// Remet un mod de la corbeille : `Mods/.<nom>` — **désactivé**, même
    /// règle que la restauration de sauvegarde (§5.6). L'utilisateur le
    /// réactive explicitement ; le rescan qui suit le fait réapparaître.
    func restoreTrashEntry(event: String, entry: String) {
        restoreFromTrash(event: event) {
            ModTrash.restoreEvent(modsPath: $0, event: event, entries: [entry],
                                  stamp: ModTrash.makeStamp())
        }
    }

    /// « Tout remettre » : l'événement entier revient en pause, un seul
    /// rescan — le pendant d'un vidage des mods en pause (X112).
    func restoreTrashEvent(_ event: String) {
        restoreFromTrash(event: event) {
            ModTrash.restoreEvent(modsPath: $0, event: event, stamp: ModTrash.makeStamp())
        }
    }

    /// Le trajet commun des deux remises : garde, travail hors main, puis
    /// journal, erreur, corbeille relue et rescan (hors main aussi — gel
    /// ~960 mods, 2026-09-14).
    private func restoreFromTrash(event: String,
                                  _ work: @escaping @Sendable (String) -> ModTrash.TrashResult) {
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        // Même garde que la purge : un event non marqué (quarantaine du
        // réparateur, nom forgé) n'est pas une corbeille à remettre.
        guard ModTrash.isUserEvent(modsPath: modsPath, event: event) else {
            showModal(message: String(format: localization.L(L10n.Maintenance.trashFailed2), event))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = work(modsPath)
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

    /// Purge nominative : une entrée, pour de bon. Jamais appelée sans la
    /// confirmation de l'écran Entretien.
    func purgeTrashEntry(event: String, entry: String) {
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try ModTrash.purgeEntry(modsPath: modsPath, event: event, entry: entry)
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

    /// Vide toute la corbeille. Le compte annoncé par la confirmation vient
    /// du même `trashEvents` que l'écran affiche — un chiffre qui divergerait
    /// de ce qui part serait un mensonge.
    func purgeAllTrash() {
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let removed = try ModTrash.purgeAll(modsPath: modsPath)
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
        // Le nom et l'identifiant Nexus sont rafraîchis en même temps : ce sont
        // les seules traces qui resteront le jour où l'un de ces mods aura été
        // désinstallé. Ce qui était su des mods **sortis** du profil est
        // abandonné avec eux — le profil ne les réclame plus.
        profilesStore.mutateProfile(with: id) {
            $0.modMetadata = ProfileFactory.metadata(of: enabledMods)
        }
        saveProfiles()
        // Le profil vient d'adopter l'état du disque : il n'y a plus d'écart
        // en suspens à protéger.
        incompletelyAppliedProfileIds.remove(id)
    }

    // MARK: - Entretien (X25)

    /// Construit l'inventaire d'entretien. Une **seule** traversée du dossier
    /// de sauvegardes : taille et fichiers utilisateur sont relevés ensemble.
    /// Mesuré le 2026-09-04 : 0,86 s pour 17 628 fichiers, d'où le passage
    /// hors du fil principal et le témoin de chargement.
    func buildMaintenanceReport() {
        guard maintenanceStore.beginBuilding() else { return }
        // X74 — les en-têtes de packs comptent : une préférence se pose sur la
        // **ligne** qu'on a sous les yeux, pas sur une identité. Le champ
        // « identifiant Nexus » et le sélecteur de catégorie sont offerts sur
        // la fiche d'un pack — c'est même le seul endroit sensé pour eux, un
        // composant n'ayant pas de page Nexus — et la bascule horodate la
        // ligne de tête. `flattenedMods` seul les déclarait mortes.
        let installedFolders = mods.preferenceKeyableFolders
        // X70 — un parc vide ne juge aucune clé morte (`stalePreferenceKeys`
        // s'en garde). Mais l'écran afficherait alors « rien à nettoyer » sans
        // dire pourquoi : le dire ici, c'est la seule trace que l'utilisateur
        // aura de la différence entre « tout est propre » et « je n'ai rien
        // pu lire ».
        if installedFolders.isEmpty {
            log("Entretien : aucun mod lu (dossier de jeu introuvable, ou "
                + "balayage en cours) — les clés de préférences ne sont pas jugées",
                level: .warning)
        }
        // X76 — l'état de lecture de l'index doit exister **avant** la passe :
        // un index absent ou corrompu ne rend orpheline aucune session, et le
        // dire est la seule trace que l'utilisateur aura de la différence
        // entre « rien à nettoyer » et « je n'ai rien pu lire ».
        let installRead = ModInstallBackupManager.shared.loadBackupsWithIndexState()
        if !installRead.indexWasReadable {
            log(self.localization.L(L10n.Maintenance.indexUnreadable), level: .warning)
        }
        let translationPathsByHost = installedTranslationRelativePaths()
        // `gameDir` et les clés de préférences se lisent **avant** la file :
        // propriétés du VM isolées sur l'acteur principal depuis L2, seules
        // leurs valeurs (Sendable) traversent la closure. La lecture des
        // sauvegardes, lourde, reste dans la closure.
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

    /// Les clés des six magasins indexés par nom de dossier — les quatre que
    /// X55 a câblés à la suppression d'un mod (35 entrées d'avant X55
    /// mesurées le 2026-09-04), plus les favoris et la marque « à écarter »
    /// (X107 : un orphelin sur le parc le 2026-09-24).
    private func maintenancePreferenceKeys() -> Set<String> {
        MaintenanceInventory.folderKeyedPreferenceKeys(
            favorites: favoriteMods,
            blacklisted: blacklistedMods,
            profileManagedConfigs: profileManagedConfigMods,
            activationTimestamps: modActivationTimestamps.keys,
            nexusModIds: nexusCustomModIds.keys,
            nexusCategories: nexusCustomCategories.keys)
    }

    /// Les chemins des traductions et greffes que **l'app** a posées, par mod
    /// hôte. Une traduction d'auteur (`i18n/default.json`) n'en fait pas
    /// partie : elle revient avec le mod, donc elle ne protège aucune
    /// sauvegarde.
    ///
    /// ⚠️ Ces chemins sont relatifs au dossier **`Mods/`** — ils portent le nom
    /// du mod hôte en tête (`[CP]Cloths and Colors/i18n/fr.json`), là où le
    /// chemin d'une sauvegarde est relatif à **sa propre racine**
    /// (`i18n/fr.json`). La comparaison se fait par suffixe de segment, jamais
    /// par égalité — et **bornée à l'hôte de la sauvegarde** : l'appariement
    /// tous-hôtes étiquetait à tort 59 fichiers du parc, tous des
    /// `i18n/*.json` d'auteur (X75). Voir
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

    /// La lecture proprement dite. Statique : aucune capture de `self`, donc
    /// aucune mutation `@Published` hors du fil principal. `nonisolated` (L2) :
    /// elle ne touche que des fichiers et ses seules entrées sont des valeurs.
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
            // Le nom de session vient du manager : la même règle que celle qui
            // supprime le dossier horodaté (premier composant sous `backups/`,
            // suffixe de nommage compris). Une formule locale, même simplifiée,
            // désynchroniserait l'inventaire de ce qui part vraiment.
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

    /// Taille et fichiers utilisateur d'une sauvegarde, en **une** traversée.
    /// `nil` quand le dossier n'existe plus. La règle de classification vit
    /// dans `MaintenanceInventory.classifyUserFile` — appariement **borné à
    /// l'hôte de la sauvegarde** (X75). `nonisolated` (L2) : marche de
    /// fichiers pure, appelée depuis le rapport hors de l'acteur principal.
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
        // ⚠️ `resolvingSymlinksInPath()` avant tout retrait de préfixe : sur macOS
        // l'énumérateur rend des chemins résolus (`/private/var…`) même quand la
        // racine passait par `/var…`.
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

    /// Ce que le mod porte aujourd'hui, limité aux chemins qui nous intéressent.
    /// `presentFiles` vaut `nil` quand le dossier du mod n'existe plus — actif ou
    /// en pause, les deux formes sont cherchées. `nonisolated` (L2) : lecture
    /// disque pure, appelée depuis le rapport hors de l'acteur principal.
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

    /// Met à la corbeille les sauvegardes que `keepPerMod` écarte, et rend leur
    /// nombre. Les protégées ne partent jamais — la règle est dans
    /// `MaintenanceInventory.plan`, pas ici.
    ///
    /// **Corbeille, pas suppression** : une action qui retire 723 Mo mérite le
    /// filet du Finder. L'écran doit dire que l'espace n'est rendu qu'après
    /// vidage, sinon le chiffre annoncé ment.
    @discardableResult
    func purgeInstallBackups(keepPerMod: Int) -> Int {
        guard let report = maintenanceReport else { return 0 }
        let plan = MaintenanceInventory.plan(keepPerMod: keepPerMod,
                                             entries: report.backups,
                                             protections: report.protections)
        guard !plan.doomed.isEmpty else { return 0 }
        let doomedIds = Set(plan.doomed.map(\.id))
        var removed = 0
        // L'index est la source de vérité : on passe par le manager pour que
        // l'entrée disparaisse avec le dossier. Le dossier horodaté vient du
        // manager lui-même — la même règle qui le supprime, et la même clé
        // (`lastPathComponent`) que l'inventaire a relevée.
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

    /// Retire les dossiers de session sans index et les clés de préférences sans
    /// mod. Rend le nombre total d'éléments retirés.
    ///
    /// C'est le « nettoyage explicite » que **X25** réclame : un bouton, jamais
    /// une passe au lancement — là-bas, une absence déciderait seule d'une
    /// suppression, ici l'utilisateur a vu ce qui part et a cliqué.
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

    /// Le mod n'est plus installé : il n'y a **pas** de dossier où écrire, et en
    /// fabriquer un reviendrait à le réinstaller. On montre le fichier dans le
    /// Finder — l'utilisateur en fait ce qu'il veut, et la sauvegarde reste
    /// protégée tant qu'elle est la seule copie.
    func revealProtectedBackup(atPath path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Retire une sauvegarde protégée, à la demande explicite de l'utilisateur.
    /// Elle passe par la corbeille comme les autres : c'est le filet, et il vaut
    /// d'autant plus ici que le fichier n'existe nulle part ailleurs.
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

    /// Les sauvegardes d'origine par session de l'inventaire — le `Report`
    /// n'en porte que l'essentiel, la récupération a besoin du reste.
    private func maintenanceBackupsBySession() -> [String: ModInstallBackup] {
        let manager = ModInstallBackupManager.shared
        return Dictionary(manager.loadBackups().map {
            (manager.backupDirectory(of: $0).lastPathComponent, $0)
        }, uniquingKeysWith: { first, _ in first })
    }

    /// Les seules copies à remettre en place, par `SoleCopyFile.id` — celles
    /// dont le mod vit encore. Sauvegardes lues **une** fois pour la liste.
    /// Absente du résultat quand la sauvegarde ou le dossier du mod a disparu
    /// depuis l'inventaire : l'écran ne propose alors que le Finder.
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

    /// Le chemin du fichier dans la sauvegarde, pour le montrer dans le Finder
    /// quand le mod n'est plus là pour le recevoir.
    func maintenanceProtectedFilePath(session: String, relativePath: String) -> String? {
        guard let backup = maintenanceBackupsBySession()[session] else { return nil }
        return (backup.backupPath as NSString).appendingPathComponent(relativePath)
    }
}

// MARK: - L10nResolver
//
// `SaveFarmNameResolver` consomme un `L10nResolver` (protocole Core) pour
// rester testable sans VM. La conformité vit désormais sur le store du
// domaine (`LocalizationStore`, qui porte la résolution) — `SavesView`
// lui passe le store directement.
