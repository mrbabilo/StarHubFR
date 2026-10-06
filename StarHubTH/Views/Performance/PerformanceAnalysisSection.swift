import SwiftUI

/// L'analyse (spec §3d) : conclusion, confiance, preuves — une ligne par
/// règle qui a joué —, une recommandation et son geste. Chaque geste :
/// confirmation, refusé si le jeu tourne (vérifié au clic), réversible.
struct PerformanceAnalysisSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    let report: ProbePerformanceReport
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
                        sideTitle(report.before), sideTitle(report.after)))
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
                    Text("· " + line(evidence)).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                }
            }
            Text(localization.L(L10n.Performance.contextual))
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
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

    // MARK: Textes

    private var conclusion: String {
        report.metrics[.frameP50].map { PerformanceMetricText.outcome($0.outcome, localization) }
            ?? localization.L(L10n.PerformanceEvidence.unavailable)
    }

    /// Le nom court d'un côté : le nom de la mesure guidée, sinon la date.
    private func sideTitle(_ side: ProbeSide) -> String {
        if let measurement = side.measurement { return measurement.name }
        guard let start = side.start else { return "—" }
        return start.formatted(date: .abbreviated, time: .shortened)
    }

    /// Même glyphe et même teinte que le verdict de tête : ils viennent du
    /// même verdict (`ProbeAnalysis`, étape 1).
    private var conclusionLabel: some View {
        let (icon, tint): (String, Color) = {
            switch analysis.direction {
            case .faster: return ("hare", AppDesign.Color.success)
            case .slower: return ("tortoise", AppDesign.Color.warning)
            case .noDifference: return ("equal", .primary)
            case .inconclusive: return ("questionmark", .primary)
            }
        }()
        return Label(conclusion, systemImage: icon)
            .font(AppDesign.Font.body(.semibold)).foregroundColor(tint)
    }

    private var confidenceBadge: some View {
        let (icon, tint): (String, Color) = {
            switch analysis.confidence {
            // Pas de vert : il dit « mieux », pas « sûr ».
            case .high: return ("checkmark.seal.fill", AppDesign.Color.accent)
            case .medium: return ("circle.lefthalf.filled", .secondary)
            case .low: return ("exclamationmark.circle", .secondary)
            }
        }()
        return PerformanceBadge(label: confidence, systemImage: icon, tint: tint)
    }

    private var confidence: String {
        switch analysis.confidence {
        case .high: return localization.L(L10n.Performance.confidenceHigh)
        case .medium: return localization.L(L10n.Performance.confidenceMedium)
        case .low: return localization.L(L10n.Performance.confidenceLow)
        }
    }

    private func line(_ evidence: ProbeAnalysisResult.Evidence) -> String {
        switch evidence {
        case .comparableMinutes(let a, let b, let same):
            let suffix = same ? ", " + localization.L(L10n.Performance.sameLocations).lowercased() : ""
            return String(format: localization.L(L10n.Performance.evidenceMinutes), a, b, suffix)
        case .singleChange(let modId):
            return String(format: localization.L(L10n.Performance.evidenceSingleChange), name(modId))
        case .changeCount(let count):
            return String(format: localization.L(L10n.Performance.evidenceChangeCount), count)
        case .directCost(let modId, let delta):
            return String(format: localization.L(L10n.Performance.evidenceDirectCost), name(modId),
                          delta.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())))
        case .indirectShare(let share):
            return String(format: localization.L(L10n.Performance.evidenceIndirect), Int((share * 100).rounded()))
        case .probeChanged: return localization.L(L10n.Performance.evidenceProbe)
        case .envelopesAsymmetric: return localization.L(L10n.Performance.evidenceEnvelopes)
        case .cleanMeasurement: return localization.L(L10n.Performance.evidenceClean)
        case .excludedMinutes(let a, let b):
            return String(format: localization.L(L10n.Performance.evidenceExcluded), counts(a), counts(b))
        case .frameWorkUnchanged: return localization.L(L10n.Performance.evidenceFrameWork)
        case .noisyMeasurement: return localization.L(L10n.Performance.evidenceNoisy)
        }
    }

    private func counts(_ exclusions: [ProbeExclusionReason: Int]) -> String {
        exclusions.isEmpty ? "—" : exclusions.sorted { $0.value > $1.value }
            .map { "\(reasonName($0.key)) ×\($0.value)" }.joined(separator: ", ")
    }

    private func reasonName(_ reason: ProbeExclusionReason) -> String {
        PerformanceFormatting.reasonName(reason, localization)
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
    private func action(_ title: String, detail: String? = nil, button: String, gesture: PendingAction?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SplitRow {
                Text(title).font(AppDesign.Font.body(.medium))
            } trailing: {
                if let gesture {
                    AdaptiveLabels {
                        Button { pending = gesture } label: { Label(localization.L(button), systemImage: "arrow.right.circle") }
                            .help(localization.L(button)).clickableCursor()
                    }
                }
            }
            if let detail {
                Text(detail).font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
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
              let mod = ProbePerformanceActions.target(modId: modId, in: mods)
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
