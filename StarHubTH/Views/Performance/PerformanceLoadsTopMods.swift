import SwiftUI

/// D5-B — les mods qui pèsent le plus sur un chargement : une barre par mod,
/// à l'échelle du plus lourd, découpée en chargement / démarrage / autre
/// quand la sonde les distingue. Le nom ouvre la fiche ; à droite, la pause
/// (ou le cadenas qui dit qui en dépend).
struct PerformanceLoadsTopMods: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let breakdown: ProbeLoadBreakdown
    let displayName: (String) -> String
    let requestPause: (ModItem, [String]) -> Void

    private static let nameWidth: CGFloat = 150
    private static let valueWidth: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            Text(localization.L(L10n.Performance.loadsTop)).font(AppDesign.Font.body(.semibold))
            if isSplit {
                WrapHStack(spacing: AppDesign.Spacing.md) {
                    PerformanceLoadsSwatch(color: AppDesign.Chart.partStrong,
                                           label: localization.L(L10n.Performance.loadsLegendLoad))
                    PerformanceLoadsSwatch(color: AppDesign.Chart.partMid,
                                           label: localization.L(L10n.Performance.loadsLegendEntry))
                    PerformanceLoadsSwatch(color: AppDesign.Chart.partLight,
                                           label: localization.L(L10n.Performance.loadsLegendOther))
                }
            }
            ForEach(breakdown.top) { total in row(total) }
        }
    }

    /// Une seule série (sauvegarde, sonde d'avant 0.8.0) : pas de légende,
    /// la barre prend la teinte pleine.
    private var isSplit: Bool { breakdown.top.contains { $0.loadMs >= 1 || $0.entryMs >= 1 } }

    private var heaviest: Double { breakdown.top.map(\.ms).max() ?? 0 }

    private func row(_ total: ProbeLoadModTotal) -> some View {
        let head = ProbePerformanceActions.target(modId: total.mod, in: viewModel.mods)
        let blockers = ProbePerformanceActions.pauseBlockers(modId: total.mod, in: viewModel.mods)
        return HStack(alignment: .center, spacing: AppDesign.Spacing.sm) {
            Button {
                if let head { viewModel.navigationStore.openModDetail(folderName: head.folderName) }
            } label: {
                Text(isContentPatcherPreparing(total) ? localization.L(L10n.Performance.loadsCpPreparing)
                                                      : displayName(total.mod))
                    .lineLimit(3).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.link)
            .disabled(head == nil)
            .frame(width: Self.nameWidth, alignment: .leading)
            bar(total).frame(height: 10)
                .helpIfPresent(partsText(total))
            Text(PerformanceLoadsSection.duration(total.ms)).monospacedDigit()
                .frame(width: Self.valueWidth, alignment: .trailing)
            action(head: head, blockers: blockers)
        }
        .font(AppDesign.Font.footnote)
    }

    @ViewBuilder
    private func action(head: ModItem?, blockers: ProbePerformanceActions.ProbePauseBlockers) -> some View {
        if !blockers.dependents.isEmpty {
            // Cible 18 × 18 avant `.help` : sur le glyphe nu, l'infobulle ne
            // s'affiche jamais.
            Image(systemName: "lock")
                .foregroundColor(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(.rect)
                .help(String(format: localization.L(L10n.Performance.loadsPauseBlocked),
                             blockers.dependents.prefix(3).joined(separator: ", ")))
        } else if let head, head.isEnabled {
            Button { requestPause(head, blockers.siblings) } label: {
                Image(systemName: "pause.circle")
                    .frame(width: 18, height: 18)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .help(localization.L(L10n.Performance.actionPause))
            .accessibilityLabel(localization.L(L10n.Performance.actionPause))
        } else {
            Color.clear.frame(width: 18, height: 18)
        }
    }

    private func bar(_ total: ProbeLoadModTotal) -> some View {
        GeometryReader { geometry in
            let scale = heaviest > 0 ? geometry.size.width / heaviest : 0
            let load = total.loadMs * scale
            let entry = total.entryMs * scale
            let other = max(0, total.ms - total.loadMs - total.entryMs) * scale
            // Écart de 2 pt entre les parts, lisible sans la couleur.
            HStack(spacing: 2) {
                if isSplit {
                    if load >= 1 { part(AppDesign.Chart.partStrong, load) }
                    if entry >= 1 { part(AppDesign.Chart.partMid, entry) }
                    if other >= 1 { part(AppDesign.Chart.partLight, other) }
                } else {
                    part(AppDesign.Chart.partStrong, max(2, total.ms * scale))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func part(_ color: Color, _ width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: width)
    }

    /// Les chiffres des parts, en infobulle sur la barre.
    private func partsText(_ total: ProbeLoadModTotal) -> String? {
        if total.loadMs >= 1 {
            return String(format: localization.L(L10n.Performance.loadsLoadPart),
                          PerformanceLoadsSection.duration(total.loadMs), PerformanceLoadsSection.duration(total.entryMs))
        }
        if total.entryMs >= 1 {
            return String(format: localization.L(L10n.Performance.loadsEntryPart),
                          PerformanceLoadsSection.duration(total.entryMs))
        }
        return nil
    }

    /// Le premier UpdateTicked de Content Patcher (chargement des packs)
    /// ne passe pas par RecordSection : étiquette propre sur son span.
    private func isContentPatcherPreparing(_ total: ProbeLoadModTotal) -> Bool {
        let cp = PerformanceLoadsSection.contentPatcherId
        guard breakdown.record.kind == .launch,
              total.mod.caseInsensitiveCompare(cp) == .orderedSame else { return false }
        let firstTick = breakdown.spans.first { $0.name == .firstTick }?.costs ?? []
        return firstTick.contains { $0.mod.caseInsensitiveCompare(cp) == .orderedSame }
    }
}
