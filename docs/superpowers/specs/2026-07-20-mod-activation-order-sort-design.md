# Tri par ordre d'activation — Conception

## Contexte

`ModListView` (StarHubTH/Views/ModListView.swift) affiche la liste des mods
installés, actuellement toujours triée par nom (`vm.mods` est trié
alphabétiquement — groupes d'abord, puis ordre alphabétique — dans
`StarHubTHViewModel.scanMods()`). Il n'existe aucun contrôle de tri dans
l'UI, et aucune notion d'« ordre d'activation » n'est suivie nulle part
dans l'app.

## Objectif

Ajouter un mode de tri alternatif dans la fenêtre des mods : trier par
ordre d'activation (le mod activé le plus récemment en premier), en plus
du tri par nom actuel.

## Fait technique confirmé

Qu'il s'agisse d'un mod seul ou d'un pack complet (groupe), l'activation
déplace toujours un seul dossier de premier niveau (`ModItem.folderName`)
entre `Mods/` et `Mods_disabled/` — que ce soit dans
`StarHubTHViewModel.toggleMod()` ou `applyProfileToFilesystem()`. Un
horodatage stocké par `folderName` fonctionne donc identiquement pour un
mod seul et pour un pack, sans logique d'agrégation par enfants à écrire.

## Conception

### 1. Stockage de l'horodatage d'activation

Nouvelle propriété dans `StarHubTHViewModel` :

```swift
@Published var modActivationTimestamps: [String: Date] = [:]
```

- Clé : `ModItem.folderName` (mod seul ou pack).
- Persistée dans UserDefaults (`Codable`, `[String: Date]` s'encode/décode
  nativement en JSON), sous une nouvelle clé
  `modActivationTimestampsKey = "modActivationTimestamps"`.
- Chargée à l'initialisation du ViewModel, comme `nexusCustomCategories`/
  `nexusCustomModIds`.

### 2. Enregistrement

Un horodatage `Date()` est posé sur `folderName` chaque fois qu'un dossier
passe de désactivé à activé — **jamais** à la désactivation (l'horodatage
représente la dernière activation, pas le dernier changement d'état) :

- `toggleMod(_:)` : pour chaque `folderName` de `foldersToToggle` qui
  passe effectivement à l'état activé (`targetState == true` et le move
  réussit) — couvre à la fois le mod ciblé directement et toute
  dépendance activée en cascade par le chain-toggle.
- `applyProfileToFilesystem(profile:)` : pour chaque mod du bloc
  « Enable mods in profile » qui passe de désactivé à activé.

Persisté immédiatement après chaque mise à jour (comme les autres maps
`nexusCustom*`).

### 3. Sélecteur de tri (UI)

Nouvel enum, à côté de `ModFilter` :

```swift
enum ModSortOrder: String, CaseIterable, Identifiable {
    case name, activationOrder
    var id: String { rawValue }
}
```

Nouvel état `@State private var selectedSort: ModSortOrder = .name` dans
`ModListView`.

Nouveau contrôle dans la barre du haut, à côté du `categoryPicker`
existant — un `Menu` du même style visuel (icône + libellé + chevron),
avec deux entrées : « Nom » et « Ordre d'activation ». Aucune option de
tri supplémentaire (YAGNI) — l'utilisateur ne demande que ces deux modes.

### 4. Application du tri

`filteredMods` (après les filtres de recherche et de catégorie existants,
avant la répartition par scope Activés/Désactivés/Problèmes et la
pagination) est trié selon `selectedSort` :

- `.name` : comportement actuel, inchangé (l'ordre de `vm.mods` est déjà
  alphabétique, donc aucun tri supplémentaire n'est nécessaire ici).
- `.activationOrder` : trie par
  `vm.modActivationTimestamps[mod.folderName]` décroissant (le plus
  récent en premier). Les mods sans horodatage enregistré (jamais
  basculés via l'app, ou installés avant cette fonctionnalité) sont
  placés après tous les mods horodatés, triés alphabétiquement entre eux.

Ce tri s'applique de façon cohérente quel que soit le scope actif
(Tous/Activés/Désactivés/Problèmes) : dans le scope « Désactivés » par
exemple, l'ordre reflète la dernière fois où chaque mod a été activé
avant d'être désactivé (ou l'absence d'historique).

Le tri choisi n'est **pas** réinitialisé automatiquement par les autres
contrôles (recherche, filtre de catégorie, changement de scope) — il
reste tel que l'utilisateur l'a explicitement choisi dans le nouveau menu,
jusqu'à ce qu'il le change lui-même.

## Hors périmètre

- Pas de reproduction de l'ordre de chargement réel de SMAPI (résolu par
  dépendances, pas par ordre de dossier) — hors scope, complexité
  disproportionnée pour ce besoin.
- Pas d'horodatage mis à jour à la désactivation.
- Pas d'agrégation par enfants pour les packs — inutile, voir le fait
  technique confirmé ci-dessus.
- Pas de nouvelle option de tri autre que Nom / Ordre d'activation.

## Tests / vérification

Pas de suite de tests automatisés pour cette vue (SwiftUI, vérification
manuelle). Vérification :
1. Compilation via `python3 build_app.py`.
2. Activer un mod jamais activé auparavant → il remonte en tête de liste
   en mode « Ordre d'activation ».
3. Activer un pack → le pack (et lui seul, pas ses enfants
   individuellement) remonte en tête.
4. Un mod jamais basculé via l'app apparaît après tous les mods
   horodatés, dans n'importe quel scope.
5. Basculer vers « Nom » restaure le tri alphabétique habituel.
