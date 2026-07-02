import SwiftUI

struct MainView: View {
    @StateObject var vm = StarHubTHViewModel()
    @State private var currentTab: String = "Profile"
    
    @AppStorage("appColorScheme") private var appColorScheme: String = "System"
    @AppStorage("showDeveloperLogs") private var showDeveloperLogs: Bool = false
    @AppStorage("launchProfile") private var launchProfile: String = "SMAPI"
    
    @State private var isProfileHovered = false
    
    var body: some View {
        ZStack {
            NavigationSplitView {
            List(selection: $currentTab) {
                Section("บัญชีผู้ใช้") {
                    Label(vm.steamUsername, systemImage: "person.crop.circle.fill")
                        .tag("Home")
                }
                
                Section("เครื่องมือและระบบ") {
                    Label("เซฟเกม (Saves)", systemImage: "folder.fill")
                        .tag("Saves")
                    Label("ส่วนเสริม (Mods)", systemImage: "puzzlepiece.extension.fill")
                        .tag("Mods")
                    Label("ตั้งค่าระบบ (Settings)", systemImage: "gearshape.fill")
                        .tag("Settings")
                }
                
                if showDeveloperLogs {
                    Section("นักพัฒนา") {
                        Label("บันทึกระบบ (Logs)", systemImage: "terminal.fill")
                            .tag("Logs")
                    }
                }
                
                Section("พร้อมลุย!") {
                    VStack(spacing: 12) {
                        Button(action: { vm.launchGame() }) {
                            Text(vm.isPlayingGame ? "กำลังเปิดเกม..." : "เข้าสู่เกม")
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .disabled(vm.isPlayingGame)
                        .pointingHandCursor()
                    }
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 240, ideal: 240, max: 240)

        } detail: {
            // ── CONTENT AREA ─────────────────────────────────────────
            Group {
                if currentTab == "Mods" {
                    ModListView(vm: vm)
                } else if currentTab == "Saves" {
                    SavesView(vm: vm)
                } else if currentTab == "Settings" {
                    SettingsView(vm: vm)
                } else if currentTab == "Logs" {
                    LogsView(vm: vm)
                } else {
                    HomeView(vm: vm)
                }
            }
            .navigationTitle(currentTab == "Mods" ? "ส่วนเสริม (Mods)" :
                             currentTab == "Saves" ? "เซฟเกม (Saves)" :
                             currentTab == "Settings" ? "ตั้งค่า (Settings)" :
                             currentTab == "Logs" ? "บันทึก (Logs)" : "หน้าแรก (Home)")
            .frame(minWidth: 600, minHeight: 460)
            .background(Color(nsColor: .controlBackgroundColor).ignoresSafeArea())
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        
        // ── CUSTOM POPUP OVERLAY ──
        if let save = vm.editingSave {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        vm.editingSave = nil
                    }
                
                SaveEditorView(vm: vm, save: save)
                    .frame(width: 450, height: 600)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Ensure the ZStack overlays everything
            .zIndex(100)
        }
        } // End of outer ZStack
        .frame(width: 900, height: 600)
        .preferredColorScheme(colorScheme)
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
                // Colored icon box
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconColor)
                        .frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text(label)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
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

