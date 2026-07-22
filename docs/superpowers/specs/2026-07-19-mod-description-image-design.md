# Description + image de mod (Nexus) — Conception

## Contexte

L'app récupère déjà, pour chaque mod ayant un id Nexus effectif (manifeste ou
override manuel), la version la plus récente et l'id de catégorie via
`NexusUpdateChecker.fetchModInfo` (`NexusUpdateChecker.swift:405-457`), qui
appelle `GET /v1/games/{game}/mods/{id}.json`. Cette réponse JSON contient déjà
tous les champs nécessaires ; il ne s'agit que d'en extraire deux de plus,
sans requête réseau supplémentaire.

Champs confirmés via le SDK officiel Node.js de Nexus Mods (type `IModInfo`,
`node-nexus-api`) :
- `summary` (string, optionnel) — description courte, texte brut.
- `picture_url` (string, optionnel) — URL de la capture d'écran principale du
  mod.
- `description` (string, optionnel) — texte long en BBCode. **Hors scope** :
  décision utilisateur de n'utiliser que `summary`, plus simple à afficher
  sans parseur BBCode.

Objectif : récupérer ces deux champs lors des fetch déjà déclenchés
aujourd'hui (check groupé "Vérifier les mises à jour" + fetch à la demande
depuis le popover d'un mod), les mettre en cache persistant comme la
catégorie, et les afficher dans le popover d'infos du mod.

## Conception

### 1. `NexusUpdateChecker.swift` — extraction et cache

Nouveau struct, à côté de `ModUpdate` :

```swift
struct NexusModExtra: Codable, Equatable {
    let summary: String
    let pictureUrl: String
}
```

`fetchModInfo` (privé) extrait `summary` et `picture_url` du dictionnaire
JSON déjà décodé, avec défaut `""` si absent ou de type inattendu (les deux
champs sont optionnels côté Nexus). Le type de retour privé `FetchResult`
gagne un cas `success(version:categoryId:extra:)` où `extra: NexusModExtra`
remplace les deux valeurs séparées.

Cache persistant : nouvelle clé UserDefaults `nexusCachedExtrasKey`, avec
`loadCachedExtras()/saveCachedExtras()` privés et un accesseur public
`cachedExtras() -> [String: NexusModExtra]`, symétriques à
`cachedCategories()`. Le verrou existant `categoryCacheLock` est renommé
`metadataCacheLock` (son usage réel couvre déjà toutes les mutations de
cache métadonnées faites dans les mêmes sections critiques) et protège
désormais aussi les mutations du cache d'extras.

`check()` (scan groupé) : accumule un `[String: NexusModExtra]` dans la même
boucle concurrente qui accumule déjà `categories`, le fusionne avec le cache
existant et le persiste dans la même section critique. `CheckResult.success`
gagne un paramètre `extras: [String: NexusModExtra]`.

`fetchSingleMod()` (fetch à la demande) : persiste l'extra retourné (sous le
même verrou) et le transmet via `SingleFetchResult`, qui gagne un cas
`success(version:categoryId:extra:)` remplaçant l'ancien
`success(version:categoryId:)`.

`clearApiKey()` : supprime aussi `nexusCachedExtrasKey` (comme les autres
clés de cache déjà nettoyées).

### 2. `StarHubTHViewModel.swift` — état publié + résolution

Nouveau `@Published var nexusModExtras: [String: NexusUpdateChecker.NexusModExtra] = [:]`,
seedé depuis `NexusUpdateChecker.shared.cachedExtras()` à l'init, à côté du
seed existant de `nexusCategories`.

- `clearNexusApiKey()` : réinitialise `nexusModExtras = [:]`.
- `checkNexusUpdates(...)` : dans le cas `.success`, fusionne
  `result.extras` dans `nexusModExtras` (même logique de merge que pour les
  catégories — ne jamais effacer une entrée existante lors d'un run
  partiel).
- `fetchMetadata(forNexusModId:)` : cache l'extra retourné dans
  `nexusModExtras[modId]` avant d'appeler `completion`, comme la catégorie
  aujourd'hui.

Nouvelle méthode, à côté de `nexusLink(for:)` :

```swift
func modExtra(for mod: ModItem) -> NexusUpdateChecker.NexusModExtra? {
    let id = effectiveNexusModId(for: mod)
    if !id.isEmpty, let extra = nexusModExtras[id] { return extra }
    if mod.isGroup, let children = mod.children {
        for c in children {
            if let extra = modExtra(for: c) { return extra }
        }
    }
    return nil
}
```

Un pack sans données propres retombe sur le premier enfant qui en a — même
convention que `nexusLink(for:)`.

### 3. `ModListView.swift` — `ModDetailsPopover`

Nouvelle section `previewSection`, insérée en premier dans le `body` du
popover (avant `categorySection`), **rendue seulement si**
`vm.modExtra(for: mod)` existe et que l'image ou le résumé n'est pas vide :

- Image : `AsyncImage(url: URL(string: extra.pictureUrl))`, hauteur fixe
  ~100pt, `.scaledToFill()` + `.clipped()` + coins arrondis (cohérent avec le
  style du popover). En cas d'URL vide/invalide ou d'échec de chargement,
  rien n'est affiché à la place (pas de placeholder visuel qui alourdirait
  l'UI) — seul le texte du résumé s'affiche le cas échéant.
- Résumé : `Text(extra.summary)`, taille de police cohérente avec le reste
  du popover (`size: 11`, `.foregroundColor(.secondary)`),
  `.lineLimit(4)` pour ne pas faire déborder le popover (hauteur max déjà
  fixée à 380pt).

Pas de titre de section (`.headline`) pour cette partie — elle se comporte
comme un en-tête visuel du popover plutôt qu'une section nommée comme
"Catégorie" ou "Nexus".

Aucune nouvelle requête réseau n'est déclenchée par le popover lui-même : il
ne fait qu'afficher ce qui a déjà été mis en cache par un check groupé ou un
fetch à la demande antérieur (cohérent avec `nexus_manual_check_only`).

## Hors périmètre

- Le champ `description` (BBCode long) n'est pas utilisé.
- Aucune vignette dans les lignes de la liste de mods — uniquement dans le
  popover d'infos.
- Aucun téléchargement/cache disque manuel de l'image — `AsyncImage`
  s'appuie sur le cache HTTP standard d'`URLSession`.
- Aucun nouveau déclencheur de fetch réseau (pas de fetch lazy à l'ouverture
  du popover).

## Tests / vérification

Pas de suite de tests automatisés (SwiftUI, vérification manuelle).
Vérification :
1. Compilation via `python3 build_app.py`.
2. Vérification manuelle : lancer un check Nexus (ou saisir un id Nexus dans
   le popover d'un mod) et confirmer que l'image + le résumé apparaissent
   dans le popover pour un mod qui en dispose sur Nexus ; confirmer qu'aucune
   section vide ne s'affiche pour un mod sans id Nexus ou dont les champs
   Nexus sont vides.
