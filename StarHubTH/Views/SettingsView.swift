import SwiftUI

struct SettingsView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @ObservedObject var smapiInstaller: SmapiInstaller

    @AppStorage("launchProfile") private var launchProfile: String = "SMAPI"
    @AppStorage("closeAfterLaunch") private var closeAfterLaunch: Bool = false
    @AppStorage("showDeveloperLogs") private var showDeveloperLogs: Bool = false
    @AppStorage(UDKey.autoCheckNexusUpdates) private var autoCheckNexusUpdates: Bool = true
    /// X103-C — inactif par défaut : une fonction qui écrit sur le disque sans
    /// qu'on l'ait demandée fait croître l'empreinte en silence.
    @AppStorage(UDKey.keepNexusArchives) private var keepNexusArchives: Bool = false
    /// A1-T7 (suite) — remettre les données de mod après une mise à jour ;
    /// le vrai défaut (clé absente = true) vit dans `shouldRestore`.
    @AppStorage(UDKey.restoreModDataOnUpdate) private var restoreModData: Bool = true

    // Nexus Mods API key entry (only used when no key is stored yet).
    @State private var nexusApiKeyInput: String = ""
    @State private var nexusKeySavedFlash: Bool = false
    @State private var showClearDisabledConfirm = false
    /// Les dossiers relevés au clic, que la confirmation chiffre et que la
    /// suppression reprend tels quels — annoncer un compte puis en supprimer
    /// un autre serait pire que de ne rien annoncer.
    @State private var disabledModsToClear: [String] = []

    init(vm: StarHubTHViewModel, localization: LocalizationStore) {
        self.localization = localization
        self.vm = vm
        self.smapiInstaller = vm.smapiInstaller
    }

    var body: some View {
        // Un onglet par groupe (2026-09-25) : la page empilait 12 sections sur
        // ~3 écrans. L'ordre et le groupement restent des données
        // (`SettingsSectionOrder`, Core, sous test) ; le `switch` de
        // `sectionView` reste exhaustif — jamais de `default:`.
        let group = vm.navigationStore.settingsGroup
        return VStack(spacing: 0) {
            Picker(localization.L(L10n.Settings.settings),
                   selection: Bindable(vm.navigationStore).settingsGroup) {
                ForEach(SettingsSectionOrder.groups, id: \.self) { g in
                    Text(localization.L(titleKey(for: g))).tag(g)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, AppDesign.Spacing.md)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppDesignCore.Spacing.xxl) {
                        ForEach(SettingsSectionOrder.sections(in: group), id: \.self) { section in
                            sectionView(section).id(section)
                        }
                        if group == .about {
                            // État de mise à jour — dérivé de la dernière réponse
                            // réussie (releaseLastKnown), PAS du tag acquitté.
                            releaseStatusRow
                            Text(String(format: localization.L(L10n.Settings.appVersion),
                                        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"))
                                .font(AppDesign.Font.footnote)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(40)
                }
                .onAppear { showPendingSection(proxy) }
                .onChange(of: vm.navigationStore.pendingSettingsSection) { _, _ in showPendingSection(proxy) }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .alert(isPresented: $showClearDisabledConfirm) {
            // cleanDisabledMods met tout le lot dans la corbeille des mods
            // (restaurable depuis Entretien) : la confirmation chiffre ce qui
            // part avant le clic.
            Alert(
                title: Text(localization.L(L10n.Settings.clearDisabledMods)),
                message: Text(String(format: localization.L(L10n.Settings.clearDisabledConfirmCount),
                                     Int64(disabledModsToClear.count))),
                primaryButton: .destructive(Text(localization.L(L10n.Settings.deleteJunkMods))) {
                    vm.cleanDisabledMods(targets: disabledModsToClear)
                },
                secondaryButton: .cancel(Text(localization.L(L10n.Saves.cancel)))
            )
        }
    }

    // MARK: - Groupes

    /// L'état de mise à jour + le bouton de vérification manuelle. Le
    /// check manuel bypass le throttle ; l'échec, lui, ne se dit qu'ICI —
    /// au lancement, une app hors-ligne ne doit pas brair (spec §7.5).
    @ViewBuilder private var releaseStatusRow: some View {
        HStack(spacing: 8) {
            if vm.releaseCheckInFlight {
                Text(localization.L(L10n.Settings.appChecking))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
            } else if let known = vm.lastKnownRelease,
                      NexusUpdateChecker.compare(known.tagName, currentAppVersion) == .orderedDescending {
                Text(String(format: localization.L(L10n.Settings.appUpdateAvailableState), known.tagName))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.orange)
            } else {
                Text(localization.L(L10n.Settings.appUpToDate))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(localization.L(L10n.Settings.appCheckUpdates)) {
                vm.checkForAppRelease(bypassThrottle: true)
            }
            .disabled(vm.releaseCheckInFlight)
            .font(AppDesign.Font.footnote)
        }
        if let failure = vm.releaseCheckFailedMessage {
            Text(failure)
                .font(AppDesign.Font.footnote)
                .foregroundColor(.red)
        }
    }

    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Ouvre l'onglet d'une section demandée par un lien, puis y défile.
    private func showPendingSection(_ proxy: ScrollViewProxy) {
        guard let section = vm.navigationStore.pendingSettingsSection else { return }
        vm.navigationStore.pendingSettingsSection = nil
        vm.navigationStore.settingsGroup = SettingsSectionOrder.group(of: section)
        Task { @MainActor in
            await Task.yield()
            withMotion { proxy.scrollTo(section, anchor: .top) }
        }
    }

    private func titleKey(for group: SettingsGroup) -> String {
        switch group {
        case .game:    return L10n.Settings.groupGame
        case .content: return L10n.Settings.groupContent
        case .data:    return L10n.Settings.groupData
        case .about:   return L10n.Settings.groupAbout
        }
    }

    @ViewBuilder
    private func sectionView(_ section: SettingsSection) -> some View {
        switch section {
        case .gameFolder:     gameFolderSection
        case .smapi:          smapiSection
        case .launch:         launchSection
        case .coreExtensions: coreExtensionsSection
        case .nexus:          nexusSection
        case .translationAI:  translationAISection
        case .modBehavior:    modBehaviorSection
        case .management:     managementSection
        case .backup:         backupSection
        case .developer:      developerSection
        case .display:        TextScaleSettingsSection(localization: localization)
        case .appInfo:        appInfoSection
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var nexusSection: some View {
        // ── Nexus Mods ──
        StandardSection(
            title: localization.L(L10n.Settings.nexusMods),
            footer: localization.L(L10n.Settings.nexusApiKeyHint)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(localization.L(L10n.Settings.nexusAutoCheck))
                        .font(AppDesign.Font.body)
                    Spacer()
                    Toggle(localization.L(L10n.Settings.nexusAutoCheck), isOn: $autoCheckNexusUpdates)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .controlSize(.small)
                        .labelsHidden()
                    InfoPopoverButton(text: localization.L(L10n.Settings.nexusAutoCheckHint))
                }

                // X103-C. Il vit ici, avec ce qui touche à Nexus, plutôt que
                // dans « Données & stockage » : c'est en réglant Nexus qu'on
                // se demande ce que deviennent les fichiers téléchargés. Son
                // poids et sa purge, eux, sont à l'écran Entretien.
                HStack {
                    Text(localization.L(L10n.Settings.keepNexusArchives))
                        .font(AppDesign.Font.body)
                    Spacer()
                    Toggle(localization.L(L10n.Settings.keepNexusArchives), isOn: $keepNexusArchives)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .controlSize(.small)
                        .labelsHidden()
                    InfoPopoverButton(text: localization.L(L10n.Settings.keepNexusArchivesHint))
                }

                // A1-T7 (suite). Section installation, pas « Données » :
                // c'est au moment d'une mise à jour qu'on se demande ce que
                // deviennent les fichiers écrits en jouant. Le défaut est
                // actif (comportement livré) ; l'installer lit la clé via
                // `PreservedModData.shouldRestore`, jamais `bool` nu.
                HStack {
                    Text(localization.L(L10n.Settings.restoreModData))
                        .font(AppDesign.Font.body)
                    Spacer()
                    Toggle(localization.L(L10n.Settings.restoreModData), isOn: $restoreModData)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .controlSize(.small)
                        .labelsHidden()
                    InfoPopoverButton(text: localization.L(L10n.Settings.restoreModDataHint))
                }

                if vm.hasNexusApiKey {
                    // Key stored — offer removal and link to fetch another.
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localization.L(L10n.Settings.nexusApiKey))
                                .font(AppDesign.Font.body)
                            Text("••••••••••••")
                                .font(AppDesign.Font.monoCaption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: {
                            if let url = URL(string: "https://www.nexusmods.com/users/myaccount?tab=api") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Text(localization.L(L10n.Settings.nexusGetKey))
                        }
                        Button(role: .destructive, action: {
                            vm.clearNexusApiKey()
                        }) {
                            Text(localization.L(L10n.Settings.nexusClearKey))
                        }
                    }

                    Divider()

                    NexusQuotaRow(vm: vm, localization: localization)
                } else {
                    // No key yet — secure field + save action.
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField(localization.L(L10n.Settings.nexusKeyPlaceholder), text: $nexusApiKeyInput)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(AppDesign.Font.monoCaption)
                            .autocorrectionDisabled(true)
                            .textContentType(.password)

                        HStack {
                            Button(action: {
                                if let url = URL(string: "https://www.nexusmods.com/users/myaccount?tab=api") {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                Text(localization.L(L10n.Settings.nexusGetKey))
                            }

                            Spacer()

                            if nexusKeySavedFlash {
                                Text(localization.L(L10n.Settings.nexusKeySaved))
                                    .font(AppDesign.Font.footnote)
                                    .foregroundColor(.green)
                                    .transition(.opacity)
                            }

                            Button {
                                let trimmed = nexusApiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                vm.setNexusApiKey(trimmed)
                                nexusApiKeyInput = ""
                                withMotion { nexusKeySavedFlash = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withMotion { nexusKeySavedFlash = false }
                                }
                            } label: {
                                Text(localization.L(L10n.Settings.nexusSaveKey))
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(nexusApiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var translationAISection: some View {
        // ── Traduction assistée ──
        LocalAISettingsSection(vm: vm, localization: localization)
    }

    @ViewBuilder
    private var launchSection: some View {
        // ── Launch Options ──
        StandardSection(
            title: localization.L(L10n.Settings.launchOptions),
            footer: localization.L(L10n.Settings.footerLaunch)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(localization.L(L10n.Settings.defaultLaunchMode))
                        .font(AppDesign.Font.body)
                    Spacer()
                    Picker(localization.L(L10n.Settings.defaultLaunchMode), selection: $launchProfile) {
                        Text(localization.L(L10n.Settings.playSMAPI)).tag("SMAPI")
                        Text(localization.L(L10n.Settings.vanillaGame)).tag("Vanilla")
                    }
                    .pickerStyle(MenuPickerStyle()).labelsHidden()
                    .fixedSize()
                    
                    InfoPopoverButton(text: localization.L(L10n.Settings.hintNextLaunchMode))
                }
                
                Divider().padding(.leading, 0)
                
                HStack {
                    Text(localization.L(L10n.Settings.closeLauncher))
                        .font(AppDesign.Font.body)
                    Spacer()
                    Toggle(localization.L(L10n.Settings.closeLauncher), isOn: $closeAfterLaunch)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .controlSize(.small)
                        .labelsHidden()
                    
                    InfoPopoverButton(text: localization.L(L10n.Settings.hintSaveResources))
                }
            }
        }
    }

    @ViewBuilder
    private var backupSection: some View {
        // ── Backup ──
        StandardSection(
            title: localization.L(L10n.Settings.backup),
            footer: localization.L(L10n.Settings.footerBackup)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(localization.L(L10n.Settings.backupSaves))
                        .font(AppDesign.Font.body)
                    Spacer()
                    Button(action: { vm.backupAllSaves() }) {
                        Text(localization.L(L10n.Settings.backupSavesButton))
                    }
                    InfoPopoverButton(text: localization.L(L10n.Settings.hintCompressSaves))
                }
                
                Divider().padding(.leading, 0)
                
                HStack {
                    Text(localization.L(L10n.Settings.backupMods))
                        .font(AppDesign.Font.body)
                    Spacer()
                    Button(action: { vm.backupAllMods() }) {
                        Text(localization.L(L10n.Settings.backupModsButton))
                    }
                    InfoPopoverButton(text: localization.L(L10n.Settings.hintCompressMods))
                }
            }
        }
    }

    @ViewBuilder
    private var developerSection: some View {
        // ── Developer ──
        // (App theme and language now live as toggles at the bottom of
        // the sidebar; this section keeps the developer-logs setting.)
        StandardSection(
            title: localization.L(L10n.Settings.developer),
            footer: localization.L(L10n.Settings.footerAppearance)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(localization.L(L10n.Settings.showDevLogs))
                        .font(AppDesign.Font.body)
                    Spacer()
                    Toggle(localization.L(L10n.Settings.showDevLogs), isOn: $showDeveloperLogs)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .controlSize(.small)
                        .labelsHidden()
                    
                    InfoPopoverButton(text: localization.L(L10n.Settings.hintDevLogs))
                }
            }
        }
    }

    @ViewBuilder
    private var modBehaviorSection: some View {
        // ── Mod Behavior ──
        StandardSection(
            title: localization.L(L10n.Settings.modBehavior),
            footer: localization.L(L10n.Settings.chainToggleHint)
        ) {
            HStack {
                Text(localization.L(L10n.Settings.chainToggle))
                    .font(AppDesign.Font.body)
                Spacer()
                Toggle(localization.L(L10n.Settings.chainToggle), isOn: Binding(
                    get: { vm.chainToggleDependencies },
                    set: { vm.chainToggleDependencies = $0 }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .controlSize(.small)
                .labelsHidden()
                
                InfoPopoverButton(text: localization.L(L10n.Settings.chainToggleHint))
            }
        }
    }

    @ViewBuilder
    private var managementSection: some View {
        // ── Management ──
        StandardSection(
            title: localization.L(L10n.Settings.management),
            footer: localization.L(L10n.Settings.footerManagement)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(localization.L(L10n.Settings.savesFolder))
                        .font(AppDesign.Font.body)
                    Spacer()
                    Button(action: { vm.openSavesFolder() }) {
                        Text(localization.L(L10n.Settings.openFolder))
                    }
                    InfoPopoverButton(text: localization.L(L10n.Settings.openFolder))
                }
                
                Divider().padding(.leading, 0)
                
                HStack {
                    Text(localization.L(L10n.Settings.clearDisabledMods))
                        .font(AppDesign.Font.body)
                    Spacer()
                    Button(action: {
                        disabledModsToClear = vm.disabledModTargets()
                        // Rien à supprimer : le dire, plutôt qu'ouvrir une
                        // alerte destructive qui n'emporterait rien.
                        if disabledModsToClear.isEmpty {
                            vm.showModal(message: localization.L(L10n.VM.cleanModsNotFound))
                        } else {
                            showClearDisabledConfirm = true
                        }
                    }) {
                        Text(localization.L(L10n.Settings.deleteJunkMods))
                    }
                    .foregroundColor(.red)
                    
                    InfoPopoverButton(text: localization.L(L10n.Settings.clearDisabledMods), color: .red.opacity(0.8))
                }
            }
        }
    }

    @ViewBuilder
    private var appInfoSection: some View {
        // ── App ──
        StandardSection(title: localization.L(L10n.Home.appInfo)) {
            StandardRow(title: LocalizedStringKey(localization.L(L10n.Home.developer)), detail: "AppleBoiy (original) · mrbabilo (fork)", showDivider: false)
        }
    }

    @ViewBuilder
    private var gameFolderSection: some View {
        // Folder Settings
        StandardSection(title: localization.L(L10n.Home.gameFolder)) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localization.L(L10n.Home.gamePath))
                        .font(AppDesign.Font.body)
                    if vm.gameDir.isEmpty {
                        Text(localization.L(L10n.Home.notSet))
                            .font(AppDesign.Font.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(vm.gameDir)
                            .font(AppDesign.Font.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Button(localization.L(L10n.Home.selectFolder)) { vm.selectGameDir() }
            }
        }
    }

    @ViewBuilder
    private var smapiSection: some View {
        // SMAPI Settings
        StandardSection(title: localization.L(L10n.Home.smapiManager)) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.L(L10n.Home.smapiStatus))
                            .font(AppDesign.Font.body)
                        if let version = vm.smapiInstalledVersion {
                            Text(String(format: localization.L(L10n.Home.smapiInstalled), version))
                                .font(AppDesign.Font.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(localization.L(L10n.Home.smapiNotInstalled))
                                .font(AppDesign.Font.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if smapiInstaller.isInstalling {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    } else if vm.smapiInstalledVersion == nil {
                        Button(localization.L(L10n.Home.installSmapi)) { vm.installSmapi() }
                    } else {
                        Button(localization.L(L10n.Home.uninstall)) { vm.uninstallSmapi() }
                    }
                }

                if smapiInstaller.isInstalling {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: smapiInstaller.progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                            .animation(Motion.animation(.easeInOut), value: smapiInstaller.progress)
                        Text(localization.L(smapiInstaller.statusMessage))
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 12)
                }
            }
        }
    }

    @ViewBuilder
    private var coreExtensionsSection: some View {
        // ── CORE EXTENSIONS SECTION ──
        StandardSection(title: localization.L(L10n.Home.coreExtensions)) {
            VStack(spacing: 0) {
                let core = vm.coreExtensionsSnapshot
                CoreModRow(vm: vm, localization: localization, title: "Content Patcher", status: core.contentPatcher.status, mod: core.contentPatcher.mod)
                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)

                CoreModRow(vm: vm, localization: localization, title: "SpaceCore", status: core.spacecore.status, mod: core.spacecore.mod)
                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)

                CoreModRow(vm: vm, localization: localization, title: "Stardew Valley Expanded", status: core.sve.status, mod: core.sve.mod)
                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)

                CoreToolRow(
                    title: localization.L(L10n.Home.toolUnar),
                    status: core.unarTool.installed ? .enabledAndInstalled : .notInstalled,
                    tooltip: localization.L(L10n.Home.toolUnarTooltip),
                    installCommand: "brew install unar"
                )
                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1).padding(.leading, 12).padding(.vertical, 2)

                CoreToolRow(
                    title: localization.L(L10n.Home.toolSevenZip),
                    status: core.sevenZipTool.installed ? .enabledAndInstalled : .notInstalled,
                    tooltip: localization.L(L10n.Home.toolSevenZipTooltip),
                    installCommand: "brew install sevenzip"
                )
            }
            .padding(.vertical, -8)
        }
    }
}

/// Ce qu'il reste de quota Nexus, tel que l'API l'annonce à chaque réponse
/// (B2-T6). Aucune requête n'est faite pour l'obtenir : les six en-têtes
/// `x-rl-*` arrivent avec tout appel, l'app se contentait de les jeter.
///
/// ⚠️ L'app n'interroge plus l'API Nexus qu'à la demande (les mises à jour
/// passent par smapi.io) : sur une installation neuve, le quota n'a **jamais**
/// été mesuré, et c'est le cas normal, pas le cas limite. D'où l'état
/// « jamais mesuré » explicite, avec ce qui le fera apparaître.
private struct NexusQuotaRow: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localization.L(L10n.Settings.nexusQuota))
                .font(AppDesign.Font.body)

            if let quota = vm.nexusQuota {
                if quota.isStale() {
                    // Les chiffres d'hier mentent après la remise à zéro : ne
                    // rien affirmer plutôt qu'afficher un reste périmé.
                    Text(localization.L(L10n.Settings.nexusQuotaRenewed))
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary)
                } else {
                    measured(quota)
                }
            } else {
                Text(localization.L(L10n.Settings.nexusQuotaNever))
                    .font(AppDesign.Font.caption)
                    .foregroundColor(.secondary)
                Text(localization.L(L10n.Settings.nexusQuotaNeverHint))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { vm.refreshNexusQuota() }
        .onReceive(NotificationCenter.default.publisher(
            for: NexusUpdateChecker.quotaDidChange)) { _ in
            vm.refreshNexusQuota()
        }
    }

    /// Chaque fenêtre est jugée pour elle-même : l'horaire se périme en une
    /// heure, le compte journalier tient jusqu'à minuit. Les agréger ferait
    /// disparaître le chiffre du jour une heure après le dernier appel — soit,
    /// l'app n'interrogeant Nexus qu'à la demande, presque tout le temps.
    @ViewBuilder
    private func measured(_ quota: NexusQuota) -> some View {
        if let daily = quota.dailyIfCurrent() {
            HStack(spacing: 6) {
                Text(String(format: localization.L(L10n.Settings.nexusQuotaDaily), counts(daily)))
                    .font(AppDesign.Font.caption)
                    .foregroundColor(daily.remaining == 0 ? .orange : .secondary)
                if daily.remaining == 0 {
                    Text(localization.L(L10n.Settings.nexusQuotaExhausted))
                        .font(AppDesign.Font.footnote(.medium))
                        .foregroundColor(.orange)
                }
            }
            if let reset = daily.reset {
                Text(String(format: localization.L(L10n.Settings.nexusQuotaReset), Self.time(reset)))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
            }
        }
        if let hourly = quota.hourlyIfCurrent() {
            Text(String(format: localization.L(L10n.Settings.nexusQuotaHourly), counts(hourly)))
                .font(AppDesign.Font.footnote)
                .foregroundColor(.secondary)
        }
    }

    /// « 19 983 sur 20 000 », ou le seul reste quand l'API tait le plafond.
    private func counts(_ window: NexusQuota.Window) -> String {
        let remaining = Self.number(window.remaining)
        guard let limit = window.limit else { return remaining }
        return String(format: localization.L(L10n.Settings.nexusQuotaOf), remaining, Self.number(limit))
    }

    private static func number(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
