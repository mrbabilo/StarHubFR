# StardewOptimizer 3.0.3 — delta depuis 1.0.0 (2026-10-14)

**Conseil : garder StardewOptimizer en pause.** Si tu veux le réactiver,
remplace d'abord son `config.json` par celui de la 3.0.3, ou désactive
`AutomateThrottle` à la main. Le parc tourne aujourd'hui avec les réglages
agressifs de la 1.0.0. L'auteur a pourtant éteint ces modules par défaut en
3.0.3.

## Périmètre et preuves

Décompilation ILSpy de trois DLL du parc : 1.0.0 et 2.0.0 (sauvegardes
d'installation `2026-10-11_185735_3DCD3724-…` et `2026-10-14_005213_E5A99BA2-…`)
et 3.0.3 (`Mods/.StardewOptimizer 53663 1 2026-10-09T19-37Z arMRSFD62`). Code du
jeu relu dans `Stardew Valley.dll` du parc (`Furniture`). Fichiers livrés relus
dans les manifestes de fichiers Nexus (`modFiles`, API v2). Aucun changelog n'est
publié. Rien n'a été exécuté.

| | |
|---|---|
| Manifeste | `baiyu.StardewOptimizer` 3.0.3, `UpdateKeys` toujours vide ; description : « toutes les optimisations désactivées par défaut » |
| DLL 3.0.3 | 662 528 o, SHA-256 `cdf8330457753bafe937718b16e87e78cad96f46f8a20a6d213c7a869a1be1b3` |
| Code | 10 141 lignes décompilées en 1.0.0, 17 922 en 2.0.0, 29 359 en 3.0.3 ; 14 modules, puis 22 |
| Fichiers Nexus | 1.0.0 → 2.0.0 → 3.0.0 (archivé) → 3.0.1 → 3.0.3, en quatre jours |

## Sécurité

Le relevé de la 1.0.0 reste vrai :
- aucun réseau, aucun `Assembly.Load`, aucun `Process.Start`, aucune suppression ;
- `DllImport` limité à `psapi.dll`, gardé par `IsWindows()`.

Deux écritures seulement, toutes deux dans des fichiers du mod :
- `interop.json`, dans son propre dossier (`InterModRegistry`) ;
- un export des conflits vers un chemin choisi (`ConflictAuditor`, éteint par défaut).

## Le parc garde les réglages de la 1.0.0

En 3.0.3, le code n'active par défaut que `MenuLazyLoad` et
`FurnitureDrawThrottle`, plus trois services internes (`AssetEditAuditor`,
`Overlay`, `SceneAware`). L'archive 3.0.3 livre un `config.json` neuf de
5 335 octets.

Le `config.json` du parc est **identique octet pour octet** à celui de la 1.0.0
(SHA-256 `d38c4ba7…832d5`, comparé au manifeste de fichiers Nexus 186155). Il n'a
donc jamais été modifié par l'utilisateur. Pourtant, l'installation de la 2.0.0
puis celle de la 3.0.3 l'ont gardé. La règle de StarHubFR est de ne jamais
écraser un `config.json` (AGENTS.md §5.5). Résultat : le parc tourne avec les
défauts que l'auteur a abandonnés.
- **Actifs :** `MenuLazyLoad`, `LocationPreload`, `AutomateThrottle`,
  `MemoryStabilizer`, `ProcessTuning` (sans effet sur Mac), `AudioChangeCoalesce`.
- Les modules apparus depuis la 1.0.0 n'y figurent pas : ils prennent la valeur
  par défaut du code.

**Pour StarHubFR (piste, non numérotée).** Un `config.json` dont l'empreinte est
celle livrée par la version précédente ne porte aucun réglage de l'utilisateur.
Le remplacer par celui de la nouvelle version ne perd rien. Tout fichier modifié
resterait intouché, comme aujourd'hui. Les deux empreintes sont déjà à la portée
de l'app, par les manifestes de fichiers Nexus (§2.4 bis de `SOURCES.md`) et les
archives gardées (`NexusArchives/`).

## Ce qui change le jeu

### `AutomateThrottle` : Automate ne tourne que joueur immobile

Ce module est actif sur le parc (`OnlyProcessWhenIdle: true`,
`IdleSecondsThreshold: 8`). Ses préfixes sur `MachineManager` et `MachineGroup`
d'Automate sautent **tout** le cycle d'automatisation, sauf dans deux cas :
- le joueur n'a ni bougé ni appuyé sur une touche depuis 8 s (16 s sous pression
  mémoire) ;
- `ContextDetector.AllowsAggressiveOptimization` est faux, c'est-à-dire en
  combat, pêche, dialogue ou cinématique.

En jeu normal, les machines reliées aux coffres ne sont donc ni alimentées ni
vidées tant que le joueur se déplace. L'audit de la 1.0.0 parlait de « frein » ;
le code dit « arrêt hors immobilité ».

### 🟡 `FurnitureDrawThrottle` : la découpe à l'écran compte en mauvaise unité

Ce module est nouveau et **actif par défaut**. À chaque tick, il garde les
meubles « visibles », et son préfixe sur `Furniture.draw` saute tous les autres.
Pour décider qu'un meuble est visible, il multiplie `boundingBox` par 64. Or le
jeu stocke déjà `boundingBox` en pixels (`tileLocation × 64`, relu dans
`Furniture.cs`). Les coordonnées comparées à l'écran sont donc 64 fois trop
grandes :
- en général, aucun meuble n'est jugé visible. L'ensemble vide laisse tout
  dessiner, et le module ne fait rien ;
- si un meuble tombe dans l'écran à cause de ces coordonnées erronées (case
  `(0, 0)` d'un intérieur, ou case `(1, 1)` quand la caméra est vers la case
  `(64, 64)`), tous les autres meubles disparaissent.

Mesuré sur les sauvegardes du parc : 50 et 35 meubles posés, aucun en `(0, 0)`.
Le module y est inerte. Le défaut se lit dans le code, il n'est pas observé en
jeu.

### `MemoryStabilizer`

Sur le parc, ce module est actif avec `AutoCleanup: false` : pas de nettoyage
automatique, seulement aux touches F9 (doux) et Maj gauche + F9 (dur). Le
nettoyage dur ne joue qu'en menu (`HardCleanupMenuOnly: true`).

## Recouvrements (catalogue A5-T7)

La 3.0.3 ajoute ces cibles : `Debris.updateChunks`, `NPC.pathfindToNextScheduleLocation`,
`GameLocation.updateWater` et `drawWater`, `Furniture.draw`,
`TerrainFeature.tickUpdate`, `MapPage.drawMap` et les dessins de minicarte.
`Models/PerformanceOverlap.swift` est mis à jour :

| Paire | Méthodes communes |
|---|---|
| StardewOptimizer × UltraSmooth 2.4.17 | 8 : `Debris.updateChunks`, `Furniture.draw`, `GameLocation.DayUpdate`, `GameLocation.updateWater`, `GameMenu.changeTab`, `Monster.update`, `NPC.update`, `TemporaryAnimatedSprite.draw` |
| StardewOptimizer × Stardropium 0.2.9 | 2 : `Furniture.draw`, `NPC.update` — **devient une paire** |
| StardewOptimizer × Radiance 2.3.2 | 1 : `GameLocation.updateWater` — bruit, écarté |

`TerrainFeature.tickUpdate` (StardewOptimizer) et les `tickUpdate` de `HoeDirt`
ou `ResourceClump` (UltraSmooth) ne portent pas le même `Type.méthode` : ils ne
comptent pas, selon la règle du catalogue.
