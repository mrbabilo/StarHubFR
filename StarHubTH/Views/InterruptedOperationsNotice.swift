import SwiftUI

/// R5 (audit UX 2026-10-16) — l'encart de l'Accueil : chaque opération qui a
/// laissé des mods déplacés sans les remettre (`ModSetOperations`), avec sa
/// remise. Avant, seule la recherche du mod responsable s'y signalait ; un
/// benchmark ou une mesure pilotée interrompus ne se voyaient qu'en
/// Performances, que rien n'invite à ouvrir au lancement.
///
/// L'Accueil est l'écran d'arrivée : c'est là que ça doit se voir. Les cartes
/// du Diagnostic et de Performances restent.
struct InterruptedOperationsNotice: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// Observée ici : la bissection publie en `ObservableObject`.
    @ObservedObject var bisection: BisectionRunner

    var body: some View {
        let awaiting = viewModel.modSetOperations.awaitingRestore
        if !awaiting.isEmpty {
            StandardSection(title: localization.L(L10n.Interrupted.title),
                            icon: ("exclamationmark.triangle.fill", AppDesign.Color.warning)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(localization.L(L10n.Interrupted.body))
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(awaiting, id: \.self) { operation in
                        SplitRow {
                            Text(label(operation)).font(AppDesign.Font.body)
                        } trailing: {
                            Button(localization.L(L10n.Bisect.restore)) { restore(operation) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(isRestoring(operation))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
        }
    }

    /// La recherche dit quand elle a commencé : l'instantané le sait.
    private func label(_ operation: ModSetOperations.Operation) -> String {
        let name = localization.name(of: operation)
        guard operation == .bisection, let started = bisection.interruptedSnapshot?.startedAt else { return name }
        return name + " · " + started.formatted(date: .abbreviated, time: .shortened)
    }

    /// Chaque opération garde sa propre remise, celle de sa carte.
    private func restore(_ operation: ModSetOperations.Operation) {
        switch operation {
        case .bisection: bisection.restoreAndStop()
        case .benchmark: viewModel.benchmark.restoreInterrupted()
        case .pilot:
            let pilot = viewModel.pilot
            Task { await pilot.restoreOrRollback() }
        }
    }

    private func isRestoring(_ operation: ModSetOperations.Operation) -> Bool {
        switch operation {
        case .bisection: return bisection.isApplying
        case .benchmark: return viewModel.benchmark.isActive
        case .pilot: return viewModel.pilot.isActive
        }
    }
}
