# UltraSmooth 2.6.2 et Stardropium 0.3.0 — deltas (2026-10-19)

**Conseil : rien ne presse de réactiver l'un ou l'autre ; les deux restent en
pause sur le parc.** Si UltraSmooth repart, garder `EnableSpaceCorePrewarm` à
`false` — la 2.6.1 l'avait remis à `true` par défaut, la 2.6.2 l'a rendu à
`false`, et le `config.json` du parc porte un `false` explicite qui l'a protégé
des deux côtés. Le conseil de l'audit 2.4.17 tient toujours : désactiver
`EnableLocationSpatialIndexEngine`, dont le code n'a pas bougé. Stardropium 0.3.0
ne change rien de ce que l'app lit chez lui.

Le relevé du catalogue des recouvrements (A5-T7) a été refait sur les quatre mods
qui changent de version : il manquait **cinq méthodes** à la paire Stardropium ×
UltraSmooth, dont deux sur l'écriture de la partie, et **six** à la paire Radiance
× UltraSmooth.

## Périmètre et preuves

Comparaison ILSpy (`ilspycmd`, scratchpad, rien exécuté) des DLL locales :

- UltraSmooth **2.5.0** (sauvegarde d'installation `2026-10-17_134538_0ED69DCB-…`)
  contre **2.6.1** (`2026-10-18_221644_DADE9E58-…`) et **2.6.2**, installée dans
  `Mods/.UltraSmooth` ;
- Stardropium **0.2.9-alpha** (`2026-10-19_162110_29854F73-…`) contre **0.3.0**,
  installée dans `Mods/.Stardropium` ;
- Radiance **2.3.4** (`Mods/.SDV-Radiance`) et StardewOptimizer 3.0.3, pour les
  paires qui contiennent UltraSmooth ;
- `Stardew Valley.dll` du parc pour savoir quels types déclarent les méthodes
  visées par les balayages dynamiques (`Critter`, `Bat`, `Cloud`, `Junimo`) ;
  `Automate.dll` pour `MachineGroup`.

| Binaire | SHA-256 |
|---|---|
| UltraSmooth 2.5.0 | `427ad35bb78811f8905504f72c3fe058c9c5cac3fadbb676d01f6e72f1018076` |
| UltraSmooth 2.6.1 | `f30945fe299a83a499e816da931b9bba861770e15b71534b1cbd9ffb1152178b` |
| UltraSmooth 2.6.2 | `1ddc497e66a6a5c578307a9f8d07dd9982b7cd4a72348b3a6bece08836f29ebc` |
| Stardropium 0.2.9-alpha | `95fd30e929e0d858bd9748f615699aa50e5e1acb90a585660a014b3100740d3a` |
| Stardropium 0.3.0 | `feb7111e6867742e38137b2299706d61f1b82df1bd5f93f4dcfef949a76858e2` |
| Radiance 2.3.4 | `2f64640361de8e639d6f86f78b57dd2227b1b53b424744f65115450edae8efaa` |

Deux trous dans la chaîne, à garder en tête :

- **la 2.4.17 n'est plus nulle part** (ni sur le parc ni dans les sauvegardes
  gardées). La 2.5.0, annoncée « à décompiler » au relevé du 2026-10-15, n'a donc
  pas pu être comparée à sa devancière : ce qu'elle apporte est lu dans son état
  final, pas en diff ;
- **la 2.6.3, publiée sur Nexus, n'est pas sur le parc** (le téléchargement par
  l'API rend 403 sans compte Premium). Elle n'est connue que par son journal :
  retour du mode « 60 FPS (Enhanced) », correctif de foule aux festivals. Le
  catalogue porte donc 2.6.2, et l'écran demandera une remesure le jour où la
  2.6.3 sera installée.

## UltraSmooth 2.5.0 → 2.6.2

18 fichiers changés, 10 nouveaux, un retiré (`HorseCornerAssist`) ; 40 441 →
43 183 lignes décompilées ; appels `harmony.Patch` : 192 → 208 (2.6.1) → 206. La
2.6.2 retire deux préfixes de `NpcPathfindingLodOptimizer` (`NPC.update`,
`Character.MovePosition`) : c'est le « retour au déplacement vanilla » annoncé
pour les PNJ bloqués. `NPC.update` reste patchée ailleurs (`HighFpsPacingEngine`).

### Sauvegarde : le piège SpaceCore a enfin un correctif, et a failli revenir

**Le correctif.** `TurboLoadEngine` pose désormais un postfix sur
`SpaceCore.Api.RegisterSerializerType`. Chaque fois qu'un mod enregistre un type
auprès de SpaceCore, il remet à zéro le cache de sérialiseurs de SpaceCore
(`InitializedSerializers = false`, `serializersAlreadyDone` vidé), qui sera
reconstruit à la prochaine sauvegarde. C'est exactement la course qui cassait
l'enregistrement du parc le 2026-09-26 (un type enregistré une seconde après le
préchauffage, absent pour toute la session). Le postfix ne dépend d'aucune
option. La garde PolyamorySweet, qui n'existait que pour ce bogue, disparaît.

**Le retour manqué.** Dans la 2.6.1, `EnableSpaceCorePrewarm` vaut **`true` par
défaut** ; la 2.6.2 le remet à `false`. Une installation neuve de la 2.6.1 sans
`config.json` relançait donc le préchauffage. Le parc n'a rien risqué : son
`config.json` (écrit le 2026-10-14 par la 2.4.17) porte `false` en clair, et la
2.6.1 n'y a jamais tourné.

**Ce qui reste.** Le préchauffage lui-même n'a pas changé : dans un
`Task.Run`, il appelle `InitializeSerializers` de SpaceCore si le drapeau est
faux. Si un mod enregistre un type pendant que ce fil construit les
sérialiseurs, l'invalidation peut passer avant la fin de la construction, qui
remet ensuite le drapeau à `true` sans le nouveau type. C'est une déduction,
tirée du code d'UltraSmooth et du mécanisme relevé le 2026-09-26 ; le code de
SpaceCore n'a pas été relu cette fois. La fenêtre est étroite, mais rien ne la
ferme. **La clé reste interdite** sur ce parc, d'autant que ce va-et-vient de
valeur par défaut montre qu'on ne peut pas compter dessus.

### Deux mods sur le même chemin d'écriture

`BatchSerializationOptimizer` (actif par défaut, `EnableBatchSerialization`)
préfixe le `MoveNext` de l'itérateur `SaveGame.getSaveEnumerator` : à l'état 2,
il agrandit la capacité du `MemoryStream` de sauvegarde selon une estimation de la
taille. Stardropium (`EnableSaveStreamOptimization`, actif par défaut) transpile
le même `MoveNext` pour remplacer ce `new MemoryStream(1024)` par un flux
réutilisé d'un jour à l'autre. Les deux s'empilent sans se contredire : UltraSmooth
agrandit le flux de Stardropium, qui garde sa capacité les jours suivants. Aucun
des deux ne réécrit les octets. Ni l'un ni l'autre ne tient compte de l'autre
(aucune mention croisée dans les deux DLL).

La traversée SpaceCore partagée (`SaveGamePatcher.FindAndRemoveModNodes`,
remplacée par les deux mods, relevée à l'audit 2.4.9) est inchangée.

### Le `GameMenu` fantôme de la 2.5.0

`MenuPrewarmer` construit un `new GameMenu(false)` une fois la partie chargée, sur
le fil du jeu, puis le jette : il compile à l'avance les chemins de dessin de
l'inventaire. Il ne touche à aucun sérialiseur et n'écrit rien. Effet de bord à
connaître : les postfix des autres mods sur le constructeur de `GameMenu` tournent
une fois sur ce menu jamais affiché. Actif par défaut (`EnableVramTextureStreamer`).
Inchangé de 2.5.0 à 2.6.2.

### D2-T6 : les deux chemins sont intacts

- `DayTransitionOptimizer.IsDormantEmptyLocation` : mêmes exclusions qu'en 2.4.10.
  `FarmCave` n'y figure toujours pas, et le chemin séquentiel saute toujours
  `DayUpdate` d'un lieu vide.
- `QueryCacheManager` : la clé de cache garde `ItemId` seul pour l'objet cible et
  l'objet d'entrée ; les contournements `random != null` et `RANDOM` restent.

Le protocole de [`verif-d2t6-ultrasmooth.md`](verif-d2t6-ultrasmooth.md) vaut
tel quel pour la 2.6.2.

### L'index spatial de la 2.4.17

`LocationSpatialIndexEngine` est identique octet pour octet à la 2.5.0 et préfixe
toujours `GameLocation.getObjectAtTile` sans regarder les meubles. Le
`config.json` du parc le garde à `true`. Le conseil de
[`audit-ultrasmooth-2.4.17.md`](audit-ultrasmooth-2.4.17.md) ne change pas.

### Configuration

Le `config.json` du parc a 105 clés ; la 2.6.2 en déclare 133. Les clés absentes
prennent la valeur par défaut du code :

- **neuves et actives par défaut :** `EnableFarmTypeManagerOptimizer` (index des
  cases de Farm Type Manager, actif sur ce parc puisque FTM y est installé) et
  `EnableExpandedPreconditionsOptimizer` ;
- **neuves et éteintes par défaut :** tampon d'actions, zone morte circulaire de
  la manette, porte de l'étable, limiteurs de chiffres de dégâts et de débris
  d'herbe, plafond de fréquence hors focus, `FastMailOpening` ;
- **passées de `true` à `false` :** `EnableFastSleepTransition`,
  `EnableSmartMagnetFilter`, `EnableFastChestStash`, `EnableSmartToolGridSnap`.
  Aucune n'est dans le `config.json` du parc : elles y sont donc éteintes, comme
  le veut désormais l'auteur ;
- **retirée :** `EnableHorseCornerAssist` (et son réglage de pixels).

`EnableExperimentalFeatures` est devenue une propriété qui allume ou éteint cinq
modules expérimentaux d'un coup ; elle vaut toujours `false`, et le parc l'écrit
à `false`.

Le mode `Enhanced60` disparaît de l'i18n en 2.6.2 (320 → 345 clés `config.*` de
2.5.0 à 2.6.2) et revient en 2.6.3. La fixture de l'éditeur reste la capture de
la 2.3.8 : aucun test à toucher.

### Surfaces

Inchangées : un seul `File.WriteAllText` (le rapport `us_trace`, dans le dossier
du mod) et 21 `WriteConfig`, tous dans `ModEntry`. Aucun accès réseau, aucun
chargement de code, aucun processus lancé.

## Stardropium 0.2.9-alpha → 0.3.0

Pas de journal sur Nexus (il s'arrête à 0.2.2-beta). 13 fichiers changés, un
nouveau ; 74 appels `harmony.Patch` avant comme après ; cibles identiques, au
transpileur interne de Fashion Sense près.

- **`PlatformHelper` (nouveau).** Détecte Android ou Cinderbox (variables
  d'environnement, fichiers `/system/…`, `/proc/version`) pour couper le GC basse
  latence, le flux de sauvegarde réutilisable et forcer le profil basse mémoire.
  Lectures seules ; sur Mac, rien ne s'allume.
- **Préchargement des données retiré.** Le `Task.Run` qui chargeait huit actifs
  `Data/*` en parallèle au lancement n'existe plus, et `EnablePreWarmDataLoader`
  passe à `false`. Le `config.json` du parc garde `true`, sans effet : il n'y a
  plus de code derrière.
- **Fashion Sense.** Le cache de tenue par joueur et direction disparaît ; seul
  reste l'index des modèles.
- **Ralentisseurs de PNJ.** Movement Overhaul et le ralentissement hors écran
  épargnent désormais un PNJ en mouvement ou guidé (`temporaryController`,
  `DirectionsToNewLocation`) et élargissent la marge d'écran (256 ou 128 → 384 px).
  Le module Movement Overhaul ne vérifie plus que le PNJ est dans le lieu du
  joueur. Movement Overhaul n'est pas sur le parc.
- **`Grass.draw` reçoit un finalizer** qui avale toute `KeyNotFoundException`.
  `Grass.draw` est patchée aussi par UltraSmooth et Radiance : une erreur de clé
  venue de n'importe lequel des trois disparaît du journal au lieu d'y figurer.
- La page GMCM des mods tiers liste enfin les six modules ajoutés en 0.2.9.

**Ce que l'app lit chez Stardropium — intact.** Le bloc qui écrit la ligne
`[Morning Memory Optimizer (Background)]` est identique ; le message du profil
basse mémoire garde, sur Mac, le préfixe et la phrase que
`StardropiumMemoryReport` attend. Les clés D2-T5 (`EnableMemoryOptimization`,
`AutoTrimWorkingSetOnNewDay`) existent toujours, et l'option du conseil Sword and
Sorcery aussi (`EnableTenMinuteObjectPassTimeOptimization`, active par défaut).
Surfaces inchangées : 8 `WriteJsonFile` et 2 `WriteConfig`, aucun réseau.

## Catalogue des recouvrements (A5-T7)

Relevé refait sur les versions du parc, avec un relevé qui suit aussi les types
tenus dans une variable (`AccessTools.TypeByName`, balayages d'assemblies). Chaque
méthode retenue a été relue à son site `harmony.Patch`, avec sa garde et sa valeur
par défaut des deux côtés.

| Paire | Avant | Après | Ajouts |
|---|---|---|---|
| Stardropium × UltraSmooth | 15 (+1 conditionnelle) | 20 (+1) | `SaveGamePatcher.FindAndRemoveModNodes`, `SaveGame+<getSaveEnumerator>d__94.MoveNext`, `TMXExtensions.SetFlip`, `TMXExtensions.SetRotationValue`, `ModEntry+Utility.GetTilesByProperty` (Farm Type Manager) |
| Radiance × UltraSmooth | 7 | 13 | `Object.draw` (neuve en 2.6.0) ; par balayage, `Critter.draw`, `Critter.drawAboveFrontLayer`, `Bat.drawAboveAllLayers`, `Junimo.draw`, `JunimoHarvester.draw` |
| StardewOptimizer × UltraSmooth | 8 | 8 (+1 conditionnelle) | `MachineGroup.Automate`, derrière `AutomateThrottle` ou `AutomateZoneThrottle`, éteints par défaut |
| Radiance × Stardropium | 4 | 4 | — |

Les quinze méthodes déjà au catalogue pour Stardropium × UltraSmooth restent
patchées des deux côtés ; `timeUpdate` reste derrière `EnableExperimentalFeatures`.

Trois remarques sur ces ajouts :

- **Les méthodes typées par variable manquaient depuis toujours**, pas depuis
  cette version : la traversée SpaceCore était déjà partagée en 2.4.9, et les
  setters TMXTile et l'itérateur de sauvegarde sont présents dès la 2.5.0. Le
  relevé lisait les seuls `typeof(...)`.
- **`AutomateHibernateOptimizer` patche `MachineGroup.Automate`, pas `Tick`.**
  Il cherche `Tick` d'abord ; `Automate.dll` n'en a pas, il se rabat sur
  `Automate`. L'audit 2.4.1 avait écrit `MachineGroup.Tick`.
- **Les balayages d'UltraSmooth ne recoupent rien d'autre** chez Stardropium et
  StardewOptimizer : leurs cibles nommées dans les familles balayées
  (`Monster`, `Critter`, `Character`, objets posés) sont déjà au catalogue
  (`NPC.update`, `FarmAnimal.draw`, `Monster.update`), et les `OnUpdateTicked`
  ou `tickUpdate` visent des types différents (AlternativeTextures, objets
  posés d'un côté ; patch interne d'AlternativeTextures, éléments de terrain
  de l'autre).
- **Restent hors catalogue**, parce qu'ils dépendent des mods installés : les
  balayages de Radiance sur les personnages des autres mods et ceux d'UltraSmooth
  sur toutes les sous-classes de `Character` se croisent sur chaque PNJ moddé qui
  déclare ses propres méthodes de dessin. Seule la carte de la sonde peut les
  compter.

## Limites

- Rien n'a été lancé : ni le jeu, ni la sonde. Les recoupements sont lus dans le
  code, pas observés.
- La 2.6.3 n'est pas décompilée ; la 2.4.17 → 2.5.0 non plus, faute de DLL.
- `Critter.draw` et `Critter.drawAboveFrontLayer` nomment une famille : `Critter`
  est abstraite, ce sont ses surcharges (onze types de `BellsAndWhistles`) qui
  sont patchées. La carte de la sonde, elle, écrirait `Birdie.draw`,
  `Butterfly.draw`…
