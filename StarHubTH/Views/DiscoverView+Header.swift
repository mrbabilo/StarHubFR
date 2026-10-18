import SwiftUI

extension DiscoverView {
    /// Titre dans la barre d'outils et rangée de commandes fixe au-dessus du
    /// défilement : le saut de section reste dans le
    /// `ScrollView` qui porte les `id` des sections.
    func pageHeader<Toolbar: View>(toolbar: Toolbar) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            PageContextBar(icon: "safari.fill", title: localization.L(L10n.Main.discover),
                           context: localization.L(L10n.Discovery.headerSubtitle))
            toolbar
        }
        .padding(.horizontal, AppDesign.Spacing.xl)
        .padding(.vertical, AppDesign.Spacing.md)
    }
}
