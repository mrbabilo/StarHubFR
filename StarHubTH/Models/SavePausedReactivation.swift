import Foundation

/// P5-8 (audit UX 2026-10-16) — « Réactiver ces mods » depuis une partie :
/// ce que le geste active, à partir des mods en pause qui ont laissé du
/// contenu dans la sauvegarde (`SavePausedFootprints`). Avant, il fallait
/// ouvrir chaque fiche, basculer, revenir.
///
/// Tout se raisonne en dossiers de tête, comme une bascule : un composant
/// réveille son pack entier (un pack ne bouge qu'en bloc), ce que le libellé
/// dit. Avec le chaînage des dépendances, le plan de chaque mod
/// (`TogglePlan`) ajoute ses dépendances requises en pause : réactiver un mod
/// sans elles rendrait la partie aussi bancale qu'avant.
struct SavePausedReactivation: Equatable {
    /// Les dossiers de tête à activer, dans l'ordre de la section puis des
    /// dépendances, sans doublon.
    let mods: [ModItem]
    /// Les packs parmi eux : leurs autres composants se réveillent aussi.
    let wholePacks: Int

    init(footprints: [PausedModFootprint], mods parc: [ModItem], chain: Bool) {
        let topOf = parc.topFolders
        let index = TogglePlan.Index(parc)
        let byFolder = index.byFolder
        var seen: Set<String> = []
        var ordered: [ModItem] = []
        for footprint in footprints {
            guard let top = topOf[footprint.folderName], let mod = byFolder[top], !mod.isEnabled else { continue }
            let plan = TogglePlan.make(mod: mod, index: index, chain: chain)
            // L'amorce d'abord, puis ses dépendances dans un ordre stable.
            for folder in [plan.seedFolder] + plan.folders.subtracting([plan.seedFolder]).sorted() {
                guard let target = byFolder[folder], !target.isEnabled, seen.insert(folder).inserted else { continue }
                ordered.append(target)
            }
        }
        mods = ordered
        wholePacks = ordered.filter(\.isGroup).count
    }
}
