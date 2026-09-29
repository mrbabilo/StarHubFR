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

    /// Un geste en attente de confirmation. `pause` porte, pour « Isoler »,
    /// le nom de la mesure à préparer ensuite (« Mettre en pause et mesurer »).
    private enum PendingAction: Identifiable {
        case pause(ModItem, thenMeasure: String?), backups(ModItem), revertConfig(ModItem, sha: String),
             prepare(String)
        var id: String {
            switch self {
            case .pause(let m, _): return "pause|\(m.folderName)"
            case .backups(let m): return "backups|\(m.folderName)"
            case .revertConfig(let m, let sha): return "config|\(m.folderName)|\(sha)"
            case .prepare(let name): return "prepare|\(name)"
            }
        }
    }

    private var analysis: ProbeAnalysisResult { report.analysis }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(localization.L(L10n.Performance.sectionAnalysis)).font(AppDesign.Font.headline(.semibold))
            Text(conclusion).font(AppDesign.Font.body(.semibold))
            Text(confidence).font(AppDesign.Font.footnote).foregroundColor(.secondary)
            recommendation
            ForEach(Array(analysis.evidence.enumerated()), id: \.offset) { _, evidence in
                Text("· " + line(evidence)).font(AppDesign.Font.footnote).foregroundColor(.secondary)
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
        }
    }

    // MARK: Textes

    private var conclusion: String {
        let percent: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(1))) }
        switch analysis.direction {
        case .slower(let p): return String(format: localization.L(L10n.Performance.conclusionSlower), percent(p))
        case .faster(let p): return String(format: localization.L(L10n.Performance.conclusionFaster), percent(p))
        case .noDifference: return localization.L(L10n.Performance.conclusionNone)
        case .inconclusive: return localization.L(L10n.Performance.conclusionInconclusive)
        }
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
        }
    }

    private func counts(_ exclusions: [ProbeExclusionReason: Int]) -> String {
        exclusions.isEmpty ? "—" : exclusions.sorted { $0.value > $1.value }
            .map { "\(reasonName($0.key)) ×\($0.value)" }.joined(separator: ", ")
    }

    private func reasonName(_ reason: ProbeExclusionReason) -> String {
        switch reason {
        case .unfocused: return localization.L(L10n.Performance.reasonUnfocused)
        case .title: return localization.L(L10n.Performance.reasonTitle)
        case .menuOpen: return localization.L(L10n.Performance.reasonMenu)
        case .night: return localization.L(L10n.Performance.reasonNight)
        case .firstAfterTitle: return localization.L(L10n.Performance.reasonLoading)
        }
    }

    // MARK: Recommandation et gestes

    @ViewBuilder
    private var recommendation: some View {
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
            let where_ = location.map { "\($0) : " } ?? ""
            action(localization.L(L10n.Performance.recRerun),
                   detail: String(format: localization.L(L10n.Performance.recRerunDetail), where_, missing),
                   button: L10n.Performance.actionPrepareMeasure,
                   gesture: .prepare(localization.L(L10n.Performance.recRerun) + (location.map { " — \($0)" } ?? "")))
        }
    }

    /// Un geste sans cible (mod plus installé) ne s'affiche pas (Review Focus 5).
    private func action(_ title: String, detail: String? = nil, button: String, gesture: PendingAction?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SplitRow {
                Text(title).font(AppDesign.Font.body(.medium))
            } trailing: {
                if let gesture {
                    Button(localization.L(button)) { pending = gesture }
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
        let measureName = String(format: localization.L(L10n.Performance.isolateMeasureName), name(change.modId))
        let gesture: PendingAction? = {
            if case .configChanged = change.kind { return revertGesture(modId: change.modId, mods: mods) }
            return ProbePerformanceActions.target(modId: change.modId, in: mods)
                .map { PendingAction.pause($0, thenMeasure: measureName) }
        }()
        return action("· " + name(change.modId), button: L10n.Performance.actionPause, gesture: gesture)
    }

    private func revertGesture(modId: String, mods: [ModItem]) -> PendingAction? {
        guard let change = report.diff?.changes.first(where: {
                  $0.modId.caseInsensitiveCompare(modId) == .orderedSame }),
              case .configChanged(let old?, _) = change.kind,
              let mod = ProbePerformanceActions.target(modId: modId, in: mods)
        else { return nil }
        return .revertConfig(mod, sha: old)
    }

    private func confirmTitle(_ gesture: PendingAction) -> String {
        let label: String
        switch gesture {
        case .pause(let m, _): label = "\(localization.L(L10n.Performance.actionPause)) — \(m.name)"
        case .backups(let m): label = "\(localization.L(L10n.Performance.actionBackups)) — \(m.name)"
        case .revertConfig(let m, _): label = "\(localization.L(L10n.Performance.actionRevertConfig)) — \(m.name)"
        case .prepare(let name): label = "\(localization.L(L10n.Performance.actionPrepareMeasure)) — \(name)"
        }
        return String(format: localization.L(L10n.Performance.confirmTitle), label)
    }

    /// Jeu vérifié **au clic** : pause et réglage refusés jeu lancé ; la
    /// préparation d'une mesure ne touche à rien (elle remplit le nom, la
    /// mesure démarre jeu lancé depuis l'en-tête).
    private func perform(_ gesture: PendingAction) {
        pending = nil
        switch gesture {
        case .prepare(let name):
            store.pendingMeasurementName = name
            message = nil
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
            if let thenMeasure { store.pendingMeasurementName = thenMeasure }
            message = nil
        case .revertConfig(let mod, let sha):
            let outcome = ProbePerformanceActions.revertConfig(
                of: mod, toSha: sha, configsDirectory: store.configsDirectory, gameDir: viewModel.gameDir,
                gameRunning: false, backups: ModConfigBackupManager.shared)
            switch outcome {
            case .reverted: message = localization.L(L10n.Performance.revertDone)
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

    private func name(_ modId: String) -> String {
        viewModel.scanStore.mods.flattenedMods
            .first { $0.uniqueId.caseInsensitiveCompare(modId) == .orderedSame }?.name ?? modId
    }
}
