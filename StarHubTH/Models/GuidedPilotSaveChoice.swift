import Foundation

/// M9 — la sauvegarde d'une paire pilotée lancée depuis l'analyse : celle que
/// la sonde a chargée dans la session du côté analysé (`loads.jsonl`), pour
/// mesurer la ferme du rapport ; à défaut, la première disponible (le défaut
/// de la feuille guidée).
public enum GuidedPilotSaveChoice {
    public static func save(session: String?, loads: [ProbeLoadRecord], available: [String]) -> String? {
        if let session,
           let loaded = loads.last(where: { $0.kind == .save && $0.session == session })?.saveName,
           available.contains(loaded) {
            return loaded
        }
        return available.first
    }

    /// X154 — la mesure « après » rejoue la ferme de sa mesure « avant » : la
    /// sauvegarde n'est pas dans la ligne de mesure, seule sa session la relie
    /// à `loads.jsonl`. Sans ce lien, deux fermes se comparaient sans alerte.
    public static func save(after before: ProbeMeasurement, sides: [ProbeSide], loads: [ProbeLoadRecord],
                            available: [String]) -> String? {
        save(session: sides.first { $0.measurement?.id == before.id }?.session, loads: loads, available: available)
    }
}
