# Prompt d'audit fichier par fichier

> Prompt réutilisable : audit dépôt par IA. Version corrigée 2026-09-04 : version qui circulait tronquée (phases 0/1 amputées, deux règles fusionnées) + fausse sur quatre points mesurables — dont système de build, annoncé SPM.
>
> Remesurée 2026-09-24 : ViewModel passé à `@Observable` (plus d'`ObservableObject` ni `@Published` chez lui), build mode Swift 6, nouveau dossier `StarHubTH/Stores/`, ROADMAP §4 vide (X1–X106 tous archivés), parc déplacé sur `/Volumes/BABILOGAMES`. Copie avec lignes amputées en plein milieu circule encore : **ce fichier = seule version de référence**.
>
> Remesurée 2026-10-03 : ViewModel descendu à 7 741 lignes (extraction vers `Stores/` continue), 534 `.swift` sous `StarHubTH/`, 4 050 `@Test`, sonde C# `companion/` entre dans périmètre.
>
> Remesurée 2026-10-09 : ViewModel remonté à 7 926 lignes (cliquet relevé par 27 commits en une semaine), 608 `.swift`, 4 371 `@Test`, X120–X125 ouverts au §4 (`docs/audit-delta-2026-10-09.md`).

---

Ingénieur senior Swift : SwiftUI (apps macOS natives), Swift Concurrency (async/await, actors), intégrations réseau (URLSession). Auditer projet StarHubFR fichier par fichier.

REPO : https://github.com/mrbabilo/StarHubFR
STACK : Swift 6 (mode langage 6 dans `build_app.py`) · SwiftUI + AppKit (UI macOS native, macOS 14+) · URLSession
(Nexus Mods API, smapi.io, DeepL, Ollama/LLM local) · persistance
fichier + UserDefaults + Trousseau (pas SQL) · scripts Python
(build, release, cliquet conventions)

⚠️ BUILD **PAS** SPM. Deux systèmes coexistent — savoir lequel couvre fichier audité :
- `python3 build_app.py` — **vrai gate** : `swiftc` sur *tous* `.swift` sous `StarHubTH/`, un seul module. Valide UI, ViewModel, installateur SMAPI, clients Nexus. `python3` uniquement, jamais `python`.
- `swift build` / `Package.swift` — compile **sous-ensemble Core** seul (modèles purs, managers backup, `SaveManager`, `L10n`…). Ne voit ni UI ni ViewModel. Correctif validé par `swift build` seul = pas validé.
- `./run_tests.sh` — `swift test` avec `DEVELOPER_DIR` sur Xcode.app. Sans : `no such module 'Testing'` — limite environnement, pas régression.

CONTEXTE STRUCTUREL (mesuré 2026-10-09, pas estimé) :
- Point d'entrée : `StarHubTH/StarHubTHApp.swift` (13 931 o, 252 l)
- ViewModel monolithique, priorité surveillance :
  `StarHubTH/StarHubTHViewModel.swift` (399 963 o, **7 926 lignes**, une seule
  classe `@MainActor @Observable final class StarHubTHViewModel`, 54 sections
  `// MARK:`). Se vide vers `StarHubTH/Stores/` (plan `docs/REFACTORING.md`)
- Stores : `StarHubTH/Stores/` — 44 fichiers (35 `*Store.swift`), état extrait du ViewModel (`ScanStore`, `ModUpdateStore`, `NexusDownloadStore`…)
- Design : `StarHubTH/AppDesignCore.swift` (5 425 o) + `StarHubTH/Design/` (1 f.)
- Sources : 608 `.swift` sous `StarHubTH/` — `Models/` 334, `Views/` 191
  (dont `Views/Components/` 56 et `Views/Performance/` 31), `Stores/` 44,
  `Extensions/` 3, `Design/` 1, racine 36
- Observation : 38 fichiers en `@Observable` ; **5 restent `ObservableObject`**
  (`SmapiInstaller`, `BisectionRunner`, `KeybindScanService`,
  `Stores/LocalizationStore`, `ModListState` dans `Models/ModListFilters.swift`) — 18 lignes `@Published`
  hors commentaires subsistent. Dans ViewModel + stores `@Observable`, `@Published` ne
  compile plus : `var` stockée déjà suivie
- Tests : `Tests/` — **Swift Testing, pas XCTest** (0 `import XCTest`).
  245 cibles dans `Package.swift`, 381 fichiers, 178 `@Suite`
  explicites, **4 371 `@Test`**.
  Tests ne couvrent que ce que `Package.swift` embarque :
  code UI/ViewModel non testable ici — déplacer en Core d'abord.
- Build/packaging : `Package.swift` (61 352 o), `Info.plist`, `build_app.py`,
  `release.py`
- Sonde C# : `companion/` — `StarHubFR.Probe` (sonde installée sous
  `Mods/StarHubFR Probe`) + `StarHubFR.Probe.Tests`, 40 `.cs`.
  Outil .NET, **hors** gate Swift : audit via `dotnet build` +
  tests dédiés, pas `build_app.py`
- Qualité : `check_standards.py` + `.standards-baseline.json` — cliquet :
  n'échoue qu'à l'**augmentation** compteur ; ajout délibéré demande
  `--update` explicite, visible dans diff
- Sources externes : `check_sources.py` + `.sources-baseline.json` — même cliquet,
  appliqué à ce qui vit **hors** dépôt (API interrogées, dumps
  téléchargés, code repris). Différence de sens : **écart ≠ faute**,
  chose à aller regarder. Carte + raisonnement dans
  `docs/SOURCES.md`. ⚠️ **Ne pas lancer script pendant audit** (sonde
  réseau) et **ne jamais réécrire `.sources-baseline.json`** : signaler
  comme constat, c'est tout
- Docs : `docs/` (dont `docs/DOMAINE.md` et `docs/ROADMAP.md`), `README.md`
  (20 738 o), `README_EN.md`, `CONTRIBUTING.md`, `SECURITY.md`
- Contexte projet : `AGENTS.md` (15 238 o) ET `CLAUDE.md` (6 362 o) — `CLAUDE.md` renvoie
  aux skills (`.claude/skills/`) et à `docs/SOURCES.md`, `docs/REFACTORING.md`
- Historique : `CHANGELOG.md` — fichier unique (327 536 o), Keep a Changelog

RÈGLE ABSOLUE : lire `AGENTS.md`, `CLAUDE.md` ET `docs/DOMAINE.md` EN PREMIER.
`DOMAINE.md` porte vocabulaire métier — « pack », « profil », « sauvegarde »
≠ sens ici vs chez l'amont, et mod **en pause** = dossier **préfixé
par point** dans `Mods/`, pas dossier déplacé.
Lire aussi `docs/ROADMAP.md` §4 : constat d'audit **ouvert**
porterait numéro `X<n>`. Au 2026-10-09 : **X120–X125 ouverts** ; X1–X119 tous
corrigés, vivent dans `docs/roadmap-archive.md`, avec mesure qui les a
établis, indexés §11 ROADMAP. Chercher `X<n>` dans **les deux**
fichiers — sinon re-signale bug corrigé, et refait mesure du parc
déjà faite. Nouveau constat prend numéro suivant (X126).
⚠️ Cases ROADMAP traînent derrière code livré — vérifier `git log`
avant tâche « à faire ».
⚠️ `AGENTS.md` §5 date : annonce ViewModel « ~3900 lignes » et
`manifestCache` « sur le VM » — cache vit désormais dans
`Models/ModScanner.swift`. Code prime ; signaler écart, ne pas s'y fier.

────────────────────────────────────────────
ORDRE D'AUDIT (respecter impérativement) :
────────────────────────────────────────────
PHASE 0 — Contexte global
  1. `AGENTS.md`
  2. `CLAUDE.md`
  3. `docs/DOMAINE.md`
  4. `docs/ROADMAP.md` (§4 : constats X<n> ouverts — aucun au
     2026-10-03 ; §11 : l'index des livrés) **et** `docs/roadmap-archive.md`
     (les X<n> corrigés, avec leur mesure)
  5. `docs/REFACTORING.md` (ce qui a quitté le ViewModel, et vers quel store)
  6. `README.md`

PHASE 1 — Cœur applicatif
  7. `StarHubTH/StarHubTHApp.swift`
  8. `StarHubTH/StarHubTHViewModel.swift` (par sections logiques si nécessaire,
     en gardant la mémoire globale du fichier)
  9. `StarHubTH/AppDesignCore.swift`
 10. `StarHubTH/Models/` (auditer dans l'ordre : stores de persistance →
     clients réseau → parseurs/décodeurs binaires → logique métier
     mods/traduction)
 11. `StarHubTH/Stores/` — l'état sorti du ViewModel ; vérifier que chaque store
     possède son invariant et que le ViewModel n'en garde pas de copie
 12. `StarHubTH/Extensions/`, `StarHubTH/Views/` (dont `Views/Components/`)

PHASE 2 — Intégrations réseau (cœur métier)
  ⚠️ PRÉREQUIS : lire `docs/SOURCES.md` avant phase. Donne, par
  contrat externe : point d'entrée, rôle, fichier qui l'implémente, piège
  connu — notamment `NexusRequestBuilder.makeRequest(path:apiKey:)` =
  **seul** constructeur de requête Nexus admis, et `apiVersion`
  obligatoire dans requête smapi.io (sans : zéro suggestion, en silence).
  Document porte rôles + raisonnement, jamais valeurs courantes.
 13. `NexusSearchClient`, `NexusModSearch`, `NexusDownloader`,
     `NexusUpdateChecker`, `NexusRequestBuilder`, `NexusRateLimitGate`,
     `NexusQuota`
 14. `DeepLClient`, `DeepLDesktop`
 15. `SmapiUpdateClient`, `SmapiUpdateRequest`, `SmapiUpdateResponse`
 16. `LocalLLMClient`, `LocalLLMEndpoint`, `OllamaCapabilities`

PHASE 3 — Persistance & données locales
 17. `UDKey.swift`, `KeychainSecret.swift`, `TokenShield.swift`
 18. Les `*Store.swift` de persistance, sous `Models/` : `ProfileConfigStore`, `GlossaryStore`,
     `TranslationFileStore`, `ModConflictVerdictsStore`,
     **`ModErrorHistoryStore`** et **`ModVersionAnchorStore`** *(le prompt
     d'origine citait un « ModErrorHonAnchorStore » qui n'existe pas — c'est la
     contraction accidentelle de ces deux-là)*, `InstalledTranslationStore`,
     `ModCompatibilityStore`, `ModDetailCache`
 19. `ModConfigBackupManager`, `ModInstallBackupManager`, `ModFolderRepairer`,
     `FileRecovery`

PHASE 4 — Tests
 20. `Tests/` (245 cibles Swift Testing, miroir modules audités)
 21. `run_tests.sh`
 22. `companion/` — sonde C# (`StarHubFR.Probe` + `.Tests`, 40 `.cs`) :
     mêmes sections de rapport ; build/tests via `dotnet`, le gate Swift ne
     la voit pas

PHASE 5 — Configuration, build & déploiement
 23. `Package.swift` (targets/dépendances), `Info.plist`
 24. `build_app.py`, `release.py`, `check_standards.py`,
     `.standards-baseline.json`, `check_sources.py`, `.sources-baseline.json`,
     `.mcp.json` — pour les deux cliquets, auditer *en lecture* : que le script
     rende bien un code de sortie non nul quand il doit échouer (ce dépôt a payé
     cher des scripts rendant `exit 0` sur un échec), et qu'un `--update` reste
     un geste explicite

────────────────────────────────────────────
PROTOCOLE D'AUDIT PAR FICHIER :
────────────────────────────────────────────
Par fichier, produire EXACTEMENT cette structure :

## 📁 [chemin/nom_fichier.swift]

### 🔴 BUGS BLOQUANTS
(crash runtime, force-unwrap nil, erreur non gérée, interblocage async,
écriture non atomique store, perte données utilisateur)
- [L.XX] ...

### 🟡 BUGS MINEURS / RÉGRESSIONS POTENTIELLES
- [L.XX] ...

### 🔧 FONCTIONNALITÉS PRÉVUES NON IMPLÉMENTÉES
(TODO/FIXME/`fatalError("TODO")`/commentaires « à faire »)
- Référence dans le code → implémentation proposée

### ⚠️ ANTI-PATTERNS SPÉCIFIQUES AU STACK
SwiftUI : mutation état observé (`@Observable` ou `@Published`) hors fil
  principal ; `@State` / `@Bindable` / `@Environment` mal employés avec type
  `@Observable` (+ `@StateObject` / `@ObservedObject` pour les 5
  `ObservableObject` restants) ; cycle rétention via closure dans type
  observé ; effet de bord dans `body` ; `.task {}` sans gestion
  d'annulation ; `@MainActor` manquant sur méthode touchant l'UI ;
  `ForEach` identifié par index ou `\.self` (fuite `@State` d'une ligne à
  l'autre) ; `body` trop dense pour type-checker
Swift Concurrency : `Task {}` non structuré qui fuit ; `[weak self]` absent
  de closure passée à `DispatchQueue.global().async` ; mélange
  DispatchQueue/async-await ; I/O synchrone sur fil principal ; structure
  mutable partagée sans `NSLock` — `scanMods()` peut s'exécuter
  **concurremment avec lui-même** (crash `EXC_BAD_ACCESS` confirmé sur
  `manifestCache` juillet 2026 ; cache vit aujourd'hui dans
  `Models/ModScanner.swift`, sous `manifestCacheLock`) ; méthode `@MainActor`
  appelée depuis fil de fond — mode Swift 6 vérifie **à l'exécution**
  et tue l'app, ni gate ni tests ne le voient
Réseau : `try?` qui avale erreur ; pas de backoff sur rate-limit ;
  décodage `Codable` échoue en silence ; clé API en `UserDefaults` au
  lieu du Trousseau ; requête Nexus construite ailleurs que par
  `NexusRequestBuilder.makeRequest(path:apiKey:)` ; requête smapi.io sans
  `apiVersion` (zéro suggestion revient, en silence) ; `Pipe` lu après
  `waitUntilExit()` (interblocage passé 64 Ko)
Persistance : écriture non atomique ; lecture/écriture concurrentes même
  JSON ; collision `UDKey` ; pas de migration schéma ; chemin disque
  construit sur `folderName` au lieu de `physicalFolderName` (mod en pause
  vit dans `Mods/.X`)

### 🔗 CARTE DE DÉPENDANCES
⚠️ App = **un seul module** : « ce fichier est importé par » n'a pas de
sens ici. Donner à la place :
- Ce fichier appelle : [types/fonctions]
- Ce que vues consomment de lui : [propriétés observées, lues par quelles vues]
- Impact d'un bug ici : [portée]

### ✅ CE QUI FONCTIONNE
(synthèse courte, sans réécrire code correct)

### 🔬 PISTES ÉCARTÉES, AVEC LA MESURE
Piste examinée puis abandonnée, avec chiffre qui la ferme.
**Section vaut autant que les deux premières** : empêche la
prochaine passe de refaire même chemin.

────────────────────────────────────────────
RÈGLES COMPLÉMENTAIRES :
────────────────────────────────────────────
1. Garder mémoire fichiers déjà audités. Bug du fichier courant
   **causé** par fichier précédent → le dire.
2. Fonctionnalité annoncée dans `AGENTS.md`, `CLAUDE.md` ou
   `README.md` mais absente du code → écart de spécification —
   pas bug.
3. **Aucune refonte globale.** Correctifs localisés seul : fichier,
   lignes, diff minimal. Pour `StarHubTHViewModel.swift` impératif —
   `AGENTS.md` §5.1 assume god-object et interdit de l'aggraver, pas de le
   réécrire. Règle F1-T2 (`docs/REFACTORING.md`) : correctif demandant
   état ou logique **neuve** la pose dans store (`Stores/`) ou type
   pur (`Models/`), jamais dans `StarHubTHViewModel`.
4. Bug async : préciser si correctif exige `@MainActor`,
   `Task { @MainActor in … }`, ou isolation d'acteur dédiée.
5. Correction proposée = Swift valide, syntaxiquement
   complet, prêt à copier-coller — **mais uniquement pour constat
   démontré** (voir règle 6).
6. **Trois filtres avant entrée en 🔴 ou 🟡** :
   a. Déjà consigné sous numéro `X<n>` — en ROADMAP §4 s'il est
      ouvert, dans `roadmap-archive.md` s'il est corrigé ? Alors il est connu,
      et souvent assorti d'une raison explicite de ne pas y toucher.
   b. Déjà mesuré et écarté ? Ne pas refaire mesure du parc
      déjà faite.
   c. **Peux-tu le démontrer ?** Scénario d'échec sur parc réel
      (1 009 entrées, 1 161 `manifest.json` au 2026-10-03, sous
      `/Volumes/BABILOGAMES/JEUX EN COURS/Stardew Valley.app/Contents/MacOS/Mods`
      — **plus** sous `/Applications`, où le dossier est vide : une mesure
      sur l'ancien chemin rend zéro sans le dire ; exclure `_Trash_*`)
      ou un test rouge. Sinon il va en « pistes écartées », jamais en bug.
      Sur ce dépôt, 3 constats de faible gravité sur 8 se sont révélés faux,
      dont un dont le correctif aurait nui.
7. **Ne jamais lancer app ni prendre capture.** Vérification GUI
   déléguée à l'humain ; agent valide par succès build et tests.
8. Ne pas éditer sources pendant qu'un `build_app.py` tourne.
9. Ne pousser sur `main` que sur demande explicite.

────────────────────────────────────────────
DÉBUT DE SESSION :
────────────────────────────────────────────
Lire `AGENTS.md`, `CLAUDE.md` et `docs/DOMAINE.md`, puis résumé en
10 points : objectif projet, fonctionnalités livrées, stack confirmée,
modules identifiés, pièges dépôt pesant sur l'audit.

Puis auditer fichier désigné. Aucun désigné → prendre
`StarHubTH/StarHubTHViewModel.swift` — plus gros gisement.