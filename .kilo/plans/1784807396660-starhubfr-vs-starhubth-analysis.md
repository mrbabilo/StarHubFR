# Plan de Merge Sélectif : Upstream StarHubTH → StarHubFR

> **Note de révision (2026-07-23)** : Ce plan a été relu et corrigé après vérification directe du dépôt (remotes, `git fetch upstream`, diff réel des 4 commits cités, état actuel des fichiers du fork). La version précédente contenait plusieurs hypothèses fausses — notamment sur la nature "safe" des cherry-picks et sur l'absence d'intégration Nexus dans le fork. Les corrections sont marquées **[CORRECTION]**.
>
> **Mise à jour (2026-07-23, suite)** : l'objectif a été précisé — il ne s'agit pas seulement d'importer des *fonctionnalités* absentes du fork, mais de comparer les **pratiques de code** des deux côtés et de retenir les meilleures, dans les deux sens. Deux points laissés "à évaluer" dans la première révision ont donc été tranchés avec preuves à l'appui (stockage de la clé API Nexus, logique de rollback de `SmapiInstaller.swift`) — voir les sections correspondantes ci-dessous.

## Objectif
Intégrer **sélectivement** les meilleures fonctionnalités et pratiques de codage de l'originale StarHubTH dans le fork StarHubFR, tout en préservant les travaux uniques du fork (tests, localisation FR des documents).

---

## [CORRECTION] Constat clé avant toute décision

Le point de divergence (`merge-base`) entre `main` et `upstream/main` est `e38c4eb`. Depuis ce point, upstream n'a que **4 commits** (`adee02c`, `9c64fcd`, `5ae50f7`, `91c9a57`) — le plan original les avait identifiés correctement. En revanche, deux hypothèses structurantes du plan original sont **fausses** :

### 1. Les commits upstream ne sont PAS des cherry-picks "safe"

`adee02c` et `9c64fcd` ne sont pas des commits "fichiers nouveaux uniquement". Ce sont des commits **monolithiques** qui mélangent l'ajout de fichiers réellement nouveaux avec des modifications profondes de fichiers que **le fork a lui-même massivement réécrits** :

| Fichier | Lignes changées upstream (les 4 commits) | Lignes changées fork (depuis merge-base) |
|---|---|---|
| `SaveManager.swift` | 45 | **385** |
| `StarHubTHViewModel.swift` | 662 | **1379** |
| `Views/ModListView.swift` | 614 | **1136** |
| `SmapiInstaller.swift` | 89 | **174** |

Le fork a divergé beaucoup plus qu'upstream sur exactement les mêmes fichiers. Un `git cherry-pick adee02c` brut :
- provoquera des conflits importants sur `StarHubTHViewModel.swift`, `Views/ModListView.swift` et `SmapiInstaller.swift` ;
- et, plus grave, **modifie silencieusement `SaveManager.swift`** : il revert les noms de fermes thaïs (`farmTypeName`) vers l'anglais, et réécrit `restoreBackup(...)` avec une version **moins robuste** que celle du fork actuel (le fork a ajouté un suivi `liveFolderMovedAside` / `restoreCompleted` pour un rollback sûr, avec une couverture Swift Testing dédiée en cours d'extension — voir `docs/superpowers/plans/2026-07-23-savemanager-folder-ops-tests.md`). Écraser cette logique serait une régression testée-puis-cassée.

`9c64fcd` a le même problème : au-delà de `ModConfigEditorView.swift`, il touche `CHANGELOG.md`, `README.md`, `README_EN.md`, `build_app.py`, `nexus_description*.txt`, et **supprime les captures d'écran d'upstream** (`screenshots/*.png` passent à 0 octet dans ce commit). Un cherry-pick brut toucherait les README/CHANGELOG propres au fork.

**➡ Conclusion : abandonner l'approche "cherry-pick des 4 commits". Remplacer par une extraction fichier-par-fichier (voir stratégie révisée plus bas).**

### 2. Le fork a DÉJÀ une intégration Nexus — plus mature qu'upstream

Le plan original recommandait de prendre `NexusAPIService.swift` (169 lignes), `ModDetailView.swift` (161 lignes), et l'intégration Nexus dans `StarHubTHViewModel.swift`/`ModListView.swift` upstream (items 1, 2, 6, 7 — classés "Critique" ⭐⭐⭐⭐⭐).

**C'est obsolète.** Le fork possède déjà, avec une architecture propre et indépendante :
- `StarHubTH/NexusUpdateChecker.swift` (745 lignes) : client API Nexus Mods complet — clé API stockée dans le **Keychain macOS** (jamais en `UserDefaults`), cache des versions/catégories/résumés, dédoublonnage des requêtes (fenêtre 1h), respect du rate-limit. Nettement plus abouti que `NexusAPIService.swift` d'upstream.
- `StarHubTH/NexusCategory.swift` (75 lignes) : les 26 catégories Nexus Stardew Valley avec couleur et emoji dédiés.
- `ThaiModDetailView` (dans `Views/ThaiTranslationHubView.swift`) : vue détail mod avec onglets Description / Installation / Translation Mod / Original Mod — l'équivalent (plus riche : 4 onglets vs 2) de `ModDetailView.swift` d'upstream.
- Intégration déjà branchée dans le ViewModel (`nexusModExtras`, `modExtra(for:)`) et `ModListView.swift` (`previewSection`).

**➡ Conclusion : ne PAS reprendre `NexusAPIService.swift`, `ModDetailView.swift`, ni la logique Nexus des diffs upstream sur `StarHubTHViewModel.swift`/`ModListView.swift`. Ces items sont retirés de la liste "à prendre". Voir la section révisée ci-dessous.**

**[AJOUT] Pratique de sécurité — clé API Nexus : le fork est déjà en avance.** Vérification faite sur `upstream/main:StarHubTH/StarHubTHViewModel.swift` et `Views/SettingsView.swift` : upstream stocke la clé API Nexus en clair via `@AppStorage("nexusApiKey")` / `UserDefaults.standard` (`ViewModel.swift:266-267`, `SettingsView.swift:10`). Le fork la stocke dans le **Keychain macOS** (`NexusUpdateChecker.swift`, `import Security`, jamais `UserDefaults`). C'est une divergence de pratique de sécurité en faveur du fork — rien à importer d'upstream ici, et c'est un point à **préserver activement** (ne pas laisser une future extension Nexus régresser vers `UserDefaults` par imitation d'upstream).

### 3. [CORRECTION] La "localisation FR" du fork est documentaire, pas applicative

Le plan original range la "localisation FR" parmi les acquis du fork à préserver, et bâtit toute une Phase 4 ("ajouter les clés FR", "valider la parité FR") dessus. Vérification faite :
- `README.md` est bien rédigé en français (bannière : *"Ce fork ajoute le support de la langue française"*) — ceci est confirmé.
- Mais **il n'existe aucun `assets/fr.json` ni `assets/fr.lproj`**. Les chaînes de l'application (`L10n.swift` + `en.json`/`th.json` + `en.lproj`/`th.lproj`) sont uniquement **anglais/thaï**, exactement comme upstream.

**➡ Conclusion : la Phase 4 ("Localization FR") du plan original ne s'applique à rien de concret aujourd'hui — il n'y a pas de fichier `fr.json` à mettre à jour. Ajouter le français au niveau applicatif serait un chantier séparé et bien plus large (traduire l'intégralité des clés existantes, pas seulement les nouvelles) : hors périmètre de ce plan sauf demande explicite. Pour les nouvelles clés nécessaires (voir ci-dessous), n'ajouter que EN + TH, comme le reste de l'app.**

---

## Classification des Fonctionnalités Upstream (révisée)

### ✅ À PRENDRE

#### 1. ModConfigEditorView.swift + CodeEditorView.swift (NOUVEAUX FICHIERS)
**Valeur** : ⭐⭐⭐⭐⭐ Toujours valide
- Éditeur visuel hiérarchique (arbre) de `config.json` de mod, avec bascule vers un éditeur JSON brut avec coloration syntaxique.
- Aucune fonctionnalité équivalente dans le fork (confirmé par recherche : `ConfigEditor`, `CodeEditorView` absents).
- `CodeEditorView.swift` n'a **aucune dépendance** au ViewModel (0 appel `vm.*`) → copie directe sans risque.
- `ModConfigEditorView.swift` (état final après `9c64fcd`, 281 lignes de plus qu'après `adee02c` — **prendre l'état final `upstream/main`, pas `adee02c` seul**) dépend de :
  - `vm.L`, `vm.gameDir`, `vm.showModal` → **existent déjà** dans le ViewModel du fork, aucun problème.
  - `vm.editingModConfig` → **à ajouter** (`@Published var editingModConfig: ModItem? = nil`), simple.
  - `vm.backupMod(mod:)` et `vm.restoreModZip(mod:)` → **[CORRECTION] n'existent PAS dans le fork.** Upstream les implémente comme une fonctionnalité indépendante (export/import du **dossier entier du mod** en `.zip` via `/usr/bin/zip`/`/usr/bin/unzip`, avec `NSSavePanel`/`NSOpenPanel`), architecturalement distincte du `ModConfigBackupManager` du fork (qui gère un index versionné de snapshots de `config.json` uniquement, en interne, sans dialogue utilisateur).
    - **Décision à prendre** : soit (a) porter ces deux méthodes telles quelles comme fonctionnalité parallèle et autonome ("exporter/restaurer le mod en zip"), soit (b) réécrire les deux points d'appel dans `ModConfigEditorView.swift` pour utiliser `ModConfigBackupManager` à la place. Recommandation : (a) d'abord (risque faible, isolé), réévaluer (b) plus tard si redondance gênante.
- **Décision** : **PRENDRE**, avec extraction fichier-par-fichier (voir stratégie révisée), pas cherry-pick.

#### 2. AppChangelogView.swift (NOUVEAU FICHIER)
**Valeur** : ⭐⭐⭐ Moyenne — toujours valide
- Vue in-app du `CHANGELOG.md`. Dépendance unique : `vm.L` (existe déjà).
- Nécessite le hunk de `build_app.py` (5 lignes, additif, sûr) qui copie `CHANGELOG.md` dans les Resources du bundle — **à appliquer manuellement**, pas via cherry-pick de `9c64fcd` (qui touche aussi CHANGELOG/README/screenshots).
- **Décision** : **PRENDRE**.

#### 3. Nouvelles clés L10n requises
Les 3 vues ci-dessus référencent 13 clés `L10n` absentes du fork (vérifié par grep dans `L10n.swift`) :
```
L10n.Main.appChangelog
L10n.Saves.saveChanges
L10n.Settings.configBackupAndRestore
L10n.Settings.configBackupMod
L10n.Settings.configCodeEditor
L10n.Settings.configInvalidJson
L10n.Settings.configNoSettingsFound
L10n.Settings.configNoSettingsFoundFor
L10n.Settings.configRawJson
L10n.Settings.configReset
L10n.Settings.configRestoreConfig
L10n.Settings.configRestoreMod
L10n.Settings.configSaved
L10n.Settings.configSearchPlaceholder
L10n.Settings.settings
```
(`L10n.Settings.settings` existe peut-être déjà sous un autre nom — à vérifier au moment de l'implémentation, éviter le doublon.)
- **Décision** : ajouter ces clés à `L10n.swift` + `assets/en.json` + `assets/th.json` + `.lproj` correspondants. **Pas de `fr.json`** (voir correction §3 ci-dessus) sauf demande explicite du user.

---

### ❌ RETIRÉ (anciennement "À PRENDRE", invalidé par la vérification)

#### ~~NexusAPIService.swift~~, ~~ModDetailView.swift~~, ~~Nexus integration dans ViewModel/ModListView~~
**[CORRECTION]** Voir constat §2. Le fork a une implémentation Nexus indépendante et plus mature (`NexusUpdateChecker.swift`, `NexusCategory.swift`, `ThaiModDetailView`). Reprendre le code upstream créerait une redondance architecturale et un risque de régression sur la sécurité (le fork stocke la clé API dans le Keychain ; upstream la stocke en clair dans `UserDefaults` — confirmé, voir encadré ci-dessous). **Ne pas prendre.**

Si des idées UX précises de `ModDetailView.swift` upstream (mise en page, interactions) semblent utiles, elles peuvent être reprises **visuellement** dans `ThaiModDetailView`, mais pas le code.

---

### ✅ [TRANCHÉ] SmapiInstaller.swift — pratique hybride à adopter

**[CORRECTION]** La première révision de ce plan laissait ce point "à évaluer" faute d'avoir comparé les deux diffs en détail. Comparaison faite (diff complet fork vs upstream depuis `merge-base` sur `install()` et `uninstall()`) — les deux camps ont chacun une pratique que l'autre n'a pas :

**Ce que le fork fait mieux (à garder) :**

- Validation du code HTTP de la réponse de téléchargement avant de continuer (upstream ne vérifie pas le statut HTTP).
- Vérification du code de sortie d'`unzip` (upstream suppose toujours un succès silencieux).
- Vérification que le payload extrait n'est pas vide avant de toucher `gameDir` (protège contre une archive tronquée qui s'extrait "avec succès" mais produit un dossier partiel/vide).
- Messages d'erreur avec détail formaté séparément de la clé de traduction (`completion(Bool, String, String?)`), pour ne pas corrompre la clé L10n en y concaténant du texte brut.
- `uninstall()` du fork a été réécrit avec le même soin (déplacement du lanceur SMAPI de côté avant remplacement, restauration en cas d'échec) — upstream a une amélioration comparable ici (`tempTrashLauncher`), les deux se valent sur ce point précis.

**Ce qu'upstream fait mieux (à considérer pour import ciblé, pas en bloc) :**

- Le rollback d'`install()` upstream est **plus fin-grain** : il suit `copiedDestPaths` (chaque fichier du payload copié) et sauvegarde individuellement, dans `smapiBackupFolder`, tout fichier existant qu'il s'apprête à écraser — puis, en cas d'échec à n'importe quelle étape de la boucle de copie, il **annule chaque fichier déjà copié et restaure chaque fichier sauvegardé**, un par un.
- Le rollback du fork, lui, ne protège que **le binaire `StardewValley` seul** (via `backupGameBin`) — si la boucle de copie échoue après avoir écrasé 4 fichiers sur 10 dans `smapi-internal`, seul le lanceur est restauré ; les 4 autres fichiers écrasés restent modifiés. C'est une lacune réelle par rapport à upstream sur ce point précis.

**Décision** : **porter le mécanisme de rollback par-fichier d'upstream (`copiedDestPaths` + sauvegarde individuelle avant écrasement, restauration itérative en cas d'échec) dans la version du fork**, en conservant toutes les validations amont du fork (HTTP, code retour unzip, payload non vide) qu'upstream n'a pas. Ne pas reprendre le fichier upstream tel quel — fusionner uniquement ce mécanisme précis dans la structure déjà plus défensive du fork. Effort estimé : petit à moyen, isolé à `SmapiInstaller.install()`, sans dépendance aux autres items de ce plan — peut être traité comme tâche indépendante (avec sa propre couverture Swift Testing si l'effort de tests en cours s'étend à ce fichier).

---

### ⚠️ Déjà dans le Fork (confirmé)

#### Pagination des mods (15/page), Catégories/Filtres, Mod Tag Inference
**Statut** : confirmé **DÉJÀ PRÉSENT** et plus développé côté fork (`ModListView.swift` du fork a divergé de 1136 lignes vs 614 pour upstream sur la même période — le fork n'est pas en retard, il est allé plus loin dans une direction différente).
- **Décision** : **PRÉSERVER** fork, ignorer upstream. *(inchangé du plan original)*

---

### ❌ À SKIPPER (confirmé)

#### Screenshots, READMEs, CHANGELOG.md upstream
**[CORRECTION mineure]** Confirmé SKIP, avec une précision : `9c64fcd` ne réorganise pas les screenshots upstream, il les **supprime** (0 octet). Aucune pertinence pour le fork de toute façon. READMEs/CHANGELOG upstream sont en anglais/thaï et divergent du contenu français du fork — SKIP intégral, sauf à vouloir ajouter manuellement une entrée CHANGELOG côté fork décrivant *ce* travail (ModConfigEditorView etc.) une fois fait.

---

## Stratégie de Merge (révisée)

### [CORRECTION] Abandon du cherry-pick, extraction fichier-par-fichier

Pas de `git cherry-pick`. À la place :

```bash
# 1. S'assurer qu'upstream est à jour
git fetch upstream main

# 2. Créer une branche de travail (pas sur main directement, malgré la préférence
#    habituelle de travailler sur main pour ce projet — ce chantier touche des
#    fichiers plus sensibles que les extensions de tests, une branche est plus sûre)
git checkout -b feature/config-editor-from-upstream

# 3. Extraire uniquement les 3 fichiers neufs, état final upstream/main
#    (pas adee02c seul : ModConfigEditorView.swift a été étendu par 9c64fcd ensuite)
git show upstream/main:StarHubTH/Views/ModConfigEditorView.swift > StarHubTH/Views/ModConfigEditorView.swift
git show upstream/main:StarHubTH/Views/CodeEditorView.swift      > StarHubTH/Views/CodeEditorView.swift
git show upstream/main:StarHubTH/Views/AppChangelogView.swift    > StarHubTH/Views/AppChangelogView.swift
git add StarHubTH/Views/ModConfigEditorView.swift StarHubTH/Views/CodeEditorView.swift StarHubTH/Views/AppChangelogView.swift
```

**Validation immédiate** : `swift build` échouera à ce stade (symboles `vm.editingModConfig`, `vm.backupMod`, `vm.restoreModZip`, clés `L10n.*` manquants) — attendu, c'est l'étape suivante qui les fournit.

### Étape 2 : Câblage manuel dans le ViewModel

Dans `StarHubTH/StarHubTHViewModel.swift`, ajouter :
```swift
@Published var editingModConfig: ModItem? = nil
```
Et porter (depuis `upstream/main:StarHubTH/StarHubTHViewModel.swift`, lignes ~1578-1650) les méthodes `backupMod(mod:)` et `restoreModZip(mod:)` telles quelles (option (a) ci-dessus) — fonctionnalité d'export/import zip du dossier de mod complet, indépendante de `ModConfigBackupManager`.

### Étape 3 : Point d'entrée UI

Dans `StarHubTH/Views/ModListView.swift`, ajouter une action (bouton ou item de menu contextuel existant sur la ligne de mod) qui fait `vm.editingModConfig = mod`.

Dans `StarHubTH/Views/MainView.swift`, ajouter le routage d'onglet/sheet pour présenter `ModConfigEditorView` quand `vm.editingModConfig != nil` et pour l'onglet `AppChangelog` → `AppChangelogView(vm: vm)` (s'inspirer du routage upstream dans `MainView.swift`, à adapter à la structure de navigation du fork qui a divergé).

### Étape 4 : `build_app.py`

Appliquer manuellement le hunk (5 lignes) qui copie `CHANGELOG.md` vers les Resources du bundle — ne pas cherry-picker `9c64fcd`.

### Étape 5 : Localisation

Ajouter les 13 clés listées plus haut dans `L10n.swift`, `assets/en.json`, `assets/th.json`, `assets/en.lproj/Localizable.strings`, `assets/th.lproj/Localizable.strings`. Pas de `fr.json` (n'existe pas actuellement — voir correction §3).

### Étape 6 : Validation

```bash
swift build
swift test
python build_app.py --check-localization   # vérifier qu'il compare EN/TH, pas FR
open build/release/StarHubTH.app
```
Vérifier manuellement :
- [ ] L'éditeur de config s'ouvre depuis la liste des mods
- [ ] Bascule éditeur visuel / JSON brut fonctionne
- [ ] Backup/restore zip du mod fonctionne (nouvelle fonctionnalité, indépendante de `ModConfigBackupManager`)
- [ ] La vue Changelog affiche le contenu de `CHANGELOG.md`
- [ ] Pagination, catégories, filtres du fork toujours intacts (non touchés par ce travail)
- [ ] Tests SaveManager/BackupManagers toujours verts (fichiers non touchés par cette extraction)

---

## Risques et Mitigations (révisés)

### Risque 1 : Redondance backup mod (zip) vs `ModConfigBackupManager`
**Probabilité** : 🟡 Moyenne — deux mécanismes de "backup" coexisteront (zip complet du dossier mod à la demande vs index versionné auto de `config.json`). Documenter clairement la différence dans l'UI pour éviter la confusion utilisateur. Envisager un renommage clair ("Exporter en .zip" vs "Historique des sauvegardes de config").

### Risque 2 : Divergence future si upstream continue sur cette voie
**Probabilité** : 🟢 Faible à court terme — upstream n'a pas de commits Nexus/config-editor après `91c9a57` au moment de cette analyse (2026-07-23). Refaire un `git fetch upstream` avant de relancer ce travail si le temps a passé.

### Risque 3 : Portage du rollback par-fichier dans SmapiInstaller.swift
**Probabilité** : 🟢 Faible — le mécanisme à porter (`copiedDestPaths` + restauration itérative, voir section "SmapiInstaller.swift — pratique hybride à adopter") est isolé à `install()` et n'a pas de dépendance avec le reste de ce plan. Risque principal : introduire une régression dans une fonction qui touche directement les fichiers du jeu — traiter comme tâche indépendante avec sa propre validation manuelle (installation SMAPI réelle testée avant/après), pas à la légère.

---

## Critères de Succès (révisés)

1. **Compilation** : ✅ `swift build` SUCCESS
2. **Tests** : ✅ `swift test` — tous les tests existants passent, aucun nouveau test requis par ce plan (pas de logique métier nouvelle testable au sens Swift Testing du fork, sauf si `backupMod`/`restoreModZip` sont jugés dignes de couverture — à évaluer séparément, en cohérence avec l'effort de test en cours sur `SaveManager`)
3. **Localisation** : ✅ `build_app.py --check-localization` SUCCESS (parité EN/TH uniquement — pas de FR applicatif à ce jour)
4. **Fonctionnalités fork préservées** : pagination, catégories, `ModConfigBackupManager`, `ModInstallBackupManager`, intégration Nexus (`NexusUpdateChecker`, `ThaiModDetailView`) — **aucun de ces fichiers n'est touché par ce plan révisé**, donc aucune régression attendue de ce côté.
5. **Nouvelles fonctionnalités** :
   - ✅ Éditeur de config visuel + JSON brut accessible depuis la liste des mods
   - ✅ Vue changelog in-app fonctionnelle
   - ✅ Export/restauration zip d'un mod (nouvelle fonctionnalité autonome)
6. **Meilleures pratiques consolidées** :
   - ✅ Stockage Keychain de la clé API Nexus préservé (pas de régression vers `UserDefaults`)
   - ✅ Rollback par-fichier d'`install()` porté dans `SmapiInstaller.swift`, en plus des validations amont déjà présentes côté fork (HTTP, code retour unzip, payload non vide)

---

## Prochaine Étape

Le plan révisé est prêt pour exécution. Points restant ouverts à trancher avec l'utilisateur :

- **A.** Lancer l'extraction des 3 fichiers + câblage ViewModel/UI/L10n telle que décrite ci-dessus (recommandé, périmètre limité et sans risque pour le travail SaveManager en cours).
- **B.** Reporter ce chantier après la fin de l'extension de tests `SaveManager` en cours (`docs/superpowers/plans/2026-07-23-savemanager-folder-ops-tests.md`), pour ne pas mélanger deux fronts de travail.
- **C.** Traiter le portage du rollback par-fichier dans `SmapiInstaller.swift` comme sous-tâche séparée avant ou après ce plan (décision déjà prise, reste à implémenter — voir section dédiée ci-dessus).
- **D.** Autre approche (à préciser).
