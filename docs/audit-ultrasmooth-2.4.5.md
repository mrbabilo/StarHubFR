# Audit — UltraSmooth 2.4.5 *(2026-10-04)*

Suite de [`audit-ultrasmooth-2.4.1.md`](audit-ultrasmooth-2.4.1.md). Delta
2.4.4 → 2.4.5 décompilé et comparé (`ilspycmd`, 7 fichiers, ~978 lignes dont
du bruit IL) ; la 2.4.4 n'a vécu sur le parc que le temps d'un
dépôt-remplacement le 2026-10-03, en pause — les journaux 2.4.2 → 2.4.4 ont
été lus dans la même passe (`check_sources --fetch-changelogs`). Rien du mod
n'est repris.

| | |
|---|---|
| **Identité** | `palmhacker13.UltraSmooth` · 2.4.5 · Nexus 50971 · installé **en pause** (`.UltraSmooth`) |
| **Surfaces** | réseau / processus / chargement de code / suppression de fichiers : **identiques** au filet à filet (Socket 33 = LAN coop du mod ; `File.WriteAllText` 1 = LagTraceRecorder, dossier du mod) |
| **Verdict** | **GO** — défauts d'usine désormais sûrs, rien à forcer |

## Prétentions de l'auteur — toutes vraies dans le code

- **Boucle sub-tick retirée** : les 9 drapeaux `[ThreadStatic]` et les 9 boucles
  ré-invoquant `tickUpdate`/`update`/`updateChunks` (TerrainFeature,
  TemporaryAnimatedSprite, Water, Debris, CosmeticDebris, Critter, Train,
  FlyingCompanion, Character) sont absentes de la 2.4.5 ;
  `SimulationTicksToRunThisFrame` ne produit plus que {0, 1} — un tick par
  trame, la cause mécanique des CTD de récolte est partie. Nuance : la boucle
  ne vivait que dans les modes débridés (`FpsMode` ≠ Standard) ; en Standard
  les préfixes passaient déjà tout à vanilla.
- **MachineOptimizer** : `heldObject.Value == null` → pas de throttle du tout
  (torches et text-signes ne sont plus touchées, les whitelists sont devenues
  inutiles) ; machines hors écran +128 px, moitié des trames.
- **`EnableSmartSchedule` false par défaut** (le `= true` a disparu) ;
  détecteur de transition de planning (controller, chemins, délais, animations
  de fin de route) qui réveillerait les NPC à 60 Hz — inerte, clé désarmée.
- **`EnableFurnitureCulling` false par défaut** ; fenêtres
  (`furniture_type == 13`) jamais cullées.
- **`EnableParallelDayUpdate` false par défaut** (déjà ainsi en 2.4.4) et le
  `Parallel.ForEach` de `DayTransitionOptimizer` reste derrière
  `!Config.EnableParallelDayUpdate || _forceSequentialDayUpdate`. Le double
  appel structurel des corps de sous-classes (défaut 2.4.1) reste **latent**
  si la clé est forcée, mais `_forceSequentialDayUpdate` s'arme seul si
  BushBloomMod / CustomBush / **ItemExtensions** (actif sur le parc) sont
  chargés — même une activation volontaire retomberait en séquentiel.

## Le bug préchauffage SpaceCore : toujours là, mais désarmé d'usine

`TurboLoadEngine.TryPrewarmSpaceCoreSerializers` est inchangé (réflexion vers
`SpaceCore … InitializeSerializers` sur un `Task.Run` au lancement) —
**aucun journal 2.4.2 → 2.4.5 ne le corrige**. Ce qui a changé :
`EnableSpaceCorePrewarm` est **false par défaut** en 2.4.5 (propriété auto
sans initialiseur, comme les quatre clés ci-dessus) — le réglage posé à la
main le 2026-09-26 est devenu l'état d'usine. Vérifié dans le ModConfig
décompilé : les cinq clés dangereuses (`EnableSpaceCorePrewarm`,
`EnableFurnitureCulling`, `EnableExperimentalFeatures`,
`EnableParallelDayUpdate`, `EnableSmartSchedule`) n'ont plus aucun
initialiseur à `true`.

## Défauts du delta — 3 × 🟡, aucun 🔴/🟠

- `us_reload` (nouvelle commande console → `ApplyRuntimeConfig`) ré-applique
  toute la config — grille de débris, consolidation, config hôte — **depuis le
  fil console de SMAPI**, sans garde : courses possibles avec la boucle de jeu
  si tapée en pleine partie. Ne pas l'utiliser en jeu.
- `ApplyRuntimeConfig` appelle désormais aussi
  `ExperimentalCoordinator.EnsureActivated()` si
  `EnableExperimentalFeatures` — reste false d'usine.
- Le rendu des badges de débris passe sous un `try/catch` qui avale en `Trace`
  : un problème de rendu récurrent deviendrait invisible. (Les deux gardes
  NRE ajoutées dans `DebrisOptimizer` sont, elles, de vrais correctifs.)

## Conditions de réactivation

Rien à forcer : les défauts d'usine sont bons. Permanent : ne jamais activer
`EnableSpaceCorePrewarm`, `EnableParallelDayUpdate`,
`EnableExperimentalFeatures` ; ne pas taper `us_reload` en partie. Même
réserve d'espérance qu'en 2.4.0 : aucun préfixe de dessin n'est touché, le
goulot `DoDraw`/`Present` (~40 FPS perdus sur ce poste) n'est pas traité — la
réactivation se justifie par le confort, pas par les FPS. Une paire guidée
avant/après (D5-A) reste le juge si l'objectif est la fluidité.
