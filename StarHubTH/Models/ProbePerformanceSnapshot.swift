import Foundation

/// Résultat immuable de la lecture, injectable sans changer le pipeline d'analyse.
struct ProbePerformanceSnapshot: Sendable {
    var sides: [ProbeSide]
    var measurements: [ProbeMeasurement] = []
    var plan: GuidedPlan? = nil
    var finishedPlan: UUID? = nil
    var unreadable: Int = 0
    var hasProbe: Bool = true
    var loads: [ProbeLoadRecord] = []
    var launches: [ProbeInventoryLaunch] = []
    var changes: [ProbeInventoryChange] = []
    var coldBefore: Date? = nil

    var guidedMinuteCount: Int {
        guard let plan else { return 0 }
        let dates = sides.filter { $0.measurement == nil }.flatMap(\.comparable.kept).compactMap { item -> Date? in
            guard item.minute.location == plan.location, let date = ProbeDate.parse(item.minute.at), date >= plan.createdAt else { return nil }
            return date
        }
        return Set(dates).count
    }

    static func read(files: ProbeFiles, index: ProbeSessionsIndex, gameDir: String?) -> Self {
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
                                           measurements: guided.measurements,
                                           excludingSessions: ProbeLoadRecords.benchmarkSessions(loads.records))
        return ProbePerformanceSnapshot(sides: sides, measurements: guided.measurements, plan: plan, finishedPlan: finished,
                      unreadable: sessions.unreadableLines + (inventory?.unreadable ?? 0) + guided.unreadable
                                  + loads.unreadable,
                      hasProbe: !sessions.sessions.isEmpty || inventory != nil || !loads.records.isEmpty,
                      loads: loads.records,
                      launches: inventory?.launches ?? [], changes: inventory?.changes ?? [],
                      coldBefore: ProbeColdDisk.cutoff(gameDir: gameDir))
    }
}
