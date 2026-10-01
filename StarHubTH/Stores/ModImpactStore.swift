import Foundation
import Observation

/// Ce que la lecture de fond rend ; hors de la classe `@MainActor` pour
/// rester `Sendable` sans isolation.
private enum ModImpactLoad: Sendable {
    case unreadable, noProbe
    case ready(ModImpactHistory)
}

/// D5-C — l'impact par mod : lit les fichiers de la sonde hors du fil
/// principal, intègre les sources closes dans l'historique (une fois
/// chacune), l'écrit, puis publie une entrée par mod installé. Possédé par le
/// ViewModel comme ses voisins (`navigationStore`, `scanStore`) ; la fiche et
/// l'onglet Performances le lisent par `vm`.
@MainActor
@Observable
final class ModImpactStore {
    enum Status: Equatable { case idle, loading, noProbe, unreadableHistory, ready }

    private(set) var status: Status = .idle
    private(set) var entries: [ModImpactEntry] = []
    private(set) var ranking: [ModImpactEntry] = []
    private(set) var probeMsPerFrame: Double?
    private(set) var lastInGame: Date?
    private(set) var lastLaunch: Date?
    private(set) var lastSave: Date?

    @ObservationIgnored private let files: ProbeFiles
    @ObservationIgnored private let index: ProbeSessionsIndex
    @ObservationIgnored private let historyURL: URL?

    init(files: ProbeFiles = ProbeFiles(),
         historyURL: URL? = AppSupport.directory?.appendingPathComponent(ModImpactHistory.fileName)) {
        self.files = files
        self.index = ProbeSessionsIndex(files: files)
        self.historyURL = historyURL
    }

    func entry(for mod: ModItem) -> ModImpactEntry? { entries.first { $0.id == mod.folderName } }

    /// `gameRunning` : la dernière session grossit encore, elle attend.
    func reload(mods: [ModItem], gameRunning: Bool, gameDir: String?) async {
        if status == .idle { status = .loading }
        let index = index, files = files, historyURL = historyURL
        let coldBefore = ProbeColdDisk.cutoff(gameDir: gameDir)
        let loaded = await Task.detached(priority: .utility) { () -> ModImpactLoad in
            var history = ModImpactHistory()
            if let historyURL {
                switch ModImpactHistory.load(from: historyURL) {
                case .unreadable: return .unreadable
                case .loaded(let saved): history = saved
                case .absent: break
                }
            }
            let sessions = index.sessions(keeping: nil)
            let inventory = files.inventory()
            let loads = files.loads().records
            guard !sessions.sessions.isEmpty || !loads.isEmpty else {
                return history.integrated.isEmpty ? .noProbe : .ready(history)
            }
            let sides = ProbePerformance.sides(sessions: sessions, launches: inventory?.launches ?? [],
                                               changes: inventory?.changes ?? [], measurements: [],
                                               excludingSessions: ProbeLoadRecords.benchmarkSessions(loads))
            let openSession = gameRunning ? sessions.sessions.map(\.id).max() : nil
            var changed = false
            if let coldBefore, !history.boots.contains(coldBefore) { history.noteBoot(coldBefore); changed = true }
            for side in sides where side.session != openSession {
                if let source = ModImpactSources.inGame(side) { changed = history.integrate(source) || changed }
            }
            for record in loads {
                let cold = ModImpactSources.isCold(record, among: loads, boots: history.boots)
                if let source = ModImpactSources.load(record, launches: inventory?.launches ?? [], isCold: cold) {
                    changed = history.integrate(source) || changed
                }
            }
            if changed, let historyURL {
                // Échec d'écriture : l'historique en mémoire reste affiché, la
                // prochaine lecture réessaie (les sources n'y sont pas encore).
                do { try history.save(to: historyURL) } catch {}
            }
            return .ready(history)
        }.value
        let history: ModImpactHistory
        switch loaded {
        case .unreadable: status = .unreadableHistory; entries = []; ranking = []; return
        case .noProbe: status = .noProbe; entries = []; ranking = []; return
        case .ready(let h): history = h
        }
        status = .ready
        entries = ModImpact.entries(history: history, mods: mods)
        ranking = ModImpact.ranking(entries)
        probeMsPerFrame = history.probeMsPerFrame
        let all = history.samples.values.flatMap { $0 }
        lastInGame = all.filter { $0.kind == .inGame }.map(\.date).max()
        lastLaunch = all.filter { $0.kind == .launch }.map(\.date).max()
        lastSave = all.filter { $0.kind == .save }.map(\.date).max()
    }
}
