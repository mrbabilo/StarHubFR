# Archive du chantier P5 — tranches L1+L2 (mode Swift 6)

*Copié du ledger SDD le 2026-09-13 à la clôture du chantier (source
git-ignorée `.superpowers/sdd/2026-09-13-p5-swift6-l1-l2/progress.md`,
désormais supprimable).
Plan : `docs/superpowers/plans/2026-09-13-p5-swift6-l1-l2.md`, spec :
`docs/superpowers/specs/2026-09-13-p5-swift6-design.md` (locaux, gitignorés).
Résultat : 453/202 bloquants au jalon → 427/184 après L1 → 237/85 après L2.

---

# SDD ledger — plan: docs/superpowers/plans/2026-09-13-p5-swift6-l1-l2.md

Spec: docs/superpowers/specs/2026-09-13-p5-swift6-design.md (lue)
Base: 1b4f9888 (main, arbre propre)

## Pre-flight scan — paires de tâches partageant un fichier ou une interface

| Tâches | Ce qui est partagé | Trouvé |
| --- | --- | --- |
| T1 × T4 × T5 | `StarHubTH/SaveManager.swift` | trois régions disjointes (SaveHairColor:76, regexCache:232, classe:20). Pas de contradiction — mais fichier **sous cliquet à 1297 lignes** → voir Ruling 2 |
| T9 × T10 | `StarHubTH/StarHubTHViewModel.swift` | ordre imposé et correct : T9 retire l'appel `log` de `renameModFolder`, T10 le rend `nonisolated`. Fichier sous cliquet à 10134 → Ruling 2 |
| T7 × T9 × T10 | même fichier VM (T7 touche l'appelant `ProfileApplyJournalStore.save` à :8805) | régions disjointes ; T7 passe avant T9 |
| T8 × T11 | `docs/REFACTORING.md`, `docs/ROADMAP.md` | T8 corrige le jalon, T11 ajoute le sien. Séquentiel, pas de conflit |
| T0 → T8, T11 | `scripts/p5-strict.sh` | produit par T0, consommé par T8 et T11 ✓ |
| T9 → T10 | `renameModFolder` sans appel à `log` | T10 en dépend et vient après ✓ |
| T3 × T5 | aucun fichier commun | `SmapiUpdateClient` (T3) et `SaveManager` (T5) distincts ✓ |

## Pre-flight scan — auto-cohérence de chaque tâche

| Tâche | Vérifié | Trouvé |
| --- | --- | --- |
| T0 | script vs usage en T8/T11 | cohérent |
| T1 | `PreferenceKey` accepte-t-il une propriété calculée ? | oui — le protocole exige `{ get }`. Cohérent |
| T2 | paramètre et valeur par défaut changés ensemble | cohérent (les deux sont nommés) |
| T3 | ajout de `final` — une sous-classe existerait-elle ? | **vérifié : aucune**. `non_final_classes` 8 → ~5, le cliquet accepte une baisse |
| T4 | deux annotations, deux raisons distinctes | cohérent |
| T5 | réduite après mesure ; `SaveNotesStore` reporté | cohérent, et la raison est écrite dans la tâche |
| T6 | canevas de test contre code non lu | **signalé dans la tâche** — l'implémenteur doit lire `DeepLClient.swift:140-205` avant d'écrire |
| T7 | signatures annoncées vs surface réelle | les 7 points d'entrée sont relevés ; la tâche dit que le grep fait foi |
| T8 | attend « 15 de moins » | cohérent avec T5 réduite |
| T9 | 3 appelants, type d'erreur neuf | cohérent ; collision de noms avec `ModFolderRenameOutcome` signalée |
| T10 | liste d'erreurs = minimum connu | cohérent (corrigé avant exécution) |
| T11 | prévision ~284 / ~96 | cohérent avec T5 réduite |

## Rulings

Ruling 1: exécuter sur `main` sans worktree — CLAUDE.md l'impose explicitement
(« Travailler sur `main` ») et c'est la convention constante du dépôt ; le skill
demande un consentement explicite, il est écrit là. Coût si faux : des commits
sur `main` local (rien n'est poussé sans demande), annulables par `git reset`.

Ruling 2: `python3 check_standards.py --update` est **autorisé** aux tâches qui
ajoutent un commentaire de justification à un fichier verrouillé en taille
(SaveManager 1297, ViewModel 10134, ModConfigBackupManager 548,
ModInstallBackupManager 729, NexusUpdateChecker 861, SmapiLogDiagnostics 590).
La convention du dépôt veut qu'une annotation de concurrence porte sa raison en
commentaire ; refuser l'`--update` reviendrait à annoter sans justification.
L'augmentation doit rester **visible dans le diff** et ne couvrir que les lignes
de commentaire ajoutées. Coût si faux : la baseline monte de quelques lignes,
réversible en un commit.

Ruling 3: T1, T2 et T4 partent en **un seul dispatch** (7 fichiers, 3 commits) —
ce sont des annotations mécaniques de même forme, dont le plan donne le code
exact. Le skill demande de batcher ce cas. Coût si faux : un diff de revue plus
large d'un tiers ; les commits restent séparés et reviewables un par un.

Ruling 4: modèles — `sonnet` pour les tâches d'annotation (T0-T5, T8, T11),
`opus` pour celles qui écrivent des tests et touchent à la concurrence réelle
(T6, T7, T9, T10). Coût si faux : une tâche mal exécutée qui repasse en boucle
de correction.

## Journal d'exécution

BASE lot A: 1b4f9888
Lot A (T0+T1+T2+T4) dispatché — implémenteur sonnet, agent a7f63845.
Lot A: T0 fait (scripts/p5-strict.sh créé, passe stricte lancée), 0 commit,
agent arrêté en attente de la mesure — comportement correct.
Ruling 5: la mesure de T0 doit **finir avant toute édition de source**. La passe
stricte compile les 318 fichiers du dépôt : éditer pendant qu'elle tourne lui
ferait lire des fichiers à moitié écrits, exactement le piège « ne pas éditer
pendant un gate » de CLAUDE.md. Mon brief de lot disait l'inverse — il avait
tort, l'agent a bien fait d'attendre. Coût si faux : ~8 minutes d'attente.
Lot A: DONE — commits 61996aac, 9085d066, 50cd0a88, 6308f5b8. Gates verts,
3152 tests verts, un `check_standards.py --update` (SaveManager +3 lignes de
commentaire) conforme au Ruling 2. Jalon confirmé indépendamment : 453 / 202 / 0.
Lot A: revue dispatchée (sonnet), paquet review-1b4f9888..6308f5b8.diff.
Réserve de l'implémenteur à trancher en revue : `BenignRule: Sendable` laisse son
membre `kind` (`SmapiDiagnostics.BenignNotice.Kind`, enum public) non-Sendable —
conformité incomplète, confirmée par un diagnostic SourceKit.
Lot A: revue clean — conformité ✅, qualité approuvée, 0 critique / 0 important.
Lot A: minor (deferred): aucune re-mesure stricte après le lot — conforme au plan
(la passe est due en T8), mais rien ne prouve encore la baisse des 202.
Ruling 6: le diagnostic neuf sur `SmapiDiagnostics.BenignNotice.Kind`
(`SmapiLogDiagnostics.swift:43`, `enum Kind: String, CaseIterable`) — révélé par
la conformité `BenignRule: Sendable` de T1 et couvert par **aucune** tâche du
plan (vérifié par le relecteur) — est **absorbé par T3** en addendum plutôt que
laissé en dette. Raison : sans lui, T1 déplace un diagnostic au lieu de
l'éteindre, et le gain annoncé de L1 serait faux de 1. L'enum porte un `String`
brut et n'a aucun membre stocké : la conformité est sûre par construction.
Coût si faux : une ligne à révoquer dans un fichier déjà touché par T3.
Lot A: complete (commits 1b4f9888..6308f5b8, review clean)
BASE T3: 6308f5b8
T3: DONE_WITH_CONCERNS — commits a3fca417 (addendum Kind, Ruling 6) + 8246c274
(les 4 singletons). Gate EXIT=0, 3152 tests verts dont X87. `--update` conforme
(3 fichiers oversized +9/10 lignes, SmapiUpdateClient franchit 400,
non_final_classes 8→6).
T3: réserve 1 (correction) — `SmapiUpdateClient.rateLimitUntil` (:410) n'a aucun
verrou tenu pendant sa mutation ; l'implémenteur annote sur un argument de
confinement + happens-before via inFlightLock. Envoyé en revue **opus** avec ce
site nommé, verdict à rendre par le relecteur sur le code, pas sur l'argument.
T3: réserve 2 — les deux managers n'ont aucun état mutable (tout `let`) ;
l'implémenteur a corrigé les commentaires plutôt que de recopier le brief faux.
Question ouverte posée au relecteur : `@unchecked` ou `Sendable` ordinaire ?
T3: minor (deferred): coquille « suppposition » dans le message de 8246c274.
T3: revue (opus) — conformité ✅, qualité approuvée avec 1 Important.
  Les deux réserves de l'implémenteur VÉRIFIÉES SUR LE CODE et tenues :
  - `rateLimitUntil` : confinement au sous-arbre de `runFetch` prouvé (accès :203
    et :386 seulement ; `post`←`collect`←`runFetch`), deux passes concurrentes
    impossibles (check-and-set atomique sous inFlightLock, `clearInFlight` après
    `await task.value`). L'annotation ne ment pas.
  - les deux managers : tous champs `let`, `indexLock` couvre tout le cycle
    disque via `withIndexLock` sans exception. Le brief était faux.
  Arithmétique du cliquet vérifiée à l'unité : 10+9+9+11 = +39 (25726→25765).
T3: minor (deferred): justification `@unchecked` de SmapiUpdateClient plus longue
  que nécessaire (l'arête porteuse est `await task.value`, pas la paire
  unlock/lock) ; message de `a3fca417` affirme un diagnostic que le gate ne peut
  pas montrer (pas de -strict-concurrency dans build_app.py) — le changement
  reste juste ; rapport annonce 4 sites pour `metadataGeneration`, il y en a 3
  (code correct) ; coquille « suppposition » dans 8246c274.
T3: fix round 1/5 — Important : les commentaires des 2 managers justifient
  `@unchecked` par « tout est let » (argument d'un `Sendable` ordinaire) au lieu
  de nommer `private let fm = FileManager.default`, seul membre non-Sendable du
  SDK et vraie raison de l'annotation. Renvoyé à l'implémenteur d'origine.
T3: fix round 1/5 (1 addressed, 0 open — commit 47a0df74) ; re-revue : TRAITÉ,
  aucune casse (diff limité aux blocs ///, baseline +14 = +7+7 cohérente).
T3: complete (commits 6308f5b8..47a0df74, review clean)
BASE T5: 47a0df74
Ruling 7: le brief de T5 est **faux** et le dispatch le corrige. Il affirme que
« le seul état mutable de type est `regexCache` » et que l'état d'instance est
immuable ; en réalité `SaveManager.swift:280` porte
`private var parseCache: [String: ParsedSave]` avec son `parseCacheLock` (:281).
L'implémenteur reçoit l'ordre de vérifier les membres stockés lui-même (classe
223-1300) et d'écrire le commentaire qui dit la vérité, pas celui du brief.
Raison : c'est le même défaut que la revue de T3 vient de sanctionner — une
justification qui nomme ce qui est vrai par ailleurs au lieu de nommer ce qui
rend l'annotation nécessaire. Coût si faux : un commentaire à réécrire.
T5: dispatché (sonnet), BASE 47a0df74.
T5: DONE — commit 6614b50. Gate EXIT=0, 3152 tests verts. Ruling 7 confirmé par
l'implémenteur : `parseCache` (:280) protégé à ses 4 accès par `parseCacheLock`,
c'est lui (SE-0302) qui interdit un `Sendable` ordinaire ; aucun membre stocké
non-Sendable (FileManager seulement local). `final` ajouté, non_final_classes 6→5.
Ruling 8: à partir de T5, la **revue de la tâche N tourne en parallèle de
l'implémentation de N+1** quand leurs fichiers sont disjoints (ici SaveManager.swift
vs DeepLClient.swift + Tests/DeepLClientTests). Le relecteur travaille sur un
paquet de diff figé, donc l'arbre qui bouge ailleurs ne l'atteint pas ; la règle
du skill n'interdit que deux **implémenteurs** simultanés. Raison : sept tâches
restent, chacune avec un gate de 8-12 min. Coût si faux : un relecteur qui lit un
fichier source en mouvement et signale une incohérence fantôme — visible dans son
rapport, sans effet sur le code.
BASE T6: 6614b50
T5: revue (sonnet) — conformité ✅ (au brief CORRIGÉ : détecter `parseCache` était
  l'exigence, pas recopier le brief), qualité approuvée, 0 critique / 0 important.
  Recensement re-vérifié par le relecteur sur toute la classe (:234-:1311) :
  rien d'oublié. `parseCacheLock` couvre les accès réels (:300 removeAll, :315
  lecture, :323 écriture). `@unchecked` confirmé nécessaire (SE-0302 : un seul
  `var` stocké exclut un `Sendable` ordinaire, verrou ou pas). SaveNotesStore
  intouché (vérifié par diff des 65 premières lignes). Baseline exacte.
T5: minor (deferred): le commentaire livré dit « ses quatre accès » à
  `parseCache` — il y en a **trois** (:300, :315, :323 ; :291 est la déclaration).
  L'erreur s'est propagée au rapport et au message de commit. Références de ligne
  du commentaire non réactualisées après insertion (« ~280 » pour :291).
  → À corriger dans T8, qui est déjà une tâche de correction documentaire.
  La clause porteuse (« tout accès passe par parseCacheLock ») est vraie.
T5: complete (commits 47a0df74..6614b506, review clean)
T6: DONE_WITH_CONCERNS — commit 4bfe22e1. 3155 tests verts (3152 + 3), gate
  EXIT=0 sans --update. La course est corrigée.
  ⚠️ Le sabotage prescrit par MON brief ne prouvait rien : remettre la seule
  écriture ne change aucun comportement. L'implémenteur a rétabli écriture ET
  lecture — deux variantes rouges (globale nue → SIGSEGV ; globale verrouillée →
  échec propre, 2,02 s contre un Retry-After: 0). Le rouge avant correctif était
  le même SIGSEGV, 3 fois sur 3.
  Trou de couverture trouvé au passage : la politique `Retry-After` n'était
  testée par RIEN (le stub émettait `headerFields: nil`). 2 tests déterministes
  ajoutés en plus du test de course.
  Son premier test était vert : il s'est arrêté au lieu de le « réparer »
  (consigne respectée), fenêtre de course ~100 ns diagnostiquée.
T6: point à trancher par l'auteur (préexistant, hors périmètre) :
  `DeepLClient.swift:146-147` annonce qu'au-delà de 60 s « on retombe sur
  retryDelay », alors que le code **borne** (`min(retryAfter, 60)`). Commentaire
  ou code — c'est une question de politique, pas de concurrence.
T6: revue dispatchée (opus) ; BASE T7: 4bfe22e1
T6: revue (opus) — conformité ✅, qualité approuvée, 1 Important.
  Flakiness tranchée PAR LA MESURE : 37 exécutions, 4 régimes (repos, 2x, 6x
  sursouscription load avg 66, + cohabitation avec les tests à butée temporelle)
  → 37/37 vert. Le pire régime triple la durée sans franchir le seuil.
  État partagé réellement supprimé (`grep lastResponse` → rien ; seul static
  restant = `maxResponseBytes`, un let). Politique de réessai identique au
  caractère près (vérifiée ligne à ligne :140, :149-153, :154-156).
  Les 2 tests ajoutés : EN périmètre — la branche :148-153 n'était couverte par
  rien, sans eux « comportement inchangé » était infalsifiable.
  Note : le brief surestimait son énoncé — `retryAfterSeconds(from:)` prenait
  DÉJÀ sa réponse en paramètre ; seul son commentaire a bougé.
T6: fix round 1/5 — Important : les 6 tâches de bruit fuient sur le chemin
  d'échec (`DeepLClientTests.swift:413-422`). Elles ne consultent `stop` qu'après
  chaque `translate`, et `stop.raise()` (:454) est inatteignable si le
  `.timeLimit(.minutes(1))` se déclenche → elles martèlent URLSession pour tout
  le reste du processus de test, dégradant les 314 autres suites, et précisément
  quand la machine est chargée. Correctif : `defer { stop.raise() }`.
T6: minor (deferred): `.serialized` inerte sur une suite à test unique (:397) ;
  coût mur des 2 tests déterministes = 2,02 s, désormais l'essentiel du chemin
  critique (`anUnreadableRetryAfter…` pourrait passer à 200 ms, 0,8 s rendus) ;
  commentaire :170-175 dit la mécanique de travers (ARC concurrent sur la
  référence partagée, pas « la variable écrase son compteur ») ; variante de
  sabotage « globale sous NSLock » étayée sur une seule exécution (la variante
  nue, celle qui reviendrait réellement, est 3/3).
Ruling 9: le fix de T6 **attend la fin de T7**. Deux implémenteurs en parallèle
  partageraient `.build` (builds incrémentaux concurrents) et se disputeraient le
  CPU sur des gates de 8-12 min — le Ruling 8 n'autorise le parallélisme qu'entre
  un relecteur (qui ne compile pas) et un implémenteur. Coût si faux : quelques
  minutes d'attente.
T7: DONE — commit 0537555d. 3159 tests verts (3155 + 4), gate EXIT=0,
  --update de 3 compteurs (+19 lignes, diff dans le commit).
  Cinq divergences du brief, toutes vers plus de sûreté :
  1. **Pas de valeur par défaut** sur les 7 points d'entrée — le paramètre est
     OBLIGATOIRE. Un défaut rouvrait le chemin d'oubli que la tâche interdit
     (`save(snap)` sans dossier écrit chez l'utilisateur). Preuve donnée : aucune
     expression des deux suites ne peut nommer le dossier réel.
  2. Le type est `URL?`, pas `URL` — les stores toléraient déjà `nil` en silence,
     préservé et épinglé par 2 tests neufs.
  3. **Les suites existantes étaient creuses** : leurs 12 assertions n'observent
     que l'aller-retour du store, donc le sabotage de l'étape 5 les aurait
     laissées ENTIÈREMENT vertes. Test manquant ajouté dans chaque suite AVANT
     de coder ; sabotage → 2 échecs pour la bonne raison.
  4. `.serialized` retiré des deux suites (sa seule raison écrite était le
     `static var` supprimé).
  5. Défaut attrapé au passage : `BisectionRunner` ancienne ligne 228, closure
     sans `guard let self` — `self?.snapshotDirectory` aurait fait rendre `true`
     à `finish(.complete)` sans rien effacer si le runner avait disparu.
  Réserve non mesurable : `private let applyJournalDirectory = AppSupport.directory`
  lit un `static let` à effet de bord depuis un initialisateur de propriété
  stockée, donc plus tôt que le `load()` qu'il remplace — raisonnement, pas mesure
  (sous `swift test`, `isHostedByTheApp` est faux).
T7: revue dispatchée (opus) ; fix T6 relancé en parallèle (Ruling 9 satisfait).
T6: fix round 1/5 — commit c63a1182. `defer { stop.raise() }` dès la création,
  PLUS `!Task.isCancelled` sur les deux boucles : sous annulation, `Task.sleep`
  rend la main aussitôt et le `try?` l'avalait — la montée en régime aurait
  tourné à plein régime 5 s. 5 relances du test 5/5 vert, marge inchangée
  (50-65 ms contre 48-63 ms, seuil 1 s). `.serialized` retiré au passage.
⚠️ INCIDENT GIT, réparé et vérifié par moi : l'agent du fix T6 a fait
  `git commit --amend` en croyant amender le sien, et est tombé sur le commit de
  T7 (bf06c730 dans le reflog), y repliant son fichier de test. Il a réparé par
  `git reset --soft 0537555d` (--soft, pour ne pas détruire d'éventuelles
  modifications non validées de l'autre). Vérifié par moi : `0537555d` porte
  exactement ses 7 fichiers (0 DeepL), `c63a1182` porte le seul fichier de test.
  Historique propre.
Ruling 10: **aucun implémenteur ne fait `git commit --amend`** à partir d'ici —
  toute correction est un commit neuf. Un amend suppose que HEAD est le sien, ce
  qui est faux dès qu'un autre agent commite entre son `add` et son `commit`.
  La cause réelle n'est pas le parallélisme lui-même (Ruling 8/9 tient : un
  relecteur ne commite pas) mais le fait que l'agent T7 restait vivant après son
  rapport et a pu committer encore. Coût si faux : un historique un peu plus
  bavard, ce qui est le prix juste.
T7: revue (opus) — conformité ✅, qualité approuvée, 0 critique / 0 important.
  Les 5 divergences jugées sur le fond, toutes validées :
  1. Paramètre obligatoire : **supérieur au précédent que mon brief citait** —
     `ModInstallBackupManager.init(backupsBasePath: URL? = nil)` + repli EST la
     forme qui a laissé les 582 exécutions polluer ; ce qui tient là-bas c'est
     `AppSupport.isHostedByTheApp`, pas l'injection. Nuance du relecteur : la
     garantie exacte n'est pas « aucun test ne PEUT nommer le vrai dossier »
     (un futur test le pourrait) mais « le vrai dossier est inatteignable par
     **omission** » — toute route vers lui est explicite et visible au grep.
  2. `URL?` : préservation vérifiée sur `git show 4bfe22e1` (dont `finish(.complete)`
     qui rendait DÉJÀ `true` via un `clear()` inopérant — le plus contre-intuitif,
     désormais épinglé).
  3. Les tests d'épinglage regardent le disque (`fileExists`) et rougissent si
     `fileURL(in:)` ignore son paramètre. Sans eux, une redirection *cohérente*
     vers le vrai AppSupport laissait les 12 assertions vertes.
  4. Retrait de `.serialized` sûr : chaque test a son dossier UUID.
  5. `guard let self` de BisectionRunner : la signature FORÇAIT la décision —
     `finish(.complete, in: nil)` aurait rendu `true` sans effacer, l'instantané
     survivant à une remise en état réussie → reprise reproposée indéfiniment.
  **Risque d'ordre d'initialisation clos PAR MESURE** (le rapport le disait non
  mesurable) : `StarHubTHViewModel.swift:217` lit déjà `AppSupport.directory`
  dans un initialisateur stocké **antérieur** au nouveau membre (:7620). La
  première lecture n'a pas bougé ; effets de bord dans la même fenêtre qu'avant.
T7: minor (deferred): `BisectionSnapshotTests.swift:15-20` ne supprime pas son
  dossier temporaire (pas de `defer`, contrairement à la suite jumelle) — 5
  dossiers fuités par exécution contre 4 avant, patron préexistant ;
  `ProfileApplyJournal.swift:59` sans dossier rend « pas d'erreur » donc aucun
  log ni filet de reprise, en silence (hérité, désormais épinglé donc visible) ;
  **la spec du chantier en cours inventorie encore les deux comme `static var`
  (`specs/2026-09-13-p5-swift6-design.md:124-125,140-145`) → à corriger en T8.**
T7: complete (commits 4bfe22e1..0537555d, review clean)

## ARRÊT DEMANDÉ PAR L'AUTEUR — 2026-09-13 13:22

Exécution interrompue à la demande de l'auteur. Re-revue scopée du correctif T6
(commit c63a1182) **arrêtée en vol, jamais rendue** : c'est le seul verdict
manquant. T6 est donc `complete` sur sa tâche mais son correctif n'a pas été
re-relu.

ÉTAT : L1 terminée côté code (T0-T7). Restent NON FAITES : T8 (mesure de fin de
L1 + corrections documentaires), T9, T10, T11 (toute la tranche L2).

Reprise : relire ce ledger, vérifier `git log`, relancer la re-revue de
c63a1182 (paquet déjà généré : review-0537555d..c63a1182.diff), puis T8.
Les briefs des tâches restantes sont dans ce dossier.

## REPRISE — 2026-09-13 13:24 (nouvelle session)

État reconstitué par `git log` et non par le handoff : 11 commits
`61996aac..c63a1182` présents, arbre propre, 12 commits non poussés. Conforme.
Relancés en parallèle : la re-revue scopée de `c63a1182` (relecteur, lecture
seule) et la passe stricte de fin de L1 (`./scripts/p5-strict.sh /tmp/p5-apres-L1`,
compile vers /tmp, ne touche pas `.build`). Les deux ne se gênent pas : l'une lit
un diff figé, l'autre compile hors du dépôt.
⚠️ Attribution des commits à partir d'ici : `Claude Opus 5 (1M context)` et
session `019h9Mz1uSpsZYziQhPBLRFd` — les briefs des tâches restantes portent
encore l'ancienne session, à remplacer dans chaque dispatch.

## T8 — session starhubth-02, 2026-09-13 13:34

⚠️ Correction de l'attribution ci-dessus : le modèle actif est **GLM 5.3 Flash**
(route `glm.sh`), pas Opus. Les commits de T8 portent
`Co-Authored-By: GLM 5.3 Flash <noreply@z.ai>`.

Constaté à l'arrivée : la passe stricte de fin de L1 **tournait déjà**
(lancée 13:24 par la session de reprise, PID 84483, sortie /tmp/p5-apres-L1) et
la re-revue de `c63a1182` **était en vol** dans la session bg « Relecture
critique ». Rien n'a été relancé.

**Étapes 1 et 2 du brief T8 — conformes** (passe terminée 13:33) :
`avertissements=427  bloquants_swift6=184  erreurs=0`, durée mesurée par
timestamps du log = **518 s** ; `MutableGlobalVariable` restant = **une seule
ligne**, `StarHubTH/SaveManager.swift` (SaveNotesStore.shared, la reportée).
Baisse de **−18 bloquants** contre −15 prévus : plusieurs globales portaient
déclaration + usages. Le brief attendait « inférieur de 15 » — satisfait.

**Étape 3 — corrigée** :
- `REFACTORING.md` §9 : tableau refait (4 relevés datés : 13/210 s, 467/212 s,
  jalon 453/202/505 s, après-L1 427/184/518 s) + note sur les bloquants et le
  −18 ; « 466 de tête » → 453 au jalon ; recommandation mise à jour
  (453/427) + reprise du jalon consignée.
- `ROADMAP.md` : « 466 diagnostics stricts » → jalon 453/202 + L1 close
  427/184, quinze sur seize.
- spec `:124-125,140-157` : les deux `storageDirectory` marquées réglées en T7
  (voie 1 durcie, paramètre obligatoire, `URL?`) + SaveNotesStore notée
  seizième, reportée.
- `SaveManager.swift:224-225` : « quatre accès » → **trois** (la parenthèse en
  listait déjà trois), « ligne ~280 » → 291 (minor T5).
- `DeepLClient.swift:170-175` : « la variable écrasait son propre compteur » →
  « les accès concurrents à la variable croisaient les releases ARC de la même
  référence » (minor T6 — mécanique réelle).

Titre de commit du brief corrigé : « les seize globales éteintes » était faux
(quinze éteintes, la seizième reportée) → « quinze globales éteintes sur seize ».

Gate `build_app.py` lancé (commentaires .swift à longueur inchangée : cliquet
taille intact, pas de `--update` attendu). Commits à suivre après gate vert.
Re-revue de `c63a1182` : verdict toujours en attente côté « Relecture critique ».

## T8 COMPLETE — 2026-09-13 13:41

Gate **EXIT=0** (incrémental 318 fichiers, cliquet vert, aucun `--update`).
Deux commits :
- `ce0d3a5d` docs(concurrence): SaveManager compte ses trois acces au
  parseCache, DeepLClient nomme la course ARC — minors T5/T6 closes.
- `6c49a7f` docs(p5): L1 close — quinze globales eteintes sur seize, le jalon
  corrige.

**L1 est désormais complète ET mesurée ET consignée.** Restent hors T8 :
- le **verdict de la re-revue de `c63a1182`** — en vol dans la session bg
  « Relecture critique » [b66b4d] (lancée par la session de reprise 13:24,
  probablement `51c513dd`) ; à consigner ici quand il arrive ;
- **L2 (T9, T10, T11)** — l'exécution SDD reste **arrêtée par l'auteur**
  (13:22) : pas de dispatch d'implémenteurs sans son feu vert explicite.
  Les briefs sont prêts dans ce dossier (task-9/10/11-brief.md) ; pensez à
  y remplacer l'attribution par `GLM 5.3 Flash` si l'exécution reprend.

## Re-revue de c63a1182 — RE-FAITE PAR STARHUBTH-02 — 2026-09-13 14:07

La session « Relecture critique » [b66b4d] est **morte sans rendre** : tour
terminé à 13:33, verdict resté dans son transcript jamais écrit sur disque,
deux appels (13:52, 13:58) restés sans réponse, aucun processus vivant à
13:58. Re-revue faite ici sur le paquet figé `review-0537555d..c63a1182.diff`,
lecture seule, aucun build, verdict porté sur le code.

**Verdict : conformité ✅, qualité approuvée — 0 critique / 0 important /
1 minor (deferred).**

Vérifié sur le code actuel (`DeepLClientTests.swift:395-476`) :
1. **Étendue** : 1 fichier (git show --stat), +19/−3, rien hors la suite de
   test ; aucune assertion touchée — l'unique `#expect(worst < 1 s)` est
   intacte, la détection de la course ne change pas (un vol ferait toujours
   rouge).
2. **`defer { stop.raise() }`** (:434) : posé après la création des 6 tâches
   détachées, mais la fenêtre entre :425 et :434 ne contient aucun point de
   sortie (pas de `try`/`return`/appel lançable) — la garantie tient. Le
   commentaire nomme déjà le risque d'un futur code intercalé.
3. **`!Task.isCancelled` sur les deux boucles** (:444, :454) : techniquement
   fondé — sous annulation, `Task.sleep` rend `CancellationError` aussitôt et
   le `try?` l'avale ; sans le garde, la butée de 5 s deviendrait un spin à
   plein régime. Les boucles vivent dans la tâche du test, celle-là même que
   le `.timeLimit` annule.
4. **Ordre raise → drainage** (:470-471) : le `raise()` explicite précède bien
   l'attente des détachées — le `defer` seul y suffirait pas (il ne sort la
   portée qu'à la fin de fonction : attendre des tâches stoppées par lui seul
   mortellerait).
5. **Retrait de `.serialized`** : la suite ne porte qu'un `@Test` (:410, unique)
   — l'annotation n'y sérialisait rien et promettait ce qu'elle ne fait pas.
   Raison du diff vérifiée juste.

Minor (deferred) : poser le `defer` **avant** la création du bruit
(`let stop = StopFlag()` puis `defer`, puis les `Task.detached`) rendrait la
garantie structurelle au lieu de dépendre d'une fenêtre vide de code —
cosmétique aujourd'hui, à prendre à l'occasion d'un prochain passage sur le
fichier. Ne vaut pas un commit à lui seul.

**L1 est entièrement close** : T0-T7 revues, T6 fix re-revu, T8 mesuré et
consigné, re-revue rendue. Reste L2 (T9, T10, T11), arrêtée au feu de l'auteur.

## REPRISE L2 — 2026-09-13 14:13 (feu vert explicite de l'auteur : « relancer L2 »)

Séquencement imposé : T9 → revue T9 → T10 → revue T10 → T11 (faite par le
contrôleur, comme T8) → revue finale whole-branch. Ruling 8 ne s'applique pas à
T9×T10 (même fichier VM — le relecteur de T9 lirait le fichier en mouvement) :
strictement séquentiel.
Ruling 11: les revues passent par des **subagents de cette session** (Agent
tool), jamais par des sessions bg d'autres sessions — la leçon de la session
« Relecture critique » morte sans rendre (voir plus haut).
Modèles : opus pour T9/T10 (Ruling 4), contrôleur pour T11, revue finale sur
le modèle le plus capable. Attribution commits : les implémenteurs opus
signent `Claude Opus 5` ; le contrôleur signe `GLM 5.3 Flash`.
BASE T9 : 6c49a7f1.

Ruling 12 (14:46) : l'implémenteur T9 s'est auto-diagnostiqué **GLM 5.3 Flash**
malgré le dispatch « opus » — glm.sh route tout le monde vers GLM, l'alias du
dispatch est une étiquette sans garantie de modèle (le piège connu de
CLAUDE.md). Tranché : tous les commits de la tranche L2 signent
`GLM 5.3 Flash <noreply@z.ai>` ; le Ruling 4 (choix de modèles) vaut comme
consigne de brief, pas comme garantie de capacité réelle.

T9: DONE_WITH_CONCERNS — commit e13c5255. 3161 tests verts (3159 + 2), rouge
au départ ET au sabotage de strandedAt, gate EXIT=0 **sans** --update
(ViewModel 10141 → 10103, rétréci). Divergence assumée portée à la revue :
corps de renameModFolder déplacé vers `Models/ModFolderRename.swift`
(`ModFolderRename.moveReplacingStaleDestination`, prétendu verbatim, +
`FolderToggleRefusal` + `uniqueId(ofModAt:)`), façade VM à signature exacte ;
le site `:2921` prétendu éteint — T10 devra être redispachée avec l'état réel
des charnières après verdict de revue. Pont `LocalizedError` : les appelants
ne lisaient que `localizedDescription`, affichage inchangé (CRITICAL + bilan).
Revue dispatchée (paquet review-6c49a7f1..e13c5255.diff, 31 Ko) avec ordre de
juger la divergence sur le code, verbatim comparé à
`git show 6c49a7f1:...`.
T9: revue — conformité ✅, qualité **approuvée**, 0 critique / 0 important /
  3 mineurs. Divergence validée sur le code : verbatim fidèle (3 divergences,
  toutes mandatées : throw rollbackFailed, throw moveFailed, catch nommé) ;
  message CRITICAL identique au caractère près (`rollbackCriticalLog`,
  Models/ModFolderRename.swift:80-82), zéro reste de l'ancienne chaîne ;
  pont LocalizedError vérifié bout en bout, emballage non observable des
  appelants, épinglé par aFailedMoveKeepsTheOriginalMessage ;
  uniqueId(ofModAt:) zéro occurrence hors Core — le site :2921 n'existe plus ;
  FolderToggleRefusal zéro référencement hors Core ; ModFolderRenameOutcome
  absent du diff. ⚠️ gate/rouge/vert restent les citations du rapport (non
  relancés, conformément au protocole) ; cohérence structurelle vérifiée.
T9: minor (deferred): interleaving des lignes décalé aux appelants 2 et 3
  (:8910, :9344) — CRITICAL groupé avec son bilan dans la boucle failures
  au lieu de tomber pendant la boucle de déplacements ; mêmes lignes, même
  file, ordre relatif seul change.
T9: minor (deferred): le pont rollbackFailed→message original n'est pas
  asserté (seul moveFailed l'est) — une ligne #expect dans
  aFailedMoveKeepsTheOriginalMessage suffirait ; c'est la 2e ligne affichée
  des trois appelants précisément quand un rollback rate.
T9: minor (deferred): doc du type (:57-62) — un futur appelant qui ne lit que
  localizedDescription après rollbackFailed ne saura pas que le dossier est
  coincé.
T9: complete (commits 6c49a7f1..e13c5255, review clean, 3 minors deferred)
BASE T10: e13c5255
T10: DONE_WITH_CONCERNS — commits 5d1ab393 (annotation + charnières + hops) +
  0962b068 (ModInstallView : le lot glisser-déposer ne traverse qu'une valeur).
  3161/316 suites verts ; gate EXIT=0 avec **0 avertissement**.
  ⚠️ Constat majeur : le compilateur (mode Swift 5, le gate ne passe pas
  -strict-concurrency=complete) n'a rendu **aucune erreur, que des
  avertissements** — l'implémenteur a pris une base de référence (stash/build)
  pour prouver qu'ils étaient tous neufs, traité ~20 par la règle
  (sortie/hop), documenté ~34 restants pour L3/LS (workers des closures
  lourdes, captures SaveGameInfo/BackupsRead). Deux `--update` assumés (R2,
  visibles). La passe stricte qu'il a lancée pour vérifier : 237/85/0 en
  594 s — **102 bloquants tombés** (prévision ~91), le VM (13) sort du top 2
  au profit de SmapiInstaller (25) / SmapiUpdateClient (22). La mesure T11
  devra être refaite proprement sur l'état final de toute façon.
  Vérification à l'écran toujours due (jamais lancée par l'agent — scénario
  minimal dans task-10-report.md, incluant glisser-déposer en échec et
  recherche Nexus). Revue dispatchée : paquet review-e13c5255..0962b068.diff,
  cinq points à verdicter sur le code (hops brèves vs englobantes, commit 2
  hors brief, BisectionRunner 13 lignes hors brief, cohérence des deux
  --update, absence de contournement d'état).
T10: revue — conformité ✅, qualité **approuvée**, 0 critique / 0 important /
  4 mineurs. Vérifié hors diff (un check par risque nommé) : BisectionRunner
  bien @MainActor ; fetchMetadata amorce dont seul le complet ment sur main ;
  uniqueId éteint et non recréé ; anomalyReasons 3 appelants tous dans des
  vues ; downloadStore lecteurs main-confinés ; cliquet +1 DispatchQueue
  cohérent. La règle F3 tenue partout (ModsFolderSizer sur utility, lecture
  lourde des sauvegardes en closure globale, cascade readMaintenanceReport
  entièrement nonisolated — meilleure décision du diff). Commit 2 : guérison
  légitime, sémantique glisser-déposer intacte, force-unwrap supprimé au
  passage. ⚠️ preuves stash/build et mesures strictes = affirmations du
  rapport (protocole).
T10: minor (deferred): rapport :123-126 — « dispatch_queue 156→158 » faux,
  c'est 156→157 (un seul ajout : amorce fetchNexusMetadata ; installDropped
  réutilise le main dispatch existant). Code juste, chiffre du rapport faux.
T10: minor (deferred): nonisolated(unsafe) monté du binding local à la
  propriété (VM:233, downloadStore) — ~10 lecteurs main-confinés perdent
  l'application statique jusqu'à LS. Dette assumée, documentée dans le diff.
T10: minor (deferred): DroppedInstallOutcome porte un Error (existentiel
  non-Sendable) à travers la frontière de fil (ModInstallView:506-509) —
  vert en mode Swift 5, futur sending en mode 6 ; dette L3+/L5.
T10: minor (deferred, préexistant hors diff): VM:4798 — si le VM est libéré,
  guard let self saute la complétion et limiter.signal() n'arrive jamais (le
  limiteur peut mourir à sec après 6 pertes) ; non introduit ici, pour L3.
T10: complete (commits e13c5255..0962b068, review clean, 4 minors deferred)
BASE T11: 0962b068 (contrôleur exécute lui-même, comme T8)
T11: DONE — commit dd90ec87. Passe stricte propre refaite sur l'état final :
  **237 / 85 bloquants / 0 erreur** — reproductible à l'identique de la
  mesure de l'implémenteur T10 (le ⚠️ de la revue est levé par une seconde
  mesure indépendante). Durées 594 s / 4379 s (machine chargée sur la
  seconde — comptes n'en dépendent pas). Étape 2 conforme : le VM (13) sort
  du top 2, remplacé par SmapiInstaller (25) et SmapiUpdateClient (22) —
  cadrage L4. Globales restantes : 1 (SaveNotesStore.shared, la reportée).
  ⚠️ Écart au brief assumé : le brief T11 disait de « noter que la
  vérification à l'écran a eu lieu » — elle n'a PAS eu lieu (aucun agent ne
  lance l'app) ; les docs consignent « due » avec le scénario minimal, la
  mention sera datée quand l'auteur l'aura faite.
T11: complete (commits 0962b068..dd90ec87, docs seulement)
Revue finale dispatchée (fable) : paquet review-1b4f9888..dd90ec87.diff
  (17 commits, 26 fichiers, +969/−285), mission = la somme (interactions
  T7×T9×T10, tri des ~15 minors deferred des revues, état d'arrivée vs spec,
  diagnostics visibles seulement de l'ensemble).

## REVUE FINALE — 2026-09-13 17:58 — PRÊTE À DIFFUSER

Diff lu en 3 passes + 4 checks focalisés hors diff (9 sites T7 tous
explicites ; façade renameModFolder nonisolated à :9084 avec 3 appelants et
zéro résidu ; BisectionRunner @MainActor ; trailers des 17 commits
conformes au Ruling 12). **0 critique, 0 important dans le code, 3 mineurs.**
La somme : T7×T9×T10 composent sans contradiction ; jalon final 237/85
dépasse la promesse (~96) ; le top de la dette a basculé exactement où la
spec le prédisait (cadrage L4 mesuré, pas estimé). Découverte de somme : le
déplacement de endSizeMeasure dans le hop main REFERME une course (begin et
end sérialisés).

**Aucun mineur deferred ne bloque une diffusion.** Tri complet (verdicts) :
clos par les tâches suivantes (Lot A re-mesure, T5 « quatre accès », T6
.serialized + commentaire :170-175, T7 spec static var) ; jamais (coût mur
2 s des tests déterministes, sabotage NSLock 1 exécution, coquilles des
messages de commit T3, chiffres faux des rapports hors dépôt, interleaving
T9) ; **L3+** (justification @unchecked SmapiUpdateClient — L4 retouche le
fichier, defer avant création du bruit DeepL, BisectionSnapshotTests sans
nettoyage /tmp, ProfileApplyJournal:59 silence, pont rollbackFailed non
asserté, doc du type rename, downloadStore nonisolated(unsafe) propriétaire
— la vraie dette, tranche des stores, DroppedInstallOutcome Error
existentiel — L5, VM:4798 limiter.signal — hors diff, commentaire
translate retryDelay — ruled à l'auteur).

Mineurs de la revue finale (deferred) :
- le second patron de traversée (log auto-sautant depuis les workers) à
  nommer au §9 quand L3 convertira la famille log-hop — la somme montre que
  les ~34 restants sont majoritairement CETTE famille, pas un résidu
  aléatoire ;
- noteNexusDownloadProgress : binding local nonisolated(unsafe) redondant
  avec l'annotation sur la propriété, à fondre au prochain passage.

**La seule obligation restante de la branche est humaine : la vérification
à l'écran de L2** — critère de clôture posé par la spec (§4-L2, §6).
Scénario minimal : liste des mods, bascule d'un mod, application d'un
profil, ouverture d'une sauvegarde, recalcul de couverture de traduction,
glisser-déposer en échec, recherche Nexus. Jusque-là, ROADMAP porte « due ».

État de sortie : 4 commits non poussés (e13c5255, 5d1ab393, 0962b068,
dd90ec87) — push sur demande de l'auteur. Workspace conservé en attendant
sa décision (archive de raisonnement, tradition du dépôt) ; suppression
prévue par le skill quand il la demande.

## CLÔTURE — 2026-09-13 18:24

Push 6c49a7f1..dd90ec87 demandé et fait, CI `success`. L'auteur a fait la
vérification à l'écran (« vérif ok », 18:24) : scénario minimal du rapport
T10 exécuté. Mentions datées dans ROADMAP §4 et REFACTORING §9.
**L2 est close. Le chantier P5 tranches L1+L2 est terminé** : 453/202 au
jalon → 427/184 après L1 → 237/85 après L2, tout revu (11 revues de tâche +
re-revue + revue finale « prête à diffuser »), la dette restante est nommée
et cadrée (L3 : famille log-hop ; L4 : SmapiInstaller/SmapiUpdateClient ;
LS : downloadStore). Restent hors périmètre : L3+, et la décision de
suppression du workspace.
