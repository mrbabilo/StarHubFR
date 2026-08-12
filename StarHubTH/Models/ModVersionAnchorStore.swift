import Foundation

/// Persistance des ancres, indexée par `UniqueID`.
///
/// `UserDefaults` est injecté : les tests écriraient sinon dans les
/// préférences réelles de l'utilisateur. Même motif que le reste du dépôt —
/// la dépendance à l'environnement entre par l'initialiseur, pas par un
/// singleton.
public final class ModVersionAnchorStore {
    private static let key = "modVersionAnchors"
    private static let registryKey = "installedModRegistry"

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func all() -> [String: ModVersionAnchor] {
        lock.lock()
        defer { lock.unlock() }
        return load()
    }

    public func anchor(for uniqueId: String) -> ModVersionAnchor? {
        all()[uniqueId]
    }

    public func put(_ anchor: ModVersionAnchor) {
        mutate { $0[anchor.uniqueId] = anchor }
    }

    public func remove(uniqueId: String) {
        mutate { $0.removeValue(forKey: uniqueId) }
    }

    /// Retire les ancres des mods qui ne sont plus installés. Sans ce ménage,
    /// un mod supprimé puis réinstallé hériterait d'une version affirmée qu'il
    /// n'a pas.
    public func pruneAnchors(keeping installed: Set<String>) {
        mutate { $0 = $0.filter { installed.contains($0.key) } }
    }

    // MARK: - Migration

    /// Retire `nexusVersion` de chaque enregistrement du registre d'install.
    ///
    /// C'est le champ qui confondait « la dernière version publiée sur Nexus »
    /// et « la version installée » : le vérificateur comparait ensuite cette
    /// version à elle-même et concluait « à jour ». 52 mods du parc réel en
    /// portaient une qu'ils n'avaient pas.
    ///
    /// On réécrit le JSON brut plutôt que de décoder vers `InstalledModRecord` :
    /// le type ne porte plus le champ, un aller-retour de décodage le
    /// supprimerait sans qu'on puisse le compter, ni signaler ce qu'on a fait.
    ///
    /// - Returns: le nombre d'enregistrements effectivement nettoyés.
    @discardableResult
    public static func migrateAwayFromNexusVersion(defaults: UserDefaults = .standard) -> Int {
        guard let data = defaults.data(forKey: registryKey),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return 0
        }
        var stripped = 0
        for (folder, value) in json {
            guard var record = value as? [String: Any],
                  record.removeValue(forKey: "nexusVersion") != nil else { continue }
            json[folder] = record
            stripped += 1
        }
        guard stripped > 0,
              let rewritten = try? JSONSerialization.data(withJSONObject: json) else {
            return stripped
        }
        defaults.set(rewritten, forKey: registryKey)
        return stripped
    }

    // MARK: - Privé

    private func mutate(_ body: (inout [String: ModVersionAnchor]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var map = load()
        body(&map)
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Une charge illisible rend un magasin vide plutôt qu'une erreur : les
    /// ancres se reposent sur constat, les perdre coûte une redécouverte, pas
    /// une donnée irremplaçable.
    private func load() -> [String: ModVersionAnchor] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([String: ModVersionAnchor].self, from: data) else {
            return [:]
        }
        return decoded
    }
}
