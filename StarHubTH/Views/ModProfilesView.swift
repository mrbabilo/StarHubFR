import SwiftUI

struct ModProfilesView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var isShowingNewProfileAlert = false
    @State private var newProfileName = ""
    @State private var selectedProfileForDetail: ModProfile?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Header
            Text(vm.localizedString(for: "โปรไฟล์ม็อด (Mod Profiles)"))
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 10)
            
            // List Container
            VStack(spacing: 0) {
                if vm.modProfiles.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(vm.localizedString(for: "ยังไม่มีโปรไฟล์ม็อด"))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    ForEach(Array(vm.modProfiles.enumerated()), id: \.element.id) { index, profile in
                        ProfileRow(profile: profile, isActive: vm.activeProfileId == profile.id, vm: vm, selectedProfileForDetail: $selectedProfileForDetail)
                        
                        if index < vm.modProfiles.count - 1 {
                            Divider()
                                .padding(.leading, 64) // Align with text
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            
            // Add buttons below list, right-aligned
            HStack {
                Spacer()
                Button(action: {
                    isShowingNewProfileAlert = true
                }) {
                    Text(vm.localizedString(for: "เพิ่มโปรไฟล์..."))
                }
            }
            
            Spacer()
        }
        .padding(30)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $selectedProfileForDetail) { profile in
            ProfileDetailSheet(profile: profile, vm: vm, isPresented: Binding(
                get: { selectedProfileForDetail != nil },
                set: { if !$0 { selectedProfileForDetail = nil } }
            ))
        }
        .alert(vm.localizedString(for: "สร้างโปรไฟล์ม็อดใหม่"), isPresented: $isShowingNewProfileAlert) {
            TextField(vm.localizedString(for: "ชื่อโปรไฟล์..."), text: $newProfileName)
            Button(vm.localizedString(for: "บันทึก")) {
                if !newProfileName.isEmpty {
                    vm.createProfile(name: newProfileName)
                    newProfileName = ""
                }
            }
            Button(vm.localizedString(for: "ยกเลิก"), role: .cancel) {
                newProfileName = ""
            }
        } message: {
            Text(vm.localizedString(for: "โปรไฟล์ใหม่จะเริ่มต้นโดยไม่มีม็อดใดๆ เปิดใช้งาน คุณสามารถตั้งค่าม็อดได้ในภายหลัง"))
        }
    }
}

struct ProfileRow: View {
    let profile: ModProfile
    let isActive: Bool
    @ObservedObject var vm: StarHubTHViewModel
    @Binding var selectedProfileForDetail: ModProfile?
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Circular Avatar
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isActive ? .white : .primary)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.primary)
                Text(vm.localizedString(for: isActive ? "กำลังใช้งาน" : "ไม่ได้ใช้งาน"))
                    .font(.system(size: 12))
                    .foregroundColor(isActive ? .secondary : .secondary)
            }
            
            Spacer()
            
            // Info button (or delete)
            Button(action: {
                selectedProfileForDetail = profile
            }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(vm.localizedString(for: "ดูรายละเอียดโปรไฟล์นี้"))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .onTapGesture {
            vm.applyProfile(id: profile.id)
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct ProfileDetailSheet: View {
    let profile: ModProfile
    @ObservedObject var vm: StarHubTHViewModel
    @Binding var isPresented: Bool
    
    @State private var editName: String = ""
    @State private var editedEnabledMods: Set<String> = []
    @State private var isShowingModsPopover = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Big Avatar
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 80, height: 80)
                
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.top, 24)
            .padding(.bottom, 24)
            
            // Settings Box
            VStack(spacing: 0) {
                // Name Row
                HStack {
                    Text(vm.localizedString(for: "ชื่อโปรไฟล์"))
                        .font(.system(size: 13))
                    Spacer()
                    TextField("", text: $editName)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 13))
                        .frame(width: 200)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider().padding(.leading, 16)
                
                // Manage Mods Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: vm.localizedString(for: "ม็อดในโปรไฟล์นี้ (%d ม็อด)"), editedEnabledMods.count))
                            .font(.system(size: 13))
                        Text(vm.localizedString(for: "เลือกม็อดที่คุณต้องการให้เปิดใช้งานในโปรไฟล์นี้"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(vm.localizedString(for: "จัดการ...")) {
                        isShowingModsPopover = true
                    }
                    .popover(isPresented: $isShowingModsPopover, arrowEdge: .trailing) {
                        VStack(spacing: 0) {
                            HStack {
                                Text(vm.localizedString(for: "จัดการม็อดในโปรไฟล์"))
                                    .font(.headline)
                                Spacer()
                                Button(vm.localizedString(for: "เลือกทั้งหมด")) {
                                    editedEnabledMods = Set(vm.mods.map { $0.uniqueId })
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                                .font(.system(size: 11))
                                .pointingHandCursor()
                                
                                Button(vm.localizedString(for: "เอาออกทั้งหมด")) {
                                    editedEnabledMods.removeAll()
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.red)
                                .font(.system(size: 11))
                                .pointingHandCursor()
                            }
                            .padding()
                            Divider()
                            
                            ScrollView {
                                VStack(spacing: 8) {
                                    ForEach(vm.mods) { mod in
                                        Toggle(mod.name, isOn: Binding(
                                            get: { editedEnabledMods.contains(mod.uniqueId) },
                                            set: { isOn in
                                                if isOn {
                                                    editedEnabledMods.insert(mod.uniqueId)
                                                } else {
                                                    editedEnabledMods.remove(mod.uniqueId)
                                                }
                                            }
                                        ))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding()
                            }
                        }
                        .frame(width: 320, height: 400)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider().padding(.leading, 16)
                
                // Delete Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.localizedString(for: "ลบโปรไฟล์ม็อดนี้"))
                            .font(.system(size: 13))
                        Text(vm.localizedString(for: "การลบโปรไฟล์จะไม่ลบไฟล์ม็อดในเครื่องของคุณ"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(vm.localizedString(for: "ลบ...")) {
                        vm.deleteProfile(id: profile.id)
                        isPresented = false
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Cancel / OK
            HStack {
                Button(action: {
                    // Action for Help
                }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help(vm.localizedString(for: "ความช่วยเหลือ"))
                
                Spacer()
                
                Button(vm.localizedString(for: "ยกเลิก")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button(vm.localizedString(for: "ตกลง")) {
                    let finalMods = Array(editedEnabledMods)
                    vm.updateProfile(id: profile.id, newName: editName, enabledModIds: finalMods)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 480, height: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            editName = profile.name
            editedEnabledMods = Set(profile.enabledModIds)
        }
    }
}
