import Foundation

/// Les archives Nexus conservées (X103-C), regroupées par mod pour l'écran
/// Entretien : un mod mis à jour plusieurs fois garde une archive par
/// version, et la liste à plat les dispersait entre les autres mods.
///
/// Le regroupement suit l'identité de l'archive, `uniqueId` (casse ignorée,
/// comme SMAPI) — jamais le nom du mod, qui change d'une version à l'autre,
/// ni l'identifiant Nexus, partagé entre mods (58 sur le parc).
struct NexusArchiveGroup: Identifiable, Equatable {
    /// `uniqueId` en minuscules.
    let id: String
    /// Le nom de la version la plus récente.
    let modName: String
    /// Plus récente d'abord.
    let entries: [NexusArchiveEntry]
    var totalBytes: Int64 { entries.reduce(0) { $0 + $1.byteSize } }
}

enum NexusArchiveGroups {
    /// Groupes triés par nom de mod (comme la liste des mods), versions de
    /// chaque groupe de la plus récente à la plus ancienne.
    static func group(_ entries: [NexusArchiveEntry]) -> [NexusArchiveGroup] {
        let byMod = Dictionary(grouping: entries) { $0.uniqueId.lowercased() }
        return byMod.map { key, members in
            let sorted = members.sorted { $0.timestamp > $1.timestamp }
            return NexusArchiveGroup(id: key, modName: sorted[0].modName, entries: sorted)
        }
        .sorted {
            let order = $0.modName.localizedCaseInsensitiveCompare($1.modName)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
