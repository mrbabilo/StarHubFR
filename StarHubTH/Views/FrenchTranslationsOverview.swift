import Charts
import SwiftUI

/// La répartition des mods traduisibles par statut (audit UX 2026-10-02) :
/// un anneau, le total au centre, et une légende dont chaque ligne mène à
/// sa section — un chiffre de synthèse conduit toujours quelque part.
struct FrenchTranslationsOverview: View {
    struct Slice: Identifiable {
        /// La clé L10n du titre de section, aussi son identifiant de défilement.
        let key: String
        let count: Int
        var id: String { key }
    }

    let slices: [Slice]
    let L: (String) -> String
    let select: (String) -> Void

    /// Couleur et glyphe d'un statut : un sens par couleur (jetons
    /// sémantiques), le glyphe pour qui ne distingue pas les teintes.
    static func style(for key: String) -> (color: Color, icon: String) {
        switch key {
        case L10n.FrTranslations.sectionUpdates:     return (AppDesign.Color.info, "arrow.up.circle.fill")
        case L10n.FrTranslations.sectionAvailable:   return (AppDesign.Color.accent, "arrow.down.circle.fill")
        case L10n.FrTranslations.sectionFailed:      return (AppDesign.Color.error, "xmark.octagon.fill")
        case L10n.FrTranslations.sectionUnverified:  return (AppDesign.Color.warning, "questionmark.circle.fill")
        case L10n.FrTranslations.sectionInstalled:   return (AppDesign.Color.success, "checkmark.circle.fill")
        case L10n.FrTranslations.sectionNone:        return (AppDesign.Color.paused, "minus.circle.fill")
        default:                                     return (Color.secondary.opacity(AppDesign.Opacity.disabled), "circle.dashed")
        }
    }

    var body: some View {
        let visible = slices.filter { $0.count > 0 }
        let total = visible.reduce(0) { $0 + $1.count }
        HStack(alignment: .center, spacing: AppDesign.Spacing.lg) {
            Chart(visible) { slice in
                SectorMark(angle: .value("count", slice.count),
                           innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(Self.style(for: slice.key).color.gradient)
            }
            .chartLegend(.hidden)
            .frame(width: 104, height: 104)
            .overlay {
                Text("\(total)")
                    .font(.system(size: AppDesign.Font.scaled(22), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .animation(Motion.animation(.smooth), value: visible.map(\.count))
            .accessibilityLabel(L(L10n.FrTranslations.chartLabel))

            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                ForEach(visible) { slice in
                    let style = Self.style(for: slice.key)
                    Button { select(slice.key) } label: {
                        Label {
                            Text(String(format: L(slice.key), slice.count))
                                .font(AppDesign.Font.footnote)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: style.icon).foregroundStyle(style.color)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
