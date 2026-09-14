import Foundation

/// Persistance de l'état de page Nexus, par `UniqueID` (`nexus_page_states.json`).
///
/// Le jumeau de `ModCompatibilityStore`, pour la même raison : le badge doit
/// être là au prochain lancement, avant qu'un nouveau check n'ait abouti.
/// Rebâtissable en une vérification — le perdre coûte un silence temporaire,
/// pas une donnée. Le contenu est une **projection du dernier check** : la
/// reprise réécrit l'ensemble observé, l'élagage (`NexusPageState.prune`)
/// retire les mods désinstallés.
enum NexusPageStateStore {
    private static var fileURL: URL? {
        guard let dir = AppSupport.directory else { return nil }
        return dir.appendingPathComponent("nexus_page_states.json")
    }

    static func load() -> [String: NexusPageState] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: NexusPageState].self, from: data)
        else { return [:] }
        return map
    }

    /// Écrit les états. **Rend `false` en cas d'échec**, et l'appelant doit
    /// le dire au journal — même règle que `ModCompatibilityStore` : une
    /// écriture perdue en silence ne se voit qu'au lancement suivant.
    @discardableResult
    static func save(_ states: [String: NexusPageState]) -> Bool {
        guard let url = fileURL, let data = try? JSONEncoder().encode(states) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
