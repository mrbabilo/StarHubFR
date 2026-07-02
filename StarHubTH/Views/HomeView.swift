import SwiftUI

struct HomeView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @ObservedObject var smapiInstaller: SmapiInstaller

    init(vm: StarHubTHViewModel) {
        self.vm = vm
        self.smapiInstaller = vm.smapiInstaller
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .center, spacing: 24) {
                
                // ── USER PROFILE HEADER ──
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.1))
                            .frame(width: 100, height: 100)
                        
                        if let avatarPath = vm.steamAvatarPath, let nsImage = NSImage(contentsOfFile: avatarPath) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                        }
                        
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).frame(width: 32, height: 32))
                            .offset(x: 35, y: 35)
                    }
                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .padding(.top, 32)
                    
                    VStack(spacing: 4) {
                        Text(vm.steamUsername)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.primary)
                        Text("Stardew Valley • เวอร์ชัน 1.6 • ภาษาไทย")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
                
                // ── GAME INFO BLOCK ──
                StandardSection(title: "ข้อมูลระบบเกม") {
                    StandardRow(title: "ผู้พัฒนา", detail: "ConcernedApe", showDivider: true)
                    StandardRow(title: "ตัวจัดการม็อด", detail: "SMAPI \(vm.smapiInstalledVersion == "ยังไม่ได้ติดตั้ง" ? "ไม่ได้ติดตั้ง" : vm.smapiInstalledVersion)", showDivider: true)
                    StandardRow(title: "ม็อดที่ติดตั้ง", detail: "\(vm.mods.count) รายการ", showDivider: false)
                }
                .padding(.horizontal, 40)
                
                // ── SYSTEM SETTINGS SECTIONS ──
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Folder Settings
                    StandardSection(title: "โฟลเดอร์เกม") {
                        HStack {
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ที่ตั้งไฟล์เกม")
                                    .font(.system(size: 13))
                                Text(vm.gameDir.isEmpty ? "ยังไม่ได้กำหนด" : vm.gameDir)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button("เลือกโฟลเดอร์...") { vm.selectGameDir() }
                        }
                    }
                    
                    // SMAPI Settings
                    StandardSection(title: "ระบบจัดการม็อด (SMAPI)") {
                        HStack {
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("สถานะ SMAPI")
                                    .font(.system(size: 13))
                                Text(vm.smapiInstalledVersion == "ยังไม่ได้ติดตั้ง" ? "ยังไม่ได้ติดตั้ง" : "ติดตั้งแล้ว (v\(vm.smapiInstalledVersion))")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if vm.smapiInstalledVersion == "ยังไม่ได้ติดตั้ง" {
                                Button("ติดตั้ง SMAPI") { vm.installSmapi() }
                            } else {
                                Button("ถอนการติดตั้ง") { vm.uninstallSmapi() }
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)
                
                // ── CORE EXTENSIONS SECTION ──
                StandardSection(title: "ส่วนเสริมหลัก (Core Extensions)") {
                    VStack(spacing: 0) {
                        CoreModRow(
                            title: "Content Patcher",
                            isInstalled: vm.mods.contains { $0.name.lowercased().contains("content patcher") && $0.isEnabled }
                        )
                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)
                        
                        CoreModRow(
                            title: "SpaceCore",
                            isInstalled: vm.mods.contains { $0.name.lowercased().contains("spacecore") && $0.isEnabled }
                        )
                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)
                        
                        CoreModRow(
                            title: "Stardew Valley Thai",
                            isInstalled: vm.isThaiTranslationInstalled
                        )
                    }
                    .padding(.vertical, -8)
                }
                .padding(.horizontal, 40)
                
                Spacer(minLength: 40)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}


// Helper for core mod status rows
struct CoreModRow: View {
    let title: String
    let isInstalled: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                Text(isInstalled ? "ติดตั้งและเปิดใช้งานแล้ว" : "ไม่ได้ติดตั้ง หรือปิดใช้งานอยู่")
                    .font(.system(size: 12))
                    .foregroundColor(isInstalled ? .secondary : .red)
            }
            Spacer()
            if isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}
