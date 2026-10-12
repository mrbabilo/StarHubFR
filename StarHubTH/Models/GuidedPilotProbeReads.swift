import Foundation

/// P1 T7 — ce que le runner piloté lit de la sonde, sans I/O : la mesure du
/// plan est-elle close, et combien de minutes gardées au lieu cible depuis le
/// plan. Même compte que `ProbePerformanceSnapshot.guidedMinuteCount`, sur la
/// seule session courante : un signal de vie pour le watchdog, pas le
/// décompte de la mesure (les gardes 6 à 9 vivent dans la sonde).
public enum GuidedPilotProbeReads {
    /// Une mesure abandonnée (retour au titre, jeu quitté) ne se clora plus :
    /// elle ne compte pas comme close.
    public static func measurementState(planId: UUID, in measurements: [ProbeMeasurement]) -> PilotMeasurementState {
        measurements.contains { $0.id == planId && $0.isFinished } ? .finished : .none
    }

    public static func keptMinutes(plan: GuidedPlan?, planId: UUID, session: ProbeSession?) -> Int {
        guard let plan, plan.id == planId, let session else { return 0 }
        let kept = ProbeComparableMinutes.filter(session.minutes, costs: session.costs).kept
        return Set(kept.compactMap { item -> Date? in
            guard item.minute.location == plan.location, let at = ProbeDate.parse(item.minute.at),
                  at >= plan.createdAt else { return nil }
            return at
        }).count
    }
}
