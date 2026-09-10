import Foundation

/// La règle qui décide quels mods la liste montre — et, depuis X57, ceux sur
/// lesquels la bascule en masse agit.
///
/// Elle vivait dans `ModListView`, puis dans le ViewModel : dans les deux cas
/// hors de portée de `swift test`, alors qu'elle commande **ce que
/// l'utilisateur voit**. Extraite le 2026-09-10 (point 2 du §5 de
/// `docs/REFACTORING.md`), par lots : ce fichier ne porte pour l'instant que
/// les prédicats dont les entrées sont **des valeurs** — le mod, les filtres, et
/// au plus un `Set` de noms de dossiers. Ceux qui ont besoin d'un verdict
/// calculé (catégorie, anomalie, couverture française) suivront avec le paquet
/// de closures qu'ils demandent.
///
/// Pourquoi des fonctions statiques et non un type à état : la règle n'a pas de
/// mémoire. Chaque prédicat répond d'un mod et d'un cadrage, sans rien retenir
/// entre deux appels — l'y forcer inviterait à y ranger un cache, et un cache
/// invalidé au mauvais moment est précisément ce qui fait diverger deux
/// pipelines jumeaux (X45 en comptait dix).
enum ModListScoping {

    /// `mod` satisfait-il `predicate`, ou — pour un pack — l'un de ses
    /// composants ?
    ///
    /// L'unique test « cette ligne correspond-elle à X », partagé par la
    /// recherche et le filtre des problèmes, de sorte que les deux ne puissent
    /// pas dériver indépendamment. Les `dependencies`/`uniqueId` propres d'un
    /// en-tête de pack étant vides, l'éprouver lui-même avant ses composants est
    /// toujours sûr, et le plus souvent sans effet.
    static func matchesSelfOrAnyChild(_ mod: ModItem,
                                      _ predicate: (ModItem) -> Bool) -> Bool {
        if predicate(mod) { return true }
        if mod.isGroup, let children = mod.children {
            return children.contains(where: predicate)
        }
        return false
    }

    /// La recherche porte sur le nom **et** l'identifiant : c'est par le second
    /// qu'un mod se retrouve quand son nom affiché ne dit rien à personne.
    static func matchesSearch(_ mod: ModItem, filters: ModListFilters) -> Bool {
        filters.search.isEmpty || matchesSelfOrAnyChild(mod) {
            $0.name.localizedCaseInsensitiveContains(filters.search)
                || $0.uniqueId.localizedCaseInsensitiveContains(filters.search)
        }
    }

    static func matchesConfig(_ mod: ModItem, filters: ModListFilters) -> Bool {
        !filters.configOnly || matchesSelfOrAnyChild(mod) { $0.hasConfigFile }
    }

    /// Le favori se marque sur la ligne de premier niveau, donc se teste sur
    /// elle : un pack est favori pour lui-même, pas par l'un de ses composants.
    ///
    /// - Parameter favorites: les dossiers marqués, tels que le magasin les
    ///   porte. Ils arrivent en valeur — la marque est un `Set` de noms, pas un
    ///   calcul, et la faire entrer par une closure masquerait qu'elle est
    ///   gratuite.
    static func matchesFavorites(_ mod: ModItem, filters: ModListFilters,
                                 favorites: Set<String>) -> Bool {
        !filters.favoritesOnly || favorites.contains(mod.folderName)
    }

    /// Le cadrage « écarter » : laisse passer tout le monde par défaut, ne garde
    /// que les mods écartés quand le filtre est actif. Symétrique de
    /// `matchesFavorites` — voir son commentaire pour le pourquoi du premier
    /// niveau.
    static func matchesBlacklisted(_ mod: ModItem, filters: ModListFilters,
                                   blacklisted: Set<String>) -> Bool {
        !filters.blacklistedOnly || blacklisted.contains(mod.folderName)
    }

    /// Ce que la couverture française d'un mod vaut pour le cadrage. Trois
    /// magasins que le ViewModel tient à jour en tâche de fond, groupés ici
    /// parce que `matchesTranslation` les lit tous les trois et qu'aucun n'est
    /// un calcul : ce sont des lectures de dictionnaire.
    struct TranslationState {
        /// La couverture mesurée, par nom de dossier. Un mod **absent** de cette
        /// carte n'a pas encore été lu — ce n'est pas la même chose qu'une
        /// couverture nulle, et le cadrage `.partial` en dépend.
        let coverage: [String: TranslationCoverage.Coverage]
        /// Les mods dont la traduction est en retard sur la version anglaise,
        /// constaté à la date des fichiers.
        let stale: Set<String>
        /// Le nombre de clés obsolètes connu du dernier diff ouvert. Zéro tant
        /// qu'on n'a jamais ouvert l'onglet Traduction d'un mod : sans
        /// référence, il n'y a pas de verdict.
        let outdatedKeys: [String: Int]

        init(coverage: [String: TranslationCoverage.Coverage] = [:],
             stale: Set<String> = [],
             outdatedKeys: [String: Int] = [:]) {
            self.coverage = coverage
            self.stale = stale
            self.outdatedKeys = outdatedKeys
        }
    }

    /// Le cadrage par couverture française.
    ///
    /// Les cinq cas ne se déduisent pas les uns des autres — chacun porte une
    /// mesure faite sur le parc réel, consignée à son cas.
    static func matchesTranslation(_ mod: ModItem,
                                   _ scope: FrenchTranslationScope,
                                   state: TranslationState) -> Bool {
        switch scope {
        case .off:
            return true
        case .available:
            // Un pack correspond dès qu'un composant livre une traduction fr.
            return matchesSelfOrAnyChild(mod) { $0.languages.contains("fr") }
        case .partial:
            // Ne montre que les mods **déjà mesurés** : la couverture se calcule
            // en tâche de fond, et annoncer « complet » sur un mod qu'on n'a pas
            // encore lu serait faux. La liste se complète donc à mesure que le
            // calcul avance.
            return matchesSelfOrAnyChild(mod) { child in
                guard let coverage = state.coverage[child.folderName]?.displayPercent else {
                    return false
                }
                return coverage < 100
            }
        case .missing:
            // « Pas de français » ne veut rien dire d'un mod qui n'a aucun
            // `i18n` : il n'a pas de texte à traduire, et l'y faire figurer
            // noyait le filtre. Mesuré sur le parc : 397 mods sans français,
            // dont **310 sans le moindre fichier de traduction**. Le filtre
            // servait à trouver ce qu'on pourrait traduire ; il rendait 8 fois
            // plus de bruit que de signal.
            //
            // `languages` porte `en` dès qu'un `default.json` existe : un mod
            // traduisible en a donc au moins un.
            let translatable = matchesSelfOrAnyChild(mod) { !$0.languages.isEmpty }
            return translatable
                && !matchesSelfOrAnyChild(mod) { $0.languages.contains("fr") }
        case .stale:
            // Les deux signaux réunis : la date, connue de tous les mods dès le
            // scan, et les clés, connues des seuls mods dont on a déjà ouvert
            // le diff.
            return matchesSelfOrAnyChild(mod) { child in
                state.stale.contains(child.folderName)
                    || (state.outdatedKeys[child.folderName] ?? 0) > 0
            }
        }
    }

    /// La clé de type inférée d'un mod, stable. Pour un pack, celle de son
    /// composant **principal** (le premier) — le pack montre le tag de son
    /// composant de tête, comme en amont.
    static func inferredTagKey(for mod: ModItem) -> String {
        let target = (mod.isGroup ? (mod.children?.first ?? mod) : mod)
        return ModItem.inferTag(name: target.name, uniqueId: target.uniqueId,
                                description: target.description)
    }
}
