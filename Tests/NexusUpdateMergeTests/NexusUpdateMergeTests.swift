import Testing
import Foundation
@testable import StarHubTHCore

/// Une vérification Nexus n'atteint pas toujours tous les mods : un 429 coupe
/// le run, un 404 fait échouer un candidat isolé. Ce que le run n'a pas pu
/// regarder ne doit pas disparaître de la liste des mises à jour — c'est le
/// défaut que ces tests verrouillent. Le run rapporte donc trois choses
/// distinctes : ce qu'il a trouvé, ce qu'il a réellement pu interroger, et la
/// liste complète des mods installés qui étaient candidats.
struct NexusUpdateMergeTests {
    private func update(_ id: String, name: String = "n",
                        installed: String = "1.0.0", latest: String = "2.0.0")
    -> NexusUpdateChecker.ModUpdate {
        .init(name: name, installedVersion: installed, latestVersion: latest,
              nexusModId: id, url: "https://x/\(id)", uploadedTime: nil)
    }

    @Test func aModTheRunNeverReachedKeepsItsCachedUpdate() {
        let merged = NexusUpdateMerge.merge(
            cached: [update("42", name: "SVE")],
            found: [],
            completedModIds: [],
            installedVersionByModId: ["42": "1.0.0"]
        )
        #expect(merged.map(\.nexusModId) == ["42"])
    }

    @Test func aModConfirmedUpToDateLosesItsCachedUpdate() {
        let merged = NexusUpdateMerge.merge(
            cached: [update("42", name: "SVE")],
            found: [],
            completedModIds: ["42"],
            installedVersionByModId: ["42": "2.0.0"]
        )
        #expect(merged.isEmpty)
    }

    @Test func aFreshlyFoundUpdateOverwritesTheCachedRow() {
        let merged = NexusUpdateMerge.merge(
            cached: [update("42", name: "SVE", latest: "2.0.0")],
            found: [update("42", name: "SVE", latest: "3.0.0")],
            completedModIds: ["42"],
            installedVersionByModId: ["42": "1.0.0"]
        )
        #expect(merged.count == 1)
        #expect(merged.first?.latestVersion == "3.0.0")
    }

    @Test func aCachedUpdateForAModNoLongerInstalledIsPruned() {
        let merged = NexusUpdateMerge.merge(
            cached: [update("42", name: "SVE"), update("7", name: "Automate")],
            found: [],
            completedModIds: [],
            installedVersionByModId: ["42": "1.0.0"]
        )
        #expect(merged.map(\.nexusModId) == ["42"])
    }

    /// Le mod a été mis à jour à la main entre deux vérifications, et le run
    /// suivant ne l'a pas atteint : sa ligne survit, mais elle ne doit pas
    /// continuer d'annoncer la version installée d'avant.
    @Test func aSurvivingRowCarriesTheCurrentInstalledVersion() {
        let merged = NexusUpdateMerge.merge(
            cached: [update("42", name: "SVE", installed: "1.0.0", latest: "3.0.0")],
            found: [],
            completedModIds: [],
            installedVersionByModId: ["42": "2.0.0"]
        )
        #expect(merged.first?.installedVersion == "2.0.0")
    }

    /// La fusion passe par un dictionnaire : sans tri explicite, l'ordre des
    /// lignes changerait à chaque vérification sous les yeux de l'utilisateur.
    @Test func theMergedListIsOrderedByName() {
        let merged = NexusUpdateMerge.merge(
            cached: [update("42", name: "Tractor"), update("7", name: "Automate")],
            found: [update("9", name: "Chests")],
            completedModIds: ["9"],
            installedVersionByModId: ["42": "1.0.0", "7": "1.0.0", "9": "1.0.0"]
        )
        #expect(merged.map(\.name) == ["Automate", "Chests", "Tractor"])
    }

    /// Une mise à jour détectée doit tenir jusqu'à ce qu'elle soit faite. Sans
    /// candidat, on ne sait rien : la liste des mods peut simplement ne pas
    /// être encore chargée. Purger là-dessus effacerait des mises à jour que
    /// personne n'a installées.
    @Test func anEmptyCandidateSetPrunesNothing() {
        let merged = NexusUpdateMerge.merge(
            cached: [update("42", name: "SVE"), update("7", name: "Automate")],
            found: [],
            completedModIds: [],
            installedVersionByModId: [:]
        )
        #expect(merged.map(\.nexusModId) == ["7", "42"])
    }

    /// Le cas complet du bug : un run partiel où un seul candidat sur trois a
    /// répondu ne doit pas ramener la liste à cette seule réponse.
    @Test func aPartialRunDoesNotTruncateTheListToWhatItReached() {
        let merged = NexusUpdateMerge.merge(
            cached: [update("1", name: "A"), update("2", name: "B"), update("3", name: "C")],
            found: [update("1", name: "A", latest: "9.0.0")],
            completedModIds: ["1"],
            installedVersionByModId: ["1": "1.0.0", "2": "1.0.0", "3": "1.0.0"]
        )
        #expect(merged.map(\.nexusModId) == ["1", "2", "3"])
    }
}
