import Foundation

/// Fusion de ce qu'une vérification Nexus vient de trouver avec ce qu'on savait
/// déjà.
///
/// Une passe de vérification n'atteint pas forcément tous les mods : un 429
/// coupe le run (les candidats restants ne partent jamais), un 404 ou une panne
/// réseau fait échouer un candidat isolé. Remplacer la liste par le résultat
/// brut de la passe efface alors les mises à jour des mods qu'elle n'a pas pu
/// regarder — et comme le résultat est aussi mis en cache, la perte survit au
/// redémarrage et se rejoue tant que le cache est frais.
///
/// La fusion se fait donc par identifiant Nexus, avec quatre règles :
///
/// - candidat interrogé avec succès **et** une mise à jour trouvée → la ligne
///   est écrite (ou réécrite) ;
/// - candidat interrogé avec succès **sans** mise à jour → sa ligne est
///   **retirée** : c'est la seule preuve qu'il est à jour, sans quoi une ligne
///   une fois affichée ne disparaîtrait plus jamais ;
/// - candidat non atteint ou en échec → sa ligne connue est **conservée** ;
/// - mod qui n'est plus candidat (désinstallé, identifiant Nexus retiré) → sa
///   ligne est purgée.
///
/// Une ligne conservée voit sa version installée rafraîchie : le mod a pu être
/// mis à jour à la main entre deux passes, et la ligne ne doit pas continuer
/// d'annoncer la version d'avant.
enum NexusUpdateMerge {
    /// - Parameters:
    ///   - cached: les mises à jour connues avant cette passe.
    ///   - found: les mises à jour trouvées pendant cette passe.
    ///   - completedModIds: les candidats dont la requête a **abouti**, qu'ils
    ///     aient une mise à jour ou non. C'est ce qui distingue « à jour » de
    ///     « pas regardé ».
    ///   - installedVersionByModId: tous les candidats de la passe et leur
    ///     version installée — y compris ceux jamais interrogés.
    static func merge(
        cached: [NexusUpdateChecker.ModUpdate],
        found: [NexusUpdateChecker.ModUpdate],
        completedModIds: Set<String>,
        installedVersionByModId: [String: String]
    ) -> [NexusUpdateChecker.ModUpdate] {
        var byId: [String: NexusUpdateChecker.ModUpdate] = [:]
        // Sans aucun candidat, on ne sait rien : la liste des mods peut ne pas
        // être encore chargée. Purger là-dessus effacerait des mises à jour que
        // personne n'a installées — elles doivent tenir jusqu'à ce qu'elles
        // soient faites.
        let canPrune = !installedVersionByModId.isEmpty

        for row in cached {
            // Purge : le mod n'est plus candidat.
            guard let installed = installedVersionByModId[row.nexusModId] else {
                if canPrune { continue }
                byId[row.nexusModId] = row
                continue
            }
            // Interrogé avec succès et absent de `found` : il est à jour.
            if completedModIds.contains(row.nexusModId) { continue }
            byId[row.nexusModId] = NexusUpdateChecker.ModUpdate(
                name: row.name,
                installedVersion: installed,
                latestVersion: row.latestVersion,
                nexusModId: row.nexusModId,
                url: row.url,
                uploadedTime: row.uploadedTime
            )
        }

        for row in found {
            byId[row.nexusModId] = row
        }

        // La fusion passe par un dictionnaire : sans tri, l'ordre des lignes
        // changerait à chaque vérification sous les yeux de l'utilisateur.
        return byId.values.sorted {
            $0.name == $1.name ? $0.nexusModId < $1.nexusModId : $0.name < $1.name
        }
    }
}
