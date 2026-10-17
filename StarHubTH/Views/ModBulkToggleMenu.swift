import SwiftUI

/// Menu offering to enable or disable the framed mods at once. Each entry
/// is disabled individually when the **current framing** (search, category,
/// translation, scope — the same rule `toggleAllMods` applies, X57) has
/// nothing to move in that direction, so an available entry says exactly
/// what would move, and the user sees why an action isn't available
/// rather than a dead button.
///
/// Takes the scoped list computed once per render by `ModListView.body`
/// (`display`) rather than re-deriving it : the rule is the ViewModel's, the
/// menu only reads its result. Sorti de `ModListView` (plafond de taille,
/// audit UX 2026-10-16, I-T26) ; `.borderlessButton` et `.fixedSize()`
/// comme les autres menus de l'en-tête : sans eux, c'était le seul à céder
/// sa largeur, et la grille le recouvrait à 821 pt (E1).
///
/// R5 : il ouvre aussi « Revenir à un état d'avant », là où se font les
/// gestes groupés qu'il annule (la section vivait seulement sous Profils).
struct ModBulkToggleMenu: View {
    let scoped: [ModItem]
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var target: Bool?
    @State private var showsHistory = false

    var body: some View {
        let anyDisabled = scoped.contains { !$0.isEnabled }
        let anyEnabled = scoped.contains { $0.isEnabled }
        Menu {
            Button {
                target = true
            } label: {
                Label(localization.L(L10n.Mods.enableAll), systemImage: "checkmark.circle")
            }
            .disabled(!anyDisabled)

            Button {
                target = false
            } label: {
                Label(localization.L(L10n.Mods.disableAll), systemImage: "xmark.circle")
            }
            .disabled(!anyEnabled)

            Divider()
            Button {
                showsHistory = true
            } label: {
                Label(localization.L(L10n.ActivationHistory.menuEntry), systemImage: "clock.arrow.circlepath")
            }
        } label: {
            Label(localization.L(L10n.Mods.toggleAllHint), systemImage: "power")
                .labelStyle(.iconOnly)
                .font(AppDesign.Font.body)
        }
        .menuStyle(.borderlessButton).focusRing(cornerRadius: 4)
        .fixedSize()
        .help(localization.L(L10n.Mods.toggleAllHint))
        .sheet(isPresented: $showsHistory) {
            VStack(spacing: 0) {
                ScrollView {
                    ActivationHistorySection(viewModel: viewModel, localization: localization)
                        .padding(AppDesign.Spacing.lg)
                }
                Divider()
                HStack {
                    Spacer()
                    Button(localization.L(L10n.Main.ok)) { showsHistory = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(AppDesign.Spacing.md)
            }
            .frame(minWidth: 560, idealWidth: 640, minHeight: 360, idealHeight: 520)
        }
    }
}
