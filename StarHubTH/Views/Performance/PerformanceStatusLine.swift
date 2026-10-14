import SwiftUI

/// Lot A (audit UX du 2026-10-14, S1) — **une** zone d'état en tête de
/// l'onglet, par priorité : série pilotée, mesure guidée en cours, benchmark,
/// diagnostic tiers, chargement. Avant, quatre lignes concurrentes dans trois
/// fichiers disaient chacune leur bout de la même chose. Les résultats
/// (rapport pilote, décision après échec) restent des blocs à part dans
/// `PerformancePilotStatus` : ce sont des conclusions, pas des états.
///
/// Le minuteur de relecture (15 s) vit ici, lié à la présence de la mesure en
/// cours — une boucle `Task.sleep`, jamais `TimelineView(.periodic(from: .now…))`
/// qui relirait en boucle (v1.64.0).
struct PerformanceStatusLine: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    var sloDiagnostic: SloDiagnosticSessionStore
    var stardropiumDiagnostic: SloDiagnosticSessionStore

    /// Mesure en cours (plan guidé ou série pilotée) et jeu ouvert : les
    /// chiffres se relisent toutes les 15 s. Même règle pour le liseré de la
    /// carte Résumé (`liveRefreshFlash`).
    static func isLive(_ viewModel: StarHubTHViewModel, _ store: ProbePerformanceStore) -> Bool {
        (store.plan != nil || viewModel.pilot.isActive) && viewModel.isGameRunning()
    }

    var body: some View {
        let pilot = viewModel.pilot
        let live = Self.isLive(viewModel, store)
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            switch pilot.state.phase {
            case .running(let step):
                SplitRow {
                    HStack(spacing: AppDesign.Spacing.sm) {
                        PerformanceLiveIndicator(viewModel: viewModel, localization: localization, store: store,
                                                 offersBringGameFront: true)
                        Text(String(format: localization.L(L10n.PerformancePilot.status),
                                    localization.L(step == .before ? L10n.PerformancePilot.stepBefore
                                                                   : L10n.PerformancePilot.stepAfter),
                                    store.guidedMinuteCount))
                            .font(AppDesign.Font.footnote)
                    }
                } trailing: {
                    Button(localization.L(L10n.PerformancePilot.stop)) { pilot.stop() }
                        .help(localization.L(L10n.PerformancePilot.stopHelp))
                        .clickableCursor()
                }
                PerformancePilotStages(viewModel: viewModel, localization: localization, store: store,
                                       launchedAt: pilot.currentSideLaunchedAt)
            case .applying:
                Text(localization.L(L10n.PerformancePilot.applying)).font(AppDesign.Font.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            case .idle, .reporting, .failed, .interrupted:
                if live {
                    HStack(spacing: AppDesign.Spacing.sm) {
                        PerformanceLiveIndicator(viewModel: viewModel, localization: localization, store: store,
                                                 offersBringGameFront: false)
                        Text(String(format: localization.L(L10n.PerformanceEvidence.guidedProgress),
                                    store.guidedMinuteCount))
                            .font(AppDesign.Font.footnote)
                    }
                }
            }
            if live {
                Color.clear.frame(width: 0, height: 0)
                    .task {
                        while true {
                            do { try await Task.sleep(for: .seconds(15)) } catch { return }   // bloc retiré
                            guard viewModel.navigationStore.diagnosticsSegment == .performance else { continue }
                            await PerformanceReloadLog.run(viewModel, cause: "minuterie de mesure, 15 s") {
                                await store.reload(gameDir: viewModel.gameDir)
                            }
                        }
                    }
            }
            if viewModel.isBenchmarkActive {
                SplitRow {
                    Text(localization.L(L10n.PerformanceEvidence.benchmarkBusy)).font(AppDesign.Font.footnote)
                } trailing: {
                    HStack(spacing: AppDesign.Spacing.sm) {
                        Button(localization.L(L10n.Benchmark.panelOpen)) { viewModel.benchmark.showPanel() }
                            .clickableCursor()
                        Button(localization.L(L10n.Benchmark.stop)) { viewModel.benchmark.stop() }.clickableCursor()
                    }
                }
            }
            diagnosticLine(sloDiagnostic, title: L10n.PerformanceSloDiagnostic.title)
            diagnosticLine(stardropiumDiagnostic, title: L10n.StardropiumMemory.title)
            if store.status == .loading {
                ProgressView(localization.L(L10n.Performance.loading)).controlSize(.small)
            }
        }
    }

    /// Un diagnostic tiers qui occupe le jeu : une ligne, pour que la carte
    /// plus bas ne soit pas le seul endroit qui le dise.
    @ViewBuilder
    private func diagnosticLine(_ diagnostic: SloDiagnosticSessionStore, title: String) -> some View {
        let phase: String? = {
            switch diagnostic.state {
            case .preparing: return L10n.PerformanceSloDiagnostic.preparing
            case .waitingForGame: return L10n.PerformanceSloDiagnostic.waiting
            case .running: return L10n.PerformanceSloDiagnostic.running
            case .restoring: return L10n.PerformanceSloDiagnostic.restoring
            case .idle, .unavailable, .ready, .report, .memoryReport, .recoveryBlocked, .failed: return nil
            }
        }()
        if let phase {
            Label("\(localization.L(title)) · \(localization.L(phase))", systemImage: "waveform")
                .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
