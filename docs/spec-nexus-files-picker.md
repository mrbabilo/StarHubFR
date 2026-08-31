# SPEC — Sélection du fichier principal sur `files.json`

> **Statut** : à implémenter · **Effort** : S · **Risque** : bas
> **Origine** : audit de `jathych/Stardew-Valley-Mod-Updater` (2026-08-31), §« Audit 2 ».
> **Documents liés** : [`ROADMAP.md`](ROADMAP.md) (X8), [`DOMAINE.md`](DOMAINE.md) §3.2.

---

## 1. Constat

`NexusDownloadAPI.pickPrimaryFile(_:)` (`StarHubTH/Models/NexusDownloadAPI.swift:58`) choisit
le fichier principal comme **le premier** renvoyé par l'API Nexus pour la catégorie 1
(Main files), ou le premier de la liste en repli :

```swift
list.files.first { $0.categoryId == 1 } ?? list.files.first
```

Or, pour un mod qui a **plusieurs fichiers MAIN** — un cas réel et fréquent : un auteur
qui a publié v1.0.0, v1.5.0, puis v2.0.0 — l'ordre renvoyé par l'API n'est pas garanti
comme étant le plus récent. La documentation Nexus ne contractualise ni l'ordre de tri,
ni la présence d'un champ de tri dans la réponse.

**Conséquence utilisateur** : `NexusUpdateChecker.fetchModInfo` (`StarHubTH/NexusUpdateChecker.swift:582-616`),
qui prend `pickPrimaryFile(...)` pour comparer la version du MAIN à celle de l'en-tête
`mods/{id}.json`, peut prendre un MAIN obsolète comme référence :

- soit un mod est signalé **à jour** alors qu'il a un fichier MAIN plus récent ;
- soit, à l'inverse, un mod est signalé **obsolète** avec un numéro de version
  inférieur à la réalité.

Le bug est silencieux : pas d'erreur réseau, pas d'alerte, juste un `latestVersion`
erroné dans le cache, propagé en cache `ModUpdate` (UserDefaults) jusqu'à la prochaine
fenêtre de check.

### Pattern de référence (rejeté, mais inspirant)

`jathych/Stardew-Valley-Mod-Updater/check_mods.py:81-93` filtre d'abord `category_name == "MAIN"`,
puis prend `max(uploaded_timestamp)`. Le concept est bon ; on le transpose à notre
équivalent `categoryId == 1` + `uploaded_timestamp`.

---

## 2. Correctif proposé

### 2.1 Étendre le modèle `NexusModFile`

Le `Decodable` actuel (`NexusDownloadAPI.swift:11-23`) ne porte ni `uploaded_timestamp`,
ni `category_name`. On les ajoute.

```swift
struct NexusModFile: Decodable {
    let fileId: Int
    let categoryId: Int
    /// Nom lisible de la catégorie côté Nexus (ex. "MAIN", "OLD VERSION", "MISC").
    /// Présent dans la réponse v1 même s'il n'est pas exploité ailleurs.
    let categoryName: String?
    let version: String?
    let modVersion: String?
    /// Timestamp Unix (secondes) de la mise en ligne de ce fichier précis. Source
    /// unique de vérité pour « le plus récent » : `updated_timestamp` du mod entier
    /// (`mods/{id}.json`) ne porte que la date du dernier upload et peut donc
    /// appartenir à un MAIN plus ancien si le dernier upload est un OPTIONAL.
    let uploadedTimestamp: Int?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case categoryId = "category_id"
        case categoryName = "category_name"
        case version
        case modVersion = "mod_version"
        case uploadedTimestamp = "uploaded_timestamp"
    }
}
```

### 2.2 Helper de tri (pure function, testable)

Ajout d'un nouveau sélecteur à `NexusDownloadAPI`, sans toucher au `pickPrimaryFile`
existant (utilisé par `NexusDownloader.resolveFileId` pour la résolution d'ID de
téléchargement — là, l'ordre n'importe pas, c'est juste « un fichier jouable ») :

```swift
/// Le MAIN le plus récent (par `uploaded_timestamp` desc), ou — à défaut — le
/// fichier le plus récent tous catégories confondues. `pickPrimaryFile` continue
/// d'exister pour la résolution d'ID de téléchargement, où l'ordre est indifférent.
static func pickLatestMainFile(_ list: NexusModFileList) -> NexusModFile? {
    let main = list.files.filter { $0.categoryId == 1 }
    let pool = main.isEmpty ? list.files : main
    return pool.max { lhs, rhs in
        (lhs.uploadedTimestamp ?? 0) < (rhs.uploadedTimestamp ?? 0)
    }
}
```

**Pourquoi `max(by:)` plutôt qu'un `sorted(...).first`** : O(n) au lieu de O(n log n),
et plus court à lire. `Int?` est `Comparable` depuis Swift 5, mais `?? 0` reste
explicite pour signaler le repli (fichier sans timestamp = considéré comme très ancien,
donc jamais élu « plus récent »).

### 2.3 Branchement dans `NexusUpdateChecker.fetchModInfo`

`NexusUpdateChecker.swift:582-616` fait aujourd'hui :

```swift
guard let primaryFile = NexusDownloadAPI.pickPrimaryFile(fileList),
      let fileVer = (primaryFile.version ?? primaryFile.modVersion)?.trimmingCharacters(...),
      !fileVer.isEmpty else { finalize(finalVersion); return }
if Self.compare(fileVer, finalVersion) == .orderedDescending {
    finalVersion = fileVer
}
```

→ Remplacer par `pickLatestMainFile` (et conserver le même contrat d'échec silencieux).
Ajouter aussi le test « le MAIN le plus récent est pris même si d'autres fichiers plus
récents existent en OPTIONAL ou MISC » — voir §3.

### 2.4 Pas de changement de cache

Le `CachedUpdate` (`NexusUpdateChecker.swift:404-416`) et la persistance UserDefaults
demeurent identiques : `latestVersion` reste une chaîne, sa valeur sera simplement plus
juste. Aucune migration de cache nécessaire (les anciennes entrées seront écrasées à la
prochaine vérification réussie).

---

## 3. Tests

`StarHubTHCore/Tests/` — nouvelles cibles de test (le module Core expose déjà
`NexusDownloadAPI` pur) :

1. `pickLatestMainFile_choosesNewestMainByTimestamp`
   Liste : `[{MAIN, ts=100, v="1.0.0"}, {MAIN, ts=200, v="1.5.0"}, {MISC, ts=300, v="2.0.0"}]`
   → renvoie `MAIN v="1.5.0"`.

2. `pickLatestMainFile_fallsBackToAllWhenNoMain`
   Liste : `[{MISC, ts=100, v="1.0.0"}, {OPTIONAL, ts=200, v="1.5.0"}]`
   → renvoie `OPTIONAL v="1.5.0"`.

3. `pickLatestMainFile_handlesMissingTimestamps`
   Liste : `[{MAIN, ts=nil, v="1.0.0"}, {MAIN, ts=100, v="1.1.0"}]`
   → renvoie celui avec timestamp (le nil est plus ancien que 100, cohérent).

4. `pickLatestMainFile_returnsNilOnEmptyList`
   Liste : `[]` → `nil`.

5. `NexusModFile_decodesUploadedTimestampFromRealNexusPayload`
   Charge un échantillon réel (anonymisé) de `files.json` et vérifie le décodage du
   nouveau champ — défaut de régression principal du refactor.

**Effort de test** : ~30 minutes, 5 cas, 5 fonctions courtes. Réutilise les fixtures
JSON déjà présentes dans le module Core.

---

## 4. Hors périmètre

- **Tri par `mod_version` plutôt que `uploaded_timestamp`** : tentant, mais la version
  est une chaîne non normalisée (« 1.0 », « 1.0.0 », « 1.0-beta »). Le timestamp est
  plus fiable et moins cher à comparer.
- **Changement de la logique `pickPrimaryFile` (utilisée par `NexusDownloader`)** : là,
  c'est l'ID qui compte, pas la version. Le tri par date y serait sans effet et
  augmenterait la complexité sans bénéfice.
- **Détection de mod « beta only » / « abandoned »** : autre sujet, à traiter
  séparément si le besoin émerge.
- **Fallback `category_name == "MAIN"`** : la spec Nexus v1 confirme `category_id == 1`,
  qu'on utilise déjà ; `category_name` est récupéré pour observabilité future
  (badge « OLD VERSION » à venir peut-être), pas pour ce correctif.

---

## 5. Plan d'implémentation

| # | Action | Fichiers | Effort |
| :-- | :-- | :-- | :-- |
| 1 | Étendre `NexusModFile` avec `categoryName` et `uploadedTimestamp` | `Models/NexusDownloadAPI.swift` | 5 min |
| 2 | Ajouter `pickLatestMainFile(_:)` | `Models/NexusDownloadAPI.swift` | 5 min |
| 3 | Brancher `pickLatestMainFile` dans `fetchModInfo` | `NexusUpdateChecker.swift:608` | 5 min |
| 4 | Ajouter les 5 tests unitaires | `Core/Tests/...` | 30 min |
| 5 | `python3 build_app.py` (validation build) | — | 2 min |
| 6 | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | — | 5 min |
| 7 | Ajouter entrée au CHANGELOG (`[Unreleased]`) | `CHANGELOG.md` | 2 min |

**Total** : ~55 min. · **Risque** : bas (modèle étendu, nouvelle fonction pure,
un site d'appel changé). · **Rétrocompatibilité** : totale (le cache existant reste
valide, le nouveau champ est juste un décodage de plus).

---

## 6. Critères d'acceptation

- [ ] `python3 build_app.py` passe (parité L10n + compile).
- [ ] `swift test` passe (5 nouveaux tests + 139 existants).
- [ ] `pickLatestMainFile` renvoie le MAIN le plus récent sur un échantillon réel
      prélevé sur un mod de la modlist de test (au moins un mod avec 3+ fichiers MAIN).
- [ ] `fetchModInfo` ne lève plus d'avertissement, et le cache `latestVersion` d'un
      mod testé correspond bien à la version du MAIN le plus récent sur Nexus.
- [ ] Entrée `[Unreleased]` du `CHANGELOG.md` ajoutée sous `### Fixed`.
