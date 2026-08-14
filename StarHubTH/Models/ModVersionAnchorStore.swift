import Foundation

/// Résultat de la migration du registre hors du champ `nexusVersion`.
/// Distinguer « rien à faire » de « illisible » n'est pas du zèle : cette
/// migration répare des données réelles, et un registre qu'on n'a pas su lire
/// doit se voir, pas se taire.
public enum RegistryMigrationOutcome: Equatable {
    case nothingToDo
    /// Les dossiers dont le champ a été retiré. Ce ne sont pas seulement des
    /// noms pour le journal : la version qu'ils portaient au registre était
    /// celle de Nexus, donc au prochain scan leur version « changera » sans que
    /// le disque ait bougé. Sans cette liste, `InstalledModRegistry.sync` les
    /// ré-estampillerait, écrasant sans retour leur date d'installation.
    case stripped([String])
    case registryUnreadable
}

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
    /// - Returns: `.nothingToDo` si la clé est absente ou si aucun enregistrement
    ///   ne porte `nexusVersion` ; `.stripped(dossiers)` si des enregistrements ont été
    ///   nettoyés et persistés ; `.registryUnreadable` si la charge n'est pas
    ///   parsable ou si la ré-sérialisation a échoué.
    @discardableResult
    public static func migrateAwayFromNexusVersion(defaults: UserDefaults = .standard) -> RegistryMigrationOutcome {
        guard let data = defaults.data(forKey: registryKey) else {
            return .nothingToDo
        }
        guard var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .registryUnreadable
        }
        var stripped: [String] = []
        for (folder, value) in json {
            guard var record = value as? [String: Any],
                  record.removeValue(forKey: "nexusVersion") != nil else { continue }
            json[folder] = record
            stripped.append(folder)
        }
        guard !stripped.isEmpty else {
            return .nothingToDo
        }
        guard let rewritten = try? JSONSerialization.data(withJSONObject: json) else {
            return .registryUnreadable
        }
        defaults.set(rewritten, forKey: registryKey)
        return .stripped(stripped.sorted())
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
