import SwiftUI

/// P1 — la fin d'une série pilotée, dans la ligne d'état même : le verdict
/// A/B, les trois chiffres qui le portent, l'état du parc et la décision
/// (retour d'écran du 2026-10-13 : « Rapport prêt » seul, deux boutons muets
/// sur le parc laissé côté B). Le rapport est celui de la paire jouée,
/// désignée par ses plans — jamais la sélection du moment.
struct PerformancePilotReport: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    var pilot: GuidedPilotRunner
    /// Bascule la Synthèse sur « Comparer » ; `scroll` y mène en plus.
    var revealComparison: (_ scroll: Bool) -> Void
    @Binding var message: String?

    private static let rows: [ProbeMetric] = [.frameP50, .frameP99, .workingSet]

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            if let report = pairReport {
                Text(localization.L(Self.verdictKey(GuidedPilotVerdict.of(report))))
                    .font(AppDesign.Font.body(.semibold)).fixedSize(horizontal: false, vertical: true)
                ForEach(Self.rows, id: \.self) { metric in
                    if let result = report.metrics[metric] { row(result, quality: report.quality[metric]) }
                }
            } else {
                Text(localization.L(L10n.PerformancePilot.ready))
                    .font(AppDesign.Font.footnote).fixedSize(horizontal: false, vertical: true)
            }
            if let note = Self.parcNote(pilot, localization) {
                Text(note).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            WrapHStack(spacing: AppDesign.Spacing.sm) {
                Button(localization.L(L10n.PerformancePilot.showDetail)) { revealComparison(true) }
                    .clickableCursor()
                    .disabled(pairReport == nil)
                if pilot.canRollback {
                    Button(Self.rollbackTitle(pilot, localization)) {
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
                let keep = Self.keepTitle(pilot, localization)
                Button(keep) {
                    pilot.dismiss()
                    message = nil
                }
                .lineLimit(1)
                .help(keep)
                .clickableCursor()
            }
        }
        .onAppear { revealComparison(false) }
        // La paire n'est lisible qu'une fois le côté B relu : une relecture
        // de plus si elle manque, puis de nouveau quand les côtés changent.
        .task(id: pairKey) {
            guard let before = pilot.state.beforePlanId, let after = pilot.state.afterPlanId else { return }
            if !store.showPilotPair(before: before, after: after) {
                await PerformanceReloadLog.run(viewModel, cause: "fin de série pilotée") {
                    await store.reload(gameDir: viewModel.gameDir)
                }
                store.showPilotPair(before: before, after: after)
            }
        }
    }

    private var pairKey: String {
        "\(pilot.state.beforePlanId?.uuidString ?? "")|\(pilot.state.afterPlanId?.uuidString ?? "")|\(store.sides.count)"
    }

    private var pairReport: ProbePerformanceReport? {
        guard let report = store.report, let before = pilot.state.beforePlanId,
              let after = pilot.state.afterPlanId,
              report.before.measurement?.id == before, report.after.measurement?.id == after
        else { return nil }
        return report
    }

    /// Partagés avec les sorties en échec (`PerformancePilotStatus.decision`) :
    /// tant que le parc est sur B, chaque bouton dit ce qu'il garde — le
    /// profil, le mod en pause ou le réglage d'avant (départ « Isoler »).
    static func parcNote(_ pilot: GuidedPilotRunner, _ localization: LocalizationStore) -> String? {
        guard pilot.canRollback, pilot.state.parcIsOnAfterSide, let label = pilot.state.changeLabel,
              let keys = changeKeys(pilot.state.gesture) else { return nil }
        return String(format: localization.L(keys.now), label)
    }

    static func keepTitle(_ pilot: GuidedPilotRunner, _ localization: LocalizationStore) -> String {
        guard pilot.canRollback else { return localization.L(L10n.PerformancePilot.close) }
        guard pilot.state.parcIsOnAfterSide, let label = pilot.state.changeLabel,
              let keys = changeKeys(pilot.state.gesture) else {
            return localization.L(L10n.PerformancePilot.dismiss)
        }
        return String(format: localization.L(keys.keep), label)
    }

    private static func changeKeys(_ gesture: GuidedPilotGesture?) -> (now: String, keep: String)? {
        switch gesture {
        case .applyProfile: return (L10n.PerformancePilot.parcNow, L10n.PerformancePilot.keepProfile)
        case .pauseMod: return (L10n.PerformancePilot.parcNowPause, L10n.PerformancePilot.keepPause)
        case .revertConfig: return (L10n.PerformancePilot.parcNowConfig, L10n.PerformancePilot.keepConfig)
        case nil: return nil
        }
    }

    static func rollbackTitle(_ pilot: GuidedPilotRunner, _ localization: LocalizationStore) -> String {
        localization.L(pilot.state.changeLabel == nil ? L10n.PerformancePilot.rollback : L10n.PerformancePilot.backToBefore)
    }

    private func row(_ result: ProbeMetricResult, quality: ProbeComparisonQuality?) -> some View {
        WrapHStack(spacing: AppDesign.Spacing.sm) {
            Text(PerformanceMetricText.name(result.metric, localization))
            Text("A \(number(result.before)) → B \(number(result.after)) \(PerformanceMetricText.unit(result.metric, localization))")
                .monospacedDigit()
            Label(PerformanceMetricText.outcome(result.outcome, localization),
                  systemImage: PerformanceMetricText.symbol(result.outcome))
                .foregroundStyle(PerformanceMetricText.tint(result.outcome))
            if let quality {
                Text(PerformanceMetricText.quality(quality.level, localization)).foregroundStyle(.secondary)
            }
        }
        .font(AppDesign.Font.footnote)
    }

    private func number(_ value: Double?) -> String { PerformanceFormatting.number(value) }

    static func verdictKey(_ verdict: GuidedPilotVerdict) -> String {
        switch verdict {
        case .identical: return L10n.PerformancePilot.verdictIdentical
        case .smoother: return L10n.PerformancePilot.verdictSmoother
        case .lessSmooth: return L10n.PerformancePilot.verdictLessSmooth
        case .mixed: return L10n.PerformancePilot.verdictMixed
        case .noDifference: return L10n.PerformancePilot.verdictNoDifference
        case .inconclusive: return L10n.PerformancePilot.verdictInconclusive
        }
    }
}
