import Foundation

/// R4 (audit UX 2026-10-16) — ce qu'un profil retient des `config.json`, mod
/// par mod : la section « Configs mémorisées » de sa feuille, la colonne
/// « Configs » de sa rangée, la confirmation de sa suppression.
///
/// Remplace `StarHubTHViewModel.profileConfigSummary`, qui ne rendait qu'un
/// compte et les noms d'orphelins : la feuille veut la liste entière.
struct ProfileConfigOverview: Equatable {
    struct Row: Identifiable, Equatable {
        /// Clé du magasin : le `folderName` **logique**, une pause ne vaut pas
        /// désinstallation.
        let folderName: String
        /// Le nom du mod installé, à défaut le dossier : un orphelin n'a plus
        /// de manifeste à lire.
        let name: String
        let isInstalled: Bool
        var id: String { folderName }
    }

    /// Les mods installés d'abord, par nom ; les orphelins ensuite, par dossier.
    let rows: [Row]

    var total: Int { rows.count }
    var orphans: [String] { rows.filter { !$0.isInstalled }.map(\.folderName) }

    init(storedFolders: some Sequence<String>, installed: [ModItem]) {
        var names: [String: String] = [:]
        for mod in installed where names[mod.folderName] == nil { names[mod.folderName] = mod.name }
        let all = storedFolders.map { folder in
            Row(folderName: folder, name: names[folder] ?? folder, isInstalled: names[folder] != nil)
        }
        let byName: (Row, Row) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        rows = all.filter(\.isInstalled).sorted(by: byName) + all.filter { !$0.isInstalled }.sorted(by: byName)
    }

    /// Lit le magasin du profil (un fichier décodé) : à l'apparition, jamais
    /// au rendu. `installed` = le parc à plat (`flattenedMods`).
    static func load(profileId: UUID, installed: [ModItem]) -> ProfileConfigOverview {
        let entries = ProfileConfigStore.fileURL(profileId: profileId).map { ProfileConfigStore.load(from: $0) } ?? [:]
        return ProfileConfigOverview(storedFolders: entries.keys, installed: installed)
    }
}
