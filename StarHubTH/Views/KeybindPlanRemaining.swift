import SwiftUI

/// Plan de raccourcis — ce que la nouvelle analyse trouve après une
/// application ou une annulation (spec 2026-10-15 §5). Fichier à part :
/// la feuille est bornée par le cliquet de taille.
///
/// - **Les conflits restants nommés** (R21) : combinaison et mods, cinq au
///   plus puis « et N autres » — un nombre seul ne dit pas quoi regarder.
///   Seules les collisions clavier entre mods sont listées : ce sont les
///   seules que le plan déplace ; le compte, lui, garde le périmètre du
///   badge (`problemCount`).
/// - **Les co-déclenchements dits** quand il n'y a plus de conflit avéré
///   (R20) : le rescan ne les compte pas comme problèmes, un vert « aucun
///   conflit » les cacherait.
struct KeybindPlanRemaining: View {
    let report: KeybindScanner.KeybindReport?
    let isScanning: Bool
    @ObservedObject var localization: LocalizationStore

    /// Assez pour voir de quoi il s'agit sans transformer le verdict en
    /// second rapport : la liste complète vit dans la section Raccourcis.
    private static let listed = 5

    var body: some View {
        if isScanning {
            HStack(spacing: AppDesign.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text(localization.L(L10n.Keybinds.scanning)).font(AppDesign.Font.caption).foregroundColor(.secondary)
            }
        } else if let report {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                caption(summary(report))
                ForEach(Array(report.collisions.prefix(Self.listed).enumerated()), id: \.offset) { _, collision in
                    HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.sm) {
                        KeybindKeyChip(text: collision.combo.display)
                        caption(KeybindScanner.groupedUses(collision.uses).map(\.modName)
                            .joined(separator: ", "))
                    }
                }
                if report.collisions.count > Self.listed {
                    caption(localization.plural(L10n.KeybindPlan.remainingMore,
                                                report.collisions.count - Self.listed))
                }
            }
        }
    }

    /// Même vert que la section : le plan ne touche ni aux conflits avec le
    /// jeu ni aux non reconnus — « aucun conflit » sur les seules collisions
    /// entre mods serait un vert mensonger.
    private func summary(_ report: KeybindScanner.KeybindReport) -> String {
        if report.problemCount > 0 {
            return localization.plural(L10n.KeybindPlan.remaining, report.problemCount)
        }
        if !report.subsetOverlaps.isEmpty {
            return localization.plural(L10n.KeybindPlan.remainingOverlaps, report.subsetOverlaps.count)
        }
        if report.unrecognized.isEmpty { return localization.L(L10n.Keybinds.empty) }
        return localization.plural(L10n.KeybindPlan.remaining, 0)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(AppDesign.Font.caption).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
