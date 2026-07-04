import SwiftUI

struct DuplicateSaveSheet: View {
    @ObservedObject var vm: StarHubTHViewModel
    let save: SaveGameInfo
    @Environment(\.dismiss) var dismiss
    
    @State private var newName: String
    @State private var newFarm: String
    
    init(vm: StarHubTHViewModel, save: SaveGameInfo) {
        self.vm = vm
        self.save = save
        _newName = State(initialValue: "\(save.playerName) \(vm.L(L10n.Saves.duplicateDefaultSuffix))")
        _newFarm = State(initialValue: save.farmName)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(vm.L(L10n.Saves.duplicateTitle))
                .font(.headline)
            
            Form {
                TextField(vm.L(L10n.Saves.newCharacterName), text: $newName)
                TextField(vm.L(L10n.Saves.newFarmName), text: $newFarm)
            }
            .formStyle(.grouped)
            
            HStack(spacing: 12) {
                Spacer()
                Button(vm.L(L10n.Saves.cancel)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button(vm.L(L10n.Saves.duplicate)) {
                    vm.duplicateSave(info: save, newName: newName, newFarm: newFarm)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 350, height: 220)
    }
}

struct BranchBackupSheet: View {
    @ObservedObject var vm: StarHubTHViewModel
    let backup: SaveBackup
    @Environment(\.dismiss) var dismiss
    
    @State private var newName: String
    @State private var newFarm: String
    
    init(vm: StarHubTHViewModel, backup: SaveBackup) {
        self.vm = vm
        self.backup = backup
        // Try parsing the original save name from backup folder name
        let originalSaveName = String(backup.folderPath.lastPathComponent.split(separator: ".")[0])
        _newName = State(initialValue: "\(originalSaveName) \(vm.L(L10n.Saves.branchDefaultSuffix))")
        
        // We don't easily have the farmName from SaveBackup directly unless we parse the XML of the backup.
        // Let's parse it! We can try reading the SaveGameInfo inside backup folder to pre-fill farm name.
        let saveGameInfoURL = backup.folderPath.appendingPathComponent("SaveGameInfo")
        var initialFarmName = vm.L(L10n.Saves.branchDefaultFarm)
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
            Text(vm.L(L10n.Saves.branchTitle))
                .font(.headline)
            
            Form {
                TextField(vm.L(L10n.Saves.newCharacterName), text: $newName)
                TextField(vm.L(L10n.Saves.newFarmName), text: $newFarm)
            }
            .formStyle(.grouped)
            
            HStack(spacing: 12) {
                Spacer()
                Button(vm.L(L10n.Saves.cancel)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button(vm.L(L10n.Saves.branch)) {
                    _ = vm.branchFromBackup(backup: backup, newName: newName, newFarm: newFarm)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 350, height: 220)
    }
}
