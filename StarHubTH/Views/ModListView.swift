import SwiftUI

struct ModListView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var searchText = ""

    var filteredMods: [ModItem] {
        vm.mods.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var activeMods: [ModItem] { filteredMods.filter { $0.isEnabled } }
    var inactiveMods: [ModItem] { filteredMods.filter { !$0.isEnabled } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                // ── Toolbar ───────────────────────────────────────────────
                HStack(spacing: 12) {
                    // Search
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                        TextField("ค้นหาส่วนเสริม...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    .frame(maxWidth: 240)
    
                    Spacer()
    
                    // SMAPI status badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(vm.smapiInstalledVersion == "ยังไม่ได้ติดตั้ง" ? Color.red : Color.green)
                            .frame(width: 8, height: 8)
                            .shadow(color: vm.smapiInstalledVersion == "ยังไม่ได้ติดตั้ง" ? .clear : Color.green.opacity(0.5), radius: 3)
                        
                        Text(LocalizedStringKey(vm.smapiInstalledVersion == "ยังไม่ได้ติดตั้ง" ? "API ออฟไลน์" : "API ทำงานปกติ"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                }
                
                // ── List ──────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 32) {
                    if filteredMods.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary.opacity(0.5))
                            if vm.mods.isEmpty {
                                Text("ไม่พบส่วนเสริมที่ติดตั้ง\nโปรดตรวจสอบโฟลเดอร์เกม")
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            } else {
                                Text(LocalizedStringKey("ไม่พบส่วนเสริม \"\(searchText)\""))
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        if !activeMods.isEmpty {
                            ModSectionGroup(title: "เปิดใช้งานแล้ว", mods: activeMods, vm: vm)
                        }
                        if !inactiveMods.isEmpty {
                            ModSectionGroup(title: "ปิดการใช้งาน", mods: inactiveMods, vm: vm)
                        }
                    }
                }
            }
            .padding(40)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Section Group
struct ModSectionGroup: View {
    let title: String
    let mods: [ModItem]
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        StandardSection(title: title) {
            VStack(spacing: 0) {
                ForEach(Array(mods.enumerated()), id: \.element.id) { idx, mod in
                    ModListRow(mod: mod, vm: vm)
                    if idx < mods.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.05))
                            .frame(height: 1)
                            .padding(.leading, 48)
                            .padding(.vertical, 2)
                    }
                }
            }
            // Offset the default 16px padding inside StandardSection to make it tighter
            .padding(.vertical, -8)
        }
    }
}

// MARK: - Row
struct ModListRow: View {
    let mod: ModItem
    @ObservedObject var vm: StarHubTHViewModel
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            // Icon Placeholder / Cover
            ModCoverView(name: mod.name, size: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: 36, height: 36)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(mod.author)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("v\(mod.version)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Actions (always visible)
            HStack(spacing: 12) {
                    if !mod.nexusUrl.isEmpty {
                        Button {
                            if let url = URL(string: mod.nexusUrl) { NSWorkspace.shared.open(url) }
                        } label: {
                            Image(systemName: "link")
                                .font(.system(size: 14))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("ดูบน Nexus Mods")
                        .pointingHandCursor()
                    }
                    Button {
                        let url = URL(fileURLWithPath: vm.gameDir)
                            .appendingPathComponent("Mods")
                            .appendingPathComponent(mod.folderName)
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("เปิดโฟลเดอร์")
                    .pointingHandCursor()
                }
                .padding(.trailing, 8)

            // macOS Native Switch Toggle
            Toggle("", isOn: Binding(get: { mod.isEnabled }, set: { _ in vm.toggleMod(mod) }))
                .toggleStyle(StardewToggleStyle())
                .labelsHidden()
                .tint(.green)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.secondary.opacity(0.05) : Color.clear)
        .cornerRadius(6)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("เปิดใน Finder") {
                let url = URL(fileURLWithPath: vm.gameDir)
                    .appendingPathComponent("Mods")
                    .appendingPathComponent(mod.folderName)
                NSWorkspace.shared.open(url)
            }
            if !mod.nexusUrl.isEmpty {
                Button("ดูรายละเอียดบน Nexus Mods") {
                    if let url = URL(string: mod.nexusUrl) { NSWorkspace.shared.open(url) }
                }
            }
        }
    }
}
