import SwiftUI

/// N-09 S7/S8 (audit UX 2026-10-16) — « Voir la fiche » d'une ligne qui
/// oppose des mods : conflit d'Alertes, conflit Content Patcher,
/// recouvrement de performance. Avant, la ligne ne menait nulle part, ou à
/// un seul des deux. Plusieurs mods : un menu nommé par mod, plutôt que des
/// boutons « Voir la fiche » indiscernables ; un seul : le bouton.
struct ModPairDetailMenu: View {
    /// Des `folderName` : ce qu'attend `openModDetail`.
    let folders: [String]
    let name: (String) -> String
    let navigation: NavigationStore
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        if folders.count == 1, let folder = folders.first {
            Button(localization.L(L10n.Health.actionOpenMod)) { open(folder) }
                .buttonStyle(.borderless).focusRing(cornerRadius: 4)
                .font(AppDesign.Font.footnote)
                .pointingHandCursor()
        } else if !folders.isEmpty {
            Menu(localization.L(L10n.Health.actionOpenMod)) {
                ForEach(folders, id: \.self) { folder in
                    Button(name(folder)) { open(folder) }
                }
            }
            .menuStyle(.borderlessButton).focusRing(cornerRadius: 4)
            .fixedSize().controlSize(.small)
        }
    }

    private func open(_ folder: String) {
        navigation.openModDetail(folderName: folder, door: .alert(dependency: false))
    }
}
