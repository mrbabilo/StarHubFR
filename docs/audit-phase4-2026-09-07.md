# Audit Phase 4 — Tests/ et run_tests.sh

**Date** : 2026-09-07
**Scope** : `Tests/` — 171 fichiers Swift Testing, 2 359 `@Test`, 239 suites,
145 cibles en miroir des modules Core — plus `run_tests.sh`
**Reference** : `docs/prompt-audit.md` (phase 4), pièges de `CLAUDE.md`
(« les tests n'écrivent jamais dans le vrai Application Support », « un cache
global impose des tests `.serialized` »)
**Précédents** : Phase 1 (cœur, par tranches), Phase 2 réseau
(`audit-phase2-2026-09-07.md`), Phase 3 persistance
(`audit-phase3-2026-09-07.md`)

---

## 1. Ce que la mesure a établi

La particularité de cette phase : presque tout se juge **par la mesure**, pas
par la lecture. Chaque chiffre ci-dessous a été relevé le jour même.

- **`run_tests.sh` est honnête** : `set -euo pipefail`, `DEVELOPER_DIR` posé sur
  Xcode.app, aucun pipe entre `swift test` et l'exit code.
- **2 359 tests / 239 suites, verts** — trois runs complets dans la journée.
- **Pollution du vrai magasin : zéro.** Un marqueur temporel posé immédiatement
  avant un run complet, puis `find … -newer` sur
  `~/Library/Application Support/StarHubTH` : **aucun des 13 102 fichiers
  touché** ; `com.appleboiy.StarHubTH.plist` inchangé (md5 identique avant /
  après). Le piège historique — 582 exécutions ayant pollué de vrais backups
  avant l'injection des managers — est éradiqué, et c'est vérifié **en
  exécution**, pas en lecture seule.
- **Aucune référence à `applicationSupportDirectory` dans `Tests/`** (145
  dossiers) : tout chemin de données passe par injection.
- **Zéro écriture `UserDefaults.standard`** dans les tests. Les deux usages de
  `UserDefaults(suiteName:)` (`ModVersionAnchorStoreTests`,
  `ModUpdateSnoozerTests`) créent des domaines **UUID-jetables** avec
  `removePersistentDomain` — pas de collision possible entre tests parallèles.
- **Zéro assertion vide** (`#expect(true)`, `1 == 1`), **zéro `.skip(`**.
- **Zéro singleton `.shared`** touché par les tests.
- **Concurrency tenue** : `SaveManager.regexCache` (l'unique dictionnaire
  statique mutable hors VM) est protégé par un `NSLock` dédié en
  read-compile-write ; la seule suite qui touche le cache de mémoïsation
  (« Cache de lecture des sauvegardes ») est `.serialized` ;
  `SaveBOMPreservationTests` et `XMLEntitiesTests` instancient des
  `SaveManager()` locaux. Les 7 suites `.serialized` du dépôt correspondent
  chacune à un état mutable global réel (`BisectionSnapshot.storageDirectory`,
  `ProfileApplyJournal.storageDirectory`, `DeepLClient.lastResponse`, clients
  réseau stubbés) — aucune n'est décorative, aucun état global n'en manque.
- **Le miroir `Package.swift` ↔ `Tests/` est exact** : 145 dossiers, 145 cibles
  déclarées, `comm` vide dans les deux sens, aucun `.swift` orphelin à la
  racine de `Tests/`. **Aucun dossier de tests qui ne s'exécute jamais** — le
  défaut le plus sournois possible ici (une suite qui ne tourne pas se donne
  pour verte) est écarté par croisement exhaustif.

## 2. Échantillon des tests récents (X78–X88)

Les tests ajoutés avec les deux vagues de durcissements réseau jugent le
**comportement observable**, pas une paraphrase du correctif : le `max_tokens`
est décodé du corps réellement envoyé au stub HTTP, l'ordre d'arrivée
Premium/free de la file est rejoué tel que mesuré, les scénarios réels
(dialogue de 800 caractères, clic in-app puis `nxm://` partagé) sont cités en
commentaire. Un micro-défaut relevé et corrigé au passage : la déclaration
`@Test func maxTokensIsClamped` était indentée à 8 espaces au lieu de 4
(`530459b`).

**Constat de paperasse voisin, corrigé au passage** : les releases v1.37.1 à
v1.37.3 — sorties dans la journée — n'avaient jamais été consignées au
`CHANGELOG.md` (leurs 14 entrées dormaient dans `[Unreleased]`). Or le
CHANGELOG est copié dans le bundle par `build_app.py` et lu dans l'app : les
trois bundles embarquaient un `[Unreleased]` en tête au lieu des sections
versionnées. Les sections rétroactives ont été posées au moment de la release
v1.37.4 (`261340c`).

## 3. Pistes écartées, avec la raison

1. **Relecture intégrale des 171 fichiers** — les trois quarts ont été écrits
   ou relus par les tranches d'audit Models/Views/VM (les TDD gaps y ont été
   corrigés au fil, 7 en septembre) ; cette passe a couvert par la mesure ce
   qui se mesure (exécution, isolation, miroir, concurrence) et par
   échantillon ce qui se lit. Une relecture exhaustive n'a pas d'hypothèse de
   défaut à tester — elle coûterait une session pour un rendement attendu nul.
2. **Chasse aux fixtures mensongères** (l'état que le vrai producteur ne génère
   jamais — défaut déjà payé une fois sur le lot JSON) — risque réel mais sans
   hypothèse actuelle : l'échantillon récent est sain, et les fixtures les plus
   anciennes à risque ont été réécrites quand leur audit l'a demandé. À
   rouvrir uniquement contre une suite précise, jamais en ratisillage.

## 4. Verdict

Le volet tests est **sain, et vérifié par la mesure** — c'est la phase du
brief qui se conclut sans aucun correctif de logique. Un seul geste : une
réindentation d'une ligne, et le rattrapage CHANGELOG des releases 1.37.1–1.37.3
documenté ci-dessus.

**Suite du brief** (`docs/prompt-audit.md`) : Phase 5 — `Package.swift`,
`Info.plist`, `build_app.py`, `release.py`, `check_standards.py`,
`.standards-baseline.json`, `check_sources.py`, `.sources-baseline.json`,
`.mcp.json` — audités **en lecture** : que chaque script rende un code de
sortie non nul quand il doit échouer (le dépôt a payé cher des scripts rendant
`exit 0` sur un échec) et qu'un `--update` reste un geste explicite. Ne pas
exécuter `check_sources.py` en passe complète depuis un agent (elle sonde le
réseau) — `--offline` seul.
