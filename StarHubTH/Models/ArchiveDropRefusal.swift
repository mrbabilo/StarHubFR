import Foundation

/// P5-5a (audit UX 2026-10-16) — ce qui interdit de déposer une archive sur
/// la fenêtre, dans l'ordre où le message le nomme. Le dépôt ouvre la
/// feuille d'installation : sans ces gardes, il en ouvrirait une seconde
/// par-dessus la première (l'une se perd en silence), ou prêterait l'id
/// Nexus d'un téléchargement en attente à l'archive de l'utilisateur.
enum ArchiveDropRefusal: Equatable {
    /// Une feuille d'installation est ouverte : c'est elle qui reçoit le dépôt.
    case installOpen
    /// Un téléchargement Nexus court, ou attend sa feuille.
    case downloadBusy
    /// Un profil est en cours d'application.
    case profileApplying
    /// La recherche du mod responsable, le benchmark ou la mesure pilotée
    /// tient le parc. Une opération seulement interrompue n'interdit rien :
    /// le nouveau mod arrive en pause et ne touche pas à son instantané.
    case operationRunning(ModSetOperations.Operation)

    static func first(installOpen: Bool, downloadBusy: Bool, profileApplying: Bool,
                      operations: ModSetOperations) -> ArchiveDropRefusal? {
        if installOpen { return .installOpen }
        if downloadBusy { return .downloadBusy }
        if profileApplying { return .profileApplying }
        if let running = ModSetOperations.Operation.allCases.first(where: operations.running.contains) {
            return .operationRunning(running)
        }
        return nil
    }
}
