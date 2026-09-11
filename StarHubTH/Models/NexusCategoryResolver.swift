import Foundation

/// La catégorie affichée pour un mod — le QUOI de `category(for:)`/
/// `computeCategory`/`dominantCategory` (le COMMENT — la mémoïsation et les
/// invalidations — reste au ViewModel).
///
/// Extraite du ViewModel le 2026-09-11 (REFACTORING §5, domaine Nexus,
/// tranche 4). La précédence (première qui parle) :
///
/// 1. L'override **utilisateur**, par nom de dossier — il permet de
///    catégoriser un mod que l'API n'a jamais vu porter de `category_id`,
///    en-tête de pack compris ;
/// 2. La catégorie **API**, par identifiant Nexus **effectif** (override
///    d'identifiant ou manifeste) — c'est ainsi qu'une catégorie posée par
///    l'éditeur par-mod atteint un mod sans identifiant de manifeste ;
/// 3. Pour un en-tête de pack **sans id propre** : la catégorie dominante de
///    ses enfants — l'en-tête est ce qu'on active, pas ses enfants pris un à
///    un ;
/// 4. `nil` — inconnu.
///
/// Tout arrive en valeurs ; la récursion du dominant refait le calcul par
/// enfant, là où le ViewModel mémoïsait les lectures — même verdict, deux
/// lectures de dictionnaire de plus par enfant, invisibles hors des packs.
enum NexusCategoryResolver {

    static func resolveCategory(for mod: ModItem,
                                customCategories: [String: Int],
                                categoriesByNexusId: [String: Int],
                                customModIds: [String: String]) -> NexusCategory? {
        if let cid = customCategories[mod.folderName],
           let cat = NexusCategory.from(id: cid) {
            return cat
        }
        let effectiveId = NexusModIdentity.effectiveId(for: mod, customIds: customModIds)
        if !effectiveId.isEmpty,
           let cid = categoriesByNexusId[effectiveId],
           let cat = NexusCategory.from(id: cid) {
            return cat
        }
        // En-tête de pack sans id propre : le plus commun de ses enfants.
        if mod.isGroup, let children = mod.children {
            return dominantCategory(among: children,
                                    customCategories: customCategories,
                                    categoriesByNexusId: categoriesByNexusId,
                                    customModIds: customModIds)
        }
        return nil
    }

    /// La catégorie la plus fréquente de l'ensemble. Ex æquo de fréquence :
    /// l'identifiant de catégorie **le plus bas** gagne — un ordre stable, où
    /// un tri non garanti ne décide de rien. `nil` quand aucun enfant n'en a
    /// une de connue.
    static func dominantCategory(among children: [ModItem],
                                 customCategories: [String: Int],
                                 categoriesByNexusId: [String: Int],
                                 customModIds: [String: String]) -> NexusCategory? {
        var counts: [Int: Int] = [:]
        for c in children {
            if let cat = resolveCategory(for: c,
                                         customCategories: customCategories,
                                         categoriesByNexusId: categoriesByNexusId,
                                         customModIds: customModIds) {
                counts[cat.id, default: 0] += 1
            }
        }
        guard let dominantId = counts.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        })?.key else { return nil }
        return NexusCategory.from(id: dominantId)
    }
}
