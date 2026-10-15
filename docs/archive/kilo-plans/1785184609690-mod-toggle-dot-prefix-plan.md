# Plan d'implémentation : Toggle de mods par préfixe point

## Objectif

Remplacer le move `Mods/ ↔ Mods_disabled/` par un **rename par préfixe point** dans `Mods/` (`Mods/.X` = désactivé). Rend le toggle instantané (rename atomique O(1)) et reste compatible avec tous les modes de lancement (Steam, GOG/direct), contrairement à l'approche `--mods-path` (Stardrop) qui casse sur Steam.

SMAPI ignore nativement les dossiers `.X` dans `Mods/`. `ModItem.folderName` reste **logique** (sans point) — c'est la clé du registre, des profils, des timestamps, des backups (aucune migration de ces maps).

## Invariants critiques (à respecter à chaque étape)

1. **`folderName` logique** (sans point) est la clé de cohérence pour : `installedModRegistry` (ligne 2542), `modActivationTimestamps` (lignes 1431/3412/3624), profils, sort. **Ne jamais stocker `.X` dans `folderName`.**
2. **Scanner ≠ Repairer** : le scanner DOIT voir les `.X` (mods désactivés) ; le repairer DOIT les ignorer (pas son job de nettoyer l'état enabled/disabled).
3. **Junk imbriqué** : retirer `.skipsHiddenFiles` globalement démasquerait `.DS_Store`, `.git/`, etc. Solution : énumération top-level manuelle + sous-scan récursif **avec** `.skipsHiddenFiles` par entrée.
4. **Junk OS vs mod désactivé** : `._Foo` = AppleDouble (junk), `.Foo` = mod désactivé. Ne jamais générer `._<name>`.
5. **Parité L10n** : `en.json` / `fr.json` (validée par le build script).
6. **One-way door** : pas de migration inverse. Documenter dans le CHANGELOG.

## Étapes ordonnées

### 1. Helper `physicalFolderName` sur `ModItem`

- Ajouter dans `StarHubTH/ModItem.swift` (extension ou dans le struct) :
  ```swift
  var physicalFolderName: String {
      (isEnabled ? "" : ".") + folderName
  }
  ```
- Toutes les constructions de chemin disque vers un dossier de mod doivent utiliser `physicalFolderName` (pas `folderName` brut).

### 2. Migration one-shot : `migrateDisabledModsToDotPrefix(gameDir:)`

- Nouvelle méthode dans `StarHubTHViewModel`, appelée dans `performInitialLoad()` (ligne 622, **juste avant** `self.scanMods()`).
- Ajouter la garde `guard !UserDefaults.standard.bool(forKey: UDKey.disabledModsMigratedToDotPrefix)` au début (défense en profondeur, safe si appelée ailleurs).
- Logique :
  - Si `Mods_disabled/` absent → no-op + set flag = true.
  - `fm.contentsOfDirectory(atPath: Mods_disabled)` (top-level seulement, pas récursif).
  - Pour chaque entrée `X` :
    - Si OS junk (`.DS_Store`, `._*`, `__MACOSX`) → skip.
    - Si `Mods/.X` n'existe pas → `fm.moveItem(Mods_disabled/X → Mods/.X)`.
    - Sinon (collision) → `fm.moveItem(Mods_disabled/X → Mods/.X_<uuid8>)` + log warning (préserve les données).
  - Si `Mods_disabled/` ne contient plus que du junk ou est vide → `fm.removeItem(Mods_disabled)`. Sinon (échec partiel) → laisser + logger.
  - Set flag = true à la fin (même en cas d'échec partiel, pour ne pas bloquer ; les restes seront invisibles au scan mais détectés par l'avertissement étape 4).
- Idempotent. Rollback naturel : exception → mods déjà déplacés restent en `.X` (état cohérent), les autres restent en `Mods_disabled/`, reprise au prochain lancement.
- **Aucune migration** de `installedModRegistry` / `modActivationTimestamps` (clés = `folderName` logique, inchangé).

### 3. Nouveau scanner `scanFolderForMods` (ligne 889)

Réécrire en énumération top-level manuelle + sous-scan récursif par entrée :

- `fm.contentsOfDirectory(atPath: modsPath)` — top-level **sans** `skipsHiddenFiles`.
- Pour chaque entrée `entry` (dossier uniquement) :
  - **Classification** (mirroring `ModFolderRepairer.repairFolder` ligne 153-159) :
    - OS junk (`.DS_Store`, `._*`, `__MACOSX`) → skip.
    - Commence par `.` mais pas junk → mod désactivé, `logicalEntry = String(entry.dropFirst())`, `isEnabled = false`.
    - Sinon → mod activé, `logicalEntry = entry`, `isEnabled = true`.
  - `physicalRoot = modsPath + "/" + entry` (avec le point si désactivé).
  - **Sous-scan récursif** de `physicalRoot` **avec** `.skipsHiddenFiles` (l'énumérateur actuel, ligne 894) — préserve l'ignorance du junk imbriqué.
  - Le `relativePath` passé à `parseModFolder` est relatif à `physicalRoot`, donc **déjà sans point** → `folderName` logique dérivé normalement (ligne 874), grouping correct (ligne 902-908).
- **Supprimer** le second appel `scanFolderForMods(at: disabledModsPath, isEnabled: false)` (ligne 947) et la construction de `disabledModsPath` (ligne 756).
- **Avertissement PERMANENT** : si `Mods_disabled/` existe et est non-vide, logger un warning "mods dans Mods_disabled/ seront invisibles". Cet avertissement reste même après le retrait de la migration (étape 17) — il couvre deux cas : (a) recréation par un autre outil, (b) retardataire qui passe d'une version pré-migration directement à N+1. Dans le cas (b), guider l'utilisateur vers la réinstallation via drag-drop.

### 4. Cache de manifests dans `scanMods`

- Instance var `private var manifestCache: [String: (mtime: Date, manifest: ParsedManifest)] = [:]` sur le VM.
- Dans `parseModFolder` (ligne 761), avant le `JSONSerialization.jsonObject` :
  - Lire le mtime du `manifestPath`.
  - Si `manifestCache[manifestPath]?.mtime == mtime` → réutiliser le `manifest` parsé, skip le decode.
  - Sinon → decoder, stocker `(mtime, parsed)` dans le cache.
- Vider le cache à la fin de `scanMods()` (ou le garder entre scans pour bénéficier du hit ; préférer le garder, invalidation par mtime = correct).
- Coût d'un rescan sans changement : ~200 `stat()` + 0 JSON decode.

### 5. `performToggle` (ligne 1289) → rename

- Remplacer la construction src/dst (ligne 1386-1388) :
  ```swift
  let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
  let srcPath = (modsPath as NSString).appendingPathComponent(m.physicalFolderName)
  // target state inverse de currentIsEnabled
  let dstName = targetState ? m.folderName : "." + m.folderName
  let dstPath = (modsPath as NSString).appendingPathComponent(dstName)
  ```
- `fm.moveItem(srcPath → dstPath)` — rename même-parent atomique.
- Supprimer la logique `staleDuplicateAside` (ligne 1409-1427) : un rename même-parent ne peut pas collisionner avec un `.X` préexistant sauf bug logique (à garder défensivement ? — recommandation : garder le set-aside, coût nul).
- Conserver le chaînage `chainToggleDependencies` (opère sur `folderName` logique).
- Conserver le `scanMods()` final (ligne 1452, avec cache étape 4).
- Conserver la file sérielle `pendingToggles` / `isToggling` (sécurité).

### 6. Bulk toggle (ligne ~3540) & `applyProfileToFilesystem` (ligne 3315)

- Remplacer chaque `moveItem(Mods/X ↔ Mods_disabled/X)` par `moveItem(Mods/<physical> ↔ Mods/<nouveau physical>)`.
- Adapter `moveModFolder` (ligne 3329+) : `src/dst` via `physicalFolderName`, `direction` labels ("→ activé" / "→ désactivé" ou garder "→ Mods" pour les logs).
- Conserver `isApplyingProfile` / `bulkToggleProgress` pour la UI.
- Un seul `scanMods()` final (cache hit sur la majorité).

### 7. `deleteMod` (ligne 3679)

- `baseFolder = modsPath` (toujours `Mods/`), `modPath = modsPath + "/" + mod.physicalFolderName`.

### 8. `cleanDisabledMods()` (ligne 2924) → reconduit sur `Mods/.*`

- Énumérer `fm.contentsOfDirectory(atPath: modsPath)`.
- Pour chaque entrée `.X` non OS junk → `fm.removeItem(modsPath + "/" + entry)`.
- Adapter le message `cleanModsNotFound` ("aucun mod désactivé" plutôt que "dossier absent"). L10n à mettre à jour dans `en.json` / `fr.json`.

### 9. `ModFolderRepairer.swift`

- `repairIfNeeded` (ligne 106) : supprimer le scan de `Mods_disabled`, ne scanner que `Mods/`.
- `repairFolder` (ligne 143) : **conserver** le skip des `.` (ligne 159) — le repairer ignore les `.X` désactivés (correct, pas son job).
- `detectDuplicates` (ligne 300) : un seul appel `collectUniqueIds(in: modsPath)` (qui doit maintenant voir les `.X`), puis croiser enabled (X) vs disabled (.X) par UniqueID.
- `collectUniqueIds` (ligne 325) : retirer `.skipsHiddenFiles` (ligne 329) pour capturer les `.X`. Pour chaque folder, dériver `isEnabled = !folderName.hasPrefix(".")` et normaliser le nom logique.

### 10. `ModZipInstaller.swift` (lignes 540-617)

- Destination nouveau mod : `Mods/.<folderName>` (désactivé par défaut).
- Mise à jour mod enabled : `Mods/<folderName>`.
- `existingPath` (ligne 592-595) : `existing.isEnabled ? "Mods/<folderName>" : "Mods/.<folderName>"`.

### 11. `ModInstallBackupManager.swift`

- `restoreBackup` (ligne 170) : `Mods/.<originalFolderName>` (désactivé).
- Ligne 173 : `modsDisabledPath` → `modsPath + "/." + name`.

### 12. Vues & paths résiduels

- `ModConfigEditorView.swift` (ligne 51), `ModInstallView.swift` (lignes 347, 433), `ModListView.swift` (lignes 1277, 1383, 1456) : `mod.isEnabled ? "Mods" : "Mods_disabled"` → `modsPath + "/" + mod.physicalFolderName`.

### 13. `backupMods` (ligne 2920)

- Vérifier le comportement du zip `Process` avec les fichiers cachés (inclut par défaut).
- Décision : **inclure** les `.X` dans le backup (cohérence "backup = tout Mods/"). Documenter.

### 14. Recherche exhaustive

- `grep -rn "Mods_disabled"` sur tout le repo (Swift + tests). Documenter chaque occurrence traitée. Ne doit rester aucune référence active après migration.

### 15. Tests

**Adapter (4 suites existantes)** :
- `ModZipInstallerTests` : `modsDisabledDir` → `Mods/.<name>`. Setup + assertions.
- `ModFolderRepairerTests` : setup sans `Mods_disabled/`. Test doublon "across Mods/X and Mods/.X".
- `ModInstallBackupManagerTests` : `restoreBackup` → `Mods/.<name>`.
- `ModConfigBackupManagerTests` : paths.

**Nouveaux tests** :
- `MigrationTests` : nominal (mods simples, packs/enfants), idempotence, collision (`.X` préexistant → `.X_<uuid8>`), échec partiel, suppression de `Mods_disabled/`.
- `ToggleRenameTests` : rename correct, `folderName` logique inchangé, `physicalFolderName` reflète l'état, chaînage dépendances, toggle de pack.
- `ScannerTests` : `.X` détecté, junk OS ignoré, junk imbriqué ignoré, grouping pack désactivé correct.

### 16. CHANGELOG & validation

- Section `[Unreleased]` : documenter le changement (sémantique `Mods/.X`) + la limitation downgrade (one-way door).
- `python3 build_app.py` sans warning ni erreur.
- `swift test` (si SPM applicable) sinon validation via le build script.
- Parité `en.json` / `fr.json`.
- **Validation empirique SMAPI** : lancer le jeu (Steam + GOG) après migration, vérifier via `startSmapiLogWatcher` que les `.X` ne sont pas chargés.

### 17. Retrait du code de migration (release N+1)

La migration `migrateDisabledModsToDotPrefix` (étape 2) est du code mort une fois les users à jour. Politique décidée : **retrait immédiat à N+1** (la release suivant celle qui introduit le préfixe point).

À faire dans la release N+1 :
- Retirer `migrateDisabledModsToDotPrefix(gameDir:)` du VM.
- Retirer l'appel dans `performInitialLoad()` (juste avant `scanMods()`).
- Retirer la clé `UDKey.disabledModsMigratedToDotPrefix` de `UDKey.swift` (garder la suppression optionnelle dans UserDefaults via un one-shot clean au lancement, ou ignorer la clé orpheline — préférer ignorer, coût nul).
- Retirer `MigrationTests`.
- **Garder** l'avertissement permanent de l'étape 3 (scanMods détecte `Mods_disabled/` non-vide). C'est la seule filet de sécurité pour les retardataires qui passent de N-1 directement à N+1 (skip N) : ils voient le warning et peuvent réinstaller leurs mods désactivés via drag-drop.
- CHANGELOG N+1 : note "removed one-shot migration code from N".

Risque assumé (retardataires N-1 → N+1) : leurs mods désactivés restent dans `Mods_disabled/`, invisibles à l'app. Le warning les guide vers la réinstallation. Accepté comme trade-off pour la netteté du code.

## Risques & mitigations

| Risque | Mitigation |
|---|---|
| Scanner démasque junk imbriqué | Énumération top-level manuelle + sous-scan **avec** `.skipsHiddenFiles` (étape 3). |
| Grouping corrompu par le point | `relativePath` relatif au `physicalRoot` post-strip → `folderName` logique (étape 3). |
| Collision `._Foo` (AppleDouble) | Classification : `._*` reste OS junk (étapes 2, 3). |
| `Mods_disabled/` recréé par autre outil OU retardataire N-1→N+1 | Avertissement PERMANENT dans `scanMods` si `Mods_disabled/` non-vide (étape 3) — guide vers la réinstallation via drag-drop. Survit au retrait de la migration (étape 17). |
| Downgrade | One-way door documenté (étape 16). |
| SMAPI charge un `.X` | Validation empirique (étape 16). |

## Critères d'acceptation

- [ ] `Mods_disabled/` absent (ou vide de mods valides) après migration.
- [ ] Toggle = rename atomique, pas de freeze UI.
- [ ] Lancement Steam + GOG chargent les activés uniquement (log SMAPI).
- [ ] Bulk toggle 50 mods : 1 rescan final, cache hit sur les autres.
- [ ] Switch de profil : batch renames + cache.
- [ ] "Clean disabled mods" supprime `Mods/.*`.
- [ ] 4 suites adaptées + 3 nouvelles suites passent.
- [ ] `python3 build_app.py` propre.

## Hors scope

- Approche `--mods-path` / symlinks (Stardrop) — incompatible Steam.
- Fichier de mods actifs — non supporté par SMAPI.
- Refactor du god-object `StarHubTHViewModel`.
- Migration inverse (downgrade).
