import SwiftUI

/// L'analyse (spec §3d) : conclusion, confiance, preuves — une ligne par
/// règle qui a joué —, une recommandation et son geste. Chaque geste :
/// confirmation, refusé si le jeu tourne (vérifié au clic), réversible.
struct PerformanceAnalysisSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    let report: ProbePerformanceReport
    /// P2 — ouvre la feuille du benchmark, côté B = ce dossier en pause.
    let onBenchmark: (String) -> Void
    @State private var pending: PendingAction?
    @State private var message: String?

    /// Un geste en attente de confirmation. `pause` et `revertConfig`
    /// portent, pour « Isoler », la mesure à préparer une fois le changement
    /// défait (D5-A : un plan, plus un nom).
    private enum PendingAction: Identifiable {
        case pause(ModItem, thenMeasure: GuidedPlanDraft?), backups(ModItem),
             revertConfig(ModItem, sha: String, thenMeasure: GuidedPlanDraft?), prepare(GuidedPlanDraft)
        var id: String {
            switch self {
            case .pause(let m, _): return "pause|\(m.folderName)"
            case .backups(let m): return "backups|\(m.folderName)"
            case .revertConfig(let m, let sha, _): return "config|\(m.folderName)|\(sha)"
            case .prepare(let draft): return "prepare|\(draft.name)"
            }
        }
    }

    private var analysis: ProbeAnalysisResult { report.analysis }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(localization.L(L10n.Performance.sectionAnalysis)).font(AppDesign.Font.headline(.semibold))
            Text(String(format: localization.L(L10n.Performance.analysisPair),
                        PerformanceAnalysisTexts.sideTitle(report.before), PerformanceAnalysisTexts.sideTitle(report.after)))
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                .lineLimit(2)
            conclusionLabel
            confidenceBadge
            recommendation
                .padding(AppDesign.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppDesign.Color.accent.opacity(AppDesign.Opacity.subtle),
                            in: RoundedRectangle(cornerRadius: AppDesign.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: AppDesign.Radius.md)
                    .stroke(AppDesign.Color.accent.opacity(AppDesign.Opacity.medium), lineWidth: 1))
            DisclosureGroup(localization.L(L10n.PerformanceEvidence.details)) {
                ForEach(Array(analysis.evidence.enumerated()), id: \.offset) { _, evidence in
                    Text("· " + PerformanceAnalysisTexts.evidence(evidence, localization, name: name))
                        .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                }
                Text(localization.L(L10n.Performance.contextual))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
            if let message {
                Text(message).font(AppDesign.Font.footnote)
            }
        }
        .confirmationDialog(pending.map(confirmTitle) ?? "", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(localization.L(L10n.Performance.confirmAction)) { if let pending { perform(pending) } }
            Button(localization.L(L10n.Performance.confirmCancel), role: .cancel) {}
        } message: {
            // Préparer une mesure remplace celle qui attend (spec D5-A).
            if let waiting = store.plan, pending.map(preparesMeasure) == true {
                Text(String(format: localization.L(L10n.Performance.guidedReplace), waiting.name))
            }
        }
    }

    // MARK: Textes (`PerformanceAnalysisTexts`)

    private var conclusionLabel: some View {
        let visuals = PerformanceAnalysisTexts.directionVisuals(analysis.direction)
        return Label(PerformanceAnalysisTexts.conclusion(report, localization), systemImage: visuals.icon)
            .font(AppDesign.Font.body(.semibold)).foregroundColor(visuals.tint)
    }

    private var confidenceBadge: some View {
        let visuals = PerformanceAnalysisTexts.confidenceVisuals(analysis.confidence)
        return PerformanceBadge(label: PerformanceAnalysisTexts.confidence(analysis.confidence, localization),
                                systemImage: visuals.icon, tint: visuals.tint)
    }

    // MARK: Recommandation et gestes

    @ViewBuilder
    private var recommendation: some View {
        if report.scope.incompatible {
            ForEach(report.scope.issues, id: \.rawValue) { issue in
                Text(PerformanceMetricText.issue(issue, localization)).font(AppDesign.Font.body(.medium))
            }
        } else { recommendationAction }
    }

    @ViewBuilder
    private var recommendationAction: some View {
        let mods = viewModel.scanStore.mods
        switch analysis.recommendation {
        case .disableMod(let modId):
            action(String(format: localization.L(L10n.Performance.recDisable), name(modId)),
                   button: L10n.Performance.actionPause,
                   gesture: ProbePerformanceActions.target(modId: modId, in: mods)
                       .map { PendingAction.pause($0, thenMeasure: nil) })
            if let mod = ProbePerformanceActions.target(modId: modId, in: mods), mod.isEnabled {
                Button(localization.L(L10n.Performance.benchmarkThisMod)) { onBenchmark(mod.folderName) }
                    .clickableCursor().disabled(viewModel.benchmark.isActive)
            }
        case .revertVersion(let modId):
            action(String(format: localization.L(L10n.Performance.recRevertVersion), name(modId)),
                   button: L10n.Performance.actionBackups,
                   gesture: ProbePerformanceActions.target(modId: modId, in: mods).map(PendingAction.backups))
        case .revertConfig(let modId):
            action(String(format: localization.L(L10n.Performance.recRevertConfig), name(modId)),
                   button: L10n.Performance.actionRevertConfig,
                   gesture: revertGesture(modId: modId, mods: mods))
        case .configNoGain(let modId):
            // Geste secondaire (spec §3d) : revenir au réglage d'avant.
            action(String(format: localization.L(L10n.Performance.recConfigNoGain), name(modId)),
                   button: L10n.Performance.actionRevertConfig,
                   gesture: revertGesture(modId: modId, mods: mods))
        case .keep:
            Text(localization.L(L10n.Performance.recKeep)).font(AppDesign.Font.body(.medium))
        case .keepNoCost(let modId):
            Text(String(format: localization.L(L10n.Performance.recKeepNoCost), name(modId)))
                .font(AppDesign.Font.body(.medium))
        case .isolate:
            Text(localization.L(L10n.Performance.recIsolate)).font(AppDesign.Font.body(.medium))
            ForEach(report.diff?.changes ?? [], id: \.modId) { change in
                isolateRow(change, mods: mods)
            }
        case .rerunCleanMeasurement(let location, let missing):
            let detail: String = {
                if missing > 0 { return String(format: localization.L(L10n.PerformanceEvidence.missingMinutes), missing) }
                if let reason = report.quality[.frameP50]?.reasons.first {
                    return PerformanceMetricText.reason(reason, localization)
                }
                return localization.L(L10n.PerformanceEvidence.repeatAdvice)
            }()
            action(localization.L(L10n.Performance.recRerun), detail: detail,
                   button: L10n.Performance.actionPrepareMeasure,
                   gesture: .prepare(GuidedPlanDraft(name: localization.L(L10n.Performance.recRerun),
                                                     role: .before,
                                                     location: GuidedProtocol.safeLocation(location),
                                                     pairedWith: nil)))
        }
    }

    /// Un geste sans cible (mod plus installé) ne s'affiche pas (Review Focus 5).
    /// Jeu ouvert : le geste qui écrit dans `Mods/` reste visible, grisé, et
    /// la ligne dit pourquoi — avant le clic, pas après (lot C, G4).
    private func action(_ title: String, detail: String? = nil, button: String, gesture: PendingAction?) -> some View {
        let blocked = gesture.map(Self.needsGameClosed) == true && viewModel.isGameRunning()
        return VStack(alignment: .leading, spacing: 2) {
            SplitRow {
                Text(title).font(AppDesign.Font.body(.medium))
            } trailing: {
                if let gesture {
                    AdaptiveLabels {
                        Button { pending = gesture } label: { Label(localization.L(button), systemImage: "arrow.right.circle") }
                            .help(localization.L(button)).clickableCursor().disabled(blocked)
                    }
                }
            }
            if let detail = blocked ? localization.L(L10n.Performance.gameRunning) : detail {
                Text(detail).font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
        }
    }

    private static func needsGameClosed(_ gesture: PendingAction) -> Bool {
        switch gesture {
        case .pause, .revertConfig: return true
        case .prepare, .backups: return false
        }
    }

    /// « Isoler » : pour chaque changement, le défaire (pause ou réglage
    /// d'avant) puis préparer une mesure à son nom — elle démarre jeu lancé,
    /// depuis l'en-tête.
    private func isolateRow(_ change: ProbeModChange, mods: [ModItem]) -> some View {
        if case .configChanged = change.kind {
            let measureName = String(format: localization.L(L10n.Performance.isolateConfigMeasureName),
                                     name(change.modId))
            return action("· " + name(change.modId), button: L10n.Performance.actionRevertConfig,
                          gesture: revertGesture(modId: change.modId, mods: mods, thenMeasure: afterDraft(measureName)))
        }
        let measureName = String(format: localization.L(L10n.Performance.isolateMeasureName), name(change.modId))
        return action("· " + name(change.modId), button: L10n.Performance.actionPause,
                      gesture: ProbePerformanceActions.target(modId: change.modId, in: mods)
                          .map { PendingAction.pause($0, thenMeasure: afterDraft(measureName)) })
    }

    private func revertGesture(modId: String, mods: [ModItem], thenMeasure: GuidedPlanDraft? = nil) -> PendingAction? {
        guard let change = report.diff?.changes.first(where: {
                  $0.modId.caseInsensitiveCompare(modId) == .orderedSame }),
              case .configChanged(let old?, _) = change.kind,
              let mod = ProbePerformanceActions.configOwner(modId: modId, in: mods)
        else { return nil }
        return .revertConfig(mod, sha: old, thenMeasure: thenMeasure)
    }

    private func confirmTitle(_ gesture: PendingAction) -> String {
        let label: String
        switch gesture {
        case .pause(let m, _): label = "\(localization.L(L10n.Performance.actionPause)) — \(m.name)"
        case .backups(let m): label = "\(localization.L(L10n.Performance.actionBackups)) — \(m.name)"
        case .revertConfig(let m, _, _): label = "\(localization.L(L10n.Performance.actionRevertConfig)) — \(m.name)"
        case .prepare(let draft): label = "\(localization.L(L10n.Performance.actionPrepareMeasure)) — \(draft.name)"
        }
        return String(format: localization.L(L10n.Performance.confirmTitle), label)
    }

    /// Jeu vérifié **au clic** : pause et réglage refusés jeu lancé ; la
    /// préparation d'une mesure ne touche à rien d'autre que le plan (D5-A :
    /// la sonde la mène en jeu).
    private func perform(_ gesture: PendingAction) {
        pending = nil
        // Série pilotée en vol ou à trancher : ni son plan écrasé, ni son parc touché.
        if viewModel.pilot.busyReasonKey != nil {
            message = localization.L(L10n.PerformancePilot.locked)
            return
        }
        switch gesture {
        case .prepare(let draft):
            prepareMeasure(draft)
            return
        case .backups(let mod):
            viewModel.navigationStore.openBackups(for: mod.folderName)
            return
        case .pause, .revertConfig:
            break
        }
        guard !viewModel.isGameRunning() else {
            message = localization.L(L10n.Performance.gameRunning)
            return
        }
        if let piloted = pilotStart(for: gesture) {
            startPilot(piloted.draft, gesture: piloted.gesture, changeLabel: piloted.label)
            return
        }
        switch gesture {
        case .pause(let mod, let thenMeasure):
            if mod.isEnabled { viewModel.toggleMod(mod) }
            if let thenMeasure { prepareMeasure(thenMeasure) }
            message = nil
        case .revertConfig(let mod, let sha, let thenMeasure):
            let outcome = ProbePerformanceActions.revertConfig(
                of: mod, toSha: sha, configsDirectory: store.configsDirectory, gameDir: viewModel.gameDir,
                gameRunning: false, backups: ModConfigBackupManager.shared)
            switch outcome {
            case .reverted:
                if let thenMeasure { prepareMeasure(thenMeasure) }
                message = localization.L(L10n.Performance.revertDone)
            case .gameRunning: message = localization.L(L10n.Performance.gameRunning)
            case .contentMissing: message = localization.L(L10n.Performance.revertMissing)
            case .changedOnDisk: message = localization.L(L10n.Performance.revertChanged)
            case .backupFailed(let e), .writeFailed(let e):
                message = String(format: localization.L(L10n.Performance.revertFailed), e)
            }
        case .prepare, .backups:
            break
        }
    }

    /// Une mesure « après » comparée au côté que le geste modifie : le côté
    /// « après » de la paire affichée.
    private func afterDraft(_ name: String) -> GuidedPlanDraft {
        GuidedPlanDraft(name: name, role: .after, location: GuidedProtocol.gestureLocation(for: report.after),
                        pairedWith: report.after.measurement?.id)
    }

    private func preparesMeasure(_ gesture: PendingAction) -> Bool {
        switch gesture {
        case .prepare: return true
        case .pause(_, let then), .revertConfig(_, _, let then): return then != nil
        case .backups: return false
        }
    }

    /// Sonde ≥ 0.9.25 : un geste qui porte une mesure d'après se joue en
    /// piloté — « avant » frais, geste entre les deux côtés, « après »,
    /// rapport (spec §2.2, §8). Le geste ne part donc pas ici.
    private func pilotStart(for gesture: PendingAction) -> (draft: GuidedPlanDraft, gesture: GuidedPilotGesture, label: String)? {
        guard case .enabled(_, let version) = ModPresence.resolve(uniqueId: ModPresence.probeId, in: viewModel.mods),
              GuidedProtocol.supportsPilot(version),
              // Vanilla : le jeu partirait sans SMAPI, la série attendrait en vain.
              UserDefaults.standard.string(forKey: UDKey.launchProfile) != "Vanilla" else { return nil }
        switch gesture {
        case .pause(let mod, let then?) where mod.isEnabled:
            return (beforeDraft(then), .pauseMod(folderName: mod.folderName, modId: pilotModId(mod)), mod.name)
        case .revertConfig(let mod, let sha, let then?):
            return (beforeDraft(then), .revertConfig(modId: pilotModId(mod), sha: sha), mod.name)
        case .pause, .revertConfig, .prepare, .backups:
            return nil
        }
    }

    /// Le côté « avant » de la paire pilotée : mêmes nom et lieu que la mesure
    /// d'après, la ferme chargée dans la session du rapport (M9).
    private func beforeDraft(_ then: GuidedPlanDraft) -> GuidedPlanDraft {
        GuidedPlanDraft(name: then.name, role: .before, location: then.location, pairedWith: nil,
                        saveName: GuidedPilotSaveChoice.save(session: report.after.session, loads: store.loads,
                                                             available: viewModel.saves.map(\.folderName)))
    }

    /// Un identifiant que `target` résout vers ce dossier (un pack n'en a pas, ses composants si).
    private func pilotModId(_ mod: ModItem) -> String {
        mod.components.first { !$0.uniqueId.isEmpty }?.uniqueId ?? mod.uniqueId
    }

    private func startPilot(_ draft: GuidedPlanDraft, gesture: GuidedPilotGesture, changeLabel: String) {
        guard draft.saveName != nil else {
            viewModel.reloadSaves()
            message = localization.L(L10n.PerformancePilot.noSave)
            return
        }
        if let refusal = GuidedPilotLive.refusal(for: gesture, viewModel) {
            message = PerformanceBenchmarkSheet.text(for: refusal, localization: localization)
            return
        }
        Task {
            let started = await viewModel.pilot.start(draft: draft, gesture: gesture, changeLabel: changeLabel)
            message = started ? nil : PerformancePilotStatus.refusalText(viewModel.pilot.lastRefusal, localization: localization)
        }
    }

    private func prepareMeasure(_ draft: GuidedPlanDraft) {
        do {
            try store.prepare(draft)
            message = nil
        } catch {
            message = String(format: localization.L(L10n.Performance.guidedWriteFailed), error.localizedDescription)
        }
    }

    private func name(_ modId: String) -> String {
        PerformanceFormatting.modName(modId, viewModel: viewModel)
    }
}
