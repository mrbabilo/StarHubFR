# Audit — UltraSmooth 2.4.1 *(2026-10-01)*

Suite de [`audit-ultrasmooth-2.4.0.md`](audit-ultrasmooth-2.4.0.md). Delta
décompilé et comparé à la 2.4.0 du backup d'installation. Rien du mod n'est
repris.

| | |
|---|---|
| **Identité** | `palmhacker13.UltraSmooth` · 2.4.1 · Nexus 50971 · installé **en pause** (`.UltraSmooth`) |
| **DLL** | `ilspycmd` : 99 → 106 fichiers. 11 fichiers neufs, 2 namespaces retirés (`Experimental.Pathfinding`, `.Patches`), 13 modifiés |
| **Exécution sur le parc** | **aucune** : le journal SMAPI ne contient aucune ligne de la 2.4.1, et le `config.json` date du 2026-09-29 (pas une des 14 clés neuves) |
| **Surfaces** | réseau / processus / chargement de code / suppression de fichier : identiques (50 occurrences avant et après) |

## 1. `EnableParallelDayUpdate` — à couper avant toute réactivation

Réglage neuf, **actif par défaut** (`true`, et `ParallelDayUpdateMaxThreads`
= 0, soit un fil par cœur). Un préfixe Harmony sur `GameLocation.DayUpdate`
intercepte le premier appel de la nuit et lance `Parallel.ForEach` sur tous les
lieux de `Game1.locations` : `ResetCharacterDialogues()` puis `DayUpdate()` sur
des fils de travail. `Game1.random` est remplacé le temps du lot par un
`ThreadSafeRandom` (un verrou autour du `Random` d'origine). Après le lot,
chaque appel de `GameLocation.DayUpdate` du jour rend `false`.

### Prouvé par le code, à chaque nuit

La boucle vanilla (`Game1`, `IsMasterGame`) appelle `location.DayUpdate()` sur
chaque lieu. 31 sous-classes surchargent `DayUpdate` ; celles des lieux de
`Game1.locations` (dont `Farm`, `Town`, `Forest`, `Beach`, `Mountain`,
`Woods`, `IslandLocation`, `Desert`) appellent `base.DayUpdate()` **en
premier**, puis font leur propre travail. Le préfixe ne bloque que la base. Le
corps propre de ces sous-classes s'exécute donc **deux fois** : une fois dans
le lot parallèle, une fois dans la boucle vanilla. Les intérieurs de bâtiments
(`AnimalHouse`, `Cabin`, `SlimeHutch`) n'y sont pas : la base de leur lieu
parent les met à jour (`Building.dayUpdate`), et elle ne tourne qu'une fois.

Conséquences relevées dans le jeu décompilé (1.6, `Stardew Valley.dll` du parc) :

- `Town.DayUpdate` : `daysUntilCommunityUpgrade` décrémenté deux fois par
  jour. La rénovation de la maison de Pam arrive en deux fois moins de jours.
- `Forest.DayUpdate` : `netWorldState.VisitsUntilY1Guarantee` décrémenté deux
  fois. Valeur enregistrée dans la sauvegarde.
- `Beach`, `Forest` (printemps), `Farm` (ferme plage) : les tirages de
  cueillette et de débris s'exécutent deux fois.
- `Farm.DayUpdate` : le tirage des slimes qui s'échappent s'exécute deux fois.

Harmony exécute aussi les autres préfixes et les postfixes quand un préfixe
saute l'original. Tout autre mod qui patche `GameLocation.DayUpdate`
s'exécute donc aux deux passages, la première fois sur un fil de travail.
Sur le parc, 26 DLL chargent Harmony et nomment `DayUpdate`, dont 9 actives
(Cropgenics, ExtraAnimalConfig, ExtraMachineConfig, ItemExtensions,
JsonAssets, MerchantsBooks, MS-Books, MS-Offerings, SpaceCore). Ce sont des
**candidates** : le nom peut viser `Object.DayUpdate` ou une autre classe.

### Plausible, intermittent

`GameLocation.DayUpdate` n'est pas écrit pour s'exécuter en parallèle. La base
écrit dans des objets partagés : `Game1.player.team.returnedDonations` (une
`NetList`), `Game1.netWorldState.Builders`, `Game1.multiplayer`, et les caches
d'`ItemRegistry`. Les courses de données ne se produisent pas à chaque nuit.
L'ordre des tirages de `Game1.random` dépend en plus de l'ordonnancement des
fils : une même sauvegarde ne donne plus le même lendemain. Une exception
d'un lieu est seulement journalisée (`ParallelDayUpdate exception in …`), et
la fin de ce `DayUpdate` est perdue.

**Réglage** : `"EnableParallelDayUpdate": false` dans le `config.json` avant de
réactiver le mod. Sans la clé, SMAPI écrit le défaut `true` au lancement.

## 2. Les autres nouveautés

| Optimiseur | Défaut | Cibles | Ce qu'il fait — et le risque relevé |
|---|---|---|---|
| `SeasonPrewarmOptimizer` | `true` | aucun patch, `DayEnding` | La nuit du 28, `Task.Run` charge les textures de la saison suivante par `Game1.content.Load<Texture2D>` **hors du fil du jeu**, pendant l'enregistrement, et règle `GraphicsDevice.Textures[0]`. Il ne touche pas au sérialiseur (classe de risque différente du préchauffage SpaceCore). Le gestionnaire de contenu de SMAPI n'est pas fait pour un accès concurrent : plausible, une fois par saison |
| `AutomateHibernateOptimizer` | `true` | `MachineGroup.Tick` d'Automate | Hors du lieu courant, un groupe de machines ne tourne qu'une fois par tranche de 2 h de jeu. Exclus : les noms qui commencent par `Farm`, `Greenhouse`, `Cellar`, `Shed`. Un intérieur 1.6 s'appelle `<carte><GUID>` (`Building.cs`) : étables, coops et cabanes sont donc hibernées. **Lu dans le code, non mesuré** : la date est gardée **par lieu**, pas par groupe. Le premier groupe d'un lieu prend la tranche et les suivants sont sautés. Si Automate parcourt ses groupes dans un ordre stable (hypothèse non vérifiée dans `Automate.dll`), les groupes après le premier ne tournent jamais. Changement de gameplay, pas seulement de performance. Sans effet aujourd'hui : Automate est en pause sur le parc |
| `BatchSerializationOptimizer` | `true` | `SaveGame.getSaveEnumerator` (`MoveNext`), `SaveGameMenu` | Préalloue le `MemoryStream` de la sauvegarde (1,35 × le fichier, 8–128 Mo) et réduit la pause d'écran de fin (1 500 → 350 ms). Champs générés par le compilateur lus par réflexion : si un nom change, la fonction se coupe sans effet. Bénin |
| `MapMemoryOptimizer` | `true` (purge toutes les 2 h) | aucun patch, 5 événements | Retire des cartes et des feuilles de tuiles du cache de contenu par réflexion. Lieux de ferme exclus |
| `LazyTextureOptimizer` | `true` | `NPC.TryLoadPortraits`, `NPC.Portrait` (getter) | Portraits chargés à la demande, vidés chaque nuit |
| `SharedStructBufferOptimizer` | `true` | `Utility.getAdjacentTileLocationsArray`, `getSurroundingTileLocationsArray` | Tampons `[ThreadStatic]` réutilisés |
| `SmartScheduleEngine` | `true` | `GameLocation.updateCharacters` | PNJ immobiles hors écran mis à jour une fois par seconde |
| `NpcRouteCacheOptimizer` | `EnableRouteCache` (`true`) | `PathFindController.findPathForNPCSchedules` (2 surcharges) | Remplace `Experimental.Pathfinding`. Le patch est **toujours posé** ; il n'agit que si `EnableRouteCache` est vrai. Il ne dépend plus d'`EnableExperimentalFeatures` |

Le saut des lieux « dormants » (`IsDormantEmptyLocation`) existait déjà en
2.4.0 : `spawnObjects` vit dans la base de `DayUpdate`, donc un lieu vide de
tout objet et de tout terrain ne refait jamais sa cueillette.

## 3. Le catalogue des recouvrements (A5-T7)

Cibles Harmony relevées dans les appels `AccessTools` (`Type.méthode`) : 84 en
2.4.0, 93 en 2.4.1. Retirées : `FarmAnimal.behaviors`, `Monster.reloadSprite`.
Ajoutées : 11, dont `LightSource.Draw`, `GameLocation.drawLightGlows`,
`NPCController.update` et `NPC.Portrait`.

- **Stardropium 0.2.0-beta** (installé en pause) : les 9 méthodes communes et
  les 3 conditionnelles du catalogue sont toujours là. `passTimeForObjects` et
  `timeUpdate` restent posées seulement sous `EnableExperimentalFeatures`
  (`ExperimentalCoordinator.IsActive`). Une 13ᵉ méthode est
  neuve et commune aux deux : `LightSource.Draw`, chez UltraSmooth sous
  `EnableLightCulling` (défaut `true`).
- La ligne `PathFindController.findPathForNPCSchedules` est classée
  « conditionnelle à `EnableExperimentalFeatures` ». En 2.4.1, elle dépend
  d'`EnableRouteCache`. Avec la config par défaut, elle est donc active.
- **Radiance 2.2.3** : les 6 méthodes communes sont inchangées, aucune des 11
  nouvelles n'est commune.

`PerformanceOverlap.catalog` (mesuré sur 2.3.7) n'est pas modifié par ce
relevé : la condition par paire n'a qu'une option, et la 2.4.1 en demande deux.
