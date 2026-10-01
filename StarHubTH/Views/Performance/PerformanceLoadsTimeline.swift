import SwiftUI

/// D5-B — les étapes d'un chargement en chronologie : une ligne par étape,
/// sa barre posée à son jalon de départ (`ProbeLoadSpan.startMs`), part des
/// mods en plein, reste en pâle. La colonne de droite redit les chiffres :
/// la part non attribuée ne se lit jamais par la seule couleur.
struct PerformanceLoadsTimeline: View {
    @ObservedObject var localization: LocalizationStore
    let breakdown: ProbeLoadBreakdown

    private static let nameWidth: CGFloat = 150
    private static let valueWidth: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            Text(localization.L(L10n.Performance.loadsSteps)).font(AppDesign.Font.body(.semibold))
            WrapHStack(spacing: AppDesign.Spacing.md) {
                PerformanceLoadsSwatch(color: AppDesign.Chart.partStrong,
                                       label: localization.L(L10n.Performance.loadsLegendMods))
                PerformanceLoadsSwatch(color: AppDesign.Chart.partLight,
                                       label: localization.L(L10n.Performance.loadsLegendRest))
            }
            ForEach(breakdown.spans) { span in row(span) }
        }
    }

    /// Fin de la dernière étape positionnée : l'échelle commune des barres.
    private var end: Double {
        breakdown.spans.compactMap { span in span.startMs.map { $0 + span.ms } }.max() ?? 0
    }

    private func row(_ span: ProbeLoadSpan) -> some View {
        HStack(alignment: .center, spacing: AppDesign.Spacing.sm) {
            Text(localization.L(L10n.Performance.span(span.name)))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .frame(width: Self.nameWidth, alignment: .leading)
            bar(span).frame(height: 10)
            VStack(alignment: .trailing, spacing: 0) {
                Text(PerformanceLoadsSection.duration(span.ms)).monospacedDigit()
                if showsUnattributed(span) {
                    Text(String(format: localization.L(L10n.Performance.loadsUnattributedShort),
                                PerformanceLoadsSection.duration(span.unattributedMs)))
                        .font(AppDesign.Font.caption).foregroundColor(.secondary).monospacedDigit()
                        .lineLimit(2).multilineTextAlignment(.trailing)
                }
            }
            .frame(width: Self.valueWidth, alignment: .trailing)
        }
        .font(AppDesign.Font.footnote)
        .helpIfPresent(showsUnattributed(span) ? localization.L(L10n.Performance.loadsUnattributed) : nil)
    }

    private func showsUnattributed(_ span: ProbeLoadSpan) -> Bool {
        span.name != .waitingForPlayer && span.ms > 0 && span.unattributedMs / span.ms > 0.05
    }

    /// Sans jalon de départ, pas de barre : une position inventée mentirait.
    private func bar(_ span: ProbeLoadSpan) -> some View {
        GeometryReader { geometry in
            if let start = span.startMs, end > 0 {
                let scale = geometry.size.width / end
                let width = max(2, span.ms * scale)
                let mods = span.name == .waitingForPlayer ? 0 : min(span.ms, span.attributedMs) * scale
                HStack(spacing: 0) {
                    if span.name == .waitingForPlayer {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(AppDesign.Opacity.light))
                    } else {
                        if mods >= 1 {
                            RoundedRectangle(cornerRadius: 2).fill(AppDesign.Chart.partStrong)
                                .frame(width: mods)
                        }
                        if width - mods >= 1 {
                            // Écart de 2 pt entre les parts, lisible sans la couleur.
                            RoundedRectangle(cornerRadius: 2).fill(AppDesign.Chart.partLight)
                                .padding(.leading, mods >= 1 ? 2 : 0)
                        }
                    }
                }
                .frame(width: width)
                .offset(x: start * scale)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Une pastille de légende : la couleur porte l'identité, le texte reste à l'encre.
struct PerformanceLoadsSwatch: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(label).font(AppDesign.Font.caption).foregroundColor(.secondary).lineLimit(1)
        }
    }
}
