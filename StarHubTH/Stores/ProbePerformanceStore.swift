import Foundation
import Observation

/// L'état de l'onglet Performances (D4-T4 §3b) et de la mesure guidée (D5-A). Les fichiers de la sonde pèsent
/// plusieurs Mo : lus hors du fil principal (`Task.detached`), une passe,
/// avec le cache par taille + date de `ProbeSessionsIndex`. Possédé par la
/// vue (`@State` de `DiagnosticsView`), jamais par le ViewModel (F1-T2).
@MainActor
@Observable
final class ProbePerformanceStore {
    enum Status: Equatable { case idle, loading, noProbe, needTwo, ready }

    private(set) var status: Status = .idle
    private(set) var sides: [ProbeSide] = []
    private(set) var report: ProbePerformanceReport?
    private(set) var singleSummary: ProbePerformanceSummary?
    private(set) var isComputing = false
    private(set) var guidedMinuteCount = 0
    private(set) var beforeId: String?
    private(set) var afterId: String?
    /// Mesures guidées lues dans `guided-measurements.jsonl` (D5-A).
    private(set) var measurements: [ProbeMeasurement] = []
    /// Plan en attente dans `guided-plan.json` ; l'app est seule à l'effacer.
    private(set) var plan: GuidedPlan?
    private(set) var unreadableLines = 0
    /// Diffs clé par clé des réglages modifiés de la paire affichée, par `modId`.
    private(set) var configDiffs: [String: [ConfigKeyDiff]] = [:]
    /// D5-B — les chargements lus dans `loads.jsonl`, la carte et le verdict.
    private(set) var loads: [ProbeLoadRecord] = []
    private(set) var lastLaunch: ProbeLoadBreakdown?
    private(set) var lastSave: ProbeLoadBreakdown?
    private(set) var launchComparison: ProbeLoadComparisonResult?
    private(set) var saveComparison: ProbeLoadComparisonResult?
    /// Enregistrements « cache froid » (premier lancement depuis le démarrage).
    private(set) var coldRecordIds: Set<String> = []
    /// Vrai si la sonde installée écrit `loads.jsonl` (0.6.0+).
    private(set) var probeWritesLoads = false

    @ObservationIgnored private let files: ProbeFiles
    @ObservationIgnored private var configDiffsTask: Task<Void, Never>?
    @ObservationIgnored private var configDiffsChanges: [ProbeModChange]?
    @ObservationIgnored private let loader: @Sendable (String?) async -> ProbePerformanceSnapshot
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var selectionGeneration = 0
    @ObservationIgnored private var reportTask: Task<Void, Never>?

    init(files: ProbeFiles = ProbeFiles(),
         loader: (@Sendable (String?) async -> ProbePerformanceSnapshot)? = nil) {
        self.files = files
        let index = ProbeSessionsIndex(files: files)
        self.loader = loader ?? { gameDir in
            await Task.detached(priority: .userInitiated) {
                ProbePerformanceSnapshot.read(files: files, index: index, gameDir: gameDir)
            }.value
        }
    }

    var configsDirectory: URL { files.configsDirectory }
    var protocolState: GuidedProtocolState { GuidedProtocol.state(plan: plan, measurements: measurements) }

    func reload(gameDir: String? = nil) async {
        // Mesures déjà connues avant la lecture : seules les nouvelles peuvent
        // prendre la sélection (ci-dessous).
        let knownMeasurementIds = Set(measurements.map(\.id))
        // Première lecture seulement : une relecture garde l'écran affiché
        // (retour dans l'app, changement de segment) au lieu de le vider.
        if status == .idle { status = .loading }
        loadGeneration += 1
        let generation = loadGeneration
        let selectionAtStart = selectionGeneration
        let loaded = await loader(gameDir)
        guard generation == loadGeneration, !Task.isCancelled else { return }
        let summary = await Task.detached(priority: .userInitiated) {
            ProbePerformanceSummary.latestSession(loaded.sides)
        }.value
        guard generation == loadGeneration, !Task.isCancelled else { return }
        singleSummary = summary
        guidedMinuteCount = loaded.guidedMinuteCount
        sides = loaded.sides
        if let finished = loaded.finishedPlan {
            do {
                try GuidedPlan.remove(at: files.guidedPlanURL, ifId: finished)
            } catch {
                // Plan resté sur disque : la prochaine relecture le verra clos
                // et réessaiera ; rien à montrer.
            }
        }
        measurements = loaded.measurements
        plan = loaded.plan
        unreadableLines = loaded.unreadable
        // La carte « Chargements » vit aussi en `.needTwo` : avant les gardes.
        loads = ProbeLoadRecords.manual(loaded.loads)
        lastLaunch = loads.last { $0.kind == .launch }.map(ProbeLoadBreakdown.of)
        lastSave = loads.last { $0.kind == .save }.map(ProbeLoadBreakdown.of)
        // Le froid se juge sur tous les lancements : si une chauffe de
        // benchmark était le premier lancement après le démarrage du Mac,
        // le filtrer d'abord ferait passer le lancement manuel suivant pour froid.
        coldRecordIds = Set(loaded.loads.filter {
            ProbeLoadComparison.isCold($0, among: loaded.loads, coldBefore: loaded.coldBefore) }.map(\.id))
        launchComparison = ProbeLoadComparison.compare(loads, kind: .launch, launches: loaded.launches,
                                                       changes: loaded.changes, coldBefore: loaded.coldBefore)
        saveComparison = ProbeLoadComparison.compare(loads, kind: .save, launches: loaded.launches,
                                                     changes: loaded.changes, coldBefore: loaded.coldBefore)
        probeWritesLoads = ProbeLoadRecords.writesLoads(probeVersion: loaded.launches.last?.probe)
        guard loaded.hasProbe else { clearSelection(); status = .noProbe; return }
        guard sides.count >= 2 else { clearSelection(); status = .needTwo; return }
        // Une mesure close depuis la lecture précédente prend la sélection :
        // la paire qu'elle forme avec celle qu'elle désigne est ce qu'on vient
        // de jouer — la paire affichée d'avant est périmée. Ensuite garder la
        // paire choisie si elle existe encore, sinon la paire par défaut.
        if selectionAtStart == selectionGeneration, let pair = freshGuidedPair(known: knownMeasurementIds) {
            await select(before: pair.before.id, after: pair.after.id).value
        } else if let beforeId, let afterId, sides.contains(where: { $0.id == beforeId }),
           sides.contains(where: { $0.id == afterId }) {
            await select(before: beforeId, after: afterId).value
        } else if let pair = ProbePerformance.defaultPair(sides) {
            await select(before: pair.before.id, after: pair.after.id).value
        } else { clearSelection() }
        guard generation == loadGeneration else { return }
        status = .ready
    }

    /// La paire formée par la dernière mesure guidée close depuis la lecture
    /// précédente et celle qu'elle désigne (`PairedWith`) : des mesures
    /// enchaînées s'affichent seules, sans les choisir à la main.
    private func freshGuidedPair(known: Set<UUID>) -> (before: ProbeSide, after: ProbeSide)? {
        guard let fresh = measurements.last(where: {
            $0.outcome != .abandoned && $0.pairedWith != nil && !known.contains($0.id)
        }), let target = fresh.pairedWith,
              let before = sides.first(where: { $0.measurement?.id == target }),
              let after = sides.first(where: { $0.measurement?.id == fresh.id })
        else { return nil }
        guard !ProbeComparisonScope.overlaps(before, after) else { return nil }
        return (before, after)
    }

    /// Calcul hors MainActor ; seule la dernière sélection publie son rapport.
    @discardableResult
    func select(before: String?, after: String?) -> Task<Void, Never> {
        selectionGeneration += 1
        let generation = selectionGeneration
        reportTask?.cancel()
        if before != beforeId || after != afterId {
            // An old pair must not appear below the new selectors while
            // its replacement is computing. Same-pair refresh keeps data.
            report = nil
            loadConfigDiffs(nil)
        }
        beforeId = before
        afterId = after
        guard let a = sides.first(where: { $0.id == before }),
              let b = sides.first(where: { $0.id == after }) else {
            report = nil; isComputing = false; loadConfigDiffs(nil)
            return Task {}
        }
        isComputing = true
        let snapshot = sides
        let task = Task { [weak self] in
            let report = await Task.detached(priority: .userInitiated) {
                let repeats = ProbePerformance.repetitionCandidates(snapshot, before: a, after: b)
                return ProbePerformance.report(before: a, after: b, repeats: repeats)
            }.value
            guard let self, !Task.isCancelled, generation == self.selectionGeneration else { return }
            self.report = report
            self.isComputing = false
            self.loadConfigDiffs(report.diff?.changes)
        }
        reportTask = task
        return task
    }

    /// Attendu par les tests : la lecture des diffs de la paire courante.
    func configDiffsLoaded() async { await reportTask?.value; await configDiffsTask?.value }

    /// Écrit le plan (atomique) ; remplace un plan en attente — la vue a
    /// déjà demandé confirmation.
    @discardableResult
    func prepare(_ draft: GuidedPlanDraft, now: Date = Date()) throws -> GuidedPlan {
        let plan = GuidedPlan(id: UUID(), name: draft.name, role: draft.role, location: draft.location,
                              pairedWith: draft.pairedWith, saveName: draft.saveName, createdAt: now)
        try plan.write(to: files.guidedPlanURL)
        self.plan = plan
        return plan
    }

    /// Efface le plan en attente ; la sonde s'arrête à la minute suivante, sans
    /// ligne. Un échec lève et garde le plan affiché : il est toujours sur disque.
    func abandonPlan() throws {
        if let plan { try GuidedPlan.remove(at: files.guidedPlanURL, ifId: plan.id) }
        plan = nil
    }

    private func clearSelection() {
        selectionGeneration += 1
        reportTask?.cancel()
        report = nil
        beforeId = nil
        afterId = nil
        isComputing = false
        loadConfigDiffs(nil)
    }

    // MARK: — Privé

    /// Les contenus de réglages se lisent sur disque : hors du fil principal,
    /// une fois par paire. Une paire changée entre-temps annule la lecture
    /// précédente — ses diffs ne s'affichent jamais sous l'autre paire. Mêmes
    /// changements qu'avant (relecture) : rien à relire.
    private func loadConfigDiffs(_ changes: [ProbeModChange]?) {
        guard changes != configDiffsChanges else { return }
        configDiffsChanges = changes
        configDiffsTask?.cancel()
        configDiffs = [:]
        guard let changes, !changes.isEmpty else { configDiffsTask = nil; return }
        let directory = files.configsDirectory
        configDiffsTask = Task { [weak self] in
            let diffs = await Task.detached(priority: .userInitiated) {
                ProbeInventoryDiffRule.configDiffs(of: changes, configsDirectory: directory)
            }.value
            guard !Task.isCancelled else { return }
            self?.configDiffs = diffs
        }
    }
}
