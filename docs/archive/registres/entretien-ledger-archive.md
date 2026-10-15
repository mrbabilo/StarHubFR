# Archive du ledger SDD — entretien-ledger-archive.md

*Copié du ledger SDD le 2026-09-14 au tri de `.superpowers/sdd/` (source
git-ignorée `.superpowers/sdd/2026-09-04-entretien/progress.md`, supprimée dans la foulée).
Plan : `docs/superpowers/plans/2026-09-04-entretien.md`.

2026-09-04-entretien.md

---

# SDD ledger — plan: docs/superpowers/plans/2026-09-04-entretien.md

Base au démarrage : 2d33feb (main, ahead 1 de origin — le commit X55 n'est pas poussé).

## Préflight

Branche : `main`. **Ruling** : on n'ouvre pas de worktree — `CLAUDE.md` dit
« Travailler sur `main` » et « pousser uniquement quand l'utilisateur le demande ».
C'est le consentement explicite du dépôt. Coût si faux : des commits d'un chantier
en cours sur `main` local, annulables par `git reset` tant que rien n'est poussé.

### Table de scan — paires partageant un fichier ou une interface

| Paires | Produit → consomme | Constat |
|---|---|---|
| T1 → T2 | `BackupEntry`, `Protection` → `plan(...)` | cohérent |
| T1 → T3 | même fichier, fonctions disjointes | cohérent |
| T1,T2 → T5 | `Report.freedBytes` appelle `plan(...)` | cohérent |
| T3 → T7 | `stalePreferenceKeys` + `ModRemovalPurge.purge` | cohérent |
| T4 → T7 | `trashItemGrantingWriteAccess` | cohérent, T4 précède |
| T6 → T7 | `L10n.Maintenance.*` cité par les actions | **corrigé au préflight** (voir ruling 2) |
| T5 → T7,T8 | `maintenanceReport`, `buildMaintenanceReport()` | cohérent |
| T7 → T8 | trois actions consommées par la vue | cohérent |
| T1 → toutes | `Package.swift` modifié en T1 seulement | cohérent |

### Cohérence interne de chaque tâche

| Tâche | Tests ↔ code spécifiés | Constat |
|---|---|---|
| T1 | `.init(relativePath:kind:)` public déclaré | cohérent |
| T2 | `keepPerModIsClampedToAtLeastOne` ↔ `max(1, keepPerMod)` | cohérent |
| T2 | `aProtectedBackupDoesNotConsumeAKeptSlot` ↔ protégées retirées de `free` avant le quota | cohérent |
| T3 | voisin `PackDeLuxe` ↔ appartenance simple | cohérent |
| T4 | pas de test unitaire — preuve faite hors dépôt à la compilation | assumé dans le plan |
| T5 | `Report.isEmpty` ↔ test « rien à faire » vs « pas mesuré » | cohérent |
| T7 | `recoverFile` ↔ `RecoverableFile` | **corrigé avant écriture** (voir ruling 3) |
| T8 | pas de canevas SwiftUI — contraintes vérifiables | assumé dans le plan |

### Rulings du préflight

1. **Ruling** : travailler sur `main` sans worktree — convention du dépôt
   (`CLAUDE.md`). Coût si faux : commits locaux à annuler, rien de poussé.
2. **Ruling** : tâches 6 et 7 échangées — les actions citaient `L10n.Maintenance.*`
   avant que la tâche qui crée ces clés ne s'exécute ; le code n'aurait pas compilé.
   Coût si faux : aucun, l'ordre est le seul changement.
3. **Ruling** : `recoverProtectedFile` ne couvre que le cas « mod installé, fichier
   disparu ». `RecoverableFile` exige un `installedPath` et un `installedRoot`
   (`Models/FileRecovery.swift:20-37`) : pour un mod désinstallé — le seul cas réel
   du parc — il n'existe pas de dossier où écrire. L'action y devient « montrer dans
   le Finder ». Coût si faux : l'utilisateur doit passer par le Finder pour un
   fichier qu'on aurait pu replacer automatiquement.
4. **Ruling** : la comparaison des chemins de traduction se fait par segment
   (`$0 == relative || $0.hasSuffix("/" + relative)`), pas par `hasSuffix` nu.
   Vérifié sur l'API réelle : `InstalledTranslationRegistry.byHost` /
   `addonsByHost` portent des `files` relatifs à `Mods/` (`[CP]Cloths and
   Colors/i18n/fr.json`), là où une sauvegarde est relative à sa propre racine
   (`i18n/fr.json`). Un `hasSuffix` nu aurait fait passer le `fr.json` d'un mod
   pour celui d'un autre. Coût si faux : des protections attribuées au mauvais mod.

## Exécution

Task 1: dispatché (haiku — transcription, le brief porte le code complet), BASE 2d33feb
Task 1: implémenté DONE (commit 646ca1e, 5/5 tests) — revue dispatchée (sonnet)
Task 1: revue — spec ✅, qualité approuvée. 1 Important (phase rouge non observée : « no tests found » au lieu d'une erreur de compilation, donc la preuve « le test échoue pour la bonne raison » manque), 3 mineurs.
Task 1: **Ruling** : l'Important est réel mais aucune correction de code n'est possible a posteriori — rejouer la phase rouge après coup serait du théâtre. La question de fond est : *ces tests discriminent-ils ?* Ronde 1 = prouver par mutation (inverser le prédicat de `protection`, constater le rouge, revenir). Coût si faux : des tests qui passeraient quel que soit le code, sur la règle qui protège les fichiers de l'utilisateur.
Task 1: minor (deferred): `guard !entry.userFiles.isEmpty` est un no-op — dicté par le plan, comportement identique sans lui.
Task 1: minor (deferred): `Protection.none` entre en collision avec `Optional.none` — sans effet ici, **risque réel en tâche 2** où le plan écrit `protections[entry.id] ?? .none`. Porté au dispatch de T2.
Task 1: **Ruling** : trailer de commit — le plan figeait « Claude Opus 5 (1M context) », `CLAUDE.md` exige le modèle réel. `CLAUDE.md` prime, le commit `646ca1e` est correct, la contrainte globale du plan est corrigée. Coût si faux : aucun, l'historique nomme le vrai auteur.
Task 1: fix round 1/5 — mutation du prédicat : 4/5 tests rougissent. Le 5e (`aBackupWithoutAnyUserFileIsNeverProtected`) n'atteint pas le prédicat, il sort sur le `guard` d'entrée : cohérent avec le mineur « guard no-op », et le test reste légitime (il épingle le contrat vide → `.none`). Arbre propre, rien de committé.
Task 1: **Ruling** : pas de re-revue scopée — la ronde n'a produit **aucun diff** (la preuve demandée était documentaire). Relire un diff vide n'apprend rien. Le constat Important est adressé : les tests discriminent là où le prédicat les atteint. Coût si faux : un test non discriminant resterait dans la suite ; mesuré à un seul, et il couvre un cas barrière réel.
Task 1: complete (commits 2d33feb..646ca1e, revue clean après ronde 1)
Task 2: dispatché (haiku), BASE 646ca1e. Portés au dispatch : la collision `Protection.none` / `Optional.none` (mineur T1) et l'exigence de prouver la phase rouge par une vraie erreur de compilation.
Task 2: implémenté DONE (commit d552e8e, 7/7 tests ; suite complète 2158). Phase rouge correcte cette fois : `type 'MaintenanceInventory' has no member 'plan'`. Aucune ambiguïté `.none` rencontrée. Revue dispatchée (sonnet).
Task 2: revue — spec ✅, qualité approuvée, 0 critique / 0 important. Le relecteur a vérifié la collision `.none` par un repro Swift isolé : clé absente → non protégé, `.soleCopy` → protégé. Le contexte du `if case` force le côté droit de `??` vers `Protection`, jamais vers `Optional`.
Task 2: minor (deferred): aucun test ne couvre deux sauvegardes du **même mod au même timestamp** (ordre de tri indéterminé). **Mesuré sur le parc avant de reporter : 0 paire (mod, timestamp) en doublon exact sur 923 entrées.** Non atteignable aujourd'hui.
Task 2: minor (deferred): les mesures chiffrées vivent dans le commentaire des tests, pas dans la doc de production — choix du plan, pas de l'implémenteur.
Task 2: complete (commits 646ca1e..d552e8e, revue clean)
Task 3: implémenté DONE (commit 76719c5, 6/6 tests, phase rouge correcte). Revue dispatchée (sonnet) — consigne appuyée : chercher un cas où une clé **légitime** serait déclarée morte, ce serait Critique (la règle décide d'effacer des réglages).
Task 4: dispatché (haiku) en parallèle de la revue T3 — **Ruling** : parallélisme autorisé ici, T4 ne touche que `ModZipInstaller.swift` et ne dépend d'aucune sortie de T3 ; aucun conflit de fichier ni d'ordre possible. Coût si faux : si la revue T3 exigeait un correctif, il se poserait après le commit T4 — sans conséquence, les deux fichiers étant disjoints. BASE 76719c5.
