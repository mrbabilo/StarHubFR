import Foundation

/// La résolution d'identité et de contenu Nexus d'un mod (REFACTORING §6,
/// domaine Détail de mod, tranche 2) : identifiant effectif, identifiant
/// résolu pour un pack, lien public, résumé + image.
///
/// Le calcul est pur — « ce qui n'est pas à moi arrive en paramètre » (§3) :
/// les Overrides utilisateur (`customIds`, publiés par le VM) et les extras
/// déjà téléchargés (`extras`) arrivent en valeurs. Les conventions de repli
/// — l'en-tête d'un pack hérite du premier enfant qui a quelque chose — sont
/// les mêmes pour l'id, le lien et l'extra, et testées.
enum NexusModIdentity {

    /// L'identifiant effectif : l'override utilisateur gagne, sinon celui
    /// du manifeste.
    static func effectiveId(for mod: ModItem, customIds: [String: String]) -> String {
        if let custom = customIds[mod.folderName], !custom.isEmpty {
            return custom
        }
        return mod.nexusModId
    }

    /// Comme `effectiveId`, mais pour un en-tête de pack sans id propre :
    /// repli sur le premier enfant qui en a un — la fiche télécharge contre
    /// cet id pour que le pack montre le même contenu que son lien. Vide
    /// quand ni le mod ni un enfant n'a d'identifiant.
    static func resolvedId(for mod: ModItem, customIds: [String: String]) -> String {
        let id = effectiveId(for: mod, customIds: customIds)
        if !id.isEmpty { return id }
        if mod.isGroup, let children = mod.children {
            for c in children {
                let childId = resolvedId(for: c, customIds: customIds)
                if !childId.isEmpty { return childId }
            }
        }
        return ""
    }

    /// Le lien Nexus : construit depuis l'identifiant effectif, sinon le
    /// `nexusUrl` du manifeste (la source d'origine — ils coïncident
    /// normalement), sinon le premier enfant qui a un lien.
    static func link(for mod: ModItem, customIds: [String: String]) -> String {
        let id = effectiveId(for: mod, customIds: customIds)
        if !id.isEmpty {
            return "https://www.nexusmods.com/stardewvalley/mods/\(id)"
        }
        if !mod.nexusUrl.isEmpty {
            return mod.nexusUrl
        }
        if mod.isGroup, let children = mod.children {
            for c in children {
                let link = link(for: c, customIds: customIds)
                if !link.isEmpty { return link }
            }
        }
        return ""
    }

    /// Le résumé + image téléchargés pour ce mod, ou `nil` quand rien
    /// n'a encore été récupéré. Un en-tête de pack sans données propres
    /// hérite du premier enfant qui en a — même convention que
    /// `resolvedId`/`link`. Un extra à la fois sans résumé et sans image
    /// ne compte pas comme des données.
    static func extra(for mod: ModItem, customIds: [String: String],
                      extras: [String: NexusUpdateChecker.NexusModExtra]) -> NexusUpdateChecker.NexusModExtra? {
        let id = effectiveId(for: mod, customIds: customIds)
        if !id.isEmpty, let extra = extras[id],
           !extra.summary.isEmpty || !extra.pictureUrl.isEmpty {
            return extra
        }
        if mod.isGroup, let children = mod.children {
            for c in children {
                if let extra = extra(for: c, customIds: customIds, extras: extras) { return extra }
            }
        }
        return nil
    }
}
