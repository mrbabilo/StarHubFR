# StardewOptimizer — relevé et décompilation *(2026-10-09)*

Nexus [53663](https://www.nexusmods.com/stardewvalley/mods/53663), publié le
2026-10-09 à 19:38 UTC, 11 téléchargements au relevé. Décompilé
(`ilspycmd`, `DOTNET_ROOT=/opt/homebrew/Cellar/dotnet/10.0.401/libexec`),
**rien exécuté** ; le mod est installé **en pause** sur le parc et y reste.

## Identité

| | |
|---|---|
| Manifeste | `baiyu.StardewOptimizer` 1.0.0, auteur `baiyu`, SMAPI ≥ 4.0.0, **`UpdateKeys` vide** |
| Page Nexus | « StardewOptimizer », version `1`, auteur `dcbnmkdshjbnfas`, catégorie *Visuals and Graphics* |
| Fichier | 186155 (MAIN), 5 fichiers : `StardewOptimizer.dll` (262 144 o), `config.json`, `i18n/default.json`, `i18n/zh.json`, `manifest.json` |
| Empreinte DLL | SHA-256 `e93c979c15c0a819e1bb7a4139fdbceb266f48c946fc3befaa232af49fb5c470` — **identique** entre le manifeste de fichiers Nexus (§2.4 bis) et la copie du parc |
| Code | 10 141 lignes décompilées, 14 modules (`StardewOptimizer.Modules.*`), hub de coordination (`Shared/CoordinationHub`) |

Le résumé de la page dit, en chinois, que le mod « combine le code des auteurs
de mods d'optimisation ». La description anglaise garde le gabarit Nexus non
rempli en dessous du texte.

## Sécurité — ce que le code fait et ne fait pas

- **Aucun accès réseau**, aucun `Assembly.Load`, aucun `Process.Start`, aucune
  suppression de fichier, aucun décodage base64 (grep sur tout le décompilé).
- **P/Invoke Windows seul** : `psapi.dll!EmptyWorkingSet`
  (`MemoryStabilizer/WindowsWorkingSet.cs`), gardé par
  `OperatingSystem.IsWindows()`.
- **`ProcessTuning`** change priorité et affinité du processus (`unsafe`
  limité à un cast d'énumération) — `IsAvailable => OperatingSystem.IsWindows()` :
  **inerte sur macOS**.
- **Absent de la liste noire SMAPI** du parc (`smapi-internal/metadata.json`).
- Compte créé le jour même, nom aléatoire, mauvaise catégorie : signaux faibles
  d'un dépôt peu soigné, **pas** d'un comportement malveillant dans le code.

## Les promesses de la page, contre le code

| Promesse | Verdict |
|---|---|
| « All risky optimizations are off by default » | **Faux en partie.** Le `config.json` livré active 6 modules sur 14 : `MenuLazyLoad`, `LocationPreload`, `AutomateThrottle`, `MemoryStabilizer`, `ProcessTuning` (inerte sur Mac), `AudioChangeCoalesce` |
| GC forcé | **Vrai.** `MemoryStabilizer`, actif par défaut : nettoyage « doux » `GC.Collect(1)`, nettoyage « dur » `GC.Collect(MaxGeneration, Forced, blocking, compacting)` **deux fois** autour de `WaitForPendingFinalizers`, compaction du LOH si `CompactLargeObjectHeapOnHardClean` — sous délai de garde (`CleanupPlanner`) |
| Auto-désactivation sur conflit | **Vrai, par UniqueID** (`CompatDetector.Detect` → `IModRegistry.IsLoaded`) : UI Info Suite 2, Better Crafting (deux id), Automate, Lookup Anything, CJB Item Spawner, Chests Anywhere, Profit Calculator, Convenient Inventory, Better Junimos |
| Budget CPU de 25 % du temps d'image | **Vrai** : `CoordinationHub.EffectiveBudgetMs = clamp(EMA(frame) × 0,25, 1, 8) ms` |
| Code d'autres auteurs | **Non établi.** Aucun nom de module, de classe ni de cible ne recoupe UltraSmooth, Stardropium, FastLoads ni SLO tels qu'audités ici |

## Ce qu'il patche (Harmony, 13 appels)

- Jeu : `GameMenu` (constructeur, `changeTab` — onglets chargés à la demande),
  `NPC.update`, `Monster.update` et ses sous-types, `GameLocation.DayUpdate`
  (pousse des cultures, conditionnée à la présence de `HoeDirt`),
  `TemporaryAnimatedSprite.draw`, `MapPage.drawMap`,
  `AudioCueModificationManager.ApplyCueModification`.
- Cibles **lues à l'exécution** par `LoadProfiler` (désactivé par défaut) :
  `TypeByName(target.TypeName)` — non énumérables statiquement.
- **Internes d'autres mods** : `Pathoschild.Stardew.Automate.Framework.MachineManager`
  et `MachineGroup` (préfixes qui espacent le traitement des machines —
  `AutomateThrottle` **actif par défaut**).
- **Interne de SMAPI** : ``StardewModdingAPI.Framework.Events.ManagedEvent`1``
  (`EventProfiler`, désactivé par défaut).
- Recoupe le catalogue A5-T7 (`Models/PerformanceOverlap.swift`) sur
  **`NPC.update`**, déjà patché par Stardropium et UltraSmooth — mais par
  `NpcThrottle`, désactivé par défaut.

## Pour StarHubFR

- **Rien à porter.** Idée à peser seulement : un registre de patchs partagé
  (`PatchRegistry` refuse un second module sur une méthode déjà prise et le
  journalise) — l'équivalent, côté app, de ce que fait déjà A5-T7 entre mods.
- `UpdateKeys` vide : l'app ne trouvera ses mises à jour que par l'identifiant
  Nexus du dossier ou de l'archive, pas par le manifeste.
- Archive **sans dossier racine** au nouveau nommage Nexus
  (`StardewOptimizer 53663 1 2026-10-09T19-37Z arMRSFD62.zip`) : l'installeur
  (`ModZipInstaller`, cas `.flatRoot`) a repris ce nom pour le dossier du mod.
  Voulu par le code, mais le nom porte la date et le jeton de téléchargement —
  à traiter à part.
