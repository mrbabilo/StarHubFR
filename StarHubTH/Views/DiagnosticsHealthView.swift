import SwiftUI

/// D4-T4 §3a — l'onglet « Santé » de « Diagnostic & Performances » : la carte
/// Santé SMAPI en pleine hauteur, puis la recherche guidée du mod responsable.
/// Autrefois empilées au-dessus du journal, dont elles partageaient la hauteur.
struct DiagnosticsHealthView: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    /// Hauteur de l'onglet, mesurée : la carte s'y dimensionne (voir
    /// `SmapiHealthCard.availableHeight`).
    @State private var viewHeight: CGFloat = 600
    /// Hauteur réellement occupée par la bissection, qui passe d'un bouton à un
    /// écran d'étape déplié : retranchée du budget de la carte.
    @State private var bisectionHeight: CGFloat = 0

    private static let padding: CGFloat = 12

    var body: some View {
        // Dans un `ScrollView` : la bissection dépliée (liste des mods) peut
        // dépasser la fenêtre ; la carte, elle, borne son propre corps.
        ScrollView {
            VStack(spacing: 0) {
                if let diag = viewModel.smapiDiagnostics, !diag.isEmpty {
                    SmapiHealthCard(vm: viewModel, localization: localization,
                                    availableHeight: max(240, viewHeight - bisectionHeight - 4 * Self.padding))
                        .padding(Self.padding)
                } else {
                    StateCard(icon: "stethoscope", text: localization.L(L10n.Logs.healthEmpty),
                              actionTitle: nil) {}
                        .padding(AppDesignCore.Spacing.lg)
                }
                Divider()
                BisectionCard(vm: viewModel, localization: localization)
                    .padding(Self.padding)
                    .background(GeometryReader { proxy in
                        Color.clear.onAppear { bisectionHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, h in bisectionHeight = h }
                    })
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppDesign.Color.windowBg)
        // Mesurée hors du `ScrollView`, qui offrirait sinon une hauteur infinie.
        .background(GeometryReader { proxy in
            Color.clear.onAppear { viewHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { _, h in viewHeight = h }
        })
    }
}
