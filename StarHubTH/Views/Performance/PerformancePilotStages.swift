import SwiftUI

/// Les étapes du côté piloté en cours, cochées au fil de l'eau, avec le temps
/// écoulé : un parc de ~900 mods met des minutes à charger, et sans elles
/// l'utilisateur croit que rien ne se passe (retour du 2026-10-13). Une fois la
/// mesure commencée, les jalons s'effacent ; « jeu derrière » est dit par
/// `PerformanceLiveIndicator` dans la même ligne d'état.
struct PerformancePilotStages: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    let launchedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .distantPast, by: 1)) { context in
            let stage = launchedAt.map {
                GuidedPilotProgress.stage(launchedAt: $0, gameRunning: viewModel.isGameRunning(), loads: store.loads)
            } ?? .launching
            VStack(alignment: .leading, spacing: 2) {
                if stage < .measuring {
                    ForEach(GuidedPilotProgress.Stage.allCases, id: \.self) { row($0, current: stage) }
                    if let launchedAt {
                        Text(String(format: localization.L(L10n.PerformancePilot.elapsed),
                                    Self.duration(context.date.timeIntervalSince(launchedAt))))
                            .font(AppDesign.Font.footnote).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }

    private func row(_ stage: GuidedPilotProgress.Stage, current: GuidedPilotProgress.Stage) -> some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Group {
                if stage < current {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppDesign.Color.success)
                } else if stage == current {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "circle").foregroundStyle(.secondary)
                }
            }
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
            Text(localization.L(Self.key(stage)))
                .font(AppDesign.Font.footnote)
                .foregroundStyle(stage > current ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private static func key(_ stage: GuidedPilotProgress.Stage) -> String {
        switch stage {
        case .launching: return L10n.PerformancePilot.stageLaunching
        case .loadingMods: return L10n.PerformancePilot.stageLoadingMods
        case .loadingSave: return L10n.PerformancePilot.stageLoadingSave
        case .measuring: return L10n.PerformancePilot.stageMeasuring
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
