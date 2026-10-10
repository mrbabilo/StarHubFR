import SwiftUI

/// Le guide de premier lancement : sheet modale en huit étapes.
/// Présentation pure — chaque étape appelle des actions existantes du
/// ViewModel ou embarque une section de Réglages existante. Rien de neuf
/// n'entre dans `StarHubTHViewModel` (règle F1-T2).
struct OnboardingView: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @ObservedObject private var smapiInstaller: SmapiInstaller
    @State private var step: OnboardingStep = .welcome
    @State private var apiKeyInput: String = ""
    @State private var modsFolderError: String?
    /// Un seul scan automatique par ouverture du guide : ré-visiter l'étape
    /// mods ne relance pas un scan complet (scanMods + saves + compte Steam).
    @State private var didAutoScanMods = false
    /// Demande la fermeture de la sheet — le `onDismiss` de `MainView` pose
    /// `onboardingCompleted`.
    let onFinish: () -> Void

    init(viewModel: StarHubTHViewModel, localization: LocalizationStore, onFinish: @escaping () -> Void) {
        self.viewModel = viewModel
        self.localization = localization
        self.smapiInstaller = viewModel.smapiInstaller
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(showsIndicators: false) {
                stepBody
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppDesign.Spacing.lg)
            }
            Divider()
            footer
        }
        // Largeur fixe : les libellés FR les plus longs (« Passer cette
        // étape », « Revoir le guide de premier lancement ») y tiennent en
        // une ligne — vérifié au pire cas.
        .frame(width: 560, height: 520)
        .background(AppDesign.Color.windowBg)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Text(localization.L(step.titleKey))
                .font(AppDesign.Font.viewTitle)
            Spacer()
            Text(String(format: localization.L(L10n.Onboarding.stepOf),
                        OnboardingStep.allCases.firstIndex(of: step)! + 1,
                        OnboardingStep.allCases.count))
                .font(AppDesign.Font.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppDesign.Spacing.lg)
        .padding(.vertical, AppDesign.Spacing.md)
    }

    private var footer: some View {
        HStack {
            // Bienvenue : sortie complète. Étapes 3-7 : sortie d'étape (spec —
            // l'étape dossier du jeu et la finale ne sont pas passables).
            if step == .welcome {
                Button(localization.L(L10n.Onboarding.skipAll), action: onFinish)
            } else if step != .gameDir, step != .done {
                Button(localization.L(L10n.Onboarding.skipStep)) {
                    advance()
                }
            }
            Spacer()
            if step == .welcome {
                Button(localization.L(L10n.Onboarding.start)) { advance() }
                    .buttonStyle(.borderedProminent)
            } else if step == .done {
                Button(localization.L(L10n.Onboarding.finish), action: onFinish)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(localization.L(L10n.Onboarding.next)) { advance() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, AppDesign.Spacing.lg)
        .padding(.vertical, AppDesign.Spacing.md)
    }

    private func advance() {
        if let next = step.next { step = next }
    }

    // MARK: - Étapes

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .welcome:     welcomeStep
        case .gameDir:     gameDirStep
        case .modsFolder:  modsStep
        case .smapi:       smapiStep
        case .apiKey:      apiKeyStep
        case .localAI:     aiStep
        case .extensions:  extensionsStep
        case .done:        doneStep
        }
    }

    private func intro(_ key: String) -> some View {
        Text(localization.L(key))
            .font(AppDesign.Font.body)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, AppDesign.Spacing.md)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            intro(L10n.Onboarding.welcomeBody)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
        }
    }

    private var gameDirStep: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            intro(L10n.Onboarding.gameDirBody)
            HStack {
                if viewModel.gameDir.isEmpty {
                    Text(localization.L(L10n.Home.notSet))
                        .font(AppDesign.Font.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(viewModel.gameDir)
                        .font(AppDesign.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(localization.L(L10n.Home.selectFolder)) { viewModel.selectGameDir() }
            }
        }
    }

    /// Le dossier mods est **dérivé** de gameDir — jamais configurable (SMAPI
    /// charge `<jeu>/Mods`). Créé si absent ; s'il contient des mods, le scan
    /// les catalogue automatiquement dès l'arrivée sur l'étape.
    private var modsStep: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            intro(L10n.Onboarding.modsBody)
            if viewModel.gameDir.isEmpty {
                Text(localization.L(L10n.Onboarding.modsNeedGameDir))
                    .font(AppDesign.Font.footnote)
                    .foregroundStyle(AppDesign.Color.warning)
            } else {
                let modsPath = (viewModel.gameDir as NSString).appendingPathComponent("Mods")
                Text(modsPath)
                    .font(AppDesign.Font.monoCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if FileManager.default.fileExists(atPath: modsPath) {
                    Button(localization.L(L10n.Onboarding.modsScan)) { viewModel.refresh() }
                    scanFeedback
                    Text(String(format: localization.L(L10n.Onboarding.modsCount),
                                viewModel.scanStore.mods.count))
                        .font(AppDesign.Font.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    // L'échec s'affiche SOUS le bouton : l'étape doit rester
                    // actée — un dossier en lecture seule se répare, et le
                    // guide n'a pas de retour en arrière (X130).
                    Button(localization.L(L10n.Onboarding.modsCreate)) {
                        do {
                            _ = try GameDirLocator.ensureModsFolder(gameDir: viewModel.gameDir)
                            modsFolderError = nil
                        } catch {
                            modsFolderError = localization.L(L10n.Onboarding.modsCreateFailed)
                        }
                    }
                    if let modsFolderError {
                        Text(modsFolderError)
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(AppDesign.Color.error)
                    }
                }
            }
        }
        .onAppear { autoScanModsIfNeeded() }
    }

    /// Mods déjà présents sur disque à l'arrivée sur l'étape : scan lancé
    /// sans geste, une seule fois. Le compte publié par `scanStore` met la
    /// ligne à jour.
    private func autoScanModsIfNeeded() {
        guard !didAutoScanMods, viewModel.gameDir.isEmpty == false else { return }
        let modsPath = (viewModel.gameDir as NSString).appendingPathComponent("Mods")
        guard FileManager.default.fileExists(atPath: modsPath) else { return }
        let entries: [String]
        do { entries = try FileManager.default.contentsOfDirectory(atPath: modsPath) }
        catch { return }
        guard entries.contains(where: { !$0.hasPrefix(".") }) else { return }
        didAutoScanMods = true
        viewModel.refresh()
    }

    private var smapiStep: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            intro(L10n.Onboarding.smapiBody)
            if let version = viewModel.smapiInstalledVersion {
                Label(version, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppDesign.Color.success)
            } else {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                    Button(localization.L(L10n.Home.installSmapi)) { viewModel.installSmapi() }
                        .buttonStyle(.borderedProminent)
                        .disabled(smapiInstaller.isInstalling)
                    if smapiInstaller.isInstalling {
                        ProgressView(value: smapiInstaller.progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                            .animation(Motion.animation(.easeInOut), value: smapiInstaller.progress)
                        Text(localization.L(smapiInstaller.statusMessage))
                            .font(AppDesign.Font.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Mêmes règles que les Réglages : trim avant enregistrement, aucune
    /// validation réseau — Nexus parlera à la première requête.
    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            intro(L10n.Onboarding.apiKeyBody)
            if viewModel.hasNexusApiKey {
                Label("••••••••••••", systemImage: "checkmark.circle.fill")
                    .font(AppDesign.Font.monoCaption)
                    .foregroundStyle(AppDesign.Color.success)
            } else {
                SecureField(localization.L(L10n.Settings.nexusKeyPlaceholder), text: $apiKeyInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(AppDesign.Font.monoCaption)
                HStack {
                    Button(localization.L(L10n.Settings.nexusGetKey)) {
                        NSWorkspace.shared.open(NexusRequestBuilder.apiKeyPageURL)
                    }
                    Spacer()
                    Button(localization.L(L10n.Settings.nexusSaveKey)) {
                        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        viewModel.setNexusApiKey(trimmed)
                        apiKeyInput = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var aiStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            intro(L10n.Onboarding.aiBody)
            // Étiquette d'argument imposée par la section ; la valeur, elle,
            // reste notre `viewModel` — le cliquet des conventions y veille.
            LocalAISettingsSection(vm: viewModel, localization: localization)
        }
    }

    private var extensionsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            intro(L10n.Onboarding.extensionsBody)
            AppExtensionsSettingsSection(viewModel: viewModel, localization: localization)
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            intro(L10n.Onboarding.doneBody)
            doneRow(L10n.Onboarding.doneGameDir,
                    done: !viewModel.gameDir.isEmpty,
                    detail: viewModel.gameDir.isEmpty ? nil : viewModel.gameDir)
            doneRow(L10n.Onboarding.doneSmapi,
                    done: viewModel.smapiInstalledVersion != nil,
                    detail: viewModel.smapiInstalledVersion)
            doneRow(L10n.Onboarding.doneApiKey, done: viewModel.hasNexusApiKey, detail: nil)
            doneRow(L10n.Onboarding.doneMods,
                    done: !viewModel.scanStore.mods.isEmpty,
                    detail: String(format: localization.L(L10n.Onboarding.modsCount),
                                   viewModel.scanStore.mods.count))
            Button(localization.L(L10n.Onboarding.runScan)) { viewModel.refresh() }
            scanFeedback
        }
    }

    /// Retour d'un scan en vol : barre + ligne courante publiée par
    /// `scanStore.scanProgress`. Sans lui, le bouton de scan d'une étape
    /// agit sans témoin — sur un parc déjà scanné au lancement, le compte ne
    /// change pas et le clic paraît mort (constat écran 2026-10-09).
    @ViewBuilder
    private var scanFeedback: some View {
        if let progress = viewModel.scanStore.scanProgress {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .progressViewStyle(.linear)
                    .tint(.blue)
                Text("\(progress.currentName) (\(progress.done)/\(progress.total))")
                    .font(AppDesign.Font.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func doneRow(_ key: String, done: Bool, detail: String?) -> some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? AppDesign.Color.success : Color.secondary)
            Text(localization.L(key))
            if let detail {
                Text(detail)
                    .font(AppDesign.Font.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
