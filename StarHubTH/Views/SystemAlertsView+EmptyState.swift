import SwiftUI

/// L'état vide et le bouton « Revérifier » des Alertes système, sortis du
/// fichier de la vue (plafond de taille) quand un conflit a gagné son menu
/// de fiches (N-09 S7).
extension SystemAlertsView {
    /// État vide : bouclier vert qui s'installe, message rassurant, et ce qui
    /// a été vérifié. Le journal date de la dernière partie — pas de bouton
    /// dédié ici, le « Revérifier » de l'en-tête couvre déjà ce cas.
    var emptyState: some View {
        VStack(spacing: AppDesign.Spacing.md) {
            Spacer()
            AllClearGlyph()
            Text(localization.L(L10n.Updates.noAlerts))
                .font(AppDesign.Font.headline(.semibold))
            Text(localization.L(L10n.Health.allClearHint))
                .font(AppDesign.Font.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
        }
        .padding(AppDesign.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Relit le journal SMAPI sans rescaner le parc — la page ne montre que
    /// ce que dit le journal, c'est lui seul qu'il faut relire.
    @ViewBuilder
    var recheckLogButton: some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Button(action: { viewModel.refreshSmapiLog() }) {
                Label(localization.L(L10n.Updates.recheckLog), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered).focusRing(cornerRadius: 5)
            .controlSize(.small)
            .pointingHandCursor()
            .disabled(viewModel.isRefreshingSmapiLog)
            if viewModel.isRefreshingSmapiLog {
                ProgressView().controlSize(.small)
            }
        }
    }
}
