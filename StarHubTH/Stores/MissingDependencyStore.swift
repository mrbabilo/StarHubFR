import Foundation
import Observation

/// A1-T1 — l'état du domaine « dépendances manquantes » : l'annuaire
/// `UniqueID` → page Nexus construit depuis le dump Pathoschild, et ce que
/// chaque téléchargement lancé devra prouver à la feuille d'installation.
/// F1-T2 : l'état neuf naît ici, pas dans le ViewModel.
@Observable
final class MissingDependencyStore {

    /// Reconstruit avec le dump (au scan, au rafraîchissement) — jamais au
    /// rendu d'une ligne : le décodage du dump coûte le fichier entier.
    private(set) var directory = DependencyNexusDirectory.empty

    /// Par téléchargement lancé : `modId` → identifiants attendus. La file
    /// de téléchargement peut en porter plusieurs à la fois.
    private(set) var expectedIds: [Int: [String]] = [:]

    /// Les identifiants attendus de l'archive qui vient d'arriver — posé en
    /// même temps que `pendingNexusSource`, lu par la feuille d'installation,
    /// effacé aux mêmes endroits qu'elle.
    private(set) var pendingExpectedIds: [String]?

    func replaceDirectory(_ directory: DependencyNexusDirectory) {
        self.directory = directory
    }

    /// Le plan que le bouton de la liste et la feuille affichent : les
    /// dépendances requises des mods actifs qu'aucun mod installé ne fournit.
    func plan(mods: [ModItem], installedIds: Set<String>) -> [MissingDependency] {
        MissingDependencies.plan(mods: mods, installedIds: installedIds,
                                 directory: directory)
    }

    func recordExpectation(nexusId: Int, uniqueIds: [String]) {
        expectedIds[nexusId] = uniqueIds
    }

    /// Le téléchargement d'un `modId` est arrivé : ce que son archive devra
    /// prouver (et que la feuille lira jusqu'à son effacement).
    @discardableResult
    func takeExpectation(for modId: Int) -> [String]? {
        pendingExpectedIds = expectedIds.removeValue(forKey: modId)
        return pendingExpectedIds
    }

    func clearPendingExpectation() {
        pendingExpectedIds = nil
    }
}
