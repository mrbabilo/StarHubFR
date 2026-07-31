import SwiftUI

/// Guide pas à pas jusqu'au mod responsable. Un seul message et un seul choix
/// par écran : la personne en face a un jeu qui plante, pas envie de lire.
struct BisectionCard: View {
    @ObservedObject var vm: StarHubTHViewModel
    @ObservedObject private var runner: BisectionRunner
    @State private var showMods = false
    @State private var showCleared = false

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
                    concluded(folder)
                case .inconclusive(let remaining):
                    inconclusive(remaining)
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

    /// Liste dépliable avec bouton de copie. Une liste de mods ne sert à rien si
    /// on ne peut pas la sortir de l'application — pour la coller dans une
    /// demande d'aide, ou simplement la garder sous les yeux.
    private func copyableList(_ title: String, _ items: [String],
                              expanded: Binding<Bool>) -> some View {
        DisclosureGroup(isExpanded: expanded) {
            VStack(alignment: .leading, spacing: 6) {
                // Défilement borné et plusieurs colonnes : une liste de
                // cinquante mods sur une colonne débordait de la carte, et le
                // bas — bouton de copie compris — devenait inatteignable.
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)],
                              alignment: .leading, spacing: 2) {
                        ForEach(items.sorted(), id: \.self) { name in
                            Text(name)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 160)
                .textSelection(.enabled)
                Button(vm.L(L10n.Bisect.copyList)) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(items.sorted().joined(separator: "\n"),
                                                   forType: .string)
                }
                .buttonStyle(.borderless).controlSize(.small)
            }
        } label: {
            Text("\(vm.L(title)) (\(items.count))").font(.system(size: 12))
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
            // Ce qui est déjà écarté : la seule mesure honnête de l'avancement,
            // et ce qui donne un sens à l'attente entre deux lancements de jeu.
            if !runner.clearedFolders.isEmpty {
                Text(String(format: vm.L(L10n.Bisect.clearedCount), runner.clearedFolders.count))
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            copyableList(L10n.Bisect.showMods, runner.currentFolders, expanded: $showMods)
            if !runner.clearedFolders.isEmpty {
                copyableList(L10n.Bisect.showCleared, runner.clearedFolders, expanded: $showCleared)
            }
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
                if runner.gameStillRunning {
                    Label(vm.L(L10n.Bisect.quitGameFirst), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
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
    ///
    /// Rien tant que le journal n'est pas celui de la partie qu'on vient de
    /// jouer : un journal périmé décrirait la session *précédente*. Une session
    /// propre suivie d'un plantage ferait alors dire « le jeu s'est terminé
    /// normalement » juste après un plantage — l'utilisateur répondrait de
    /// travers et la recherche désignerait un innocent. Écarte aussi le mode
    /// sans SMAPI, où il n'y a pas de journal du tout.
    private var logHint: String? {
        guard !vm.smapiLogStale, let d = vm.smapiDiagnostics else { return nil }
        return vm.L(d.problemCount == 0 ? L10n.Bisect.hintClean : L10n.Bisect.hintCrashed)
    }

    /// « Pas de réponse simple » n'est pas rien : la recherche a réduit le champ
    /// à ces mods-là. Les taire jetterait le bénéfice de plusieurs lancements de
    /// jeu à la dernière ligne.
    private func inconclusive(_ remaining: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vm.L(L10n.Bisect.inconclusiveTitle)).font(.system(size: 13, weight: .semibold))
            Text(vm.L(L10n.Bisect.inconclusiveBody))
                .font(.system(size: 12)).foregroundColor(.secondary)
            if !remaining.isEmpty {
                Text(vm.L(L10n.Bisect.inconclusiveRemaining))
                    .font(.system(size: 12, weight: .medium))
                Text(remaining.sorted().joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            logEvidenceView
            Button(vm.L(L10n.Bisect.restore)) { runner.restoreAndStop() }
                .disabled(runner.isApplying)
        }
    }

    /// Conclusion, confrontée à ce que le journal dit de son côté.
    ///
    /// La bissection suppose **un seul** coupable. Quand la panne naît de deux
    /// mods qui ne s'entendent pas, retirer l'un ou l'autre la fait disparaître :
    /// la recherche en désigne un, en toute légitimité, mais présenter ce mod
    /// comme « la » cause est trompeur — et l'utilisateur qui a vu l'autre nom
    /// dans le journal n'y croira pas, à raison. Si le journal impute des
    /// erreurs à un mod différent, on le dit.
    private func concluded(_ folder: String) -> some View {
        // Sur le relevé accumulé, pas sur le dernier journal lu : après la
        // restauration finale, celui-ci décrit une partie qui n'est plus celle
        // de la recherche. Et c'est bien le cumul qui porte l'information —
        // une erreur intermittente n'apparaît qu'à certaines étapes.
        let blamedByLog = runner.logEvidence
            .first { !$0.name.localizedCaseInsensitiveContains(folder)
                  && !folder.localizedCaseInsensitiveContains($0.name) }?.name
        return VStack(alignment: .leading, spacing: 10) {
            Text(vm.L(L10n.Bisect.concludedTitle)).font(.system(size: 13, weight: .semibold))
            Text(String(format: vm.L(L10n.Bisect.concludedBody), folder))
                .font(.system(size: 12)).foregroundColor(.secondary)
            if let other = blamedByLog {
                Label(String(format: vm.L(L10n.Bisect.logNamesOther), other, folder),
                      systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundColor(.orange)
            }
            logEvidenceView
            Button(vm.L(L10n.Bisect.restore)) { runner.restoreAndStop() }
                .disabled(runner.isApplying)
        }
    }

    /// Ce que le journal a imputé, étape après étape. Signal **indépendant** des
    /// réponses : la bissection cherche un coupable unique, le journal nomme
    /// tout ce qui a mal tourné. Quand les deux divergent, c'est presque
    /// toujours que deux mods sont en cause ensemble.
    @ViewBuilder
    private var logEvidenceView: some View {
        if !runner.logEvidence.isEmpty {
            Text(vm.L(L10n.Bisect.logEvidence))
                .font(.system(size: 12, weight: .medium))
            ForEach(runner.logEvidence) { suspect in
                Text(String(format: vm.L(L10n.Bisect.logSuspectLine),
                            suspect.name, suspect.whenBroken, suspect.brokenSteps))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
