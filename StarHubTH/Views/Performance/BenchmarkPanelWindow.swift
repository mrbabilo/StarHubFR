import SwiftUI
import AppKit

/// Lignes de verdict d'un benchmark fini, partagées par le statut inline et
/// le panneau flottant (une seule copie : deux formats divergents se
/// contrediraient un jour).
struct BenchmarkOutcomeLines: View {
    let outcome: BenchmarkOutcome
    @ObservedObject var localization: LocalizationStore

    static let percentFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        // Un formateur nu n'écrit aucune décimale (0,5 → « 0 »).
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            line(L10n.Benchmark.resultLaunch, outcome.launch)
            line(L10n.Benchmark.resultSave, outcome.save)
        }
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
}

/// D5-B — le panneau de suivi du benchmark : un `NSPanel` utilitaire
/// **non activant** au niveau flottant, visible pendant que le jeu tourne
/// au premier plan, sans jamais lui prendre le focus (l'inverse du splash,
/// qui devait s'activer pour se montrer). Jamais `orderOut` d'une autre
/// fenêtre : fermer le panneau ne fait qu'achever le panneau.
@MainActor
final class BenchmarkPanelController {
    static let shared = BenchmarkPanelController()
    private init() {}

    private var panel: NSPanel?

    func show(runner: BenchmarkRunner, localization: LocalizationStore) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.title = localization.L(L10n.Benchmark.panelTitle)
        panel.contentView = NSHostingView(rootView: BenchmarkPanelContent(
            runner: runner, localization: localization,
            onClose: { [weak panel] in panel?.orderOut(nil) }))
        panel.center()
        // `orderFrontRegardless` : l'app n'est pas forcément active (le jeu
        // l'est), `makeKeyAndOrderFront` resterait sans effet visible.
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
                            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        return panel
    }
}

/// Le contenu du panneau : la ligne « ce qui change entre A et B », chaque
/// étape de la série avec son état et sa durée, la sous-progression du run
/// en cours (chronomètre + dernier jalon lu dans `loads.jsonl`), le bouton
/// d'arrêt et le verdict final.
struct BenchmarkPanelContent: View {
    let runner: BenchmarkRunner
    @ObservedObject var localization: LocalizationStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            if let setup = runner.setup { changeLine(setup) }
            switch runner.phase {
            case .preparing:
                HStack(spacing: AppDesign.Spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text(localization.L(L10n.Benchmark.preparingLine))
                }
            case .idle:
                EmptyView()
            default:
                steps
            }
            switch runner.phase {
            case .restoring:
                HStack(spacing: AppDesign.Spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text(localization.L(L10n.Benchmark.restoring))
                }
            case .finished(let outcome):
                BenchmarkOutcomeLines(outcome: outcome, localization: localization)
                Button(localization.L(L10n.Benchmark.close), action: onClose).clickableCursor()
            case .failed(let failure):
                Text(String(format: localization.L(L10n.Benchmark.failed), failureName(failure)))
                    .fixedSize(horizontal: false, vertical: true)
                Button(localization.L(L10n.Benchmark.close), action: onClose).clickableCursor()
            default:
                EmptyView()
            }
            if runner.isActive {
                VStack(alignment: .leading, spacing: 2) {
                    Button(localization.L(L10n.Benchmark.stop)) { runner.stop() }.clickableCursor()
                    Text(localization.L(L10n.Benchmark.stopHint))
                        .font(AppDesign.Font.caption(.regular)).foregroundColor(.secondary)
                }
            }
            if !runner.touchedSaves.isEmpty {
                Text(String(format: localization.L(L10n.Benchmark.saveTouched),
                            runner.touchedSaves.joined(separator: ", ")))
                    .foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppDesign.Spacing.md)
        .frame(minWidth: 360, alignment: .leading)
        .font(AppDesign.Font.footnote)
    }

    /// La ligne d'annonce : ce que la série compare, et avec quelles sauvegardes.
    @ViewBuilder
    private func changeLine(_ setup: BenchmarkSetup) -> some View {
        let changeText: String = {
            switch BenchmarkSides.change(for: setup.sideB, mods: runner.viewModelMods) {
            case .pauseMod(let name): return String(format: localization.L(L10n.Benchmark.changePause), name)
            case .profile(let count): return String(format: localization.L(L10n.Benchmark.changeProfile), count)
            case .sameState: return localization.L(L10n.Benchmark.changeSame)
            }
        }()
        let saves = setup.saveA.folderName == setup.saveB.folderName
            ? localization.L(L10n.Benchmark.savesSame)
            : localization.L(L10n.Benchmark.savesDistinct)
        VStack(alignment: .leading, spacing: 2) {
            Text(changeText)
            Text(String(format: localization.L(L10n.Benchmark.savesLine), saves))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var steps: some View {
        ForEach(runner.runs.indices, id: \.self) { index in
            if index < runner.observations.count {
                stepRow(index, runner.observations[index])
            }
        }
    }

    @ViewBuilder
    private func stepRow(_ index: Int, _ observation: BenchmarkRunner.RunObservation) -> some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Text(runLabel(index))
            Spacer()
            stateLabel(observation)
        }
    }

    private func runLabel(_ index: Int) -> String {
        guard index < runner.runs.count else { return "" }
        return "\(index + 1)/\(runner.runs.count) · \(localization.L(runSideKey(runner.runs[index].side)))"
    }

    @ViewBuilder
    private func stateLabel(_ observation: BenchmarkRunner.RunObservation) -> some View {
        if let duration = observation.duration {
            Text("✔ \(PerformanceLoadsSection.duration(duration * 1000))")
                .foregroundColor(.secondary)
        } else if let startedAt = observation.startedAt {
            HStack(spacing: AppDesign.Spacing.xs) {
                ProgressView().controlSize(.mini)
                Text(timerInterval: startedAt...startedAt.addingTimeInterval(BenchmarkRunner.maxRunSeconds),
                     countsDown: false)
                Text(milestoneText(observation)).foregroundColor(.secondary)
            }
        } else {
            Text(localization.L(L10n.Benchmark.stepPending)).foregroundColor(.secondary)
        }
    }

    /// La sous-progression, tirée des jalons que la sonde écrit déjà dans
    /// `loads.jsonl` — rien de nouveau à installer.
    private func milestoneText(_ observation: BenchmarkRunner.RunObservation) -> String {
        switch (observation.gameSeen, observation.milestone) {
        case (false, _):
            return localization.L(L10n.Benchmark.gameLaunching)
        case (true, "L4"), (true, "L3"):
            return localization.L(L10n.Benchmark.titleReached)
        case (true, "S9"):
            return localization.L(L10n.Benchmark.saveLoadedDone)
        case (true, .some(let name)) where name.hasPrefix("S"):
            return String(format: localization.L(L10n.Benchmark.loadingAt), name)
        case (true, .some(let name)):
            return String(format: localization.L(L10n.Benchmark.startingAt), name)
        case (true, .none):
            return localization.L(L10n.Benchmark.gameLoading)
        }
    }

    private func runSideKey(_ side: BenchmarkSide) -> String {
        switch side {
        case .warmupA, .warmupB: return L10n.Benchmark.runWarmup
        case .a: return L10n.Benchmark.runA
        case .b: return L10n.Benchmark.runB
        }
    }

    private func failureName(_ failure: BenchmarkFailure) -> String {
        switch failure {
        case .neverStarted: return localization.L(L10n.Benchmark.failNeverStarted)
        case .timeout: return localization.L(L10n.Benchmark.failTimeout)
        case .noLine: return localization.L(L10n.Benchmark.failNoLine)
        case .apply: return localization.L(L10n.Benchmark.failApply)
        case .launch: return localization.L(L10n.Benchmark.failLaunch)
        case .copy: return localization.L(L10n.Benchmark.failCopy)
        case .stopped: return localization.L(L10n.Benchmark.failStopped)
        }
    }
}
