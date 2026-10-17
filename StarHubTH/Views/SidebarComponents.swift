import SwiftUI

// MARK: - Sidebar Nav Groups

/// Les quatre groupes d'entrées de la barre latérale — Bibliothèque, Parties,
/// Santé & secours, Application. Extrait du corps de `MainView` (densité) et
/// posé dans le `ScrollView` de la colonne : en fenêtre basse, ce sont ces
/// lignes qui défilent, pas les réglages du bas.
struct SidebarNavGroups: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var currentTab: SidebarDestination

    /// Le badge d'une destination — donnée **vivante** du ViewModel, pas de
    /// `SidebarOrder` : il change à chaque scan. `nil` quand l'entrée ne
    /// compte rien.
    private func badge(_ d: SidebarDestination) -> (count: Int, color: Color)? {
        let model = vm
        switch d {
        case .updates:
            return (UpdateCount.pending(outOfDate: model.outOfDateMods,
                                        nexusCount: model.nexusUpdates.count) {
                model.resolveModFolder(forLoggedName: $0)?.version
            }, AppDesign.Color.info)
        case .systemAlerts:
            return (model.systemAlertCount, AppDesign.Color.warning)
        case .quarantine:
            return (model.maintenanceStore.quarantineItemCount, AppDesign.Color.quarantine)
        case .frenchTranslations:
            // P5-10 : mods actifs, mises à jour et traductions confirmées.
            return (model.frenchTranslationBadgeCount, AppDesign.Color.accent)
        case .home, .mods, .discover, .profiles, .saves,
             .backups, .maintenance, .logs, .settings,
             .appChangelog:
            return nil
        }
    }

    private func group(_ g: SidebarGroup, header: String,
                       icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SidebarSectionHeader(title: header, icon: icon)
            ForEach(SidebarOrder.entries(in: g)) { e in
                // `badge: Int?` est déjà optionnel côté SidebarItem — `nil`
                // veut dire « cet item ne compte rien », `0` « il compte, et
                // il n'y a rien ». Pas de branche à écrire.
                let b = badge(e.destination)
                SidebarItem(icon: e.icon, label: localization.L(e.labelKey),
                            tab: e.destination, badge: b?.count,
                            badgeColor: b?.color ?? AppDesign.Color.info,
                            currentTab: $currentTab)
            }
        }
    }

    /// Le groupe `.top` (l'Accueil) n'est **pas** rendu ici : il vit dans
    /// `AccountHeaderCard`, en tête de colonne. Il est dans `SidebarOrder`
    /// parce que le menu « Aller » et la palette en ont besoin, pas la barre.
    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
            group(.library, header: localization.L(L10n.Main.groupLibrary),
                  icon: "square.grid.2x2")
            group(.saves, header: localization.L(L10n.Main.groupSaves),
                  icon: "gamecontroller")
            group(.health, header: localization.L(L10n.Main.groupHealth),
                  icon: "cross.case")
            group(.app, header: localization.L(L10n.Main.groupApp), icon: "gearshape")
        }
    }
}

// MARK: - Sidebar Pinned Footer

/// Le pied épinglé de la barre latérale : volet Nexus, poids de `Mods/`,
/// thème, journal des modifications et langue. Toujours visible, quelle que
/// soit la hauteur de la fenêtre.
struct SidebarPinnedFooter: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var appColorScheme: String
    @Binding var currentTab: SidebarDestination

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            // Un lien `nxm://` arrive quel que soit l'onglet ouvert : son
            // téléchargement se voit ici, pas sur la seule page des mises à jour.
            NexusDownloadFooter(vm: vm, localization: localization)

            ModsWeightFooter(vm: vm, localization: localization)

            SidebarFooterPages(vm: vm, localization: localization, currentTab: $currentTab) // ligne à part : 220 pt ne tiennent pas thème + pages + drapeaux
            HStack {
                ThemeToggle(vm: vm, localization: localization, appColorScheme: $appColorScheme).fixedSize()
                Spacer()
                LanguageFlagToggle(vm: vm, localization: localization).fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, AppDesign.Spacing.sm)
        .padding(.bottom, 10)
    }
}

// MARK: - Sidebar Section Header
/// Compact language switcher shown at the bottom of the sidebar: two flag
/// buttons (🇫🇷 / 🇬🇧) with the active language highlighted. Setting
/// `localization.currentLanguage` swaps the bundle live (same path as before), so the UI
/// re-localizes immediately.
struct LanguageFlagToggle: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        HStack(spacing: 2) {
            flagButton(flag: "🇫🇷", code: "fr", help: localization.L(L10n.Settings.languageFrench))
            flagButton(flag: "🇬🇧", code: "en", help: localization.L(L10n.Settings.languageEnglish))
        }
        .padding(3)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
    }

    private func flagButton(flag: String, code: String, help: String) -> some View {
        let isActive = localization.currentLanguage == code
        return Button {
            if localization.currentLanguage != code { localization.setLanguage(code) }
        } label: {
            Text(flag)
                .font(.system(size: AppDesign.Font.scaled(15)))
                .grayscale(isActive ? 0 : 0.9)
                .opacity(isActive ? 1 : 0.55)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isActive ? Color.accentColor.opacity(0.22) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain).focusRing(cornerRadius: FocusRing.capsule)
        .pointingHandCursor()
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Compact appearance switcher shown at the bottom-left of the sidebar: System
/// / Light / Dark, mirroring the language flag toggle on the right. Writes the
/// same `appColorScheme` AppStorage the app reads for `preferredColorScheme`.
struct ThemeToggle: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var appColorScheme: String

    var body: some View {
        HStack(spacing: 2) {
            themeButton(icon: "circle.lefthalf.filled", value: "System", help: localization.L(L10n.Settings.themeSystem))
            themeButton(icon: "sun.max.fill", value: "Light", help: localization.L(L10n.Settings.themeLight))
            themeButton(icon: "moon.fill", value: "Dark", help: localization.L(L10n.Settings.themeDark))
        }
        .padding(3)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
    }

    private func themeButton(icon: String, value: String, help: String) -> some View {
        let isActive = appColorScheme == value
        return Button {
            if appColorScheme != value { appColorScheme = value }
        } label: {
            Image(systemName: icon)
                .font(AppDesign.Font.caption)
                .foregroundColor(isActive ? .accentColor : .secondary)
                .opacity(isActive ? 1 : 0.6)
                .padding(.horizontal, 6)
                .padding(.vertical, AppDesign.Spacing.xs)
                .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain).focusRing(cornerRadius: FocusRing.capsule)
        .pointingHandCursor()
        .help(help)
        .accessibilityLabel(help)
    }
}

struct SidebarSectionHeader: View {
    let title: String
    var icon: String = ""   // optionnel, vide par défaut (pas de breaking change)

    var body: some View {
        HStack(spacing: AppDesign.Spacing.xs + 2) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(AppDesign.Font.iconXS.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            Text(title)
                .font(AppDesign.Font.caption(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(.leading, AppDesign.Spacing.sm)
        .padding(.top, AppDesign.Spacing.sm)
        .padding(.bottom, 0)
        .accessibilityAddTraits(.isHeader)
    }
}
