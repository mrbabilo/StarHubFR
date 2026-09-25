import SwiftUI
import UniformTypeIdentifiers

/// Main view for mod installation via drag-and-drop of zip files.
struct ModInstallView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// C2-T4 — « Voir la fiche » mène au bon onglet (canal pending, patron
    /// B3-T4).
    @Binding var currentTab: SidebarDestination
    @State private var isDropTarget = false
    @State private var zipModInfo: ZipModInfo?
    @State private var isAnalyzing = false
    @State private var isInstalling = false
    @State private var errorMessage: String?
    /// B2-T4 : commande copiable, posée avec le message par `showFailure`.
    @State private var copyableInstallCommand: String?
    @State private var errorRecoveryHint: String?
    @State private var showError = false
    @State private var tempDir: URL?
    @State private var showFilePicker = false
    /// Accusé du dépôt dans un mod existant : un message, pas un bilan (spec
    /// §5.6).
    @State private var recoveryAckMessage: String?
    /// False after `onDisappear`: a late analysis then cleans its own temp dir.
    @State private var isViewActive = true
    /// Fermeture sur installation réussie ? Alors le **bilan** prend la file ;
    /// sinon elle meurt avec la feuille. `@State` local, pas
    /// `vm.pendingInstallReport` : un clic rapide sur « Archive suivante » le
    /// remet à nil avant cet `onDisappear`.
    @State private var closingAfterInstall = false

    /// Archive qui n'est pas un mod mais du contenu pour le dossier d'un autre
    /// (`DroppedContentRecognizer`). Temp dir vivant tant qu'elle est affichée.
    private struct DroppedProposal {
        /// Un fichier reconnu et sa place chez l'hôte.
        struct File {
            let source: URL
            let destination: URL
        }
        let hostDisplayName: String
        /// Hôte, pour le sauvegarder avant écrasement.
        let host: ModItem
        /// **Tous** les fichiers reconnus (dix sacs dans `Utility Bags`).
        let files: [File]
        let hostIsPaused: Bool

        /// Le dossier qui les recevra, commun à tous.
        var destinationFolder: URL { files[0].destination.deletingLastPathComponent() }
    }
    @State private var droppedProposal: DroppedProposal?
    @State private var showDroppedProposal = false
    /// Archive sans manifeste situable, ou dont l'hôte est à désigner (un
    /// dossier entier, contre un fichier nu pour `droppedProposal`).
    @State private var manifestlessPlan: ManifestlessArchive.Plan?
    @State private var manifestlessCandidates: [String] = []
    @State private var manifestlessEntries: [ManifestlessArchive.Entry] = []
    /// Traduction : au registre, retirable ; greffe : non (le message le dit).
    @State private var manifestlessKind: ManifestlessArchive.Kind = .addon
    /// Nom de l'archive, retenu à part (`zipModInfo` est remis à nil).
    @State private var analyzedArchiveName = ""
    /// Archive analysée : l'id du téléchargement ne vaut **que** pour elle
    /// (la feuille accepte aussi un glisser-déposer).
    @State private var analyzedURL: URL?
    // File du dépôt multiple dans le VM (`vm.pendingDropQueue`), survit
    // entre deux zips ; ménage à l'abandon dans `onDisappear`.

    /// Sélection en attente : smapi.io signale un mod cassé.
    @State private var pendingBrokenInstall: [InstallSelection]?
    @State private var showManifestlessPlan = false
    @State private var showManifestlessChoice = false

    /// Parent-controlled binding so the view can dismiss the sheet.
    @Binding var isPresented: Bool

    let preloadedZip: URL?

    private let installer = ModZipInstaller()

    init(vm: StarHubTHViewModel, localization: LocalizationStore, currentTab: Binding<SidebarDestination>,
         isPresented: Binding<Bool>, preloadedZip: URL? = nil) {
        self.localization = localization
        self.vm = vm
        self._currentTab = currentTab
        self._isPresented = isPresented
        self.preloadedZip = preloadedZip
    }

    var body: some View {
        VStack(spacing: 20) {
            if recoveryAckMessage != nil {
                recoveryAckView
            } else {
                // Header
                HStack {
                    Text(localization.L(L10n.ModInstall.title))
                        .font(AppDesign.Font.viewTitle)
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: AppDesign.Font.scaled(18)))
                            .foregroundColor(AppDesign.Color.dimmedSecondary(0.6))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .iconHelp(localization.L(L10n.Saves.cancel))
                }

                // Drop zone
                if zipModInfo == nil {
                    Button { // un bouton, et non un geste : atteignable au clavier (I-T6)
                        guard !isAnalyzing, !isInstalling else { return }
                        showFilePicker = true
                    } label: { dropZone }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                } else {
                    InstallPreview(
                        zipModInfo: zipModInfo!,
                        installer: installer,
                        vm: vm,
                        localization: localization,
                        tempDir: $tempDir,
                        isInstalling: $isInstalling,
                        onInstall: installSelected,
                        onCancel: cancelInstall
                    )
                }
            }
        }
        .padding(AppDesignCore.Spacing.xl)
        // Grande feuille : `InstallPreview` profite de chaque point.
        .frame(minWidth: 800, idealWidth: 960, minHeight: 560, idealHeight: 700)
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            // Reject drops during analysis/install: `analyzeZip` deletes the current
            // `tempDir` synchronously.
            guard !isAnalyzing, !isInstalling else { return false }
            handleDrop(providers)
            return true
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.zip, UTType(filenameExtension: "rar"), UTType(filenameExtension: "7z")].compactMap({ $0 }), allowsMultipleSelection: false) { result in
            switch result {
            case .success(let files):
                if let url = files.first {
                    // Drop any pending Nexus source so it can't misapply.
                    self.vm.pendingNexusSource = nil
                    self.analyzeZip(url)
                }
            case .failure:
                break
            }
        }
        .alert(localization.L(L10n.ModInstall.validationError), isPresented: $showError) {
            // B2-T4 : bouton seulement si l'erreur porte une commande ; copie et
            // referme.
            if let command = copyableInstallCommand {
                Button(localization.L(L10n.ModInstall.copyCommand)) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
            }
            Button(localization.L(L10n.Main.ok)) {
                // L'archive refusée ne doit pas arrêter le reste du dépôt.
                analyzeNextQueuedArchive()
            }
        } message: {
            if let error = errorMessage {
                if let hint = errorRecoveryHint {
                    Text("\(error)\n\n\(hint)")
                } else {
                    Text(error)
                }
            }
        }
        .alert(localization.L(L10n.Mods.compatInstallTitle),
               isPresented: Binding(get: { pendingBrokenInstall != nil },
                                    set: { if !$0 { pendingBrokenInstall = nil } })) {
            if let selections = pendingBrokenInstall {
                let broken = brokenAmong(selections)
                ForEach(broken.first?.verdict.links.prefix(2) ?? [], id: \.url) { link in
                    Button(link.label) {
                        if let url = URL(string: link.url) { NSWorkspace.shared.open(url) }
                        pendingBrokenInstall = nil
                    }
                }
                Button(localization.L(L10n.Mods.compatInstallConfirm)) {
                    // **Directement `performInstall`** : repasser par la porte reposerait la
                    // question en boucle selon l'ordre de SwiftUI.
                    pendingBrokenInstall = nil
                    performInstall(selections: selections)
                }
                Button(localization.L(L10n.ModInstall.cancel), role: .cancel) { pendingBrokenInstall = nil }
            }
        } message: {
            if let selections = pendingBrokenInstall {
                Text(brokenAmong(selections).map { entry in
                    var line = entry.name + " — " + CompatibilityWarning.label(entry.verdict.status, localization)
                    if let brokeIn = entry.verdict.brokeIn {
                        line += "\n" + String(format: localization.L(L10n.Mods.compatBrokeIn), brokeIn)
                    }
                    if !entry.verdict.summary.isEmpty { line += "\n" + entry.verdict.summary }
                    return line
                }.joined(separator: "\n\n"))
            }
        }
        .alert(localization.L(L10n.ModInstall.depositTitle), isPresented: $showManifestlessPlan) {
            if let plan = manifestlessPlan {
                Button(String(format: localization.L(L10n.ModInstall.depositConfirm), plan.hostFolderName)) {
                    deposit(plan)
                }
                Button(localization.L(L10n.ModInstall.cancel), role: .cancel) {
                    manifestlessPlan = nil
                    // Dépôt annulé : le reste du dépôt multiple continue.
                    analyzeNextQueuedArchive()
                }
            }
        } message: {
            if let plan = manifestlessPlan {
                // Une greffe n'est pas défaisable depuis l'app.
                Text(String(format: localization.L(plan.kind == .translation
                                         ? L10n.ModInstall.depositMessage
                                         : L10n.ModInstall.depositMessageAddon),
                            plan.entries.count, plan.hostFolderName))
            }
        }
        .confirmationDialog(localization.L(L10n.ModInstall.depositChooseTitle),
                            isPresented: $showManifestlessChoice, titleVisibility: .visible) {
            // Un bouton par candidat : l'utilisateur tranche, jamais l'heuristique.
            ForEach(manifestlessCandidates, id: \.self) { candidate in
                Button(candidate) {
                    deposit(ManifestlessArchive.Plan(hostFolderName: candidate,
                                                     kind: manifestlessKind,
                                                     entries: manifestlessEntries))
                }
            }
            Button(localization.L(L10n.ModInstall.cancel), role: .cancel) {
                manifestlessCandidates = []
                // Choix annulé : le reste du dépôt multiple continue.
                analyzeNextQueuedArchive()
            }
        } message: {
            Text(String(format: localization.L(L10n.ModInstall.depositChoose), manifestlessEntries.count))
        }
        .alert(localization.L(L10n.ModInstall.droppedTitle), isPresented: $showDroppedProposal) {
            if let proposal = droppedProposal {
                Button(String(format: localization.L(L10n.ModInstall.droppedInstall),
                              proposal.hostDisplayName)) {
                    installDroppedContent(proposal)
                }
            }
            Button(localization.L(L10n.ModInstall.cancel), role: .cancel) {
                if let tempDir = tempDir {
                    installer.cleanupTempDir(at: tempDir)
                    self.tempDir = nil
                }
                // Proposition refusée : le reste du dépôt continue.
                analyzeNextQueuedArchive()
            }
        } message: {
            Text(droppedProposalMessage)
        }
        .onDisappear {
            isViewActive = false
            // Le lot meurt avec la feuille, **sauf** après une installation réussie.
            if !closingAfterInstall {
                vm.abandonDropQueue()
            }
            // Swipe/Esc dismissal: clean the temp dir, unless an install owns it.
            if !isInstalling, let tempDir = tempDir {
                installer.cleanupTempDir(at: tempDir)
                self.tempDir = nil
            }
        }
        .onAppear {
            if let zip = preloadedZip { analyzeZip(zip) }
        }
    }

    /// Accusé du dépôt dans un mod existant (spec §5.6) ; le bilan
    /// d'installation vit dans `InstallReportWindow`.
    private var recoveryAckView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: AppDesign.Font.scaled(56)))
                .foregroundColor(.green)
            Text(recoveryAckMessage ?? "")
                .font(AppDesign.Font.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(localization.L(L10n.Main.ok)) {
                recoveryAckMessage = nil
                if vm.nextQueuedDropURL != nil {
                    // Le dépôt n'est pas épuisé : l'archive suivante attend.
                    analyzeNextQueuedArchive()
                } else {
                    isPresented = false
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(AppDesignCore.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropZone: some View {
        VStack(spacing: AppDesignCore.Spacing.lg) {
            if isAnalyzing {
                ProgressView()
                    .controlSize(.large)
                Text(localization.L(L10n.ModInstall.analyzingZip))
                    .font(AppDesign.Font.rowTitle)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: isDropTarget ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .font(.system(size: AppDesign.Font.scaled(48)))
                    .foregroundColor(isDropTarget ? .accentColor : AppDesign.Color.dimmedSecondary(0.6))

                VStack(spacing: AppDesignCore.Spacing.sm) {
                    Text(localization.L(L10n.ModInstall.dropZoneText))
                        .font(AppDesign.Font.headline.weight(.medium))
                        .foregroundColor(.primary)

                    Text(localization.L(L10n.ModInstall.dropHint))
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.accentColor.opacity(0.8))
                }
            }
        }
        .frame(maxWidth: .infinity)
        // Premier écran : place pour le geste.
        .frame(height: isDropTarget ? 300 : 260)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDropTarget ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isDropTarget ? Color.accentColor : Color.secondary.opacity(0.2),
                            lineWidth: isDropTarget ? 2 : 1
                        )
                )
        )
        .animation(Motion.animation(.easeInOut(duration: 0.2)), value: isDropTarget)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        loadDroppedFileURLs(from: providers) { urls in
            DispatchQueue.main.async {
                // A dropped zip isn't the Nexus download: clear the pending source.
                self.vm.pendingNexusSource = nil

                // Un seul chemin d'échec.
                guard !urls.isEmpty else {
                    self.showFailure(self.localization.L(L10n.ModInstall.invalidZipStructure))
                    self.errorRecoveryHint = ValidationStatus.invalidStructure.recoveryHintKey
                        .map { self.localization.L($0) }
                    self.showError = true
                    return
                }

                // Signature plutôt qu'extension ; fichier étranger écarté.
                let (archives, _) = ModZipInstaller.partitionDroppedFiles(urls)
                guard let first = archives.first else {
                    if let url = urls.first {
                        self.showFailure(String(format: self.localization.L(L10n.ModInstall.unsupportedFormat),
                                                url.pathExtension))
                        self.errorRecoveryHint = ValidationStatus
                            .unsupportedFormat(url.pathExtension).recoveryHintKey
                            .map { self.localization.L($0) }
                        self.showError = true
                    }
                    return
                }

                if self.isSheetShowingAnArchive {
                    // Fiche ouverte : les nouvelles archives attendent.
                    self.vm.dropQueuePush(archives)
                } else {
                    // La première part tout de suite ; les suivantes en file.
                    self.vm.dropQueuePush(Array(archives.dropFirst()))
                    self.analyzeZip(first)
                }
            }
        }
    }

    /// URL de chaque provider, dans l'ordre : chaque archive a sa fiche.
    private func loadDroppedFileURLs(from providers: [NSItemProvider],
                                     accumulated: [URL] = [],
                                     completion: @escaping @MainActor @Sendable ([URL]) -> Void) {
        guard let provider = providers.first else { completion(accumulated); return }
        // `NSItemProvider` non `Sendable` : la file se transporte explicitement
        // (P5-L6), consommée une à une sur l'acteur.
        nonisolated(unsafe) let rest = Array(providers.dropFirst())
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var urls = accumulated
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                urls.append(url)
            }
            let carried = urls
            Task { @MainActor in
                self.loadDroppedFileURLs(from: rest,
                                         accumulated: carried,
                                         completion: completion)
            }
        }
    }

    /// Feuille occupée : fiche, succès ou proposition de dépôt.
    private var isSheetShowingAnArchive: Bool {
        zipModInfo != nil || recoveryAckMessage != nil || droppedProposal != nil
            || manifestlessPlan != nil || !manifestlessCandidates.isEmpty
    }

    /// Ouvre la fiche de l'archive suivante, depuis chaque retour à la zone de
    /// dépôt. Une feuille fermée par l'utilisateur n'y passe pas (arrêt du lot).
    private func analyzeNextQueuedArchive() {
        // Qui présente dépile (invariant partagé avec `queueNextDropArchive`).
        guard let next = vm.dropQueueAdvance() else { return }
        analyzeZip(next)
    }

    private func analyzeZip(_ url: URL) {
        isAnalyzing = true
        zipModInfo = nil
        analyzedArchiveName = ModZipInstaller.strippingArchiveExtension(
            from: url.lastPathComponent)
        analyzedURL = url

        // Discard any previous temp dir before re-analyzing.
        if let oldTemp = tempDir {
            installer.cleanupTempDir(at: oldTemp)
            self.tempDir = nil
        }

        // Captured before dispatch: a concurrent refresh can't swap them.
        let gameDir = vm.gameDir
        let existingMods = vm.scanStore.mods

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Temp dir captured locally, assigned to @State in the main block below.
                var capturedTempDir: URL?
                let info = try self.installer.analyzeZip(
                    at: url,
                    gameDir: gameDir,
                    existingMods: existingMods
                ) { newTempDir in
                    capturedTempDir = newTempDir
                }

                let finalTempDir = capturedTempDir
                // Notes d'une extraction réussie (repli d'outil) : archive pas ordinaire.
                let extractionNotes = self.installer.lastExtractionNotes
                DispatchQueue.main.async {
                    for note in extractionNotes {
                        self.vm.log("Installation: \(note)", level: .warning)
                    }
                    guard self.isViewActive else {
                        // Dismissed meanwhile: clean up here.
                        if let finalTempDir = finalTempDir {
                            self.installer.cleanupTempDir(at: finalTempDir)
                        }
                        return
                    }
                    self.tempDir = finalTempDir
                    self.isAnalyzing = false
                    self.zipModInfo = info

                    if !info.isValid {
                        // Avant de refuser : peut-être du contenu pour un autre mod, décidé sur
                        // le dossier extrait.
                        if case .invalidStructure = info.validationStatus,
                           let outcome = self.recognizeDroppedContent() {
                            switch outcome {
                            case .proposal(let proposal):
                                self.droppedProposal = proposal
                                self.showDroppedProposal = true
                                self.zipModInfo = nil
                                return
                            case .hostMissing(let hostName):
                                self.showFailure(String(
                                    format: self.localization.L(L10n.ModInstall.droppedHostMissing), hostName))
                                self.errorRecoveryHint = nil
                                self.showError = true
                                self.zipModInfo = nil
                                if let tempDir = self.tempDir {
                                    self.installer.cleanupTempDir(at: tempDir)
                                    self.tempDir = nil
                                }
                                return
                            }
                        }

                        // Dossier entier (traduction, greffes) : `ManifestlessArchive` ; les
                        // deux se complètent.
                        if case .invalidStructure = info.validationStatus,
                           self.considerManifestlessArchive() {
                            self.zipModInfo = nil
                            return
                        }

                        switch info.validationStatus {
                        case .invalidStructure:
                            // Dire ce que l'archive contenait.
                            var msg = self.localization.L(L10n.ModInstall.invalidZipStructure)
                            if !info.extractedTopLevel.isEmpty {
                                msg += "\n\n" + String(format: self.localization.L(L10n.ModInstall.archiveContains),
                                                       info.extractedTopLevel.joined(separator: ", "))
                            }
                            self.showFailure(msg)
                        case .oversized:
                            self.showFailure(self.localization.L(L10n.ModInstall.zipOversized))
                        case .tooManyMods:
                            self.showFailure(self.localization.L(L10n.ModInstall.tooManyMods))
                        case .corrupted:
                            self.showFailure(self.localization.L(L10n.ModInstall.zipCorrupted))
                        case .unsupportedFormat(let ext):
                            self.showFailure(String(format: self.localization.L(L10n.ModInstall.unsupportedFormat), ext))
                        case .valid:
                            break
                        }
                        // Conseil tiré du statut (règle en Core).
                        self.errorRecoveryHint = info.validationStatus.recoveryHintKey.map { self.localization.L($0) }
                        self.showError = true
                        self.zipModInfo = nil
                        // Invalid → drop the temp dir.
                        if let tempDir = self.tempDir {
                            self.installer.cleanupTempDir(at: tempDir)
                            self.tempDir = nil
                        }
                        return
                    }

                    if info.detectedMods.isEmpty {
                        self.showFailure(self.localization.L(L10n.ModInstall.noModsDetected))
                        self.showError = true
                        self.zipModInfo = nil
                        if let tempDir = self.tempDir {
                            self.installer.cleanupTempDir(at: tempDir)
                            self.tempDir = nil
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isAnalyzing = false
                    self.showFailure(self.vm.installErrorMessage(error),
                                     copyableCommand: (error as? InstallError)?.copyableCommand)
                    self.showError = true
                    if let tempDir = self.tempDir {
                        self.installer.cleanupTempDir(at: tempDir)
                        self.tempDir = nil
                    }
                }
            }
        }
    }

    /// Montre le **chemin exact** : l'utilisateur vérifie où l'on écrit.
    private var droppedProposalMessage: String {
        guard let proposal = droppedProposal else { return "" }
        var text: String
        if proposal.files.count == 1 {
            text = String(format: localization.L(L10n.ModInstall.droppedQuestion),
                          proposal.hostDisplayName, proposal.files[0].destination.path)
        } else {
            // Un lot : le dossier, pas dix chemins.
            text = String(format: localization.L(L10n.ModInstall.droppedQuestionMany),
                          proposal.files.count, proposal.hostDisplayName,
                          proposal.destinationFolder.path)
        }
        if proposal.hostIsPaused {
            text += "\n\n" + String(format: localization.L(L10n.ModInstall.droppedHostPaused),
                                    proposal.hostDisplayName)
        }
        return text
    }

    /// Ce que la reconnaissance a conclu sur le dossier extrait.
    private enum DroppedOutcome {
        case proposal(DroppedProposal)
        case hostMissing(String)
    }

    /// Archive sans manifeste visant un mod installé ?
    /// - Returns: `true` si une suite est proposée (plan ou hôte à désigner).
    private func considerManifestlessArchive() -> Bool {
        guard let tempDir else { return false }
        let paths = ManifestlessArchive.paths(under: tempDir)
        let installed = vm.scanStore.mods.map(\.folderName)
        switch ManifestlessArchive.classify(paths: paths, installedFolderNames: installed,
                                            rootFileOwners: vm.rootFileOwners()) {
        case .plan(let plan):
            manifestlessPlan = plan
            showManifestlessPlan = true
            return true
        case .needsHost(let candidates, let kind, let entries):
            // Archive d'un lien Nexus : les mods de la fiche passent devant le nom
            // (souvent muet, C5-T1).
            let downloaded = analyzedURL == preloadedZip ? vm.pendingNexusSource?.modId : nil
            let linked = downloaded.map { FrenchTranslationSweep.hosts(
                ofTranslation: $0, in: vm.translationSweep.entries,
                detailHits: vm.translationHub.hits, installed: installed) } ?? []
            let ranked = linked + candidates.filter { !linked.contains($0) }
            // Sans candidat : refus ordinaire.
            guard !ranked.isEmpty else { return false }
            manifestlessCandidates = Array(ranked.prefix(4))
            manifestlessEntries = entries
            manifestlessKind = kind
            showManifestlessChoice = true
            return true
        case .unrecognised:
            return false
        }
    }

    /// B2-T4 — message et commande posés ensemble : sinon une commande
    /// traînerait sur une erreur qui n'est pas la sienne.
    private func showFailure(_ message: String, copyableCommand: String? = nil) {
        errorMessage = message
        copyableInstallCommand = copyableCommand
    }

    /// Dépose dans le mod désigné, via le VM (registre des traductions, d'où
    /// « Retirer » sur la fiche).
    private func deposit(_ plan: ManifestlessArchive.Plan) {
        guard let tempDir,
              let host = vm.scanStore.mods.first(where: { $0.folderName == plan.hostFolderName }) else {
            showFailure(localization.L(L10n.ModInstall.depositFailed))
            showError = true
            return
        }
        // Id de page retenu pour l'archive téléchargée seulement (sinon un lot
        // `nxm://` entrait sans suivi).
        let downloadedModId = analyzedURL == preloadedZip ? vm.pendingNexusSource?.modId : nil
        let result = vm.depositIntoMod(plan: plan, extractedRoot: tempDir, host: host,
                                       sourceName: analyzedArchiveName, nexus: nil,
                                       downloadedModId: downloadedModId)
        guard let outcome = result.outcome else {
            showFailure(result.message ?? localization.L(L10n.ModInstall.depositFailed))
            showError = true
            return
        }
        vm.log(String(format: localization.L(L10n.ModInstall.depositDone),
                      outcome.written.count, host.name))
        installer.cleanupTempDir(at: tempDir)
        self.tempDir = nil
        vm.refresh()
        // Message éventuel par la modale ; la feuille se ferme.
        if let message = result.message { vm.showModal(message: message) }
        isPresented = false
    }

    /// Fichier du dossier extrait destiné au dossier d'un autre mod ; `nil`
    /// sinon (refus ordinaire).
    private func recognizeDroppedContent() -> DroppedOutcome? {
        guard let tempDir = tempDir else { return nil }
        let found = DroppedContentRecognizer.recognizeAll(inExtractedDirectory: tempDir)
        guard let first = found.first else { return nil }

        var files: [DroppedProposal.File] = []
        var paused = false
        // Une proposition, un hôte : seule la première règle est traitée.
        for match in found where match.rule == first.rule {
            switch DroppedContentRecognizer.destination(for: match.rule,
                                                        fileName: match.fileURL.lastPathComponent,
                                                        installedMods: vm.scanStore.mods,
                                                        gameDir: vm.gameDir) {
            case .ready(let destination, let hostIsPaused):
                files.append(.init(source: match.fileURL, destination: destination))
                paused = hostIsPaused
            case .hostMissing(let name):
                return .hostMissing(name)
            case .unusableFileName:
                // Nom refusé : celui-là seul écarté.
                continue
            }
        }
        // Rien retenu : refus ordinaire.
        guard !files.isEmpty else { return nil }

        // `mod(withUniqueId:)` plutôt qu'un 23e dépliage à la main.
        guard let host = vm.scanStore.mods.mod(withUniqueId: first.rule.hostUniqueId)
        else { return .hostMissing(first.rule.hostDisplayName) }
        return .proposal(DroppedProposal(hostDisplayName: first.rule.hostDisplayName,
                                         host: host, files: files, hostIsPaused: paused))
    }

    /// Résultat d'un lot : fichiers posés ou erreur ; une seule valeur
    /// traverse les fils.
    private enum DroppedInstallOutcome {
        case done(installed: Int)
        case failed(error: Error, installed: Int)
    }

    /// Copie le fichier reconnu chez son hôte, sauvegardé d'abord si le
    /// fichier existait.
    private func installDroppedContent(_ proposal: DroppedProposal) {
        isInstalling = true
        let gameDir = vm.gameDir
        DispatchQueue.global(qos: .userInitiated).async {
            var installed = 0
            let outcome: DroppedInstallOutcome
            do {
                // Sauvegarder l'hôte avant d'écraser (sac retouché à la main), une fois
                // pour le lot. `try`, pas `try?` : un échec de sauvegarde arrête
                // l'écrasement.
                if proposal.files.contains(where: {
                    FileManager.default.fileExists(atPath: $0.destination.path)
                }) {
                    _ = try ModInstallBackupManager.shared.createBackup(
                        for: proposal.host, gameDir: gameDir, reason: .beforeInstall)
                }
                let hostRoot = URL(fileURLWithPath: gameDir)
                    .appendingPathComponent("Mods")
                    .appendingPathComponent(proposal.host.physicalFolderName, isDirectory: true)
                for file in proposal.files {
                    try DroppedContentRecognizer.install(from: file.source, to: file.destination,
                                                         hostRoot: hostRoot)
                    installed += 1
                }
                outcome = .done(installed: installed)
            } catch {
                // Lot interrompu : dire le compte de fichiers déjà posés.
                outcome = .failed(error: error, installed: installed)
            }
            DispatchQueue.main.async {
                self.isInstalling = false
                if let tempDir = self.tempDir {
                    self.installer.cleanupTempDir(at: tempDir)
                    self.tempDir = nil
                }
                switch outcome {
                case .done:
                    // Pas de `scanMods()` : aucun dossier de mod n'a bougé.
                    self.recoveryAckMessage = proposal.files.count == 1
                        ? String(format: self.localization.L(L10n.ModInstall.droppedDone),
                                 proposal.hostDisplayName)
                        : String(format: self.localization.L(L10n.ModInstall.droppedDoneMany),
                                 proposal.files.count, proposal.hostDisplayName)
                case .failed(let installError, let installed):
                    // Message assemblé **sur main** (L2).
                    var failure = self.vm.installErrorMessage(installError)
                    if installed > 0 {
                        failure += "\n\n" + String(format: self.localization.L(L10n.ModInstall.droppedDoneMany),
                                                   installed, proposal.hostDisplayName)
                    }
                    self.showFailure(failure,
                                     copyableCommand: (installError as? InstallError)?.copyableCommand)
                    self.errorRecoveryHint = nil
                    self.showError = true
                }
            }
        }
    }

    private func installSelected(selections: [InstallSelection]) {
        // **Le moment qui décide** : les 7 mods cassés du parc étaient déjà en
        // pause ; celui qu'on vient de télécharger, l'utilisateur l'ignore.
        guard brokenAmong(selections).isEmpty else {
            pendingBrokenInstall = selections
            return
        }
        performInstall(selections: selections)
    }

    /// Les mods de la sélection que smapi.io signale, avec leur verdict.
    private func brokenAmong(_ selections: [InstallSelection])
        -> [(name: String, verdict: ModCompatibility)] {
        guard let info = zipModInfo else { return [] }
        let selected = Set(selections.filter { $0.selected }.map { $0.modId })
        return info.detectedMods
            .filter { selected.contains($0.id) }
            .compactMap { detected in
                guard let verdict = vm.modCompatibility[detected.uniqueId], verdict.status.needsAttention, // l'archive peut ÊTRE le remplaçant
                      CompatibilityResolution.resolution(of: verdict, installedVersion: detected.manifest.version, installedNexusId: detected.manifest.nexusModId) == nil else { return nil }
                return (detected.name, verdict)
            }
    }

    private func performInstall(selections: [InstallSelection]) {
        guard let tempDir = tempDir,
              let info = zipModInfo else { return }

        isInstalling = true

        let selectedModIds = Set(selections.filter { $0.selected }.map { $0.modId })
        let modsBeingInstalled = info.detectedMods.filter { selectedModIds.contains($0.id) }
        // Captured before dispatching — see analyzeZip's identical comment.
        let gameDir = vm.gameDir
        let existingMods = vm.scanStore.mods

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Installer's `to:` is a no-op; legacy path kept for source compatibility.
                let modsDisabledPath = (gameDir as NSString).appendingPathComponent("Mods_disabled")
                // Chemins rendus par l'installateur, seul à savoir où il a écrit.
                let written = try self.installer.install(
                    from: tempDir,
                    to: modsDisabledPath,
                    selections: selections,
                    detectedMods: info.detectedMods,
                    gameDir: gameDir,
                    existingMods: existingMods
                )

                // Chemins comptés (ancre, réconciliation, enregistrement), règle
                // d'abstention testée (`accountingPaths`).
                let installedFolderPaths = ModZipInstaller.accountingPaths(
                    written: written,
                    selections: selections,
                    detectedMods: info.detectedMods)

                DispatchQueue.main.async {
                    self.isInstalling = false
                    self.installer.cleanupTempDir(at: tempDir)
                    self.tempDir = nil
                    // C2-T4 — delta persisté avant l'écran de succès.
                    self.vm.persistUpdateKeyDeltas(written)
                    self.zipModInfo = nil
                    // Couverture en cache périmée pour ces mods.
                    for mod in modsBeingInstalled {
                        self.vm.invalidateFrenchCoverage(for: mod.folderName)
                    }
                    self.vm.refresh()
                    self.vm.log(self.localization.L(L10n.ModInstall.installSuccess), level: .info)

                    // X63 — mod posé ailleurs (nom pris) : le dire.
                    for written in written where written.displacedFrom != nil {
                        self.vm.log(String(format: self.localization.L(L10n.ModInstall.folderTaken),
                                           written.displacedFrom ?? "",
                                           (written.path as NSString).lastPathComponent),
                                    level: .warning)
                    }

                    // Registry updated by scanMods() in refresh() (all install paths).

                    // Nexus-sourced install: reconcile the manifest Version.
                    if let source = self.vm.pendingNexusSource {
                        // X103-C — archive gardée AVANT le reste (seul instant où archive, mod
                        // et version sont connus). Pack : abstention.
                        let onlyMod = modsBeingInstalled.count == 1 ? modsBeingInstalled.first : nil
                        self.vm.keepNexusArchiveIfEnabled(
                            archive: self.preloadedZip,
                            uniqueId: onlyMod?.uniqueId,
                            version: onlyMod?.version,
                            modName: onlyMod?.name)
                        // Id retenu AVANT : `reconcileManifestVersion` consomme
                        // `pendingNexusSource`.
                        self.vm.recordNexusModId(source.modId,
                                                 installedFolderPaths: installedFolderPaths)
                        // Ancres posées au seul instant de certitude ; X9 : faits du fichier
                        // résolu joints.
                        let anchoredIds = self.vm.anchorInstalledMods(
                            installedFolderPaths: installedFolderPaths,
                            nexusFacts: source.facts)
                        // Reconcile FIRST (reads the entry), then drop the entry.
                        self.vm.reconcileManifestVersion(installedFolderPaths: installedFolderPaths)
                        self.vm.dismissInstalledUpdates(uniqueIds: anchoredIds)
                    }

                    // Auto-fetch Nexus metadata for installed mods with an id.
                    self.fetchNexusMetadata(for: modsBeingInstalled)

                    // Bilan posé, feuille refermée (`onDismiss` inchangé) — ICI, après la
                    // copie de l'archive par `keepNexusArchiveIfEnabled`.
                    self.vm.completeInstall(
                        installedNames: modsBeingInstalled.map { $0.name })
                    self.closingAfterInstall = true
                    self.isPresented = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    self.showFailure(self.vm.installErrorMessage(error),
                                     copyableCommand: (error as? InstallError)?.copyableCommand)
                    self.showError = true
                    // Always clean the temp dir, even on failure.
                    self.installer.cleanupTempDir(at: tempDir)
                    self.tempDir = nil
                    // Partial install: refresh so installed mods show up.
                    self.vm.refresh()
                }
            }
        }
    }

    /// Nexus metadata for installed mods with an id, **bornée** comme
    /// `check()` (`fetchSingleMod` tirait tout d'un coup : 20 requêtes pour un
    /// pack). Un seul client cohérent vu de Nexus.
    private func fetchNexusMetadata(for mods: [DetectedMod]) {
        let toFetch = mods.filter { !$0.nexusModId.isEmpty }
        guard !toFetch.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let limiter = DispatchSemaphore(value: Self.maxConcurrentMetadataFetches)
            for mod in toFetch {
                limiter.wait()
                // Complétion garantie sur main (place toujours rendue, 429 compris).
                // Amorce sur main (L2) ; réseau sur les fils d'`URLSession`.
                let modId = mod.nexusModId
                DispatchQueue.main.async {
                    self.vm.fetchMetadata(forNexusModId: modId) { _ in
                        limiter.signal()
                    }
                }
            }
        }
    }

    /// Maximum en vol, aligné sur `NexusUpdateChecker.check`.
    private static let maxConcurrentMetadataFetches = 6

    private func cancelInstall() {
        zipModInfo = nil
        if let tempDir = tempDir {
            installer.cleanupTempDir(at: tempDir)
            self.tempDir = nil
        }
        // Le dépôt multiple continue : l'archive suivante attend sa fiche.
        analyzeNextQueuedArchive()
    }
}