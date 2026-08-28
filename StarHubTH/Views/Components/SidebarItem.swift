import SwiftUI

/// L'item unique de la barre latérale : une icône, un libellé, et un badge
/// capsule facultatif au bord fuyant — le motif de Mail, où le compte se pose
/// *sur* la destination au lieu d'occuper une zone à part.
///
/// Remplace `SidebarNavItem` et `SidebarBadgeItem`, qui disaient la même chose
/// de deux façons : le second n'avait pas d'icône et se peignait de sa propre
/// couleur à la sélection. Un seul concept (H-T2).
struct SidebarItem: View {
    let icon: String
    let label: String
    let tab: String
    /// `nil` : cet item ne compte rien. `0` : il compte, et il n'y a rien —
    /// la capsule disparaît mais l'item reste, parce que la destination doit
    /// rester atteignable quand tout va bien.
    var badge: Int? = nil
    var badgeColor: Color = .blue
    @Binding var currentTab: String
    @State private var isHovered = false

    private var isSelected: Bool { currentTab == tab }

    var body: some View {
        Button(action: { currentTab = tab }) {
            HStack(spacing: AppDesign.Spacing.md) {
                Image(systemName: icon)
                    .font(AppDesign.Font.rowTitle)
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(width: 20, alignment: .center)

                Text(label)
                    .font(AppDesign.Font.rowTitle)
                    .foregroundColor(isSelected ? .white : .primary)
                Spacer()

                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(AppDesign.Font.footnote(.bold))
                        .foregroundColor(isSelected ? badgeColor : .white)
                        .frame(minWidth: 18, minHeight: 18)
                        .padding(.horizontal, AppDesign.Spacing.xs)
                        .background(isSelected ? Color.white : badgeColor)
                        .clipShape(Capsule())
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            // 6 : la valeur de `SidebarNavItem`, qu'aucun token ne porte.
            // L'écrire `Spacing.sm - 2` serait une devinette pour le lecteur.
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor
                          : (isHovered ? Color.primary.opacity(AppDesign.Opacity.subtle) : Color.clear))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered = $0 }
        .pointingHandCursor()
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Un item qui compte annonce son compte ; un item qui ne compte rien
    /// annonce son nom. Dire « Réglages, 0 élément » serait plus bruyant
    /// qu'utile.
    private var accessibilityText: String {
        guard let badge else { return label }
        return String(format: NSLocalizedString("main_alerts_nav_a11y", comment: ""),
                      label, Int64(badge))
    }
}
