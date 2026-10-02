import SwiftUI

/// Ce que l'analyse des raccourcis a écarté, en pied de page : mods en
/// pause, documentations de raccourcis (règle du catalogue), mods de
/// remappage. **Une exclusion muette est un mensonge par omission** (défaut
/// 1, tâche 6 — ModShortcutReferenceHub pesait 12 des 29 collisions) : les
/// notes restent visibles, jamais repliées, et le compte vient avant les
/// noms — la troncature au milieu peut couper les noms, jamais le nombre.
/// La chaîne parle du champ, pas du mod (ronde de correction 1).
struct KeybindExclusionNotes: View {
    let report: KeybindScanner.KeybindReport
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        let notes = lines
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                ForEach(notes, id: \.self) { note in
                    Label(note, systemImage: "line.3.horizontal.decrease.circle")
                        .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(.horizontal, AppDesign.Spacing.lg)
        }
    }

    private var lines: [String] {
        var out: [String] = []
        if report.pausedIgnored > 0 {
            out.append(String(format: localization.L(L10n.Keybinds.pausedNote), report.pausedIgnored))
        }
        if !report.catalogModsIgnored.isEmpty {
            out.append(String(format: localization.L(L10n.Keybinds.catalogNote),
                              report.catalogModsIgnored.count,
                              report.catalogModsIgnored.joined(separator: ", ")))
        }
        if !report.remapModsIgnored.isEmpty {
            // C4-T9 — le nom porte la fonction (« mod de remap »).
            out.append(String(format: localization.L(L10n.Keybinds.remapNote),
                              report.remapModsIgnored.joined(separator: ", ")))
        }
        return out
    }
}
