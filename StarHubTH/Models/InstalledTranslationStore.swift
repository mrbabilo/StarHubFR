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

    /// Charge le registre : le fichier d'abord, son `.bak` si le fichier est
    /// corrompu — promu au fichier principal au passage, comme le registre
    /// d'install UserDefaults promeut son backup. Un registre perdu rendrait
    /// toute désinstallation impossible ; un registre vide silencieux est le
    /// même mal déguisé en premier lancement.
    ///
    /// - Parameter url: surcharge du fichier réel. `nil` (par défaut) lit
    ///   `fileURL` ; les tests passent un dossier temporaire pour ne jamais
    ///   toucher aux traductions de l'utilisateur.
    public static func load(from url: URL? = nil) -> InstalledTranslationRegistry {
        guard let target = url ?? fileURL else { return InstalledTranslationRegistry() }
        guard let data = try? Data(contentsOf: target) else {
            return InstalledTranslationRegistry()   // premier lancement : pas un événement
        }
        if let registry = try? JSONDecoder().decode(InstalledTranslationRegistry.self, from: data) {
            return registry
        }
        // Présent mais illisible : c'est une corruption, et elle se dit.
        let backup = target.appendingPathExtension("bak")
        if let backupData = try? Data(contentsOf: backup),
           let registry = try? JSONDecoder().decode(InstalledTranslationRegistry.self,
                                                    from: backupData) {
            // Promotion : le prochain chargement ne repassera pas par ici.
            // Best effort — si l'écriture échoue, le backup reste en place
            // et servira encore.
            if let promoted = try? JSONEncoder().encode(registry) {
                try? promoted.write(to: target, options: .atomic)
            }
            NSLog("[StarHubFR] Registre des traductions corrompu — restauré "
                  + "depuis le backup (%lu hôte(s)).", registry.byHost.count)
            return registry
        }
        NSLog("[StarHubFR] Registre des traductions illisible et sans backup "
              + "lisible — repars vide.")
        return InstalledTranslationRegistry()
    }

    /// Écrit le registre au fichier principal **et** à son `.bak`, la même
    /// génération aux deux emplacements — le motif du registre d'install
    /// UserDefaults : une corruption de l'un se relit depuis l'autre. **Rend
    /// `false` en cas d'échec du principal**, et l'appelant doit le dire :
    /// c'est la seule trace de ce qui a été déposé. Un enregistrement perdu en
    /// silence laisserait des fichiers dans un mod sans que rien ne sache plus
    /// les retirer — le contraire du service rendu. L'écriture du `.bak` est
    /// best effort : le principal seul ne casse pas le contrat.
    ///
    /// - Parameter url: surcharge du fichier réel, même rôle que dans `load`.
    @discardableResult
    public static func save(_ registry: InstalledTranslationRegistry, to url: URL? = nil) -> Bool {
        guard let target = url ?? fileURL,
              let data = try? JSONEncoder().encode(registry) else { return false }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            return false
        }
        try? data.write(to: target.appendingPathExtension("bak"), options: .atomic)
        return true
    }
}
