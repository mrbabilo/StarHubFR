# Archive du ledger SDD — guided-bisection-ledger-archive.md

*Copié du ledger SDD le 2026-09-14 au tri de `.superpowers/sdd/` (source
git-ignorée `.superpowers/sdd/2026-07-31-guided-bisection/progress.md`, supprimée dans la foulée).
Plan : `docs/superpowers/plans/2026-07-31-guided-bisection.md`.

2026-07-31-guided-bisection.md

---

# SDD ledger — plan: docs/superpowers/plans/2026-07-31-guided-bisection.md
Pre-flight: 2 défauts du plan corrigés avant exécution (test vacuous sur la fermeture ; `_ = s` mort dans start()).
Task 1: implemented (commit a58bf13, 244/244 tests) — review ❌
Task 1: plan-mandated finding, escalated to human. Critical: `suspects` non fermé → essai vide → non-convergence. Important: essai de confirmation non fermé. Les deux viennent du code de référence du plan (Step 4), copié verbatim.
Task 1: fix round 1/5 (2 addressed, 1 nouveau Critical — grappe cyclique : la fermeture vers le haut reconstitue la grappe, la recherche ne rétrécit plus ; commits a58bf13..9feedfc)
Task 1: minor (deferred): `.reproducing` ne court-circuite pas vers `.confirming` à un seul candidat
Task 1: minor (deferred): `total` est une estimation statique — `step` peut le dépasser
Task 1: fix round 2/5 (1 addressed, 1 nouveau Important — session à un seul candidat conclut `.inconclusive` au lieu de `.confirming` ; commits 9feedfc..4fa0d76)
Task 1: minor (deferred): `withRequiredDependencies` ferme sur `ordered` et non sur `suspects` — un mod déjà disculpé peut revenir dans un essai, et donc dans l'ensemble suspect. À trancher à la revue finale.
Task 1: fix round 3/5 (1 addressed, 0 open — court-circuit à un seul candidat ; commits 4fa0d76..13343c0)
Task 1: complete (commits 981e358..13343c0, review clean)
--- RECONSTRUIT DEPUIS GIT (le ledger avait décroché de la réalité) ---
Task 2: complete (52bb26e — instantané de la modlist)
Task 3: complete (f41361a — textes sans jargon en/fr)
Task 4: complete (d9119b1 — câblage ViewModel)
Task 5: complete (f4f6e8c — carte de guidage)
Task 6: complete (342ae50 — documentation)
Post-tâches: a9bd4cb (6 défauts de la revue Tasks 4-5), 2775043 (isolation de concurrence), 9b6d01b (Localizable.strings)
État vérifié 2026-07-31 18:0x : 253 tests verts, build vert.
Reste : revue finale de branche (981e358..HEAD).
Revue finale (981e358..9b6d01b, opus) : 2 Critical, 5 Important, 4 Minor.
  C1 `closeAfterLaunch` fait quitter l'app à chaque étape → fonctionnalité inutilisable avec ce réglage.
  C2 une restauration partielle efface l'instantané → état mi-pausé irrécupérable.
  I1 l'indice du journal peut venir de la session précédente → pousse à la mauvaise réponse.
  I2 pas de sérialisation avec applyProfile/toggleMod pendant la fenêtre d'attente.
  I3 l'offre de restauration d'une session interrompue n'est visible que dans l'onglet Diagnostic.
  I4 les textes de fin promettent des actions absentes ; ROADMAP coche A4-T5 à tort.
  I5 l'attente de fin de session (spec §cycle automatique) n'est pas implémentée.
  Triage des 3 différés : #1 à corriger (une ligne), #2 et #3 acceptés (argument de terminaison vérifié par le relecteur).
Vague de correctifs finale : commit 19d401e (C1, C2, I1, I3, I4, différé #1, 2 mineurs) — 257 tests, build vert.
Re-revue de la vague (opus) : PROPRE. 8/8 corrigés, trou d'état mi-recherche vérifié fermé, profils non régressés.
  Nouveau Minor (non bloquant) : `bisect_concluded_body` affirme « tous vos autres mods sont réactivés » alors que
  `state = .concluded` est posé AVANT la restauration ; si celle-ci échoue partiellement, l'affirmation reste à l'écran.
