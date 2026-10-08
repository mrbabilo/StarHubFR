import SwiftUI

/// Ce qui est cassé dans les raccourcis des mods, chiffré avant les listes :
/// la gravité se lit d'un coup d'œil (audit UX 2026-10-02). Refonte du même
/// soir : une tuile à zéro se tait, et chaque tuile **mène** à son groupe —
/// `open` reçoit la clé du groupe, l'ouvre et y défile.
struct KeybindSummaryTiles: View {
    let report: KeybindScanner.KeybindReport
    let L: (String) -> String
    let open: (String) -> Void

    private struct Tile: Identifiable {
        let id: String
        let icon: String
        let value: Int
        let label: String
        let tint: Color
    }

    private var tiles: [Tile] {
        [Tile(id: "collisions", icon: "keyboard", value: report.collisions.count,
              label: L(L10n.Keybinds.tileCollisions), tint: KeybindConflictStyle.color(.mods)),
         Tile(id: "gamepad", icon: "gamecontroller.fill", value: report.gamepadOff ? 0 : report.gamepadCollisions.count,
              label: L(L10n.Keybinds.tileGamepad), tint: KeybindConflictStyle.color(.mods)),
         Tile(id: "game", icon: KeybindConflictStyle.glyph, value: report.gameConflicts.count,
              label: L(L10n.Keybinds.tileGame), tint: KeybindConflictStyle.color(.game)),
         Tile(id: "unrecognized", icon: AppDesign.Status.unknown.symbol, value: report.unrecognized.count,
              label: L(L10n.Keybinds.tileUnrecognized), tint: AppDesign.Color.warning)]
            .filter { $0.value > 0 }
    }

    var body: some View {
        WrapHStack(spacing: AppDesign.Spacing.sm, lineSpacing: AppDesign.Spacing.sm) {
            ForEach(tiles) { tile in
                MetricTile(icon: tile.icon, value: tile.value, label: tile.label,
                           tint: tile.tint) { open(tile.id) }
            }
        }
    }
}
