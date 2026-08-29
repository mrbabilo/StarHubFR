import Foundation

/// Où vivent les verdicts que l'utilisateur a posés sur des incompatibilités
/// entre mods (déclarées ou écartées).
///
/// Dans Application Support et non dans Caches, comme `InstalledTranslationStore` :
/// c'est la **seule** trace de ce triage. Le perdre effacerait un travail que
/// l'utilisateur ne referait pas — une incompatibilité qu'il connaît
/// disparaîtrait du rapport, et un faux positif qu'il a écarté y réapparaîtrait
/// comme s'il ne l'avait jamais vu.
///
/// L'emplacement est **partagé** avec `InstalledTranslationStore` — on réutilise
/// son `directory` plutôt que d'en recalculer un identique ici. Un seul dossier
/// de données utilisateur, pas deux copies du même calcul qui pourraient un
/// jour diverger : le dépôt a déjà payé ce prix ailleurs, avec quatre copies
/// d'un même filtre de fichiers système dont une amputée laissait un dossier
/// `.Spotlight-V100` s'afficher comme un mod.
public enum ModConflictVerdictsStore {
    static var fileURL: URL? {
        InstalledTranslationStore.directory?.appendingPathComponent("mod_conflicts.json")
    }

    /// Rend un magasin **vide** plutôt qu'une erreur : premier lancement,
    /// fichier absent ou illisible ne doivent jamais empêcher l'utilisateur
    /// d'ouvrir le rapport d'incompatibilités.
    ///
    /// - Parameter url: surcharge du fichier réel. `nil` (par défaut) lit
    ///   `fileURL` ; les tests passent un dossier temporaire pour ne jamais
    ///   toucher aux verdicts de l'utilisateur.
    public static func load(from url: URL? = nil) -> ModConflictVerdicts {
        guard let target = url ?? fileURL, let data = try? Data(contentsOf: target),
              let decoded = try? JSONDecoder().decode(ModConflictVerdicts.self, from: data)
        else { return ModConflictVerdicts() }
        return decoded
    }

    /// Écrit le magasin. **Rend `false` en cas d'échec**, et l'appelant doit
    /// le dire : un verdict perdu en silence est pire que pas de verdict — il
    /// se croit posé alors qu'il ne survivra pas à la fermeture.
    ///
    /// - Parameter url: surcharge du fichier réel, même rôle que dans `load`.
    @discardableResult
    public static func save(_ verdicts: ModConflictVerdicts, to url: URL? = nil) -> Bool {
        guard let target = url ?? fileURL, let data = try? JSONEncoder().encode(verdicts) else { return false }
        do {
            try data.write(to: target, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
