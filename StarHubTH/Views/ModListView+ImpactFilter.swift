import SwiftUI

/// D5-C — le filtre et les comptes d'impact de la liste, sortis de
/// `ModListView+Filters` (fichier au cliquet) : le menu à trois états, son
/// entrée, et les comptes qu'il affiche.
extension ModListView {
    /// Menu à trois états : tout, ou seulement les mods d'impact mesuré
    /// élevé (ou élevé **et** moyen). Même famille de puce que le menu
    /// « traduction FR ». Les comptes viennent du store de la sonde, pas de
    /// la liste cadrée : ils ne bougent pas quand le filtre s'applique à
    /// lui-même — et à la première lecture ils valent 0, le temps que la
    /// relecture de fond finisse.
    func impactPicker(counts: (high: Int, highAndMedium: Int)) -> some View {
        let scope = filters.impactScope
        let isActive = scope != .off
        let label: String = {
            switch scope {
            case .off:             return localization.L(L10n.Mods.impactFilterLabel)
            case .high:            return localization.L(L10n.Mods.impactFilterHigh)
            case .highAndMedium:   return localization.L(L10n.Mods.impactFilterHighMedium)
            }
        }()
        let icon: String = {
            switch scope {
            case .off:             return "gauge"
            // Plein = élevé seul ; contour = élevé et moyen. La même paire
            // que la note (« en attente ») et la page Nexus : le contour
            // annonce la version adoucie du même signal.
            case .high:            return "exclamationmark.triangle.fill"
            case .highAndMedium:   return "exclamationmark.triangle"
            }
        }()
        return Menu {
            Button {
                listState.filters.impactScope = .off
            } label: {
                Label(localization.L(L10n.Mods.impactFilterLabel), systemImage: "gauge")
            }
            impactItem(.high, label: L10n.Mods.impactFilterHigh,
                       icon: "exclamationmark.triangle.fill", count: counts.high)
            impactItem(.highAndMedium, label: L10n.Mods.impactFilterHighMedium,
                       icon: "exclamationmark.triangle", count: counts.highAndMedium)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(AppDesign.Font.footnote)
                Text(label)
                    .font(AppDesign.Font.caption(.medium))
                Image(systemName: "chevron.down")
                    .font(AppDesign.Font.iconXXS(.bold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(isActive ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .fill(isActive ? Color.accentColor.opacity(AppDesign.Opacity.medium) : Color.secondary.opacity(AppDesign.Opacity.light))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(localization.L(L10n.Mods.impactFilterLabel))
    }

    private func impactItem(_ scope: ImpactScope,
                            label: String,
                            icon: String,
                            count: Int) -> some View {
        Button {
            listState.filters.impactScope = scope
        } label: {
            Label("\(localization.L(label)) (\(count))", systemImage: icon)
        }
    }

    /// Les comptes du menu impact (D5-C) : les classes du store de la sonde,
    /// composants de pack compris — la même carte que lit
    /// `ModListScoping.matchesImpact`. Zéro tant que la relecture de fond
    /// n'a pas abouti ; le menu reste utilisable, ses entrées montrent (0).
    func impactFilterCounts() -> (high: Int, highAndMedium: Int) {
        let classes = vm.modImpactStore.classesById.values
        let high = classes.filter { $0 == .high }.count
        let medium = classes.filter { $0 == .medium }.count
        return (high, high + medium)
    }
}
