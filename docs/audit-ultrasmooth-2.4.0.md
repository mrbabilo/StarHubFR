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

## 2. Constats sur les options

- **« Activer le Profilateur » n'est pas le profileur.** Dans le `fr.json` de
  l'auteur du parc (produit par le hub de traduction le 2026-09-08), la clé
  `config.enableSkipIntro` — « Fast Startup (Skip Intro) » — est traduite
  « Activer le Profilateur » ; la référence `TranslationBaselines` montre la
  bonne source et une cible fausse, `reviewNeeded: false`. L'option décochée
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
