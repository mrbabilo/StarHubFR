import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: StarHubTHViewModel

    @AppStorage("launchProfile") private var launchProfile: String = "SMAPI"
    @AppStorage("closeAfterLaunch") private var closeAfterLaunch: Bool = false
    @AppStorage("appColorScheme") private var appColorScheme: String = "System"
    @AppStorage("showDeveloperLogs") private var showDeveloperLogs: Bool = false

    // Nexus Mods API key entry (only used when no key is stored yet).
    @State private var nexusApiKeyInput: String = ""
    @State private var nexusKeySavedFlash: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                
                // ── Language ──
                StandardSection(title: vm.L(L10n.Settings.appLanguage)) {
                    HStack {
                        Text(vm.L(L10n.Settings.selectLanguage))
                            .font(.system(size: 13))
                        Spacer()
                        Picker("", selection: $vm.currentLanguage) {
                            Text(vm.L(L10n.Settings.languageThai)).tag("th")
                            Text(vm.L(L10n.Settings.languageEnglish)).tag("en")
                            Text(vm.L(L10n.Settings.languageFrench)).tag("fr")
                        }
                        .pickerStyle(MenuPickerStyle())
                        .fixedSize()
                        
                        InfoPopoverButton(text: vm.L(L10n.Settings.selectLanguage))
                    }
                }

                // ── Nexus Mods ──
                StandardSection(
                    title: vm.L(L10n.Settings.nexusMods),
                    footer: vm.L(L10n.Settings.nexusApiKeyHint)
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        if vm.hasNexusApiKey {
                            // Key stored — offer removal and link to fetch another.
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vm.L(L10n.Settings.nexusApiKey))
                                        .font(.system(size: 13))
                                    Text("••••••••••••")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(action: {
                                    if let url = URL(string: "https://www.nexusmods.com/users/myaccount?tab=api") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    Text(vm.L(L10n.Settings.nexusGetKey))
                                }
                                Button(role: .destructive, action: {
                                    vm.clearNexusApiKey()
                                }) {
                                    Text(vm.L(L10n.Settings.nexusClearKey))
                                }
                            }
                        } else {
                            // No key yet — secure field + save action.
                            VStack(alignment: .leading, spacing: 8) {
                                SecureField(vm.L(L10n.Settings.nexusKeyPlaceholder), text: $nexusApiKeyInput)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.system(size: 12, design: .monospaced))
                                    .autocorrectionDisabled(true)
                                    .textContentType(.password)

                                HStack {
                                    Button(action: {
                                        if let url = URL(string: "https://www.nexusmods.com/users/myaccount?tab=api") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }) {
                                        Text(vm.L(L10n.Settings.nexusGetKey))
                                    }

                                    Spacer()

                                    if nexusKeySavedFlash {
                                        Text(vm.L(L10n.Settings.nexusKeySaved))
                                            .font(.system(size: 11))
                                            .foregroundColor(.green)
                                            .transition(.opacity)
                                    }

                                    Button {
                                        let trimmed = nexusApiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !trimmed.isEmpty else { return }
                                        vm.setNexusApiKey(trimmed)
                                        nexusApiKeyInput = ""
                                        withAnimation { nexusKeySavedFlash = true }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            withAnimation { nexusKeySavedFlash = false }
                                        }
                                    } label: {
                                        Text(vm.L(L10n.Settings.nexusSaveKey))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(nexusApiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                        }
                    }
                }

                // ── Launch Options ──
                StandardSection(
                    title: vm.L(L10n.Settings.launchOptions),
                    footer: vm.L(L10n.Settings.footerLaunch)
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(vm.L(L10n.Settings.defaultLaunchMode))
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $launchProfile) {
                                Text(vm.L(L10n.Settings.playSMAPI)).tag("SMAPI")
                                Text(vm.L(L10n.Settings.vanillaGame)).tag("Vanilla")
                            }
                            .pickerStyle(MenuPickerStyle())
                            .fixedSize()
                            
                            InfoPopoverButton(text: vm.L(L10n.Settings.hintNextLaunchMode))
                        }
                        
                        Divider().padding(.leading, 0)
                        
                        HStack {
                            Text(vm.L(L10n.Settings.closeLauncher))
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: $closeAfterLaunch)
                                .toggleStyle(SwitchToggleStyle(tint: .blue))
                                .controlSize(.small)
                                .labelsHidden()
                            
                            InfoPopoverButton(text: vm.L(L10n.Settings.hintSaveResources))
                        }
                    }
                }
                
                // ── Backup ──
                StandardSection(
                    title: vm.L(L10n.Settings.backup),
                    footer: vm.L(L10n.Settings.footerBackup)
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(vm.L(L10n.Settings.backupSaves))
                                .font(.system(size: 13))
                            Spacer()
                            Button(action: { vm.backupAllSaves() }) {
                                Text(vm.L(L10n.Settings.backupSavesButton))
                            }
                            InfoPopoverButton(text: vm.L(L10n.Settings.hintCompressSaves))
                        }
                        
                        Divider().padding(.leading, 0)
                        
                        HStack {
                            Text(vm.L(L10n.Settings.backupMods))
                                .font(.system(size: 13))
                            Spacer()
                            Button(action: { vm.backupAllMods() }) {
                                Text(vm.L(L10n.Settings.backupModsButton))
                            }
                            InfoPopoverButton(text: vm.L(L10n.Settings.hintCompressMods))
                        }
                    }
                }
                
                // ── Appearance ──
                StandardSection(
                    title: vm.L(L10n.Settings.appearance),
                    footer: vm.L(L10n.Settings.footerAppearance)
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(vm.L(L10n.Settings.appTheme))
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $appColorScheme) {
                                Text(vm.L(L10n.Settings.themeSystem)).tag("System")
                                Text(vm.L(L10n.Settings.themeLight)).tag("Light")
                                Text(vm.L(L10n.Settings.themeDark)).tag("Dark")
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .fixedSize()
                        }
                        
                        Divider().padding(.leading, 0)
                        
                        HStack {
                            Text(vm.L(L10n.Settings.showDevLogs))
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: $showDeveloperLogs)
                                .toggleStyle(SwitchToggleStyle(tint: .blue))
                                .controlSize(.small)
                                .labelsHidden()
                            
                            InfoPopoverButton(text: vm.L(L10n.Settings.hintDevLogs))
                        }
                    }
                }
                
                // ── Mod Behavior ──
                StandardSection(
                    title: vm.L(L10n.Settings.modBehavior),
                    footer: vm.L(L10n.Settings.chainToggleHint)
                ) {
                    HStack {
                        Text(vm.L(L10n.Settings.chainToggle))
                            .font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { vm.chainToggleDependencies },
                            set: { vm.chainToggleDependencies = $0 }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .controlSize(.small)
                        .labelsHidden()
                        
                        InfoPopoverButton(text: vm.L(L10n.Settings.chainToggleHint))
                    }
                }

                // ── Management ──
                StandardSection(
                    title: vm.L(L10n.Settings.management),
                    footer: vm.L(L10n.Settings.footerManagement)
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(vm.L(L10n.Settings.savesFolder))
                                .font(.system(size: 13))
                            Spacer()
                            Button(action: { vm.openSavesFolder() }) {
                                Text(vm.L(L10n.Settings.openFolder))
                            }
                            InfoPopoverButton(text: vm.L(L10n.Settings.openFolder))
                        }
                        
                        Divider().padding(.leading, 0)
                        
                        HStack {
                            Text(vm.L(L10n.Settings.clearDisabledMods))
                                .font(.system(size: 13))
                            Spacer()
                            Button(action: { vm.cleanDisabledMods() }) {
                                Text(vm.L(L10n.Settings.deleteJunkMods))
                            }
                            .foregroundColor(.red)
                            
                            InfoPopoverButton(text: vm.L(L10n.Settings.clearDisabledMods), color: .red.opacity(0.8))
                        }
                    }
                }
            }
            .padding(40)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
