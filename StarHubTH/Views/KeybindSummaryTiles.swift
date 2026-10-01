import SwiftUI

/// Ce qui est cassé dans les raccourcis des mods, chiffré avant les listes :
/// la gravité se lit d'un coup d'œil (audit UX 2026-10-02). Les groupes
/// détaillés suivent juste en dessous, dans le même ordre.
struct KeybindSummaryTiles: View {
    let report: KeybindScanner.KeybindReport
    let L: (String) -> String

    var body: some View {
        WrapHStack(spacing: AppDesign.Spacing.sm, lineSpacing: AppDesign.Spacing.sm) {
            MetricTile(icon: "keyboard", value: report.collisions.count,
                       label: L(L10n.Keybinds.tileCollisions), tint: AppDesign.Color.error)
            MetricTile(icon: "gamecontroller.fill", value: report.gamepadCollisions.count,
                       label: L(L10n.Keybinds.tileGamepad), tint: AppDesign.Color.error)
            MetricTile(icon: "exclamationmark.triangle.fill", value: report.gameConflicts.count,
                       label: L(L10n.Keybinds.tileGame), tint: AppDesign.Color.warning)
            MetricTile(icon: "questionmark.circle.fill", value: report.unrecognized.count,
                       label: L(L10n.Keybinds.tileUnrecognized), tint: AppDesign.Color.warning)
        }
    }
}
