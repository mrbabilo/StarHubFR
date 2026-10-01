import SwiftUI

/// La feuille « Signaler un conflit » : sélecteur du mod visé (les autres
/// mods du parc, triés) et note libre. La cible revient vide à chaque
/// ouverture (patron des brouillons) — `MainView` remet aussi les deux
/// brouillons à l'ouverture du geste.
struct ReportConflictSheet: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let modFolderName: String
    @Binding var target: String?
    @Binding var note: String
    let close: () -> Void

    private var candidates: [ModItem] {
        vm.scanStore.mods.flattenedMods
            .filter { $0.folderName != modFolderName }
            .alphabeticalListOrder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(localization.L(L10n.Conflicts.reportButton))
                .font(.system(size: AppDesign.Font.scaled(15), weight: .bold))
            Picker(localization.L(L10n.Conflicts.pickMod), selection: $target) {
                Text("").tag(String?.none)
                ForEach(candidates, id: \.folderName) { candidate in
                    Text(candidate.name).tag(String?.some(candidate.folderName))
                }
            }
            TextField(localization.L(L10n.Conflicts.notePlaceholder), text: $note)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(localization.L(L10n.Saves.cancel)) { close() }
                Button(localization.L(L10n.Conflicts.reportConfirm)) {
                    if let targetFolder = target {
                        vm.declareConflict(ModConflictPair(modFolderName, targetFolder), note: note)
                    }
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(target == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
