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
    @ObservationIgnored private let index: ProbeSessionsIndex

    init(files: ProbeFiles = ProbeFiles()) {
        self.files = files
        self.index = ProbeSessionsIndex(files: files)
    }

    var configsDirectory: URL { files.configsDirectory }
    var protocolState: GuidedProtocolState { GuidedProtocol.state(plan: plan, measurements: measurements) }

    func reload(gameDir: String? = nil) async {
        // Première lecture seulement : une relecture garde l'écran affiché
        // (retour dans l'app, changement de segment) au lieu de le vider.
        if status == .idle { status = .loading }
        let index = index, files = files
        let loaded = await Task.detached(priority: .userInitiated) { () -> Loaded in
            let sessions = index.sessions(keeping: nil)
            let inventory = files.inventory()
            let guided = files.guidedMeasurements()
            let loads = files.loads()
            var plan = files.guidedPlan()
            // Mesure close : le plan est à effacer — sur le fil principal,
            // là où passent toutes les écritures du plan (pas de course avec
            // une préparation).
            var finished: UUID?
            if let current = plan, guided.measurements.contains(where: { $0.id == current.id && $0.isFinished }) {
                finished = current.id
                plan = nil
            }
            let sides = ProbePerformance.sides(sessions: sessions, launches: inventory?.launches ?? [],
                                               changes: inventory?.changes ?? [],
                                               measurements: guided.measurements)
            return Loaded(sides: sides, measurements: guided.measurements, plan: plan, finishedPlan: finished,
                          unreadable: sessions.unreadableLines + (inventory?.unreadable ?? 0) + guided.unreadable
                                      + loads.unreadable,
                          hasProbe: !sessions.sessions.isEmpty || inventory != nil || !loads.records.isEmpty,
                          loads: loads.records,
                          launches: inventory?.launches ?? [], changes: inventory?.changes ?? [],
                          coldBefore: ProbeColdDisk.cutoff(gameDir: gameDir))
        }.value
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
        coldRecordIds = Set(loads.filter {
            ProbeLoadComparison.isCold($0, among: loads, coldBefore: loaded.coldBefore) }.map(\.id))
        launchComparison = ProbeLoadComparison.compare(loads, kind: .launch, launches: loaded.launches,
                                                       changes: loaded.changes, coldBefore: loaded.coldBefore)
        saveComparison = ProbeLoadComparison.compare(loads, kind: .save, launches: loaded.launches,
                                                     changes: loaded.changes, coldBefore: loaded.coldBefore)
        probeWritesLoads = ProbeLoadRecords.writesLoads(probeVersion: loaded.launches.last?.probe)
        guard loaded.hasProbe else { status = .noProbe; report = nil; return }
        guard sides.count >= 2 else { status = .needTwo; report = nil; return }
        // Garder la paire choisie si elle existe encore, sinon la paire par défaut.
        if let beforeId, let afterId, sides.contains(where: { $0.id == beforeId }),
           sides.contains(where: { $0.id == afterId }) {
            select(before: beforeId, after: afterId)
        } else if let pair = ProbePerformance.defaultPair(sides) {
            select(before: pair.before.id, after: pair.after.id)
        }
        status = .ready
    }

    /// Le rapport d'une paire se calcule sur des minutes déjà en mémoire
    /// (quelques centaines) : sur place.
    func select(before: String?, after: String?) {
        beforeId = before
        afterId = after
        guard let a = sides.first(where: { $0.id == before }),
              let b = sides.first(where: { $0.id == after }), a.id != b.id
        else { report = nil; loadConfigDiffs(nil); return }
        report = ProbePerformance.report(before: a, after: b)
        loadConfigDiffs(report?.diff?.changes)
    }

    /// Attendu par les tests : la lecture des diffs de la paire courante.
    func configDiffsLoaded() async { await configDiffsTask?.value }

    /// Écrit le plan (atomique) ; remplace un plan en attente — la vue a
    /// déjà demandé confirmation.
    @discardableResult
    func prepare(_ draft: GuidedPlanDraft, now: Date = Date()) throws -> GuidedPlan {
        let plan = GuidedPlan(id: UUID(), name: draft.name, role: draft.role, location: draft.location,
                              pairedWith: draft.pairedWith, createdAt: now)
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

    // MARK: — Privé

    private struct Loaded: Sendable {
        let sides: [ProbeSide]
        let measurements: [ProbeMeasurement]
        let plan: GuidedPlan?
        let finishedPlan: UUID?
        let unreadable: Int
        let hasProbe: Bool
        let loads: [ProbeLoadRecord]
        let launches: [ProbeInventoryLaunch]
        let changes: [ProbeInventoryChange]
        let coldBefore: Date?
    }

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
