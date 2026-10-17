import SwiftUI

/// Ouvre la feuille d'installation de la liste quand le menu Fichier la
/// demande (⌘O, N-07) — à l'apparition de la liste comme pendant qu'elle est
/// affichée : la demande précède souvent la vue (changement d'onglet).
struct InstallRequestConsumer: ViewModifier {
    var navigation: NavigationStore

    func body(content: Content) -> some View {
        content
            .onAppear(perform: consume)
            .onChange(of: navigation.pendingInstallRequest) { _, _ in consume() }
            // Le drapeau vit dans le store (P5-5a) : la liste démontée par un
            // changement d'onglet ne doit pas laisser la fenêtre refuser les dépôts.
            .onDisappear { navigation.showsInstallSheet = false }
    }

    private func consume() {
        guard navigation.pendingInstallRequest else { return }
        navigation.consumeInstallRequest()
        navigation.showsInstallSheet = true
    }
}
