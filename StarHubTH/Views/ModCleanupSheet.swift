import SwiftUI

/// A1-T11 plan 2 — l'aperçu du nettoyage d'un mod : ce qui serait retiré,
/// coché d'office quand c'est prouvé (identique à un fichier de l'auteur
/// déposé avant la version installée), décoché quand ce n'est que probable.
/// Confirmer sauvegarde le dossier, puis retire.
///
/// ⚠️ `analyze` et `apply` bloquent leur appelant : `DispatchQueue.global`,
/// jamais un `Task` — le pool coopératif gèle (CI du 2026-09-28).
struct ModCleanupSheet: View {
    @ObservedObject var localization: LocalizationStore
    let viewModel: StarHubTHViewModel
    let mod: ModItem
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case analyzing
        case noReference
        case ready(LegacyFileCleanup.Plan)
        case applying
        case finished(String)
    }

    @State private var phase: Phase = .analyzing
    @State private var selection: Set<String> = []
    @State private var gameRunningAtConfirm = false

    /// Un autre dossier porte le même `UniqueID` (Swim installé deux fois) :
    /// leur journal commun ne sert ni de référence ni de destination.
    private var uniqueIdIsShared: Bool {
        viewModel.mods.flattenedMods.filter {
            $0.uniqueId.caseInsensitiveCompare(mod.uniqueId) == .orderedSame
        }.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(String(format: localization.L(L10n.ModCleanup.title), mod.name))
                .font(AppDesign.Font.headline)
                .lineLimit(2)
            content
            Divider()
            footer
        }
        .padding(AppDesign.Spacing.lg)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 360, idealHeight: 520)
        .onAppear(perform: analyze)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .analyzing:
            progress(localization.L(L10n.ModCleanup.analyzing))
        case .applying:
            progress(localization.L(L10n.ModCleanup.applying))
        case .noReference:
            message(String(format: localization.L(L10n.ModCleanup.noReference), mod.version))
        case .finished(let text):
            message(text)
        case .ready(let plan):
            if plan.candidates.isEmpty {
                message(localization.L(L10n.ModCleanup.nothing))
            } else {
                candidateList(plan)
            }
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            ProgressView().controlSize(.small)
            Text(text).font(AppDesign.Font.footnote)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(AppDesign.Font.body)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func candidateList(_ plan: LegacyFileCleanup.Plan) -> some View {
        let identical = plan.candidates.filter { $0.certainty == .identical }
        let probable = plan.candidates.filter { $0.certainty == .pathOnly }
        return ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                if !plan.preselectsIdentical {
                    Text(localization.L(L10n.ModCleanup.unverified))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(AppDesign.Color.warning)
                        .fixedSize(horizontal: false, vertical: true)
                } else if plan.nexusIncomplete {
                    Text(localization.L(L10n.ModCleanup.nexusIncomplete))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(AppDesign.Color.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !identical.isEmpty {
                    group(title: String(format: localization.L(L10n.ModCleanup.identical), identical.count),
                          hint: localization.L(L10n.ModCleanup.identicalHint), candidates: identical)
                }
                if !probable.isEmpty {
                    group(title: String(format: localization.L(L10n.ModCleanup.probable), probable.count),
                          hint: localization.L(L10n.ModCleanup.probableHint), candidates: probable)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Un groupe, ses fichiers rangés par dossier.
    private func group(title: String, hint: String, candidates: [LegacyFileCleanup.Candidate]) -> some View {
        let byFolder = Dictionary(grouping: candidates) { ($0.path as NSString).deletingLastPathComponent }
        return VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            Text(title).font(AppDesign.Font.footnote(.semibold))
            Text(hint)
                .font(AppDesign.Font.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(byFolder.keys.sorted(), id: \.self) { folder in
                if !folder.isEmpty {
                    Text(folder + "/")
                        .font(AppDesign.Font.monoFootnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.top, 2)
                }
                ForEach(byFolder[folder] ?? []) { candidate in
                    Toggle(isOn: binding(for: candidate.path)) {
                        HStack(spacing: 6) {
                            Text((candidate.path as NSString).lastPathComponent)
                                .font(AppDesign.Font.monoFootnote)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(ByteCountFormatter.string(fromByteCount: candidate.size, countStyle: .file))
                                .font(AppDesign.Font.caption)
                                .foregroundColor(.secondary)
                                .fixedSize()
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.leading, folder.isEmpty ? 0 : 12)
                    .accessibilityLabel(candidate.path)
                }
            }
        }
    }

    private func binding(for path: String) -> Binding<Bool> {
        Binding(get: { selection.contains(path) },
                set: { isOn in if isOn { selection.insert(path) } else { selection.remove(path) } })
    }

    private var selected: [LegacyFileCleanup.Candidate] {
        guard case .ready(let plan) = phase else { return [] }
        return plan.candidates.filter { selection.contains($0.path) }
    }

    private var hasCandidates: Bool {
        if case .ready(let plan) = phase { return !plan.candidates.isEmpty }
        return false
    }

    private var isApplying: Bool {
        if case .applying = phase { return true }
        return false
    }

    @ViewBuilder
    private var footer: some View {
        if hasCandidates {
            let bytes = selected.reduce(Int64(0)) { $0 + $1.size }
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: localization.L(L10n.ModCleanup.selection), selected.count,
                            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))
                    .font(AppDesign.Font.footnote)
                Text(localization.L(L10n.ModCleanup.backupNote))
                    .font(AppDesign.Font.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if gameRunningAtConfirm {
                    Text(localization.L(L10n.ModCleanup.gameRunning))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(AppDesign.Color.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        HStack {
            Spacer()
            if hasCandidates {
                Button(localization.L(L10n.ModCleanup.cancel)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(localization.L(L10n.ModCleanup.confirm), action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            } else {
                Button(localization.L(L10n.ModCleanup.close)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isApplying)
            }
        }
    }

    private func analyze() {
        let mod = mod
        let gameDir = viewModel.gameDir
        let translations = viewModel.installedTranslations
        let customIds = viewModel.nexusCustomModIds
        let shared = uniqueIdIsShared
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = LegacyCleanupSession.analyze(mod: mod, gameDir: gameDir, translations: translations,
                                                       customNexusIds: customIds, uniqueIdIsShared: shared)
            DispatchQueue.main.async {
                switch outcome {
                case .noReference:
                    phase = .noReference
                case .plan(let plan):
                    selection = plan.preselectsIdentical
                        ? Set(plan.candidates.filter { $0.certainty == .identical }.map(\.path)) : []
                    phase = .ready(plan)
                }
            }
        }
    }

    private func apply() {
        // Le jeu a pu démarrer depuis l'ouverture de la feuille : la liste et
        // la sélection restent, il suffit de fermer le jeu et de confirmer.
        gameRunningAtConfirm = viewModel.isGameRunning()
        guard !gameRunningAtConfirm else { return }
        let chosen = selected
        let mod = mod
        let gameDir = viewModel.gameDir
        let shared = uniqueIdIsShared
        phase = .applying
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome: Result<LegacyCleanupSession.ApplyResult, Error>
            do {
                outcome = .success(try LegacyCleanupSession.apply(chosen, mod: mod, gameDir: gameDir,
                                                                  recordInHistory: !shared))
            } catch {
                outcome = .failure(error)
            }
            // Les textes se composent sur le fil principal : `localization`
            // est un magasin de l'interface.
            DispatchQueue.main.async { finish(outcome) }
        }
    }

    private func finish(_ outcome: Result<LegacyCleanupSession.ApplyResult, Error>) {
        switch outcome {
        case .success(let result):
            if result.failed.isEmpty {
                phase = .finished(String(format: localization.L(L10n.ModCleanup.done), result.removed.count))
            } else {
                phase = .finished(String(format: localization.L(L10n.ModCleanup.partial), result.removed.count,
                                         result.failed.count, result.failed.joined(separator: ", ")))
            }
            if !result.removed.isEmpty {
                viewModel.log(String(format: localization.L(L10n.ModCleanup.logDone), mod.name, result.removed.count),
                       level: .info)
            }
            if !result.historyWritten {
                viewModel.log(String(format: localization.L(L10n.ModHistory.writeFailed), mod.uniqueId), level: .warning)
            }
        case .failure(LegacyCleanupSession.ApplyError.backupFailed(let reason)):
            phase = .finished(String(format: localization.L(L10n.ModCleanup.backupFailed), reason))
        case .failure(let error):
            phase = .finished(String(format: localization.L(L10n.ModCleanup.backupFailed),
                                     error.localizedDescription))
        }
        viewModel.measureModsFolderSize()
    }
}
