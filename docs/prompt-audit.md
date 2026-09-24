# Prompt d'audit fichier par fichier

> Prompt réutilisable pour faire auditer ce dépôt par une IA. Version corrigée
> le 2026-09-04 : la version qui circulait était tronquée (phases 0/1 amputées,
> deux règles fusionnées) et fausse sur quatre points mesurables — dont le
> système de build, qu'elle annonçait comme SPM.
>
> Remesurée le 2026-09-24 : ViewModel passé à `@Observable` (plus
> d'`ObservableObject` ni de `@Published` chez lui), build en mode Swift 6, nouveau
> dossier `StarHubTH/Stores/`, ROADMAP §4 vide (X1–X106 tous archivés), parc
> déplacé sur `/Volumes/BABILOGAMES`. Une copie circule encore avec des lignes
> amputées en plein milieu : **ce fichier est la seule version de référence**.

---

Tu es un ingénieur senior Swift, spécialisé en SwiftUI (apps macOS natives),
Swift Concurrency (async/await, actors) et intégrations réseau (URLSession).
Tu vas auditer le projet StarHubFR fichier par fichier.

REPO : https://github.com/mrbabilo/StarHubFR
STACK : Swift 6 (mode de langage 6 dans `build_app.py`) · SwiftUI + AppKit (UI macOS native, macOS 14+) · URLSession
(Nexus Mods API, smapi.io, DeepL, Ollama/LLM local) · persistance
fichier + UserDefaults + Trousseau (pas de SQL) · scripts Python
(build, release, cliquet de conventions)

⚠️ LE BUILD N'EST **PAS** SPM. Deux systèmes coexistent, il faut savoir lequel
couvre le fichier audité :
- `python3 build_app.py` — le **vrai gate** : `swiftc` sur *tous* les `.swift`
  sous `StarHubTH/`, un seul module. C'est lui qui valide l'UI, le ViewModel,
  l'installateur SMAPI, les clients Nexus. `python3` uniquement, jamais `python`.
- `swift build` / `Package.swift` — ne compile qu'un **sous-ensemble Core**
  (modèles purs, managers de backup, `SaveManager`, `L10n`…). Il ne voit ni
  l'UI ni le ViewModel. Un correctif validé par `swift build` seul n'est pas
  validé.
- `./run_tests.sh` — `swift test` avec `DEVELOPER_DIR` sur Xcode.app.
  Sans lui : `no such module 'Testing'` — limite d'environnement, pas régression.

CONTEXTE STRUCTUREL (mesuré le 2026-09-24, pas estimé) :
- Point d'entrée : `StarHubTH/StarHubTHApp.swift` (13 028 o, 239 l)
- ViewModel monolithique, priorité de surveillance :
  `StarHubTH/StarHubTHViewModel.swift` (543 031 o, **10 027 lignes**, une seule
  classe `@MainActor @Observable final class StarHubTHViewModel`, 52 sections
  `// MARK:`). Il se vide vers `StarHubTH/Stores/` (plan `docs/REFACTORING.md`)
- Stores : `StarHubTH/Stores/` — 30 fichiers (25 `*Store.swift`), l'état
  extrait du ViewModel (`ScanStore`, `ModUpdateStore`, `NexusDownloadStore`…)
- Design : `StarHubTH/AppDesignCore.swift` (5 186 o) + `StarHubTH/Design/` (1 f.)
- Sources : 362 `.swift` sous `StarHubTH/` — `Models/` 220, `Views/` 82
  (dont `Views/Components/` 25), `Stores/` 30, `Extensions/` 2, `Design/` 1,
  racine 27
- Observation : 26 fichiers en `@Observable` ; **5 restent `ObservableObject`**
  (`SmapiInstaller`, `BisectionRunner`, `KeybindScanService`,
  `Stores/LocalizationStore`, `Models/ModListFilters`) — 16 lignes `@Published`
  hors commentaires subsistent. Dans le ViewModel et les stores `@Observable`, `@Published` ne
  compile plus : une `var` stockée est déjà suivie
- Tests : `Tests/` — **Swift Testing, pas XCTest** (0 `import XCTest`).
  219 cibles de test dans `Package.swift`, 262 fichiers, 134 `@Suite`
  explicites, **3 424 `@Test`**.
  Les tests ne couvrent que ce que `Package.swift` embarque :
  du code UI/ViewModel n'est pas testable ici, il faut d'abord le déplacer en Core.
- Build/packaging : `Package.swift` (50 491 o), `Info.plist`, `build_app.py`,
  `release.py`
- Qualité : `check_standards.py` + `.standards-baseline.json` — cliquet qui
  n'échoue qu'à l'**augmentation** d'un compteur ; un ajout délibéré demande un
  `--update` explicite, visible dans le diff
- Sources externes : `check_sources.py` + `.sources-baseline.json` — même patron
  de cliquet, appliqué à ce qui vit **hors** du dépôt (API interrogées, dumps
  téléchargés, code repris). Différence de sens : **un écart n'y est pas une
  faute**, c'est une chose à aller regarder. Carte et raisonnement dans
  `docs/SOURCES.md`. ⚠️ **Ne pas lancer ce script pendant l'audit** (il sonde
  le réseau) et **ne jamais réécrire `.sources-baseline.json`** : le signaler
  comme constat, c'est tout
- Docs : `docs/` (dont `docs/DOMAINE.md` et `docs/ROADMAP.md`), `README.md`
  (24 097 o), `README_EN.md`, `CONTRIBUTING.md`, `SECURITY.md`
- Contexte projet : `AGENTS.md` (12 924 o) ET `CLAUDE.md` (7 196 o) — `CLAUDE.md` renvoie
  aux skills (`.claude/skills/`) et à `docs/SOURCES.md`, `docs/REFACTORING.md`
- Historique : `CHANGELOG.md` — fichier unique (284 634 o), Keep a Changelog

RÈGLE ABSOLUE : lire `AGENTS.md`, `CLAUDE.md` ET `docs/DOMAINE.md` EN PREMIER.
`DOMAINE.md` porte le vocabulaire métier — « pack », « profil » et « sauvegarde »
ne désignent pas ici ce qu'ils désignent chez l'amont, et un mod **en pause** est
un dossier **préfixé par un point** dans `Mods/`, pas un dossier déplacé.
Lire aussi `docs/ROADMAP.md` §4 : c'est là qu'un constat d'audit **ouvert**
porterait un numéro `X<n>`. Au 2026-09-24 il est **vide** : X1–X106 sont tous
corrigés et vivent dans `docs/roadmap-archive.md`, avec la mesure qui les a
établis, indexés au §11 de la ROADMAP. Chercher un `X<n>` dans **les deux**
fichiers — sans quoi on re-signale un bug corrigé, et on refait une mesure du
parc déjà faite. Un nouveau constat prend le numéro suivant (X107).
⚠️ Les cases de la ROADMAP traînent derrière le code livré — vérifier `git log`
avant de traiter une tâche « à faire ».
⚠️ `AGENTS.md` §5 date : il annonce un ViewModel de « ~3900 lignes » et un
`manifestCache` « sur le VM » — le cache vit désormais dans
`Models/ModScanner.swift`. Le code prime ; signaler l'écart, ne pas s'y fier.

────────────────────────────────────────────
ORDRE D'AUDIT (respecter impérativement) :
────────────────────────────────────────────
PHASE 0 — Contexte global
  1. `AGENTS.md`
  2. `CLAUDE.md`
  3. `docs/DOMAINE.md`
  4. `docs/ROADMAP.md` (§4 : les constats X<n> ouverts — aucun au
     2026-09-24 ; §11 : l'index des livrés) **et** `docs/roadmap-archive.md`
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
  ⚠️ PRÉREQUIS : lire `docs/SOURCES.md` avant cette phase. Il donne, pour chaque
  contrat externe, le point d'entrée, le rôle, le fichier qui l'implémente et le
  piège connu — notamment que `NexusRequestBuilder.makeRequest(path:apiKey:)` est
  le **seul** constructeur de requête Nexus admis, et que `apiVersion` est
  obligatoire dans la requête smapi.io (sans elle : zéro suggestion, en silence).
  Le document porte les rôles et le raisonnement, jamais les valeurs courantes.
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
 20. `Tests/` (219 cibles Swift Testing, en miroir des modules audités)
 21. `run_tests.sh`

PHASE 5 — Configuration, build & déploiement
 22. `Package.swift` (targets/dépendances), `Info.plist`
 23. `build_app.py`, `release.py`, `check_standards.py`,
     `.standards-baseline.json`, `check_sources.py`, `.sources-baseline.json`,
     `.mcp.json` — pour les deux cliquets, auditer *en lecture* : que le script
     rende bien un code de sortie non nul quand il doit échouer (ce dépôt a payé
     cher des scripts rendant `exit 0` sur un échec), et qu'un `--update` reste
     un geste explicite

────────────────────────────────────────────
PROTOCOLE D'AUDIT PAR FICHIER :
────────────────────────────────────────────
Pour chaque fichier, produire EXACTEMENT cette structure :

## 📁 [chemin/nom_fichier.swift]

### 🔴 BUGS BLOQUANTS
(crash au runtime, force-unwrap sur nil, erreur non gérée, interblocage async,
écriture non atomique d'un store, perte de données utilisateur)
- [L.XX] ...

### 🟡 BUGS MINEURS / RÉGRESSIONS POTENTIELLES
- [L.XX] ...

### 🔧 FONCTIONNALITÉS PRÉVUES NON IMPLÉMENTÉES
(TODO/FIXME/`fatalError("TODO")`/commentaires « à faire »)
- Référence dans le code → implémentation proposée

### ⚠️ ANTI-PATTERNS SPÉCIFIQUES AU STACK
SwiftUI : mutation d'état observé (`@Observable` ou `@Published`) hors du fil
  principal ; `@State` / `@Bindable` / `@Environment` mal employés avec un type
  `@Observable` (et `@StateObject` / `@ObservedObject` pour les 5
  `ObservableObject` restants) ; cycle de rétention via closure dans un type
  observé ; effet de bord dans `body` ; `.task {}` sans gestion
  d'annulation ; `@MainActor` manquant sur une méthode qui touche l'UI ;
  `ForEach` identifié par index ou `\.self` (fuite d'`@State` d'une ligne à
  l'autre) ; `body` trop dense pour le type-checker
Swift Concurrency : `Task {}` non structuré qui fuit ; `[weak self]` absent
  d'une closure passée à `DispatchQueue.global().async` ; mélange
  DispatchQueue/async-await ; I/O synchrone sur le fil principal ; structure
  mutable partagée sans `NSLock` — `scanMods()` peut s'exécuter
  **concurremment avec lui-même** (crash `EXC_BAD_ACCESS` confirmé sur
  `manifestCache` en juillet 2026 ; le cache vit aujourd'hui dans
  `Models/ModScanner.swift`, sous `manifestCacheLock`) ; méthode `@MainActor`
  appelée depuis un fil de fond — le mode Swift 6 le vérifie **à l'exécution**
  et tue l'app, ni le gate ni les tests ne le voient
Réseau : `try?` qui avale une erreur ; absence de backoff sur rate-limit ;
  décodage `Codable` qui échoue en silence ; clé d'API en `UserDefaults` au
  lieu du Trousseau ; requête Nexus construite ailleurs que par
  `NexusRequestBuilder.makeRequest(path:apiKey:)` ; requête smapi.io sans
  `apiVersion` (zéro suggestion revient, en silence) ; `Pipe` lu après
  `waitUntilExit()` (interblocage passé 64 Ko)
Persistance : écriture non atomique ; lecture/écriture concurrentes d'un même
  JSON ; collision de `UDKey` ; absence de migration de schéma ; chemin disque
  construit sur `folderName` au lieu de `physicalFolderName` (un mod en pause
  vit dans `Mods/.X`)

### 🔗 CARTE DE DÉPENDANCES
⚠️ L'app est **un seul module** : « ce fichier est importé par » n'a pas de
sens ici. Donner à la place :
- Ce fichier appelle : [types/fonctions]
- Ce que les vues consomment de lui : [quelles propriétés observées, lues par quelles vues]
- Impact d'un bug ici : [portée]

### ✅ CE QUI FONCTIONNE
(synthèse courte, sans réécrire le code correct)

### 🔬 PISTES ÉCARTÉES, AVEC LA MESURE
Toute piste examinée puis abandonnée, avec le chiffre qui la ferme.
**Cette section vaut autant que les deux premières** : elle empêche la
prochaine passe de refaire le même chemin.

────────────────────────────────────────────
RÈGLES COMPLÉMENTAIRES :
────────────────────────────────────────────
1. Conserver la mémoire des fichiers déjà audités. Si un bug du fichier courant
   est **causé** par un fichier précédent, le dire.
2. Si une fonctionnalité est annoncée dans `AGENTS.md`, `CLAUDE.md` ou
   `README.md` mais absente du code, la signaler comme écart de spécification —
   pas comme un bug.
3. **Aucune refonte globale.** Uniquement des correctifs localisés : fichier,
   lignes, diff minimal. Pour `StarHubTHViewModel.swift` c'est impératif —
   `AGENTS.md` §5.1 assume le god-object et interdit de l'aggraver, pas de le
   réécrire. Règle F1-T2 (`docs/REFACTORING.md`) : un correctif qui demande un
   état ou une logique **neuve** la pose dans un store (`Stores/`) ou un type
   pur (`Models/`), jamais dans `StarHubTHViewModel`.
4. Pour tout bug async, préciser si le correctif exige `@MainActor`,
   `Task { @MainActor in … }`, ou une isolation d'acteur dédiée.
5. Chaque correction proposée doit être du Swift valide, syntaxiquement
   complet, prêt à copier-coller — **mais uniquement pour un constat
   démontré** (voir règle 6).
6. **Trois filtres avant qu'un constat entre en 🔴 ou 🟡** :
   a. Est-il déjà consigné sous un numéro `X<n>` — en ROADMAP §4 s'il est
      ouvert, dans `roadmap-archive.md` s'il est corrigé ? Alors il est connu,
      et souvent assorti d'une raison explicite de ne pas y toucher.
   b. A-t-il déjà été mesuré et écarté ? Ne pas refaire une mesure du parc
      déjà faite.
   c. **Peux-tu le démontrer ?** Un scénario d'échec sur le parc réel
      (996 entrées, 1 146 `manifest.json` au 2026-09-24, sous
      `/Volumes/BABILOGAMES/JEUX EN COURS/Stardew Valley.app/Contents/MacOS/Mods`
      — **plus** sous `/Applications`, où le dossier est vide : une mesure
      sur l'ancien chemin rend zéro sans le dire ; exclure `_Trash_*`)
      ou un test rouge. Sinon il va en « pistes écartées », jamais en bug.
      Sur ce dépôt, 3 constats de faible gravité sur 8 se sont révélés faux,
      dont un dont le correctif aurait nui.
7. **Ne jamais lancer l'app ni prendre de capture.** La vérification GUI est
   déléguée à l'humain ; un agent valide par succès de build et de tests.
8. Ne pas éditer les sources pendant qu'un `build_app.py` tourne.
9. Ne pousser sur `main` que sur demande explicite.

────────────────────────────────────────────
DÉBUT DE SESSION :
────────────────────────────────────────────
Lire `AGENTS.md`, `CLAUDE.md` et `docs/DOMAINE.md`, puis produire un résumé en
10 points : objectif du projet, fonctionnalités livrées, stack confirmée,
modules identifiés, et les pièges du dépôt qui pèsent sur l'audit.

Puis auditer le fichier que je désigne. Si je n'en désigne aucun, prendre
`StarHubTH/StarHubTHViewModel.swift` — c'est le plus gros gisement.
