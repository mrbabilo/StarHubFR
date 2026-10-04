import SwiftUI

/// D5-C — l'impact mesuré d'un mod, sur sa ligne de liste : l'icône et la
/// couleur de la carte Impact (`ModImpactBadge.visuals`), la note au survol
/// avec l'axe dominant. Portée par les seules classes élevée et moyenne —
/// 29 lignes sur le parc de référence ; marquer aussi les 84 « faible » et
/// les 172 négligeables en ferait du bruit. Non cliquable : la destination
/// existe au clic de rangée, la fiche portant la section d'impact en entier.
struct ImpactListBadge: View {
    let shown: ModImpactVersionStats
    let impactClass: ModImpactClass
    @ObservedObject var localization: LocalizationStore

    /// Note + axe qui pèse le plus dans la note (poids × part) — « Trame :
    /// 43 % du total » dit ce qui coûte, pas seulement combien.
    private var helpText: String {
        let visuals = ModImpactBadge.visuals(for: impactClass)
        var lines = ["\(localization.L(visuals.key)) · "
            + String(format: localization.L(L10n.Performance.impactScore),
                     ModImpactFormat.score(shown.score))]
        let contribution = { (pair: (key: ModImpactAxis, value: Double)) in
            (ModImpact.weights[pair.key] ?? 0) * pair.value
        }
        if let top = shown.shares.max(by: { contribution($0) < contribution($1) }) {
            lines.append(String(format: localization.L(L10n.Performance.impactAxisDetail),
                                ModImpactBadge.axisLabel(top.key, localization: localization),
                                ModImpactFormat.percent(top.value, language: localization.currentLanguage),
                                shown.sourceCount))
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        let visuals = ModImpactBadge.visuals(for: impactClass)
        Image(systemName: visuals.icon)
            .font(AppDesign.Font.iconXS)
            .foregroundStyle(visuals.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(visuals.color.opacity(AppDesign.Opacity.medium)))
            // Même cible de 18 pt que l'anomalie voisine : en dessous, macOS
            // n'accorde plus son infobulle (le curseur n'y reste pas assez).
            .frame(minWidth: 18, minHeight: 18)
            .contentShape(.rect)
            .help(helpText)
            .accessibilityLabel(helpText)
    }
}
