import SwiftUI

/// Bandeau discret de la page Profils : après une bascule de profil de cette
/// session, si le rapport de raccourcis porte des collisions clavier, il le
/// dit et mène au « Plan de raccourcis » (Alertes système). Le rapport est
/// recalculé par le scan qui suit toute bascule (`scanIfNeeded` sur le parc
/// relu) : le bandeau se tait pendant ce scan, le rapport publié étant alors
/// l'ancien. La croix le masque jusqu'à la bascule suivante.
struct KeybindPlanProfileBanner: View {
    let viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @ObservedObject private var service: KeybindScanService

    init(viewModel: StarHubTHViewModel, localization: LocalizationStore) {
        self.viewModel = viewModel
        self.localization = localization
        self.service = viewModel.keybindScanService
    }

    private var count: Int {
        guard viewModel.profilesStore.switchBannerPending, !service.isScanning else { return 0 }
        return service.report?.collisions.count ?? 0
    }

    var body: some View {
        if count > 0 {
            SplitRow {
                Image(systemName: "keyboard.badge.ellipsis").foregroundColor(AppDesign.Color.warning)
                Text(localization.plural(L10n.KeybindPlan.profileBanner, count))
                    .font(AppDesign.Font.body)
                    .fixedSize(horizontal: false, vertical: true)
            } trailing: {
                Button(localization.L(L10n.KeybindPlan.propose)) { viewModel.navigationStore.openKeybindPlan() }
                    .buttonStyle(.bordered).focusRing(cornerRadius: 5)
                    .controlSize(.small)
                    .pointingHandCursor()
                Button(action: { viewModel.profilesStore.dismissSwitchBanner() }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless).focusRing(cornerRadius: 4)
                .pointingHandCursor()
                .iconHelp(localization.L(L10n.KeybindPlan.profileBannerDismiss))
            }
            .padding(.horizontal, AppDesign.Spacing.xl)
            .padding(.vertical, AppDesign.Spacing.sm)
            .background(AppDesign.Color.warning.opacity(0.12))
        }
    }
}
