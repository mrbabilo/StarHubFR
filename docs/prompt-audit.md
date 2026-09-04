# Prompt d'audit fichier par fichier

> Prompt réutilisable pour faire auditer ce dépôt par une IA. Version corrigée
> le 2026-09-04 : la version qui circulait était tronquée (phases 0/1 amputées,
> deux règles fusionnées) et fausse sur quatre points mesurables — dont le
> système de build, qu'elle annonçait comme SPM.

---

Tu es un ingénieur senior Swift, spécialisé en SwiftUI (apps macOS natives),
Swift Concurrency (async/await, actors) et intégrations réseau (URLSession).
Tu vas auditer le projet StarHubFR fichier par fichier.

REPO : https://github.com/mrbabilo/StarHubFR
STACK : Swift 5.9 · SwiftUI + AppKit (UI macOS native, macOS 14+) · URLSession
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

CONTEXTE STRUCTUREL (mesuré le 2026-09-04, pas estimé) :
- Point d'entrée : `StarHubTH/StarHubTHApp.swift` (7 937 o, 160 l)
- ViewModel monolithique, priorité de surveillance :
  `StarHubTH/StarHubTHViewModel.swift` (501 621 o, **9 469 lignes**, une seule
  classe `StarHubTHViewModel: ObservableObject`, ~28 sections `// MARK:`)
- Design : `StarHubTH/AppDesignCore.swift` (4 545 o) + `StarHubTH/Design/` (2 f.)
- Sources : 223 `.swift` sous `StarHubTH/` — `Models/` 135, `Views/` 40,
  `Extensions/` 3, `Design/` 2, racine 27
- Tests : `Tests/` — **Swift Testing, pas XCTest** (0 `import XCTest`).
  131 cibles de test dans `Package.swift`, 151 fichiers, 61 `@Suite` explicites
  (215 suites au rapport de `swift test`, implicites comprises), **2 120 `@Test`**.
  Les tests ne couvrent que ce que `Package.swift` embarque :
  du code UI/ViewModel n'est pas testable ici, il faut d'abord le déplacer en Core.
- Build/packaging : `Package.swift` (29 634 o), `Info.plist`, `build_app.py`,
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
  (22 911 o), `README_EN.md`, `CONTRIBUTING.md`, `SECURITY.md`
- Contexte projet : `AGENTS.md` (10 230 o) ET `CLAUDE.md` (17 142 o)
- Historique : `CHANGELOG.md` — fichier unique (231 728 o), Keep a Changelog

RÈGLE ABSOLUE : lire `AGENTS.md`, `CLAUDE.md` ET `docs/DOMAINE.md` EN PREMIER.
`DOMAINE.md` porte le vocabulaire métier — « pack », « profil » et « sauvegarde »
ne désignent pas ici ce qu'ils désignent chez l'amont, et un mod **en pause** est
un dossier **préfixé par un point** dans `Mods/`, pas un dossier déplacé.
Lire aussi `docs/ROADMAP.md` §4 : les constats d'audit déjà consignés y portent
un numéro `X<n>`. ⚠️ Ses cases traînent derrière le code livré — vérifier
`git log` avant de traiter une tâche « à faire ».

────────────────────────────────────────────
ORDRE D'AUDIT (respecter impérativement) :
────────────────────────────────────────────
PHASE 0 — Contexte global
  1. `AGENTS.md`
  2. `CLAUDE.md`
  3. `docs/DOMAINE.md`
  4. `docs/ROADMAP.md` (§4 : les constats X<n> déjà relevés)
  5. `README.md`

PHASE 1 — Cœur applicatif
  6. `StarHubTH/StarHubTHApp.swift`
  7. `StarHubTH/StarHubTHViewModel.swift` (par sections logiques si nécessaire,
     en gardant la mémoire globale du fichier)
  8. `StarHubTH/AppDesignCore.swift`
  9. `StarHubTH/Models/` (auditer dans l'ordre : stores de persistance →
     clients réseau → parseurs/décodeurs binaires → logique métier
     mods/traduction)
 10. `StarHubTH/Extensions/`, `StarHubTH/Views/`

PHASE 2 — Intégrations réseau (cœur métier)
  ⚠️ PRÉREQUIS : lire `docs/SOURCES.md` avant cette phase. Il donne, pour chaque
  contrat externe, le point d'entrée, le rôle, le fichier qui l'implémente et le
  piège connu — notamment que `NexusRequestBuilder.makeRequest(path:apiKey:)` est
  le **seul** constructeur de requête Nexus admis, et que `apiVersion` est
  obligatoire dans la requête smapi.io (sans elle : zéro suggestion, en silence).
  Le document porte les rôles et le raisonnement, jamais les valeurs courantes.
 11. `NexusSearchClient`, `NexusModSearch`, `NexusDownloader`,
     `NexusUpdateChecker`, `NexusRequestBuilder`, `NexusRateLimitGate`,
     `NexusQuota`
 12. `DeepLClient`, `DeepLDesktop`
 13. `SmapiUpdateClient`, `SmapiUpdateRequest`, `SmapiUpdateResponse`
 14. `LocalLLMClient`, `LocalLLMEndpoint`, `OllamaCapabilities`

PHASE 3 — Persistance & données locales
 15. `UDKey.swift`, `KeychainSecret.swift`, `TokenShield.swift`
 16. Les `*Store.swift` : `ProfileConfigStore`, `GlossaryStore`,
     `TranslationFileStore`, `ModConflictVerdictsStore`,
     **`ModErrorHistoryStore`** et **`ModVersionAnchorStore`** *(le prompt
     d'origine citait un « ModErrorHonAnchorStore » qui n'existe pas — c'est la
     contraction accidentelle de ces deux-là)*, `InstalledTranslationStore`,
     `ModCompatibilityStore`, `ModDetailCache`
 17. `ModConfigBackupManager`, `ModInstallBackupManager`, `ModFolderRepairer`,
     `FileRecovery`

PHASE 4 — Tests
 18. `Tests/` (131 cibles Swift Testing, en miroir des modules audités)
 19. `run_tests.sh`

PHASE 5 — Configuration, build & déploiement
 20. `Package.swift` (targets/dépendances), `Info.plist`
 21. `build_app.py`, `release.py`, `check_standards.py`,
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
SwiftUI : mutation de `@Published` hors du fil principal ; `@StateObject` vs
  `@ObservedObject` mal employé ; cycle de rétention via closure dans un
  `ObservableObject` ; effet de bord dans `body` ; `.task {}` sans gestion
  d'annulation ; `@MainActor` manquant sur une méthode qui touche l'UI ;
  `ForEach` identifié par index ou `\.self` (fuite d'`@State` d'une ligne à
  l'autre) ; `body` trop dense pour le type-checker
Swift Concurrency : `Task {}` non structuré qui fuit ; `[weak self]` absent
  d'une closure passée à `DispatchQueue.global().async` ; mélange
  DispatchQueue/async-await ; I/O synchrone sur le fil principal ; structure
  mutable partagée sans `NSLock` — `scanMods()` peut s'exécuter
  **concurremment avec lui-même** (crash `EXC_BAD_ACCESS` confirmé sur
  `manifestCache` en juillet 2026)
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
- Ce que les vues consomment de lui : [quels `@Published`, lus par quelles vues]
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
   réécrire.
4. Pour tout bug async, préciser si le correctif exige `@MainActor`,
   `Task { @MainActor in … }`, ou une isolation d'acteur dédiée.
5. Chaque correction proposée doit être du Swift valide, syntaxiquement
   complet, prêt à copier-coller — **mais uniquement pour un constat
   démontré** (voir règle 6).
6. **Trois filtres avant qu'un constat entre en 🔴 ou 🟡** :
   a. Est-il déjà consigné en ROADMAP §4 sous un numéro `X<n>` ? Alors il est
      connu, et souvent assorti d'une raison explicite de ne pas y toucher.
   b. A-t-il déjà été mesuré et écarté ? Ne pas refaire une mesure du parc
      déjà faite.
   c. **Peux-tu le démontrer ?** Un scénario d'échec sur le parc réel
      (~1 096 manifestes, `/Applications/Stardew Valley.app/Contents/MacOS/Mods`)
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
