# Audit — UltraSmooth 2.4.0 *(2026-09-29)*

Suite de [`audit-ultrasmooth-2.3.7.md`](audit-ultrasmooth-2.3.7.md). Question de
l'auteur : **pourquoi ce mod de performance fait-il chuter les FPS**, et quels
réglages changer. Rien du mod n'est repris (ni source publique ni licence).

| | |
|---|---|
| **Identité** | `palmhacker13.UltraSmooth` · 2.4.0 · Nexus 50971 · installé **en pause** (`.UltraSmooth`) |
| **DLL** | `ilspycmd` 10.1.1 (lancer avec `DOTNET_ROOT=/opt/homebrew/Cellar/dotnet/<v>/libexec`, sinon code 131) : 99 fichiers, 26 049 lignes |
| **Mesure** | paire guidée du 2026-09-29 15:22 (avec) → 15:33 (sans), Ferme, 5 minutes gardées de chaque côté, sonde 0.5.0 |

## 1. Le mécanisme : une spirale de rattrapage

Décomposition des minutes gardées (médianes par minute) :

| | Avec UltraSmooth | Sans |
|---|---|---|
| FPS | 12–18 | 51–58 |
| Trame p50 | 51–82 ms | 16,5–16,9 ms |
| Mises à jour par image (`UpdatesPerTick`) | **3 à 5** | 1 |
| Une mise à jour (`Update` p50) | 10–12 ms | 11 ms |
| Dessin total `DoDraw` (`OuterDraw`) | **19–22 ms** | 4,6–5,1 ms |
| Dessin du jeu seul (`Draw`, `DebugTimings`) | 3,1–4,2 ms | 2,9–3,5 ms |
| Envoi à l'écran (`Present`) | 13–15 ms | 0,7–1,8 ms |
| Travail de trame du fil du jeu | ~1 000 ms/s | ~1 000 ms/s |

Sans le mod, une image tient **tout juste** dans le budget de 16,67 ms (le parc
de 966 mods ne laisse presque aucune marge). UltraSmooth ajoute ~15 ms dans
`DoDraw`, **hors** du dessin propre du jeu : l'image dépasse le budget, le jeu
reste en pas fixe à 60 Hz (mode `Standard`, `ProfilerEngine.ApplyFpsMode`),
se croit en retard et enchaîne 3 à 5 mises à jour par image pour rattraper — qui
coûtent chacune 11 ms et le retardent encore. `Present` à 15 ms est l'attente de
synchro, un symptôme, pas la cause.

Les événements d'UltraSmooth ne coûtent que ~3 ms/s (`RenderedHud` 2,0). Les
~15 ms sont donc dans ses **patches Harmony** (une vingtaine de préfixes de
tri sur le dessin : arbres, herbe, terre labourée, meubles, bâtiments,
personnages, débris, sources de lumière… `RenderingOptimizer`,
`SpriteInterpolator`, `HighFpsPacingEngine.Farmer_Draw_Prefix`) — que les
mesures guidées ne comptent pas (patches désarmés). **À confirmer** par une
session non guidée, `MeasureHarmonyPatches` armé (`PatchMs` par propriétaire
dans `mod-costs.jsonl`).

### Mesuré ensuite : ses patches (session 19:50, non guidée, patches armés)

5 minutes à la Ferme, UltraSmooth 2.4.0 actif, 3 mises à jour par image, ~17
FPS. Aucun transpileur d'UltraSmooth (`patch-wraps.json`) : tout son coût est
dans les préfixes mesurés. Biais de l'enveloppe : 36,3 ns par appel.

| Méthode patchée | Appels / min | Coût / image |
|---|---|---|
| `MonsterLodOptimizer.Monster_Update_Prefix` (`EnableMonsterLod`) | 4,69 M | **3,19 ms** |
| `HighFpsPacingEngine.Character_Update_Prefix` | 9,76 M | 1,03 ms |
| `MachineOptimizer.UpdateWhenCurrentLocation_Prefix` (`EnableMachineOptimizer`) | 3,70 M | 0,95 ms |
| `NpcPathfindingLodOptimizer.Npc_Update_Prefix` (`EnableNpcPathfindingLod`) | 0,99 M | 0,65 ms |
| `HighFpsPacingEngine.Object_UpdateWhenCurrentLocation_Prefix` | 3,70 M | 0,39 ms |

Total ~69,6 ms/s, dont ~15 ms/s de biais : **~5,2 ms réels par image**, côté
mise à jour — multipliés par 3 à 5 par la spirale. Ses « optimiseurs » (LOD
des monstres, des machines, des PNJ) coûtent plus qu'ils n'économisent sur ce
parc. Ses préfixes de dessin, eux, sont négligeables (≤ 0,13 ms) : les ~12 ms
de `DoDraw` restent inexpliquées par les patches — probable saturation GPU
(`Present` 11 ms), à départager par les paires guidées des groupes de réglages.

**Deux constats hors UltraSmooth, sur la même session** :
- `Monster.update` est appelé **4,7 à 4,9 M fois par minute** (~1 500 monstres
  par mise à jour), partout (Ferme, Plage, Ville), et **croît dans la session**
  (1,9 M → 4,9 M en 4 minutes ; ~1,2 M les sessions du 26/09). Des monstres
  s'accumulent dans un lieu mis à jour en permanence ; aucun n'est dans la
  sauvegarde (le jeu ne les enregistre pas). Le mod qui les fait naître reste à
  trouver.
- **Alternative Textures** paie un suffixe sur chacune de ces mises à jour
  (`MonsterPatch.UpdatePostfix`) : **5,2 ms par image**, sans UltraSmooth.

### Test des réglages (paire guidée 19:32 → 20:14, Ferme, deux côtés `stable`)

Désactivés : `EnableMonsterLod`, `EnableMachineOptimizer`,
`EnableNpcPathfindingLod`, `ShowOverlay`, `EnableRenderTelemetry`,
`EnableDensityHeatmap`, `EnableHalfResLightMap` (config relue après la
session : tenue). Résultat : 17,1 → 18,0 FPS, toujours 3 mises à jour par
image, `OuterDraw` 16,5 → 15,7 ms, `Present` 11,7 → 12,2 ms. **La spirale
reste.** Le goulot n'est pas dans les optimiseurs côté mise à jour mais dans
le dessin : `DoDraw` ~16 ms (≈ 5 sans le mod) et `Present` ~12 ms (≈ 1 sans) —
signature d'un **GPU saturé** par UltraSmooth, ses préfixes de dessin étant
négligeables côté processeur. Conclusion pratique sur ce poste et ce parc :
**UltraSmooth en pause (≈ 56 FPS) vaut mieux qu'aucun réglage (≈ 18 FPS)**.
Ce qu'il apporte en échange (intro passée, chargement de sauvegarde sans
délai, fondus accélérés) est du confort, pas de la fluidité.

## 2. Constats sur les options

- **« Activer le Profilateur » n'est pas le profileur.** Dans le `fr.json` du
  parc (daté du 2026-09-08, d'origine inconnue : absent du registre des
  traductions installées, rien ne montre qu'il vienne du hub), la clé
  `config.enableSkipIntro` — « Fast Startup (Skip Intro) » — est traduite
  « Activer le Profilateur ». La référence `TranslationBaselines` n'en dit que
  ceci : la cible était déjà fausse le jour où l'app l'a vue (voir
  [`audit-traductions-fr-parc.md`](audit-traductions-fr-parc.md)). Retraduit
  en entier le 2026-09-29 (230 clés). L'option décochée
  est « passer l'intro ». Le vrai profileur (section « Profiler & Overlay »,
  `EnableRenderTelemetry`, `ShowOverlay`) est **activé**. Le `fr.json` a aussi
  58 clés dont l'anglais a changé, 113 clés non traduites, 100 orphelines.
- **`EnableHalfResLightMap` est sans effet en 1.6.** `Options.lightingQuality`
  est une constante (`=> 8`) que `Game1.allocateLightmap` lit : la carte de
  lumière garde sa taille. Le préfixe d'UltraSmooth écrit seulement
  `appliedLightingQuality` (4), témoin que `Options.reApplySetOptions` — appelé à
  chaque mise à jour — compare à 8 : au pire une reconstruction des surfaces
  (`refreshWindowSettings`), après quoi le jeu remet 8. Pas de boucle démontrée.
- **`FpsMode` : `Enhanced60`** passe en pas **variable** sur un écran ≤ 60 Hz
  (`DisplayHzDetector`) — plus de rattrapage possible, donc la spirale du §1
  disparaît, au prix d'une logique de jeu en pas variable (risque à mesurer).
- **`EnableSpaceCorePrewarm` reste à `false`** : il casse la sauvegarde (mémoire
  `ultrasmooth-prewarm-breaks-saves`).

## 3. Delta 2.3.9 → 2.4.0

5 fichiers : `HighFpsPacingEngine` (153 lignes), `DialoguePacingEngine`,
`MinigamePacingEngine`, `ProjectileOptimizer`, `UiOverlaySmoother`. Le temps
fixe `16,6667 ms` passé aux mises à jour cadencées devient
`HighFpsPacingEngine.GetPacedGameTime(time)` — ne joue que dans les modes à pas
variable. `ModConfig` inchangé (aucune option neuve). Surfaces comptées avant →
après : réseau 34 → 34, `Process.Start` 0 → 0, `Assembly.Load|DllImport`
3 → 3, suppression de fichiers 0 → 0.

## 4. Protocole pour trancher

1. Session **non guidée** (aucun plan en attente), UltraSmooth actif,
   `MeasureHarmonyPatches: true` : les 5 premières minutes après le chargement
   donnent `PatchMs` par propriétaire (le disjoncteur coupe ensuite ; les
   transpileurs restent invisibles).
2. Puis une paire guidée par groupe de réglages, au même lieu : diagnostics
   (`ShowOverlay`, `EnableRenderTelemetry`, `EnableDensityHeatmap`) ; dessin
   (culling, `EnableWorldRenderOptimization`, `EnableSpriteInterpolation`) ;
   `FpsMode: Enhanced60` seul.
