import SwiftUI

struct MainView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var currentTab: String = "Home"
    @State private var searchText: String = ""
    
    // History Management
    @State private var tabHistory: [String] = ["Home"]
    @State private var forwardHistory: [String] = []
    @State private var isNavigatingBackOrForward = false
    
    @AppStorage("appColorScheme") private var appColorScheme: String = "System"
    @AppStorage("showThaiTranslationHub") private var showThaiTranslationHub: Bool = false
    @AppStorage("launchProfile") private var launchProfile: String = "SMAPI"
    
    @State private var isProfileHovered = false
    @State private var showDownloadedInstall = false
    
    private func matchesSearch(_ text: String...) -> Bool {
        if searchText.isEmpty { return true }
        let lowerSearch = searchText.lowercased()
        return text.contains { $0.lowercased().contains(lowerSearch) }
    }
    
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
                
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(vm.L(L10n.Main.search), text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .accessibilityLabel(vm.L(L10n.Main.search))
                }
                .padding(.horizontal, AppDesign.Spacing.sm)
                .padding(.vertical, 6)
                .background(AppDesign.Color.textBg)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(AppDesign.Opacity.light), lineWidth: 1)
                )
                
                // Account Section (macOS style profile)
                if matchesSearch(vm.steamUsername, vm.L(L10n.Main.account)) {
                    Button(action: { currentTab = "Home" }) {
                        let activeProfile = vm.activeProfileId.flatMap { id in vm.modProfiles.first(where: { $0.id == id }) }
                        HStack(spacing: 12) {
                            ZStack(alignment: .bottomTrailing) {
                                if let avatarPath = vm.steamAvatarPath, let nsImage = NSImage(contentsOfFile: avatarPath) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 48, height: 48)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .frame(width: 48, height: 48)
                                        .foregroundColor(.gray)
                                }
                                
                                if let activeProfile = activeProfile {
                                    InitialsAvatar(
                                        text: activeProfile.name,
                                        size: 20,
                                        fontSize: 10,
                                        strokeColor: Color(nsColor: .windowBackgroundColor)
                                    )
                                    .offset(x: 4, y: 4)
                                }
                            }
                                
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vm.steamUsername.isEmpty ? vm.L(L10n.Main.playerFallback) : vm.steamUsername)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.primary)
                                Text(vm.L(L10n.Main.steamAccount))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                
                                if let activeProfile = activeProfile {
                                    Text("\(vm.L(L10n.Profiles.titleFull)): \(activeProfile.name)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.accentColor)
                                        .padding(.top, 2)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(currentTab == "Home" ? Color.primary.opacity(0.1) : (isProfileHovered ? Color.primary.opacity(0.05) : Color.clear))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { isProfileHovered = $0 }
                    .pointingHandCursor()
                }
                
                // Mod Updates: Nexus updates + out-of-date mods (a single
                // badge). Separate from System Alerts so update notifications
                // don't get hidden behind SMAPI error counts.
                let modUpdateCount = vm.outOfDateMods.count + vm.nexusUpdates.count
                if modUpdateCount > 0 {
                    SidebarBadgeItem(
                        label: vm.L(L10n.Main.modUpdates),
                        tab: "Updates",
                        count: modUpdateCount,
                        accentColor: .blue,
                        currentTab: $currentTab
                    )
                }

                // System Alerts: SMAPI errors. These are also logged to the
                // Journaux tab so they remain consultable after the banner
                // is dismissed.
                if !vm.smapiErrors.isEmpty {
                    SidebarBadgeItem(
                        label: vm.L(L10n.Main.systemAlerts),
                        tab: "SystemAlerts",
                        count: vm.smapiErrors.count,
                        accentColor: .orange,
                        currentTab: $currentTab
                    )
                }

                // Quarantine badge: shown only when items have actually been
                // quarantined, so the sidebar doesn't show an empty indicator.
                if let report = vm.lastRepairReport, !report.quarantined.isEmpty {
                    SidebarBadgeItem(
                        label: vm.L(L10n.Main.quarantine),
                        tab: "Quarantine",
                        count: report.quarantined.count,
                        accentColor: .purple,
                        currentTab: $currentTab
                    )
                }
                
                // Game Section
                VStack(alignment: .leading, spacing: 2) {
                    SidebarSectionHeader(title: vm.L(L10n.Main.gameManagement), icon: "gamecontroller")
                    
                    if matchesSearch(vm.L(L10n.Profiles.title)) {
                        SidebarNavItem(
                            icon: "person.2.fill",
                            iconColor: .orange,
                            label: vm.L(L10n.Profiles.title),
                            tab: "Profiles",
                            currentTab: $currentTab
                        )
                    }
                    
                    if matchesSearch(vm.L(L10n.Mods.mods)) {
                        SidebarNavItem(
                            icon: "puzzlepiece.extension.fill",
                            iconColor: .purple,
                            label: vm.L(L10n.Mods.mods),
                            tab: "Mods",
                            currentTab: $currentTab
                        )
                    }

                    if matchesSearch(vm.L(L10n.ModInstall.manageBackups)) {
                        SidebarNavItem(
                            icon: "arrow.uturn.backward.circle.fill",
                            iconColor: .pink,
                            label: vm.L(L10n.ModInstall.manageBackups),
                            tab: "InstallBackups",
                            currentTab: $currentTab
                        )
                    }

                    if matchesSearch(vm.L(L10n.ModConfigBackups.tabTitle)) {
                        SidebarNavItem(
                            icon: "archivebox.fill",
                            iconColor: .green,
                            label: vm.L(L10n.ModConfigBackups.tabTitle),
                            tab: "ConfigBackups",
                            currentTab: $currentTab
                        )
                    }

                    if matchesSearch(vm.L(L10n.Saves.saves)) {
                        SidebarNavItem(
                            icon: "folder.fill",
                            iconColor: .blue,
                            label: vm.L(L10n.Saves.saves),
                            tab: "Saves",
                            currentTab: $currentTab
                        )
                    }
                }
                
                // System & Settings Section
                VStack(alignment: .leading, spacing: 2) {
                    SidebarSectionHeader(title: vm.L(L10n.Main.system), icon: "gearshape")
                    
                    if matchesSearch(vm.L(L10n.Settings.settings)) {
                        SidebarNavItem(
                            icon: "gearshape.fill",
                            iconColor: .gray,
                            label: vm.L(L10n.Settings.settings),
                            tab: "Settings",
                            currentTab: $currentTab
                        )
                    }

                    if matchesSearch(vm.L(L10n.Main.quarantine)) {
                        SidebarNavItem(
                            icon: "archivebox.fill",
                            iconColor: .purple,
                            label: vm.L(L10n.Main.quarantine),
                            tab: "Quarantine",
                            currentTab: $currentTab
                        )
                    }

                    if matchesSearch(vm.L(L10n.Main.appChangelog)) {
                        SidebarNavItem(
                            icon: "doc.text.fill",
                            iconColor: .indigo,
                            label: vm.L(L10n.Main.appChangelog),
                            tab: "AppChangelog",
                            currentTab: $currentTab
                        )
                    }
                }
                
                if showThaiTranslationHub {
                    // Thai Hub Section
                    VStack(alignment: .leading, spacing: 2) {
                        SidebarSectionHeader(title: vm.L(L10n.Main.online), icon: "globe.asia.australia")
                        if matchesSearch(vm.L(L10n.ThaiHub.title)) {
                            SidebarNavItem(
                                icon: "globe.asia.australia.fill",
                                iconColor: .blue,
                                label: vm.L(L10n.ThaiHub.title),
                                tab: "ThaiHub",
                                currentTab: $currentTab
                            )
                        }
                    }
                }
                
                if matchesSearch(vm.L(L10n.Logs.logs)) {
                        SidebarNavItem(
                            icon: "terminal.fill",
                            iconColor: .black,
                            label: vm.L(L10n.Logs.logs),
                            tab: "Logs",
                            currentTab: $currentTab
                        )
                    }

                SystemStatusFooter(vm: vm)

                Spacer()

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
                        .disabled(forwardHistory.isEmpty)
                    }
                }
            }
            .frame(minWidth: 560, minHeight: 400)
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        
        } // End of outer ZStack
        .frame(minWidth: 820, minHeight: 520)
        .preferredColorScheme(colorScheme)
        .environment(\.locale, Locale(identifier: vm.currentLanguage))
        .onReceive(NotificationCenter.default.publisher(for: .jumpToMod)) { notification in
            if let modName = notification.object as? String {
                vm.selectedModID = vm.mods
                    .flatMap { m -> [ModItem] in m.isGroup ? (m.children ?? []) : [m] }
                    .first { $0.name.localizedCaseInsensitiveContains(modName) }?
                    .folderName
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
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isSelected ? accentColor : .white)
                    .frame(minWidth: 18, minHeight: 18)
                    .padding(.horizontal, 4)
                    .background(isSelected ? Color.white : accentColor)
                    .clipShape(Capsule())
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
                                    
                                    Button(action: {}) {
                                        Image(systemName: "info.circle")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 16))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 16) {
                                Text(vm.L(L10n.Updates.updateDescription))
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                
                                Text("\(vm.L(L10n.Updates.visitWebsite)) [\(mod.url)](\(mod.url))")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
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
                                vm.checkNexusUpdates(force: true)
                            } label: {
                                Text(vm.L(L10n.Updates.nexusCheckButton))
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .disabled(!vm.hasNexusApiKey)
                        }
                    }

                    if !vm.hasNexusApiKey {
                        // CTA: prompt user to add an API key.
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
                    } else if vm.isCheckingNexusUpdates {
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

                                if let nexusId = Int(update.nexusModId) {
                                    Button {
                                        vm.downloadModFromNexus(nexusId: nexusId)
                                    } label: {
                                        Label(vm.L(L10n.Mods.premiumUpdate), systemImage: "arrow.down.circle")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(vm.isDownloadingFromNexus)
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
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 28))
                        Text(vm.L(L10n.Updates.nexusNoUpdates))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .background(Color.green.opacity(0.06))
                    .cornerRadius(12)
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
                }

                // Actions
                HStack(spacing: 12) {
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
                    Label(result, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.green)
                        .padding(12)
                        .background(Color.green.opacity(0.08))
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
            vm.quarantineActionMessage = vm.L(L10n.Quarantine.noQuarantine)
            return
        }

        do {
            try NSWorkspace.shared.recycle(trashURLs, completionHandler: { _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        vm.quarantineActionMessage = error.localizedDescription
                    } else {
                        vm.quarantineActionMessage = vm.L(L10n.Quarantine.emptied)
                        vm.lastRepairReport = nil
                    }
                }
            })
        } catch {
            vm.quarantineActionMessage = error.localizedDescription
        }
    }
}
