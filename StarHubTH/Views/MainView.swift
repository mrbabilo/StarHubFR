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
                if matchesSearch(vm.steamUsername, vm.localizedString(for: "บัญชีผู้ใช้")) {
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
                    if matchesSearch(vm.localizedString(for: "เซฟเกม (Saves)")) {
                        SidebarNavItem(
                            icon: "folder.fill",
                            iconColor: .blue,
                            label: vm.localizedString(for: "เซฟเกม (Saves)"),
                            tab: "Saves",
                            currentTab: $currentTab
                        )
                    }
                    
                    if matchesSearch(vm.localizedString(for: "ส่วนเสริม (Mods)")) {
                        SidebarNavItem(
                            icon: "puzzlepiece.extension.fill",
                            iconColor: .purple,
                            label: vm.localizedString(for: "ส่วนเสริม (Mods)"),
                            tab: "Mods",
                            currentTab: $currentTab
                        )
                    }
                    
                    if matchesSearch(vm.localizedString(for: "ตั้งค่าระบบ (Settings)")) {
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
                        if matchesSearch(vm.localizedString(for: "บันทึกระบบ (Logs)")) {
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
                
                let alertCount = vm.smapiErrors.count + vm.outOfDateMods.count
                if alertCount > 0 {
                    Button(action: { currentTab = "Updates" }) {
                        HStack {
                            Text(vm.smapiErrors.isEmpty ? vm.localizedString(for: "อัปเดตซอฟต์แวร์ (Updates)") : vm.localizedString(for: "แจ้งเตือนระบบ (Alerts)"))
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
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(currentTab == "Updates" ? Color.blue : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .pointingHandCursor()
                    .padding(.bottom, 8)
                }
                
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
                } else if currentTab == "Updates" {
                    UpdatesView(vm: vm, currentTab: $currentTab)
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
                (currentTab == "Updates" ? Text(vm.localizedString(for: "อัปเดตซอฟต์แวร์ (Updates)")) :
                (currentTab == "Saves" ? Text(vm.localizedString(for: "เซฟเกม (Saves)")) :
                (currentTab == "Settings" ? Text(vm.localizedString(for: "ตั้งค่าระบบ (Settings)")) :
                (currentTab == "Logs" ? Text(vm.localizedString(for: "บันทึกระบบ (Logs)")) : Text(vm.localizedString(for: "หน้าแรก (Home)")))))))
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
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(width: 24, alignment: .center)
                
                Text(label)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
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
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.1))
                                    Text(String(mod.name.prefix(2)).uppercased())
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.blue.opacity(0.8))
                                }
                                .frame(width: 56, height: 56)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mod.name)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.primary)
                                    Text(mod.version)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    
                                    Text(vm.localizedString(for: "มีการอัปเดตใหม่ในเว็บไซต์ Nexus Mods"))
                                        .font(.system(size: 12))
                                        .foregroundColor(.red.opacity(0.8))
                                        .padding(.top, 2)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 8) {
                                    Button(action: {
                                        if let url = URL(string: mod.url) {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }) {
                                        Text(vm.localizedString(for: "ดาวน์โหลด (Download)"))
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
                                Text(vm.localizedString(for: "อัปเดตนี้เพิ่มคุณสมบัติใหม่และแก้ไขข้อบกพร่องสำหรับม็อดของคุณ"))
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                
                                Text("\(vm.localizedString(for: "สำหรับข้อมูลเกี่ยวกับเนื้อหาของอัปเดตนี้ โปรดไปที่เว็บไซต์:")) [\(mod.url)](\(mod.url))")
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
                
                // SMAPI Errors (More Storage Required style)
                if !vm.smapiErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 16))
                            let errorText = String(format: vm.localizedString(for: "พบข้อผิดพลาดจากตัวเกม หรือม็อด (%lld รายการ)"), vm.smapiErrors.count)
                            Text(errorText)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer()
                            Button(action: { currentTab = "Logs" }) {
                                Text(vm.localizedString(for: "ดูบันทึกระบบ (Logs)"))
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
                        
                        Text(vm.localizedString(for: "เกมพบข้อผิดพลาดระหว่างการรันครั้งล่าสุด ซึ่งอาจเกิดจากม็อดที่ล้าสมัยหรือไฟล์ที่ขาดหายไป"))
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
