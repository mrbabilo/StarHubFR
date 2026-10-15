# Plan d'implémentation - Sauvegarde Configurations Mods

## Objectif
Implémenter un système de backup/restauration incrémentiel des fichiers `config.json` et `fr.json` des mods activés, avec une interface dédiée et une gestion centralisée.

## Décisions d'architecture prises

1. **Emplacement UI**: Section "Game Management" dans la sidebar (entre "Mods" et "Profiles")
2. **Pattern de communication**: Manager reçoit `gameDir` en paramètre (pas de dépendance directe au ViewModel)
3. **Structure de données**: `ModConfigBackupItem` inclut `parentFolderName` pour gérer les mods groupés
4. **État invalide**: Bouton désactivé avec tooltip informatif (gameDir vide ou 0 mods activés)
5. **Cleanup automatique**: Déclenché après chaque création de backup, avec message de confirmation si des backups sont supprimés
6. **Architecture UI**: NavigationSplitView existante (pas de TabView)

## Architecture du système

### Emplacements de stockage
- **Backups**: `~/Library/Application Support/StarHubTH/Backups/ModConfigs/`
- **Structure**: 
  ```
  ModConfigs/
  ├── metadata.json                          # Index global des backups
  ├── backups/
  │   ├── 2026-07-20_143022_backup/          # Dossier de backup (timestamp)
  │   │   ├── ModFolder1/
  │   │   │   ├── config.json
  │   │   │   └── fr.json
  │   │   └── ModFolder2/
  │   │       └── config.json
  │   └── 2026-07-19_120515_backup/
  ```

### Architecture des backups pour mods groupés
```
// Exemple avec un mod groupé "ContentPatcher Packs" contenant:
//   - "ModA/config.json"
//   - "ModB/fr.json"

Structure du backup:
2026-07-20_143022_backup/
├── ContentPatcher Packs/           // ← parentFolderName = nil (c'est le group)
│   ├── ModA/                       // ← modFolderName = "ModA", parentFolderName = "ContentPatcher Packs"
│   │   └── config.json
│   └── ModB/                       // ← modFolderName = "ModB", parentFolderName = "ContentPatcher Packs"  
│       └── fr.json
└── StandaloneMod/                  // ← modFolderName = "StandaloneMod", parentFolderName = nil
    └── config.json
```

Lors de la restauration:
- ModA → `Mods/ContentPatcher Packs/ModA/config.json`
- ModB → `Mods/ContentPatcher Packs/ModB/fr.json`
- StandaloneMod → `Mods/StandaloneMod/config.json`

## Implémentation - Ordre d'exécution

**Total: 7 fichiers à créer/modifier**

### Étape 1: Modèles de données (1 fichier)
1. Créer `StarHubTH/ModConfigBackup.swift` avec:
   - `ModConfigBackupItem` (incluant `parentFolderName`)
   - `ModConfigBackup`
   - `ModConfigBackupsIndex`

### Étape 2: Manager de backups (1 fichier)
2. Créer `StarHubTH/ModConfigBackupManager.swift` avec:
   - Initialisation des dossiers `~/Library/Application Support/StarHubTH/Backups/ModConfigs/`
   - `createBackup(gameDir:mods:)` avec gestion des groups
   - `restoreBackup(gameDir:backup:selectedItems:)` avec backup auto
   - `cleanupOldBackups()` automatique → retourne `Int` (nombre de backups supprimés)
   - Méthodes helpers pour la gestion des fichiers

### Étape 3: Localisation (3 fichiers)
3. Ajouter `enum ModConfigBackups` dans `StarHubTH/L10n.swift`
4. Ajouter traductions en anglais dans `assets/en.json`
5. Ajouter traductions en thaï dans `assets/th.json`
   - **Validation**: Respecter la parité des clés (constraint: localization_key_parity)

### Étape 4: Interface utilisateur (1 fichier)
6. Créer `StarHubTH/Views/ModConfigBackupsView.swift` avec:
   - Header avec bouton "Créer un backup" (désactivé si `!canCreateBackup`)
   - Liste des backups triés par date récente
   - Détail des fichiers par backup (avec affichage de `parentFolderName` si présent)
   - Interface de sélection pour restauration partielle
   - Alertes: confirmation restauration, confirmation suppression
   - Message de cleanup si des backups ont été supprimés automatiquement

### Étape 5: Intégration sidebar (1 fichier)
7. Modifier `StarHubTH/Views/MainView.swift`:
   - Ajouter `SidebarNavItem` dans section "Game Management"
   - Ajouter cas `currentTab == "ConfigBackups"` dans la zone de contenu
   - Ajouter titre dans `navigationTitleText`

### Étape 6: Tests manuels
- Suivre la checklist de validation ci-dessous

## Checklist de validation

### Fonctionnalités core
- [ ] Création de backup fonctionne avec mods activés
- [ ] Bouton désactivé quand gameDir vide (tooltip message)
- [ ] Bouton désactivé quand 0 mods activés (tooltip message)
- [ ] Mods groupés: `parentFolderName` correctement renseigné
- [ ] Fichiers copiés dans `~/Library/Application Support/StarHubTH/Backups/ModConfigs/`
- [ ] `metadata.json` créé et mis à jour

### Restauration
- [ ] Backup automatique créé avant restauration
- [ ] Alerte de confirmation affichée
- [ ] Fichiers restaurés aux bons emplacements (y compris sous-dossiers pour groups)
- [ ] Sélection partielle fonctionne (seuls les items sélectionnés restaurés)

### Cleanup automatique
- [ ] Déclenché après chaque création de backup
- [ ] Supprime les backups > 30 jours (garde min 5 versions)
- [ ] Message affiché si des backups supprimés
- [ ] Aucun message si aucun backup supprimé

### Interface
- [ ] Navigation vers onglet "Config Backups" fonctionne
- [ ] Liste de backups se met à jour après création
- [ ] Liste de backups se met à jour après suppression
- [ ] Taille et date des backups affichées correctement
- [ ] `parentFolderName` affiché dans le détail des fichiers (si présent)

### Cas limites
- [ ] Backup avec 0 fichiers trouvés (crée backup vide, pas d'erreur)
- [ ] Restauration avec backup source manquant (skip avec avertissement)
- [ ] Restauration avec dossier destination inexistant (crée dossier)
- [ ] Corruption du metadata.json (recréé depuis le système de fichiers)

### Localisation
- [ ] Toutes les clés présentes en anglais ET thaï
- [ ] Aucune clé manquante (parité respectée)
- [ ] Textes affichés correctement dans les deux langues

## Détails d'implémentation

### Fichiers à créer

#### 1. `StarHubTH/ModConfigBackup.swift` - Modèles de données
```swift
// Structure de backup individuel
struct ModConfigBackupItem: Identifiable, Codable {
    var id: UUID
    let modFolderName: String      // Nom du dossier du mod (ou sous-mod pour les groups)
    let parentFolderName: String?  // Si présent, ce fichier est dans un sous-dossier d'un mod groupé
    let modDisplayName: String
    let files: [String] // Noms de fichiers trouvés (config.json, fr.json)
    let fileSizes: [String: Int] // Pour information
}

// Structure de backup complet
struct ModConfigBackup: Identifiable, Codable, Equatable {
    var id: UUID
    let timestamp: Date
    let items: [ModConfigBackupItem]
    let totalFiles: Int
    let totalSize: Int
    
    var displayName: String {
        // Format: "Backup 20/07/2026 à 14:30 - 12 fichiers"
    }
    
    var formattedDate: String { ... }
    var formattedSize: String { ... }
}

// Index global des backups
struct ModConfigBackupsIndex: Codable {
    var backups: [ModConfigBackup]
    var lastAutoCleanup: Date?
}
```

#### 2. `StarHubTH/ModConfigBackupManager.swift` - Gestionnaire de backups
```swift
class ModConfigBackupManager {
    static let shared = ModConfigBackupManager()
    
    // Chemin du dossier de backups
    private let backupsBasePath: URL
    private let metadataPath: URL
    
    // Index en mémoire
    @Published private(set) var allBackups: [ModConfigBackup] = []
    
    // Méthodes principales
    func createBackup(gameDir: String, mods: [ModItem]) async throws -> ModConfigBackup
    func restoreBackup(gameDir: String, _ backup: ModConfigBackup, selectedItems: [ModConfigBackupItem]) async throws
    func deleteBackup(_ backup: ModConfigBackup) async throws
    func loadBackups() async throws
    func cleanupOldBackups() async throws -> Int // Retourne nombre de backups supprimés
    
    // Helpers
    private func findConfigFiles(in modPath: String, for mod: ModItem) -> [(filename: String, url: URL, parentFolder: String?)]
    private func createBackupDirectory(timestamp: Date) -> URL
    private func saveMetadata() async throws
    private func loadMetadata() async throws
}
```

#### 3. `StarHubTH/Views/ModConfigBackupsView.swift` - Interface principale
```swift
struct ModConfigBackupsView: View {
    @ObservedObject var viewModel: StarHubTHViewModel
    @StateObject private var backupManager = ModConfigBackupManager.shared
    
    @State private var selectedBackup: ModConfigBackup?
    @State private var selectedItems: Set<UUID> = []
    @State private var isCreatingBackup = false
    @State private var showingRestoreAlert = false
    @State private var showingDeleteAlert = false
    @State private var cleanupMessage: String? = nil
    
    private var canCreateBackup: Bool {
        !viewModel.gameDir.isEmpty && !viewModel.enabledMods.isEmpty
    }
    
    var body: some View {
        VStack {
            // Header avec bouton "Créer un backup"
            HStack {
                Text("Configurations Backups")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { createBackup() }) {
                    Label("Créer un backup", systemImage: "plus.circle.fill")
                }
                .disabled(!canCreateBackup)
                .tooltip(viewModel.gameDir.isEmpty 
                    ? "Sélectionnez d'abord un dossier de jeu" 
                    : "Aucun mod activé")
            }
            
            // Liste des backups existants (triés par date récente)
            // Détail du backup sélectionné (liste des mods/fichiers)
            // Boutons d'action: "Restaurer la sélection", "Supprimer le backup"
        }
        .onAppear { loadBackups() }
        .alert("Cleanup", isPresented: .constant(cleanupMessage != nil)) {
            Button("OK") { cleanupMessage = nil }
        } message: {
            Text(cleanupMessage ?? "")
        }
    }
    
    private func createBackup() {
        isCreatingBackup = true
        Task {
            do {
                let backup = try await backupManager.createBackup(
                    gameDir: viewModel.gameDir, 
                    mods: viewModel.enabledMods
                )
                
                // Cleanup automatique après création
                let deletedCount = try await backupManager.cleanupOldBackups()
                if deletedCount > 0 {
                    cleanupMessage = "\(deletedCount) vieux backups supprimés"
                }
                
                isCreatingBackup = false
            } catch {
                isCreatingBackup = false
                viewModel.alertMessage = "Erreur: \(error.localizedDescription)"
                viewModel.showAlert = true
            }
        }
    }
}
```

### Modifications aux fichiers existants

#### 4. `StarHubTH/Views/MainView.swift` - Intégration Sidebar
```swift
// Dans la section "Game Management" (vers ligne 166), après "Mods":
if matchesSearch(vm.L(L10n.ModConfigBackups.tabTitle)) {
    SidebarNavItem(
        icon: "archivebox.fill",
        iconColor: .green,
        label: vm.L(L10n.ModConfigBackups.tabTitle),
        tab: "ConfigBackups",
        currentTab: $currentTab
    )
}

// Puis dans la zone de contenu (detail:), ajouter le cas:
} else if currentTab == "ConfigBackups" {
    ModConfigBackupsView(vm: vm)

// Dans navigationTitleText, ajouter:
if currentTab == "ConfigBackups" { return vm.L(L10n.ModConfigBackups.title) }
```

#### 5. `StarHubTH/StarHubTHViewModel.swift`
```swift
// Ajouter une propriété pour passer les mods activés au backup manager:
var enabledMods: [ModItem] {
    mods.filter { $0.isEnabled }
}

// Aucune autre modification nécessaire au ViewModel
```

#### 6. `StarHubTH/L10n.swift` - Localisations
```swift
enum ModConfigBackups {
    static let title = "mod_config_backups_title"
    static let tabTitle = "mod_config_backups_tab_title"
    static let createBackup = "mod_config_backups_create"
    static let creatingBackup = "mod_config_backups_creating"
    static let backupCreated = "mod_config_backups_created"
    static let backupFailed = "mod_config_backups_failed"
    static let restoreBackup = "mod_config_backups_restore"
    static let restoringBackup = "mod_config_backups_restoring"
    static let backupRestored = "mod_config_backups_restored"
    static let deleteBackup = "mod_config_backups_delete"
    static let deleteConfirm = "mod_config_backups_delete_confirm"
    static let noBackups = "mod_config_backups_empty"
    static let selectFilesToRestore = "mod_config_backups_select_files"
    static let restoreWarning = "mod_config_backups_restore_warning"
    static let restoreWarningCreateBackup = "mod_config_backups_restore_create_backup"
    static let filesCount = "mod_config_backups_files_count"
    static let size = "mod_config_backups_size"
    static let createdDate = "mod_config_backups_created_date"
    static let noGameDir = "mod_config_backups_no_game_dir"
    static let noEnabledMods = "mod_config_backups_no_enabled_mods"
    static let diskFull = "mod_config_backups_disk_full"
    static let fileNotFound = "mod_config_backups_file_not_found"
    static let restoreFailed = "mod_config_backups_restore_failed"
    static let backupAutoCreated = "mod_config_backups_auto_created"
    static let cleanupComplete = "mod_config_backups_cleanup_complete"
}
```

#### 7. `assets/en.json` et `assets/th.json` - Traductions
```json
// En.json
{
  "mod_config_backups_title": "Configuration Backups",
  "mod_config_backups_tab_title": "Backups",
  "mod_config_backups_create": "Create Backup",
  "mod_config_backups_creating": "Creating backup...",
  "mod_config_backups_created": "Backup created successfully",
  "mod_config_backups_failed": "Failed to create backup",
  "mod_config_backups_restore": "Restore",
  "mod_config_backups_restoring": "Restoring...",
  "mod_config_backups_restored": "Backup restored successfully",
  "mod_config_backups_delete": "Delete",
  "mod_config_backups_delete_confirm": "Delete this backup?",
  "mod_config_backups_empty": "No backups yet",
  "mod_config_backups_select_files": "Select files to restore",
  "mod_config_backups_restore_warning": "This will overwrite existing config files. Continue?",
  "mod_config_backups_restore_create_backup": "A backup of current configs will be created first.",
  "mod_config_backups_files_count": "%d files",
  "mod_config_backups_size": "Size",
  "mod_config_backups_created_date": "Created",
  "mod_config_backups_no_game_dir": "Veuillez sélectionner un dossier de jeu d'abord",
  "mod_config_backups_no_enabled_mods": "Aucun mod activé à sauvegarder",
  "mod_config_backups_disk_full": "Espace disque insuffisant",
  "mod_config_backups_file_not_found": "Fichier introuvable: {filename}",
  "mod_config_backups_restore_failed": "Échec de la restauration: {error}",
  "mod_config_backups_auto_created": "Un backup automatique a été créé avant la restauration",
  "mod_config_backups_cleanup_complete": "{count} vieux backups supprimés (plus de 30 jours, minimum 5 versions conservées)"
}

// Th.json - Traductions thaïlandaises correspondantes
```

## Logique de backup détaillée

### Scan des fichiers avec gestion des groups
```swift
func findConfigFiles(in modPath: String, for mod: ModItem) -> [(filename: String, url: URL, parentFolder: String?)] {
    let fm = FileManager.default
    var foundFiles: [(filename: String, url: URL, parentFolder: String?)] = []
    
    // Fichiers cibles
    let targetFiles = ["config.json", "fr.json"]
    
    // Pour les mods groupés avec children, scanner chaque sous-mod
    if let children = mod.children {
        for child in children where child.isEnabled {
            let childPath = (modPath as NSString).appendingPathComponent(child.folderName)
            
            if let enumerator = fm.enumerator(at: URL(fileURLWithPath: childPath), ...) {
                for case let fileURL as URL in enumerator {
                    let filename = fileURL.lastPathComponent
                    if targetFiles.contains(filename) {
                        foundFiles.append((filename, fileURL, mod.folderName))
                    }
                }
            }
        }
    } else {
        // Mod standard
        if let enumerator = fm.enumerator(at: URL(fileURLWithPath: modPath), ...) {
            for case let fileURL as URL in enumerator {
                let filename = fileURL.lastPathComponent
                if targetFiles.contains(filename) {
                    foundFiles.append((filename, fileURL, nil))
                }
            }
        }
    }
    
    return foundFiles
}
```

### Logique de restauration
```swift
func restoreBackup(gameDir: String, _ backup: ModConfigBackup, selectedItems: [ModConfigBackupItem]) async throws {
    // 1. Créer un backup automatique de l'état actuel
    _ = try await createBackup(gameDir: gameDir, mods: viewModel.enabledMods)
    
    // 2. Avertir l'utilisateur (alerte UI)
    // Fait dans la Vue via Alert
    
    // 3. Restaurer les fichiers sélectionnés
    let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
    
    for item in selectedItems {
        let backupDir = getBackupDirectory(for: backup)
        let sourceBase = backupDir.appendingPathComponent(item.modFolderName)
        
        // Construire le chemin cible en tenant compte de parentFolderName
        let targetBase: URL
        if let parent = item.parentFolderName {
            targetBase = URL(fileURLWithPath: modsPath)
                .appendingPathComponent(parent)
                .appendingPathComponent(item.modFolderName)
        } else {
            targetBase = URL(fileURLWithPath: modsPath)
                .appendingPathComponent(item.modFolderName)
        }
        
        for filename in item.files {
            let source = sourceBase.appendingPathComponent(filename)
            let target = targetBase.appendingPathComponent(filename)
            
            // S'assurer que le dossier parent existe
            try fm.createDirectory(atPath: target.deletingLastPathComponent().path, ...)
            
            // Copier le fichier
            try fm.copyItem(at: source, to: target)
        }
    }
}
```

### Logique de cleanup
```swift
func cleanupOldBackups() async throws -> Int {
    let now = Date()
    let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 60 * 60)
    
    var deletedCount = 0
    
    // Si on a plus de 5 backups, supprimer ceux de plus de 30 jours
    if allBackups.count > 5 {
        let toDelete = allBackups.filter { $0.timestamp < thirtyDaysAgo }
        
        for backup in toDelete {
            try await deleteBackup(backup)
            deletedCount += 1
        }
    }
    
    // Sinon, garder tous les backups même si > 30 jours
    return deletedCount
}
```

## Gestion des erreurs

### Scénarios d'erreur à gérer
1. **Pas de mods activés**: Bouton désactivé avec tooltip informatif, pas d'erreur
2. **gameDir vide**: Bouton désactivé avec message "Sélectionnez d'abord un dossier de jeu"
3. **Dossier de mods inaccessible**: Capturer l'erreur FileManager et afficher dans l'UI via `vm.showAlert`
4. **Espace disque insuffisant**: Vérifier avant copie, avertir si problème
5. **Fichier source introuvable lors restauration**: Skip le fichier, logger l'avertissement, continuer avec autres fichiers
6. **Fichier destination verrouillé**: Retry avec timeout, puis échec
7. **Structure de mods invalides (group moved)**: Vérifier que le dossier parent existe, skip avec avertissement si absent

## Risques et atténuations

### Risque 1: Corruption du dossier de backups
- **Atténuation**: Vérifier l'intégrité du `metadata.json` au chargement, recréer depuis le système de fichiers si corrompu

### Risque 2: fichiers modifiés pendant le backup
- **Atténuation**: Copier les fichiers avec FileManager atomic write, vérifier les tailles après copie

### Risque 3: Chemins de mods invalides (dossier déplacé/renommé)
- **Atténuation**: Lors de la restauration, vérifier que le dossier de mod existe, skip avec avertissement si absent

### Risque 4: Conflit de noms de fichiers (cas rare)
- **Atténuation**: Chaque backup utilise un timestamp unique, pas de conflit possible

### Risque 5: Structure de mods groupés modifiée entre backup et restauration
- **Atténuation**: Vérifier la cohérence des chemins lors de la restauration, logger les incohérences sans échouer complètement

## Rollout et migration

### Pas de migration nécessaire
- Fonctionnalité entièrement nouvelle, aucun code existant modifié
- Les backups seront créés à la demande
- Pas de données existantes à migrer

### Déploiement
1. Build standard avec `python3 build_app.py`
2. Au premier lancement, le dossier `~/Library/Application Support/StarHubTH/Backups/ModConfigs/` sera créé automatiquement
3. Aucune action manuelle requise de l'utilisateur

## Améliorations futures (hors scope)

- Backup automatique avant activation/désactivation de mods
- Export/import de backups entre machines
- Compression des backups (zip)
- Interface de comparaison entre backups
- Restauration sélective au niveau fichier (pas juste au niveau mod)
- Intégration avec les profils de mods
- Logging des opérations de backup/restauration
