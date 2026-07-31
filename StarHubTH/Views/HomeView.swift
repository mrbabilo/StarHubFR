import SwiftUI

struct HomeView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @ObservedObject var smapiInstaller: SmapiInstaller

    // Mirrors the key launchGame() reads, so the subtitle reflects the mode that fires.
    @AppStorage("launchProfile") private var launchProfile: String = "SMAPI"

    init(vm: StarHubTHViewModel) {
        self.vm = vm
        self.smapiInstaller = vm.smapiInstaller
    }
    
    private var bannerWithAvatarOverlay: some View {
        ZStack(alignment: .bottom) {
            // Nexus banner
            if let url = Bundle.main.url(forResource: "nexus_banner_final", withExtension: "png"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
            }
            
            // Steam avatar overlay - floats on banner
            VStack(spacing: 0) {
                Spacer()
                avatarCircle
                    .offset(y: 40)
            }
        }
        .padding(.bottom, 40)
    }
    
    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: 100, height: 100)
                .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
            
            if let avatarPath = vm.steamAvatarPath, let nsImage = NSImage(contentsOfFile: avatarPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 92, height: 92)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
            }
            
            // Stardew badge
            Image(systemName: "leaf.fill")
                .font(.system(size: 22))
                .foregroundColor(.green)
                .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).frame(width: 28, height: 28))
                .offset(x: 32, y: 32)
        }
        .frame(width: 100, height: 100)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .center, spacing: 24) {

                // ── BANNER WITH AVATAR OVERLAY ──
                bannerWithAvatarOverlay
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 40)
                    .padding(.top, 28)
                // ── USER INFO ──
                VStack(spacing: 4) {
                    Text(vm.steamUsername)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                    Text(String(format: vm.L(L10n.Home.versionString), appVersion))
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }

                // ── LAUNCH BUTTON ──
                VStack(spacing: 6) {
                    Button(action: { vm.launchGame() }) {
                        Label(vm.L(L10n.Main.launchGame), systemImage: "play.fill")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
                    .disabled(vm.gameDir.isEmpty)

                    Text(launchProfile == "Vanilla"
                        ? vm.L(L10n.Settings.vanillaGame)
                        : vm.L(L10n.Settings.playSMAPI))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                // ── GAME INFO BLOCK ──
                StandardSection(title: vm.L(L10n.Home.appInfo)) {
                    StandardRow(title: LocalizedStringKey(vm.L(L10n.Home.developer)), detail: "AppleBoiy (original) · mrbabilo (fork)", showDivider: true)
                    StandardRow(
                        title: LocalizedStringKey(vm.L(L10n.Home.modManager)),
                        detail: LocalizedStringKey(vm.smapiInstalledVersion == nil
                            ? vm.L(L10n.Home.notInstalled)
                            : "SMAPI \(vm.smapiInstalledVersion!)"),
                        showDivider: true
                    )
                    StandardRow(
                        title: LocalizedStringKey(vm.L(L10n.Home.installedMods)),
                        detail: LocalizedStringKey(String(format: vm.L(L10n.Home.itemCount), Int64(vm.mods.count))),
                        showDivider: false
                    )
                }
                .padding(.horizontal, 40)
                
                // ── SYSTEM SETTINGS SECTIONS ──
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Folder Settings
                    StandardSection(title: vm.L(L10n.Home.gameFolder)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vm.L(L10n.Home.gamePath))
                                    .font(.system(size: 13))
                                if vm.gameDir.isEmpty {
                                    Text(vm.L(L10n.Home.notSet))
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(vm.gameDir)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            Spacer()
                            Button(vm.L(L10n.Home.selectFolder)) { vm.selectGameDir() }
                        }
                    }
                    
                    // SMAPI Settings
                    StandardSection(title: vm.L(L10n.Home.smapiManager)) {
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vm.L(L10n.Home.smapiStatus))
                                        .font(.system(size: 13))
                                    if let version = vm.smapiInstalledVersion {
                                        Text(String(format: vm.L(L10n.Home.smapiInstalled), version))
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text(vm.L(L10n.Home.smapiNotInstalled))
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if smapiInstaller.isInstalling {
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(.trailing, 4)
                                } else if vm.smapiInstalledVersion == nil {
                                    Button(vm.L(L10n.Home.installSmapi)) { vm.installSmapi() }
                                } else {
                                    Button(vm.L(L10n.Home.uninstall)) { vm.uninstallSmapi() }
                                }
                            }
                            
                            if smapiInstaller.isInstalling {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(value: smapiInstaller.progress, total: 1.0)
                                        .progressViewStyle(.linear)
                                        .tint(.blue)
                                        .animation(.easeInOut, value: smapiInstaller.progress)
                                    Text(vm.L(smapiInstaller.statusMessage))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 12)
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)
                
                // ── CORE EXTENSIONS SECTION ──
                StandardSection(title: vm.L(L10n.Home.coreExtensions)) {
                    VStack(spacing: 0) {
                        let core = vm.coreExtensionsSnapshot
                        CoreModRow(vm: vm, title: "Content Patcher", status: core.contentPatcher.status, mod: core.contentPatcher.mod)
                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)

                        CoreModRow(vm: vm, title: "SpaceCore", status: core.spacecore.status, mod: core.spacecore.mod)
                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)

                        CoreModRow(vm: vm, title: "Stardew Valley Thai", status: core.thai.status, mod: core.thai.mod)
                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)

                        CoreModRow(vm: vm, title: "Stardew Valley Expanded", status: core.sve.status, mod: core.sve.mod)
                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)

                        CoreToolRow(
                            title: vm.L(L10n.Home.toolUnar),
                            status: core.unarTool.installed ? .enabledAndInstalled : .notInstalled,
                            tooltip: vm.L(L10n.Home.toolUnarTooltip),
                            installCommand: "brew install unar"
                        )
                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)

                        CoreToolRow(
                            title: vm.L(L10n.Home.toolSevenZip),
                            status: core.sevenZipTool.installed ? .enabledAndInstalled : .notInstalled,
                            tooltip: vm.L(L10n.Home.toolSevenZipTooltip),
                            installCommand: "brew install sevenzip"
                        )
                    }
                    .padding(.vertical, -8)
                }
                .padding(.horizontal, 40)
                
                Spacer(minLength: 40)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { vm.refresh() }
    }
}


// MARK: - Core Mod Status

enum CoreModStatus {
    case enabledAndInstalled
    case installedButDisabled
    case notInstalled
}

struct CoreModSlot {
    let status: CoreModStatus
    let mod: ModItem?
}

struct CoreExtensionsSnapshot {
    let contentPatcher: CoreModSlot
    let spacecore: CoreModSlot
    let thai: CoreModSlot
    let sve: CoreModSlot
    let unarTool: CoreToolSlot
    let sevenZipTool: CoreToolSlot
}

struct CoreToolSlot {
    let installed: Bool
}

// Helper for core mod status rows
struct CoreModRow: View {
    @ObservedObject var vm: StarHubTHViewModel
    let title: String
    let status: CoreModStatus
    let mod: ModItem?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))

                // Author + version when installed, otherwise status text
                if let mod = mod {
                    HStack(spacing: 4) {
                        if !mod.author.isEmpty {
                            Text(mod.author)
                                .foregroundColor(.secondary)
                        }
                        if !mod.author.isEmpty && !mod.version.isEmpty {
                            Text("•").foregroundColor(.secondary.opacity(0.5))
                        }
                        if !mod.version.isEmpty {
                            Text("v\(mod.version)")
                                .foregroundColor(.secondary)
                                .fontDesign(.monospaced)
                        }
                    }
                    .font(.system(size: 11))

                    // Status label below author/version
                    Group {
                        switch status {
                        case .enabledAndInstalled:
                            Text(vm.L(L10n.Home.installedAndEnabled))
                                .foregroundColor(.secondary)
                        case .installedButDisabled:
                            Text(vm.L(L10n.Home.installedButDisabled))
                                .foregroundColor(.orange)
                        case .notInstalled:
                            EmptyView()
                        }
                    }
                    .font(.system(size: 11))
                } else {
                    Text(vm.L(L10n.Home.notInstalledOrDisabled))
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
            }
            Spacer()
            switch status {
            case .enabledAndInstalled:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .installedButDisabled:
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.orange)
            case .notInstalled:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

// Row for a non-mod tool status (e.g. unar)
struct CoreToolRow: View {
    let title: String
    let status: CoreModStatus
    let tooltip: String
    /// Commande à taper quand l'outil manque. Paramétrée : la ligne servait
    /// jusqu'ici au seul `unar` et l'affichait en dur.
    let installCommand: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                Group {
                    switch status {
                    case .enabledAndInstalled:
                        Text("")
                    case .installedButDisabled:
                        Text("")
                    case .notInstalled:
                        Text(installCommand)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .font(.system(size: 11))
            }
            Spacer()
            switch status {
            case .enabledAndInstalled:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .installedButDisabled:
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.orange)
            case .notInstalled:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .help(tooltip)
    }
}
