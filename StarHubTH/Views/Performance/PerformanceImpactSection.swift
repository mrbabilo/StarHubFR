import SwiftUI

/// D5-C — le classement « Impact par mod » : dix premiers, puis tout. Chaque
/// ligne ouvre la fiche (retour en un clic, `detailOpenedByJump`). Ne calcule
/// rien : tout vient de `ModImpactStore`.
struct PerformanceImpactSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State private var showAll = false

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
                StateCard(icon: "exclamationmark.triangle",
                          text: localization.L(L10n.Performance.impactUnreadable), actionTitle: nil) {}
            case .ready:
                list
            }
        }
        .task { if store.status == .idle { await reload() } }
        // L'onglet reste monté : relire au retour dans l'app seulement s'il est
        // affiché (patron `PerformanceView`).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if viewModel.navigationStore.diagnosticsSegment == .performance { Task { await reload() } }
        }
    }

    private func reload() async {
        await store.reload(mods: viewModel.mods, gameRunning: viewModel.isGameRunning(), gameDir: viewModel.gameDir)
    }

    @ViewBuilder
    private var list: some View {
        let ranked = store.ranking
        let shown = showAll ? ranked : Array(ranked.prefix(10))
        if ranked.isEmpty {
            StateCard(icon: "hourglass", text: localization.L(L10n.Performance.impactEmptyMod), actionTitle: nil) {}
        } else {
            ForEach(shown) { entry in row(entry) }
            if ranked.count > 10 {
                Button(showAll ? localization.L(L10n.Performance.impactShowLess)
                               : String(format: localization.L(L10n.Performance.impactShowAll), ranked.count)) {
                    showAll.toggle()
                }
                .buttonStyle(.hoverLink)
            }
        }
        footer
    }

    private func row(_ entry: ModImpactEntry) -> some View {
        let stats = entry.shown
        return HStack(alignment: .center, spacing: AppDesign.Spacing.sm) {
            ModImpactRadar(shares: stats?.shares ?? [:], size: 24, showsLabels: false,
                           label: { $0.rawValue }, detail: { $0.rawValue })
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                // Le dossier du mod lui-même, composant de pack compris :
                // `ModFocusResolver` le retrouve (H-T6c), et c'est sa fiche —
                // pas celle du pack, sans UniqueID — qui porte l'impact.
                Button(entry.name) { viewModel.navigationStore.openModDetail(folderName: entry.id) }
                    .buttonStyle(.hoverLink)
                .lineLimit(2).multilineTextAlignment(.leading)
                if entry.current == nil, let stats {
                    Text(String(format: localization.L(L10n.Performance.impactLastKnown),
                                ModImpactFormat.version(stats.version, localization: localization)))
                        .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: AppDesign.Spacing.sm)
            if let delta = entry.evolution {
                let icon = ModImpactFormat.evolutionIcon(delta)
                let text = ModImpactFormat.evolutionText(delta, previous: entry.previousVersion?.version,
                                                         localization: localization)
                Image(systemName: icon.name)
                    .foregroundStyle(icon.color)
                    .frame(width: 18, height: 18).contentShape(.rect)
                    .help(text)
                    .accessibilityLabel(text)
            }
            ModImpactBadge(localization: localization, impactClass: stats?.impactClass, score: stats?.score,
                           dimmed: entry.current == nil)
        }
    }

    private var footer: some View {
        let negligible = store.entries.filter { $0.isEnabled && $0.isNegligible }.count
        let unmeasured = store.entries.filter { $0.isEnabled && $0.shown == nil && !$0.isNegligible }.count
        return VStack(alignment: .leading, spacing: 2) {
            Text(String(format: localization.L(L10n.Performance.impactCardFooter), negligible, unmeasured))
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
