import Foundation
import Observation
import Combine

/// Les métadonnées Nexus **écrites par l'utilisateur** : la catégorie
/// épinglée sur un mod et l'identifiant Nexus attribué à la main
/// (REFACTORING §6 — le voisinage amont du domaine Nexus). Persistées en
/// JSON dans les préférences — ce sont des données utilisateur, elles
/// survivent à tout, y compris à « oublier » (le clear du checker ne les
/// touche pas).
///
/// Ce qui n'est PAS ici : `nexusCategories`/`nexusModExtras`, miroirs du
/// cache du checker lus une fois au lancement — ils restent au VM.
///
/// « Ce qui n'est pas à moi arrive en paramètre » (§3) : les préférences
/// arrivent par l'initialiseur (suite jetable en test). Les règles de
/// migration (`ModFolderRename.migrate`) et de purge
/// (`ModRemovalPurge.purge`) — déjà Core — sont appelées ici, si bien que
/// la persistance ne peut plus être oubliée par un appelant.
@Observable
final class NexusMetadataStore {

    /// `{ folderName: categoryId }` — la catégorie épinglée par
    /// l'utilisateur, qui gagne sur celle de l'API.
    private(set) var customCategories: [String: Int] = [:]
    /// `{ folderName: modId }` — l'identifiant Nexus attribué à la main,
    /// qui gagne sur les `UpdateKeys` du manifeste.
    private(set) var customModIds: [String: String] = [:]

    private let defaults: UserDefaults
    // Les clés historiques, inchangées : les données des utilisateurs
    // existants sont lues telles quelles.
    private static let categoriesKey = "nexusCustomCategories"
    private static let modIdsKey = "nexusCustomModIds"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.categoriesKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            customCategories = decoded
        }
        if let data = defaults.data(forKey: Self.modIdsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            customModIds = decoded
        }
    }

    // MARK: - Écritures (chaque méthode persiste)

    /// Épingle une catégorie sur un mod ; `nil` revient à la catégorie
    /// automatique de l'API.
    public func setCustomCategory(_ categoryId: Int?, for folderName: String) {
        if let categoryId {
            customCategories[folderName] = categoryId
        } else {
            customCategories.removeValue(forKey: folderName)
        }
        persistCategories()
    }

    /// Attribue un identifiant Nexus à la main ; `nil` ou blanc retire.
    /// Le trim fait partie de la règle : un copier-coller venu d'une URL
    /// se nettoie ici, pas chez chaque appelant.
    public func setCustomModId(_ modId: String?, for folderName: String) {
        let trimmed = (modId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            customModIds.removeValue(forKey: folderName)
        } else {
            customModIds[folderName] = trimmed
        }
        persistModIds()
    }

    /// Le plan d'apprentissage (`NexusIdLearning`) fusionné d'un bloc —
    /// parfois vingt identifiants d'un coup, une seule persistance.
    public func mergeCustomModIds(_ ids: [String: String]) {
        for (folderName, id) in ids {
            customModIds[folderName] = id
        }
        persistModIds()
    }

    /// Un dossier renommé : les métadonnées suivent (`shared` est le
    /// drapeau de collision d'`ModFolderRename` — renommage vers un dossier
    /// déjà présent — et `policy` porte la règle leaveBehind des
    /// identifiants). Persiste chaque table uniquement si elle a bougé.
    /// Retourne `true` si quelque chose a été migré.
    @discardableResult
    public func migrateFolderName(from old: String, to new: String,
                                  shared: Bool) -> Bool {
        var changed = false
        if ModFolderRename.migrate(&customModIds, from: old, to: new,
                                   shared: shared, policy: .leaveBehind) {
            persistModIds()
            changed = true
        }
        if ModFolderRename.migrate(&customCategories, from: old, to: new, shared: shared) {
            persistCategories()
            changed = true
        }
        return changed
    }

    /// Un mod supprimé : ses métadonnées ne doivent pas traîner. Persiste
    /// chaque table uniquement si elle a bougé. Retourne `true` si quelque
    /// chose a été purgé.
    @discardableResult
    public func purgeMod(folderName: String) -> Bool {
        var changed = false
        if ModRemovalPurge.purge(&customModIds, removing: folderName) {
            persistModIds()
            changed = true
        }
        if ModRemovalPurge.purge(&customCategories, removing: folderName) {
            persistCategories()
            changed = true
        }
        return changed
    }

    // MARK: - Persistance

    /// Posée par le possesseur : appelée après chaque persistance, c'est-à-dire
    /// après toute mutation. Le VM y purge son cache de catégories et incrémente
    /// la révision qui le publie — sous `@Observable`, il n'y a plus de
    /// publication globale à laquelle se raccrocher, ce crochet **est** le
    /// chemin d'invalidation, le seul.
    ///
    /// ⚠️ `@ObservationIgnored` : une closure stockée dans une classe
    /// `@Observable` devient de l'état observable comme le reste. La lire dans
    /// `persistCategories()` enregistrerait un accès dans n'importe quelle
    /// portée de suivi active, et la poser publierait un changement — pour un
    /// champ qui n'est pas de l'état.
    ///
    /// L'écriture passe par `setOnInvalidate(_:)` : parce que ce crochet est
    /// unique, l'écraser désactive le rafraîchissement des catégories sans
    /// erreur ni plantage, et un point d'écriture nommé se cherche au `grep`.
    @ObservationIgnored
    public private(set) var onInvalidate: (() -> Void)?

    /// Pose le crochet d'invalidation. Voir `onInvalidate` — il n'y en a qu'un,
    /// et le poser deux fois remplace le premier.
    public func setOnInvalidate(_ handler: (() -> Void)?) {
        onInvalidate = handler
    }

    private func persistCategories() {
        onInvalidate?()
        guard let data = try? JSONEncoder().encode(customCategories) else { return }
        defaults.set(data, forKey: Self.categoriesKey)
    }

    private func persistModIds() {
        onInvalidate?()
        guard let data = try? JSONEncoder().encode(customModIds) else { return }
        defaults.set(data, forKey: Self.modIdsKey)
    }
}
