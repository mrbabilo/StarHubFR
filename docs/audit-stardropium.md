# Audit — Stardropium *(2026-09-25)*

Mod de performances paru le jour même, signalé comme source à suivre, audité
pour décider quoi en tirer. **Aucun code de Stardropium ne tourne chez nous ;
ce document porte les conclusions.**

| | Stardropium |
|---|---|
| **Nexus** | [52803](https://www.nexusmods.com/stardewvalley/mods/52803) — catégorie « Visuals and Graphics », créé et mis à jour le 2026-09-25 |
| **Sources** | [ArshiaS1381/StardropiumMod](https://github.com/ArshiaS1381/StardropiumMod), 4 commits, dernier `bbdd0c0` |
| **Identité** | `Arshia1381.Stardropium` · **0.1.1-Beta** (manifeste et smapi.io ; la fiche Nexus dit encore 0.1.0-Beta) · Arshia1381 |
| **Dépendances** | GMCM **optionnel**, rien d'autre de déclaré |
| **UpdateKeys** | **aucune** — SMAPI ne signalera jamais de mise à jour ; notre vérificateur non plus sans identifiant Nexus saisi |
| **DLL** | 256 Ko, 46 fichiers décompilés ; sources 7 846 lignes, 36 modules |
| **Parc** | **déjà installé, en pause** (`Mods/.Stardropium/`), DLL identique à `bbdd0c0` (le module Content Patcher retiré par ce commit est absent de la décompilation) |
| **Axes recouverts** | D (performance), A5 (incompatibilités entre mods) |

*Méthode* : description lue par l'API Nexus v2 (GraphQL `legacyMods`, sans
clé — la page renvoie 403 à `WebFetch`), sources clonées, DLL du parc
décompilée par `ilspycmd` et comparée, puis UltraSmooth 2.3.6 et Stardew
Loading Optimizer 1.0.0 décompilés pour mesurer le recouvrement. Les chiffres
du parc viennent des 1 133 manifestes lus le jour même.

---

## 1. Ce qu'il fait

36 modules posés à `Entry`, chacun derrière une clé `Enable*` de
`config.json` (50 clés, défauts « sûrs », trois préréglages accessibles
seulement par des boutons GMCM : *Maximum Performance*, *Handheld / Steam
Deck*, *Recommended Safe Defaults*).

- **Rendu** : culling hors écran (meubles, animaux, arbres/herbe/cultures,
  vagues, compagnons, poissons), cache de la carte d'éclairage, lissage
  sous-pixel de la caméra.
- **Simulation** : lieux distants à 15 Hz, tick des 10 minutes qui saute les
  lieux vides, NPC hors écran animés moins souvent, cache des chemins de
  planning à 6 h.
- **Mémoire** : GC `SustainedLowLatency`, compactage du tas et rognage de la
  mémoire du process chaque matin (`malloc_zone_pressure_relief` sur macOS),
  bornage LRU du cache d'images de **SinZational Speedy Solutions**.
- **Sauvegarde** : tampons plus grands sur l'itérateur de sauvegarde du jeu,
  boucles du sérialiseur de SpaceCore raccourcies.
- **Mods tiers** : 16 modules patchent des **types internes** de 15 autres mods
  par leur nom (`AccessTools.TypeByName("ContentPatcher.Framework.PatchManager")`,
  `SpaceCore.Patches.SaveGamePatcher`, `FarmTypeManager.ModEntry+Generation`…),
  plus deux internes de SMAPI et un type généré par le compilateur
  (`StardewValley.SaveGame+<getSaveEnumerator>d__94`).
- **Diagnostic** : commandes `perf_status`, `perf_memory`, `perf_trim`.

**Contrôle de sécurité** : aucun accès réseau, aucun `Process`, aucun
chargement de code. Les `DllImport` sont les appels de rognage mémoire de
chaque OS (`psapi`, `kernel32`, `libSystem.dylib`, `libc`). Bénin.

## 2. Constats

1. **7 méthodes patchées en commun avec UltraSmooth**, actif sur le parc :
   `HoeDirt.draw`, `Grass.draw`, `Tree.draw`, `Bush.draw`, `FruitTree.draw`
   (culling des deux côtés), `Game1.getTimeOfDayString` (deux préfixes qui
   rendent une chaîne mémorisée — le premier qui court-circuite gagne, en
   silence), `NPC.update`. Les deux règlent en plus le **tampon des sockets
   du multijoueur** (`CoopSocketBufferSizeKB` / `CoopSocketBufferSizeKb`).
   Avec Stardew Loading Optimizer : `GameLocation.loadMap` (sonde de timing
   chez SLO, sans conflit). Relevé grossier (`typeof(...)` + nom de méthode
   dans le C# décompilé), confirmé à la main pour le culling, l'horloge et
   les sockets.
2. **Couplage de versions non déclaré.** Le manifeste ne déclare que GMCM,
   alors que 16 modules dépendent de la forme interne d'autres mods. La
   description exige « the newest versions of all your installed mods ». Un
   **type** introuvable fait sauter le module sans rien journaliser (garde
   `if (type != null)`) ; une **méthode** introuvable donne un `WARN`. Le mod
   se dégrade donc en partie en silence à la mise à jour d'un autre. Sur le parc, les cibles **actives** sont Content Patcher, SpaceCore,
   Alternative Textures, Custom Companions, Farm Type Manager, UI Info Suite 2
   Alt., Ridgeside Village et Speedy Solutions ; Dynamic Reflections, NPC Map
   Locations et DaLion sont en pause ; Cloudy Skies, Help Wanted, Movement
   Overhaul et Better Game Menu sont absents. Le module « Visible Fish » vise
   `showFishInWater.*` : le `ZeroXPatch.VisibleFishAndShadows` du parc est un
   autre mod, le module n'y fait rien.
3. **Il empêche Farm Type Manager d'enregistrer son état.** Le module FTM
   (actif par défaut) pose un préfixe sur `ContentPack.WriteJsonFile<InternalSaveData>`
   de SMAPI et **saute l'écriture** de `data/<partie>_SaveData.save` dès que
   `SavedObjects` est vide. Or FTM range dans ce même fichier
   `WeatherForYesterday`, `LNOSCounter` (compteurs des apparitions limitées)
   et `ExistingObjectLocations` (vérifié dans la DLL FTM 1.26.1 du parc,
   écritures en fin de journée). Un jour sans objet sauvegardé laisse donc
   sur le disque l'état **de la veille** : compteurs et objets déjà ramassés
   relus au chargement suivant. Il saute aussi la réécriture de
   `content.json` de chaque pack, que FTM fait après `ValidateFarmData`.
   Packs concernés sur le parc : ceux de Ridgeside Village (`Rafseazz.RSVFTM`)
   et tout pack FTM actif. Défaut du mod, à signaler à son auteur.
4. **Chargement d'assets hors du fil principal.** `EnablePreWarmDataLoader`
   (actif par défaut) appelle `Game1.content.Load<object>` sur huit
   `Data/*` depuis un `Parallel.ForEach` en tâche de fond, exceptions avalées.
   Le contenu SMAPI n'est pas prévu pour ça, et chaque chargement déclenche les
   éditions de Content Patcher hors du fil principal. Risque d'erreurs
   intermittentes, **non constaté** — à mesurer avant d'en faire un signal.
5. **Bêta instable par construction** : le premier correctif, le jour même,
   retire un module entier (« unsafe Content Patcher token update
   suppression », qui cassait l'évaluation des conditions). Deux modules
   touchent le chemin de sauvegarde.
6. **Journal exploitable** : chaque matin, une ligne `INFO`
   `[Morning Memory Optimizer (Background)] RAM: <a> MB -> <b> MB (Managed
   Heap: <c> MB -> <d> MB, <n> cached textures purged/bounded).` — une courbe
   mémoire **par jour de jeu**, sans commande. Au démarrage, `INFO`
   « Detected low-memory / unified memory device (<= 8GB RAM) » quand il
   bascule seul en profil basse mémoire. `perf_memory` imprime un bloc
   structuré (RAM, tas, GC, caches SinZ et Stardropium, configuration).
7. **Config sans libellés** : aucun `i18n/`, libellés GMCM en anglais en dur
   (avec émojis). Notre éditeur de config affichera les 50 clés brutes.
8. **La description promet plus que le code** : « reads manifests in
   parallel » est en fait un cache d'images posé sur
   `ModContentManager.LoadRawImageData` de SMAPI (délégué à Speedy Solutions
   quand il est présent) plus le pré-chargement du constat 4. Les mods sont
   déjà chargés quand un mod reçoit `Entry`.

## 3. Ce que StarHubFR peut en tirer

Inscrits à la ROADMAP le 2026-09-25 : idée 1 → **A5-T7**, idée 2 → **A5-T6**
(mesurée sur tout le parc : 19 mods actifs citent un type interne d'un autre
mod ; les UniqueID cités, eux, sont des intégrations optionnelles — piste
écartée), idée 3 → **D2-T5**. L'idée 4 **existe déjà** : la fiche dit « Pas de
suivi des mises à jour : aucune page Nexus rattachée » et propose de relier le
mod à sa fiche Nexus.

1. **Signal « mods de performance qui se marchent dessus »** (axe A5, nouvelle
   source de signal, niveau DLL) : lister les cibles Harmony d'un mod par
   lecture statique de sa DLL et signaler deux mods **actifs** qui patchent
   la même méthode. Cas mesuré : Stardropium × UltraSmooth, 7 méthodes. Coût
   élevé (lire l'IL ou les chaînes de métadonnées sans .NET) ; première étape
   moins chère : une liste connue des mods de performance qui se recouvrent,
   comme la liste de compatibilité de smapi.io.
2. **Dépendances implicites** (axe A5 ou A1) : les chaînes
   `TypeByName("<Espace>.…")` d'une DLL désignent les mods dont elle dépend
   sans le déclarer. Rapprochées des `EntryDll` du parc, elles donneraient
   « Stardropium touche 8 de vos mods actifs » et, à la mise à jour de l'un
   d'eux, « Stardropium peut perdre un module en silence ».
3. **Source de télémétrie D2** : la ligne du matin (constat 6) se parse comme
   `[OPTIMIZER CONFIG]` de SLO (D2-T1) et donnerait la courbe mémoire par
   jour de jeu dans la vue Performance (D2-T3). Seulement si l'auteur active
   le mod : il est en pause aujourd'hui.
4. **Mod sans UpdateKeys** : troisième cas après SaveSaver. Notre fiche
   pourrait dire « ce mod ne déclare pas où chercher ses mises à jour » et
   proposer de saisir l'identifiant Nexus.

**Pour le parc, sans code** : garder Stardropium en pause tant
qu'UltraSmooth est actif. Pour l'essayer, couper au moins
`EnableVegetationCulling`, `EnableTimeStringMemoization`,
`EnableNPCFrustumThrottling`, `EnableCoopNetworkOptimization` (recouvrements
du constat 1), `EnableFTMOptimization` (constat 3) et
`EnablePreWarmDataLoader` (constat 4), puis comparer deux sessions avec
Profiler (D1).

## 4. Delta 0.1.1 → 0.1.3 *(2026-09-26)*

Installé sur le parc (toujours en pause). Décompilé contre la DLL 0.1.1
gardée dans `Backups/ModInstalls` ; aucune nouvelle référence réseau,
process ou chargement d'assembly (le seul `Process` reste la lecture mémoire
de `LiveDiagnosticsModule`, déjà là en 0.1.1). 37 modules : deux ajoutés,
un retiré.

- **Retiré** : `VisibleFishOptimizationModule` — le mod Visible Fish le fait
  lui-même. Ses deux clés disparaissent du `config.json`. Il patchait trois
  types internes de Visible Fish (`showFishInWater.*`) : 15 modules touchent
  désormais l'intérieur d'autres mods, contre 16.
- **`TMXTilePropertyOptimizationModule`**, activé par défaut : préfixes sur
  `TMXTile.TMXExtensions.SetRotationValue` et `SetFlip` qui sautent l'écriture
  quand la valeur vaut 0, plus un balayage à `SaveLoaded` qui retire des
  cartes du monde les `@Rotation`/`@Flip` valant `"0"`. Cas limite : une
  tuile déjà tournée qu'on remet à 0 garde son ancienne valeur. Personne
  d'autre sur le parc ne patche ces méthodes (SLO appelle seulement
  `TMXExtensions.SetupImageLayer`).
- **`ItemQueryOptimizationModule`**, activé par défaut : préfixe sur
  `ItemQueryResolver.TryResolve` qui remplace le résolveur du jeu pour les
  requêtes `ALL_ITEMS` (1 259 lignes décompilées) et rend la main au jeu
  quand il ne sait pas. 51 DLL du parc référencent `ItemQueryResolver` : un
  écart de résultat se verrait dans les boutiques, machines et Automate.
- **API publique** `IStardropiumApi` (index d'objets et requêtes par tag).

Conclusion pour le parc inchangée : pause tant qu'UltraSmooth est actif. Pour
l'essayer, ajouter `EnableItemQueryOptimization` aux clés à couper d'abord,
le temps de vérifier les boutiques.
