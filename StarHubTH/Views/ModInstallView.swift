import SwiftUI
import UniformTypeIdentifiers

/// Main view for mod installation via drag-and-drop of zip files.
struct ModInstallView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var isDropTarget = false
    @State private var zipModInfo: ZipModInfo?
    @State private var isAnalyzing = false
    @State private var isInstalling = false
    @State private var errorMessage: String?
    @State private var errorRecoveryHint: String?
    @State private var showError = false
    @State private var tempDir: URL?
    @State private var installedModNames: [String] = []
    @State private var showSuccess = false
    @State private var showFilePicker = false
    /// Set false in `onDisappear`. A background analysis started before
    /// dismissal can still complete afterward; its completion checks this
    /// flag so it cleans up the temp dir itself instead of writing into
    /// `@State` that `onDisappear` already ran past (which would leak it).
    @State private var isViewActive = true

    /// Une archive qui n'est pas un mod, mais du contenu reconnu comme
    /// destiné au dossier d'un autre mod — voir `DroppedContentRecognizer`.
    /// Le dossier temporaire reste vivant tant que cette proposition est à
    /// l'écran : c'est de là que le fichier sera copié.
    private struct DroppedProposal {
        let hostDisplayName: String
        /// Le mod hôte lui-même, pour pouvoir le sauvegarder avant écrasement
        /// sans avoir à le retrouver depuis le chemin de destination.
        let host: ModItem
        let sourceURL: URL
        let destinationURL: URL
        let hostIsPaused: Bool
    }
    @State private var droppedProposal: DroppedProposal?
    @State private var showDroppedProposal = false

    /// Binding controlled by the parent so the sheet can be dismissed from
    /// inside this view (close button / Done button).
    @Binding var isPresented: Bool

    let preloadedZip: URL?

    private let installer = ModZipInstaller()

    init(vm: StarHubTHViewModel, isPresented: Binding<Bool>, preloadedZip: URL? = nil) {
        self.vm = vm
        self._isPresented = isPresented
        self.preloadedZip = preloadedZip
    }

    var body: some View {
        VStack(spacing: 20) {
            if showSuccess {
                successView
            } else {
                // Header
                HStack {
                    Text(vm.L(L10n.ModInstall.title))
                        .font(.system(size: 20, weight: .semibold))
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
                    .help(vm.L(L10n.Saves.cancel))
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
                        tempDir: $tempDir,
                        isInstalling: $isInstalling,
                        onInstall: installSelected,
                        onCancel: cancelInstall
                    )
                }
            }
        }
        .padding(20)
        .frame(minWidth: 600, idealWidth: 700, minHeight: 400, idealHeight: 600)
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
        .alert(vm.L(L10n.ModInstall.validationError), isPresented: $showError) {
            Button(vm.L(L10n.Main.ok)) { }
        } message: {
            if let error = errorMessage {
                if let hint = errorRecoveryHint {
                    Text("\(error)\n\n\(hint)")
                } else {
                    Text(error)
                }
            }
        }
        .alert(vm.L(L10n.ModInstall.droppedTitle), isPresented: $showDroppedProposal) {
            if let proposal = droppedProposal {
                Button(String(format: vm.L(L10n.ModInstall.droppedInstall),
                              proposal.hostDisplayName)) {
                    installDroppedContent(proposal)
                }
            }
            Button(vm.L(L10n.ModInstall.cancel), role: .cancel) {
                if let tempDir = tempDir {
                    installer.cleanupTempDir(at: tempDir)
                    self.tempDir = nil
                }
            }
        } message: {
            Text(droppedProposalMessage)
        }
        .onDisappear {
            isViewActive = false
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

    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text(String(format: vm.L(L10n.ModInstall.successMessage), installedModNames.count))
                .font(.system(size: 18, weight: .semibold))
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                ForEach(installedModNames, id: \.self) { name in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                        Text(name)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 400)

            Spacer()

            Button(vm.L(L10n.ModInstall.done)) {
                showSuccess = false
                installedModNames = []
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            if isAnalyzing {
                ProgressView()
                    .controlSize(.large)
                Text(vm.L(L10n.ModInstall.analyzingZip))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: isDropTarget ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .font(.system(size: 48))
                    .foregroundColor(isDropTarget ? .accentColor : .secondary.opacity(0.6))

                VStack(spacing: 8) {
                    Text(vm.L(L10n.ModInstall.dropZoneText))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)

                    Text(vm.L(L10n.ModInstall.dropHint))
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor.opacity(0.8))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isDropTarget ? 200 : 180)
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
        guard let provider = providers.first else { return }

            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                // Un seul chemin d'échec : le message change, le conseil découle
                // du statut, et il n'y a qu'un saut vers le fil principal.
                let fail: (String, ValidationStatus) -> Void = { message, status in
                    DispatchQueue.main.async {
                        self.errorMessage = message
                        self.errorRecoveryHint = status.recoveryHintKey.map { self.vm.L($0) }
                        self.showError = true
                    }
                }

                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                fail(vm.L(L10n.ModInstall.invalidZipStructure), .invalidStructure)
                return
            }

            // Le format se juge sur la signature, pas sur l'extension : un
            // dépôt sans extension exploitable mais à la signature reconnue
            // reste une archive installable. L'extension ne sert qu'au message
            // quand rien ne colle.
            let declared = url.pathExtension.lowercased()
            let recognised = ModZipInstaller.detectedArchiveExtension(at: url) != nil
            guard recognised || ModZipInstaller.supportedExtensions.contains(declared) else {
                fail(String(format: vm.L(L10n.ModInstall.unsupportedFormat), url.pathExtension),
                     .unsupportedFormat(url.pathExtension))
                return
            }

            DispatchQueue.main.async {
                // A manually dropped zip is not the Nexus download that opened
                // this sheet — drop any pending source so it can't misapply.
                self.vm.pendingNexusSource = nil
                self.analyzeZip(url)
            }
        }
    }

    private func analyzeZip(_ url: URL) {
        isAnalyzing = true
        zipModInfo = nil

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
                DispatchQueue.main.async {
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
                                self.errorMessage = String(
                                    format: self.vm.L(L10n.ModInstall.droppedHostMissing), hostName)
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

                        switch info.validationStatus {
                        case .invalidStructure:
                            // Dire ce que l'archive contenait : sans cela
                            // l'utilisateur sait seulement qu'il manque un
                            // manifeste, pas ce qu'il y avait à la place.
                            var msg = self.vm.L(L10n.ModInstall.invalidZipStructure)
                            if !info.extractedTopLevel.isEmpty {
                                msg += "\n\n" + String(format: self.vm.L(L10n.ModInstall.archiveContains),
                                                       info.extractedTopLevel.joined(separator: ", "))
                            }
                            self.errorMessage = msg
                        case .oversized:
                            self.errorMessage = self.vm.L(L10n.ModInstall.zipOversized)
                        case .tooManyMods:
                            self.errorMessage = self.vm.L(L10n.ModInstall.tooManyMods)
                        case .corrupted:
                            self.errorMessage = self.vm.L(L10n.ModInstall.zipCorrupted)
                        case .unsupportedFormat(let ext):
                            self.errorMessage = String(format: self.vm.L(L10n.ModInstall.unsupportedFormat), ext)
                        case .valid:
                            break
                        }
                        // Le conseil découle du statut, et cette règle vit dans
                        // Core avec ses tests — la vue ne fait que l'afficher.
                        self.errorRecoveryHint = info.validationStatus.recoveryHintKey.map { self.vm.L($0) }
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
                        self.errorMessage = self.vm.L(L10n.ModInstall.noModsDetected)
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
                    self.errorMessage = self.vm.installErrorMessage(error)
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
        var text = String(format: vm.L(L10n.ModInstall.droppedQuestion),
                          proposal.hostDisplayName, proposal.destinationURL.path)
        if proposal.hostIsPaused {
            text += "\n\n" + String(format: vm.L(L10n.ModInstall.droppedHostPaused),
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
    private func recognizeDroppedContent() -> DroppedOutcome? {
        guard let tempDir = tempDir,
              let found = DroppedContentRecognizer.recognize(inExtractedDirectory: tempDir)
        else { return nil }

        switch DroppedContentRecognizer.destination(for: found.rule,
                                                    fileName: found.fileURL.lastPathComponent,
                                                    installedMods: vm.mods,
                                                    gameDir: vm.gameDir) {
        case .ready(let destination, let paused):
            let wanted = found.rule.hostUniqueId.lowercased()
            guard let host = vm.mods
                .flatMap({ $0.isGroup ? ($0.children ?? []) : [$0] })
                .first(where: { $0.uniqueId.lowercased() == wanted })
            else { return .hostMissing(found.rule.hostDisplayName) }
            return .proposal(DroppedProposal(hostDisplayName: found.rule.hostDisplayName,
                                             host: host,
                                             sourceURL: found.fileURL,
                                             destinationURL: destination,
                                             hostIsPaused: paused))
        case .hostMissing(let name):
            return .hostMissing(name)
        case .unusableFileName:
            // Nom de fichier refusé : ne rien proposer, l'archive repart sur le
            // refus ordinaire plutôt que sur une destination approximative.
            return nil
        }
    }

    /// Copie le fichier reconnu chez son hôte, après avoir sauvegardé ce dernier
    /// si le fichier existait déjà.
    private func installDroppedContent(_ proposal: DroppedProposal) {
        isInstalling = true
        let gameDir = vm.gameDir
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do {
                // Un sac peut avoir été retouché à la main (prix, capacités) :
                // sauvegarder l'hôte avant d'écraser. Rien à préserver si le
                // fichier n'existait pas.
                //
                // Le `try` n'est pas un `try?` : « sauvegarder **puis**
                // écraser » n'a de sens que si l'échec de la sauvegarde arrête
                // l'écrasement. L'avaler écraserait un fichier retouché sans
                // filet et sans le dire.
                if FileManager.default.fileExists(atPath: proposal.destinationURL.path) {
                    _ = try ModInstallBackupManager.shared.createBackup(
                        for: proposal.host, gameDir: gameDir, reason: .beforeInstall)
                }
                try DroppedContentRecognizer.install(from: proposal.sourceURL,
                                                     to: proposal.destinationURL)
            } catch {
                failure = self.vm.installErrorMessage(error)
            }
            DispatchQueue.main.async {
                self.isInstalling = false
                if let tempDir = self.tempDir {
                    self.installer.cleanupTempDir(at: tempDir)
                    self.tempDir = nil
                }
                if let failure = failure {
                    self.errorMessage = failure
                    self.errorRecoveryHint = nil
                    self.showError = true
                } else {
                    // Pas de `scanMods()` ici : le fichier a atterri *dans* un
                    // mod existant, aucun dossier de mod n'a bougé. Rescanner
                    // ne changerait rien à l'écran et laisserait croire le
                    // contraire.
                    self.installedModNames = [String(
                        format: self.vm.L(L10n.ModInstall.droppedDone), proposal.hostDisplayName)]
                    self.showSuccess = true
                }
            }
        }
    }

    private func installSelected(selections: [InstallSelection]) {
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
                try self.installer.install(
                    from: tempDir,
                    to: modsDisabledPath,
                    selections: selections,
                    detectedMods: info.detectedMods,
                    gameDir: gameDir,
                    existingMods: existingMods
                )

                DispatchQueue.main.async {
                    self.isInstalling = false
                    self.installer.cleanupTempDir(at: tempDir)
                    self.tempDir = nil
                    self.installedModNames = modsBeingInstalled.map { $0.name }
                    self.showSuccess = true
                    self.zipModInfo = nil
                    // Les fichiers de ces mods viennent de changer : leur
                    // couverture en cache ne vaut plus rien. Sans cela, un mod
                    // mis à jour garderait le pourcentage de sa version
                    // précédente indéfiniment.
                    for mod in modsBeingInstalled {
                        self.vm.invalidateFrenchCoverage(for: mod.folderName)
                    }
                    self.vm.refresh()
                    self.vm.log(self.vm.L(L10n.ModInstall.installSuccess), level: .info)

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
                        let installedFolderPaths = self.installedFolderPaths(
                            selections: selections,
                            detectedMods: info.detectedMods,
                            existingMods: existingMods,
                            gameDir: gameDir
                        )
                        // Reconcile FIRST — it reads this mod's update entry to
                        // learn the version the checker flags on — then drop the
                        // entry from the list so it no longer appears.
                        self.vm.reconcileManifestVersion(installedFolderPaths: installedFolderPaths)
                        self.vm.dismissNexusUpdate(nexusModId: source.modId)
                    }

                    // Auto-fetch Nexus metadata (image + description) for
                    // installed mods that have a Nexus mod id, so the mods
                    // list shows them immediately without a manual check.
                    self.fetchNexusMetadata(for: modsBeingInstalled)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    self.errorMessage = self.vm.installErrorMessage(error)
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

    /// Mirrors `ModZipInstaller.install`'s destination logic (final folder
    /// name + enabled/disabled prefix under Mods/) so the post-install
    /// reconciler can find the manifest that was actually written, without
    /// the installer having to expose its write paths.
    ///
    /// `.rename`-resolved mods are excluded: the installer appends an
    /// internally-generated timestamp suffix (`stampedFolderSuffix()`) that
    /// isn't surfaced anywhere, so the real folder name can't be reproduced
    /// here — abstaining is safer than guessing wrong and mutating (or
    /// misreading) an unrelated manifest.
    private func installedFolderPaths(selections: [InstallSelection], detectedMods: [DetectedMod], existingMods: [ModItem], gameDir: String) -> [String] {
        // Note: unlike ModZipInstaller.install, this doesn't skip sources that
        // failed the existence check — a path to a not-actually-written folder
        // is harmless because reconcileManifestVersion fails safe (its
        // `try? String(contentsOfFile:)` returns nil → no-op).
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")

        var paths: [String] = []
        for selection in selections {
            guard selection.selected else { continue }
            guard let detectedMod = detectedMods.first(where: { $0.id == selection.modId }) else { continue }

            let existingMod = existingMods.first { $0.uniqueId.caseInsensitiveCompare(detectedMod.uniqueId) == .orderedSame }

            let finalDestFolderName: String
            if existingMod != nil, let resolution = selection.conflictResolution {
                switch resolution {
                case .skip:
                    continue
                case .rename:
                    continue  // unreproducible timestamp suffix → abstain
                case .overwriteWithBackup, .keepExisting, .useNew:
                    finalDestFolderName = detectedMod.folderName
                }
            } else {
                finalDestFolderName = detectedMod.folderName
            }

            // Enabled-update lands at Mods/X, everything else at Mods/.X
            // (disabled by default). Mirrors the installer's destFolderPrefix.
            let prefix: String
            if let existing = existingMod, existing.isEnabled, selection.conflictResolution == .overwriteWithBackup {
                prefix = ""
            } else {
                prefix = "."
            }

            paths.append((modsPath as NSString).appendingPathComponent(prefix + finalDestFolderName))
        }
        return paths
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
    }
}