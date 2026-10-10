# Audit — Stardropium 0.2.9-alpha *(2026-10-10)*

Suite de [`audit-stardropium-0.2.2.md`](audit-stardropium-0.2.2.md). Delta
0.2.2-beta → 0.2.9-alpha décompilé et comparé (`ilspycmd`) : le 0.2.2-beta
vient du backup d'installation `2026-10-10_125856_6FA8A47D…`, le 0.2.9 du parc.
Ouvert par le relevé des sources du même soir (`check_sources.py`), qui
signalait **sept versions publiées sans aucun changelog** sur Nexus
(0.2.3 → 0.2.9). Rien du mod n'est repris.

| | |
|---|---|
| **Identité** | `Arshia1381.Stardropium` · **0.2.9-alpha** au manifeste installé (Nexus et le relevé disent « 0.2.9-beta » : rien ne prouve que ce soient les mêmes octets) · DLL `6f4512a05bfd…` du 2026-10-08 · Nexus 52803 · **en pause** sur le parc (`.Stardropium`) |
| **Surfaces** | réseau / chargement de code / écriture de fichiers : 19 occurrences avant comme après, aucune dans les modules neufs |
| **Verdict** | **GARDER EN PAUSE, rien à forcer** — le delta ajoute des optimisations ciblées sur d'autres mods ; les contrats que l'app lit sont intacts |

## Ce qui a changé

- **Sept modules neufs, aucun retiré** (49 au total). Tous ciblent le code
  interne d'un autre mod, résolu par `AccessTools.TypeByName` — inertes si le
  mod visé est absent — et **tous actifs par défaut** :

  | Module | Cible | Option |
  |---|---|---|
  | Automate | `MachineGroupFactory.GetMachineGroups` | `EnableAutomateOptimization` |
  | Dynamic Map Tiles | `DMT.Patches.CheckBarrier` + `GameLocation._TestCornersTiles` (jeu) | `EnableDynamicMapTilesOptimization` |
  | Fashion Sense | `GetCurrentlyEquippedModels` (transpileur) + `Reset` du gestionnaire de textures | `EnableFashionSenseOptimization` |
  | GMCM | `GenericModConfigMenu.Mod.OnRendered` / `OnUpdateTicking` | `EnableGMCMOptimization` |
  | Nature in the Valley | `NatureInTheValleyEntry.Decorate` | `EnableNatureInTheValleyOptimization` |
  | Ornithologist's Guild | `TreePatches.tickUpdate_Postfix` | `EnableOrnithologistsGuildOptimization` |
  | Tilesheet Path | SMAPI `ModContentManager.TryGetTilesheetAssetName` | `EnableTilesheetPathOptimization` |

- **`MapLoadOptimizationModule`** : un préfixe neuf sur `GameLocation.reloadMap`
  (« déduplication sûre au chargement de partie »).
- `harmony.Patch` : **128 → 148** appels. Options de config : +7 (celles du
  tableau), aucune retirée. `ModEntry` : 190 lignes de diff, menus GMCM et
  télémétrie — aucun GC, patch, fichier ni réseau neuf.

## Ce que l'app lit chez Stardropium — intact

- **Diagnostic guidé D2-T5** : les deux clés forcées, `EnableMemoryOptimization`
  et `AutoTrimWorkingSetOnNewDay`, existent toujours.
- **Carte « Mémoire — Stardropium »** : la ligne
  `[Morning Memory Optimizer (Background)] RAM: … MB -> … MB (Managed Heap: …)`
  est **identique octet pour octet** dans `TrimMemory`, toujours appelée par
  `OnDayStarted` avec `isOvernight: true` ; le message du profil basse mémoire
  aussi. Le parseur `StardropiumMemoryReport` n'a rien à changer.
- **Le conseil Sword and Sorcery** de `SOURCES.md` reste juste : le préfixe de
  `passTimeForObjects` saute toujours `minutesElapsed` sur un objet simple sans
  `heldObject`, et `EnableTenMinuteObjectPassTimeOptimization` existe toujours,
  vrai par défaut.

## Catalogue des recouvrements (A5-T7) — une correction, pas un ajout

Les intersections ont été recalculées sur les six mods du catalogue, aux
versions du parc (UltraSmooth 2.4.16, Radiance 2.3.1, StardewOptimizer 1.0.0,
SinZ Speedy Solutions 1.1.0, Loading Optimizer 1.0.0) : relevé des
`AccessTools.Method`, puis lecture des sites de balayage dynamique. **Aucune
des cibles neuves de Stardropium n'est patchée par un autre membre**
(`reloadMap`, `_TestCornersTiles`, `TryGetTilesheetAssetName`,
`GetMachineGroups`).

En revanche, la remesure A5-T10 du matin avait **recopié une ligne fausse** :
`GameLocation.passTimeForObjects` figurait parmi les méthodes conditionnelles
de la paire Stardropium × UltraSmooth, derrière `EnableExperimentalFeatures`.
Ce n'est plus vrai depuis UltraSmooth **2.4.9** : `ClockTickOptimizer` la
préfixe dans `ApplyHarmonyPatches`, sous le seul garde `EnableMod` (vrai par
défaut) — l'audit [`audit-ultrasmooth-2.4.9.md`](audit-ultrasmooth-2.4.9.md)
§3 l'avait noté sans le reporter au catalogue. Stardropium la préfixe aussi
par défaut. Les deux mods remplacent donc **le même passage de 10 minutes par
deux règles différentes** d'objets « inertes ». Corrigé : 15 méthodes
partagées, `timeUpdate` seule reste conditionnelle (UltraSmooth ne la patche
que dans `TickScheduler`, via `ExperimentalCoordinator`).

Deux faits voisins, hors catalogue :

- Automate est désormais freiné **par deux mods** : Stardropium sur
  `MachineGroupFactory.GetMachineGroups`, StardewOptimizer sur
  `MachineGroup.Automate` — deux méthodes distinctes, donc pas une paire au
  sens du catalogue, mais le même mod visé.
- UltraSmooth patche le code de Radiance (`SDVRadiance.ParticleSystem.AdvanceTo`,
  `HighFpsPacingEngine`) — déjà présent en 2.4.15. Le catalogue décompilé ne
  porte pas les patches de code d'un mod sur un autre ; seule la carte de la
  sonde les relève.

## UltraSmooth 2.4.15 → 2.4.16, au passage

14 fichiers, 165 `harmony.Patch` des deux côtés. Le changelog annonce le
repli du limiteur de sons (objet de secours plutôt que `null`).
`DayTransitionOptimizer` ne change que d'une ligne : la mise à jour
parallèle des lieux est coupée en multijoueur. **Les deux chemins suivis par
D2-T6** — le saut de `DayUpdate` des lieux vides et l'identité par `ItemId`
de `QueryCacheManager` — sont inchangés : la vérification en jeu reste à faire
telle quelle.

## Limites

- Le relevé par expression régulière compte des appels qui ne sont pas des
  patches (`JitPrewarmer`) et en rate d'autres (types en variable, balayages) :
  chaque intersection retenue a été relue à son site `harmony.Patch`.
- Rien n'a été vérifié en jeu. Le mod est en pause.
