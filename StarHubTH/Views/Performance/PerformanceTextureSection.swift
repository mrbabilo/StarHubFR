import SwiftUI

/// D4-T6 — la mémoire retenue en textures, par mod ou pack : dix premiers,
/// puis tout, et ce qui ne revient à aucun mod installé. Hors note d'impact.
/// Ne calcule rien : tout vient de `ModImpactStore` (relu par
/// `PerformanceImpactSection`, son voisin dans l'onglet).
struct PerformanceTextureSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State private var showAll = false

    private var store: ModImpactStore { viewModel.modImpactStore }
    private var language: String { localization.currentLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(localization.L(L10n.PerformanceTextures.subtitle))
                .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            switch store.status {
            case .idle, .loading:
                ProgressView().controlSize(.small)
            case .unreadableHistory:
                StateCard(icon: AppDesign.Status.warning.symbol,
                          text: localization.L(L10n.Performance.impactUnreadable), actionTitle: localization.L(L10n.Mods.revealInFinder)) {
                if let url = store.historyFileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            case .noProbe, .ready:
                if store.textureRows.isEmpty && store.textureRemainder == nil {
                    StateCard(icon: "photo.stack", text: localization.L(L10n.PerformanceTextures.empty), actionTitle: nil) {}
                } else {
                    list
                }
            }
        }
        .task {
            if store.status == .idle {
                await store.reload(mods: viewModel.mods, gameRunning: viewModel.isGameRunning(), gameDir: viewModel.gameDir)
            }
        }
    }

    private func megabytes(_ value: Double) -> String {
        String(format: localization.L(L10n.PerformanceTextures.value),
               ModImpactFormat.number(value, language: language))
    }

    private var list: some View {
        let rows = store.textureRows
        let shown = showAll ? rows : Array(rows.prefix(10))
        return VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            LazyVStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                ForEach(shown) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        SplitRow {
                            Button(row.name) { viewModel.navigationStore.openModDetail(folderName: row.id) }
                                .buttonStyle(.hoverLink).help(row.name)
                        } trailing: { Text(megabytes(row.mb)).monospacedDigit() }
                        ProgressView(value: row.mb, total: max(rows.first?.mb ?? 1, 1))
                            .tint(AppDesign.Chart.before)
                            .accessibilityLabel(localization.L(L10n.PerformanceTextures.title))
                            .accessibilityValue(megabytes(row.mb))
                        Text(String(format: localization.L(L10n.PerformanceEvidence.historyCoverage),
                                    row.version ?? "—", row.sourceCount,
                                    row.lastMeasured.formatted(date: .abbreviated, time: .shortened)))
                            .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                        if !row.currentVersionMeasured {
                            Text(localization.L(L10n.PerformanceEvidence.historical))
                                .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if rows.count > 10 {
                Button(showAll ? localization.L(L10n.Performance.impactShowLess)
                               : String(format: localization.L(L10n.Performance.impactShowAll), rows.count)) { showAll.toggle() }
                    .buttonStyle(.hoverLink)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let remainder = store.textureRemainder {
                    Text(String(format: localization.L(L10n.PerformanceTextures.remainder),
                                ModImpactFormat.number(remainder.mb, language: language),
                                remainder.date.formatted(date: .abbreviated, time: .shortened)))
                        .help(String(format: localization.L(L10n.PerformanceTextures.remainderHelp),
                                     remainder.owners.joined(separator: ", ")))
                }
                Text(localization.L(L10n.PerformanceTextures.partial))
            }
            .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
