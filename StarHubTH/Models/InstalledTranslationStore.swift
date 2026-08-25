import Foundation

/// Où vivent les traductions posées sur les mods.
///
/// Dans Application Support et non dans Caches, comme `ModErrorHistoryStore` :
/// c'est la **seule** trace de ce qui a été déposé. La perdre rendrait toute
/// désinstallation impossible — les fichiers resteraient dans les mods sans que
/// rien ne sache plus d'où ils viennent.
public enum InstalledTranslationStore {
    static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("StarHubTH", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var fileURL: URL? {
        directory?.appendingPathComponent("installed_translations.json")
    }

    /// Où les fichiers recouverts sont mis à l'abri.
    public static var backupRoot: URL? {
        directory?.appendingPathComponent("TranslationBackups", isDirectory: true)
    }

    public static func load() -> InstalledTranslationRegistry {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let registry = try? JSONDecoder().decode(InstalledTranslationRegistry.self, from: data)
        else { return InstalledTranslationRegistry() }
        return registry
    }

    /// Écrit le registre. **Rend `false` en cas d'échec**, et l'appelant doit
    /// le dire : c'est la seule trace de ce qui a été déposé. Un enregistrement
    /// perdu en silence laisserait des fichiers dans un mod sans que rien ne
    /// sache plus les retirer — le contraire du service rendu.
    @discardableResult
    public static func save(_ registry: InstalledTranslationRegistry) -> Bool {
        guard let url = fileURL, let data = try? JSONEncoder().encode(registry) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
