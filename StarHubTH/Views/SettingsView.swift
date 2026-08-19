import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: StarHubTHViewModel

    @AppStorage("launchProfile") private var launchProfile: String = "SMAPI"
    @AppStorage("closeAfterLaunch") private var closeAfterLaunch: Bool = false
    @AppStorage("showDeveloperLogs") private var showDeveloperLogs: Bool = false
    @AppStorage(UDKey.autoCheckNexusUpdates) private var autoCheckNexusUpdates: Bool = true

    // Nexus Mods API key entry (only used when no key is stored yet).
    @State private var nexusApiKeyInput: String = ""
    @State private var nexusKeySavedFlash: Bool = false
    @State private var showClearDisabledConfirm = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {

                // ── Nexus Mods ──
                StandardSection(
                    title: vm.L(L10n.Settings.nexusMods),
                    footer: vm.L(L10n.Settings.nexusApiKeyHint)
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(vm.L(L10n.Settings.nexusAutoCheck))
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: $autoCheckNexusUpdates)
                                .toggleStyle(SwitchToggleStyle(tint: .blue))
                                .controlSize(.small)
                                .labelsHidden()
                            InfoPopoverButton(text: vm.L(L10n.Settings.nexusAutoCheckHint))
                        }

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

                // ── Traduction assistée ──
                LocalAISettingsSection(vm: vm)

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
                
                // ── Developer ──
                // (App theme and language now live as toggles at the bottom of
                // the sidebar; this section keeps the developer-logs setting.)
                StandardSection(
                    title: vm.L(L10n.Settings.developer),
                    footer: vm.L(L10n.Settings.footerAppearance)
                ) {
                    VStack(alignment: .leading, spacing: 16) {
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
                            Button(action: { showClearDisabledConfirm = true }) {
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
        .alert(isPresented: $showClearDisabledConfirm) {
            // cleanDisabledMods fait un removeItem définitif (pas la corbeille) :
            // sans cette confirmation, un clic supprimait tous les mods désactivés
            // du profil sans retour possible.
            Alert(
                title: Text(vm.L(L10n.Settings.clearDisabledMods)),
                message: Text(vm.L(L10n.Settings.clearDisabledConfirm)),
                primaryButton: .destructive(Text(vm.L(L10n.Settings.deleteJunkMods))) {
                    vm.cleanDisabledMods()
                },
                secondaryButton: .cancel(Text(vm.L(L10n.Saves.cancel)))
            )
        }
    }
}

/// La section « Traduction assistée » des réglages (tâche 15 du plan P2b,
/// spec §6) : serveur IA local + glossaire du jeu.
///
/// Le sondage des briques connues (Ollama 11434, LM Studio 1234) tourne à
/// l'apparition, en parallèle, timeout 2 s : une répond → URL préremplie ;
/// les deux → deux lignes, au choix ; aucune → champ libre et la mention
/// d'installation. La saisie manuelle reste toujours possible — le champ
/// n'est jamais verrouillé sur ce que le sondage a vu.
private struct LocalAISettingsSection: View {
    @ObservedObject var vm: StarHubTHViewModel

    @AppStorage(UDKey.localAIBaseURL) private var baseURL: String = ""
    @AppStorage(UDKey.localAIModel) private var model: String = ""

    @State private var probes: [LocalLLMClient.ProbeResult] = []
    @State private var isProbing = true
    @State private var models: [String] = []
    @State private var testVerdictOK: Bool?
    @State private var isRebuildingGlossary = false
    @State private var glossaryCount: Int?
    @State private var glossaryDate: Date?

    var body: some View {
        VStack(spacing: 32) {
            StandardSection(
                title: vm.L(L10n.Settings.localAITitle),
                footer: vm.L(L10n.Settings.localAIPrivacy)
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    if isProbing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                        }
                    } else if probes.isEmpty {
                        Text(vm.L(L10n.Settings.localAINoneDetected))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        // Chaque brique détectée est cliquable : elle préremplit
                        // l'URL et ses modèles — deux briques, deux lignes, le
                        // choix appartient à l'utilisateur.
                        ForEach(probes, id: \.baseURL.absoluteString) { probe in
                            Button {
                                baseURL = probe.baseURL.absoluteString
                                models = probe.models
                                if model.isEmpty || !probe.models.contains(model) {
                                    model = probe.models.first ?? ""
                                }
                                testVerdictOK = nil
                            } label: {
                                Label(String(format: vm.L(L10n.Settings.localAIDetected),
                                             probe.baseURL.absoluteString,
                                             Int64(probe.models.count)),
                                      systemImage: "circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.L(L10n.Settings.localAIURL)).font(.system(size: 13))
                        TextField("http://localhost:11434", text: $baseURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.system(size: 12, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(vm.L(L10n.Settings.localAIModel)).font(.system(size: 13))
                            if !models.isEmpty {
                                // Les modèles vus sur ce serveur, en choix
                                // rapide — le champ reste la voie de saisie
                                // libre, jamais remplacé.
                                Menu(vm.L(L10n.Settings.localAIModel)) {
                                    ForEach(models, id: \.self) { name in
                                        Button(name) { model = name }
                                    }
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }
                        TextField("qwen2.5", text: $model)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.system(size: 12, design: .monospaced))
                    }

                    HStack(spacing: 8) {
                        Button {
                            testConnection()
                        } label: {
                            Text(vm.L(L10n.Settings.localAITest))
                        }
                        .disabled(baseURL.isEmpty)
                        if testVerdictOK == true {
                            Text(vm.L(L10n.Settings.localAIOK))
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                        } else if testVerdictOK == false {
                            Text(vm.L(L10n.Settings.localAINoneDetected))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            StandardSection(title: vm.L(L10n.Settings.glossaryTitle)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if let count = glossaryCount, let date = glossaryDate {
                            Text(String(format: vm.L(L10n.Settings.glossaryInfo),
                                        Int64(count),
                                        date.formatted(date: .abbreviated, time: .shortened)))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        } else {
                            Text(vm.L(L10n.Settings.localAINoneDetected))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            rebuildGlossary()
                        } label: {
                            if isRebuildingGlossary {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(vm.L(L10n.Settings.glossaryRebuild))
                            }
                        }
                        .disabled(isRebuildingGlossary)
                    }
                }
            }
        }
        .task {
            // Sondage parallèle des deux briques, timeout 2 s (spec §6).
            probes = await LocalLLMClient.probeBricks(
                session: LocalLLMEndpoint.makeSession(timeout: 2))
            isProbing = false
            if baseURL.isEmpty, let first = probes.first {
                baseURL = first.baseURL.absoluteString
                models = first.models
            }
            if model.isEmpty, let first = probes.first {
                model = first.models.first ?? ""
            }
            glossaryCount = vm.currentGlossary(language: "fr")?.entries.count
            glossaryDate = vm.glossaryBuiltDate(language: "fr")
        }
    }

    private func testConnection() {
        Task {
            guard let url = LocalLLMEndpoint.validate(baseURL) else {
                testVerdictOK = false
                return
            }
            do {
                models = try await LocalLLMClient.listModels(
                    baseURL: url, session: LocalLLMEndpoint.makeSession(timeout: 5))
                testVerdictOK = true
            } catch {
                testVerdictOK = false
            }
        }
    }

    private func rebuildGlossary() {
        Task {
            isRebuildingGlossary = true
            defer { isRebuildingGlossary = false }
            glossaryCount = await vm.rebuildGlossary(language: "fr")
            glossaryDate = vm.glossaryBuiltDate(language: "fr")
        }
    }
}
