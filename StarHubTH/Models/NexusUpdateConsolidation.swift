import Foundation

/// Regroupe les mises à jour Nexus par pack avant affichage.
///
/// Extrait du ViewModel, où rien ne le testait. Ce calcul décide de ce que
/// montre l'écran des mises à jour : un pack de dix composants doit produire
/// une ligne et non dix, et la ligne retenue ne doit pas en masquer une plus
/// récente — auquel cas le pack passerait pour à jour alors qu'il ne l'est pas.
///
/// La **résolution** d'un identifiant Nexus vers son pack parent reste au
/// ViewModel (elle dépend du registre des mods installés) ; seule la table
/// `parentPackName` entre ici. C'est ce qui rend ce calcul pur, donc testable.
/// `internal` et non `public` : `NexusUpdateChecker.ModUpdate` l'est aussi, et
/// les tests y accèdent par `@testable import`. L'application compile en un
/// seul module, donc le ViewModel y accède également.
enum NexusUpdateConsolidation {
    /// - Parameter parentPackName: identifiant Nexus effectif → nom du pack qui
    ///   le contient. Un mod autonome n'y figure pas.
    /// - Returns: une entrée par mod autonome et une par pack, par ordre
    ///   alphabétique.
    static func consolidate(_ updates: [NexusUpdateChecker.ModUpdate],
                                   parentPackName: [String: String]) -> [NexusUpdateChecker.ModUpdate] {
        var byPack: [String: [NexusUpdateChecker.ModUpdate]] = [:]
        var consolidated: [NexusUpdateChecker.ModUpdate] = []

        for update in updates {
            if let packName = parentPackName[update.nexusModId] {
                byPack[packName, default: []].append(update)
            } else {
                // Un mod autonome passe tel quel.
                consolidated.append(update)
            }
        }

        for (packName, components) in byPack {
            // Le composant le plus avancé porte la mise à jour du pack : en
            // retenir un autre afficherait une version inférieure à celle
            // réellement disponible.
            guard let winner = highestVersion(among: components) else { continue }
            consolidated.append(
                NexusUpdateChecker.ModUpdate(
                    // La ligne du pack hérite de l'identité du composant
                    // retenu : c'est lui qu'on installera, et c'est la seule
                    // identité de la liste qui soit garantie unique.
                    uniqueId: winner.uniqueId,
                    name: packName,
                    installedVersion: winner.installedVersion,
                    latestVersion: winner.latestVersion,
                    nexusModId: winner.nexusModId,
                    url: winner.url,
                    uploadedTime: winner.uploadedTime
                )
            )
        }

        // Par ordre alphabétique, insensible à la casse et aux accents.
        //
        // Le tri précédent — les plus récemment mises en ligne d'abord —
        // portait sur `uploadedTime`, que la voie smapi.io laisse **toujours**
        // à `nil` : toutes les lignes étaient égales, et `sorted` n'est pas
        // stable en Swift. L'ordre affiché ne voulait donc rien dire et
        // pouvait changer d'une vérification à l'autre. `uploadedTime` garde
        // son rôle là où il est renseigné : départager les composants d'un
        // pack à versions égales, plus haut dans cette fonction.
        return consolidated.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// La mise à jour portant la version la plus haute ; à versions égales, la
    /// plus récemment mise en ligne. `nil` sur une liste vide.
    ///
    /// L'appelant d'origine posait une `precondition` sur la non-vacuité — elle
    /// ne pouvait pas être violée, puisque les listes viennent d'un
    /// regroupement. Rendre l'absence explicite retire un point de crash plutôt
    /// que de compter sur cette invariance.
    static func highestVersion(among updates: [NexusUpdateChecker.ModUpdate]) -> NexusUpdateChecker.ModUpdate? {
        guard var best = updates.first else { return nil }
        for candidate in updates.dropFirst() {
            switch NexusUpdateChecker.compare(candidate.latestVersion, best.latestVersion) {
            case .orderedDescending:
                best = candidate
            case .orderedSame:
                if (candidate.uploadedTime ?? .distantPast) > (best.uploadedTime ?? .distantPast) {
                    best = candidate
                }
            case .orderedAscending:
                break
            }
        }
        return best
    }
}
