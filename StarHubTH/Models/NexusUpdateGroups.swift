import Foundation

/// P5-6a (audit UX 2026-10-16) — les mises à jour Nexus de la page, mods
/// actifs d'abord, mods en pause à part. Au parc de l'auteur, 5 mises à jour
/// sur 6 visaient un mod en pause (78 % du parc l'est) : triées ensemble, la
/// seule qui compte se cherchait à l'œil.
///
/// L'ordre d'arrivée est gardé dans chaque groupe. Un mod introuvable sur le
/// disque compte en pause : rien de lui n'est chargé, comme la pastille de la
/// rangée le dit déjà.
struct NexusUpdateGroups<Update> {
    let active: [Update]
    let paused: [Update]

    init(_ updates: [Update], isActive: (Update) -> Bool?) {
        var active: [Update] = []
        var paused: [Update] = []
        for update in updates {
            if isActive(update) == true { active.append(update) } else { paused.append(update) }
        }
        self.active = active
        self.paused = paused
    }
}
