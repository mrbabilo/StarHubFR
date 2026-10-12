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
}
