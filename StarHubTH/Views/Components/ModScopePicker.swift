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
            segment(L10n.Mods.filterIssues, counts.issues, "exclamationmark.triangle").tag(ModFilter.issues)
            segment(L10n.Mods.filterUpdates, counts.updates, "arrow.up.circle").tag(ModFilter.updates)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    /// « icône Titre (n) », ou, compact, « icône n » — le titre reste lu par
    /// VoiceOver.
    ///
    /// ⚠️ L'icône vit **dans le texte** (`Text` interpolant une `Image`) : un
    /// segment de sélecteur macOS ne rend que le titre d'un `Label`, son icône
    /// disparaissait et le mode compact n'affichait que des chiffres.
    private func segment(_ key: String, _ count: Int, _ symbol: String) -> some View {
        let title = "\(localization.L(key)) (\(count))"
        return Text(compact ? "\(Image(systemName: symbol)) \(count)"
                            : "\(Image(systemName: symbol)) \(title)")
            .accessibilityLabel(title)
    }
}
