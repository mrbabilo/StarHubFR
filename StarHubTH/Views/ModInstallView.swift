import SwiftUI
import UniformTypeIdentifiers

/// Main view for mod installation via drag-and-drop of zip files.
struct ModInstallView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// C2-T4 — le bouton « Voir la fiche » de l'écran de succès conduit au
    /// bon onglet : même canal que `SystemAlertsView` (pending posé avant le
    /// changement d'onglet — patron B3-T4).
    @Binding var currentTab: SidebarDestination
    @State private var isDropTarget = false
    @State private var zipModInfo: ZipModInfo?
    @State private var isAnalyzing = false
    @State private var isInstalling = false
    @State private var errorMessage: String?
    /// B2-T4 : commande copiable attachée à l'erreur courante — posée avec
    /// le message par `showFailure`, jamais l'une sans l'autre.
    @State private var copyableInstallCommand: String?
    @State private var errorRecoveryHint: String?
    @State private var showError = false
    @State private var tempDir: URL?
    @State private var showFilePicker = false
    /// L'accusé du flux « fichiers déposés dans un mod existant » — un
    /// message, pas un bilan : ce flux garde son écran réduit DANS la
    /// feuille (spec §5.6).
    @State private var recoveryAckMessage: String?
    /// Set false in `onDisappear`. A background analysis started before
    /// dismissal can still complete afterward; its completion checks this
    /// flag so it cleans up the temp dir itself instead of writing into
    /// `@State` that `onDisappear` already ran past (which would leak it).
    @State private var isViewActive = true
    /// Cette feuille se ferme-t-elle parce qu'une installation a réussi ?
    /// Si oui, le lot continue : c'est le **bilan** qui devient responsable
    /// de la file (« Archive suivante », ou abandon à la fermeture de sa
    /// fenêtre). Sinon, la feuille meurt sur un abandon et emporte la file.
    ///
    /// Un `@State` local, et pas une lecture de `vm.pendingInstallReport` :
    /// le bilan s'ouvre pendant l'animation de fermeture de la feuille, si
    /// bien qu'un clic rapide sur « Archive suivante » remet le report à nil
    /// **avant** que cet `onDisappear` ne s'exécute — la file de la suite
    /// serait alors effacée sous les pieds du lot en cours. Porté par
    /// l'instance de vue, ce drapeau ne dépend d'aucun ordre.
    @State private var closingAfterInstall = false

    /// Une archive qui n'est pas un mod, mais du contenu reconnu comme
    /// destiné au dossier d'un autre mod — voir `DroppedContentRecognizer`.
    /// Le dossier temporaire reste vivant tant que cette proposition est à
    /// l'écran : c'est de là que le fichier sera copié.
    private struct DroppedProposal {
        /// Un fichier reconnu et sa place chez l'hôte.
        struct File {
            let source: URL
            let destination: URL
        }
        let hostDisplayName: String
        /// Le mod hôte lui-même, pour pouvoir le sauvegarder avant écrasement
        /// sans avoir à le retrouver depuis le chemin de destination.
        let host: ModItem
        /// **Tous** les fichiers reconnus, pas seulement le premier : les
        /// archives de sacs se distribuent par lot — dix dans `Utility Bags`,
        /// cinq dans `Sword and Sorcery Bags`.
        let files: [File]
        let hostIsPaused: Bool

        /// Le dossier qui les recevra, commun à tous.
        var destinationFolder: URL { files[0].destination.deletingLastPathComponent() }
    }
    @State private var droppedProposal: DroppedProposal?
    @State private var showDroppedProposal = false
    /// Une archive sans manifeste que `ManifestlessArchive` a su situer, ou
    /// dont il faut désigner l'hôte. Distinct de `droppedProposal`, qui ne
    /// traite qu'un fichier nu reconnu à ses clés : ici c'est un dossier entier.
    @State private var manifestlessPlan: ManifestlessArchive.Plan?
    @State private var manifestlessCandidates: [String] = []
    @State private var manifestlessEntries: [ManifestlessArchive.Entry] = []
    /// Ce que l'archive dépose. Une traduction s'inscrit au registre et se
    /// retire depuis la fiche du mod ; une greffe, non — et le message le dit.
    @State private var manifestlessKind: ManifestlessArchive.Kind = .addon
    /// Le nom de l'archive en cours d'analyse. Retenu à part : `zipModInfo` est
    /// remis à nil dès qu'une proposition de dépôt s'affiche, alors que c'est
    /// ce nom qui nommera la traduction sur la fiche du mod.
    @State private var analyzedArchiveName = ""
    /// L'archive effectivement analysée. Sert à ne créditer un dépôt de
    /// l'identifiant Nexus du téléchargement **que** s'il s'agit bien de
    /// l'archive téléchargée : la même feuille accepte aussi un glisser-déposer,
    /// et `vm.pendingNexusSource` vaudrait alors pour un autre fichier.
    @State private var analyzedURL: URL?
    // Les archives restant à traiter d'un dépôt multiple vivent dans le
    // ViewModel (`vm.pendingDropQueue`) : la fenêtre de bilan s'ouvre entre
    // deux zips, un état de feuille serait perdu à sa fermeture. Leur ménage
    // à l'abandon est explicite — voir `onDisappear` plus bas.

    /// La sélection dont l'installation attend une confirmation : smapi.io
    /// signale l'un de ses mods comme cassé. Voir `CompatibilityWarning`.
    @State private var pendingBrokenInstall: [InstallSelection]?
    @State private var showManifestlessPlan = false
    @State private var showManifestlessChoice = false

    /// Binding controlled by the parent so the sheet can be dismissed from
    /// inside this view (close button / Done button).
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
                            .font(.system(size: 18))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help(localization.L(L10n.Saves.cancel))
                }

                // Drop zone
                if zipModInfo == nil {
                    dropZone
                        .onTapGesture {
                            guard !isAnalyzing, !isInstalling else { return }
                            showFilePicker = true
                        }
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
        // Grande feuille : l'analyse d'un pack (liste des mods, dépendances,
        // avertissements de compatibilité) demande de la place — et
        // `InstallPreview` n'a aucun plafond de largeur propre, il profite
        // de chaque point gagné ici.
        .frame(minWidth: 800, idealWidth: 960, minHeight: 560, idealHeight: 700)
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            // Reject drops while an analysis or install is in flight — both
            // read from `tempDir` on a background queue, and `analyzeZip`
            // below deletes the *current* `tempDir` synchronously before
            // starting a new analysis, which would otherwise yank the
            // directory out from under the in-flight operation.
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
            // B2-T4 : le bouton n'existe que si l'erreur courante porte une
            // commande. Le clic la copie et referme l'alerte — le contenu est
            // au presse-papiers, prêt à coller dans Terminal.
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
                    // **Directement `performInstall`, jamais `installSelected`.**
                    // Repasser par la porte dépendrait de l'ordre dans lequel
                    // SwiftUI exécute l'action et vide le binding : s'il le vide
                    // d'abord, la question se reposerait — en boucle.
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
                // Une greffe ne promet pas d'être défaisable depuis l'app : le
                // registre ne retient que les traductions.
                Text(String(format: localization.L(plan.kind == .translation
                                         ? L10n.ModInstall.depositMessage
                                         : L10n.ModInstall.depositMessageAddon),
                            plan.entries.count, plan.hostFolderName))
            }
        }
        .confirmationDialog(localization.L(L10n.ModInstall.depositChooseTitle),
                            isPresented: $showManifestlessChoice, titleVisibility: .visible) {
            // Un bouton par candidat : c'est l'utilisateur qui tranche, jamais
            // l'heuristique — écrire dans le mauvais mod ne se rattrape pas.
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
            // Le lot de dépôt meurt avec la feuille **sauf** si elle se ferme
            // sur une installation réussie : le bilan prend alors la suite.
            if !closingAfterInstall {
                vm.abandonDropQueue()
            }
            // If the sheet is dismissed without the Cancel button (swipe /
            // Esc), don't leak the extracted temp directory. Skip cleanup
            // while an install is in flight — it owns the temp dir.
            if !isInstalling, let tempDir = tempDir {
                installer.cleanupTempDir(at: tempDir)
                self.tempDir = nil
            }
        }
        .onAppear {
            if let zip = preloadedZip { analyzeZip(zip) }
        }
    }

    /// L'accusé du flux « fichiers déposés dans un mod existant » — un
    /// message, pas un bilan : ce flux garde son écran réduit DANS la
    /// feuille (spec §5.6). Le bilan d'installation, lui, vit dans
    /// `InstallReportWindow`.
    private var recoveryAckView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
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
                    .font(.system(size: 48))
                    .foregroundColor(isDropTarget ? .accentColor : .secondary.opacity(0.6))

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
        // Plus haute : premier écran de la feuille, elle doit accueillir le
        // geste sans que le texte soit tassé sous le glyphe.
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
        .animation(.easeInOut(duration: 0.2), value: isDropTarget)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        loadDroppedFileURLs(from: providers) { urls in
            DispatchQueue.main.async {
                // A manually dropped zip is not the Nexus download that opened
                // this sheet — drop any pending source so it can't misapply.
                self.vm.pendingNexusSource = nil

                // Un seul chemin d'échec : le message change, le conseil
                // découle du statut, et il n'y a qu'un saut de plus vers le fil
                // principal.
                guard !urls.isEmpty else {
                    self.showFailure(self.localization.L(L10n.ModInstall.invalidZipStructure))
                    self.errorRecoveryHint = ValidationStatus.invalidStructure.recoveryHintKey
                        .map { self.localization.L($0) }
                    self.showError = true
                    return
                }

                // Le format se juge sur la signature, pas sur l'extension : un
                // dépôt sans extension exploitable mais à la signature reconnue
                // reste une archive installable. Un fichier étranger glissé
                // dans le lot est écarté, pas subi.
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
                    // Une fiche est déjà ouverte : ne pas la balayer sous le
                    // dépôt — les nouvelles archives attendent leur tour.
                    self.vm.dropQueuePush(archives)
                } else {
                    // La première part tout de suite ; les suivantes en file.
                    self.vm.dropQueuePush(Array(archives.dropFirst()))
                    self.analyzeZip(first)
                }
            }
        }
    }

    /// Charge l'URL de fichier portée par chaque provider du dépôt, dans
    /// l'ordre du dépôt. Un dépôt multiple n'est plus réduit à son premier
    /// élément : chaque archive déposée a droit à sa fiche.
    private func loadDroppedFileURLs(from providers: [NSItemProvider],
                                     accumulated: [URL] = [],
                                     completion: @escaping ([URL]) -> Void) {
        guard let provider = providers.first else { completion(accumulated); return }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var urls = accumulated
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                urls.append(url)
            }
            self.loadDroppedFileURLs(from: Array(providers.dropFirst()),
                                     accumulated: urls,
                                     completion: completion)
        }
    }

    /// Vrai quand la feuille montre déjà quelque chose à ne pas balayer :
    /// une fiche d'installation, un succès, ou une proposition de dépôt.
    private var isSheetShowingAnArchive: Bool {
        zipModInfo != nil || recoveryAckMessage != nil || droppedProposal != nil
            || manifestlessPlan != nil || !manifestlessCandidates.isEmpty
    }

    /// Referme le cycle de l'archive courante et ouvre la fiche de la
    /// suivante du dépôt, s'il en reste une en file. Appelé de chaque point
    /// qui ramène à la zone de dépôt : bouton Terminé, annulation, alertes
    /// refermées. Une feuille fermée par l'utilisateur n'y passe pas : la
    /// file meurt avec elle, c'est l'arrêt volontaire du lot.
    private func analyzeNextQueuedArchive() {
        // Dépile : qui présente une archive la retire de la file (invariant
        // partagé avec `queueNextDropArchive`).
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

        // Captured before dispatching so a concurrent `vm.refresh()` on the
        // main thread can't reassign `vm.mods`/`vm.gameDir` mid-flight out
        // from under this background read.
        let gameDir = vm.gameDir
        let existingMods = vm.mods

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Capture the temp dir locally instead of hopping to main
                // synchronously mid-analysis (avoids blocking the background
                // thread on the main run loop). It is assigned to @State in
                // the main.async block below, before any code path that
                // reads it.
                var capturedTempDir: URL?
                let info = try self.installer.analyzeZip(
                    at: url,
                    gameDir: gameDir,
                    existingMods: existingMods
                ) { newTempDir in
                    capturedTempDir = newTempDir
                }

                let finalTempDir = capturedTempDir
                // Ce que l'extraction a eu à dire alors même qu'elle a réussi :
                // un repli sur un autre outil, typiquement. Le succès seul ne
                // se raconte pas, et c'est pourtant le moment où l'on veut
                // savoir que l'archive n'était pas ordinaire.
                let extractionNotes = self.installer.lastExtractionNotes
                DispatchQueue.main.async {
                    for note in extractionNotes {
                        self.vm.log("Installation: \(note)", level: .warning)
                    }
                    guard self.isViewActive else {
                        // Dismissed while this analysis was running —
                        // `onDisappear` already ran with `tempDir == nil`,
                        // so clean up here instead of leaking the directory.
                        if let finalTempDir = finalTempDir {
                            self.installer.cleanupTempDir(at: finalTempDir)
                        }
                        return
                    }
                    self.tempDir = finalTempDir
                    self.isAnalyzing = false
                    self.zipModInfo = info

                    if !info.isValid {
                        // Avant de refuser : ce n'est peut-être pas un mod
                        // manqué, mais du contenu destiné au dossier d'un autre
                        // mod. Se décide sur le dossier extrait, donc avant tout
                        // nettoyage.
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

                        // Le reconnaisseur ci-dessus ne traite qu'un fichier
                        // nu identifié à ses clés. Une archive qui porte un
                        // dossier — une traduction, un pack de greffes — relève
                        // de `ManifestlessArchive`, qui la situe par sa
                        // structure. Les deux se complètent ; aucun ne double
                        // l'autre.
                        if case .invalidStructure = info.validationStatus,
                           self.considerManifestlessArchive() {
                            self.zipModInfo = nil
                            return
                        }

                        switch info.validationStatus {
                        case .invalidStructure:
                            // Dire ce que l'archive contenait : sans cela
                            // l'utilisateur sait seulement qu'il manque un
                            // manifeste, pas ce qu'il y avait à la place.
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
                        // Le conseil découle du statut, et cette règle vit dans
                        // Core avec ses tests — la vue ne fait que l'afficher.
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

    /// Le texte de la proposition. Montre le **chemin exact** : c'est la seule
    /// façon pour l'utilisateur de vérifier qu'on écrit là où il l'entend.
    private var droppedProposalMessage: String {
        guard let proposal = droppedProposal else { return "" }
        var text: String
        if proposal.files.count == 1 {
            text = String(format: localization.L(L10n.ModInstall.droppedQuestion),
                          proposal.hostDisplayName, proposal.files[0].destination.path)
        } else {
            // Un lot : c'est le dossier qui compte, pas dix chemins qui ne
            // tiendraient pas dans l'alerte.
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

    /// Tente de reconnaître, dans le dossier extrait, un fichier destiné au
    /// dossier d'un autre mod. `nil` si rien n'est reconnu — l'archive suit
    /// alors le refus ordinaire.
    /// Regarde si l'archive, faute de manifeste, vise un mod installé.
    ///
    /// - Returns: `true` quand une suite est proposée — plan à confirmer ou
    ///   hôte à désigner —, `false` pour laisser le refus ordinaire suivre son
    ///   cours.
    private func considerManifestlessArchive() -> Bool {
        guard let tempDir else { return false }
        let paths = ManifestlessArchive.paths(under: tempDir)
        let installed = vm.mods.map(\.folderName)
        switch ManifestlessArchive.classify(paths: paths, installedFolderNames: installed,
                                            rootFileOwners: vm.rootFileOwners()) {
        case .plan(let plan):
            manifestlessPlan = plan
            showManifestlessPlan = true
            return true
        case .needsHost(let candidates, let kind, let entries):
            // Sans candidat, on n'a rien à proposer : le refus ordinaire dit au
            // moins ce que l'archive contenait.
            guard !candidates.isEmpty else { return false }
            manifestlessCandidates = Array(candidates.prefix(4))
            manifestlessEntries = entries
            manifestlessKind = kind
            showManifestlessChoice = true
            return true
        case .unrecognised:
            return false
        }
    }

    /// Dépose les fichiers dans le mod désigné.
    ///
    /// B2-T4 — un seul point d'entrée pour l'erreur que montre l'alerte : le
    /// message et la commande copiable se posent ensemble. La feuille ne
    /// remet jamais `errorMessage` à zéro, donc une commande posée séparément
    /// traînerait jusqu'à une erreur qui n'est pas la sienne — l'alerte
    /// offrirait « Copier la commande » sur une erreur sans commande.
    private func showFailure(_ message: String, copyableCommand: String? = nil) {
        errorMessage = message
        copyableInstallCommand = copyableCommand
    }

    /// Passe par le ViewModel : c'est lui qui tient le registre des traductions,
    /// sans lequel le bouton « Retirer » de la fiche du mod n'existerait pas —
    /// et le message de confirmation promet précisément que l'opération reste
    /// défaisable.
    private func deposit(_ plan: ManifestlessArchive.Plan) {
        guard let tempDir,
              let host = vm.mods.first(where: { $0.folderName == plan.hostFolderName }) else {
            showFailure(localization.L(L10n.ModInstall.depositFailed))
            showError = true
            return
        }
        // L'identifiant de la page ne se retient que pour l'archive
        // téléchargée : la branche d'installation d'un mod le fait depuis
        // toujours (« la seule occasion où l'app le connaît »), celle du dépôt
        // le jetait — un lot de sacs venu d'un lien `nxm://` entrait au
        // registre sans identifiant, donc sans suivi de version.
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
        // Un dépôt réussi peut avoir quelque chose à dire — le registre non
        // écrit, par exemple. Ce n'est pas une erreur de validation : le dire
        // par la fenêtre modale de l'app, et fermer la feuille comme d'habitude.
        if let message = result.message { vm.showModal(message: message) }
        isPresented = false
    }

    private func recognizeDroppedContent() -> DroppedOutcome? {
        guard let tempDir = tempDir else { return nil }
        let found = DroppedContentRecognizer.recognizeAll(inExtractedDirectory: tempDir)
        guard let first = found.first else { return nil }

        var files: [DroppedProposal.File] = []
        var paused = false
        // Une seule proposition, donc un seul hôte : si l'archive mêlait des
        // fichiers relevant de deux règles, seule la première est traitée.
        for match in found where match.rule == first.rule {
            switch DroppedContentRecognizer.destination(for: match.rule,
                                                        fileName: match.fileURL.lastPathComponent,
                                                        installedMods: vm.mods,
                                                        gameDir: vm.gameDir) {
            case .ready(let destination, let hostIsPaused):
                files.append(.init(source: match.fileURL, destination: destination))
                paused = hostIsPaused
            case .hostMissing(let name):
                return .hostMissing(name)
            case .unusableFileName:
                // Nom de fichier refusé : celui-là seul est écarté. Refuser le
                // lot entier pour un nom douteux priverait l'utilisateur des
                // neuf autres sacs.
                continue
            }
        }
        // Rien de retenu : l'archive repart sur le refus ordinaire plutôt que
        // sur une destination approximative.
        guard !files.isEmpty else { return nil }

        // Le dépliage était réécrit ici à la main — la 23e copie de
        // `flattenedMods`, dont le commentaire raconte les 22 premières.
        guard let host = vm.mods.mod(withUniqueId: first.rule.hostUniqueId)
        else { return .hostMissing(first.rule.hostDisplayName) }
        return .proposal(DroppedProposal(hostDisplayName: first.rule.hostDisplayName,
                                         host: host, files: files, hostIsPaused: paused))
    }

    /// Copie le fichier reconnu chez son hôte, après avoir sauvegardé ce dernier
    /// si le fichier existait déjà.
    private func installDroppedContent(_ proposal: DroppedProposal) {
        isInstalling = true
        let gameDir = vm.gameDir
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            var failureCommand: String?
            var installed = 0
            do {
                // Un sac peut avoir été retouché à la main (prix, capacités) :
                // sauvegarder l'hôte avant d'écraser. Rien à préserver si le
                // fichier n'existait pas.
                //
                // Le `try` n'est pas un `try?` : « sauvegarder **puis**
                // écraser » n'a de sens que si l'échec de la sauvegarde arrête
                // l'écrasement. L'avaler écraserait un fichier retouché sans
                // filet et sans le dire.
                // Une seule sauvegarde pour le lot : elle porte le dossier du
                // mod entier, la refaire à chaque fichier n'ajouterait rien.
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
            } catch {
                // Un lot interrompu en cours de route a déjà posé des fichiers :
                // dire « échec » sans le compte laisserait croire que rien n'a
                // bougé, et l'utilisateur chercherait au mauvais endroit.
                failure = self.vm.installErrorMessage(error)
                failureCommand = (error as? InstallError)?.copyableCommand
                if installed > 0 {
                    failure! += "\n\n" + String(format: self.localization.L(L10n.ModInstall.droppedDoneMany),
                                                 installed, proposal.hostDisplayName)
                }
            }
            DispatchQueue.main.async {
                self.isInstalling = false
                if let tempDir = self.tempDir {
                    self.installer.cleanupTempDir(at: tempDir)
                    self.tempDir = nil
                }
                if let failure = failure {
                    self.showFailure(failure, copyableCommand: failureCommand)
                    self.errorRecoveryHint = nil
                    self.showError = true
                } else {
                    // Pas de `scanMods()` ici : le fichier a atterri *dans* un
                    // mod existant, aucun dossier de mod n'a bougé. Rescanner
                    // ne changerait rien à l'écran et laisserait croire le
                    // contraire.
                    self.recoveryAckMessage = proposal.files.count == 1
                        ? String(format: self.localization.L(L10n.ModInstall.droppedDone),
                                 proposal.hostDisplayName)
                        : String(format: self.localization.L(L10n.ModInstall.droppedDoneMany),
                                 proposal.files.count, proposal.hostDisplayName)
                }
            }
        }
    }

    private func installSelected(selections: [InstallSelection]) {
        // **Le moment qui décide.** Sept mods du parc sont signalés cassés, et
        // les sept étaient déjà en pause : l'utilisateur les avait trouvés
        // seul. Ce qu'il ne peut pas savoir, c'est qu'un mod qu'il vient de
        // télécharger l'est aussi. On le dit ici, avant d'écrire.
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
                guard let verdict = vm.modCompatibility[detected.uniqueId],
                      verdict.status.needsAttention else { return nil }
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
        let existingMods = vm.mods

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // The installer's `to:` param is now a no-op (mods land under
                // Mods/ directly), but we still pass the legacy path for
                // source compatibility.
                let modsDisabledPath = (gameDir as NSString).appendingPathComponent("Mods_disabled")
                // Les chemins viennent de l'installateur : lui seul sait où
                // il a écrit — un composant reste dans son pack, un mod
                // activé garde sa place, un `.rename` porte un horodatage
                // fabriqué au moment de l'écriture.
                let written = try self.installer.install(
                    from: tempDir,
                    to: modsDisabledPath,
                    selections: selections,
                    detectedMods: info.detectedMods,
                    gameDir: gameDir,
                    existingMods: existingMods
                )

                // Une installation **renommée** laisse l'original en place :
                // deux dossiers portent alors le même `UniqueID`, quand une
                // ancre de version est unique par identifiant. Affirmer la
                // version de la copie renommée décrirait mal celle qui reste
                // active — et si l'utilisateur supprimait la copie sans
                // l'activer, la mise à jour ne serait plus jamais annoncée.
                // On s'abstient donc pour elles, comme avant ; la différence
                // est qu'on le fait sciemment, et non faute de connaître le
                // chemin.
                let renamedIds = Set(selections
                    .filter { $0.conflictResolution == .rename }
                    .map(\.modId))
                // X63 — une installation **déplacée** est un renommage par
                // d'autres moyens, et la même abstention s'impose. Le
                // déclencheur n'est pas toujours un identifiant étranger :
                // une racine de pack ne porte pas de manifeste, et le mod qui
                // s'en écarte peut très bien partager son `UniqueID` avec un
                // composant vivant sous cette racine. Deux dossiers pour un
                // identifiant, exactement ce que l'abstention évite.
                let installedFolderPaths = written
                    .filter { !renamedIds.contains($0.modId) && $0.displacedFrom == nil }
                    .map(\.path)

                DispatchQueue.main.async {
                    self.isInstalling = false
                    self.installer.cleanupTempDir(at: tempDir)
                    self.tempDir = nil
                    // C2-T4 — le delta de clés se persiste avant l'écran de
                    // succès : la feuille et la fiche liront la même chose.
                    self.vm.persistUpdateKeyDeltas(written)
                    self.zipModInfo = nil
                    // Les fichiers de ces mods viennent de changer : leur
                    // couverture en cache ne vaut plus rien. Sans cela, un mod
                    // mis à jour garderait le pourcentage de sa version
                    // précédente indéfiniment.
                    for mod in modsBeingInstalled {
                        self.vm.invalidateFrenchCoverage(for: mod.folderName)
                    }
                    self.vm.refresh()
                    self.vm.log(self.localization.L(L10n.ModInstall.installSuccess), level: .info)

                    // X63 — un mod dont le nom de dossier était déjà pris par
                    // un autre mod a été posé ailleurs. Sans cette ligne, la
                    // liste montre deux mods de même nom logique et rien ne
                    // dit pourquoi l'un vit dans un dossier horodaté.
                    for written in written where written.displacedFrom != nil {
                        self.vm.log(String(format: self.localization.L(L10n.ModInstall.folderTaken),
                                           written.displacedFrom ?? "",
                                           (written.path as NSString).lastPathComponent),
                                    level: .warning)
                    }

                    // The install registry is updated by scanMods() during the
                    // refresh() above (syncInstalledModRegistry detects the new
                    // version and stamps it with Date()), so no explicit
                    // recording is needed here — it covers ALL install paths
                    // (Nexus, drag-and-drop, manual folder copy).

                    // A Nexus-sourced install (nxm:// deep link or in-app
                    // download) may have an author-forgotten manifest
                    // Version — reconcile it against the Nexus file's own
                    // version/date now that the mod is on disk.
                    if let source = self.vm.pendingNexusSource {
                        // X103-C — garder l'archive AVANT tout le reste, pour
                        // la même raison que l'identifiant juste dessous : on
                        // est ici au succès de l'installation, le seul instant
                        // où l'archive, son mod et sa version sont connus
                        // ensemble. Un seul mod installé, sinon abstention —
                        // un pack porte plusieurs UniqueID pour une archive.
                        let onlyMod = modsBeingInstalled.count == 1 ? modsBeingInstalled.first : nil
                        self.vm.keepNexusArchiveIfEnabled(
                            archive: self.preloadedZip,
                            uniqueId: onlyMod?.uniqueId,
                            version: onlyMod?.version,
                            modName: onlyMod?.name)
                        // Retenir l'identifiant AVANT tout le reste : c'est la
                        // seule occasion où l'app le connaît, et
                        // `reconcileManifestVersion` consomme
                        // `pendingNexusSource` en le remettant à nil.
                        self.vm.recordNexusModId(source.modId,
                                                 installedFolderPaths: installedFolderPaths)
                        // L'installation est le seul instant où l'app sait avec
                        // certitude ce qui est posé. `isReferenceFile: true` :
                        // le téléchargement intégré et les liens `nxm://` ne
                        // servent aujourd'hui que le fichier principal.
                        // X9 : les faits du fichier résolu (identifiant + date)
                        // partent avec — l'ancre saura dire, au prochain check,
                        // si la page publie plus récent que ce qu'on vient de
                        // poser, libellés ou pas.
                        let anchoredIds = self.vm.anchorInstalledMods(
                            installedFolderPaths: installedFolderPaths,
                            nexusFacts: source.facts)
                        // Reconcile FIRST — it reads this mod's update entry to
                        // learn the version the checker flags on — then drop the
                        // entry from the list so it no longer appears.
                        self.vm.reconcileManifestVersion(installedFolderPaths: installedFolderPaths)
                        self.vm.dismissInstalledUpdates(uniqueIds: anchoredIds)
                    }

                    // Auto-fetch Nexus metadata (image + description) for
                    // installed mods that have a Nexus mod id, so the mods
                    // list shows them immediately without a manual check.
                    self.fetchNexusMetadata(for: modsBeingInstalled)

                    // Le bilan quitte la feuille : le report est posé, la
                    // feuille se referme — le `onDismiss` de la MainView
                    // (archive, X103-C, file nxm) s'exécute à l'identique.
                    // ICI, et pas avant : l'archive a déjà été copiée par
                    // `keepNexusArchiveIfEnabled` pendant que le fichier
                    // téléchargé vivait encore.
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
                    // Always clean up the temp extract dir, even on failure —
                    // otherwise a failed multi-mod install leaks the extracted
                    // zip on disk until the view is dismissed.
                    self.installer.cleanupTempDir(at: tempDir)
                    self.tempDir = nil
                    // A partial multi-mod install can leave some mods
                    // actually installed on disk even though this call
                    // threw — refresh so they show up immediately instead
                    // of only appearing after a manual refresh, which also
                    // avoids a retry re-using now-stale `existingMods`.
                    self.vm.refresh()
                }
            }
        }
    }

    /// Fetches Nexus metadata for installed mods that declare a Nexus mod id
    /// in their manifest UpdateKeys.
    ///
    /// `fetchMetadata` part sans attendre : la boucle rendait donc la main
    /// aussitôt et lâchait toutes les requêtes d'un coup — un pack de 20 mods
    /// en envoyait 20 en même temps, juste après une installation. Le
    /// commentaire d'origine affirmait ici que `NexusUpdateChecker` bornait la
    /// concurrence : c'est vrai de `check()`, qui a sa propre sémaphore, pas de
    /// `fetchSingleMod`, qui tire directement.
    ///
    /// Même borne que `check()` : l'app doit se présenter à l'API Nexus comme un
    /// seul client cohérent, quel que soit le chemin qui appelle.
    private func fetchNexusMetadata(for mods: [DetectedMod]) {
        let toFetch = mods.filter { !$0.nexusModId.isEmpty }
        guard !toFetch.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let limiter = DispatchSemaphore(value: Self.maxConcurrentMetadataFetches)
            for mod in toFetch {
                limiter.wait()
                // La complétion de `fetchMetadata` est garantie sur le main par
                // `fetchSingleMod`, sur tous ses chemins de sortie : la place
                // est donc toujours rendue, même sur 429 ou clé absente.
                self.vm.fetchMetadata(forNexusModId: mod.nexusModId) { _ in
                    limiter.signal()
                }
            }
        }
    }

    /// Requêtes de métadonnées Nexus en vol au maximum. Aligné sur le
    /// `maxConcurrent` de `NexusUpdateChecker.check`.
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