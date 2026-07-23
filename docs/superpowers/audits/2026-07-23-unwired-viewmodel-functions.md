# Audit : fonctions du ViewModel sans accès UI

**Date** : 2026-07-23
**Contexte** : recherche déclenchée par la question « d'autres features upstream non intégrées ou sans accès direct ? » pendant la conception de la refonte de la page des mods (tri/filtre/bouton Install).

## Méthode

1. Extraction de toutes les fonctions non-`private` de `StarHubTH/StarHubTHViewModel.swift`.
2. Recherche de chaque nom dans `StarHubTH/Views/*.swift` (appel direct `.fn(` et référence de fonction sans parenthèses).
3. Pour chaque candidat sans aucun appel trouvé, vérification croisée :
   - appelée ailleurs *dans* le ViewModel lui-même (helper interne légitime → faux positif, écarté) ;
   - présente ou non dans `upstream/main` (`AppleBoiy/StarHubTH`), pour distinguer un trou propre au fork d'un problème hérité.

## Résultat

**Aucune fonctionnalité upstream n'est absente du fork** sur `ModListView.swift` — comparaison exhaustive des libellés de boutons (`Label(vm.L(L10n...` / `Button(vm.L(L10n...`) entre upstream et le fork : ensembles identiques (le seul écart réel, l'icône engrenage de l'éditeur de config, était déjà connu et traité séparément).

**5 fonctions du ViewModel n'ont aucun appelant dans les vues, ni dans le fork ni dans upstream** — donc un problème hérité, pas une régression ou un oubli du fork :

| Fonction | Ligne (fork) | Statut |
|---|---|---|
| `launchGame()` | `StarHubTHViewModel.swift:1094` | Aucun bouton « Lancer le jeu » nulle part, fork ou upstream |
| `fetchSteamUser()` | — | Idem |
| `checkSmapiVersion()` | — | Idem |
| `setAvatar()` | — | Idem |
| `translatedStatus()` | — | Idem |

Probablement du code mort issu d'anciens refactors (fonctionnalité remplacée par un autre mécanisme sans suppression de l'ancien code). Non bloquant, non lié au travail en cours — à traiter comme un nettoyage séparé si souhaité un jour.

## Faux positifs écartés

Ces fonctions sont apparues initialement dans la recherche mais sont en réalité des helpers internes légitimes (appelés par d'autres méthodes du ViewModel, jamais censés être appelés directement depuis une vue) : `getTopLevelFolder`, `getParentFolderName`, `sortedNodes`, `buildNode`, `moveModFolder`, `getTopLevelMod`, `providedIds`, `getDependencies`, `startSmapiLogWatcher`, `loadProfiles`, `isCoveredByProfile`, `syncActiveProfileIds`, `slot`. `saveInventory` est également un faux positif : appelée via référence de fonction (`confirmedOrWarn(vm.saveInventory)`) plutôt qu'un appel direct, ce que la première passe de recherche ne détectait pas.
