import SwiftUI

/// Le chevron qui dit « cette ligne ouvre son détail » — celui du relevé de
/// santé d'un mod, repris partout où une ligne mène ailleurs (2026-10-08).
struct DisclosureChevron: View {
    var body: some View {
        Image(systemName: AppDesign.disclosureSymbol)
            .font(AppDesign.Font.iconXS)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}
