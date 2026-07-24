# Plan d'implémentation : Installation de mods par glisser-déposer

## Objectif
Permettre l'installation de packs de mods au format zip dans le dossier `Mods_disabled/` du jeu Stardew Valley via glisser-déposer dans StarHubTH, avec gestion intelligente des conflits et système de backup.

## Contraintes et décisions validées

### Architecture globale
- **Approche hybride pour backups** : Système dédié `ModInstallBackupManager` séparé de `ModConfigBackupManager` existant
- **Stockage backups** : `~/Library/Application Support/StarHubTH/Backups/ModInstalls/`
- **Rétention hybride** : Tous les backups des 30 derniers jours + 1 backup par mois pour l'historique long terme

### Flux d'installation
- **Extraction** : Atomique dans dossier temporaire `/tmp/StarHubTH_<timestamp>/` avec aperçu avant validation
- **Destination finale** : `Mods_disabled/` du jeu
- **Validation utilisateur** : Sheet/Modal avec aperçu de ce qui sera installé et des conflits détectés
- **UI** : Bouton "Installer un mod" dans `ModListView` ouvrant une sheet avec zone de drop

### Gestion des conflits
- **Conflits de dossiers** : Détection + présentation à l'utilisateur avec options (écraser avec backup / renommer / ignorer)
- **Conflits de fichiers** : Comparaison intelligente (versions/dates) + choix utilisateur (garder l'ancien / utiliser le nouveau / fusionner)
- **Erreurs** : Partition avec choix utilisateur (erreurs critiques = abort, erreurs mod-spécifiques = continuer sans ce mod)

### Fichiers zip
- **Formats supportés** : .zip uniquement (via ZipArchive macOS)
- **Limites** : 500MB max par zip, 10 mods max par drag & drop
- **Validation** : Extension .zip + signature ZIP (PK\x03\x04) + vérification taille
- **Structure** : Détection heuristique multi-niveaux :
  1 dossier racine avec manifest.json → base = ce dossier
  2 plusieurs dossiers avec manifest.json → multi-mod pack
  3 manifest.json à la racine → base = racine
  4 sinon → erreur structure non reconnue

### Dépendances
- **Détection passive** : Scan des manifest.json pour identifier les dépendances
- **Suggestions intelligentes** : Signalées celles manquantes + proposer d'activer les mods déjà installés mais désactivés + liens vers Nexus pour les mods manquants

## Composants à implémenter

### 1. Modèle de données

#### ModInstallBackup.swift
```swift
// Backup d'un mod complet avant installation
struct ModInstallBackup: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let originalFolderName: String
    let backupPath: String
    let modMetadata: ModMetadata
    let reason: BackupReason // .beforeInstall, .beforeUpdate
}

enum BackupReason {
    case beforeInstall
    case beforeUpdate
}

struct ModMetadata: Codable {
    let name: String
    let version: String
    let author: String
    let uniqueId: String
}
```

#### ZipModInfo.swift
```swift
// Informations extraites d'un zip avant installation
struct ZipModInfo: Identifiable {
    let id: UUID
    let zipName: String
    let detectedMods: [DetectedMod]
    let validationStatus: ValidationStatus
    let conflicts: [ModConflict]
    let estimatedSize: Int64
}

struct DetectedMod: Identifiable {
    let id: UUID
    let folderName: String
    let relativePath: String // Chemin relatif dans le zip
    let manifest: ModManifest
    let hasConfigFiles: Bool
    let dependencies: [String]
    let existingVersion: ModItem? // Version existante si conflit
}

struct ModManifest {
    let name: String
    let version: String
    let uniqueId: String
    let author: String
    let dependencies: [ModDependency]
}

enum ValidationStatus {
    case valid
    case invalidStructure
    case oversized
    case tooManyMods
    case corrupted
}

struct ModConflict: Identifiable {
    let id: UUID
    let conflictType: ConflictType
    let folderName: String
    let existingVersion: String
    let newVersion: String
    let resolutionOptions: [ConflictResolution]
}

enum ConflictType {
    case folderExists
    case configFilesConflict
    case dependencyMissing
}

enum ConflictResolution {
    case overwriteWithBackup
    case rename
    case skip
    case keepExisting
    case useNew
}
```

### 2. Logique métier

#### ModInstallBackupManager.swift
```swift
class ModInstallBackupManager {
    static let shared = ModInstallBackupManager()

    // Créer un backup avant installation
    func createBackup(for mod: ModItem, reason: BackupReason) throws -> ModInstallBackup

    // Restaurer un backup
    func restoreBackup(_ backup: ModInstallBackup, gameDir: String) throws

    // Nettoyer les vieux backups (rétention hybride)
    func cleanupOldBackups() -> Int

    // Lister les backups disponibles
    func listBackups() -> [ModInstallBackup]

    // Supprimer un backup
    func deleteBackup(_ backup: ModInstallBackup) throws
}
```

#### ModZipInstaller.swift
```swift
class ModZipInstaller {
    // Valider le zip (taille, format, structure)
    func validateZip(at url: URL) -> ValidationStatus

    // Analyser le contenu du zip
    func analyzeZip(at url: URL, gameDir: String, existingMods: [ModItem]) throws -> ZipModInfo

    // Extraire le zip dans le dossier temporaire
    func extractToTemp(zipUrl: URL) throws -> URL

    // Installer depuis le dossier temporaire vers Mods_disabled
    func install(from tempDir: URL, to modsDisabledPath: String, selections: [InstallSelection]) throws

    // Nettoyer le dossier temporaire
    func cleanupTempDir(at url: URL)

    // Détection heuristique de la structure du zip
    private func detectZipStructure(at url: URL) -> ZipStructure
}

enum ZipStructure {
    case singleMod(folderName: String)
    case multiMod(mods: [String])
    case flatRoot
    case unrecognized
}

struct InstallSelection {
    let modId: UUID
    let selected: Bool
    let conflictResolution: ConflictResolution?
    let configResolution: ConfigResolution?
}

enum ConfigResolution {
    case keepExisting
    case useNew
    case merge
}
```

### 3. Interface utilisateur

#### ModInstallView.swift (nouvelle vue)
```swift
struct ModInstallView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var isDropTarget = false
    @State private var pendingZip: ZipModInfo?
    @State private var extractedMod: ZipModInfo?
    @State private var showConflictDialog = false

    var body: some View {
        VStack {
            // Zone de drop visuelle
            DropArea(isDropTarget: $isDropTarget)
                .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
                    handleDrop(providers)
                }

            // Aperçu de ce qui sera installé
            if let modInfo = extractedMod {
                InstallPreview(modInfo: modInfo)
                    .environmentObject(vm)
            }
        }
    }
}
```

#### InstallPreview.swift
```swift
struct InstallPreview: View {
    let modInfo: ZipModInfo
    @ObservedObject var vm: StarHubTHViewModel
    @State private var selections: [UUID: InstallSelection] = [:]
    @State private var showBackups = false

    var body: some View {
        VStack {
            // Header avec informations générales
            InstallPreviewHeader(modInfo: modInfo)

            // Liste des mods détectés
            ForEach(modInfo.detectedMods) { mod in
                DetectedModRow(mod: mod, existingVersion: mod.existingVersion)
                    .overlay(selectionBadge)
            }

            // Section des conflits
            if !modInfo.conflicts.isEmpty {
                ConflictSection(conflicts: modInfo.conflicts)
            }

            // Section des dépendances
            DependencySection(mods: modInfo.detectedMods)

            // Actions
            HStack {
                Button("Annuler") { cancelInstall() }
                Button("Installer") { installSelected() }
                    .disabled(!hasValidSelections)
                Button("Gérer les backups") { showBackups = true }
            }
        }
    }
}
```

#### ModInstallBackupsView.swift (nouvelle vue pour gestion backups)
```swift
struct ModInstallBackupsView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var backups: [ModInstallBackup] = []

    var body: some View {
        VStack {
            List(backups) { backup in
                ModInstallBackupRow(backup: backup)
                    .contextMenu {
                        Button("Restaurer") { restoreBackup(backup) }
                        Button("Supprimer") { deleteBackup(backup) }
                    }
            }
        }
        .onAppear { loadBackups() }
    }
}
```

### 4. Intégration dans ModListView

```swift
// Ajouter dans ModListView.swift
@State private var showInstallSheet = false

var body: some View {
    ScrollView {
        VStack {
            // Nouveau bouton d'installation
            HStack {
                Button("Installer un mod") {
                    showInstallSheet = true
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding(.bottom, 8)

            // ... code existant ...
        }
    }
    .sheet(isPresented: $showInstallSheet) {
        ModInstallView(vm: vm)
    }
}
```

### 5. Localisation (L10n.swift + assets/en.json, th.json)

```swift
// L10n.swift
enum ModInstall {
    static let title = "mod_install_title"
    static let installButton = "mod_install_button"
    static let dropZoneText = "mod_install_drop_zone"
    static let analyzingZip = "mod_install_analyzing"
    static let extractToTemp = "mod_install_extracting"
    static let validationError = "mod_install_validation_error"
    static let conflictDetected = "mod_install_conflict"
    static let backupCreated = "mod_install_backup_created"
    static let installSuccess = "mod_install_success"
    static let installFailed = "mod_install_failed"
    static let dependencyMissing = "mod_install_dependency_missing"
    static let activateSuggestion = "mod_install_activate_suggestion"
    static let viewOnNexus = "mod_install_view_nexus"
}
```

## Flux d'exécution détaillé

### 1. Drop initial
```
User drop zip → validateZip() → analyzeZip() → show InstallPreview
```

### 2. Validation et analyse
```
validateZip()
  ├─ Vérifier extension .zip
  ├─ Vérifier signature PK\x03\x04
  ├─ Vérifier taille < 500MB
  └─ Retourner ValidationStatus

analyzeZip()
  ├─ detectZipStructure()
  ├─ Scanne tous les manifest.json
  ├─ Compare avec mods existants
  ├─ Détecte les conflits (dossiers, fichiers)
  ├─ Scanne les dépendances
  └─ Retourne ZipModInfo
```

### 3. Aperçu et sélection
```
InstallPreview affiche:
  ├─ Liste des mods détectés
  ├─ Conflits identifiés (avec options de résolution)
  ├─ Dépendances manquantes
  └─ Boutons d'action (Installer/Annuler/Gérer backups)
```

### 4. Installation
```
installSelected()
  ├─ Pour chaque mod sélectionné:
  │   ├─ Si conflit dossier:
  │   │  └─ Selon résolution:
  │   │     ├─ overwriteWithBackup → createBackup() → remove existing
  │   │     ├─ rename → renommer nouveau mod
  │   │     └─ skip → passer ce mod
  │   ├─ Si conflit config:
  │   │  └─ Selon résolution:
  │   │     ├─ keepExisting → préserver config.json/fr.json existants
  │   │     ├─ useNew → utiliser nouvelles configs
  │   │     └─ merge → fusionner (si possible)
  │   └─ Copier vers Mods_disabled/
  ├─ scanMods() pour rafraîchir la liste
  └─ cleanupTempDir()
```

### 5. Gestion des erreurs
```
try-catch par mod:
  ├─ Erreur critique (zip corrompu, disque plein):
  │   └─ Abort immédiat + rollback + message utilisateur
  ├─ Erreur mod-spécifique:
  │   └─ Logger + continuer sans ce mod + avertissement
  └─ Toujours: cleanupTempDir()
```

## Tests et validation

### Cas de test à couvrir

1. **Installation simple**
   - Zip avec 1 mod → extraction réussie → mod apparaît dans Mods_disabled

2. **Multi-mod pack**
   - Zip avec 3 mods → tous 3 extraits → apparaissent dans Mods_disabled

3. **Conflit de dossier**
   - ContentPatcher existe déjà → options présentées → backup créé → nouvelle version installée

4. **Conflit de fichiers**
   - config.json existe → comparaison → utilisateur choisit → résolution appliquée

5. **Structure non reconnue**
   - Zip sans manifest.json → erreur claire → installation annulée

6. **Limite de taille**
   - Zip 600MB → erreur taille → installation refusée

7. **Dépendances manquantes**
   - Mod dépend de X non installé → signalé → lien Nexus affiché

8. **Backup et restauration**
   - Créer backup → installer → restauration → version précédente restaurée

9. **Erreur critique**
   - Disque plein pendant extraction → abort → rollback → message utilisateur

10. **Erreur mod-spécifique**
    - Un mod échoue → autres continuent → avertissement affiché

## Risques et mitigations

### Performance
- **Risque** : Extraction de gros zips bloque l'UI
- **Mitigation** : Toutes les opérations lourdes sur background queue, UI reactive avec ProgressView

### Espace disque
- **Risque** : Backups illimités saturent le disque
- **Mitigation** : Rétention hybride automatique + UI pour gestion manuelle

### Conflits complexes
- **Risque** : Conflits de fusion impossibles à résoudre automatiquement
- **Mitigation** : Toujours présenter à l'utilisateur, jamais deviner

### Fichiers corrompus
- **Risque** : Zip corrompu fait planter l'app
- **Mitigation** : Validation robuste + try-catch à tous les niveaux

### UX confuse
- **Risque** : Trop d'options overwhelment l'utilisateur
- **Mitigation** : Options par défaut intelligentes, UI claire avec actions suggérées

## Migration et déploiement

### Aucune migration nécessaire
- Nouvelle fonctionnalité isolée
- Aucun changement de structure de données existante
- Backward compatible

### Déploiement
- Build standard avec `python3 build_app.py`
- Test manuel des scénarios ci-dessus
- Rollback facile (feature flag possible si nécessaire)

## Questions ouvertes

### Résolues
- ✅ Flux d'installation (temporaire + aperçu)
- ✅ Gestion des conflits
- ✅ Stratégie de backup
- ✅ Structure des fichiers
- ✅ Gestion des dépendances
- ✅ UI et UX
- ✅ Validation et sécurité

### À clarifier si nécessaire
- Comportement exact pour la "fusion" de configs (si implémenté)
- Stratégie de pagination si 10+ mods dans un zip (rare mais possible)

## Prochaines étapes

1. ✅ Plan validé par l'utilisateur
2. ⏭️ Implémentation des modèles de données
3. ⏭️ Implémentation de la logique métier
4. ⏭️ Implémentation des composants UI
5. ⏭️ Intégration dans ModListView
6. ⏭️ Localisation complète
7. ⏭️ Tests et validation
8. ⏭️ Documentation utilisateur