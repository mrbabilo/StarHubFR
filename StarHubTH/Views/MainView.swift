import SwiftUI

struct MainView: View {
    @StateObject var vm = StarHubTHViewModel()
    @State private var currentTab: String = "Home"
    @State private var searchText: String = ""
    
    // History Management
    @State private var tabHistory: [String] = ["Home"]
    @State private var forwardHistory: [String] = []
    @State private var isNavigatingBackOrForward = false
    
    @AppStorage("appColorScheme") private var appColorScheme: String = "System"
    @AppStorage("showDeveloperLogs") private var showDeveloperLogs: Bool = false
    @AppStorage("launchProfile") private var launchProfile: String = "SMAPI"
    
    @State private var isProfileHovered = false
    
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
        if currentTab == "Mods" { return vm.L(L10n.Mods.mods) }
        if currentTab == "ConfigBackups" { return vm.L(L10n.ModConfigBackups.title) }
        if currentTab == "Profiles" { return vm.L(L10n.Profiles.title) }
        if currentTab == "Updates" { return vm.L(L10n.Main.softwareUpdate) }
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
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
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
                
                let alertCount = vm.smapiErrors.count + vm.outOfDateMods.count + vm.nexusUpdates.count
                if alertCount > 0 {
                    Button(action: { currentTab = "Updates" }) {
                        HStack {
                            Text(vm.smapiErrors.isEmpty ? vm.L(L10n.Main.softwareUpdate) : vm.L(L10n.Main.systemAlerts))
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(currentTab == "Updates" ? .white : .primary)
                            Spacer()
                            Text("\(alertCount)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(currentTab == "Updates" ? .blue : .white)
                                .frame(minWidth: 18, minHeight: 18)
                                .padding(.horizontal, 4)
                                .background(currentTab == "Updates" ? Color.white : Color.red)
                                .clipShape(Capsule())
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(currentTab == "Updates" ? Color.blue : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .pointingHandCursor()
                }
                
                // Game Section
                VStack(alignment: .leading, spacing: 2) {
                    SidebarSectionHeader(title: vm.L(L10n.Main.gameManagement))
                    if matchesSearch(vm.L(L10n.Saves.saves)) {
                        SidebarNavItem(
                            icon: "folder.fill",
                            iconColor: .blue,
                            label: vm.L(L10n.Saves.saves),
                            tab: "Saves",
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

                    if matchesSearch(vm.L(L10n.ModConfigBackups.tabTitle)) {
                        SidebarNavItem(
                            icon: "archivebox.fill",
                            iconColor: .green,
                            label: vm.L(L10n.ModConfigBackups.tabTitle),
                            tab: "ConfigBackups",
                            currentTab: $currentTab
                        )
                    }

                    if matchesSearch(vm.L(L10n.Profiles.title)) {
                        SidebarNavItem(
                            icon: "person.2.fill",
                            iconColor: .orange,
                            label: vm.L(L10n.Profiles.title),
                            tab: "Profiles",
                            currentTab: $currentTab
                        )
                    }
                }
                
                // System & Settings Section
                VStack(alignment: .leading, spacing: 2) {
                    SidebarSectionHeader(title: vm.L(L10n.Main.system))
                    
                    if matchesSearch(vm.L(L10n.Settings.settings)) {
                        SidebarNavItem(
                            icon: "gearshape.fill",
                            iconColor: .gray,
                            label: vm.L(L10n.Settings.settings),
                            tab: "Settings",
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
                
                // Thai Hub Section
                VStack(alignment: .leading, spacing: 2) {
                    SidebarSectionHeader(title: vm.L(L10n.Main.online))
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
                
                if showDeveloperLogs {
                    if matchesSearch(vm.L(L10n.Logs.logs)) {
                            SidebarNavItem(
                                icon: "terminal.fill",
                                iconColor: .black,
                                label: vm.L(L10n.Logs.logs),
                                tab: "Logs",
                                currentTab: $currentTab
                            )
                        }
                    }
                
                Spacer()
                

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
                        ModConfigEditorView(vm: vm, mod: mod)
                    } else {
                        ModListView(vm: vm)
                    }
                } else if currentTab == "ConfigBackups" {
                    ModConfigBackupsView(vm: vm)
                } else if currentTab == "Saves" {
                    if let save = vm.viewingSaveTimeline {
                        SaveTimelineView(vm: vm, save: save)
                    } else if let save = vm.editingSave {
                        SaveEditorView(vm: vm, save: save)
                    } else {
                        SavesView(vm: vm)
                    }
                } else if currentTab == "Profiles" {
                    ModProfilesView(vm: vm)
                } else if currentTab == "Updates" {
                    UpdatesView(vm: vm, currentTab: $currentTab)
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
            .onChange(of: currentTab) {
                vm.editingSave = nil
                vm.viewingThaiMod = nil
                vm.viewingSaveTimeline = nil
                vm.editingModConfig = nil

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
                            } else if tabHistory.count > 1 {
                                isNavigatingBackOrForward = true
                                let current = tabHistory.removeLast()
                                forwardHistory.append(current)
                                currentTab = tabHistory.last ?? "Home"
                            }
                        }) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(vm.editingSave == nil && vm.viewingThaiMod == nil && vm.viewingSaveTimeline == nil && vm.editingModConfig == nil && tabHistory.count <= 1)
                        
                        Button(action: {
                            if let next = forwardHistory.popLast() {
                                isNavigatingBackOrForward = true
                                tabHistory.append(next)
                                currentTab = next
                            }
                        }) {
                            Image(systemName: "chevron.right")
                        }
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
struct SidebarSectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.leading, 8)
            .padding(.top, 8)
            .padding(.bottom, 0)
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
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(width: 20, alignment: .center)
                
                Text(label)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor
                          : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered = $0 }
        .pointingHandCursor()
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
                            Text(vm.L(L10n.Updates.nexusNoUpdates))
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

                                Button {
                                    if let url = URL(string: update.url) {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Text(vm.L(L10n.Updates.download))
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

                // SMAPI Errors (More Storage Required style)
                if !vm.smapiErrors.isEmpty {
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
