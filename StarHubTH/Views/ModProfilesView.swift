import SwiftUI

struct ModProfilesView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var isShowingNewProfileAlert = false
    @State private var newProfileName = ""
    @State private var selectedProfileForDetail: ModProfile?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Header
            Text(vm.L(L10n.Profiles.titleFull))
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
                        Text(vm.L(L10n.Profiles.noProfiles))
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
                    Text(vm.L(L10n.Profiles.addProfile))
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
        .alert(vm.L(L10n.Profiles.createNewProfile), isPresented: $isShowingNewProfileAlert) {
            TextField(vm.L(L10n.Profiles.profileNamePlaceholder), text: $newProfileName)
            Button(vm.L(L10n.Profiles.save)) {
                if !newProfileName.isEmpty {
                    vm.createProfile(name: newProfileName)
                    newProfileName = ""
                }
            }
            Button(vm.L(L10n.Profiles.cancel), role: .cancel) {
                newProfileName = ""
            }
        } message: {
            Text(vm.L(L10n.Profiles.newProfileNote))
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
        // A plain Button for the whole row (rather than .onTapGesture) so the
        // nested info Button correctly claims its own tap instead of also
        // triggering the row's applyProfile action underneath it.
        Button(action: {
            vm.applyProfile(id: profile.id)
        }) {
            HStack(spacing: 14) {
                // Circular Avatar
                InitialsAvatar(
                    text: profile.name,
                    size: 40,
                    fillColor: isActive ? Color.accentColor : Color.gray.opacity(0.3),
                    textColor: isActive ? .white : .primary,
                    fontSize: 20,
                    fontWeight: .medium
                )

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.primary)
                    Text(vm.L(isActive ? L10n.Profiles.inUse : L10n.Profiles.inactive))
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
                .help(vm.L(L10n.Profiles.viewDetails))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
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

    /// Mods for the checklist — top-level groups and standalone mods only.
    /// Groups show as a single row; toggling a group toggles all its children.
    /// Computed once in onAppear rather than as a live computed property —
    /// vm.mods doesn't change while this sheet is open, so recomputing the
    /// filter+sort on every checkbox tap (each of which re-renders this
    /// view via editedEnabledMods) would be wasted work.
    @State private var flatMods: [ModItem] = []

    /// All uniqueIds covered by a ModItem (group = all children's ids, single mod = its own id).
    private func idsFor(_ mod: ModItem) -> [String] {
        if mod.isGroup, let children = mod.children {
            return children.map { $0.uniqueId }.filter { !$0.isEmpty }
        }
        return mod.uniqueId.isEmpty ? [] : [mod.uniqueId]
    }

    /// Whether a mod (or group) is fully checked in the current selection.
    private func isChecked(_ mod: ModItem) -> Bool {
        let ids = idsFor(mod)
        return !ids.isEmpty && ids.allSatisfy { editedEnabledMods.contains($0) }
    }

    /// Apply chain-toggle logic on the in-memory editedEnabledMods set
    /// by delegating to the ViewModel's shared logic.
    private func applyChain(mod: ModItem, enable: Bool) {
        editedEnabledMods = vm.applyChainToSet(mod: mod, enable: enable, currentEnabled: editedEnabledMods)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Big Avatar
            InitialsAvatar(text: profile.name, size: 80, fontSize: 40)
                .padding(.top, 24)
                .padding(.bottom, 24)
            
            // Settings Box
            VStack(spacing: 0) {
                // Name Row
                HStack {
                    Text(vm.L(L10n.Profiles.profileName))
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
                        Text(String(format: vm.L(L10n.Profiles.modsInProfile), editedEnabledMods.count))
                            .font(.system(size: 13))
                        Text(vm.L(L10n.Profiles.selectMods))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(vm.L(L10n.Profiles.manage)) {
                        isShowingModsPopover = true
                    }
                    .popover(isPresented: $isShowingModsPopover, arrowEdge: .trailing) {
                        VStack(spacing: 0) {
                            HStack {
                                Text(vm.L(L10n.Profiles.manageMods))
                                    .font(.headline)
                                Spacer()
                                Button(vm.L(L10n.Profiles.selectAll)) {
                                    editedEnabledMods = Set(flatMods.flatMap { idsFor($0) })
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                                .font(.system(size: 11))
                                .pointingHandCursor()
                                
                                Button(vm.L(L10n.Profiles.deselectAll)) {
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
                                    ForEach(flatMods) { mod in
                                        Toggle(mod.name, isOn: Binding(
                                            get: { isChecked(mod) },
                                            set: { isOn in
                                                if vm.chainToggleDependencies {
                                                    // For groups, chain-apply each child
                                                    if mod.isGroup, let children = mod.children {
                                                        for child in children where !child.uniqueId.isEmpty {
                                                            applyChain(mod: child, enable: isOn)
                                                        }
                                                    } else {
                                                        applyChain(mod: mod, enable: isOn)
                                                    }
                                                } else {
                                                    let ids = idsFor(mod)
                                                    if isOn { ids.forEach { editedEnabledMods.insert($0) } }
                                                    else    { ids.forEach { editedEnabledMods.remove($0) } }
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
                        Text(vm.L(L10n.Profiles.deleteProfile))
                            .font(.system(size: 13))
                        Text(vm.L(L10n.Profiles.deleteNote))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(vm.L(L10n.Profiles.delete)) {
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
                .help(vm.L(L10n.Profiles.help))
                
                Spacer()
                
                Button(vm.L(L10n.Profiles.cancel)) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button(vm.L(L10n.Profiles.ok)) {
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
            flatMods = vm.mods
                .filter { !$0.uniqueId.isEmpty || $0.isGroup }
                .sorted { $0.name.lowercased() < $1.name.lowercased() }
            // If this is the active profile, reflect actual filesystem state
            if vm.activeProfileId == profile.id {
                editedEnabledMods = Set(
                    vm.mods.flatMap { mod -> [String] in
                        if mod.isGroup, let children = mod.children {
                            return children.filter { $0.isEnabled }.map { $0.uniqueId }
                        }
                        return mod.isEnabled ? [mod.uniqueId] : []
                    }.filter { !$0.isEmpty }
                )
            } else {
                editedEnabledMods = Set(profile.enabledModIds)
            }
        }    }
}
