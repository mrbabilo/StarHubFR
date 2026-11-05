import SwiftUI

/// La feuille d'installation et la demande du menu Fichier ou de la palette
/// (⌘O, N-07). Posée sur `MainView`, pas sur la liste : celle-ci n'est pas
/// montée sous une fiche ou l'éditeur de config, où ⌘O restait sans effet et
/// où la feuille surgissait à la fermeture de la fiche (X155).
struct InstallRequestConsumer: ViewModifier {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var currentTab: SidebarDestination
    /// Faux si une autre feuille occupe la fenêtre : deux `.sheet` simultanés
    /// et l'un se perd. La demande tombe alors, comme ⌘K.
    let canPresent: Bool

    private var navigation: NavigationStore { viewModel.navigationStore }

    func body(content: Content) -> some View {
        content
            .onChange(of: navigation.pendingInstallRequest) { _, _ in consume() }
            .sheet(isPresented: Bindable(navigation).showsInstallSheet) {
                ModInstallView(vm: viewModel, localization: localization, currentTab: $currentTab,
                               isPresented: Bindable(navigation).showsInstallSheet)
            }
    }

    private func consume() {
        guard navigation.pendingInstallRequest else { return }
        navigation.consumeInstallRequest()
        if canPresent { navigation.showsInstallSheet = true }
    }
}
