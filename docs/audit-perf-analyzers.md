# Audit des analyseurs de performance — UltraSmooth 2.1.3 et SDV-Radiance 1.7.6

> **Objet** — ce que la décompilation des deux mods suivis comme « analyseurs
> de performances » (`docs/SOURCES.md` §6) apprend à StarHubFR : ce qu'ils
> mesurent vraiment, ce qu'ils impriment, et ce que nos diagnostics SMAPI
> peuvent en reconnaître. Complète
> [`audit-mods-config-perf.md`](audit-mods-config-perf.md) (2026-09-04), qui
> avait noté les rapports d'UltraSmooth « durs à ingérer » sans avoir ouvert
> le code — ici le code est lu.
>
> **Méthode** — mêmes gestes que l'audit précédent : archives de `mods
> tests/` (gitignoré), DLL décompilées avec `ilspycmd` 10.1.1 (`DOTNET_ROOT`
> sur le Cellar Homebrew). Les espaces d'analyse lus en entier :
> `UltraSmooth.Analyzer`, `UltraSmooth.Profiler`, `UltraSmooth.Diagnostics`
> côté UltraSmooth ; `FrameCost`, `PhaseCost`, `GpuTimer`, `PerfHud`,
> `VramTally`, `PlatformReport` et les commandes (`ConsoleCommands.cs`,
> 2 196 l.) côté Radiance. Les citations sont des identifiants ou des
> littéraux décompilés. Relevé : **2026-09-08**.

---

## 1. Le constat qui recale tout : ils se mesurent, ils n'attribuent pas

- **UltraSmooth ne patche rien chez les autres.**
  `ProfilerEngine.ApplyPatches(Harmony)` est **vide**. `ModAnalyzer` — le
  moteur derrière `us_analyze` — n'enregistre que les sections internes du
  mod (`"Update Loop"`, `"Game Save Serialization"`,
  `"10-Minute Clock Update"`), avec un `ModId` synthétisé
  `"ultrasmooth." + section`. « Prints top resource-consuming engines » :
  les **siennes**, top 5, rien d'autre.
- **Radiance mesure ses quatorze passes, et avoue le reste.** Chaque frame
  longue est découpée en `ours {X} ms  not ours {Y} ms`, avec l'aveu en
  en-tête de rapport : *« 'not ours' is the game, other mods, the driver
  and the collector »* — jamais attribué plus loin.

**Conséquence pour StarHubFR** : aucun outil tiers ne dit *quel autre mod*
coûte cher. Nos seuls signaux d'attribution croisée restent ceux déjà
roadmappés — l'attribution par source du journal SMAPI, les packs Profiler
`[BigLoop]` (D1), le `[OPTIMIZER CONFIG]` du SLO (D2). Ces deux mods
n'ajoutent pas un chemin vers l'attribution ; ils ajoutent des **formats de
rapport reconnaissables** et des diagnostics de premier parti que notre
écran peut *conduire* à lancer.

## 2. UltraSmooth — la boîte noire `us_trace`

Commandes : `us_toggle`, `us_trace start|stop|status`, `us_diag`,
`us_analyze`, `us_trim`, `us_stress`, `us_testfarm`, `us_ping`,
`us_coop_fps`…

- **Échantillonnage** : tampons circulaires de **3 600 frame-times + 3 600
  tick-times** (60 s à 60 fps) ; spike si frame **> 25 ms**, gardé au
  top-100 avec heure de jeu, lieu et détails.
- **Métriques** : FPS moyen (EMA `0.85/0.15`), **1 % low** = 99ᵉ
  percentile des frame-times (tri desc., index `count × 0,01` borné), pire
  frame, tick CPU moyen/pic, tick 10-min du jeu (`ClockTickOptimizer`),
  tas managé (Mo), compteurs GC Gen0/1/2 **cumulatifs** depuis `Start()`.
- **Le rapport** (`GenerateReport`) : cinq sections — `[1. HARDWARE &
  DISPLAY ENVIRONMENT]` (Hz détectés par `DisplayHzDetector`, cœurs,
  VSync, timestep variable), `[2. PERFORMANCE & LATENCY METRICS]`,
  `[3. MEMORY & GARBAGE COLLECTION]`, `[4. RECORDED SPIKE EVENTS]`
  (top 8, `" [1] 42.3ms Spike | Frame Render Hitch"`), puis
  `[5. AUTOMATIC ROOT CAUSE ISOLATION & DIAGNOSIS]` — **trois règles
  fixes** : tick 10-min > 25 ms → `performTenMinuteClockUpdate`
  surchargé ; tick moyen > 12 ms ou pic > 25 ms → « autres mods C# lourds
  sur le tick » ; pire frame > 35 ms **et** pic tick < 10 ms →
  « GPU / VSync stall » ; sinon « SYSTEM HEALTHY ».
- **Sorties** : le bloc entier va au **journal SMAPI** (Info, donc sous la
  source `[UltraSmooth]`) **et** dans un fichier
  `UltraSmooth_TraceReport_AAAA-MM-JJ_HH-mm-ss.txt` écrit dans le dossier
  du mod (`Task.Run`, échec warné). `us_diag` = le même rapport sur la
  fenêtre roulante, sans session.

## 3. SDV-Radiance — l'attribution honnête « ours / not ours »

- **`FrameCost`** : 14 parties nommées (`ShadowPrepare` …
  `ReliefNormals`), 12 compteurs (bakes, misses, evictions, flushes…),
  fenêtre roulante de **300 frames**, frames **sans focus comptées à
  part** (`UnfocusedFramesInWindow`) — les 6 frames les plus longues
  retenues, chacune avec : total, « ours », « not ours », top 3 des
  parties, **deltas GC de la frame**, lieu, heure de jeu, `arrival+N`
  (frames depuis l'entrée dans le lieu — le travail d'arrivée est attendu)
  et `WhatTheGameWasDoing()` ∈ {loading, not in world, warping, cutscene,
  menu, playing}. Frames **≥ 250 ms** comptées à part (`_hugeFrames`).
- **`GpuTimer`** : vraies requêtes de timer OpenGL (`GL_TIMESTAMP`,
  ring de 4, latence 3) par partie **et** par étage de pipeline, via
  P/Invoke ; leur propre mise en garde : *« treat any single GPU row that
  matches its neighbour to the digit as suspect »*.
- **`PerfHud`** : affichage à l'écran — frame entière, « this mod » en %,
  chaque partie en ms CPU **et** GPU.
- **`PhaseCost`** : phases nommées génériques, `"N time(s)  avg X ms
  worst Y ms"`, triées par coût.
- **`radiance_report`** → `~/Documents/Radiance-Dumps/radiance-report.txt`
  : horloge de frame et état du device (avec des mises en garde honnêtes
  sur `IsContentLost`/OpenGL), réglages verbatim, vérification des
  labels, ombres, eau, chaîne d'effets, et la table `ours/not ours`
  (`DescribeLongestFrames`). `radiance_screenwatch` trace la passe de
  rendu **par écran** (60 appels par défaut — détection du ping-pong de
  caméras en split-screen). `radiance_debug` : 16 canaux de surcouche
  **visuels** (water, normals, lampshadow, flood…), rien de textuel.

## 4. Ce que StarHubFR en tire

1. **Pas d'attribution croisée à espérer de ces deux-là** — D1/D2 restent
   les bons plans ; rien à changer.
2. **Reconnaître pour conduire** ([[a-diagnostic-screen-must-conduct]]) :
   les marqueurs `ULTRA SMOOTH — LAG TRACE DIAGNOSTIC REPORT` /
   `RECENT 60-SECOND LAG DIAGNOSTIC REPORT` dans le journal, et la
   présence de Radiance, sont reconnaissables par notre parseur existant
   (attribution par source). Un jour où la carte perf croise l'un d'eux,
   le geste utile est **de donner la commande** : « `us_trace start`,
   rejouez le lag, `us_trace stop` » ou « `radiance_report` puis joignez
   `Radiance-Dumps/radiance-report.txt` » — leurs rapports sont meilleurs
   que tout ce qu'on pourrait re-mesurer de l'extérieur.
3. **Des seuils publiés et mesurés** à comparer aux nôtres quand la carte
   perf existante posera les siens : spike 25 ms (UltraSmooth),
   frame énorme 250 ms (Radiance), et les trois règles de la section [5]
   — dont la pointe de 10 minutes, le même motif que vise D2.
4. **`arrival+N`** (Radiance) est une idée à garder : distinguer le coût
   d'arrivée dans un lieu du coût de croisière — directement applicable
   à notre carte « impact d'un mod » si elle mesure par lieu.
