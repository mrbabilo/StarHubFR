# Audit Phase 5 — Configuration, build & déploiement

**Date** : 2026-09-07
**Scope** : `Package.swift` (905 l.), `Info.plist`, `build_app.py` (379 l.),
`release.py` (128 l., lu et exécuté pour la release v1.37.4),
`check_standards.py` (257 l.), `check_sources.py` (630 l.), `.mcp.json`, les
deux baselines — **en lecture** pour tout, exécution seule pour les vérifications
sans effet de bord (`swift build`, `swift test`, deux builds de fingerprint)
**Reference** : `docs/prompt-audit.md` (phase 5), `AGENTS.md` §2 (« les deux
cliquets »), la mémoire des scripts rendant `exit 0` sur un échec
**Précédents** : Phases 1–4 (`audit-phase{1-2,2,3,4}-2026-09-*.md`)
**Avec ce document, les cinq phases du brief sont closes.**

---

## 1. Constats corrigés

### X91 — trois fichiers de `Models/` n'ont jamais été dans le module testable

La cible `StarHubTHCore` liste ses sources **explicitement** — l'envers exact du
piège « dossier Tests/ sans cible » fermé en Phase 4 : un fichier déplacé dans
`Models/` mais oublié de la liste est compilé par `build_app.py` (qui fait un
`os.walk` de tout l'arbre), donc présent dans l'app, et **invisible de
`swift build` comme des tests**. La mesure (liste ↔ disque, racine + `Models/`)
a rendu onze non-listés : sept exclus pour raison lisible (l'app, le ViewModel,
les vues, et la grappe non testable documentée — `NexusSearchClient`,
`NexusDownloader`, `KeybindScanService`, `SmapiInstaller`), et **trois sans
raison** :

- `Models/ModCompatibilityStore.swift` (ajouté `7177e87`, jamais listé) —
  Foundation pur, store de persistance audité en Phase 3 à la main, jamais
  testable ;
- `Models/ModDetailCache.swift` (`3efd1df`) — Foundation pur ;
- `Models/NexusFileDownload.swift` (`3e07ee4`) — Foundation pur.

Corrigé : ajoutés à la liste, preuve par la compilation — `swift build` vert,
**2 359 tests verts**. Aucun effet sur l'app (le module Core ne sert qu'aux
tests ; `build_app.py` compile l'arbre entier lui-même).

**Le quatrième candidat a été tenté et retiré** : `ModListFilters.swift`
(extrait du ViewModel vers `Models/` par `92b0510` — donc écrit pour être
testable, et jamais entré dans le module testable) ne compile pas dans le Core :
il dépend de `FrenchTranslationScope`, défini dans `Views/ModListView.swift`.
Son exclusion est **technique**, pas un oubli — la lever exige de descendre
l'enum dans `Models/` (axe F1, pas cet audit).

### Le fingerprint de `compile_commands.json` ignorait les arguments

Le commentaire de `write_compile_commands` prétendait « same files, same args →
skip », mais le fingerprint ne hashait que `(file, directory)` : un changement
de deployment target ou de flag dans `build_swiftc_command` aurait laissé
SourceKit-LSP sur une commande périmée sans jamais se régénérer. Corrigé : le
fingerprint couvre les arguments. Vérifié en deux passes : régénération
exactement une fois au premier build, skip au second.

## 2. Exit codes — le critère central du brief

« Que le script rende bien un code de sortie non nul quand il doit échouer » —

- **`build_app.py`** : les huit chemins d'échec (parité L10n, clés `L10n.swift`,
  fichiers Swift absents, compilation incrémentale, objets manquants, édition de
  liens, codesign, cliquet) finissent tous en `sys.exit(1)` ou
  `raise SystemExit(1)`. L'échec cliquet de la session (print_calls +1) rendait
  bien 1 — l'affichage « exit 0 » venait du leurre zsh (`PIPESTATUS` est
  bash-only ; consigné en mémoire avec le remède).
- **`check_standards.py`** : `sys.exit(main())`, `return 1` sur les trois
  familles (baseline absente, régression, règle inconnue). `--update` est le
  seul chemin d'écriture de la base et **n'est jamais invoqué par
  `build_app.py`** (l'appel post-build est nu, ligne 365). Un flag inconnu
  (`--help` compris) est ignoré et tombe en mode vérification — sûr, quoique
  surprenant (anecdote déjà connue du handoff).
- **`check_sources.py`** : les codes 0/1/2 annoncés en tête sont tenus ;
  baseline illisible → 2, écart → 1, injoignable → **reporté, pas compté**
  (une panne de réseau ne se lit pas comme un changement). Le `--update` est un
  **merge** prudent : une source injoignable garde sa référence au lieu d'être
  écrasée par du vide. Et `gh` est invoqué avec `stdin=DEVNULL` — le piège du
  tube qui ne se ferme jamais en tâche de fond est couvert.
- **`release.py`** : bump du compteur **avant** le build (sinon le bundle
  embarquerait l'ancien), refus net si `CFBundleVersion` n'est pas un entier,
  échec de build interrompu avant le zip. Le prompt d'upload lit stdin —
  `echo n |` le sert proprement.
- **`run_tests.sh`** : clos en Phase 4 (`set -euo pipefail`, exit transmis).

## 3. Le reste du périmètre

- **`Info.plist`** : cohérent — `CFBundleShortVersionString` 1.37.4 /
  `CFBundleVersion` 52 (les deux numéros d'aujourd'hui), scheme `nxm`
  déclaré, `LSMinimumSystemVersion` 14.0 aligné avec `platforms: [.macOS(.v14)]`
  du Package et le `-target …macosx14.0` de `build_app.py`. L'identifiant
  `com.appleboiy.StarHubTH` est l'exclusion documentée **F5**, pas un défaut.
- **`.mcp.json`** : un serveur `xcodebuild` via `npx xcodebuildmcp@latest` —
  aucun secret. Note : version flottante `@latest`, donc un outillage d'agent
  non épinglé ; sans effet sur l'app ni le dépôt.
- **Miroir Core après correction** : 166 fichiers listés. Restent hors module
  testable, pour raison lisibile : l'app, le ViewModel, les vues, le design —
  et la grappe des singletons réseau (`NexusSearchClient`, `NexusDownloader`,
  `KeybindScanService`, `SmapiInstaller`), plus `NexusCategory` et
  `BisectionRunner` (SwiftUI — ils compileraient, `AppDesignCore` le prouve,
  mais rien ne les testerait mieux pour autant), et `ModListFilters` (bloqué,
  voir X91).

## 4. Pistes écartées, avec la raison

1. **`create_app_bundle` efface l'ancien bundle avant de compiler** — un gate
   raté laisse le dépôt sans `StarHubFR.app` local. Choix cohérent : ne jamais
   laisser croire qu'un binaire périmé est frais ; les releases publiées vivent
   dans `bundles/*.zip`.
2. **`os.listdir(custom_ui)` copierait un AppleDouble `._*.png`** s'il en
   existait — mesuré : le seul résidu présent est un `.DS_Store`, que le filtre
   `endswith(".png")` exclut. Inoffensif en l'état.
3. **Fenêtre de course dans le cache fraîcheur de `check_standards`** (le
   fingerprint est relevé une seconde fois, après la mesure) — pire cas : un
   cache légèrement obsolète, invalidé au prochain changement de mtime. Écarté.
4. **`_gh` tente `gh` puis retombe sur urllib** — deux chemins pour une même
   sonde, mais le fallback est documenté (quota 60/h) et le 404 de `gh` rend
   `None` proprement. Pas une copie divergente : un seul format de sortie.

## 5. Verdict

La chaîne build/release est **honnête** : chaque échec rend un exit non nul,
chaque `--update` est un geste explicite jamais automatisé, les deux cliquets
font exactement ce que leurs en-têtes annoncent. Deux oublis réparés (X91 et le
fingerprint LSP), un troisième candidat documenté comme bloqué par dépendance
UI (`ModListFilters`).

**Le brief d'audit fichier-par-fichier (`docs/prompt-audit.md`) est complet sur
ses cinq phases.** Les suites naturelles ne relèvent plus de l'audit : F1
(descendre `FrenchTranslationScope` vers `Models/` débloquerait le test de
`ModListFilters`), et la re-passe périodique des zones vivantes — la leçon des
tranches : une zone déclarée complète n'est pas une preuve.
