import SwiftUI

/// D4-T4 §3a — l'onglet « Santé » de « Diagnostic & Performances » : la carte
/// Santé SMAPI en pleine hauteur, puis la recherche guidée du mod responsable.
/// Autrefois empilées au-dessus du journal, dont elles partageaient la hauteur.
struct DiagnosticsHealthView: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State private var scrollRequest: ScrollRequest?

    private struct ScrollRequest: Equatable {
        let anchor: String
        let id = UUID()
    }

    private static let padding: CGFloat = 12
    private static let bisectionAnchor = "bisection"

    var body: some View {
        // Un seul ascenseur pour tout l'onglet : la Santé et la bissection
        // restent dans le même parcours, y compris quand leurs listes grandissent.
        BackToTopScrollView(localization) { ScrollViewReader { proxy in
            VStack(spacing: 0) {
                alertsLink
                if let diag = viewModel.smapiDiagnostics, !diag.isEmpty {
                    SmapiHealthCard(vm: viewModel, localization: localization,
                                    showBlock: requestScroll,
                                    showBisection: { requestScroll(Self.bisectionAnchor) })
                        .padding(Self.padding)
                } else {
                    StateCard(icon: "stethoscope", text: localization.L(L10n.Logs.healthEmpty),
                              actionTitle: nil) {}
                        .padding(AppDesignCore.Spacing.lg)
                }
                if let last = viewModel.modImpactStore.lastInGame {
                    Divider()
                    SplitRow {
                        Text(String(format: localization.L(L10n.Performance.healthLastMeasure),
                                    last.formatted(date: .abbreviated, time: .shortened)))
                            .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                    } trailing: {
                        Button(localization.L(L10n.Performance.healthOpen)) {
                            viewModel.navigationStore.openPerformance()
                        }.buttonStyle(.link).clickableCursor().focusRing(cornerRadius: 4).font(AppDesign.Font.footnote)
                    }
                    .padding(.horizontal, Self.padding).padding(.vertical, AppDesign.Spacing.sm)
                }
                Divider()
                BisectionCard(vm: viewModel, localization: localization)
                    .padding(Self.padding).id(Self.bisectionAnchor)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .task(id: scrollRequest?.id) {
                guard let request = scrollRequest else { return }
                // L'ouverture de la carte et la création de son ancre doivent
                // précéder le saut demandé par son compteur.
                await Task.yield()
                withAnimation { proxy.scrollTo(request.anchor, anchor: .top) }
            }
        } }
        .background(AppDesign.Color.windowBg)
    }

    private func requestScroll(_ anchor: String) {
        scrollRequest = ScrollRequest(anchor: anchor)
    }

    /// R2 — l'aller vers les Alertes, même compte que la pastille. Hors de la
    /// carte, qui exige un journal lu : les collisions de raccourcis n'en
    /// ont pas besoin pour exister.
    @ViewBuilder
    private var alertsLink: some View {
        let count = viewModel.systemAlertCount
        if count > 0 {
            SplitRow {
                Text(localization.plural(L10n.Health.openAlerts, count))
                    .font(AppDesign.Font.footnote(.medium)).foregroundColor(AppDesign.Color.warning)
            } trailing: {
                Button(localization.L(L10n.Health.openAlertsAction)) {
                    // Le segment d'abord : il survit au changement d'onglet.
                    viewModel.navigationStore.alertsSegment = .alerts
                    viewModel.navigationStore.requestTab(.systemAlerts)
                }.buttonStyle(.link).clickableCursor().focusRing(cornerRadius: 4).font(AppDesign.Font.footnote)
            }
            .padding(.horizontal, Self.padding).padding(.vertical, AppDesign.Spacing.sm)
            Divider()
        }
    }
}
