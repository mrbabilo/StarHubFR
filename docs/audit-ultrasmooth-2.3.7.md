# Audit — UltraSmooth 2.3.7 *(2026-09-26)*

Suite de [`audit-perf-analyzers.md`](audit-perf-analyzers.md), qui lisait la
2.1.3. **Aucun code d'UltraSmooth ne tourne chez nous** : le mod n'a ni source
publique ni licence, rien n'en est repris. Ce document porte ce que la
lecture apprend — idées à refaire de zéro, mesures à ne pas croire, risques
pour le parc.

| | |
|---|---|
| **Identité** | `palmhacker13.UltraSmooth` · 2.3.7 · Nexus 50971 |
| **DLL** | décompilée par `ilspycmd` 10.1.1 : 99 fichiers, ~26 000 lignes (`ModEntry` 5 293, `DebrisOptimizer` 2 520, `HighFpsPacingEngine` 2 043) |
| **Parc** | actif ; 45 options `Enable*` à `true` sur 59, dont `ShowOverlay` (réglé par l'auteur) |
| **Confronté à** | la sonde `companion/StarHubFR.Probe` v0.2 et `harmony_summary`, sur le parc, la même nuit |

---

## 1. Ce que ses mesures mesurent vraiment

- **« CPU Tick Time »** va du gestionnaire `UpdateTicking` d'UltraSmooth à
  son `UpdateTicked` (`ModEntry.OnUpdateTicking` → `ProfilerEngine.OnTickStart`,
  `OnUpdateTicked` → `OnTickEnd`). SMAPI enchaîne les `UpdateTicking` de tous
  les mods, la mise à jour du jeu, puis les `UpdateTicked`
  (`SCore.cs:903-919`). La mesure couvre donc **la logique du jeu et les
  gestionnaires placés entre les deux siens** — pas SMAPI, pas la plupart des
  mods. D'où ses 0,5 ms quand la sonde voit 5 à 9 ms de mise à jour par
  tick. Constat utile, involontaire : **la logique du jeu seule est
  légère ; le coût est dans SMAPI et les gestionnaires des mods.**
- **« Last 60s »** = 3 600 trames ÷ 60 (`LagTraceRecorder`,
  `MaxRollingSamples`) : à 20 FPS, la fenêtre couvre trois minutes.
- **Les causes du §5** sont quatre textes figés déclenchés par des seuils ;
  « GPU presentation » se déduit d'un pic de trame isolé face à son tick
  mal mesuré. Sonde : l'affichage (`Present`) prend 10 ms, stable.
- **`us_analyze` « top slow mods »** n'enregistre que des sections internes
  d'UltraSmooth (`ModAnalyzer.Record("Update Loop", …)`,
  `"Game Save Serialization"`…). Aucun autre mod n'y entre.
- **Le banc avant/après** (`CaptureBaseline`/`CaptureAfter`) compare deux
  nombres : le FPS moyen et le temps d'**un seul** tick.
- **`SmartModGovernor`** ne gouverne rien : il lisse ce même tick et écrit un
  avertissement au-delà de 20 ms, en renvoyant vers `us_analyze`.
- **Rien ne signale la fenêtre sans focus.** MonoGame dort 20 ms par tick
  quand le jeu n'a pas le focus (`InactiveSleepTime`) ; un `us_diag` tapé
  après être sorti du jeu décrit ce sommeil (19,6 FPS mesurés le 2026-09-26,
  1 175 ticks sans focus sur 1 175 selon la sonde).

## 2. Idées à refaire de zéro

| Idée | Chez lui | À refaire ainsi |
|---|---|---|
| Pics avec contexte (heure de jeu, lieu, menu, météo) | `SpikeEvent`, seuil fixe 25 ms | seuil relatif (> 2 × la trame médiane) — sous VSync 60 Hz, 25 ms est franchi par chaque trame lente |
| Durée de l'horloge des 10 minutes | `ClockTickOptimizer`, pré/postfix sur `performTenMinuteClockUpdate` | même point d'accroche ; son compteur « Occurred 0x » est mort |
| Durée des changements de lieu | `RecordWarp` (nom seulement) | chronométrer le passage, par destination |
| Avant/après | deux nombres, un seul tick | comparer deux sessions de la sonde, fenêtres en temps réel |
| Contexte matériel | `DisplayHzDetector` (mode d'affichage de l'adaptateur), `SwapInterval`, pas fixe | en-tête de session de la sonde |

## 3. Risques pour le parc

1. **`DayTransitionOptimizer` saute `GameLocation.DayUpdate`** (préfixe,
   priorité 600) pour tout lieu sans objet, végétation, gros décor, débris,
   personnage ni animal (`IsDormantEmptyLocation`), actif par défaut
   (`EnableDayTransitionSlicing`). C'est `DayUpdate` qui fait repousser la
   cueillette (`spawnObjects`) et que surchargent des lieux spéciaux
   (`FarmCave` : fruits et champignons). **Un lieu entièrement ramassé
   risque de ne plus jamais se regarnir.** Mesure sur la sauvegarde de
   l'auteur : 183 lieux sur 362 remplissent la condition, dont `FarmCave`,
   `Custom_CrimsonBadlands`, `Custom_IridiumQuarry`,
   `Custom_GrampletonCoast`, `IslandSouthEastCave`. **Non prouvé en jeu** :
   la sauvegarde est au 16 printemps an 1 depuis le 2026-09-16, aucune nuit
   n'est passée depuis. À vérifier : dormir une nuit avec et sans l'option,
   et comparer un lieu vidé.
2. **`QueryCacheManager` met en cache `GameStateQuery.CheckConditions` pour
   la trame** en identifiant l'objet cible par son `ItemId` seul
   (`QueryKey.TargetItemId`, `InputItemId`). Deux objets de même
   identifiant mais de qualité, quantité ou prix différents, testés dans la
   même trame (`ITEM_QUALITY`, `ITEM_STACK`, `ITEM_PRICE`…), reçoivent la
   réponse du premier. `RANDOM` est exclu ; le reste non.
3. **GC forcés** : `SafeWindowMemoryManager` lance un GC complet bloquant
   compactant, deux fois, en fin de journée (fenêtre sûre, écran de
   sauvegarde) ; et **à chaque changement de lieu** un GC de génération 1
   dès que le tas dépasse 800 Mo — le tas du parc en fait ~3 000, donc à
   chaque fois. `GcCoordinator` en demande d'autres, bornés par un délai : génération 0
   au plus toutes les 30 s dans un dialogue, une lettre ou une boutique,
   toutes les 20 s aux changements de lieu et avant la sauvegarde ;
   génération 1 toutes les 15 s hors partie. À côté,
   Stardropium passe le GC en `SustainedLowLatency` : deux mods tirent le
   même levier en sens contraires.
4. **Il patche le code d'autres mods** — contrairement à la 2.1.3 :
   `ContentPatcher.ModEntry.OnUpdateTicked`, Alternative Textures, SpaceCore
   (`TextureAnimation`), Movement Overhaul, Lots of Kisses
   (`HighFpsPacingEngine`), Radiance et Nature in the Valley
   (`UiOverlaySmoother`), Campgrounds. En mode « Standard » (celui du parc),
   `IsPacingActive` est faux et ces préfixes laissent passer : coût d'appel
   seulement. En mode « Unlimited », ils **sautent** des mises à jour de
   Content Patcher et d'autres selon la cadence.
5. `ShowOverlay` actif : le profileur interne et le calque tournent à chaque
   trame.

Sans risque relevé : `FastSaveEngine` (chronomètre la sauvegarde et demande
un GC), `SmartModGovernor` (journal seulement).

## 4. Ce que StarHubFR en retient

- **D2-T2 (lire `us_trace`) est à abandonner** : ses chiffres centraux sont
  faux ou mal nommés, et la sonde donne les mêmes FPS (51,0 ms contre
  51,01 ms sur la même minute) avec un découpage juste.
- Les idées du §2 entrent dans la sonde v0.3.
- Les risques 1 et 2 sont des signalements à faire à l'auteur, après
  vérification en jeu — pas des corrections à faire chez nous.
