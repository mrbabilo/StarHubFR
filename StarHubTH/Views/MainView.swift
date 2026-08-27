import SwiftUI

struct MainView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var currentTab: String = "Home"
    
    // History Management
    @State private var tabHistory: [String] = ["Home"]
    @State private var forwardHistory: [String] = []
    @State private var isNavigatingBackOrForward = false
    
    @AppStorage("appColorScheme") private var appColorScheme: String = "System"
    @AppStorage("showThaiTranslationHub") private var showThaiTranslationHub: Bool = false
    @AppStorage("launchProfile") private var launchProfile: String = "SMAPI"
    
    @State private var isProfileHovered = false
    @State private var showDownloadedInstall = false
    

    private var navigationTitleText: String {
        if currentTab == "Saves" && vm.viewingSaveTimeline != nil { return vm.L(L10n.Saves.timeline) }
        if currentTab == "Saves" && vm.editingSave != nil { return vm.editingSave!.playerName }
        if currentTab == "ThaiHub" && vm.viewingThaiMod != nil { return vm.viewingThaiMod!.name }
        if currentTab == "Mods" && vm.editingModConfig != nil { return vm.editingModConfig!.name }
        if currentTab == "Mods" && vm.viewingModDetail != nil { return vm.viewingModDetail!.name }
        if currentTab == "Mods" { return vm.L(L10n.Mods.mods) }
        if currentTab == "InstallBackups" { return vm.L(L10n.ModInstall.manageBackups) }
        if currentTab == "ConfigBackups" { return vm.L(L10n.ModConfigBackups.title) }
        if currentTab == "Profiles" { return vm.L(L10n.Profiles.title) }
        if currentTab == "Updates" { return vm.L(L10n.Main.modUpdates) }
        if currentTab == "SystemAlerts" { return vm.L(L10n.Main.systemAlerts) }
        if currentTab == "Quarantine" { return vm.L(L10n.Main.quarantine) }
        if currentTab == "ThaiHub" { return vm.L(L10n.ThaiHub.title) }
        if currentTab == "Saves" { return vm.L(L10n.Saves.saves) }
        if currentTab == "Settings" { return vm.L(L10n.Settings.settings) }
        if currentTab == "Logs" { return vm.L(L10n.Logs.logs) }
        if currentTab == "AppChangelog" { return vm.L(L10n.Main.appChangelog) }
        return vm.L(L10n.Main.home)
    }
    
    var body: some View {
        ZStack {
            NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                
                // Account Header Card — compact identity + active profile +
                // key metadata (mods active/total, SMAPI status). Replaces the
                // old bulky 48px avatar and the floating SystemStatusFooter:
                // everything the user needs at-a-glance is now in one card.
                AccountHeaderCard(
                    vm: vm,
                    isActive: currentTab == "Home",
                    isHovered: isProfileHovered,
                    onTap: { currentTab = "Home" }
                )
                .onHover { isProfileHovered = $0 }
                
                // Mod Updates: Nexus updates + out-of-date mods (a single
                // badge). Separate from System Alerts so update notifications
                // don't get hidden behind SMAPI error counts. Always visible
                // — even when there are 0 updates, the user must be able to
                // reach the tab to manually trigger a Nexus check. The badge
                // is hidden when count == 0 (see `SidebarBadgeItem`).
                let modUpdateCount = vm.outOfDateMods.count + vm.nexusUpdates.count
                SidebarBadgeItem(
                    label: vm.L(L10n.Main.modUpdates),
                    tab: "Updates",
                    count: modUpdateCount,
                    accentColor: .blue,
                    currentTab: $currentTab
                )

                // System Alerts: SMAPI errors. These are also logged to the
                // Journaux tab so they remain consultable after the banner
                // is dismissed. Always visible for the same reason as Mod
                // Updates above: the page carries « Revérifier le journal »
                // (B2-T3), and a journal silent before an install says
                // nothing about after — the tab must be reachable when green.
                // The badge is hidden when count == 0 (see `SidebarBadgeItem`).
                SidebarBadgeItem(
                    label: vm.L(L10n.Main.systemAlerts),
                    tab: "SystemAlerts",
                    count: vm.smapiErrors.count,
                    accentColor: .orange,
                    currentTab: $currentTab
                )

                // Quarantine: folder-repair report + « Relancer l'analyse »
                // (B2-T3). Always visible — the entry used to appear only
                // when items were quarantined, which hid the page on a
                // healthy library: precisely the case where the user wants
                // to run the analysis and see it find nothing. The badge is
                // hidden when count == 0 (see `SidebarBadgeItem`).
                SidebarBadgeItem(
                    label: vm.L(L10n.Main.quarantine),
                    tab: "Quarantine",
                    count: vm.lastRepairReport?.quarantined.count ?? 0,
                    accentColor: .purple,
                    currentTab: $currentTab
                )
                
                // Game Section
                VStack(alignment: .leading, spacing: 2) {
                    SidebarSectionHeader(title: vm.L(L10n.Main.gameManagement), icon: "gamecontroller")
                    
                    SidebarNavItem(
                        icon: "person.2.fill",
                        iconColor: .orange,
                        label: vm.L(L10n.Profiles.title),
                        tab: "Profiles",
                        currentTab: $currentTab
                    )
                    
                    SidebarNavItem(
                        icon: "puzzlepiece.extension.fill",
                        iconColor: .purple,
                        label: vm.L(L10n.Mods.mods),
                        tab: "Mods",
                        currentTab: $currentTab
                    )

                    SidebarNavItem(
                        icon: "arrow.uturn.backward.circle.fill",
                        iconColor: .pink,
                        label: vm.L(L10n.ModInstall.manageBackups),
                        tab: "InstallBackups",
                        currentTab: $currentTab
                    )

                    SidebarNavItem(
                        icon: "archivebox.fill",
                        iconColor: .green,
                        label: vm.L(L10n.ModConfigBackups.tabTitle),
                        tab: "ConfigBackups",
                        currentTab: $currentTab
                    )

                    SidebarNavItem(
                        icon: "folder.fill",
                        iconColor: .blue,
                        label: vm.L(L10n.Saves.saves),
                        tab: "Saves",
                        currentTab: $currentTab
                    )
                }
                
                // System & Settings Section. Quarantine lives in the status
                // zone above — always reachable, badge only when it holds
                // something (see its comment there).
                VStack(alignment: .leading, spacing: 2) {
                    SidebarSectionHeader(title: vm.L(L10n.Main.system), icon: "gearshape")
                    
                    SidebarNavItem(
                        icon: "gearshape.fill",
                        iconColor: .gray,
                        label: vm.L(L10n.Settings.settings),
                        tab: "Settings",
                        currentTab: $currentTab
                    )

                    SidebarNavItem(
                        icon: "terminal.fill",
                        iconColor: .black,
                        label: vm.L(L10n.Logs.logs),
                        tab: "Logs",
                        currentTab: $currentTab
                    )

                    SidebarNavItem(
                        icon: "doc.text.fill",
                        iconColor: .indigo,
                        label: vm.L(L10n.Main.appChangelog),
                        tab: "AppChangelog",
                        currentTab: $currentTab
                    )
                }
                
                if showThaiTranslationHub {
                    // Thai Hub Section
                    VStack(alignment: .leading, spacing: 2) {
                        SidebarSectionHeader(title: vm.L(L10n.Main.online), icon: "globe.asia.australia")
                        SidebarNavItem(
                            icon: "globe.asia.australia.fill",
                            iconColor: .blue,
                            label: vm.L(L10n.ThaiHub.title),
                            tab: "ThaiHub",
                            currentTab: $currentTab
                        )
                    }
                }

                Spacer()

                ModsWeightFooter(vm: vm)

                // Bottom bar: theme switcher (left) + language switcher (right).
                HStack {
                    ThemeToggle(vm: vm, appColorScheme: $appColorScheme)
                    Spacer()
                    LanguageFlagToggle(vm: vm)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .frame(minWidth: 240, idealWidth: 240, maxWidth: 240, maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())

        } detail: {
            // ── CONTENT AREA ─────────────────────────────────────────
            Group {
                if currentTab == "Mods" {
                    if let mod = vm.editingModConfig {
                        ModConfigEditorView(vm: vm, mod: mod, initialTab: 1)
                    } else if let mod = vm.viewingModDetail {
                        ModDetailView(vm: vm, mod: mod)
                            .id(mod.folderName)
                    } else {
                        ModListView(vm: vm)
                    }
                } else if currentTab == "ConfigBackups" {
                    ModConfigBackupsView(vm: vm)
                } else if currentTab == "InstallBackups" {
                    ModInstallBackupsView(vm: vm)
                } else if currentTab == "Saves" {
                    if let save = vm.viewingSaveTimeline {
                        SaveTimelineView(vm: vm, save: save)
                    } else if let save = vm.editingSave {
                        SaveEditorView(vm: vm, save: save)
                    } else {
                        SavesView(vm: vm)
                    }
                } else if currentTab == "Profiles" {
                    ModProfilesView(vm: vm, currentTab: $currentTab)
                } else if currentTab == "Updates" {
                    UpdatesView(vm: vm, currentTab: $currentTab)
                } else if currentTab == "SystemAlerts" {
                    SystemAlertsView(vm: vm, currentTab: $currentTab)
                } else if currentTab == "Quarantine" {
                    QuarantineView(vm: vm)
                } else if currentTab == "ThaiHub" {
                    ThaiTranslationHubView(vm: vm)
                } else if currentTab == "Settings" {
                    SettingsView(vm: vm)
                } else if currentTab == "Logs" {
                    LogsView(vm: vm)
                } else if currentTab == "AppChangelog" {
                    AppChangelogView(vm: vm)
                } else {
                    HomeView(vm: vm)
                }
            }
            .navigationTitle(navigationTitleText)
            .onChange(of: currentTab) { _, _ in
                vm.editingSave = nil
                vm.viewingThaiMod = nil
                vm.viewingSaveTimeline = nil
                vm.editingModConfig = nil
                vm.viewingModDetail = nil

                // …sauf une demande de traduction, qui est précisément **ce
                // qui** amène sur cet onglet (B3-T4, depuis la couverture
                // française d'un profil). La poser avant de changer d'onglet
                // ne servait à rien : la remise à zéro ci-dessus l'effaçait
                // aussitôt, et le bouton n'ouvrait que la liste des mods.
                if currentTab == "Mods", let folderName = vm.pendingTranslationFocus {
                    vm.viewingModDetail = vm.mods.flattenedMods
                        .first { $0.folderName == folderName }
                }

                if !isNavigatingBackOrForward {
                    if tabHistory.last != currentTab {
                        tabHistory.append(currentTab)
                        forwardHistory.removeAll()
                    }
                } else {
                    isNavigatingBackOrForward = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 8) {
                        Button(action: {
                            if vm.editingSave != nil {
                                vm.editingSave = nil
                            } else if vm.viewingThaiMod != nil {
                                vm.viewingThaiMod = nil
                            } else if vm.viewingSaveTimeline != nil {
                                vm.viewingSaveTimeline = nil
                            } else if vm.editingModConfig != nil {
                                vm.editingModConfig = nil
                            } else if vm.viewingModDetail != nil {
                                vm.viewingModDetail = nil
                            } else if tabHistory.count > 1 {
                                isNavigatingBackOrForward = true
                                let current = tabHistory.removeLast()
                                forwardHistory.append(current)
                                currentTab = tabHistory.last ?? "Home"
                            }
                        }) {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel(vm.L(L10n.Main.navBack))
                        .help(vm.L(L10n.Main.navBack))
                        .disabled(vm.editingSave == nil && vm.viewingThaiMod == nil && vm.viewingSaveTimeline == nil && vm.editingModConfig == nil && vm.viewingModDetail == nil && tabHistory.count <= 1)
                        
                        Button(action: {
                            if let next = forwardHistory.popLast() {
                                isNavigatingBackOrForward = true
                                tabHistory.append(next)
                                currentTab = next
                            }
                        }) {
                            Image(systemName: "chevron.right")
                        }
                        .accessibilityLabel(vm.L(L10n.Main.navForward))
                        .help(vm.L(L10n.Main.navForward))
                        .disabled(forwardHistory.isEmpty)
                    }
                }
            }
            .frame(minWidth: 560, minHeight: 400)
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        
            // Application d'un profil : le voile couvre toute la fenêtre, pas
            // seulement la page des profils — « Gérer » applique le profil puis
            // bascule sur la page des mods, et l'utilisateur y attendrait
            // devant une liste figée sans savoir pourquoi.
            if let progress = vm.profileApplyProgress {
                switch progress.phase {
                case .movingFolders:
                    ModalProgressOverlay(label: vm.L(L10n.Profiles.applyingMoving),
                                         done: progress.done,
                                         total: progress.total)
                case .rescanning:
                    // Le rescane publie déjà son propre avancement pour le
                    // voile de démarrage : on le montre plutôt que de laisser
                    // la barre pleine du temps d'avant.
                    ModalProgressOverlay(label: vm.L(L10n.Profiles.applyingScanning),
                                         done: vm.scanProgress?.done ?? 0,
                                         total: vm.scanProgress?.total ?? 0)
                }
            }
        } // End of outer ZStack
        // No launch overlay here any more: the splash is its own window
        // (`LaunchSplashController`) and this window stays hidden until the
        // app is ready, so there's never a half-loaded UI to cover up.
        .frame(minWidth: 820, minHeight: 520)
        .preferredColorScheme(colorScheme)
        .environment(\.locale, Locale(identifier: vm.currentLanguage))
        .onReceive(NotificationCenter.default.publisher(for: .jumpToMod)) { notification in
            if let modName = notification.object as? String {
                vm.selectedModID = ModFocusResolver.resolve(modName, in: vm.mods)?.folderName
                // Hand the request to the list itself: it may not be on screen
                // yet (tabs are created on demand), so it picks this up on
                // appear and scopes itself to the mod.
                vm.pendingModFocus = modName
                currentTab = "Mods"
            }
        }
        .alert(isPresented: $vm.showAlert) {
            Alert(
                title: Text(vm.L(L10n.Main.alert)),
                message: Text(vm.alertMessage),
                dismissButton: .default(Text(vm.L(L10n.Main.ok)))
            )
        }
        .onChange(of: vm.pendingDownloadedZip) { _, newValue in
            showDownloadedInstall = (newValue != nil)
        }
        .sheet(isPresented: $showDownloadedInstall, onDismiss: {
            if let url = vm.pendingDownloadedZip {
                try? FileManager.default.removeItem(at: url)
            }
            vm.pendingDownloadedZip = nil
            vm.pendingNexusSource = nil
        }) {
            ModInstallView(vm: vm, isPresented: $showDownloadedInstall, preloadedZip: vm.pendingDownloadedZip)
        }
    }
    

    var colorScheme: ColorScheme? {
        switch appColorScheme {
        case "Light": return .light
        case "Dark": return .dark
        default: return nil
        }
    }
}

// MARK: - Sidebar Section Header
/// Compact language switcher shown at the bottom of the sidebar: two flag
/// buttons (🇫🇷 / 🇬🇧) with the active language highlighted. Setting
/// `vm.currentLanguage` swaps the bundle live (same path as before), so the UI
/// re-localizes immediately.
struct LanguageFlagToggle: View {
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        HStack(spacing: 2) {
            flagButton(flag: "🇫🇷", code: "fr", help: vm.L(L10n.Settings.languageFrench))
            flagButton(flag: "🇬🇧", code: "en", help: vm.L(L10n.Settings.languageEnglish))
        }
        .padding(3)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
    }

    private func flagButton(flag: String, code: String, help: String) -> some View {
        let isActive = vm.currentLanguage == code
        return Button {
            if vm.currentLanguage != code { vm.currentLanguage = code }
        } label: {
            Text(flag)
                .font(.system(size: 15))
                .grayscale(isActive ? 0 : 0.9)
                .opacity(isActive ? 1 : 0.55)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isActive ? Color.accentColor.opacity(0.22) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Compact appearance switcher shown at the bottom-left of the sidebar: System
/// / Light / Dark, mirroring the language flag toggle on the right. Writes the
/// same `appColorScheme` AppStorage the app reads for `preferredColorScheme`.
struct ThemeToggle: View {
    @ObservedObject var vm: StarHubTHViewModel
    @Binding var appColorScheme: String

    var body: some View {
        HStack(spacing: 2) {
            themeButton(icon: "circle.lefthalf.filled", value: "System", help: vm.L(L10n.Settings.themeSystem))
            themeButton(icon: "sun.max.fill", value: "Light", help: vm.L(L10n.Settings.themeLight))
            themeButton(icon: "moon.fill", value: "Dark", help: vm.L(L10n.Settings.themeDark))
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
                .font(.system(size: 12))
                .foregroundColor(isActive ? .accentColor : .secondary)
                .opacity(isActive ? 1 : 0.6)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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

// MARK: - Sidebar Badge Item (alert-style nav with count capsule)
struct SidebarBadgeItem: View {
    let label: String
    let tab: String
    let count: Int
    let accentColor: Color
    @Binding var currentTab: String

    private var isSelected: Bool { currentTab == tab }

    var body: some View {
        Button(action: { currentTab = tab }) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                Spacer()
                // Badge hidden when count == 0 so a "no updates / no alerts"
                // item still appears in the sidebar but doesn't show a
                // misleading empty bubble.
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isSelected ? accentColor : .white)
                        .frame(minWidth: 18, minHeight: 18)
                        .padding(.horizontal, 4)
                        .background(isSelected ? Color.white : accentColor)
                        .clipShape(Capsule())
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? accentColor : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHandCursor()
        .accessibilityLabel(
            String(format: NSLocalizedString("main_alerts_nav_a11y", comment: ""),
                   label, Int64(count))
        )
    }
}

// MARK: - Sidebar Nav Item (macOS System Settings style)
struct SidebarNavItem: View {
    let icon: String
    let iconColor: Color
    let label: String
    let tab: String
    @Binding var currentTab: String
    @State private var isHovered = false

    var isSelected: Bool { currentTab == tab }

    var body: some View {
        Button(action: { currentTab = tab }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(AppDesign.Font.rowTitle)
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(width: 20, alignment: .center)

                Text(label)
                    .font(AppDesign.Font.rowTitle)
                    .foregroundColor(isSelected ? .white : .primary)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
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
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - SMAPI Alerts UI
// MARK: - Updates View (macOS System Settings style)
struct UpdatesView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @Binding var currentTab: String
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // Out of date mods (Software Update style)
                if !vm.outOfDateMods.isEmpty {
                    ForEach(vm.outOfDateMods) { mod in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 16) {
                                // App Icon Fake
                                InitialsAvatar(
                                    text: mod.name,
                                    initialsCount: 2,
                                    size: 56,
                                    fillColor: Color.blue.opacity(0.1),
                                    textColor: .blue.opacity(0.8),
                                    fontSize: 20
                                )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mod.name)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.primary)
                                    Text(mod.version)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    
                    Text(vm.L(L10n.Updates.newUpdate))
                                        .font(.system(size: 12))
                                        .foregroundColor(.red.opacity(0.8))
                                        .padding(.top, 2)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 8) {
                                    Button(action: {
                                        if let url = URL(string: mod.url) { NSWorkspace.shared.open(url) }
                                    }) {
                                        Text(vm.L(L10n.Updates.download))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 6)
                                            .background(Color.primary.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .pointingHandCursor()
                                }
                            }

                            VStack(alignment: .leading, spacing: 16) {
                                Text(vm.L(L10n.Updates.updateDescription))
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)

                                HStack(spacing: 4) {
                                    Text(vm.L(L10n.Updates.visitWebsite))
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                    // Vrai lien cliquable plutôt qu'un Markdown
                                    // `[url](url)` interpolé que Text rendait en brut.
                                    if let url = URL(string: mod.url) {
                                        Link(url.absoluteString, destination: url)
                                            .font(.system(size: 13))
                                    }
                                }
                                .tint(.blue)
                            }
                            .padding(.top, 8)
                        }
                        .padding(20)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(12)
                    }
                }
                
                // ── Nexus Mods updates ─────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 16))
                        Text(vm.L(L10n.Updates.nexusSection))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
                        Spacer()
                        if vm.isCheckingNexusUpdates {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                vm.checkNexusUpdates()
                            } label: {
                                Text(vm.L(L10n.Updates.nexusCheckButton))
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                    }

                    // Note, plus barrage : la vérification passe par smapi.io,
                    // sans clé ni quota. La clé ne manque qu'au téléchargement
                    // intégré. Tant que ce bloc était la première branche de la
                    // chaîne, il **remplaçait** la liste : sans compte Nexus,
                    // aucune mise à jour n'était visible, quand bien même
                    // l'app en avait trouvé.
                    if !vm.hasNexusApiKey {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "key.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(vm.L(L10n.Updates.nexusApiKeyMissing))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Button {
                                    if let url = URL(string: "https://www.nexusmods.com/users/myaccount?tab=api") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Text(vm.L(L10n.Updates.nexusGetKey))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                            }
                        }
                    }

                    if vm.isCheckingNexusUpdates {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(vm.L(L10n.Updates.nexusChecking))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                if let prog = vm.nexusCheckProgress, prog.total > 0 {
                                    Spacer()
                                    Text("\(prog.done)/\(prog.total)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            // Determinate progress bar when we know the total.
                            if let prog = vm.nexusCheckProgress, prog.total > 0 {
                                let fraction = Double(prog.done) / Double(prog.total)
                                ProgressView(value: fraction)
                                    .progressViewStyle(.linear)
                                    .tint(.accentColor)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: vm.nexusCheckProgress?.done)
                    } else if let err = vm.nexusCheckError, vm.nexusUpdates.isEmpty {
                        // A partial run that still found updates falls
                        // through to the list below instead of here — an
                        // error banner must never hide real data that was
                        // actually gathered.
                        Text(err == "rate_limited"
                             ? vm.L(L10n.Updates.nexusRateLimited)
                             : vm.L(L10n.Updates.nexusError))
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                    } else if vm.nexusUpdates.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        Text(vm.L(L10n.Logs.systemAlertsSection))
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    } else {
                        // Summary line + list of available updates.
                        Text(String(format: vm.L(L10n.Updates.nexusUpdatesCount),
                                    Int64(vm.nexusUpdates.count)))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        ForEach(vm.nexusUpdates) { update in
                            let isEnabled = vm.modForNexusUpdate(update)?.isEnabled ?? false
                            HStack(alignment: .top, spacing: 16) {
                                InitialsAvatar(
                                    text: update.name,
                                    initialsCount: 2,
                                    size: 44,
                                    fillColor: Color.accentColor.opacity(0.12),
                                    textColor: .accentColor,
                                    fontSize: 16
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(update.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)
                                        Text(isEnabled ? vm.L(L10n.Updates.enabled) : vm.L(L10n.Updates.disabled))
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(isEnabled ? .green : .orange)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background((isEnabled ? Color.green : Color.orange).opacity(0.12))
                                            .cornerRadius(4)
                                    }
                                    HStack(spacing: 12) {
                                        Label("\(vm.L(L10n.Updates.installedVersion)) \(update.installedVersion)",
                                              systemImage: "tag.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Label("\(vm.L(L10n.Updates.latestVersion)) \(update.latestVersion)",
                                              systemImage: "sparkles")
                                            .font(.system(size: 11))
                                            .foregroundColor(.green)
                                        if let uploaded = update.uploadedTime {
                                            Label(vm.formatUploadedDate(uploaded),
                                                  systemImage: "clock.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary.opacity(0.8))
                                        }
                                    }
                                }

                                Spacer()

                                if let nexusId = Int(update.nexusModId),
                                   vm.downloadingNexusModId == nexusId {
                                    ProgressView()
                                        .controlSize(.small)
                                        .help(vm.L(L10n.VM.nexusDlStarting).replacingOccurrences(of: "%lld", with: String(nexusId)))
                                } else {
                                    if let nexusId = Int(update.nexusModId) {
                                        Button {
                                            vm.downloadModFromNexus(nexusId: nexusId)
                                        } label: {
                                            Label(vm.L(L10n.Mods.premiumUpdate), systemImage: "arrow.down.circle")
                                        }
                                        .buttonStyle(.bordered)
                                        // Désactivé quand on **sait** que le
                                        // compte n'est pas premium : l'API
                                        // refuse alors tout lien direct
                                        // (`403 premium users only`), et
                                        // proposer le bouton revient à promettre
                                        // un échec. Le doute, lui, ne retire
                                        // rien.
                                        .disabled(vm.isDownloadingFromNexus || vm.nexusDirectDownloadUnavailable)
                                        .help(vm.nexusDirectDownloadUnavailable
                                              ? vm.L(L10n.Mods.premiumOnlyHint) : "")
                                    }

                                    Button {
                                        // Open the mod's Files tab directly, where the free
                                        // "Mod Manager Download" (nxm://) button lives.
                                        if var comps = URLComponents(string: update.url) {
                                            comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: "tab", value: "files")]
                                            if let url = comps.url { NSWorkspace.shared.open(url) }
                                        }
                                    } label: {
                                        Text(vm.L(L10n.Mods.nexusUpdate))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(Color.primary.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .pointingHandCursor()
                                    .disabled(vm.isDownloadingFromNexus)

                                    // La seule sortie quand l'auteur a oublié
                                    // d'incrémenter son manifest : la
                                    // comparaison de chaînes réclamera cette
                                    // mise à jour à chaque passe, sinon.
                                    Button {
                                        vm.affirmInstalled(uniqueId: update.uniqueId,
                                                           version: update.latestVersion)
                                    } label: {
                                        Text(vm.L(L10n.Updates.nexusAlreadyHave))
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .pointingHandCursor()
                                    .help(vm.L(L10n.Updates.nexusAlreadyHaveHelp))
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(isEnabled ? Color.primary.opacity(0.04) : Color.orange.opacity(0.06))
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(20)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)

            }
            .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - System Alerts View

/// Dedicated view for SMAPI system errors. These are also logged to the
/// Journaux tab (see StarHubTHViewModel.parseSMAPILog) so they remain
/// consultable after this banner is dismissed.
struct SystemAlertsView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @Binding var currentTab: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if vm.smapiErrors.isEmpty {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 28))
                            // Cette page parle du journal SMAPI, pas des mises
                            // à jour Nexus : l'ancienne clé disait « tous les
                            // mods sont à jour », hors sujet ici.
                            Text(vm.L(L10n.Updates.noAlerts))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                        .background(Color.green.opacity(0.06))
                        .cornerRadius(12)
                        // Vert ne veut pas dire véridique pour toujours : le
                        // journal date de la dernière partie, et l'utilisateur
                        // qui vient d'installer un mod veut pouvoir revoir.
                        recheckLogButton
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 16))
                            let errorText = String(format: vm.L(L10n.Updates.errorsFound), vm.smapiErrors.count)
                            Text(errorText)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer()
                            recheckLogButton
                            Button(action: { currentTab = "Logs" }) {
                                Text(vm.L(L10n.Updates.viewLogs))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .pointingHandCursor()
                        }

                        Text(vm.L(L10n.Updates.errorDescription))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)

                        ForEach(vm.smapiErrors, id: \.self) { error in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(Color.secondary.opacity(0.5))
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 6)
                                Text(error)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(20)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(12)
                }
            }
            .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Relit le journal SMAPI sans rescaner le parc — la page ne montre que
    /// ce que dit le journal, c'est lui seul qu'il faut relire.
    @ViewBuilder
    private var recheckLogButton: some View {
        HStack(spacing: 6) {
            Button(action: { vm.refreshSmapiLog() }) {
                Label(vm.L(L10n.Updates.recheckLog), systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .pointingHandCursor()
            .disabled(vm.isRefreshingSmapiLog)
            if vm.isRefreshingSmapiLog {
                ProgressView().controlSize(.small)
            }
        }
    }
}

// MARK: - Quarantine View

/// Shows the last folder-repair report and provides actions to open the
/// `_Trash_` quarantine folder or empty it to the Mac Trash (with
/// confirmation). Quarantined items are never deleted directly — "empty"
/// moves them to the Mac Trash where they can be recovered until the user
/// empties the Trash themselves.
struct QuarantineView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var showEmptyConfirmation = false

    var body: some View {
        let quarantineDir = quarantinePath

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(vm.L(L10n.Quarantine.title))
                        .font(.system(size: 20, weight: .bold))
                    Text(vm.L(L10n.Quarantine.subtitle))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Last repair report (or empty state when none yet).
                if let report = vm.lastRepairReport {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(vm.L(L10n.Quarantine.lastRepair))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)

                        if report.quarantined.isEmpty && report.duplicates.isEmpty {
                            Text(vm.L(L10n.Quarantine.noQuarantine))
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        } else {
                            Label(
                                String(format: vm.L(L10n.Quarantine.itemsQuarantined), Int64(report.quarantined.count)),
                                systemImage: "tray.and.arrow.down.fill"
                            )
                            .font(.system(size: 13))
                            .foregroundColor(.purple)

                            ForEach(Array(report.quarantined.prefix(20).enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "archivebox.fill")
                                        .foregroundColor(.purple.opacity(0.7))
                                        .font(.system(size: 10))
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.relativePath)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.primary)
                                        Text(item.reason)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            if report.quarantined.count > 20 {
                                Text("+ \(report.quarantined.count - 20) more…")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        }

                        if !report.duplicates.isEmpty {
                            Label(
                                String(format: vm.L(L10n.Quarantine.duplicatesFound), Int64(report.duplicates.count)),
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.system(size: 13))
                            .foregroundColor(.orange)

                            ForEach(Array(report.duplicates.prefix(20).enumerated()), id: \.offset) { _, dup in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "doc.on.doc.fill")
                                        .foregroundColor(.orange.opacity(0.7))
                                        .font(.system(size: 10))
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(dup.uniqueId)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.primary)
                                        Text("\(dup.enabledFolder)  ⇄  \(dup.disabledFolder)")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(12)
                } else {
                    // Atteignable depuis que l'entrée est permanente (B2-T3) :
                    // aucune analyse n'a encore tourné (jeu non configuré, ou
                    // rapport jamais produit). Même message que le rapport
                    // vide, plutôt qu'un blanc entre le sous-titre et les
                    // boutons.
                    Text(vm.L(L10n.Quarantine.noQuarantine))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                // Actions
                HStack(spacing: 12) {
                    Button(action: { vm.refresh() }) {
                        Label(vm.L(L10n.Quarantine.rescan), systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    // `refresh()` est le « rafraîchissement manuel » établi —
                    // celui des installations et de l'accueil — et c'est le seul
                    // chemin qui relance la réparation dont cette page publie
                    // le rapport. Inactif pendant le scan : un second clic
                    // lancerait une double traversée du parc.
                    .disabled(vm.scanProgress != nil)
                    if vm.scanProgress != nil {
                        ProgressView().controlSize(.small)
                    }

                    Button(action: openQuarantineFolder) {
                        Label(vm.L(L10n.Quarantine.openFolder), systemImage: "folder.fill")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(quarantineDir == nil)

                    Button(role: .destructive, action: { showEmptyConfirmation = true }) {
                        Label(vm.L(L10n.Quarantine.emptyTrash), systemImage: "trash.fill")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .disabled(quarantineDir == nil)
                }

                if let result = vm.quarantineActionMessage {
                    Label(result.text, systemImage: result.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(result.isError ? .red : .green)
                        .padding(12)
                        .background((result.isError ? Color.red : Color.green).opacity(0.08))
                        .cornerRadius(8)
                }

                Spacer(minLength: 20)
            }
            .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            vm.L(L10n.Quarantine.emptyConfirmTitle),
            isPresented: $showEmptyConfirmation,
            titleVisibility: .visible
        ) {
            Button(vm.L(L10n.Quarantine.emptyTrash), role: .destructive) {
                emptyToMacTrash()
            }
            Button(vm.L(L10n.Main.ok), role: .cancel) {}
        } message: {
            Text(vm.L(L10n.Quarantine.emptyConfirmMessage))
        }
    }

    // MARK: - Actions

    /// Resolves the most recent `_Trash_` folder in the game dir (if any).
    /// The reported path is validated to be inside the game directory and
    /// start with `_Trash_` before being returned, preventing a crafted
    /// or stale report from escaping the expected containment.
    private var quarantinePath: String? {
        guard !vm.gameDir.isEmpty else { return nil }
        let gameDirURL = URL(fileURLWithPath: vm.gameDir).resolvingSymlinksInPath()
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: gameDirURL.path) else { return nil }
        // Prefer the path from the last report, fall back to the newest
        // _Trash_* folder on disk.
        if let reported = vm.lastRepairReport?.trashPath,
           FileManager.default.fileExists(atPath: reported) {
            let reportedURL = URL(fileURLWithPath: reported).resolvingSymlinksInPath()
            let lastComponent = reportedURL.lastPathComponent
            // Containment: must be inside gameDir and have the quarantine
            // naming prefix so a stale/malformed report can't point
            // outside the expected tree.
            if lastComponent.hasPrefix("_Trash_"),
               reportedURL.path.hasPrefix(gameDirURL.path + "/") {
                return reported
            }
        }
        let trashFolders = entries
            .filter { $0.hasPrefix("_Trash_") }
            .sorted()
        guard let newest = trashFolders.last else { return nil }
        return (vm.gameDir as NSString).appendingPathComponent(newest)
    }

    private func openQuarantineFolder() {
        guard let path = quarantinePath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Moves all `_Trash_*` folders in the game dir to the Mac Trash using
    /// the standard NSWorkspace API. On success, clears the repair report so
    /// the sidebar badge disappears. The result is published on the VM (not
    /// @State on this struct) because the recycle completion fires
    /// asynchronously after this View struct may have been recreated.
    private func emptyToMacTrash() {
        let vm = self.vm
        guard !vm.gameDir.isEmpty else { return }
        let fm = FileManager.default
        let gameDirURL = URL(fileURLWithPath: vm.gameDir).resolvingSymlinksInPath()
        guard let entries = try? fm.contentsOfDirectory(atPath: gameDirURL.path) else { return }
        let trashURLs = entries
            .filter { $0.hasPrefix("_Trash_") }
            .map { gameDirURL.appendingPathComponent($0) }

        guard !trashURLs.isEmpty else {
            vm.quarantineActionMessage = .init(text: vm.L(L10n.Quarantine.noQuarantine), isError: false)
            return
        }

        NSWorkspace.shared.recycle(trashURLs, completionHandler: { _, error in
            DispatchQueue.main.async {
                if let error = error {
                    vm.quarantineActionMessage = .init(text: error.localizedDescription, isError: true)
                } else {
                    vm.quarantineActionMessage = .init(text: vm.L(L10n.Quarantine.emptied), isError: false)
                    vm.lastRepairReport = nil
                }
            }
        })
    }
}


// MARK: - Poids du parc (B2-T2)

/// Ce que pèsent les mods, en pied de barre latérale.
///
/// Mesuré sur le parc réel le 2026-08-24 : **16,84 Go de mods, dont 12,71 Go
/// en pause** — 746 dossiers sur 863 — pour 30 Go libres. C'est ce rapport-là
/// que la barre montre, et c'est pour lui qu'elle existe : le total seul ne
/// dit pas que les trois quarts de la place sont immobilisés par des mods
/// désactivés, alors qu'une barre coupée aux trois quarts le dit sans qu'on
/// lise un chiffre.
///
/// **La barre ne compte que les mods** (100 % = le total mesuré), partagée
/// entre actifs et en pause. La place libre reste du texte : `mods + libre`
/// ne forme pas un tout — il y a ~450 Go d'autre chose sur ce volume — et un
/// troisième segment énoncerait une proportion fausse.
///
/// Ses deux couleurs sont celles des barres d'accent de la liste des mods
/// (vert pour un mod actif, gris pour un mod en pause) : le pied de barre
/// résume la liste, il doit en parler la langue.
///
/// Rien ne s'affiche tant qu'aucun jeu n'est désigné : « 0 octet » serait faux.
struct ModsWeightFooter: View {
    @ObservedObject var vm: StarHubTHViewModel

    /// Reprises telles quelles de `ModListRow` : la barre d'accent verte d'un
    /// mod actif, le gris d'un mod en pause.
    private static let activeColor = Color(red: 0.20, green: 0.65, blue: 0.35)
    private static let pausedColor = Color.secondary.opacity(AppDesign.Opacity.strong)

    var body: some View {
        if let sizes = vm.modsFolderSizes {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(String(format: vm.L(L10n.Main.sidebarModsWeight),
                                Self.bytes(sizes.totalBytes)))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    if vm.isMeasuringModsFolder {
                        ProgressView().controlSize(.mini).scaleEffect(0.6)
                    }
                }

                // Sans mod en pause, il n'y a pas de partage à montrer : la
                // barre serait d'une seule couleur et sa légende d'un seul
                // point, soit une décoration. Le total et la place libre disent
                // alors tout.
                //
                // Un parc vide, lui, n'a pas de proportion du tout — et le
                // rapport vaudrait une division par zéro, qui donne une largeur
                // `NaN` : une erreur d'exécution SwiftUI, pas une barre plate.
                if sizes.totalBytes > 0, sizes.pausedBytes > 0 {
                    weightBar(sizes)
                    legend(sizes)
                }

                if let free = sizes.availableBytes {
                    Text(String(format: vm.L(L10n.Main.sidebarDiskFree), Self.bytes(free)))
                        .font(.system(size: 9).monospacedDigit())
                        // Orange quand il reste moins que ce que pèsent déjà
                        // les mods : le prochain gros mod ne rentrera pas.
                        .foregroundStyle(free < sizes.totalBytes ? Color.orange : Color.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.a11yLabel(sizes, vm: vm))
        } else if vm.isMeasuringModsFolder {
            // Sans cet état, le pied reste vide plusieurs secondes au
            // lancement — de trois à six secondes de traversée sur 100 000
            // fichiers — et le vide se lit comme un défaut.
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini).scaleEffect(0.6)
                Text(vm.L(L10n.Main.sidebarModsWeightMeasuring))
                    .font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// La part active posée sur toute la largeur, qui porte la part en pause.
    ///
    /// `GeometryReader` sous une hauteur **explicite** : laissé libre dans la
    /// pile de la barre latérale, il réclamerait toute la hauteur restante et
    /// pousserait les boutons de thème et de langue hors de l'écran.
    private func weightBar(_ sizes: ModsFolderSizes) -> some View {
        let active = Double(sizes.totalBytes - sizes.pausedBytes) / Double(sizes.totalBytes)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Self.pausedColor)
                Capsule()
                    .fill(Self.activeColor)
                    // Un filet minimal : une part active infime doit rester
                    // visible, sinon la barre laisse croire qu'il n'y a rien
                    // d'actif du tout.
                    .frame(width: max(active > 0 ? 2 : 0, geo.size.width * active))
            }
        }
        .frame(height: 5)
    }

    /// « 4,1 Go actifs · 12,7 Go en pause », chaque part sous sa couleur.
    private func legend(_ sizes: ModsFolderSizes) -> some View {
        HStack(spacing: 5) {
            dot(Self.activeColor)
            Text(String(format: vm.L(L10n.Main.sidebarModsWeightActive),
                        Self.bytes(sizes.totalBytes - sizes.pausedBytes)))
            dot(Self.pausedColor)
            Text(String(format: vm.L(L10n.Main.sidebarModsWeightAsleep),
                        Self.bytes(sizes.pausedBytes)))
        }
        .font(.system(size: 9).monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 5, height: 5)
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    /// Une barre ne se lit pas à voix haute : le lecteur d'écran reçoit les
    /// mêmes chiffres que les lignes de texte.
    static func a11yLabel(_ sizes: ModsFolderSizes, vm: StarHubTHViewModel) -> String {
        let label = String(format: vm.L(L10n.Main.sidebarModsWeightA11y),
                           bytes(sizes.totalBytes),
                           bytes(sizes.totalBytes - sizes.pausedBytes),
                           bytes(sizes.pausedBytes),
                           sizes.availableBytes.map { bytes($0) } ?? "—")
        // `children: .ignore` remplace tout ce que contient le pied de barre,
        // y compris l'indicateur de mesure en cours. Sans cet ajout, un lecteur
        // d'écran recevrait des chiffres périmés pendant les secondes qui
        // suivent chaque bascule, sans rien pour le dire.
        guard vm.isMeasuringModsFolder else { return label }
        return label + " " + vm.L(L10n.Main.sidebarModsWeightMeasuring)
    }
}
