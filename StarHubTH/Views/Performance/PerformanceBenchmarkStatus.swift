import SwiftUI

/// Série en cours, résultat ou reprise d'un benchmark interrompu. Le détail
/// vivant (étapes, durées, jalons) vit dans le panneau flottant
/// (`BenchmarkPanelContent`) ; cette ligne reste le filet quand le panneau
/// est fermé.
struct PerformanceBenchmarkStatus: View {
    var runner: BenchmarkRunner
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if runner.interrupted != nil, !runner.isActive {
                Text(localization.L(L10n.Benchmark.interrupted)).fixedSize(horizontal: false, vertical: true)
                Button(localization.L(L10n.Benchmark.restore)) { runner.restoreInterrupted() }.clickableCursor()
            }
            switch runner.phase {
            case .idle:
                EmptyView()
            case .preparing:
                ProgressView().controlSize(.small)
            case .running(let index):
                HStack {
                    Text(String(format: localization.L(L10n.Benchmark.progress), index + 1, runner.runs.count,
                                localization.L(runKey(runner.runs[index].side))))
                    Spacer()
                    Button(localization.L(L10n.Benchmark.stop)) { runner.stop() }.clickableCursor()
                }
            case .restoring:
                Text(localization.L(L10n.Benchmark.restoring))
            case .finished(let outcome):
                BenchmarkOutcomeLines(outcome: outcome, localization: localization)
            case .failed(let failure):
                Text(String(format: localization.L(L10n.Benchmark.failed), localization.L(key(failure))))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Ce que la série compare — la même ligne que le panneau, pour
            // qu'un panneau fermé ne perde pas l'information.
            if runner.isActive, let setup = runner.setup {
                changeLine(setup)
            }
            if !runner.touchedSaves.isEmpty {
                Text(String(format: localization.L(L10n.Benchmark.saveTouched),
                            runner.touchedSaves.joined(separator: ", ")))
                    .foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(AppDesign.Font.footnote)
    }

    /// Ce qui change entre A et B : le mod en pause (par son nom), le profil
    /// réduit, ou la mesure du bruit. Résolution partagée avec le panneau
    /// (`BenchmarkSides.change`).
    @ViewBuilder
    private func changeLine(_ setup: BenchmarkSetup) -> some View {
        let text: String = {
            switch BenchmarkSides.change(for: setup.sideB, mods: runner.viewModelMods) {
            case .pauseMod(let name): return String(format: localization.L(L10n.Benchmark.changePause), name)
            case .profile(let count): return String(format: localization.L(L10n.Benchmark.changeProfile), count)
            case .sameState: return localization.L(L10n.Benchmark.changeSame)
            }
        }()
        Text(text).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    /// Une chauffe se dit comme telle : sans quoi elle passe pour une mesure A.
    private func runKey(_ side: BenchmarkSide) -> String {
        switch side {
        case .warmupA, .warmupB: return L10n.Benchmark.runWarmup
        case .a: return L10n.Benchmark.runA
        case .b: return L10n.Benchmark.runB
        }
    }

    private func key(_ failure: BenchmarkFailure) -> String {
        switch failure {
        case .neverStarted: return L10n.Benchmark.failNeverStarted
        case .timeout: return L10n.Benchmark.failTimeout
        case .noLine: return L10n.Benchmark.failNoLine
        case .apply: return L10n.Benchmark.failApply
        case .launch: return L10n.Benchmark.failLaunch
        case .copy: return L10n.Benchmark.failCopy
        case .stopped: return L10n.Benchmark.failStopped
        }
    }
}
