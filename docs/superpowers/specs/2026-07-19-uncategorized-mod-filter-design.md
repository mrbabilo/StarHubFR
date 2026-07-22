# Filtre "Sans catégorie" dans ModListView

## Contexte

`ModListView` (StarHubTH/Views/ModListView.swift) propose déjà deux filtres :
un filtre de portée (Tous / Activés / Désactivés / Problèmes, segmented picker)
et un filtre de catégorie (menu déroulant listant les catégories Nexus
présentes parmi les mods installés, via `selectedCategory: NexusCategory?`).

Il n'existe aucun moyen de repérer rapidement les mods qui n'ont pas de
catégorie assignée (ni catégorie API Nexus, ni override manuel).

## Objectif

Ajouter une entrée dans le menu déroulant de catégorie existant permettant
d'afficher uniquement les mods sans catégorie assignée.

## Conception

### État

Remplacer `selectedCategory: NexusCategory?` par :

```swift
enum CategoryScope: Equatable {
    case all
    case category(NexusCategory)
    case uncategorized
}
```

Un enum à 3 cas plutôt qu'un booléen séparé, pour garantir l'exclusivité
mutuelle par construction (impossible d'avoir à la fois une catégorie
sélectionnée et le filtre "sans catégorie" actif).

### Filtrage (`filteredMods`)

- `.all` : comportement inchangé (aucun filtre de catégorie).
- `.category(cat)` : comportement inchangé (pack correspond si un enfant
  correspond, mod seul correspond si sa catégorie effective correspond).
- `.uncategorized` :
  - Mod seul : retenu si `vm.category(for: mod) == nil`.
  - Pack (groupe) : retenu seulement si **tous** ses enfants sont sans
    catégorie (`children.allSatisfy { vm.category(for: $0) == nil }`,
    et `children` non vide). Décision utilisateur : plus strict que la
    correspondance "au moins un enfant" utilisée pour `.category`, car on
    ne veut pas signaler un pack comme "sans catégorie" s'il contient déjà
    des mods catégorisés.

### Comptage et visibilité dans le menu

Nouvelle propriété calculée :

```swift
private var uncategorizedCount: Int {
    vm.mods.filter { mod in
        if mod.isGroup, let children = mod.children {
            return !children.isEmpty && children.allSatisfy { vm.category(for: $0) == nil }
        }
        return vm.category(for: mod) == nil
    }.count
}
```

Compte les entrées de premier niveau (mods seuls + packs, un pack = 1),
cohérent avec ce qui apparaîtra effectivement comme lignes dans la liste
filtrée — différent du comptage par enfant utilisé par
`availableCategories`, mais adapté ici car la sémantique de correspondance
diffère (tous les enfants vs un seul).

L'entrée "Sans catégorie (N)" n'apparaît dans le menu **que si
`uncategorizedCount > 0`** (comme les catégories Nexus dans
`availableCategories`, qui n'apparaissent que si elles sont représentées).

### UI du menu et du bouton

- Nouvelle entrée dans le `Menu`, juste après "Toutes catégories" (`nil`)
  et avant le `Divider()` qui précède la liste des catégories Nexus.
- Le bouton "Effacer le filtre" (`categoryFilterClear`) reste affiché dès
  que `selectedCategory != .all`.
- Label du bouton principal quand `.uncategorized` est sélectionné : icône
  neutre (`circle.dashed` ou équivalent) + texte localisé, même style que
  l'affichage d'une catégorie sélectionnée (mais sans couleur de catégorie).
- Condition de désactivation du picker mise à jour :
  `.disabled(availableCategories.isEmpty && uncategorizedCount == 0)`.
  Le hint (`categoryFilterEmptyHint` / `categoryFilterHint`) suit la même
  condition.

### Localisation

Nouvelle clé, ajoutée à `assets/en.json` et `assets/th.json`, suivant le
pattern existant (`mods_category_filter_*`) :

- `mods_category_filter_uncategorized`
  - en : "No Category"
  - th : traduction correspondante

Référencée dans `L10n.swift` sous `Mods.categoryFilterUncategorized`.
Les fichiers `.strings` sont régénérés automatiquement par `build_app.py`
(pas d'édition manuelle nécessaire des `.lproj/*.strings`).

## Hors périmètre

- Pas de changement au filtre de portée segmenté (Tous/Activés/Désactivés/
  Problèmes) — le nouveau filtre reste dans le menu de catégorie.
- Pas de persistance du choix de filtre entre sessions (comportement actuel
  de `selectedCategory`, non persisté).
- Pas de changement à `availableCategories` ni à son comptage par enfant.

## Tests / vérification

Pas de suite de tests automatisés pour cette vue (SwiftUI, testée
manuellement). Vérification :
1. Compilation via `python3 build_app.py`.
2. Vérification manuelle : sélectionner "Sans catégorie" affiche uniquement
   les mods seuls sans catégorie et les packs entièrement non catégorisés ;
   le compteur correspond au nombre de lignes affichées ; l'option
   disparaît du menu si tous les mods ont une catégorie.
