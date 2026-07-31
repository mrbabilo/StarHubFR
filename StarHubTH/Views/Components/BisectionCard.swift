import SwiftUI

/// Guide pas à pas jusqu'au mod responsable. Un seul message et un seul choix
/// par écran : la personne en face a un jeu qui plante, pas envie de lire.
struct BisectionCard: View {
    @ObservedObject var vm: StarHubTHViewModel
    @ObservedObject private var runner: BisectionRunner
    @State private var showMods = false

    init(vm: StarHubTHViewModel) {
        self.vm = vm
        self.runner = vm.bisection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(vm.L(L10n.Bisect.title)).font(.headline)

            if let snapshot = runner.interruptedSnapshot, runner.state == nil, !runner.noCandidates {
                interrupted(snapshot)
            } else if runner.noCandidates {
                noCandidatesView
            } else {
                switch runner.state {
                case nil:
                    idle
                case .reproducing:
                    step(title: L10n.Bisect.reproduceTitle, body: L10n.Bisect.reproduceBody)
                case .trial(let n, let total):
                    trial(n, total)
                case .confirming(let folder):
                    confirming(folder)
                case .concluded(let folder):
                    finished(L10n.Bisect.concludedTitle,
                             String(format: vm.L(L10n.Bisect.concludedBody), folder))
                case .inconclusive:
                    finished(L10n.Bisect.inconclusiveTitle, vm.L(L10n.Bisect.inconclusiveBody))
                case .notReproducible:
                    finished(L10n.Bisect.notReproducibleTitle, vm.L(L10n.Bisect.notReproducibleBody))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 10) {
            if runner.isApplying {
                // Préparation de la recherche (détection des candidats) ou
                // lancement du jeu : rien à proposer tant que ça tourne.
                Text(vm.L(L10n.Bisect.launching)).font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                Text(vm.L(L10n.Bisect.intro)).font(.system(size: 12)).foregroundColor(.secondary)
                Button(vm.L(L10n.Bisect.start)) { runner.start() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func step(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vm.L(title)).font(.system(size: 13, weight: .semibold))
            Text(vm.L(body)).font(.system(size: 12)).foregroundColor(.secondary)
            answerButtons
        }
    }

    private func trial(_ n: Int, _ total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(format: vm.L(L10n.Bisect.stepOf), n, total))
                .font(.system(size: 13, weight: .semibold))
            ProgressView(value: Double(n), total: Double(total))
            // Mods en pause = candidats (code-mods) moins ceux de l'essai courant.
            // On ne compte pas les mods déjà désactivés avant la recherche.
            Text(String(format: vm.L(L10n.Bisect.pausedCount),
                        max(0, runner.candidateCount - runner.currentFolders.count)))
                .font(.system(size: 12)).foregroundColor(.secondary)
            DisclosureGroup(vm.L(L10n.Bisect.showMods), isExpanded: $showMods) {
                Text(runner.currentFolders.sorted().joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 12))
            answerButtons
        }
    }

    private func confirming(_ folder: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vm.L(L10n.Bisect.confirmTitle)).font(.system(size: 13, weight: .semibold))
            Text(String(format: vm.L(L10n.Bisect.confirmBody), folder))
                .font(.system(size: 12)).foregroundColor(.secondary)
            answerButtons
        }
    }

    private var answerButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            if runner.isApplying {
                Text(vm.L(L10n.Bisect.launching)).font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                Text(vm.L(L10n.Bisect.waiting)).font(.system(size: 12)).foregroundColor(.secondary)
                if let hint = logHint {
                    Text(String(format: vm.L(L10n.Bisect.hintFromLog), hint))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Text(vm.L(L10n.Bisect.question)).font(.system(size: 12, weight: .medium))
                HStack {
                    Button(vm.L(L10n.Bisect.answerYes)) { runner.answer(.stillBroken) }
                    Button(vm.L(L10n.Bisect.answerNo)) { runner.answer(.fixed) }
                    Spacer()
                    Button(vm.L(L10n.Bisect.restore)) { runner.restoreAndStop() }
                        .buttonStyle(.borderless).foregroundColor(.secondary)
                }
            }
        }
    }

    /// Ce que dit le journal, traduit — une suggestion, jamais une décision.
    /// `SmapiDiagnostics` n'expose pas de prédicat « sain » : on se fie au
    /// nombre de problèmes (zéro = le jeu s'est terminé normalement).
    private var logHint: String? {
        guard let d = vm.smapiDiagnostics else { return nil }
        return vm.L(d.problemCount == 0 ? L10n.Bisect.hintClean : L10n.Bisect.hintCrashed)
    }

    private func finished(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vm.L(title)).font(.system(size: 13, weight: .semibold))
            Text(body).font(.system(size: 12)).foregroundColor(.secondary)
            Button(vm.L(L10n.Bisect.restore)) { runner.restoreAndStop() }
                .disabled(runner.isApplying)
        }
    }

    private func interrupted(_ snapshot: BisectionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vm.L(L10n.Bisect.interruptedTitle)).font(.system(size: 13, weight: .semibold))
            Text(String(format: vm.L(L10n.Bisect.interruptedBody),
                        DateFormatter.localizedString(from: snapshot.startedAt,
                                                      dateStyle: .short, timeStyle: .short)))
                .font(.system(size: 12)).foregroundColor(.secondary)
            Button(vm.L(L10n.Bisect.restore)) { runner.restoreAndStop() }
                .buttonStyle(.borderedProminent)
                .disabled(runner.isApplying)
        }
    }

    /// Aucun code-mod parmi les mods actifs : rien à mettre en pause. Un bouton
    /// pour refermer et revenir à l'intro (restoreAndStop se contente de
    /// réinitialiser l'état quand il n'y a rien à restaurer).
    private var noCandidatesView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vm.L(L10n.Bisect.title)).font(.system(size: 13, weight: .semibold))
            Text(vm.L(L10n.Bisect.noCandidates)).font(.system(size: 12)).foregroundColor(.secondary)
            Button(vm.L(L10n.Bisect.restore)) { runner.restoreAndStop() }
                .disabled(runner.isApplying)
        }
    }
}
