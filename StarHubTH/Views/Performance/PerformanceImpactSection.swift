import SwiftUI

/// D5-C — le classement « Impact par mod » : dix premiers, puis tout. Chaque
/// ligne ouvre la fiche (retour en un clic, `detailOpenedByJump`). Ne calcule
/// rien : tout vient de `ModImpactStore`.
struct PerformanceImpactSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State private var showAll = false
    @State private var axis: ModImpactAxis = .fps
    /// Arrivée depuis la liste ou la fiche (lot D, S8) : ce mod en tête.
    var focus: String?

    private var store: ModImpactStore { viewModel.modImpactStore }
    private var language: String { localization.currentLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(localization.L(L10n.Performance.impactCardTitle)).font(AppDesign.Font.headline(.semibold))
            Text(localization.L(L10n.Performance.impactCardSubtitle))
                .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            switch store.status {
            case .idle, .loading:
                ProgressView().controlSize(.small)
            case .noProbe:
                StateCard(icon: "gauge.with.dots.needle.0percent",
                          text: localization.L(L10n.Performance.impactEmptyProbe), actionTitle: nil) {}
            case .unreadableHistory:
                StateCard(icon: AppDesign.Status.warning.symbol,
                          text: localization.L(L10n.Performance.impactUnreadable), actionTitle: localization.L(L10n.Mods.revealInFinder)) {
                if let url = store.historyFileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            case .ready:
                list
            }
        }
        // Les relectures au retour (onglet, app, jeu quitté) sont celles de
        // `PerformanceView.reloadAll` : une seule par événement.
        .task { if store.status == .idle { await store.reload(mods: viewModel.mods, gameRunning: viewModel.isGameRunning(), gameDir: viewModel.gameDir) } }
    }

    private var list: some View {
        var ranked = store.performanceRows[axis] ?? []
        if let focus, let index = ranked.firstIndex(where: { $0.id == focus }) {
            ranked.insert(ranked.remove(at: index), at: 0)
        }
        let shown = showAll ? ranked : Array(ranked.prefix(10))
        return VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(localization.L(L10n.PerformanceEvidence.historyNote)).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            Picker(localization.L(L10n.PerformanceEvidence.history), selection: $axis) {
                ForEach(ModImpactAxis.allCases, id: \.self) { Text(axisName($0)).tag($0) }
            }.pickerStyle(.menu)
            LazyVStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                ForEach(shown) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        SplitRow {
                            Button(row.name) { viewModel.navigationStore.openModDetail(folderName: row.id) }
                                .buttonStyle(.hoverLink).help(row.name)
                        } trailing: { Text(valueText(row.value)).monospacedDigit() }
                        if let value = row.value {
                            ProgressView(value: value, total: max(ranked.first?.value ?? 1, 1))
                                .tint(AppDesign.Chart.before).accessibilityLabel(axisName(axis))
                                .accessibilityValue(valueText(value))
                        }
                        Text(String(format: localization.L(L10n.PerformanceEvidence.historyCoverage),
                                    row.version ?? "—", row.sourceCount,
                                    row.lastMeasured?.formatted(date: .abbreviated, time: .shortened) ?? "—"))
                            .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                        if !row.currentVersionMeasured && row.value != nil {
                            Text(localization.L(L10n.PerformanceEvidence.historical)).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if ranked.count > 10 {
                Button(showAll ? localization.L(L10n.Performance.impactShowLess)
                               : String(format: localization.L(L10n.Performance.impactShowAll), ranked.count)) { showAll.toggle() }
                    .buttonStyle(.hoverLink)
            }
            footer
        }
    }

    private func axisName(_ axis: ModImpactAxis) -> String {
        let key: String
        switch axis {
        case .fps: key = L10n.PerformanceEvidence.axisFps
        case .spikes: key = L10n.PerformanceEvidence.axisSpikes
        case .launch: key = L10n.PerformanceEvidence.axisLaunch
        case .save: key = L10n.PerformanceEvidence.axisSave
        case .alloc: key = L10n.PerformanceEvidence.axisAlloc
        }
        return localization.L(key)
    }

    private func valueText(_ value: Double?) -> String {
        guard let value else { return localization.L(L10n.PerformanceEvidence.unavailable) }
        let unit: String
        switch axis {
        case .fps: unit = "ms"
        case .launch, .save: unit = "s"
        case .spikes: unit = "%"
        case .alloc: unit = localization.L(L10n.Performance.unitMB) + "/min"
        }
        return "\(PerformanceFormatting.number(axis == .launch || axis == .save ? value / 1000 : value, fraction: 2)) \(unit)"
    }

    private var footer: some View {
        return VStack(alignment: .leading, spacing: 2) {
            if let probe = store.probeMsPerFrame {
                Text(String(format: localization.L(L10n.Performance.impactProbeCost),
                            ModImpactFormat.number(probe, digits: 2, language: language)))
            }
            if store.lastSave == nil { Text(localization.L(L10n.Performance.impactSaveMissing)) }
        }
        .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
