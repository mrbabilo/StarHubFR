import SwiftUI

extension UpdatesView {
    /// En-tête commun des pages (audit UX 2026-10-02). Le compte vient de
    /// `UpdateCount.pending`, la fonction du badge de la barre latérale et de
    /// la tuile de l'accueil : trois endroits, un seul chiffre.
    var pageHeader: some View {
        let pending = UpdateCount.pending(outOfDate: vm.outOfDateMods,
                                          nexusCount: vm.nexusUpdates.count) {
            vm.resolveModFolder(forLoggedName: $0)?.version
        }
        return PageHeader(icon: "arrow.triangle.2.circlepath",
                          title: localization.L(L10n.Main.modUpdates),
                          subtitle: pending > 0
                              ? String(format: localization.L(L10n.Updates.headerPending), Int64(pending))
                              : localization.L(L10n.Updates.headerUpToDate),
                          // Pas de vert à zéro : un 0 vaut aussi pour une
                          // vérification Nexus jamais lancée — « à jour » mentirait.
                          tint: pending > 0 ? AppDesign.Color.info : AppDesign.Color.accent)
            .padding(.horizontal, AppDesign.Spacing.xl)
            .padding(.vertical, AppDesign.Spacing.md)
    }
}
