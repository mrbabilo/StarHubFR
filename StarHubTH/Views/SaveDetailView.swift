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
            Picker("", selection: Bindable(navigation).saveSegment) {
                ForEach(SaveSegment.allCases, id: \.self) { segment in
                    Text(label(segment)).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, AppDesign.Spacing.sm)
            Divider()
            ZStack {
                shown(.details, navigation.saveSegment) {
                    SaveEditorView(vm: viewModel, localization: localization, save: save, currentTab: $currentTab)
                }
                shown(.mods, navigation.saveSegment) { modsSegment }
                shown(.history, navigation.saveSegment) {
                    SaveTimelineView(vm: viewModel, localization: localization, save: save,
                                     isActive: navigation.saveSegment == .history)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Les mods en pause qui ont laissé du contenu dans la partie, et les mods
    /// disparus qu'elle cite encore, avec « Nettoyer… ».
    private var modsSegment: some View {
        VStack(spacing: 0) {
            PageContextBar(icon: "shippingbox", title: save.playerName,
                           context: save.farmName,
                           isActive: viewModel.navigationStore.saveSegment == .mods)
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
}
