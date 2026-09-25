import SwiftUI

/// Le sélecteur de cadrage de la liste des mods — Tous, Activés, En pause,
/// Problèmes, Mises à jour, chacun avec son compte. `ModListView` en pose
/// deux dans un `ViewThatFits` : libellés complets, ou icône et compte quand
/// la barre est trop étroite (fenêtre minimale) — jamais tronqués.
///
/// ⚠️ **Pas un `Picker(.segmented)`.** Un segment macOS n'affiche que du texte
/// **ou** une image : ni l'icône d'un `Label` ni une `Image` interpolée dans un
/// `Text` n'y survivent (deux essais le 2026-09-25, le compact n'affichait que
/// des chiffres). Des boutons rendent le `Label` entier ; l'apparence et le
/// trait « sélectionné » imitent le segmenté.
struct ModScopePicker: View {
    @Binding var scope: ModFilter
    let counts: (all: Int, enabled: Int, disabled: Int, issues: Int, updates: Int)
    @ObservedObject var localization: LocalizationStore
    let compact: Bool

    var body: some View {
        HStack(spacing: 2) {
            segment(.all, L10n.Mods.filterAll, counts.all, "square.stack")
            segment(.enabled, L10n.Mods.enabled, counts.enabled, "checkmark.circle")
            segment(.disabled, L10n.Mods.disabled, counts.disabled, "pause.circle")
            segment(.issues, L10n.Mods.filterIssues, counts.issues, "exclamationmark.triangle")
            segment(.updates, L10n.Mods.filterUpdates, counts.updates, "arrow.up.circle")
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(AppDesign.Opacity.subtle)))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(Color.primary.opacity(AppDesign.Opacity.light), lineWidth: 0.5))
        .fixedSize()
    }

    /// « icône Titre (n) », ou, compact, « icône n » — titre en infobulle et
    /// lu par VoiceOver.
    private func segment(_ value: ModFilter, _ key: String, _ count: Int,
                         _ symbol: String) -> some View {
        let title = "\(localization.L(key)) (\(count))"
        let selected = scope == value
        return Button { scope = value } label: {
            Label(compact ? "\(count)" : title, systemImage: symbol)
                .font(AppDesign.Font.caption(selected ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, AppDesign.Spacing.sm)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? Color.accentColor.opacity(0.22) : .clear))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundColor(selected ? .primary : .secondary)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
