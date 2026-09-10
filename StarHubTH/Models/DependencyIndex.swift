import Foundation

/// Les index dérivés du parc pour le domaine Dépendances (REFACTORING §6) :
/// qui est installé, dans quel état, et où sont les doublons d'UniqueID.
/// Construit en **une seule passe** sur la liste publiée par le scan.
///
/// Le calcul est pur : « ce qui n'est pas à moi arrive en paramètre » (§3) —
/// ici la liste des mods, telle que servie par `vm.mods`. Les plis de
/// casse (`lowercased`) reproduisent la résolution d'UniqueID de SMAPI :
/// un mod déclarant ` mod.Id` et une dépendance écrivant `Mod.id`
/// doivent se rencontrer.
struct DependencyIndex {

    /// UniqueIDs installés, **pliés en minuscules**.
    let installedUniqueIds: Set<String>
    /// UniqueID plié → état activé.
    let installedModStates: [String: Bool]
    /// UniqueID plié → mod (composants de packs compris).
    let installedModsByUniqueId: [String: ModItem]
    /// Les doublons X/.X par UniqueID, sortis du même parcours.
    let duplicateIndex: ModDuplicateIndex

    static let empty = DependencyIndex(
        installedUniqueIds: [],
        installedModStates: [:],
        installedModsByUniqueId: [:],
        duplicateIndex: .empty)

    static func build(from mods: [ModItem]) -> DependencyIndex {
        var ids = Set<String>()
        var states: [String: Bool] = [:]
        var byId: [String: ModItem] = [:]
        var entries: [(uniqueId: String, folderName: String, isEnabled: Bool)] = []
        for m in mods {
            if m.isGroup, let children = m.children {
                for c in children {
                    let k = c.uniqueId.lowercased()
                    ids.insert(k)
                    states[k] = c.isEnabled
                    byId[k] = c
                    // `folderName` d'un composant **porte déjà** le nom du
                    // pack (`scanEntryForMods` construit
                    // `{pack}/{sous-chemin}`) : c'est lui qui distingue
                    // « Swim » de « Swim Mod-23169…/Swim ». Le préfixer une
                    // seconde fois donnerait un chemin qui n'existe pas.
                    entries.append((c.uniqueId, c.folderName, c.isEnabled))
                }
            } else {
                let k = m.uniqueId.lowercased()
                ids.insert(k)
                states[k] = m.isEnabled
                byId[k] = m
                entries.append((m.uniqueId, m.folderName, m.isEnabled))
            }
        }
        return DependencyIndex(
            installedUniqueIds: ids,
            installedModStates: states,
            installedModsByUniqueId: byId,
            // Les doublons sortent du **même parcours** : `states` et `byId` en
            // écrasent silencieusement un sur deux (le dernier gagne), si bien que
            // le seul endroit où l'information existe encore est ici, avant
            // l'aplatissement.
            duplicateIndex: ModDuplicateIndex.build(from: entries))
    }

    /// Required dependency UniqueIDs absents du parc.
    func missing(for mod: ModItem) -> [String] {
        ModDependencyStatus.missing(for: mod, installedIds: installedUniqueIds)
    }

    /// Required dependency UniqueIDs installés mais désactivés.
    func disabled(for mod: ModItem) -> [String] {
        ModDependencyStatus.disabled(for: mod, states: installedModStates)
    }

    /// Pour un pack (groupe, dont les propres `dependencies` sont vides) :
    /// l'union **dédupliquée** des dépendances de ses enfants, pliage de
    /// casse compris, une dépendance optionnelle devenant requise dès qu'un
    /// enfant l'exige. C'est cette union qui donne à un pack un arbre de
    /// dépendances lisible.
    static func mergedPackRoots(of mod: ModItem) -> [ModDependency] {
        guard mod.isGroup, let children = mod.children else { return mod.dependencies }
        var merged: [ModDependency] = []
        for child in children {
            for dep in child.dependencies {
                let key = dep.uniqueId.lowercased()
                if let idx = merged.firstIndex(where: { $0.uniqueId.lowercased() == key }) {
                    if dep.isRequired && !merged[idx].isRequired {
                        merged[idx] = ModDependency(uniqueId: merged[idx].uniqueId, isRequired: true)
                    }
                } else {
                    merged.append(dep)
                }
            }
        }
        return merged
    }

    /// Le mod installé correspondant à un UniqueID, pour la résolution de
    /// l'arbre — rendu en tuple tel que `DependencyTreeBuilder` le consomme
    /// (labels compris : `deps`, pas `dependencies`).
    func resolve(_ uid: String) -> (mod: ModItem, isEnabled: Bool, deps: [ModDependency])? {
        guard let m = installedModsByUniqueId[uid.lowercased()] else { return nil }
        return (m, m.isEnabled, m.dependencies)
    }
}
