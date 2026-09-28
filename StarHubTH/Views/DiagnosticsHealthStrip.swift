import SwiftUI

/// D4-T4 §3a — en tête du Journal, ce que la carte Santé disait au-dessus des
/// lignes quand elles partageaient la page : l'état SMAPI d'un coup d'œil, la
/// recherche guidée en cours, et le chemin vers l'onglet Santé.
struct DiagnosticsHealthStrip: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    // Observé séparément, comme dans `HomeView` : `BisectionRunner` publie
    // son propre état.
    @ObservedObject private var bisection: BisectionRunner

    init(viewModel: StarHubTHViewModel, localization: LocalizationStore) {
        self.viewModel = viewModel
        self.localization = localization
        self.bisection = viewModel.bisection
    }

    private var status: (icon: String, color: Color, text: String) {
        guard let diag = viewModel.smapiDiagnostics, !diag.isEmpty else {
            return ("questionmark.circle", .secondary, localization.L(L10n.Logs.stripNoLog))
        }
        if diag.problemCount == 0 {
            return ("checkmark.circle.fill", AppDesign.Color.success, localization.L(L10n.Logs.stripHealthy))
        }
        return ("exclamationmark.triangle.fill", AppDesign.Color.warning,
                String(format: localization.L(L10n.Logs.stripProblems), diag.problemCount))
    }

    var body: some View {
        let status = status
        HStack(spacing: AppDesign.Spacing.sm) {
            Image(systemName: status.icon).foregroundColor(status.color)
            Text(status.text).font(AppDesign.Font.footnote(.medium))
            if bisection.state != nil {
                Label(localization.L(L10n.Logs.stripBisection), systemImage: "magnifyingglass")
                    .font(AppDesign.Font.footnote)
            }
            Spacer(minLength: AppDesign.Spacing.sm)
            Button(localization.L(L10n.Logs.stripOpenHealth)) {
                viewModel.navigationStore.diagnosticsSegment = .health
            }
            .font(AppDesign.Font.footnote)
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
