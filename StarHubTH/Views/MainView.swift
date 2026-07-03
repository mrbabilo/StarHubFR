import SwiftUI

struct MainView: View {
    @StateObject var vm = StarHubTHViewModel()
    @State private var currentTab: String = "Saves"
    @State private var searchText: String = ""
    
    @AppStorage("appColorScheme") private var appColorScheme: String = "System"
    @AppStorage("showDeveloperLogs") private var showDeveloperLogs: Bool = false
    @AppStorage("launchProfile") private var launchProfile: String = "SMAPI"
    
    @State private var isProfileHovered = false
    
    private func matchesSearch(_ text: String...) -> Bool {
        if searchText.isEmpty { return true }
        let lowerSearch = searchText.lowercased()
        return text.contains { $0.lowercased().contains(lowerSearch) }
    }
    
    var body: some View {
        ZStack {
            NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(vm.localizedString(for: "ค้นหา (Search)"), text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                
                // Account Section (macOS style profile)
                if matchesSearch(vm.steamUsername, "Player", "Steam Account", "Home", "Profile", "บัญชีผู้ใช้") {
                    Button(action: { currentTab = "Home" }) {
                        HStack(spacing: 12) {
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
                                
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vm.steamUsername.isEmpty ? "Player" : vm.steamUsername)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.primary)
                                Text("Steam Account")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
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
                
                // Tools Section
                VStack(alignment: .leading, spacing: 2) {
                    if matchesSearch(vm.localizedString(for: "เซฟเกม (Saves)"), "Saves") {
                        SidebarNavItem(
                            icon: "folder.fill",
                            iconColor: .blue,
                            label: vm.localizedString(for: "เซฟเกม (Saves)"),
                            tab: "Saves",
                            currentTab: $currentTab
                        )
                    }
                    
                    if matchesSearch(vm.localizedString(for: "ส่วนเสริม (Mods)"), "Mods") {
                        SidebarNavItem(
                            icon: "puzzlepiece.extension.fill",
                            iconColor: .purple,
                            label: vm.localizedString(for: "ส่วนเสริม (Mods)"),
                            tab: "Mods",
                            currentTab: $currentTab
                        )
                    }
                    
                    if matchesSearch(vm.localizedString(for: "ตั้งค่าระบบ (Settings)"), "Settings", "Set") {
                        SidebarNavItem(
                            icon: "gearshape.fill",
                            iconColor: .gray,
                            label: vm.localizedString(for: "ตั้งค่าระบบ (Settings)"),
                            tab: "Settings",
                            currentTab: $currentTab
                        )
                    }
                }
                
                if showDeveloperLogs {
                    VStack(alignment: .leading, spacing: 2) {
                        if matchesSearch(vm.localizedString(for: "บันทึกระบบ (Logs)"), "Logs") {
                            SidebarNavItem(
                                icon: "terminal.fill",
                                iconColor: .black,
                                label: vm.localizedString(for: "บันทึกระบบ (Logs)"),
                                tab: "Logs",
                                currentTab: $currentTab
                            )
                        }
                    }
                }
                
                Spacer()
                
                // Launch Button
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: { vm.launchGame() }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text(vm.localizedString(for: vm.isPlayingGame ? "กำลังเปิดเกม..." : "เข้าสู่เกม"))
                        }
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.blue)
                    .disabled(vm.isPlayingGame)
                    .pointingHandCursor()
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
                    ModListView(vm: vm)
                } else if currentTab == "Saves" {
                    if let save = vm.editingSave {
                        SaveEditorView(vm: vm, save: save)
                            // Remove any extra background here because SaveEditorView will set its own
                    } else {
                        SavesView(vm: vm)
                    }
                } else if currentTab == "Settings" {
                    SettingsView(vm: vm)
                } else if currentTab == "Logs" {
                    LogsView(vm: vm)
                } else {
                    HomeView(vm: vm)
                }
            }
            .navigationTitle(
                (currentTab == "Saves" && vm.editingSave != nil) ? Text(vm.editingSave!.playerName) :
                (currentTab == "Mods" ? Text(vm.localizedString(for: "ส่วนเสริม (Mods)")) :
                (currentTab == "Saves" ? Text(vm.localizedString(for: "เซฟเกม (Saves)")) :
                (currentTab == "Settings" ? Text(vm.localizedString(for: "ตั้งค่าระบบ (Settings)")) :
                (currentTab == "Logs" ? Text(vm.localizedString(for: "บันทึกระบบ (Logs)")) : Text(vm.localizedString(for: "หน้าแรก (Home)"))))))
            )
            .onChange(of: currentTab) {
                vm.editingSave = nil
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 8) {
                        Button(action: {
                            if vm.editingSave != nil {
                                vm.editingSave = nil
                            }
                        }) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(vm.editingSave == nil)
                        
                        Button(action: { }) {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(true)
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 460)
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        
        } // End of outer ZStack
        .frame(width: 900, height: 600)
        .preferredColorScheme(colorScheme)
        .environment(\.locale, Locale(identifier: vm.currentLanguage))
        .alert(isPresented: $vm.showAlert) {
            Alert(title: Text("แจ้งเตือน"), message: Text(vm.alertMessage), dismissButton: .default(Text("ตกลง")))
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
            HStack(spacing: 10) {
                // Colored icon box
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(iconColor)
                        .frame(width: 28, height: 28)
                        .shadow(color: Color.black.opacity(0.1), radius: 1, y: 1)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text(label)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected
                          ? Color.primary.opacity(0.1)
                          : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered = $0 }
        .pointingHandCursor()
    }
}

