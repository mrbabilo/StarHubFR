import SwiftUI

/// Le sélecteur de cadrage de la liste des mods — Tous, Activés, En pause,
/// Problèmes, Mises à jour, chacun avec son compte. `ModListView` en pose
/// deux dans un `ViewThatFits` : libellés complets, ou icône et compte quand
/// la barre est trop étroite (fenêtre minimale) — jamais tronqués.
struct ModScopePicker: View {
    @Binding var scope: ModFilter
    let counts: (all: Int, enabled: Int, disabled: Int, issues: Int, updates: Int)
    @ObservedObject var localization: LocalizationStore
    let compact: Bool

    var body: some View {
        Picker("", selection: $scope) {
            segment(L10n.Mods.filterAll, counts.all, "square.stack").tag(ModFilter.all)
            segment(L10n.Mods.enabled, counts.enabled, "checkmark.circle").tag(ModFilter.enabled)
            segment(L10n.Mods.disabled, counts.disabled, "pause.circle").tag(ModFilter.disabled)
            segment(L10n.Mods.filterIssues, counts.issues, "exclamationmark.triangle", icon: true)
                .tag(ModFilter.issues)
            segment(L10n.Mods.filterUpdates, counts.updates, "arrow.up.circle", icon: true)
                .tag(ModFilter.updates)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    /// « Titre (n) » — avec son icône pour les deux cadrages d'attention —,
    /// ou, compact, l'icône et le compte (le titre reste lu par VoiceOver).
    @ViewBuilder
    private func segment(_ key: String, _ count: Int, _ symbol: String,
                         icon: Bool = false) -> some View {
        let title = "\(localization.L(key)) (\(count))"
        if compact {
            Label("\(count)", systemImage: symbol).accessibilityLabel(title)
        } else if icon {
            Label(title, systemImage: symbol)
        } else {
            Text(title)
        }
    }
}
