import Foundation

/// La composition des deux appels réseau de la fiche de mod : la
/// description (`mods/{id}.json`) puis le changelog **complet**
/// (`mods/{id}/changelogs.json` — toutes versions, pas le `changelog_html`
/// d'un seul fichier). Extrait du ViewModel le 2026-09-10 (REFACTORING §6,
/// domaine Détail de mod, tranche 3).
///
/// Les fetchers arrivent en closures (§3) : `NexusUpdateChecker.shared`
/// en production, des stubs en test. La règle — une description vide
/// invalide le tout (le repli cache/local de l'appelant reste intact
/// plutôt que d'être écrasé par du blanc), un changelog vide est
/// acceptable — vit ici, testée.
///
/// A3-T7 : une description v1 vide (pas de clé, quota épuisé, panne) passe
/// la main au repli v2 (`NexusModDetailV2`, sans clé), qui rend les deux
/// d'un coup ; `nil` du repli garde la règle — rien n'écrase le local.
enum ModDetailRefresh {

    static func fetch(modId: Int,
                      fetchDescription: @escaping (Int, @escaping (String) -> Void) -> Void,
                      fetchChangelogs: @escaping (Int, @escaping (String) -> Void) -> Void,
                      fallback: @escaping (Int, @escaping (ModDetailRaw?) -> Void) -> Void = { $1(nil) },
                      completion: @escaping (ModDetailRaw?) -> Void) {
        fetchDescription(modId) { description in
            guard !description.isEmpty else {
                fallback(modId, completion)
                return
            }
            fetchChangelogs(modId) { changelog in
                completion(ModDetailRaw(description: description, changelog: changelog))
            }
        }
    }
}
