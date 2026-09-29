import Foundation
import Observation

/// L'état de l'onglet Performances (D4-T4 §3b). Les fichiers de la sonde pèsent
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
    private(set) var measurements: [ProbeMeasurement] = []
    private(set) var unreadableLines = 0
    var pendingMeasurementName: String?

    @ObservationIgnored private let files: ProbeFiles
    @ObservationIgnored private let index: ProbeSessionsIndex
    @ObservationIgnored private let measurementsDirectory: URL?

    init(files: ProbeFiles = ProbeFiles(),
         measurementsDirectory: URL? = ProbeMeasurementsFile.defaultDirectory()) {
        self.files = files
        self.index = ProbeSessionsIndex(files: files)
        self.measurementsDirectory = measurementsDirectory
    }

    var openMeasurement: ProbeMeasurement? { measurements.last { $0.end == nil } }
    var configsDirectory: URL { files.configsDirectory }

    func reload() async {
        status = .loading
        let index = index, files = files, directory = measurementsDirectory
        let loaded = await Task.detached(priority: .userInitiated) { () -> Loaded in
            let sessions = index.sessions(keeping: nil)
            let inventory = files.inventory()
            var measurements: [ProbeMeasurement] = []
            if case .measurements(let saved) = ProbeMeasurementsFile.load(directory: directory) {
                measurements = saved
            }
            // Une mesure jamais terminée se lit close à sa dernière minute ;
            // le fichier la garde ouverte (« Terminer » reste possible).
            let closed = ProbeMeasurementsLogic.closeOpen(measurements, sessions: sessions)
            let sides = ProbePerformance.sides(sessions: sessions, launches: inventory?.launches ?? [],
                                               changes: inventory?.changes ?? [], measurements: closed)
            return Loaded(sides: sides, measurements: measurements,
                          unreadable: sessions.unreadableLines + (inventory?.unreadable ?? 0),
                          hasProbe: !sessions.sessions.isEmpty || inventory != nil)
        }.value
        sides = loaded.sides
        measurements = loaded.measurements
        unreadableLines = loaded.unreadable
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
        else { report = nil; return }
        report = ProbePerformance.report(before: a, after: b)
    }

    /// Jeu lancé seulement, vérifié par l'appelant au clic. Une mesure déjà
    /// ouverte n'en ouvre pas une seconde.
    @discardableResult
    func startMeasurement(name: String, gameRunning: Bool, now: Date = Date()) -> Bool {
        guard gameRunning, openMeasurement == nil else { return false }
        measurements.append(ProbeMeasurement(name: name, start: now, end: nil))
        pendingMeasurementName = nil
        persist(now: now)
        return true
    }

    /// Possible jeu fermé (spec « Mesure propre »).
    func stopMeasurement(now: Date = Date()) {
        guard let index = measurements.lastIndex(where: { $0.end == nil }) else { return }
        measurements[index].end = now
        persist(now: now)
    }

    // MARK: — Privé

    private struct Loaded: Sendable {
        let sides: [ProbeSide]
        let measurements: [ProbeMeasurement]
        let unreadable: Int
        let hasProbe: Bool
    }

    private func persist(now: Date) {
        do {
            try ProbeMeasurementsFile.save(measurements, directory: measurementsDirectory, now: now)
        } catch {
            // L'état en mémoire reste juste ; le prochain enregistrement réessaiera.
        }
    }
}
