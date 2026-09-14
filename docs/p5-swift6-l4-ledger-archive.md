# Archive du chantier P5-L4 — les trois clients réseau/process

*Copié du ledger SDD le 2026-09-14 à la clôture du chantier (source git-ignorée
`.superpowers/sdd/2026-09-14-p5-swift6-l4/`, désormais supprimable). Plan :
`docs/superpowers/plans/2026-09-14-p5-swift6-l4.md`, spec :
`docs/superpowers/specs/2026-09-13-p5-swift6-design.md` §L4 (locaux, gitignorés).
Résultat : 216/83 bloquants après L3 → **121/28 après L4** — 55 tombés, exactement
les 55 ciblés (la spec en annonçait 60, chiffre d'avant L3). `SmapiInstaller`
25 → 0 (façade `@MainActor`), `SmapiUpdateClient` 22 → 0 (types traversants
`Sendable`, X87 intact), `NexusUpdateChecker` 8 → 0 (complétions `@Sendable`).*

**Trois enseignements** — détaillés dans les entrées ci-dessous et résumés au §9
de `REFACTORING.md` : une passe stricte tuée **sous-compte en silence** (12
fichiers couverts sur 17, compte intermédiaire faux de 3) ; un type **public**
casse l'inférence `Sendable` d'un type interne à un maillon de distance
(`NexusInstallFacts` → `Blocked` → `Target`) ; un **relais** de complétion se
type `@MainActor @Sendable`, sinon la dette migre dans les vues.

⏳ **Vérification GUI due par l'auteur à la clôture** : installation SMAPI réelle
→ désinstallation → réinstallation (Step 7 de T1 — le seul chemin qu'aucun des
3 183 tests ne couvre).

---

# SDD ledger — plan: docs/superpowers/plans/2026-09-14-p5-swift6-l4.md

Spec: docs/superpowers/specs/2026-09-13-p5-swift6-design.md §L4 (l. 223-233)
(lue). ⚠️ La spec traîne sur les chiffres : elle annonce 60 bloquants, la
mesure doublement vérifiée du 2026-09-14 tranche **55** (25+22+8 sur 83).
Rulings hérités des tranches L1-L3 (ledgers archivés dans docs/) : R2
(--update visible), R5 (mesure finie avant toute édition de source — fait,
deux passes 216/83 reproductibles), R8 (revue de N en parallèle de N+1 si
fichiers disjoints), R9 (jamais deux implémenteurs en parallèle), R10 (jamais
de --amend), R11 (revues par subagents de cette session), R12 (attribution
GLM 5.3, vérifier avec l'implémenteur).
Ruling (hérité Ruling 1 L1-L2) : exécution sur `main` sans worktree —
CLAUDE.md l'impose, convention constante du dépôt.

## Pre-flight scan — paires de tâches partageant un fichier ou une interface

| Tâches | Ce qui est partagé | Trouvé |
| --- | --- | --- |
| T1 × T2 × T3 | les trois fichiers cibles sont **disjoints** (SmapiInstaller / SmapiUpdateClient+Models / NexusUpdateChecker) | le VM est « au plus » touché par chacun : T1 commentaire :1959-1969, T2 site :3559 si migration, T3 appelants si migration — régions disjointes, R8 s'applique (revue de N en parallèle de N+1). Correctif de revue + édition concurrente = régions disjointes, se pose après |
| T1 × T2 | `StarHubTHViewModel.swift` possible des deux côtés | T1 : région :1959 (commentaire) ; T2 : région :3559 (si le diagnostic migère). Disjointes — R8 tient |
| T3 × T1/T2 | aucun fichier commun | NexusUpdateChecker seule ✓ |
| T4 × T1-T3 | docs + mesure finale | T4 après tout le monde ✓ |
| Ordre imposé | T1 d'abord (le plus gros, le pire chemin — découverte tôt) | plan le dit ✓ |

## Pre-flight scan — auto-cohérence de chaque tâche

| Tâche | Vérifié | Trouvé |
| --- | --- | --- |
| T1 | les 14/11 hops cités vs code lu intégralement | ✓ (remesure critique : ventilations corrigées) |
| T1 | `nonisolated static` sur runOfficialInstaller/resolveLatest : tout membre d'instance ? | ✓ un seul (`onWarning` :536) — sort en callback |
| T1 | appelants install/uninstall/onWarning/@Published | ✓ tous MainActor (VM :2002/:3052/:3062, vues en lecture) — zéro migration attendue |
| T2 | types traversants : membres tous Sendables ? | à faire par l'implémenteur (leçon Ruling 7) — le brief l'exige |
| T2 | X87 : engage/clearInFlight intouchés | ✓ le canevas ne les touche pas ; filet au nom exact (Tests:326) |
| T3 | payloads vérifiés par grep | ✓ (remesure critique : SingleFetchResult, pas ModUpdate) |
| T1×T2×T3 | la baisse des trois fichiers peut-elle masquer une hausse chez les appelants ? | la mesure GLOBALE fait foi (83 → ~28 attendu) — écrit dans les contraintes et relue à chaque Step mesure |
| T4 | « NN/MM bloquants » placeholder | assumé : tâche de mesure, les chiffres se remplissent à l'exécution |

Ruling (remesure critique, avant dispatch) : SmapiInstallerAction gagne
`Sendable` explicite dans T1 — public enum = jamais d'inférence. Le brief T1
le porte. Coût si faux : un diagnostic neuf à T1, rattrapé dans la tâche.

## Journal d'exécution

BASE T1: 7275082b
T1: DONE_WITH_CONCERNS — commit 9c1546b1 (4 fichiers, +119/-59). Gate EXIT=0,
  3183/318 suites vertes, passe stricte 83 -> 58 (-25), SmapiInstaller 25 -> 0,
  VM 11 -> 11 (zéro migrant, diff des logs vérifié).
T1: cinq réserves à verdicter en revue : (1) defer tempRoot préexistant
  (hors périmètre, porté à l'auteur) ; (2) onWarning ne part plus que du main
  actor (bug latent corrigé au passage — fidélité vs correction, à verdicter
  SUR LE CODE) ; (3) erreur de MON dispatch (~26 vs -25) tranchée par
  l'implémenteur en faveur du brief — mesure a tranché : 58 ✓ ; (4) quatre
  helpers statics passés nonisolated + hops success d'install/uninstall
  (requis pour compiler, sémantique à vérifier) ; (5) Step 7 GUI à l'auteur.
T1: revue — conformité ✅ (10/10 points, cliquet décompté à l'unité +56 = 47+9,
  dispatch_queue 147->133), qualité approuvée, 0 critique / 0 important /
  3 mineurs. Les 5 réserves + 2 divergences VALIDÉES SUR LE CODE : onWarning
  neutre (l'ancien chemin était déjà défendu par le garde interne de log(),
  la justification du rapport était fausse — finding mineur), 4 nonisolated
  exigés par le compilateur (statiques d'une classe @MainActor, tous purs),
  ordre des hops préservé (seul écart : second hop sur les complétions du VM,
  invisible à l'UI), defer/commentaire intacts conformes au périmètre,
  Step 7 GUI correctement reporté à l'auteur.
T1: minor (deferred): la justification de la réserve 2 dans task-1-report.md
  dit un défaut latent qui n'existait pas (log() guardait déjà) — le rapport
  ment, pas le code.
T1: minor (deferred): commentaire :426-429 surestime le defer tempRoot —
  à corriger dans la même future tranche que le defer lui-même.
T1: minor (deferred): le defer de tempRoot s'exécute désormais sur le main
  thread (ENOENT avalé, coût nul) — dossier tempRoot pour l'auteur.
T1: complete (commits 7275082b..9c1546b1, review clean) — clôture FORMELLE
  après Step 7 (installation réelle SMAPI par l'auteur, à la clôture de
  tranche, comme L2/L3).
BASE T2: 9c1546b1
T2: dispatchée (implémenteur, pipeline R8 : revue T1 en parallèle — fichiers
  disjoints).
T2: ⚠️ implémenteur perdu entre la passe stricte et la remise — aucun rapport,
  édits non committés, gate et tests jamais lancés. La session reprend en
  direct (pas de re-dispatch) : revue du diff + gate + tests + rapport écrits
  par elle (`task-2-report.md`, section « reconstitué »).
T2: DONE — commit aac4dd40 (6 fichiers, +44/-23). Gate EXIT=0 (deux passes,
  la seconde après ajout d'un commentaire), 3183 tests / 318 suites verts,
  X87 `anOverlappingCallWaitsItsTurnAndTheSlotIsReturned` vert par son nom.
  Passe stricte 58 -> 33 (-25, pas -22) : SmapiUpdateClient 22 -> 0 + en prime
  ModInstallView 2 et ModConfigBackupsView 1, consommateurs des types devenus
  Sendable. VM 11 -> 11 : zéro migration.
T2: X87 prouvé par le diff, pas seulement par le test : aucun hunk ne traverse
  SmapiUpdateClient.swift:112-130 (engage/clearInFlight/inFlightLock).
T2: divergence 1 (VERDICTÉE, acceptée) : `Models/NexusUpdateCheck.swift` n'était
  pas dans les Files du brief et gagne `SmapiResultBox: @unchecked Sendable` —
  le diagnostic a migré d'un cran plus loin que prévu, jusqu'à la composition
  qui injecte `fetch`. Boîte = bon geste pour une tranche d'annotations.
  Clause de renvoi ajoutée au commentaire : `pathoschildFetchFailed` porte le
  même argument et reste un `var` nu (sa complétion ne traverse pas de
  frontière `@Sendable`) — sinon l'asymétrie piège le prochain lecteur.
T2: divergence 2 (constat) : les deux hops du VM sont des **seconds** hops —
  le client appelle déjà progress/completion depuis `await MainActor.run`
  (:241, :281, :298). Même écart que la revue T1 avait validé.
T2: minor (deferred) : :3598 est le premier hop posé sur un flux **répété**
  (les précédents L2/T1 n'enveloppaient que du one-shot). Les Task non
  structurés ne sont pas FIFO en théorie ; en pratique l'enfilement part du
  main actor. Option plus fidèle si l'auteur la veut : `MainActor.assumeIsolated`.
T2: ⚠️ écart d'arithmétique à porter en T4 : la tranche efface 55 ciblés **+ 3
  consommateurs** = 58. Le jalon final attendu est donc ~25, pas les ~28 du
  plan. « 55 mesurés, 55 partis » de la ROADMAP sera faux — à réécrire.
BASE T3: aac4dd40
T2: ⚠️⚠️ **CORRECTION DU RELEVÉ T2 — la mesure `/tmp/p5-l4-t2` était TRONQUÉE.**
  Le processus avait été tué (pas de binaire `probe`) et le journal ne couvre
  que **12 fichiers sur 17-18** : `ModInstallView` n'y apparaît **pas une seule
  fois**, ni en bloquant ni en avertissement simple. Le pied de page des URL de
  diagnostic était bien là — il ne prouve donc rien sur la complétude. Les « 33
  bloquants, −25, ModInstallView et ModConfigBackupsView en prime » sont **faux**.
  Le vrai delta T2 est **−22** (SmapiUpdateClient seul), soit **36** après T2 —
  exactement ce que le brief prévoyait. Arithmétique recoupée par T3 : 36 − 8
  (checker) + 4 (migrants VM) = 32, la mesure t3 complète (exit=0, probe présent).
  ⚠️ Le message du commit `aac4dd40` porte l'erreur ; pas de `--amend` (R10) —
  la correction vit ici et dans les docs de T4.
T3: édité (checker : 2 completions `@Sendable`, 8 hops intouchés ; VM : 3 sites
  migrés enveloppés en `Task { @MainActor in }`), gate exit 0, cliquet assumé
  (VM 9959 -> 9975, +16), tests 3183/318 verts, passe stricte /tmp/p5-l4-t3 :
  exit=0, 125 avert., **32 bloquants**, 532 s. NexusUpdateChecker 8 -> 0.
T3: MIGRATION TRAITÉE DANS LA TÂCHE (contrainte globale) : le hop de
  `fetchNexusFallback` faisait naître 4 bloquants neufs au VM (capture/sending
  de `NexusFallbackCheck.Target` et `[Target]`). Cause : `NexusInstallFacts`
  (`Models/ModVersionAnchor.swift:57`) est **public** — jamais de Sendable
  implicite (règle §9) — et casse la chaîne `Target` -> `Blocked` -> lui.
  Conformité explicite ajoutée ; remesure en cours.
T3: décision d'idiome : `fetchMetadata` prend `@MainActor @Sendable` (voir
  `task-3-report.md`) — sans quoi la dette migrait dans `ModDetailView`, qui
  écrit un `@State` dans cette complétion.
T3: DONE — commit 1fbf4ad7 (4 fichiers, +44/-28). Passe stricte **complète**
  `/tmp/p5-l4-t3b` : exit=0, probe présent, 121 avert., **28 bloquants**, 590 s.
  NexusUpdateChecker 8 -> 0, VM revenu à 11 (les 4 migrants guéris), seul
  `NexusFallbackCheck.swift` disparaît du relevé — le fichier guéri. Gate exit 0,
  3183 tests / 318 suites verts.
T4: mesure finale = celle de T3b (aucune édition de source depuis). Arithmétique
  à l'unité : 83 (ouverture L4) -25 (T1) -22 (T2) -8 (T3) = **28** ✓ — les 55
  ciblés, ni plus ni moins. Le « +3 consommateurs » annoncé à T2 était un
  artefact de mesure tronquée, pas une découverte.
T4: docs écrites (REFACTORING.md §9 : ligne de tableau + paragraphe de clôture
  avec les trois enseignements ; ROADMAP.md : case P5) et ledger archivé dans
  `docs/p5-swift6-l4-ledger-archive.md`.
T4: ⏳ RESTE : vérification GUI de T1 par l'auteur (installation SMAPI réelle →
  désinstallation → réinstallation). La tranche n'est formellement close
  qu'après son verdict — comme L2 et L3.

---

# Rapport Task 1 — P5-L4 : `SmapiInstaller` façade `@MainActor`

**Statut : DONE_WITH_CONCERNS** (livré au commit ; la vérification GUI — Step 7 — reste à l'auteur, conformément à la résolution 1).

**Commit : `9c1546b1`** sur `main`, au-dessus de la BASE `7275082b`. Un seul commit,
aucun `--amend`, aucun push (non demandé). Trailer exact :
`Co-Authored-By: GLM 5.3 <noreply@z.ai>`.

## Ce qui a été fait

1. **`StarHubTH/SmapiInstaller.swift`** (561 → 608 lignes) :
   - `@MainActor final class SmapiInstaller: ObservableObject` avec le doc
     comment du brief **recopié verbatim** (Step 2).
   - Les **14 hops** `DispatchQueue.main.async` → `Task { @MainActor in }`
     (2 dans les closures de résolution d'`install`/`uninstall`, 12 dans le
     callback `downloadTask`).
   - `@escaping @Sendable (Bool, String, String?) -> Void` sur les 5
     complétions (`install`, `uninstall`, `downloadAndRunInstaller`,
     `runOfficialInstaller`, `resolveLatestSmapiInstallerURL`).
   - `runOfficialInstaller` et `resolveLatestSmapiInstallerURL` sortent en
     `private nonisolated static func` (signatures du brief) ; le warning
     marqueur d'écriture traverse en valeur par le nouveau paramètre
     `onVersionMarkerWriteFailure: @escaping @Sendable (String) -> Void`,
     ré-injecté au site d'appel par `{ message in Task { @MainActor in
     self.onWarning?(message) } }`. Le corps de `runOfficialInstaller`
     (boucle bornée, `Process`, timeouts, verdicts) est inchangé ; celui de
     `resolveLatestSmapiInstallerURL` est inchangé.
   - **Ajout hors liste du brief (nécessaire)** : `nonisolated` sur les 4
     helpers statiques `posixLocaleEnvironment()`, `downloadSession()`,
     `classify(_:)`, `lastMeaningfulLine(of:)`. L'annotation de classe
     isole **aussi les statiques** au main actor ; or ils sont appelés
     depuis les callbacks de fond — sans le mot-clé, le fichier ne
     compile pas (« call to main actor-isolated static method … in a
     synchronous nonisolated context »). Chacun porte son commentaire de
     raison (résolution 6).
2. **`StarHubTH/Models/SmapiInstallerInvocation.swift`** :
   `SmapiInstallerAction: String, Sendable` + commentaire (type public, pas
   d'inférence — capture dans les closures `@Sendable` du flux sinon
   diagnostiquée). Le fichier vit aussi dans le paquet Core
   (`Package.swift:37`) : l'ajout y est source-compatible, suites vertes.
3. **`StarHubTH/StarHubTHViewModel.swift`** (9946 → 9955 lignes) :
   - Commentaire :1965-1969 mis à jour (une phrase de raison, la classe du
     VM est `@MainActor` depuis L2, 2026-09-13 ; le `nonisolated init()` de
     `KeybindScanService` n'est plus ce dont l'appel dépend — il est
     conservé tel quel, hors périmètre).
   - **Migration appelants (résolution 5)** : les corps des closures de
     `installSmapi()`/`uninstallSmapi()` passent en hop
     `Task { @MainActor in }` — devenues `@Sendable`, leurs appels aux
     méthodes MainActor du VM ne compilaient plus. **Aucun nouveau
     bloquant strict en sortie** (preuve ci-dessous).
4. **Cliquet** : `python3 check_standards.py --update` après premier gate —
   diff visible : `file:SmapiInstaller.swift` 561 → 608,
   `file:StarHubTHViewModel.swift` 9946 → 9955,
   `oversized_excess_lines` 25 763 → 25 819 (les seules lignes ajoutées),
   **plus** deux gains resserrés : `dispatch_queue` 147 → 133 (−14, les
   hops convertis) et `non_final_classes` 5 → 4.

## Chiffres

| Mesure | Avant | Après |
|---|---|---|
| Passe stricte globale (`bloquants_swift6`) | **83** (`/tmp/p5-l4-t0`, 562 s, exit 0, 0 erreur) | **58** (`/tmp/p5-l4-t1`, 516 s, exit 0, 0 erreur) |
| `SmapiInstaller.swift` | 25 (14 × sending 'self' + 11 × completion) | **0** — sort de la liste |
| `StarHubTHViewModel.swift` | 11 | 11 — **mêmes diagnostics**, seuls les numéros de ligne glissent (+1 puis +9 = mes insertions) ; diff des deux logs vérifié |
| Gate `python3 build_app.py` | — | exit 0 (2ᵉ passe ; la 1ʳᵉ compile à 0 erreur et s'arrête sur le cliquet, comme prévu) |
| `./run_tests.sh` (DEVELOPER_DIR Xcode) | — | exit 0 — **3183 tests / 318 suites passés**, 0 échec |

La baisse globale est exactement **−25**, l'attendu du brief (« le total
global baisse d'environ 25 »). L'attente « ~26 après T1 » donnée par le
contrôleur était incompatible avec le brief ; la mesure a tranché pour le
brief — les 58 restants sont les fichiers des tâches suivantes
(`SmapiUpdateClient` 22, VM 11, `NexusUpdateChecker` 8, …).

## Divergences au brief

1. `git add` inclut `StarHubTH/Models/SmapiInstallerInvocation.swift` — le
   Step 1 du brief l'exige mais le canevas du Step 6 l'omet de la liste.
2. Les 4 helpers statiques passent `nonisolated` (voir 1. — non nommés par
   le brief, requis par la portée de l'annotation de classe).
3. Les chemins **success** d'`install`/`uninstall` gagnent un hop
   `Task { @MainActor in }` autour de `downloadAndRunInstaller` — ce n'est
   pas un hop `DispatchQueue` préexistant : la méthode, MainActor-isolée,
   est appelée depuis une closure `@Sendable` hors acteur. Sémantique
   inchangée (elle ne fait que créer et démarrer le `downloadTask`).
4. Les deux hops d'appelants du VM (voir 3.) sont une migration de plus que
   le texte du brief, mandatée par la résolution 5 — payée à 0 nouveau
   bloquant strict.
5. Une passe de référence stricte (`/tmp/p5-l4-t0`) a été lancée **avant**
   les éditions pour attribuer proprement les écarts ; elle a fini juste
   après un `pkill` de ma part (collision de timing, log complet et exit 0 —
   chiffres fiables). Le brief ne la demandait pas.

## Réserves

1. **`defer { removeItem(tempRoot) }` (:235) part avant le travail** —
   comportement **préexistant préservé au caractère près** : le `defer`
   s'exécute à la sortie de `downloadAndRunInstaller`, donc avant même la
   fin du download ; le callback recrée ensuite `tempRoot`, et le dossier
   `smapi_install_<uuid>` fuit dans `NSTemporaryDirectory` après un succès.
   Le commentaire conservé dans la closure de complétion (« le temp est
   nettoyé par le defer… ») décrit une portée que le defer n'a pas. Hors
   périmètre ici (isolation seulement), mais candidat naturel pour une
   tranche de fond.
2. **`onWarning` ne part plus que du main actor** — correction silencieuse
   d'un défaut latent : avant, il était invoqué depuis le thread de fond
   (`runOfficialInstaller` tournait dans le callback), donc `self?.log`
   touchait du `@Published` hors main. À savoir pour la vérification GUI.
3. **Ordonnancement des hops** : `Task { @MainActor in }` au lieu de
   `DispatchQueue.main.async` — FIFO préservé à l'intérieur du flux (tous
   les hops sont devenus des Tasks) ; l'ordre relatif Task/DispatchQueue
   n'est pas garanti entre mécanismes, invisible à l'UI ici.
4. Le `nonisolated init()` de `KeybindScanService` est probablement
   devenu superflu (VM `@MainActor`) — non retiré, hors périmètre ; le
   commentaire mis à jour le documente honnêtement.
5. **Step 7 non joué** : l'installation/désinstallation/réinstallation SMAPI
   réelle reste à l'auteur — la tâche n'est **complete** qu'après son
   verdict (le trou de couverture est connu : aucun test ne touche
   `SmapiInstaller` en direct).

---

# T2 — rapport (reconstitué par la session d'orchestration)

⚠️ **L'implémenteur T2 n'a pas rendu de rapport** : il s'est arrêté entre la
passe stricte (`/tmp/p5-l4-t2`, 11:00) et la remise. Les édits étaient dans
l'arbre de travail, non committés, gate et tests non lancés. Ce rapport est
écrit par la session à partir du diff et des mesures relancées — pas recopié
d'un implémenteur.

## Ce que le diff fait (6 fichiers, +39/-23)

| Fichier | Changement |
| --- | --- |
| `SmapiUpdateClient.swift` | `Failure: Sendable`, `Outcome: Sendable`, `progress`/`completion` de `fetch` et `runFetch` deviennent `@Sendable` |
| `Models/SmapiUpdateRequest.swift` | `Entry: Sendable` |
| `Models/SmapiUpdateResponse.swift` | `Version`/`Metadata`/`Mod`/`Blocker: Sendable` |
| `Models/NexusUpdateCheck.swift` | **hors liste du brief** : `run(smapiFetch:progress:)` porte les `@Sendable` jusqu'au site d'appel ; `var smapiResult` devient une boîte `SmapiResultBox: @unchecked Sendable` |
| `StarHubTHViewModel.swift` | deux touches d'état passent par `Task { @MainActor in }` (site :3576 completion, :3598 progression) |
| `.standards-baseline.json` | VM 9955 → 9959 (+4 lignes des deux hops), `oversized_excess_lines` +4 |

## Vérifications

- **Gate** : `python3 build_app.py` → **exit 0** (lu directement), cliquet
  « aucune violation nouvelle ». Log `/tmp/p5-l4-t2-gate.log`.
- **Passe stricte** `/tmp/p5-l4-t2` : 120 avertissements, **33 bloquants**,
  0 erreur — contre 160/58 après T1. **−25**, pas −22.
- **Ventilation** : `SmapiUpdateClient` 22 → **0** ; en prime
  `ModInstallView` 2 → 0 et `ModConfigBackupsView` 1 → 0 — ils consomment
  les types devenus Sendable. **Le VM reste à 11** : zéro migration, la
  « fausse victoire » des contraintes globales est écartée.
- **X87 intouché, prouvé par le diff** : les hunks de `SmapiUpdateClient`
  tombent en :34-37, :58-61, :134-137, :171-175. `engage`, `clearInFlight`,
  `inFlight`, `inFlightLock` vivent en :112-130 — **aucun hunk ne les
  traverse**. Preuve plus forte qu'un test vert.
- ⚠️ La passe stricte t2 n'a **pas** laissé de binaire `probe` : elle a été
  tuée à l'édition de liens. Les diagnostics sont complets (le pied de page
  des URL de diagnostic est présent, et la ventilation par fichier se
  reconstitue à l'unité : 11+8+6+2+2+1+1+1+1 = 33), le compte est donc
  utilisable ; la mesure propre revient à T3.

## Divergences au brief — à verdicter

1. **Un fichier non listé gagne une classe `@unchecked Sendable`.**
   `Models/NexusUpdateCheck.swift` n'est pas dans les *Files* de T2 ;
   `SmapiResultBox` y est un type neuf, en Core. Le brief prévoyait « au
   plus le VM si le diagnostic migre » — il a migré d'un cran plus loin,
   jusqu'à la composition qui injecte `fetch`. La boîte est le bon geste
   pour une tranche d'annotations (restructurer le `DispatchGroup` serait
   hors périmètre), mais elle mérite un verdict écrit, pas le silence.
   **Asymétrie à connaître** : `pathoschildFetchFailed`, deux lignes plus
   haut, porte le *même* argument de sûreté et reste un `var` nu — seule la
   complétion smapi.io traverse une frontière `@Sendable`.
2. **Les deux hops du VM sont des *seconds* hops.** Le client appelle déjà
   `progress` et `completion` **depuis** `await MainActor.run { … }`
   (`SmapiUpdateClient.swift:241`, `:281`, `:298`). Le `Task { @MainActor in }`
   ajouté ne fait donc pas monter sur le main : il **diffère d'un tour** un
   appel déjà sur le main. C'est exactement l'écart que la revue T1 avait
   validé (« second hop sur les complétions du VM, invisible à l'UI »).
   L'ordre porteur `setProgress(nil)` **puis** `completion(result)` est
   préservé — les deux lignes sont dans le même `Task`.
3. **Premier hop sur un flux répété.** Les précédents L2/T1 (VM :3058,
   :3070) n'enveloppaient que des complétions **one-shot** ; :3598 est une
   **progression répétée**. Les `Task` non structurés vers un acteur ne sont
   pas FIFO *en théorie* — un compteur pourrait reculer. En pratique
   l'enfilement se fait depuis le main actor lui-même et l'ordre tient.
   Option plus fidèle si l'auteur la préfère : `MainActor.assumeIsolated`
   (synchrone, contrat garanti par le `MainActor.run` du client, mais
   fatal si le contrat change un jour). **Laissé tel quel** : cohérence
   avec T1 déjà revue. Mineur consigné, pas un blocage.

---

# T3 — rapport (exécuté en direct par la session, sans implémenteur dispatché)

## Ce que le diff fait

| Fichier | Changement |
| --- | --- |
| `NexusUpdateChecker.swift` | `fetchAccount(completion:)` et `fetchSingleMod(modId:completion:)` prennent des callbacks `@Sendable`. **Les huit hops `DispatchQueue.main.async` ne bougent pas** — conforme au brief. Aucune conformité `Sendable` à ajouter : `NexusAccount` la portait déjà (tranche antérieure), `NexusModExtra`, `NexusModFile` et `SingleFetchResult` sont **internes** et l'inférence s'applique (tous membres en types de valeur). Le brief prévoyait des conformités explicites : elles se sont révélées inutiles. |
| `StarHubTHViewModel.swift` | les **trois** sites appelants migrés passent par un hop `Task { @MainActor in }` : `refreshNexusAccount` (:3494), `fetchNexusFallback` (:3950), `fetchMetadata(forNexusModId:)` (:4810). |

## La décision de T3 : `@MainActor @Sendable` sur `fetchMetadata`

`fetchMetadata` est un **relais** : sa propre `completion` est appelée dans la
complétion devenue `@Sendable`. La rendre simplement `@Sendable` aurait fait
migrer le diagnostic **dans les vues** — `ModDetailView:872` écrit un `@State`
(`fetchStatus`) dans ce corps. C'est exactement la « fausse victoire » que les
contraintes globales interdisent.

Remède retenu : `completion: @escaping @MainActor @Sendable (…)`. La garantie
« invoquée sur la queue principale » que le commentaire portait **déjà** devient
une garantie de type ; les deux vues appelantes (`ModDetailView`,
`ModInstallView:1078`) et le site interne `:5366` ne changent pas d'une ligne et
gardent une complétion **synchrone**. ⚠️ **Idiome neuf dans le dépôt** : zéro
`@MainActor` sur un paramètre closure avant celui-ci (relevé par grep).

Option écartée : `MainActor.assumeIsolated` aux sites appelants. Elle rendrait
la fidélité au caractère près, mais `fetchNexusFallback` est **récursive dans sa
complétion** — la rendre synchrone supprimerait les tours de main que la boucle
de reprise (jusqu'à ~900 mods) rend aujourd'hui entre deux pages. Retirer des
respirations est un écart plus grand qu'en ajouter une.

## Vérifications

- **Gate** : compilation + édition de liens + signature OK ; le cliquet a
  refusé l'ajout (VM 9959 → 9975, +16 lignes de hops et de justification),
  assumé par `check_standards.py --update` (Ruling 2), visible dans le diff.
- **Passe stricte** `/tmp/p5-l4-t3` : voir le journal d'exécution du ledger.
- **Tests** : voir le journal d'exécution du ledger.
