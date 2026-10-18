import SwiftUI

/// R6 (audit UX 2026-10-16, décision de l'auteur) — la page d'une partie, à
/// trois segments : Détails (l'éditeur), Mods (ce que la partie doit aux mods,
/// en lecture), Historique (ses sauvegardes de secours). Avant, l'éditeur et
/// l'historique étaient deux pages pleines qui se renvoyaient l'une à
/// l'autre, et les mods se cherchaient au milieu du formulaire, où Entrée
/// enregistre.
///
/// Les trois segments restent montés (patron de `DiagnosticsView`) : passer à
/// l'historique et revenir ne perd pas une saisie en cours de l'éditeur.
struct SaveDetailView: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let save: SaveGameInfo
    @Binding var currentTab: SidebarDestination

    var body: some View {
        let navigation = viewModel.navigationStore
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(SaveSegment.allCases, id: \.self) { segment in
                    segmentButton(segment, navigation: navigation)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(AppDesign.Opacity.subtle)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(AppDesign.Opacity.light), lineWidth: 0.5))
            .fixedSize()
            .padding(.vertical, AppDesign.Spacing.sm)
            .zIndex(2)
            Divider()
            ZStack {
                shown(.details, navigation.saveSegment) {
                    SaveEditorView(vm: viewModel, localization: localization, save: save, currentTab: $currentTab)
                }
                shown(.mods, navigation.saveSegment) { modsSegment }
                shown(.history, navigation.saveSegment) {
                    SaveTimelineView(vm: viewModel, localization: localization, save: save)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Les mods en pause qui ont laissé du contenu dans la partie, et les mods
    /// disparus qu'elle cite encore, avec « Nettoyer… ».
    private var modsSegment: some View {
        VStack(spacing: 0) {
            PageHeader(icon: "shippingbox", title: save.playerName, subtitle: save.farmName)
                .padding(.horizontal, AppDesign.Spacing.xl)
                .padding(.vertical, AppDesign.Spacing.md)
            Divider()
            Form {
                SavePausedFootprintSection(vm: viewModel, localization: localization, save: save, currentTab: $currentTab)
                SaveAbsentModsSection(vm: viewModel, localization: localization, save: save)
            }
            .formStyle(.grouped)
        }
    }

    private func shown(_ segment: SaveSegment, _ current: SaveSegment,
                       @ViewBuilder content: () -> some View) -> some View {
        let visible = segment == current
        return content()
            // Les trois segments restent montés. Le segment actif doit donc
            // passer au-dessus des contrôles macOS des segments cachés ;
            // sinon l'éditeur peut continuer à occuper la couche interactive.
            .zIndex(visible ? 1 : 0)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            // Un segment caché ne doit pas garder ses raccourcis : Entrée
            // enregistre dans l'éditeur, même invisible.
            .disabled(!visible)
            .accessibilityHidden(!visible)
    }

    private func label(_ segment: SaveSegment) -> String {
        switch segment {
        case .details: return localization.L(L10n.Saves.segmentDetails)
        case .mods:    return localization.L(L10n.Saves.segmentMods)
        case .history: return localization.L(L10n.Saves.timeline)
        }
    }

    private func segmentButton(_ segment: SaveSegment,
                               navigation: NavigationStore) -> some View {
        let title = label(segment)
        let selected = navigation.saveSegment == segment
        return Button { navigation.saveSegment = segment } label: {
            Text(title)
                .font(AppDesign.Font.caption(selected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, AppDesign.Spacing.md)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? Color.accentColor.opacity(0.22) : .clear))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusRing(cornerRadius: 5)
        .foregroundColor(selected ? .primary : .secondary)
        .help(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
