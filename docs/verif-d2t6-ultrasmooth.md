# D2-T6 — Vérification en jeu des deux risques UltraSmooth (2026-10-08)

Protocole pour l'auteur + brouillons de signalement à l'auteur du mod.
Risques relevés dans [`audit-ultrasmooth-2.3.7.md`](audit-ultrasmooth-2.3.7.md) §3
(2026-09-04, décompilation UltraSmooth 2.3.7).

## Re-vérification sur la version du parc — 2.4.10

UltraSmooth installé sur le parc : **2.4.10**, en pause (`Mods/.UltraSmooth`),
DLL SHA-256 `54a17291f31976c6dd748c87de70cdbb06719ae87e0d7592bf0e105d6a6c92cd`
(différente de la 2.4.9 audite le 2026-10-07). Décompilation ILSpy du
2026-10-08 : **les deux chemins de code existent inchangés** dans leur logique.

1. `UltraSmooth.Optimizers.DayTransitionOptimizer` — préfixe priorité 600 sur
   `GameLocation.DayUpdate`, actif dès `EnableDayTransitionSlicing` (vrai dans
   la config du parc). Le **chemin séquentiel** (`EnableParallelDayUpdate=false`,
   cas du parc) saute aussi les lieux « dormants » : `IsDormantEmptyLocation`
   puis `return false`. `FarmCave` n'est pas dans les exclusions
   (Farm, Greenhouse, Cellar, Shed\*, IslandWest\*, lieu courant, `lastSleepLocation`).
2. `UltraSmooth.Optimizers.QueryCacheManager` — clé de cache par trame :
   chaîne, lieu, joueur, **`targetItem.ItemId` / `inputItem.ItemId` seuls**
   (qualité, quantité, prix absents). Améliorations vs 2.3.7 : un appel avec
   `random != null` contourne le cache, et `RANDOM`/`RANDOM_BOOL` (sous-chaîne,
   insensible à la casse) aussi. `ITEM_QUALITY`, `ITEM_STACK`, `ITEM_PRICE`
   restent con fondables dans la même trame.

Contre-vérification dans la DLL du jeu (`FarmCave.DayUpdate`, décompilée) :
`caveChoice == 1` (chauves-souris) fait tomber les fruits **dans `DayUpdate`
même** (boucle `while (Game1.random.NextDouble() < 0.66)`, objets posés au
sol) ; `caveChoice == 2` (champignons) pose six bacs `(BC)128`, qui sont des
**objets** — une grotte à champignons n'est donc jamais « dormante » et
s'auto-protège. **Seule la grotte à chauves-souris, vidée de ses fruits,
expose le risque.** La sauvegarde TestOK est à `caveChoice 0` (choix pas
encore fait) au 23 printemps an 1 : choisir « chauves-souris » pendant l'essai.

## Protocole — risque 1 (grotte qui ne se regarnit plus)

Deux sessions de quelques nuits chacune. Les nuits avec l'option active sont
**déterministes** (skip complet du `DayUpdate` : zéro fruit garanti) ; les
nuits témoins sont aléatoires (0,66 par roulement) — prévoir 3-4 nuits.

**Session A — option active (bug attendu)**

1. Dé-pauser UltraSmooth dans StarHubFR. Config inchangée :
   `EnableDayTransitionSlicing: true`, `EnableSpaceCorePrewarm: false`,
   `EnableParallelDayUpdate: false` (ne pas toucher à ces deux derniers).
2. Choisir la grotte à **chauves-souris** chez Démétrius si pas encore fait.
3. Ramasser **tous** les fruits au sol de la grotte (la vider entièrement).
4. Dormir 3-4 nuits, en re-ramassant chaque matin.
5. Constat attendu : **zéro fruit nouveau** sur toutes les nuits.
   Preuve d'appoint dans le journal SMAPI, chaque nuit :
   `DayTransitionOptimizer: Day transition completed in … skipped N dormant`
   avec N > 0.

**Session B — témoin (option coupée)**

1. Quitter le jeu, re-pauser UltraSmooth, éditer
   `…/Mods/.UltraSmooth/config.json` : `"EnableDayTransitionSlicing": false`.
2. Dé-pauser, jouer, vider la grotte de la même façon, dormir 3-4 nuits.
3. Constat attendu : les fruits **réapparaissent** au moins une nuit sur deux
   (probabilité 0,66 par roulement, plusieurs roulements par nuit).

**Restauration** : `"EnableDayTransitionSlicing": true` (valeur d'origine),
mod remis en pause. Ne jamais utiliser `us_reload` en partie (courses de
threads documentées depuis 2.4.5) : éditer la config jeu fermé.

## Risque 2 — preuve par code, pas de vérification en jeu à coût raisonnable

Aucune commande console d'UltraSmooth n'évalue une `GameStateQuery`
(`us_toggle`, `us_trace`, `us_diag`… inventoriées ; rien de la sorte), et les
seuls usages pertinents sur le parc sont :

- `ITEM_QUALITY Target 1 4` dans `[CP] Cornucopia Cooking Recipes/data/forage.json`
  — règle de cueillette Content Patcher, évaluée à l'édition d'asset, pas en
  rafale par trame sur deux objets frères ;
- `ITEM_PRICE Input …` dans `[CP] BinningSkill/data/machines.json` — exige que
  deux objets de même `ItemId` mais de prix différent soient testés dans la
  **même trame**, scénario que le jeu ne présente pas de façon contrôlable.

Le signalement ci-dessous repose donc sur le code décompilé (2.3.7 et 2.4.10
identiques sur ce point). Si l'auteur du mod veut une reproduction jouée, un
mini-mod d'essai appelant `CheckConditions` deux fois dans la même trame sur
deux objets frères suffirait — hors périmètre StarHubFR.

## Brouillons de signalement (anglais, à poster après vérification)

### Bug 1 — Dormant locations never run DayUpdate (fruit bat cave stops producing)

> **UltraSmooth 2.4.10** (`DayTransitionOptimizer`), with default
> `EnableDayTransitionSlicing: true` and `EnableParallelDayUpdate: false`.
>
> `GameLocation_DayUpdate_Prefix` (priority 600) skips `DayUpdate` entirely for
> any location where `IsDormantEmptyLocation` returns true — no objects,
> terrain features, characters, animals, debris, resource clumps, large
> terrain features or buildings. This also holds on the sequential path, not
> just the parallel one.
>
> The problem: `DayUpdate` is where daily forage and location-specific spawns
> happen. A picked-clean fruit bat cave is "empty" by this test, so its
> `FarmCave.DayUpdate` never runs again and **fruit never respawns** — the
> location is permanently dead until the option is disabled. Mushroom caves
> are unaffected in practice (the six mushroom bins count as objects), which
> is why the bug hides: it only hits the bat cave variant and similar
> spawn-on-empty locations (on my save, 183 of 362 locations qualify as
> dormant, including several Content Patcher forage locations from expanded
> maps).
>
> Repro (verified in decompiled game code, in-game check pending/on my side):
> pick the fruit bat cave, pick up every fruit, sleep several nights with the
> option on — zero new fruit; disable the option, same steps — fruit returns.
>
> Suggested fix: never skip `DayUpdate` for locations whose type overrides it
> (FarmCave and friends), or maintain a whitelist of locations with daily
> spawn logic, or only skip the base `GameLocation.DayUpdate` body while
> still calling overrides.

### Bug 2 — Query cache key ignores item quality / stack / price

> **UltraSmooth 2.4.10** (`QueryCacheManager`), with `EnableQueryCache: true`.
>
> The per-frame memoization key is
> `(queryString, locationName, playerId, targetItem.ItemId, inputItem.ItemId, ignoreKeysHash)`.
> Two calls in the same tick with the *same* `ItemId` but different
> **quality, stack or price** are treated as the same query, so the second
> caller receives the first caller's answer. Any condition like
> `ITEM_QUALITY`, `ITEM_STACK` or `ITEM_PRICE` (on target or input) can
> therefore evaluate against the wrong item.
>
> `RANDOM`/`RANDOM_BOOL` and any call passing a non-null `random` already
> bypass the cache; the item-identity collision remains.
>
> Suggested fix: include `targetItem?.Quality`, `inputItem?.Quality`,
> `Stack` and `salePrice()` (or the full item identity) in the key, or skip
> caching whenever the query string contains `ITEM_QUALITY`/`ITEM_STACK`/`ITEM_PRICE`,
> the same way `RANDOM` is skipped today.

Lieu de dépôt : page Nexus du mod (50971), bugs séparés ou un même message à
deux volets — à juger après la vérification, les deux correctifs sont
indépendants.
