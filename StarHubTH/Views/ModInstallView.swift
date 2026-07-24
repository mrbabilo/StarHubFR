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
    @State private var showError = false
    @State private var tempDir: URL?
    @State private var showBackups = false
    @State private var installedModNames: [String] = []
    @State private var showSuccess = false
    /// Set false in `onDisappear`. A background analysis started before
    /// dismissal can still complete afterward; its completion checks this
    /// flag so it cleans up the temp dir itself instead of writing into
    /// `@State` that `onDisappear` already ran past (which would leak it).
    @State private var isViewActive = true

    let preloadedZip: URL?

    private let installer = ModZipInstaller()

    init(vm: StarHubTHViewModel, preloadedZip: URL? = nil) {
        self.vm = vm
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
                    Button(vm.L(L10n.ModInstall.manageBackups)) {
                        showBackups = true
                    }
                    .buttonStyle(.bordered)
                }

                // Drop zone
                if zipModInfo == nil {
                    dropZone
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
        .frame(minWidth: 600, minHeight: 400)
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
        .sheet(isPresented: $showBackups) {
            ModInstallBackupsView(vm: vm)
        }
        .alert(vm.L(L10n.ModInstall.validationError), isPresented: $showError) {
            Button(vm.L(L10n.Main.ok)) { }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
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
                        .foregroundColor(.secondary)
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
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension.lowercased() == "zip" else {
                DispatchQueue.main.async {
                    self.errorMessage = vm.L(L10n.ModInstall.invalidZipStructure)
                    self.showError = true
                }
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
                        switch info.validationStatus {
                        case .invalidStructure:
                            self.errorMessage = self.vm.L(L10n.ModInstall.invalidZipStructure)
                        case .oversized:
                            self.errorMessage = self.vm.L(L10n.ModInstall.zipOversized)
                        case .tooManyMods:
                            self.errorMessage = self.vm.L(L10n.ModInstall.tooManyMods)
                        case .corrupted:
                            self.errorMessage = self.vm.L(L10n.ModInstall.zipCorrupted)
                        case .valid:
                            break
                        }
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
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    if let tempDir = self.tempDir {
                        self.installer.cleanupTempDir(at: tempDir)
                        self.tempDir = nil
                    }
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
                    self.vm.refresh()
                    self.vm.log(self.vm.L(L10n.ModInstall.installSuccess), level: .info)

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
                    self.errorMessage = error.localizedDescription
                    self.showError = true
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
    /// name + `Mods`/`Mods_disabled` zone) so the post-install reconciler can
    /// find the manifest that was actually written, without the installer
    /// having to expose its write paths.
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
        let modsDisabledPath = (gameDir as NSString).appendingPathComponent("Mods_disabled")

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

            let destBasePath: String
            if let existing = existingMod, existing.isEnabled, selection.conflictResolution == .overwriteWithBackup {
                destBasePath = modsPath
            } else {
                destBasePath = modsDisabledPath
            }

            paths.append((destBasePath as NSString).appendingPathComponent(finalDestFolderName))
        }
        return paths
    }

    /// Fetches Nexus metadata for installed mods that declare a Nexus mod id
    /// in their manifest UpdateKeys. Rate limiting is handled internally by
    /// the NexusUpdateChecker (bounded concurrency).
    private func fetchNexusMetadata(for mods: [DetectedMod]) {
        let toFetch = mods.filter { !$0.nexusModId.isEmpty }
        guard !toFetch.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            for mod in toFetch {
                self.vm.fetchMetadata(forNexusModId: mod.nexusModId) { _ in }
            }
        }
    }

    private func cancelInstall() {
        zipModInfo = nil
        if let tempDir = tempDir {
            installer.cleanupTempDir(at: tempDir)
            self.tempDir = nil
        }
    }
}