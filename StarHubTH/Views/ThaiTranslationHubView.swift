import SwiftUI

struct ThaiTranslationHubView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var searchText = ""
    
    var filteredMods: [ThaiTranslationMod] {
        if searchText.isEmpty {
            return vm.thaiTranslations
        } else {
            return vm.thaiTranslations.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        if let mod = vm.viewingThaiMod {
            ThaiModDetailView(vm: vm, mod: mod)
        } else {
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // Header Block (Like 'Privacy' block in macOS settings)
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        // Icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue)
                            Image(systemName: "globe.asia.australia.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 16))
                        }
                        .frame(width: 32, height: 32)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(vm.L(L10n.ThaiHub.title))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.primary)
                            
                            Text(vm.L(L10n.ThaiHub.note))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                        }
                        
                    }
                    .padding(16)
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)
                
                if vm.thaiTranslations.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(vm.L(L10n.ThaiHub.loading))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredMods.enumerated()), id: \.element.id) { index, mod in
                            ThaiModRow(vm: vm, mod: mod)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    vm.viewingThaiMod = mod
                                }
                            
                            if index < filteredMods.count - 1 {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                }
            }
            .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .searchable(text: $searchText, prompt: Text(vm.L(L10n.Main.search)))
        .onAppear {
            if vm.thaiTranslations.isEmpty {
                vm.fetchThaiTranslations()
            } else {
                vm.evaluateThaiTranslationStatus()
            }
        }
        }
    }
}

struct ThaiModRow: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ThaiTranslationMod
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {

            
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.name)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)
                
                if mod.isInstalled {
                    Text("\(mod.author) • v\(mod.version) • \(vm.L(L10n.ThaiHub.installed))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("\(mod.author) • v\(mod.version)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary.opacity(0.5))
                .font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { isHovered = $0 }
    }
}

struct ThaiModDetailView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ThaiTranslationMod
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    
                    // Description Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text(vm.L(L10n.ThaiHub.description))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                            
                        VStack(alignment: .leading, spacing: 0) {
                            Text(vm.L(L10n.ThaiHub.descriptionPrefix) + mod.name + vm.L(L10n.ThaiHub.descriptionSuffix))
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .lineSpacing(4)
                                .padding(16)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    // Installation Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text(vm.L(L10n.ThaiHub.installation))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                            
                        VStack(spacing: 0) {
                            HStack {
                                Text(vm.L(L10n.ThaiHub.status))
                                    .font(.system(size: 13))
                                Spacer()
                                Text(mod.installationStatusText(vm: vm))
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            
                            Divider().padding(.leading, 16)
                            
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(vm.L(L10n.ThaiHub.downloadAndInstall))
                                        .font(.system(size: 13))
                                        
                                    HStack(spacing: 4) {
                                        Text(vm.L(mod.isInstalled ? L10n.ThaiHub.alreadyInstalled : L10n.ThaiHub.clickToInstall))
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                
                                Button(action: { vm.installThaiTranslation(mod: mod) }) {
                                    Text(vm.L(mod.isInstalled ? L10n.ThaiHub.reinstall : L10n.ThaiHub.install))
                                        .font(.system(size: 12))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 4)
                                        .background(Color.primary.opacity(0.1))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .pointingHandCursor()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    // Thai Translation Mod Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text(vm.L(L10n.ThaiHub.thaiTranslationMod))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                        
                        VStack(spacing: 0) {
                            HStack {
                                Text(vm.L(L10n.ThaiHub.translator))
                                    .font(.system(size: 13))
                                Spacer()
                                Text("AppleBoiy & Contributors")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            
                            Divider().padding(.leading, 16)
                            
                            HStack {
                                Text(vm.L(L10n.ThaiHub.version))
                                    .font(.system(size: 13))
                                Spacer()
                                Text("v\(mod.version)")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            
                            Divider().padding(.leading, 16)
                            
                            HStack {
                                Text(vm.L(L10n.ThaiHub.destinationFolder))
                                    .font(.system(size: 13))
                                Spacer()
                                Text("Mods/")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    // Original Mod Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text(vm.L(L10n.ThaiHub.originalMod))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                        
                        VStack(spacing: 0) {
                            HStack {
                                Text(vm.L(L10n.ThaiHub.author))
                                    .font(.system(size: 13))
                                Spacer()
                                Text(mod.author)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            
                            Divider().padding(.leading, 16)
                            
                            HStack {
                                Text(vm.L(L10n.ThaiHub.website))
                                    .font(.system(size: 13))
                                Spacer()
                                Button(action: {
                                    let targetUrl = mod.nexusUrl.isEmpty ? mod.url : mod.nexusUrl
                                    if let url = URL(string: targetUrl) { NSWorkspace.shared.open(url) }
                                }) {
                                    Text(vm.L(L10n.ThaiHub.viewOnNexus))
                                        .font(.system(size: 13))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .pointingHandCursor()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    Spacer()
                }
                .padding(30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
