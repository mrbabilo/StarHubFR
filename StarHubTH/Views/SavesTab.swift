import SwiftUI

/// L'onglet « Sauvegardes du jeu » : la liste des parties, ou la page de l'une
/// d'elles (R6). Sorti de `MainView`, verrouillé par le cliquet de taille, avec
/// le canal de la palette qu'il consomme.
///
/// N-08 — ↩ sur une partie dans la palette pose `pendingSaveFocus`. Depuis un
/// autre onglet, `MainView.handleTabChange` la consomme **après** sa remise à
/// zéro (poser la partie avant serait effacé). Ici, l'onglet déjà affiché,
/// aucun changement d'onglet n'a lieu : la demande se consomme à sa pose.
/// Pas d'`onAppear` : à l'arrivée, il passerait avant la remise à zéro.
struct SavesTab: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var currentTab: SidebarDestination

    var body: some View {
        let navigation = viewModel.navigationStore
        Group {
            if let save = navigation.editingSave {
                SaveDetailView(viewModel: viewModel, localization: localization, save: save,
                               currentTab: $currentTab)
                    // Une autre partie ouverte depuis la palette : l'éditeur
                    // repart de ses champs, pas de ceux de la précédente.
                    .id(save.folderName)
            } else {
                SavesView(vm: viewModel, localization: localization)
            }
        }
        .onChange(of: navigation.pendingSaveFocus) { _, _ in
            navigation.consumeSaveFocus(in: viewModel.saves)
        }
    }
}
