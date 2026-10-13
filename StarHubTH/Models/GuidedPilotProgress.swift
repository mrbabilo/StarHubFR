import Foundation

/// Les étapes visibles d'un côté piloté, du clic à la mesure (retour du
/// 2026-10-13 : le jeu met minutes à charger ~900 mods, l'utilisateur croyait
/// que rien ne se passait). Signaux : le processus du jeu, puis les lignes de
/// `loads.jsonl` que la sonde écrit à l'écran titre (`launch`) et au monde
/// prêt (`save`) — seules celles d'après le lancement du côté comptent.
public enum GuidedPilotProgress {
    public enum Stage: Int, CaseIterable, Comparable, Sendable {
        case launching, loadingMods, loadingSave, measuring

        public static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public static func stage(launchedAt: Date, gameRunning: Bool, loads: [ProbeLoadRecord]) -> Stage {
        let since = loads.filter { ($0.at ?? .distantPast) >= launchedAt }
        if since.contains(where: { $0.kind == .save }) { return .measuring }
        if since.contains(where: { $0.kind == .launch }) { return .loadingSave }
        return gameRunning ? .loadingMods : .launching
    }
}
