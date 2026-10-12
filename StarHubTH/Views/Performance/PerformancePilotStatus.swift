import SwiftUI

/// P1 — la ligne d'état de la mesure pilotée, sous l'état de la sonde :
/// étape et minutes gardées pendant la série, message nommé à l'échec,
/// retour arrière proposé quand le parc a pu changer (spec §8). Aucun
/// panneau flottant : l'utilisateur n'a rien à surveiller.
struct PerformancePilotStatus: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    @State private var message: String?

    var body: some View {
        let pilot = viewModel.pilot
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            switch pilot.state.phase {
            case .idle:
                EmptyView()
            case .running(let step):
                SplitRow {
                    Text(String(format: localization.L(L10n.PerformancePilot.status),
                                localization.L(step == .before ? L10n.PerformancePilot.stepBefore
                                                               : L10n.PerformancePilot.stepAfter),
                                store.guidedMinuteCount))
                        .font(AppDesign.Font.footnote)
                } trailing: {
                    Button(localization.L(L10n.PerformancePilot.stop)) { pilot.stop() }
                        .help(localization.L(L10n.PerformancePilot.stopHelp))
                        .clickableCursor()
                }
            case .applying:
                Text(localization.L(L10n.PerformancePilot.applying)).font(AppDesign.Font.footnote)
            case .reporting:
                decision(localization.L(L10n.PerformancePilot.ready), pilot: pilot)
            case .failed(let failure):
                decision(localization.L(Self.failureKey(failure)), pilot: pilot)
            case .interrupted:
                decision(localization.L(L10n.PerformancePilot.interrupted), pilot: pilot)
            }
            if let message { PerformanceFormatting.note(message) }
        }
    }

    /// Fin de série : retour arrière si le parc a pu changer, sinon fermer.
    private func decision(_ text: String, pilot: GuidedPilotRunner) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(AppDesign.Font.footnote).fixedSize(horizontal: false, vertical: true)
            WrapHStack(spacing: AppDesign.Spacing.sm) {
                if pilot.canRollback {
                    Button(localization.L(L10n.PerformancePilot.rollback)) {
                        Task {
                            await pilot.restoreOrRollback()
                            message = pilot.state.phase == .idle
                                ? nil : localization.L(L10n.PerformancePilot.rollbackFailed)
                        }
                    }
                    .help(localization.L(L10n.PerformancePilot.rollbackHelp))
                    .clickableCursor()
                    .disabled(viewModel.isGameRunning())
                }
                Button(localization.L(L10n.PerformancePilot.dismiss)) {
                    pilot.dismiss()
                    message = nil
                }
                .clickableCursor()
            }
        }
    }

    private static func failureKey(_ failure: GuidedPilotPlan.Failure) -> String {
        switch failure {
        case .noMeasurement: return L10n.PerformancePilot.failedNoMeasurement
        case .stalled: return L10n.PerformancePilot.failedStalled
        case .applyFailed: return L10n.PerformancePilot.failedApplyFailed
        case .revertFailed: return L10n.PerformancePilot.failedRevertFailed
        case .gameQuit: return L10n.PerformancePilot.failedGameQuit
        case .stopped: return L10n.PerformancePilot.failedStopped
        }
    }
}
