# Archive du ledger SDD — ancrage-versions-lot-a-ledger-archive.md

*Copié du ledger SDD le 2026-09-14 au tri de `.superpowers/sdd/` (source
git-ignorée `.superpowers/sdd/2026-08-12-ancrage-versions-lot-a/progress.md`, supprimée dans la foulée).
Plan : `docs/superpowers/plans/2026-08-12-ancrage-versions-lot-a.md`.

2026-08-12-ancrage-versions-lot-a.md

---

# SDD ledger — plan: docs/superpowers/plans/2026-08-12-ancrage-versions-lot-a.md

Branche : `main` (conforme à CLAUDE.md:64 — « Travailler sur `main` »).
Base au démarrage : 267b94d.

Un ledger étranger existe à l'ancien chemin plat `.superpowers/sdd/progress.md` —
laissé en place, ce n'est pas le nôtre.

## Journal

Task 1: complete (commits 267b94d..d7f6237, review clean)
Task 1: minor (deferred): l'enum `Origin` ne documente pas qu'il s'appuie sur le
  `Decodable` synthétisé pour rejeter une valeur inconnue ; un `init(from:)`
  personnalisé ajouté plus tard casserait la garantie sans que le test l'explique.
  Une ligne de commentaire sur l'enum suffirait.
Task 1: ⚠️ du relecteur (état réel des tests/build) résolu par le contrôleur :
  714 tests verts, `python3 build_app.py` [SUCCESS], vérifiés à 267b94d..d7f6237.
Task 2: complete (commits d7f6237..5e0835f, review clean)
Task 2: minor (deferred): la branche « fichier secondaire + facts nil + ancre
  préexistante » n'est pas testée ; seule la variante fichier principal l'est.
Task 2: minor (deferred): `afterInstall` sur fichier secondaire réécrit
  `anchoredAt` alors que ni la version ni l'origine ne changent. Imposé par le
  plan, aucun test ne l'observe — à signaler à qui consommera `anchoredAt`.

## Environnement — 2026-08-12 22:5x

`swift test` échoue dans le bac à sable d'outils du contrôleur :
`sandbox-exec: sandbox_apply: Operation not permitted` — SwiftPM ne peut pas
créer son propre sandbox d'évaluation de manifeste à l'intérieur. Reproductible,
non lié au code : hors sandbox, **736 tests passent** au HEAD f65874e.
`python3 build_app.py` n'est pas affecté ([SUCCESS]).

Conséquence sur le procédé : les implémenteurs ne peuvent plus produire de preuve
RED/GREEN. Ils doivent rapporter l'erreur verbatim et ne jamais affirmer un vert
non constaté ; le contrôleur vérifie à chaque frontière de tâche hors sandbox.

## Journal (suite)

Note : deux commits de david pendant l'interruption de session —
c9b009a (docs README, hors plan) et f65874e (2 tests fermant le minor
« précédence des faits / asymétrie d'origine » consigné pour la Task 2).
CORRECTION : la panne `swift test` était TRANSITOIRE. Elle a disparu d'elle-même
à 22:5x ; `./run_tests.sh` rend 736 tests verts dans le sandbox normal. Les
implémenteurs peuvent de nouveau produire leurs preuves RED/GREEN.
Task 3: revue = Needs fixes (2 Important) — voir ci-dessous.
Task 3: fix round 1/5 (3 addressed, 0 open ; commits 257de39..316bdaa)
  - Finding 1 (cliquet non justifié) : le re-relecteur l'a dit NOT ADDRESSED,
    mais sur du matériel incomplet — `review-package` ne transporte que le SUJET
    des commits, pas leur corps. Vérifié par le contrôleur : le message de
    316bdaa porte la justification en point 2. ADDRESSED.
    ⚠️ Limite d'outillage à retenir : pour toute revue portant sur un message de
    commit, le fournir en clair dans le prompt.
  - Finding 2 (migration aveugle) : ADDRESSED, RegistryMigrationOutcome à 3 cas,
    les 5 branches conformes au contrat arbitré par david, 2 tests neufs qui
    échoueraient sur l'ancienne implémentation.
  - Finding 3 (compte rendu sans persistance) : ADDRESSED en sous-produit.
Task 3: complete (commits 5e0835f..316bdaa, review clean après 1 round)
  Vérifié par le contrôleur : 738 tests verts, build [SUCCESS].
  Note : commits de david intercalés — f65874e (tests), 321842f (i18n), hors plan.
Task 4: implémentée (316bdaa..7da44a9), revue = Needs fixes (2 Important) :
  - dédoublonnage non déterministe sur égalité stricte (même pause, même version) :
    le premier rencontré gagne, donc les updateKeys envoyées dépendent de l'ordre
    du scan disque — exactement ce que la conception interdit ;
  - les 2 tests de priorité placent le gagnant en DERNIER : un « le dernier écrit
    gagne » les passerait tous.
  Fix round 1 dispatché : fusionner les updateKeys à égalité (union triée),
  + variantes ordre inverse + test de fusion.
Task 4: fix round 1/5 (1 addressed, 1 open ; commits 7da44a9..53beb42)
  - Finding 2 (tests incapables d'échouer) : ADDRESSED, 4 tests neufs écartent
    « le premier gagne » ET « le dernier gagne ».
  - Finding 1 (ordre-dépendance) : PARTIEL. Les updateKeys et le manualNexusId
    sont devenus commutatifs, mais `merge()` retient `candidate.manifestVersion`
    du pliage. Or l'égalité est SÉMANTIQUE, pas textuelle : "1.0" et "1.0.0"
    comparent égal. L'ordre-dépendance a déménagé des clés vers la version, et
    atteint Entry.installedVersion quand aucune ancre n'existe.
  Fix round 2 dispatché : plus petite chaîne lexicographiquement + test des deux
  ordres avec "1.0" / "1.0.0".
NOTE PROCÉDÉ : le plan imposait `Co-Authored-By: Claude Opus 5` en dur dans
  chaque bloc de commit. C'est une ERREUR de ma part — CLAUDE.md exige le modèle
  qui écrit réellement, « jamais un nom figé ». Les 5 premiers commits du lot
  sont donc mal attribués (écrits par haiku, signés Opus 5). Le plan est corrigé
  pour la suite ; l'implémenteur de la Task 4 avait déjà signé Haiku 4.5 de
  lui-même, contre la consigne — il avait raison.
Task 4: fix round 2/5 (1 addressed, 0 open ; commits 53beb42..d76feaf)
  - résidu du Finding 1 : ADDRESSED. `[a, b].sorted().first` est commutatif par
    construction. Le re-relecteur a tracé le nouveau test contre le code d'avant :
    il échoue bien sur les deux assertions. Aucun autre champ de merge() ne reste
    dépendant du pliage (isPaused est garanti égal par compare(), uniqueId aussi).
Task 4: minor (deferred): `.sorted().first ?? candidate.manifestVersion` — le
  fallback est du code mort, le tableau littéral a toujours deux éléments.
Task 4: complete (commits 316bdaa..d76feaf, review clean après 2 rounds)
  Vérifié par le contrôleur : 756 tests verts, build [SUCCESS], cliquet inchangé.
Task 5: complete (commits d76feaf..c18b09b, review clean du premier coup)
  Vérifié par le contrôleur : 767 tests verts, build [SUCCESS], cliquet inchangé.
  ⚠️ résolu : la ligne « Interfaces » du plan annonçait `blocker(for:) -> Blocker?`
  alors que son bloc de code fait `-> Blocker`. Incohérence du PLAN, pas du code ;
  le non-optionnel est le bon choix (un optionnel inviterait à jeter les erreurs
  non reconnues). Aucun changement de code requis.
Task 5: minor (deferred): `anAlmostEmptyMetadataStillDecodes` passe aussi si
  `metadata` est nil — ajouter `#expect(mods[0].metadata != nil)`.
Task 5: minor (deferred): le « lève plutôt que [] » n'est testé que sur des octets
  illisibles, pas sur du JSON valide de mauvaise forme (réponse non-200).
Task 5: minor (deferred): l'ordre des cas dans la doc de `Blocker` ne suit pas
  l'ordre réel de la cascade.
Task 6: complete (commits c18b09b..228d353, review Approved)
  Vérifié : 763 tests (767 − 4 supprimés), build [SUCCESS], cliquet inchangé.
  Suppression jugée complète et symétrique, aucun commentaire devenu menteur,
  et les 4 tests supprimés ne verrouillaient QUE la règle retirée
  (`aVersionChangeRestampsTheInstallDate` a bien été conservé).
Task 6: ⚠️ ACCEPTANCE À PORTER EN TASK 8 (Important, pas un défaut de ce diff) :
  au premier scan après ce commit, les ~52 dossiers dont la `version` au registre
  était la version Nexus verront `installedAt` ré-estampillé à `now`, alors que
  le DISQUE n'a pas changé — seule la lecture a changé. Or `installedAt` alimente
  le tri « date d'installation » (ModListView:39-40,699) et le badge de ligne
  (ModListView:1140) : david verra 52 mods non touchés marqués « installés
  aujourd'hui », en tête de son tri. Le relecteur a vérifié que la détection de
  mise à jour reste correcte pour ces 52 (leur manifest est en retard, donc pris
  par la comparaison de versions), mais le faux signal d'affichage est réel et
  permanent. À trancher avec david.
Task 6: minor (deferred): reformulation de `vm_manifest_version_fixed` (en+fr)
  hors périmètre du brief — exacte au regard du code, parité préservée, et
  signalée dans le commit. Mais c'est une chaîne visible par l'utilisateur :
  décidée seule là où elle aurait dû être rapportée.
Task 7: BLOCKED puis débloquée. L'implémenteur a fait exactement ce qu'on lui
  demandait : le code du brief fait monter le cliquet (dispatch_queue 120→124,
  try_optional 188→189), il s'est arrêté et l'a rapporté au lieu de lancer
  `--update`. Step 2 vérifié au passage : `NexusRequestBuilder.userAgent` existe
  bien sous ce nom.
  DÉCISION du contrôleur : ne PAS relever le cliquet. Le cliquet a raison et le
  code du plan avait tort — `DispatchQueue.global` + `DispatchSemaphore` pour
  sérialiser des lots réseau est un patron daté, et c'est lui qui portait le
  risque d'interblocage. Réécriture en async/await : plus de sémaphore, plus de
  fil bloqué, et le `try?` de l'encodage devient un `try` qui propage une
  Failure.decoding au lieu d'avaler. L'API publique (rappels) ne change pas,
  donc le plan de la Task 8 reste valide.
Task 7: complete (commits 228d353..bfbc23f, review Approved)
  Vérifié : build [SUCCESS], cliquet REVENU À SA BASE (dispatch_queue 120,
  try_optional 188), 763 tests inchangés (fichier hors module de test, voulu).
  Le relecteur a validé les 4 points : sérialité réelle (un seul await par tour,
  aucune tâche concurrente), fil principal garanti sur les 3 sorties dont le
  retour anticipé, `failure!` sûr par construction, aucune décision métier dans
  le fichier. Il note aussi que retirer `[weak self]` corrige un bug latent de
  la version rejetée : `guard let self else { return }` aurait pu ne JAMAIS
  appeler completion si le client était libéré en vol.
Task 7: Important plan-mandated RÉSOLU EN TASK 8 (pas de question à david) :
  `Result<[Mod], Failure>` ne distingue pas un succès partiel d'un complet. Sur
  7 lots, un 503 au 4e laisse ~510 mods sans verdict, que l'appelant prendrait
  pour « à jour ». Pas besoin de changer la signature : Task 8 reçoit `entries`
  ET `mods`, donc elle voit qui n'a pas répondu. Plan mis à jour — un mod absent
  de la réponse CONSERVE sa ligne précédente, et l'écart est journalisé.
Task 7: minor (deferred): pas de délai global ni d'annulation — 7 lots × 120 s.
Task 7: minor (deferred): rappels non-Sendable capturés dans un Task @Sendable —
  muet en Swift 5, diagnostiqué en Swift 6 strict.
Task 8: implémentée (28ace1a), DONE_WITH_CONCERNS, amendement en cours.
  Cliquet : abbreviation_vm +1 (1460→1461), forcé par l'unique appel
  vue→ViewModel du Step 4. DÉCISION du contrôleur : RELEVER, contrairement à la
  Task 7. La règle qui distingue les deux cas — un compteur qui monte parce
  qu'on SUIT la convention du dépôt se relève ; un compteur qui monte parce
  qu'on introduit un patron qu'on regretterait se corrige. Ici `vm.` est
  l'idiome, il y en a déjà 1460 ; le contourner rendrait le code moins conforme.
  Écarts au brief signalés par l'implémenteur, à faire juger par la revue :
  - il a CORRIGÉ un bug de mon code de filtre `unanswered` (mélange UniqueID /
    NexusID qui pouvait perdre ou dupliquer des lignes d'une passe à l'autre) ;
  - il a déplacé la migration de `init()` vers `performInitialLoad()` pour ne
    pas bloquer l'écran de lancement sur ~900 entrées JSON ;
  - `NexusUpdateChecker.shared.check(...)` est devenu inatteignable sans être
    supprimé — laissé volontairement, hors périmètre.
Task 8: complete (commits bfbc23f..0a634ff, review Approved)
  Vérifié : build [SUCCESS], 763 tests, cliquet touche uniquement abbreviation_vm.
  Le relecteur a TRACÉ les deux exigences dures de bout en bout plutôt que de
  croire le rapport : lot 4 en échec → 510 mods sans réponse → conservés et
  journalisés ; panne totale → nexusUpdates intact. Ordre de lecture de l'ancre,
  unicité de la migration et son antériorité sur le premier lecteur du registre :
  vérifiés aussi.
  Il confirme que la correction du filtre par l'implémenteur était NÉCESSAIRE :
  `ModUpdate.id` est `{ nexusModId }`, et mon code du plan ne comparait qu'à
  `mods.map(\.id)` (toujours des UniqueID) — il n'aurait jamais reconnu une ligne
  antérieure clé sur un identifiant Nexus.
  Il relève aussi que ma description de l'exigence 3 était fausse : le code passe
  `facts: nil`, pas `fileId: 0` / `fileUploadedAt: now`. Le code est bon, c'est
  ma consigne de revue qui décrivait mal le brief.
Task 8: ⚠️ Important PLAN-MANDATED — à trancher par david :
  `modForNexusUpdate` (VM:2741-2753, MainView:734) cherche le mod par
  `effectiveNexusModId == update.nexusModId`. Or `applySmapiResults` met un
  UniqueID dans `nexusModId` quand smapi.io ne rend pas de `metadata.nexusID`.
  La recherche échoue alors, et le badge Activé/Désactivé de l'écran des mises à
  jour est faux. Le brief interdisait explicitement de toucher ce code (« lot C »).
Task 8: minor (deferred): MainView:712 teste `rate_limited`, chaîne qui ne peut
  plus être produite — message générique à la place sur un 429.
Task 8: minor (deferred): progression par lot (3/7) au lieu de par mod (450/960).
Task 8: minor (deferred): `NexusUpdateChecker.shared.check(...)` est mort.
Task 8: minor (deferred): `unverifiableMods` / `affirmInstalled` pas encore
  consommés par une vue (périmètre déclaré, lot C).
Task 10 (hors plan, décidée par david après la revue de la Task 8) : complete
  (commits 0a634ff..f788149, 3 commits + 4ae1bf9 pour le reliquat de commentaire)
  - 36ab125 : le message de limitation de débit remis sous smapi.io (un .http(429)
    repose `nexusCheckError = "rate_limited"`, la vue reste inchangée) ;
  - 0f511a8 : `modForNexusUpdate` accepte aussi l'UniqueID — le badge
    Activé/Désactivé n'est plus faux pour les mods sans identifiant Nexus ;
  - f788149 : `NexusUpdateChecker.check()` retiré, avec NexusUpdateMerge et ses
    8 tests (seul appelant), entrées Package.swift comprises.
  Vérifié : build [SUCCESS], 755 tests (763 − 8), cliquet inchangé.
  L'agent a signalé `dedupeInterval`/`lastCheckKey`/`hasRecentCheck()` comme
  devenus orphelins SANS les supprimer — c'était la consigne, et il l'a tenue.
  À reprendre au lot C si on veut finir le ménage.
Task 9: complete (commit 3b6f65a) — écrite par le contrôleur, pas dispatchée :
  david a interrompu trois dispatches de suite, signal clair qu'un aller-retour
  d'agent pour une ligne de changelog ne valait pas son prix.
  En la relisant, un défaut trouvé : l'entrée « A detected update no longer
  vanishes… » décrivait NexusUpdateMerge, supprimé en Task 10. Jamais publiée
  (les deux vivaient dans [Unreleased]), donc fondue dans la nouvelle plutôt que
  laissée à décrire du code absent.
ÉTAT : 12 commits, 755 tests verts, build [SUCCESS], arbre propre, rien de poussé.

## REVUE FINALE DE BRANCHE — 2026-08-14 — À CORRIGER AVANT FUSION

3 Critical, confirmés par grep du contrôleur (pas seulement rapportés) :
C1 — les mises à jour trouvées ne sont JAMAIS persistées. `applySmapiResults`
     n'appelle pas `saveCachedUpdates` ; son seul appelant restant est
     `dismissUpdate`. Or VM:722 réamorce `nexusUpdates` depuis `cachedUpdates()`
     au lancement. Les 41 lignes meurent à la fermeture, et l'utilisateur revoit
     au lancement suivant la liste écrite par le CODE BOGUÉ. L'ancien `check()`
     persistait ; la garantie est partie avec lui, sans remplaçant.
C2 — `ModVersionAnchorRules.afterDiskChange` n'a AUCUN appelant. `.diskObserved`
     ne se produit jamais. Un mod ancré puis mis à jour à la main envoie
     éternellement l'ancienne version → fausse mise à jour permanente. Le défaut
     d'origine en miroir. La règle et ses 7 tests existent ; il manque l'appel
     dans `syncInstalledModRegistry`.
C3 — `affirmInstalled` n'est atteignable depuis aucune vue. Combiné à C2, une
     fausse ligne ne peut être ni corrigée ni écartée durablement.

Important : I1 changelog surpromettait (CORRIGÉ, e993448) ; I2 `ModUpdate.id` en
doublon donné à ForEach (58 id Nexus portés par plusieurs dossiers) ; I3 aucune
purge des lignes de mods désinstallés (seule règle de NexusUpdateMerge perdue
sans remplaçant) ; I4 le glisser-déposer ne pose aucune ancre ; I5
`anchorInstalledMods` ignore les manifests dont `Version` est un objet ; I6 la
vérification reste bloquée derrière une clé API Nexus dont smapi.io n'a pas besoin.

Les 52 `installedAt` : AVANT FUSION. Corruption irréversible, fenêtre d'un seul
lancement, aucune source pour reconstituer les dates. Correctif à portée du lot A :
`migrateAwayFromNexusVersion` sait déjà quels dossiers portaient un `nexusVersion`.
