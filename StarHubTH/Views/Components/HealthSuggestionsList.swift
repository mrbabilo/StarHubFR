import SwiftUI

/// N-09 S9 (audit UX 2026-10-16) — « Ce que vous pouvez faire » : chaque
/// conseil porte son bouton. Sorti de `SmapiHealthCard` (plafond de taille).
///
/// Un bouton qui ne trouve plus sa cible (dépendance installée depuis le
/// journal, mod retiré) reste là, grisé, avec son motif : un refus discret
/// n'est jamais muet.
struct HealthSuggestionsList: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let suggestions: [HealthSuggestion]
    /// Défile jusqu'à un bloc de la carte.
    let showBlock: (String) -> Void
    /// Défile jusqu'à la recherche guidée, sous la carte.
    let showBisection: () -> Void

    @State private var showsMissingDependencies = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesignCore.Spacing.sm) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                HStack(alignment: .top, spacing: AppDesignCore.Spacing.sm) {
                    Text("\(index + 1).")
                        .font(.system(size: AppDesign.Font.scaled(11), weight: .semibold, design: .rounded))
                        .foregroundColor(.accentColor)
                        .frame(width: 16, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.text)
                            .font(AppDesign.Font.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        if let action = suggestion.action { gesture(action) }
                    }
                }
            }
        }
        .sheet(isPresented: $showsMissingDependencies) {
            MissingDependenciesSheet(vm: viewModel, localization: localization,
                                     isPresented: $showsMissingDependencies)
        }
    }

    @ViewBuilder
    private func gesture(_ action: HealthSuggestion.Action) -> some View {
        switch action {
        case .installDependency(let missing):
            let available = HealthSuggestion.isStillMissing(missing, in: viewModel.missingDependenciesPlan)
            button(L10n.HealthSuggestion.install, refusal: available ? nil : L10n.HealthSuggestion.depResolved) {
                showsMissingDependencies = true
            }
        case .openMod(let name):
            let found = ModFocusResolver.resolve(name, in: viewModel.scanStore.mods) != nil
            button(L10n.HealthSuggestion.openMod, refusal: found ? nil : L10n.HealthSuggestion.modGone) {
                NotificationCenter.default.post(name: .jumpToMod, object: name)
            }
        case .showBlock(let anchor):
            button(L10n.HealthSuggestion.showMods, refusal: nil) { showBlock(anchor) }
        case .showBisection:
            button(L10n.Bisect.title, refusal: nil, action: showBisection)
        }
    }

    private func button(_ title: String, refusal: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: AppDesignCore.Spacing.sm) {
            Button(localization.L(title), action: action)
                .buttonStyle(.link).clickableCursor().focusRing(cornerRadius: 4)
                .font(AppDesign.Font.footnote)
                .disabled(refusal != nil)
            if let refusal {
                Text(localization.L(refusal))
                    .font(AppDesign.Font.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
