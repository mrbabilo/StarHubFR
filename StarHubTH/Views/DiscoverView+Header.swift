import SwiftUI

extension DiscoverView {
    /// En-tête commun des pages (audit UX 2026-10-02) et rangée de commandes,
    /// fixes au-dessus du défilement : le saut de section reste dans le
    /// `ScrollView` qui porte les `id` des sections.
    func pageHeader<Toolbar: View>(toolbar: Toolbar) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            PageHeader(icon: "safari.fill", title: localization.L(L10n.Main.discover),
                       subtitle: localization.L(L10n.Discovery.headerSubtitle))
            toolbar
        }
        .padding(.horizontal, AppDesign.Spacing.xl)
        .padding(.vertical, AppDesign.Spacing.md)
    }
}
