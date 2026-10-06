import SwiftUI

/// D4-T9 — ce que la scène du lieu dit des deux côtés d'une comparaison :
/// rien si aucune minute ne porte de scène (sonde < 0.9.21, minutes hors
/// monde), « comparable » quand la mesure existe mais ne sépare pas, les
/// compteurs qui séparent sinon (« meubles 312 → 424 (+36 %) »).
struct PerformanceSceneNote: View {
    @ObservedObject var localization: LocalizationStore
    let before: [ProbeMinute]
    let after: [ProbeMinute]

    var body: some View {
        let assessment = ProbeScene.assess(before: before, after: after)
        let text: String = {
            switch assessment {
            case .unknown: return localization.L(L10n.PerformanceEvidence.sceneUnknown)
            case .similar: return localization.L(L10n.Performance.sceneComparable)
            case .different(let differences): return differences.compactMap(sceneText).joined(separator: ", ")
            }
        }()
        Text(text).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// « meubles 312 → 424 (+36 %) » ; une clé sans libellé (sonde future) est
    /// sautée plutôt qu'affichée brute.
    private func sceneText(_ difference: ProbeScene.Difference) -> String? {
        guard let name = PerformanceFormatting.sceneName(difference.key, localization) else { return nil }
        let sign = (difference.percent ?? 0) >= 0 ? "+" : "−"
        let before = PerformanceFormatting.number(difference.medianBefore, fraction: 0)
        let after = PerformanceFormatting.number(difference.medianAfter, fraction: 0)
        let percent = PerformanceFormatting.number(abs(difference.percent ?? 0), fraction: 0)
        return "\(name) \(before) → \(after)" + (difference.percent == nil ? "" : " (\(sign)\(percent) %)")
    }
}
