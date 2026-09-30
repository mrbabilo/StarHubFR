import SwiftUI

/// Série en cours, résultat ou reprise d'un benchmark interrompu.
struct PerformanceBenchmarkStatus: View {
    var runner: BenchmarkRunner
    @ObservedObject var localization: LocalizationStore

    private static let percentFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        // Un formateur nu n'écrit aucune décimale (0,5 → « 0 »).
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if runner.interrupted != nil, !runner.isActive {
                Text(localization.L(L10n.Benchmark.interrupted)).fixedSize(horizontal: false, vertical: true)
                Button(localization.L(L10n.Benchmark.restore)) { runner.restoreInterrupted() }
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
                    Button(localization.L(L10n.Benchmark.stop)) { runner.stop() }
                }
            case .restoring:
                Text(localization.L(L10n.Benchmark.restoring))
            case .finished(let outcome):
                line(L10n.Benchmark.resultLaunch, outcome.launch)
                line(L10n.Benchmark.resultSave, outcome.save)
            case .failed(let failure):
                Text(String(format: localization.L(L10n.Benchmark.failed), localization.L(key(failure))))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !runner.touchedSaves.isEmpty {
                Text(String(format: localization.L(L10n.Benchmark.saveTouched),
                            runner.touchedSaves.joined(separator: ", ")))
                    .foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(AppDesign.Font.footnote)
    }

    @ViewBuilder
    private func line(_ titleKey: String, _ outcome: BenchmarkKindOutcome) -> some View {
        switch outcome {
        case .notComparable:
            Text(String(format: localization.L(titleKey), localization.L(L10n.Benchmark.notComparable)))
                .fixedSize(horizontal: false, vertical: true)
        case .result(let r):
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: localization.L(titleKey), verdict(r.verdict)))
                    .font(AppDesign.Font.body(.semibold))
                Text(String(format: localization.L(L10n.Benchmark.noiseLine),
                            PerformanceLoadsSection.duration(r.medianAMs),
                            PerformanceLoadsSection.duration(r.medianBMs),
                            percent(r.noisePercent), percent(r.thresholdPercent)))
                    .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func verdict(_ v: ProbeLoadVerdict) -> String {
        switch v {
        case .faster(let seconds, let p):
            return "B −\(PerformanceLoadsSection.duration(seconds * 1000)) (−\(percent(p)))"
        case .slower(let seconds, let p):
            return "B +\(PerformanceLoadsSection.duration(seconds * 1000)) (+\(percent(p)))"
        case .noDifference:
            return localization.L(L10n.Benchmark.verdictSame)
        case .grayZone:
            return localization.L(L10n.Benchmark.verdictGray)
        }
    }

    private func percent(_ value: Double?) -> String {
        guard let value, let text = Self.percentFormatter.string(from: NSNumber(value: value)) else { return "—" }
        return "\(text) %"
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
