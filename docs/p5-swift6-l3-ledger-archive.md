# Archive du chantier P5-L3 — les boucles disque en Core

*Copié du ledger SDD le 2026-09-14 à la clôture du chantier (source git-ignorée
`.superpowers/sdd/2026-09-13-p5-swift6-l3/progress.md`, désormais supprimable).
Plan : `docs/superpowers/plans/2026-09-13-p5-swift6-l3.md`, spec :
`docs/superpowers/specs/2026-09-13-p5-swift6-design.md` §L3 (locaux, gitignorés).
Résultat : 237/85 bloquants après L2 → 216/83 après L3 ; l'exécution des boucles
testée en Core pour la première fois (8 tests disque) ; le rescan plein parc rendu
au fond (gel UI attrapé en revue, corrigé avant fusion).

---

# SDD ledger — plan: docs/superpowers/plans/2026-09-13-p5-swift6-l3.md

Spec: docs/superpowers/specs/2026-09-13-p5-swift6-design.md §L3 (l. 201-222) (lue)
Base: c10a4fe3 (main, arbre propre, L1+L2 closes et poussées, CI verte)
Héritage des rulings de la tranche L1-L2 (voir
`docs/p5-swift6-ledger-archive.md`) : R2 (--update visible), R5 (mesure avant
édition de source), R9 (jamais deux implémenteurs en parallèle), R10 (jamais
de --amend), R11 (revues par subagents de cette session), R12 (attribution
GLM 5.3 Flash — tous les agents tournent sur GLM).

## Pre-flight scan — paires de tâches partageant un fichier ou une interface

| Tâches | Ce qui est partagé | Trouvé |
| --- | --- | --- |
| T1 × T2 × T3 | l'exécutant `ModFolderBulkMove` | T1 produit, T2/T3 consomment — séquentiel obligatoire |
| T2 × T3 | `StarHubTHViewModel.swift` (régions disjointes 9227-9385 / 8754-9012) | Ruling 8 exige fichiers disjoints pour parallélisme revue/N+1 : MÊME fichier → strictement séquentiel |
| T3 × T4 | rien (T4 = docs + mesure) | T4 après T3 ✓ |
| T1 × tests existants | `ScriptedMoves` dupliqué du patron ModFolderRollbackTests (private) | assumé par le plan : les suites dupliquent le harnais, pas le fichier |

## Pre-flight scan — auto-cohérence de chaque tâche

| Tâche | Vérifié | Trouvé |
| --- | --- | --- |
| T1 | le test 7 (rollback raté) a-t-il sa construction disque ? | le résidu même-mod à destination est requis (patron ModFolderRollbackTests:58-65) — à préciser dans le dispatch |
| T1 | `Direction` traversant les événements | internal → implicitement Sendable ; la passe stricte de T4 confirme |
| T1 | `total == 0` | l'exécutant ne rend que `finished` — écrit dans le plan ⚠️ (a) |
| T2 | fidélité du bilan (log/modal/warning) | code fourni verbatim au plan, fidélités listées |
| T3 | `anyEnabled` → save horodatages | ancien testait `movedCount > 0` direction enable ; nouveau : au moins un `.activated` reçu — équivalent, dit dans le plan |
| T4 | prévision non chiffrée | leçon spec-rules-need-measuring appliquée ✓ |

## Décision préalable de l'auteur (plan, point ouvert)

La bascule en masse garde `progressStep: 1` (barre à chaque dossier,
comportement actuel) — fidélité d'abord ; aucun choix contraire exprimé.

## Journal d'exécution

BASE T1: c10a4fe3
T1: DONE_WITH_CONCERNS — commit 3faf8e46 (Package.swift + baseline R2
  inclus). TDD : rouge « cannot find BulkMoveEvent », 8/8 verts, suite
  3169/317 suites, 3 sabotages joués et révoqués. Gate EXIT=0 après
  `--update` assumé (dispatch_queue 157→158).
  Quatre divergences portées à la revue : (1) la prose du test 1 du brief
  contredisait la règle (b) — tranché vers la règle (b) + patron VM
  (:8885-8894), l'exécutant n'a jamais bougé ; (2) stranded à nom pointé
  (`.X.stale_…`) ; (3) coquille « Clicquet » dans le message de commit
  (R10 : pas d'amend) ; (4) Package.swift modifié malgré le « aucun
  changement attendu » — la cible énumère ses fichiers.
Revue dispatchée : paquet review-c10a4fe3..3faf8e46.diff (25 Ko), quatre
  divergences à verdicter sur le code + conformité de l'interface produite
  (T2/T3 la consommeront telle quelle).
T1: revue — conformité ✅, qualité **approuvée**, 0 critique / 0 important /
  3 mineurs. Les 4 divergences validées SUR LE CODE : ordre des événements
  épingle [activated, progress, finished] conforme au VM, règle (b) et test
  cohérents entre eux ; stranded pointé confirmé à la source
  (ModFolderCollision.asideName préfixe un point) ; Package.swift minimal et
  nécessaire (cibles explicites = auto-découverte désactivée — les « 8
  verts » n'existaient qu'avec cette entrée) ; coquille sans portée. Scripts
  du test 7 vérifiés contre les trois gestes réels de
  moveReplacingStaleDestination (aside/move/rollback). Interface exacte,
  types posés au niveau du fichier — T2/T3 consomment. R2 : +1
  DispatchQueue exactement celui de l'exécutant. ⚠️ exécutions = affirmations
  du rapport (protocole), cohérentes avec les artefacts.
T1: minor (deferred): defer{} no-op dans makeRoot() (repris de l'esquisse du
  plan — défaut du plan, pas de l'implémenteur) ; à retirer au prochain
  passage.
T1: minor (deferred): trailer « GLM 5.3 Flash » vs convention maison
  « GLM 5.3 » (CLAUDE.md §Git) — non amendable (R10). Tranché pour la suite
  de L3 : signer `Co-Authored-By: GLM 5.3 <noreply@z.ai>` (forme de la
  convention maison).
T1: minor (deferred): fm.attempted lu après drain (test 7) — sûr de facto
  (finish() est la dernière instruction), noté pour mémoire.
T1: complete (commits c10a4fe3..3faf8e46, review clean, 3 minors deferred)
BASE T2: 3faf8e46
T2: DONE — commit 75d67f48 (fichier unique, +48/−124 ; VM 10122→10046,
  dispatch_queue 158→151 — 7 hops disparus, aucun --update). Gate EXIT=0,
  3169 verts. Corps posé verbatim du brief, preuve de fidélité en 11 points
  dans le rapport. Deux divergences à verdicter : (1) WeakViewModelBox
  supprimée (hors plage nominale, dans le « remplacé » du brief, morts sinon)
  ; (2) seul écart comportemental déclaré : désallocation du VM en vol —
  l'ancien retenait le contexte (référence forte extraite du box), le nouveau
  relit weak à chaque événement ; plus fidèle à la règle weak, invisible UI.
Revue dispatchée : paquet review-3faf8e46..75d67f48.diff (13 Ko) — 11 points
  de fidélité à vérifier contre l'ancien corps, les deux divergences, et le
  critère T10 (ModsFolderSizer sur utility, lectures lourdes hors main).
T2: revue — conformité ✅, qualité **approuvée**, 0 critique / 0 important /
  3 mineurs. Corps verbatim du brief ; les 11 fidélités prouvées contre le
  code de l'exécutant T1 et l'ancien corps (y compris message d'échec
  identique via errorDescription jamais nil) ; WeakViewModelBox : zéro
  occurrence restante (T3 pas cassé) ; critère T10 tenu (ModsFolderSizer
  toujours utility, rien rapatrié) ; Task @MainActor, zéro hop, zéro
  FileManager, zéro disque dans la fonction.
T2: minor (deferred): bloc de doc orphelin (:9207-9214) séparé de
  toggleAllMods — supprimer la ligne vide :9215 pour fusionner (une ligne).
T2: minor (deferred): rapport « dupliqué verbatim » inexact (le fond X57
  survit reformulé, la moitié box-spécifique meurt juste) — hors dépôt.
T2: minor (deferred): seconde facette de la divergence désallocation : VM
  mort avant le démarrage → l'ancien ne faisait AUCUN travail disque, le
  nouveau fait les moves sans état/bilan (discutablement plus juste — la
  demande s'accomplit) ; invisible en pratique, le VM vit pour l'app.
T2: complete (commits 3faf8e46..75d67f48, review clean, 3 minors deferred)
BASE T3: 75d67f48
T3: dispatché (le patron de forme = le corps T2 revu et approuvé ; les 4
  fidélités du profil + WeakViewModelBox ne revient pas + le doc orphelin
  :9207-9215 est deferred, hors tâche).
T3: DONE — commit fd69ccb7 (fichier unique, +55/−181 ; VM −202 lignes sur
  toute L3, signature inchangée). Gate EXIT=0 sans --update (« aucune
  violation nouvelle »), 3169 verts. Corps verbatim du brief, fidélité en
  11 points. Écart assumé porté à la revue : le `outcome.movedCount > 0`
  du code normatif DU PLAN (défaut du plan, pas de l'implémenteur) déclenche
  un save horodatages idempotent sur un apply sans activation — l'ancien
  `anyEnabled` était plus étroit. Second point : les commentaires de
  rationale de l'ancien corps partent avec lui.
Revue dispatchée : paquet review-75d67f48..fd69ccb7.diff (17 Ko) — 11
  fidélités contre l'ancien corps, l'écart movedCount/anyEnabled à
  verdicter (Important ou Minor), la survie des « pourquoi » dans le code
  vivant.
T3: revue — conformité ❌, qualité **à corriger** : 1 Critique + 1 Important,
  **tous deux défauts du plan** (mon code normatif). Transposition propre
  (verbatim, segments intouchés, ordre final intact, captures impeccables,
  les « pourquoi » de l'ancien corps survivent — garde d'adoption sur
  syncActiveProfileIds et les déclarations, completion-dernier dans le doc
  comment).
  - CRITIQUE : scanMods() appelé dans le Task @MainActor → le rescan lourd
    (plusieurs secondes sur ~900 mods) tourne sur main — gel UI à chaque
    application de profil, le voile .rescanning ne se rend même plus.
    Violation T10 directe. ⚠️ **T2 porte le même pattern** (:9169) qui avait
    échappé à la revue T2 — le fix couvre les deux sites (ré-ouverture de
    T2 pour ce seul point).
  - IMPORTANT : fidélité (a) violée — `movedCount > 0` (mon plan) vs
    l'ancien `anyEnabled` plus étroit ; save idempotent superflu ; fix une
    ligne sur le pattern T2 (:9140-9157).
  - Mineurs deferred : 2 imprécisions du rapport T3 ; wording stale :8791 ;
    bruit « snooze store undecodable » préexistant hors périmètre.
  ⚠️ Leçon de somme : la revue T2 avait validé « aucun disque dans le
  Task » sans creuser scanMods — la revue T3 l'a vu en creusant une
  primitive nommée. Les revues qui vérifient « rien de lourd » doivent
  nommer les primitives lourdes appelées, pas seulement les closures.
T3: fix round 1/5 — implémenteur original repris avec les findings verbatim,
  couverture étendue au site T2 (même fichier, même forme — Ruling 9 tient,
  un seul implémenteur). Forme à trancher par lui en lisant scanMods/refresh
  : scan hors main, voile rendu (suspension avant blocage), fin sur main dans
  l'ordre. Le « pourquoi » : forme candidate `await Task.detached{...}.value`
  si scanMods est rendu appelable hors isolation — à lui de lire et poser la
  forme juste.
T3: fix round 1/5 livré — commit 52e6b1d0 (fichier unique, +29/−3). Les deux
  sites (T3 ET T2) sortent scanMods du main via `withCheckedContinuation` +
  file globale `.userInitiated` : suspension avant blocage (voile/barre se
  rendent), reprise sur main, ordre de fin intact. La forme `Task.detached`
  du plan a été REJETÉE PAR LE COMPILATEUR (closure @Sendable) ;
  `nonisolated` sur scanMods faisait tomber 28 erreurs sur tout son
  call-graph — retiré, documenté (c'est le travail de la tranche
  d'isolation). anyEnabled armé sur `.activated` (fidélité a). Gate EXIT=0,
  cliquet « aucune violation nouvelle » (dispatch_queue 147 < 158), VM −176
  lignes, 3169 verts. Noté au rapport : scanMods reste main-actor-annoté
  (pont file globale assumé), un scanMods() sur main préexistant au chemin
  trash-restored (:9465), hors portée.
Re-revue scopée dispatchée : paquet review-fd69ccb7..52e6b1d0.diff (7 Ko) —
  verdicts des deux findings + la sûreté du pont (scanMods main-annoté
  appelé depuis la file : que fait-il de son thread appelant ?) + nouvelles
  casses du fix uniquement (suspension jamais reprise ? T2 symétrique ?).
T3: re-revue — **les deux findings ADDRESSED, fix approuvé, aucune nouvelle
  casse**. Le pont GCD est sûr tel que compilé : appel synchrone sans
  `await` = aucun hop dynamique en mode Swift 5, le corps tourne sur le
  thread GCD — forme identique à `refresh()` (:2188-2190) et au contrat
  documenté de scanMods (:2407, :2523-2524) ; toutes les mutations
  @Published sautent sur main en interne ; caches protégés NSLock. Reprise
  sur main via l'exécuteur du Task, ordres T3/T2 intacts. anyEnabled ⟺
  l'ancien (ni plus ni moins). Continuation toujours reprise (resume
  inconditionnel, CheckedContinuation<Void, Never>). ⚠️ site trash-restored
  :9476 et sortie d'acteur complète → ledgered pour la tranche d'isolation.
T3: complete (commits 75d67f48..52e6b1d0, fix round 1/5 : 2 addressed,
  0 open — review clean, 3+2 minors deferred dont les imprécisions de
  rapport)
BASE T4: 52e6b1d0 (contrôleur exécute lui-même, comme T8/T11)
T4: DONE — commit 6f404ad9. Passe stricte : **216 / 83 bloquants / 0
  erreur, 527 s** — baisse de compteur **modeste** (−2 bloquants contre
  237/85), consignée telle quelle au §9 avec ce qu'elle dit : le gain de
  L3 est l'exécution testée (8 tests disque), la conversion du patron
  log-hop (7 DispatchQueue), le rescan rendu au fond (gel UI attrapé en
  revue). VM 11, reste 3e ; L4 cadrée (SmapiInstaller 25 /
  SmapiUpdateClient 22). ⚠️ Vérification à l'écran de L3 DUE (bascule en
  masse filtrée, application de profil avec mod manquant, bissection
  profil). Push des commits T1-T3 demandé par l'auteur pendant T4 (fait,
  CI success) — le commit T4 attend son push.
T4: complete (commits 52e6b1d0..6f404ad9, docs seulement)
Revue finale L3 dispatchée : paquet review-c10a4fe3..6f404ad9.diff
  (5 commits) — mission = la somme.

## REVUE FINALE L3 — 2026-09-13 22:09 — PRÊTE À DIFFUSER

Diff en 2 passes + 5 checks focaux. **0 critique, 0 important, 3 mineurs.**
La propriété de somme : la **topologie de threads est prouvablement
identique au baseline** — chaque ligne sur main y tournait déjà (hops
partants visibles au diff), scanMods du fond GCD avant et après le pont ;
primitives restantes sur main toutes légères et toutes déjà là
(syncActiveProfileIds, save horodatages, clear journal, message plafonné).
Jumeaux symétriques au squelette, différenciés exactement aux écarts
d'origine (skip-vs-failure, 1 vs 1 %, journal/missingIds/phases/completion
vs syncActiveProfileIds/barre). Journal R2 écrit avant la création du
stream (séquentiel de la même fonction). X57 tient. Annulation : parité
(aucune des deux côtés). La facette somme de la survie : l'exécutant tourne
même si le VM meurt avant le Task — plus cohérent avec le journal R2 (le
garde d'adoption réconcilie au lancement suivant, sur un disque qui dit
vrai, là où l'ancien laissait un journal qui mentait).

**Tri des mineurs L3 — rien ne bloque la diffusion** : « jamais » (trailer
Flash, fm.attempted après drain, rapports hors dépôt, VM-mort-fait-les-moves,
bruit snooze préexistant) ; « tranche suivante » (defer{} no-op makeRoot,
doc orphelin :9207-9215, wording :8791, scanMods trash-restored :9476 →
tranche d'isolation).

Découvertes de somme :
- **Slack de cliquet** : baseline dispatch_queue 158 vs 147 réels — 11
  recroissances silencieuses gratuites. Resserré à la suite (règle maison).
- Asymétrie cosmétique T2/T3 : T3 lit le total porté par l'événement, T2
  relit son total capturé (prouvé égal). À aligner au prochain passage.
- Pont GCD dupliqué en 2 exemplaires texte à texte — assumé, la tranche
  d'isolation remodelera ; un runScanOffMain() si elle tarde.
- Vérification à l'écran de L3 due (bascule filtrée, profil, mod manquant,
  bissection) — avant une release.

État de sortie L3 : commits c10a4fe3..6f404ad9 (+ resserrement cliquet),
poussés jusqu'à 52e6b1d0 ; 6f404ad9 (T4) et le resserrement attendent le
push. Workspace conservé, copie-archive à la demande de l'auteur (même
patron que L1-L2).
