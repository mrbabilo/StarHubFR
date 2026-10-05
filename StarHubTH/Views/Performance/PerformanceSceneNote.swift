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
        if ProbeScene.hasData(before) || ProbeScene.hasData(after) {
            let differences = ProbeScene.differences(before: before, after: after)
            let body = differences.isEmpty
                ? localization.L(L10n.Performance.sceneComparable)
                : differences.compactMap(sceneText).joined(separator: ", ")
            Text("\(localization.L(L10n.Performance.sceneLabel)) — \(body)")
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// « meubles 312 → 424 (+36 %) » ; une clé sans libellé (sonde future) est
    /// sautée plutôt qu'affichée brute.
    private func sceneText(_ difference: ProbeScene.Difference) -> String? {
        guard let name = PerformanceFormatting.sceneName(difference.key, localization) else { return nil }
        let sign = difference.percent >= 0 ? "+" : "−"
        let before = PerformanceFormatting.number(difference.medianBefore, fraction: 0)
        let after = PerformanceFormatting.number(difference.medianAfter, fraction: 0)
        let percent = PerformanceFormatting.number(abs(difference.percent), fraction: 0)
        return "\(name) \(before) → \(after) (\(sign)\(percent) %)"
    }
}
