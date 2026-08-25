import Foundation

/// Persistance des verdicts de compatibilité, par `UniqueID`.
///
/// Dans Application Support, à côté de `ModErrorHistoryStore`, et **persistée
/// plutôt que gardée en mémoire** pour une raison précise : l'avertissement le
/// plus utile se déclenche au moment où l'utilisateur **active** un mod, ce qui
/// arrive volontiers dans la minute qui suit le lancement — avant qu'une
/// vérification ait eu le temps d'aboutir. Un verdict qui meurt à la fermeture
/// ne serait là qu'après coup.
///
/// Rebâtissable, contrairement à l'historique d'erreurs : une vérification
/// suffit à la reconstituer. La perdre coûte donc un avertissement tardif, pas
/// une information définitivement perdue.
enum ModCompatibilityStore {
    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("StarHubTH", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mod_compatibility.json")
    }

    static func load() -> [String: ModCompatibility] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: ModCompatibility].self, from: data)
        else { return [:] }
        return map
    }

    /// Écrit les verdicts. **Rend `false` en cas d'échec**, et l'appelant doit
    /// le dire au journal : une écriture perdue en silence ne se voit qu'au
    /// lancement suivant, sous la forme d'un avertissement qui ne s'ouvre pas
    /// quand l'utilisateur active un mod cassé. Le défaut serait invisible
    /// précisément au moment où il coûte.
    @discardableResult
    static func save(_ verdicts: [String: ModCompatibility]) -> Bool {
        guard let url = fileURL, let data = try? JSONEncoder().encode(verdicts) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
