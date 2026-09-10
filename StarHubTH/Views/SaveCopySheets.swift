import SwiftUI

struct DuplicateSaveSheet: View {
    @ObservedObject var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let save: SaveGameInfo
    @Environment(\.dismiss) var dismiss
    
    @State private var newName: String
    @State private var newFarm: String
    
    init(vm: StarHubTHViewModel, localization: LocalizationStore, save: SaveGameInfo) {
        self.localization = localization
        self.vm = vm
        self.save = save
        _newName = State(initialValue: "\(save.playerName) \(localization.L(L10n.Saves.duplicateDefaultSuffix))")
        _newFarm = State(initialValue: save.farmName)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(localization.L(L10n.Saves.duplicateTitle))
                .font(AppDesign.Font.headline)
            
            Form {
                TextField(localization.L(L10n.Saves.newCharacterName), text: $newName)
                TextField(localization.L(L10n.Saves.newFarmName), text: $newFarm)
            }
            .formStyle(.grouped)
            
            HStack(spacing: 12) {
                Spacer()
                Button(localization.L(L10n.Saves.cancel)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                // `Task` non structurée, lancée depuis l'action du bouton : la
                // copie doit survivre à la fermeture de la feuille. Un `.task`
                // de vue serait annulé à sa disparition, laissant un dossier
                // de sauvegarde copié à moitié. La feuille ne se ferme que
                // sur un succès (audit 2026-08-05) : sur échec, le modal
                // d'erreur s'affiche et l'utilisateur peut réessayer.
                Button(localization.L(L10n.Saves.duplicate)) {
                    Task {
                        if await vm.duplicateSave(info: save, newName: newName, newFarm: newFarm) {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(vm.isSaveOperationRunning)
            }
        }
        .padding()
        .frame(width: 350, height: 220)
    }
}

struct BranchBackupSheet: View {
    @ObservedObject var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let backup: SaveBackup
    @Environment(\.dismiss) var dismiss
    
    @State private var newName: String
    @State private var newFarm: String
    
    init(vm: StarHubTHViewModel, localization: LocalizationStore, backup: SaveBackup) {
        self.localization = localization
        self.vm = vm
        self.backup = backup
        // Try parsing the original save name from backup folder name
        // Try parsing the original save name from backup folder name.
        // `.first` (pas `[0]`) : un `lastPathComponent` vide ou sans point
        // donnait un tableau vide → crash à l'ouverture de la feuille.
        let originalSaveName = backup.folderPath.lastPathComponent
            .split(separator: ".").first.map(String.init) ?? backup.folderPath.lastPathComponent
        _newName = State(initialValue: "\(originalSaveName) \(localization.L(L10n.Saves.branchDefaultSuffix))")
        
        // We don't easily have the farmName from SaveBackup directly unless we parse the XML of the backup.
        // Let's parse it! We can try reading the SaveGameInfo inside backup folder to pre-fill farm name.
        let saveGameInfoURL = backup.folderPath.appendingPathComponent("SaveGameInfo")
        var initialFarmName = localization.L(L10n.Saves.branchDefaultFarm)
        if let content = try? String(contentsOf: saveGameInfoURL, encoding: .utf8) {
            let pattern = "(<farmName>)([^<]+)(</farmName>)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..<content.endIndex, in: content)),
               let swiftRange = Range(match.range(at: 2), in: content) {
                initialFarmName = String(content[swiftRange])
            }
        }
        _newFarm = State(initialValue: initialFarmName)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(localization.L(L10n.Saves.branchTitle))
                .font(AppDesign.Font.headline)
            
            Form {
                TextField(localization.L(L10n.Saves.newCharacterName), text: $newName)
                TextField(localization.L(L10n.Saves.newFarmName), text: $newFarm)
            }
            .formStyle(.grouped)
            
            HStack(spacing: 12) {
                Spacer()
                Button(localization.L(L10n.Saves.cancel)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                // Même raison qu'au-dessus : la `Task` doit survivre à la
                // fermeture de la feuille, donc non structurée. Fermeture sur
                // succès seul — un échec laisse réessayer sous le modal.
                Button(localization.L(L10n.Saves.branch)) {
                    Task {
                        if await vm.branchFromBackup(backup: backup, newName: newName, newFarm: newFarm) {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(vm.isSaveOperationRunning)
            }
        }
        .padding()
        .frame(width: 350, height: 220)
    }
}
