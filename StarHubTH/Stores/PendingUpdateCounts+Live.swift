import Foundation

/// P5-6b (audit UX 2026-10-16, décision de l'auteur) — les mises à jour dues,
/// mods actifs et mods en pause comptés à part. Le badge de la barre latérale
/// et la tuile de l'Accueil ne comptent que les actifs : au parc de l'auteur,
/// cinq mises à jour sur six visaient un mod en pause. L'en-tête de la page
/// dit les deux.
///
/// Même source et même filtre que la page (`UpdateCount.pendingEntries`, X113),
/// même règle de pause que ses groupes (`NexusUpdateGroups` : un mod
/// introuvable compte en pause).
struct PendingUpdateCounts: Equatable {
    let active: Int
    let paused: Int
    var total: Int { active + paused }
}

extension StarHubTHViewModel {
    var pendingUpdateCounts: PendingUpdateCounts {
        let smapi = UpdateCount.pendingEntries(outOfDate: outOfDateMods) {
            self.resolveModFolder(forLoggedName: $0)?.version
        }
        let smapiGroups = NexusUpdateGroups(smapi) { self.resolveModFolder(forLoggedName: $0.name)?.isEnabled }
        let nexusGroups = NexusUpdateGroups(nexusUpdates) { self.modForNexusUpdate($0)?.isEnabled }
        return PendingUpdateCounts(active: smapiGroups.active.count + nexusGroups.active.count,
                                   paused: smapiGroups.paused.count + nexusGroups.paused.count)
    }
}
