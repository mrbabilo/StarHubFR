# Mod List — Toolbar Rework & Config Access Design

**Date** : 2026-07-23
**Fichier principal concerné** : `StarHubTH/Views/ModListView.swift` (+ `ModItem.swift`, `StarHubTHViewModel.swift`, `L10n.swift`, `assets/en.json`, `assets/th.json`)

## Objectif

Trois demandes initiales, plus un ajustement découvert en cours de conception (accès à l'éditeur de config depuis la ligne du mod, alignant le fork sur upstream) :

1. Déplacer et renommer le bouton d'installation de mods.
2. Étendre le tri (icône fixe, nouvelles options : Z→A, Auteur, Version).
3. Ajouter un filtre "Avec configuration".
4. Ajouter un accès direct (icône) à l'éditeur de config sur chaque ligne de mod configurable, à la manière d'upstream.

## Décisions déjà validées (au fil des échanges)

- Le bouton de tri garde son libellé **dynamique** (affiche le nom de l'option active) — pas de libellé fixe "Trier".
- Son icône devient **fixe** (`arrow.up.arrow.down`), indépendante de la sélection ; chaque entrée du menu garde sa propre icône.
- Tri par version : **décroissant** par défaut (version la plus récente en premier), cohérent avec les tris "Date d'installation" et "Ordre d'activation" déjà décroissants.
- Filtre "Avec configuration" : **bouton/menu séparé**, visuellement aligné sur le bouton de tri — pas fondu dans le menu Catégorie, pas une simple case à cocher.
- Un **pack** (groupe de mods) est considéré "configurable" pour le filtre si lui-même OU au moins un de ses enfants a un `config.json` — cohérent avec le pattern déjà utilisé pour la recherche et le filtre "Problèmes" (`matchesSelfOrAnyChild`).
- Icône engrenage sur la ligne : **ajoutée en complément** de l'entrée "Code Editor" du clic droit existante (les deux coexistent), visible uniquement si `!mod.isGroup && mod.hasConfigFile` — reproduit exactement la logique d'upstream (`hasConfigJson`, vérifiée sur `ModListView.swift:537` d'upstream), mais via un champ précalculé plutôt qu'un `FileManager.fileExists` à chaque rendu.

## 1. Modèle de données

### `ModItem` (`StarHubTH/ModItem.swift`)
Nouveau champ :
```swift
public let hasConfigFile: Bool
```
Représente uniquement le `config.json` du dossier propre du mod — **pas** d'agrégation sur les enfants ici (l'agrégation pour les packs se fait au niveau du filtre, via `matchesSelfOrAnyChild`, pas dans le modèle).

### `scanMods()` (`StarHubTHViewModel.swift`)
Calculé dans la même passe que `installedFileDate` (même bloc, un seul `fm.fileExists` supplémentaire par mod — coût négligeable, la boucle touche déjà le système de fichiers pour chaque mod) :
```swift
let hasConfigFile = fm.fileExists(atPath: (path as NSString).appendingPathComponent("config.json"))
```

### Comparaison de version
Réutilise `NexusUpdateChecker.compare(_:_:) -> ComparisonResult`, déjà présent et testé (gère préfixe "v", suffixes pre-release, segments manquants). Pas de nouvelle logique de comparaison à écrire.

## 2. `ModSortOrder` (dans `ModListView.swift`)

```swift
enum ModSortOrder: String, CaseIterable, Identifiable {
    case name, nameDescending, activationOrder, installDate, author, version
    var id: String { rawValue }
}
```

Règles de tri à ajouter dans `filteredMods`'s `.sorted { ... }` :
- `.nameDescending` : inverse de `.name` (`lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending`).
- `.author` : `lhs.author.localizedCaseInsensitiveCompare(rhs.author) == .orderedAscending` (A→Z), avec repli sur le nom du mod en cas d'égalité (auteurs identiques) pour un ordre stable.
- `.version` : `NexusUpdateChecker.compare(lhs.version, rhs.version) == .orderedDescending` (plus récent en premier), repli sur le nom en cas d'égalité de version.

## 3. Bouton de tri (`sortPicker`)

- `Image(systemName: sortIcon)` → remplacé par une icône fixe `"arrow.up.arrow.down"` dans le label du bouton (le `sortIcon` calculé par cas devient inutile côté bouton, mais chaque item du menu garde son icône propre).
- Nouvelles entrées de menu, dans cet ordre (après les 3 existantes) :
  - "Nom (Z→A)" — icône `"textformat.size.larger"` (distincte de `"textformat"` utilisé pour Nom A→Z, tout en restant dans la même famille visuelle "texte").
  - "Auteur" — icône `"person"`.
  - "Version" — icône `"number"` (évite la confusion avec `"tag"`, déjà utilisé pour les catégories dans ce même fichier).
- Nouvelles clés `L10n.Mods` : `sortNameDescending`, `sortAuthor`, `sortVersion`. La clé existante `sortName` passe de "Name" à **"Name (A-Z)"** (EN) / ajustement TH correspondant, pour rester symétrique avec la nouvelle option Z→A.

| Clé | EN | TH (proposition) |
|---|---|---|
| `mods_sort_name` (existant, valeur modifiée) | Name (A-Z) | ชื่อ (ก-ฮ) |
| `mods_sort_name_descending` (nouveau) | Name (Z-A) | ชื่อ (ฮ-ก) |
| `mods_sort_author` (nouveau) | Author | ผู้สร้าง |
| `mods_sort_version` (nouveau) | Version | เวอร์ชัน |

## 4. Filtre "Avec configuration"

Nouvel état `@State private var configOnlyFilter: Bool = false` dans `ModListView`. Bouton toggle stylé comme `sortPicker` (fond arrondi, bordure fine) mais sans sous-menu — un simple `Button` qui bascule le booléen, avec un état visuel actif distinct (ex. fond teinté `Color.accentColor.opacity(0.15)` quand actif, comme les autres affordances actives de ce fichier).

Ajout dans la chaîne `.filter` de `filteredMods` :
```swift
.filter { mod in
    !configOnlyFilter || matchesSelfOrAnyChild(mod) { $0.hasConfigFile }
}
```

Nouvelles clés : `L10n.Mods.configFilterLabel` (EN "With Config", TH "มีการตั้งค่า") pour le libellé du bouton, et un `.help(...)` réutilisant ou complétant ce même texte.

## 5. Bouton "Install mods"

Déplacé de sa `HStack` dédiée (lignes ~257-268 actuelles) vers la fin de la ligne de filtres existante (après le `categoryPicker`), en conservant `.buttonStyle(.borderedProminent)` et l'icône `"plus.circle"`.

Clé existante `mod_install_button` (utilisée **uniquement** à cet endroit — sûr à modifier directement) :
- EN : "Install" → **"Install mods"**
- TH : "ติดตั้ง" → **"ติดตั้งม็อด"**

## 6. Icône engrenage sur la ligne de mod

Dans le groupe `// Actions (always visible)` de `ModListRow` (`ModListView.swift:806-...`), juste après le bouton dossier existant :
```swift
if !mod.isGroup && mod.hasConfigFile {
    Button {
        vm.editingModConfig = mod
    } label: {
        Image(systemName: "gearshape")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
    }
    .buttonStyle(PlainButtonStyle())
    .help(vm.L(L10n.Settings.configCodeEditor))
    .pointingHandCursor()
}
```
Réutilise la clé `L10n.Settings.configCodeEditor` déjà existante (déjà utilisée pour le libellé de l'entrée du menu contextuel "Code Editor") plutôt que d'en créer une nouvelle — même action, même texte, cohérent.

L'entrée existante du menu contextuel (clic droit → "Code Editor") **reste en place**, inchangée — les deux points d'accès coexistent.

## Hors périmètre

- Le nettoyage des 5 fonctions mortes du ViewModel (`launchGame`, `fetchSteamUser`, `checkSmapiVersion`, `setAvatar`, `translatedStatus`) — documenté séparément dans `docs/superpowers/audits/2026-07-23-unwired-viewmodel-functions.md`, sans lien avec ce travail.
- Toute modification de `ModConfigEditorView.swift` lui-même (déjà livré dans une session précédente) — ce design ne fait qu'ajouter un nouveau point d'entrée vers une vue existante.

## Tests

Aucune couverture Swift Testing automatisée n'existe pour `ModListView.swift` (hors du périmètre `StarHubTHCore` du `Package.swift`, comme tous les fichiers `Views/*.swift`). Validation par build (`python3 build_app.py`) + vérification manuelle en app, cohérent avec le reste de ce fichier.
