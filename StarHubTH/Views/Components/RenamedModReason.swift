import Foundation

/// La raison « identifiant changé par l'auteur » d'une anomalie, avec le
/// dossier de l'autre copie : c'est lui qu'il faut aller voir (ou effacer).
@MainActor
func renamedReason(_ renamed: ModAnomaly.Renamed, _ localization: LocalizationStore) -> String {
    switch renamed {
    case .oldCopy(let folder, let version):
        String(format: localization.L(L10n.Mods.anomalyRenamedOld), version, folder)
    case .newCopy(let folder, let version):
        String(format: localization.L(L10n.Mods.anomalyRenamedNew), version, folder)
    }
}
