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

    /// Ce que le cadrage complet a besoin de savoir et qu'il ne peut pas
    /// calculer lui-même.
    ///
    /// Deux closures seulement — le relevé du 2026-09-10 avait annoncé cinq
    /// dépendances puis en a mesuré neuf, mais sept se sont révélées être des
    /// **valeurs** : des `Set` de noms de dossiers et des dictionnaires. Ne
    /// restent ici que ce qui calcule vraiment.
    ///
    /// ⚠️ **Les deux closures sont paresseuses à dessein, et doivent le rester.**
    /// `category` est mémoïsée derrière un cache côté appelant, et `sizeOnDisk`
    /// rend `nil` tant que la passe de mesure n'a pas abouti. Résoudre ces
    /// verdicts d'avance pour les 949 mods du parc les transformerait en
    /// balayage inconditionnel, y compris sous les tris et filtres qui ne les
    /// lisent jamais. C'est le chemin même que **F3** met en cause.
    ///
    /// Le verdict d'anomalie n'est **pas** ici : il ne sert qu'au cadrage
    /// « Problèmes », et `scoped(_:scope:hasAnomaly:)` est une fonction séparée,
    /// appelée depuis les vues (`ModListView`) sans jamais avoir d'`Inputs` en
    /// main. Il a vécu ici un temps sans lecteur — deux portes d'entrée pour la
    /// même règle, le motif X45 que ce fichier existe précisément pour fermer.
    struct Inputs {
        /// La catégorie effective, surcharge manuelle comprise, un pack rendant
        /// celle qui domine chez ses composants.
        let category: (ModItem) -> NexusCategory?
        /// Le poids mesuré, `nil` tant que la mesure n'a pas abouti.
        let sizeOnDisk: (ModItem) -> Int64?
        let favorites: Set<String>
        let blacklisted: Set<String>
        let translation: TranslationState
        /// Les dates de dernière activation, pour le tri correspondant.
        let activationDates: [String: Date]

        init(category: @escaping (ModItem) -> NexusCategory? = { _ in nil },
             sizeOnDisk: @escaping (ModItem) -> Int64? = { _ in nil },
             favorites: Set<String> = [],
             blacklisted: Set<String> = [],
             translation: TranslationState = .init(),
             activationDates: [String: Date] = [:]) {
            self.category = category
            self.sizeOnDisk = sizeOnDisk
            self.favorites = favorites
            self.blacklisted = blacklisted
            self.translation = translation
            self.activationDates = activationDates
        }
    }

    /// Le cadrage par catégorie.
    ///
    /// `category` résout déjà un pack à la catégorie qui domine chez ses
    /// composants : ce prédicat s'accorde donc **par construction** avec la
    /// pastille affichée sur la ligne du pack.
    static func matchesCategory(_ mod: ModItem, filters: ModListFilters,
                                category: (ModItem) -> NexusCategory?) -> Bool {
        switch filters.category {
        case .all:
            return true
        case .category(let cat):
            return category(mod)?.id == cat.id
        case .inferredTag(let tag):
            return category(mod) == nil && inferredTagKey(for: mod) == tag
        case .uncategorized:
            // Même raisonnement : `category` rend `nil` pour un pack exactement
            // quand aucun de ses composants n'a de catégorie connue, ce que son
            // absence de pastille montre.
            return category(mod) == nil && inferredTagKey(for: mod) == "Other"
        }
    }

    /// Les six filtres composés. **Ne trie pas** — voir `sorted(_:by:_:)`.
    static func matches(_ mod: ModItem, filters: ModListFilters,
                        inputs: Inputs) -> Bool {
        matchesSearch(mod, filters: filters)
            && matchesCategory(mod, filters: filters, category: inputs.category)
            && matchesConfig(mod, filters: filters)
            && matchesFavorites(mod, filters: filters, favorites: inputs.favorites)
            && matchesBlacklisted(mod, filters: filters, blacklisted: inputs.blacklisted)
            && matchesTranslation(mod, filters.frenchTranslation, state: inputs.translation)
    }

    /// La liste cadrée restreinte au cadrage courant — ce que la section
    /// « Tous / Activés / En pause / Problèmes » montre, et l'ensemble exact
    /// sur lequel la bascule en masse agit (X57).
    ///
    /// **Pas** de partition actifs/en pause sous « Tous » : grouper d'abord par
    /// état écraserait le tri choisi — trier par poids remontait le plus gros
    /// mod *actif*, jamais le plus gros du parc, alors que les trois quarts du
    /// poids dorment dans des mods en pause. L'état reste lisible ligne à ligne
    /// dans la liste ; ici, l'ordre du tri passe tel quel.
    /// - Parameter hasAnomaly: le verdict d'anomalie, **paresseux à dessein**.
    ///   Il fait un balayage de dépendances par mod — c'est pour ne pas le
    ///   refaire à chaque évaluation du sélecteur que `ModListView.scopeCounts`
    ///   existe. Le résoudre d'avance pour les 949 mods du parc en ferait un
    ///   balayage inconditionnel, y compris sous « Tous », qui ne le lit jamais.
    ///   C'est le chemin même que **F3** met en cause. Il arrive en paramètre
    ///   plutôt que par `Inputs` parce que les vues appellent ce cadrage seul.
    static func scoped(_ mods: [ModItem], scope: ModFilter,
                       hasAnomaly: (ModItem) -> Bool) -> [ModItem] {
        switch scope {
        case .all:      return mods
        case .enabled:  return mods.filter(\.isEnabled)
        case .disabled: return mods.filter { !$0.isEnabled }
        case .issues:   return mods.filter { mod in
            // Tout ce qui porte une anomalie, en propre ou par un composant.
            //
            // ⚠️ **La restriction aux mods activés n'est pas ici** : elle vit
            // dans le verdict que l'appelant fournit, et elle ne porte que sur
            // les **dépendances** (`hasDependencyIssue` : `mod.isEnabled && …`)
            // — un mod en pause ne s'appuie sur rien, lui reprocher une
            // dépendance manquante n'aurait pas de sens. Un mod en pause
            // apparaît en revanche pour une erreur de journal, un manifest sans
            // identifiant, un doublon ou une incompatibilité connue : ceux-là ne
            // cessent pas d'exister parce qu'on l'a mis en pause.
            matchesSelfOrAnyChild(mod) { hasAnomaly($0) }
        }
        }
    }

    /// Le tri de la liste.
    ///
    /// `.name` ne trie **pas** : la liste porte déjà cet ordre, établi par le
    /// scan (`scannedMods.alphabeticalListOrder`), et un filtre le préserve. Le
    /// code triait ici avec un comparateur toujours faux, ce qui ne rendait le
    /// même résultat **que si** `sorted(by:)` était stable : la bibliothèque
    /// standard ne le garantit pas (elle l'est aujourd'hui, par implémentation).
    /// Ne rien faire est à la fois juste et gratuit — le tri à blanc coûtait une
    /// passe complète sur 949 mods à chaque rendu, donc à chaque frappe dans la
    /// recherche.
    static func sorted(_ mods: [ModItem], by order: ModSortOrder,
                       inputs: Inputs) -> [ModItem] {
        guard order != .name else { return mods }
        return mods.sorted { lhs, rhs in
            switch order {
            case .name:
                // Inatteignable : écarté par le `guard` ci-dessus. Le cas reste
                // écrit pour que le `switch` demeure exhaustif.
                return false
            case .activationOrder:
                return byDateThenName(inputs.activationDates[lhs.folderName],
                                      inputs.activationDates[rhs.folderName], lhs, rhs)
            case .installDate:
                return byDateThenName(lhs.effectiveInstallDate, rhs.effectiveInstallDate,
                                      lhs, rhs)
            case .nameDescending:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            case .author:
                let authorOrder = lhs.author.localizedCaseInsensitiveCompare(rhs.author)
                if authorOrder != .orderedSame { return authorOrder == .orderedAscending }
                return byName(lhs, rhs)
            case .version:
                let versionOrder = NexusUpdateChecker.compare(lhs.version, rhs.version)
                if versionOrder != .orderedSame { return versionOrder == .orderedDescending }
                return byName(lhs, rhs)
            case .size:
                // Le plus lourd d'abord : c'est le sens dans lequel on cherche.
                // Les non mesurés ferment la marche, par nom — et ils sont
                // nombreux par construction : rien n'est mesuré tant que la
                // première passe n'a pas abouti, ni pendant les secondes qui
                // suivent une bascule.
                switch (inputs.sizeOnDisk(lhs), inputs.sizeOnDisk(rhs)) {
                case (let l?, let r?):
                    if l != r { return l > r }
                    return byName(lhs, rhs)
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil):   return byName(lhs, rhs)
                }
            }
        }
    }

    /// Le plus récent d'abord, les sans-date en fin de liste, départagés par
    /// nom. La forme est la même pour la date d'activation et celle
    /// d'installation : elle vivait en deux exemplaires identiques.
    ///
    /// ⚠️ **Un point n'est pas un simple déplacement : le départage par nom sur
    /// dates égales.** Les deux originaux rendaient `l > r` nu, donc `false` à
    /// dates égales — un ordre qui ne tenait que si `sorted(by:)` était stable,
    /// ce que la bibliothèque standard ne garantit pas. C'est le défaut même que
    /// le tri `.name` corrige juste au-dessus. Le cas est atteignable :
    /// `copyItem` conserve la date d'empaquetage de l'archive, et le parc de
    /// référence compte **63 horodatages partagés couvrant 175 de ses 961
    /// dossiers** (mesuré le 2026-09-10). Couvert par
    /// `equalDatesAreBrokenByNameRatherThanLeftUndetermined`.
    private static func byDateThenName(_ lhs: Date?, _ rhs: Date?,
                                       _ lhsMod: ModItem, _ rhsMod: ModItem) -> Bool {
        switch (lhs, rhs) {
        case (let l?, let r?):
            if l != r { return l > r }
            return byName(lhsMod, rhsMod)
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil):   return byName(lhsMod, rhsMod)
        }
    }

    private static func byName(_ lhs: ModItem, _ rhs: ModItem) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    /// La clé de type inférée d'un mod, stable. Pour un pack, celle de son
    /// composant **principal** (le premier) — le pack montre le tag de son
    /// composant de tête, comme en amont. Le tag est déjà **stocké** sur
    /// chaque `ModItem` (calculé à l'init — F3) : cette fonction ne fait plus
    /// que choisir l'item qui le porte.
    static func inferredTagKey(for mod: ModItem) -> String {
        (mod.isGroup ? (mod.children?.first ?? mod) : mod).inferredTag
    }
}
