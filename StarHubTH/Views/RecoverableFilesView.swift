import SwiftUI

/// Les fichiers qu'une mise à jour de mod a emportés, et qu'une sauvegarde peut
/// rendre — sans restaurer le mod entier.
///
/// Une mise à jour écrase le dossier du mod : elle emporte ce que l'auteur ne
/// redistribue pas, la traduction française installée à la main en premier.
/// Mesuré sur le parc de référence le 2026-08-24 : **10 `i18n/fr.json`** ne
/// vivent plus que dans une sauvegarde.
///
/// Segment « Fichiers récupérables » de `BackupsView` depuis I-T8 (feuille
/// ouverte depuis les sauvegardes d'installation auparavant).
struct RecoverableFilesView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    /// Le fichier dont l'aperçu est déplié. Un seul à la fois : la lecture se
    /// fait à l'ouverture, et il n'y a pas de raison d'en tenir dix en mémoire.
    @State private var previewing: RecoverableFile?
    @State private var previewText = ""
    @State private var comparing: RecoverableFile?
    /// Les seules copies de l'Entretien que le scanner ne liste pas (I-T8) :
    /// sessions plus anciennes, autres chemins, mods désinstallés. Celles
    /// dont le mod vit encore se remettent comme les autres (`resolved`).
    @State private var soleCopies: [MaintenanceInventory.SoleCopyFile] = []
    @State private var resolved: [String: RecoverableFile] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(localization.L(L10n.Recovery.title))
                    .font(.system(size: 16, weight: .semibold))
                Text(localization.L(L10n.Recovery.note))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            Divider()

            if vm.isScanningRecoverableFiles
                || (vm.maintenanceReport == nil && vm.maintenanceStore.isBuilding) {
                centered { ProgressView() }
            } else if vm.recoverableFiles.isEmpty && soleCopies.isEmpty {
                centered {
                    Text(localization.L(L10n.Recovery.empty))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.recoverableFiles) { file in
                            row(file)
                            if previewing?.id == file.id { preview }
                            Divider().padding(.leading, 20)
                        }
                        ForEach(soleCopies) { copy in
                            if let file = resolved[copy.id] {
                                row(file)
                                if previewing?.id == file.id { preview }
                            } else {
                                goneRow(copy)
                            }
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button(localization.L(L10n.ModInstall.refreshBackups)) {
                    vm.scanRecoverableFiles()
                    vm.buildMaintenanceReport()
                }
                .disabled(vm.isScanningRecoverableFiles)
                Spacer()
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if vm.recoverableFiles.isEmpty { vm.scanRecoverableFiles() }
            // Garde anti-chevauchement dans `buildMaintenanceReport` ; le
            // rapport déjà posé sert pendant la refonte.
            vm.buildMaintenanceReport()
            refreshSoleCopies()
        }
        .onChange(of: vm.maintenanceReport) { refreshSoleCopies() }
        .onChange(of: vm.recoverableFiles) { refreshSoleCopies() }
        .sheet(item: $comparing) { file in
            TranslationRecoveryDiffView(
                vm: vm,
                localization: localization,
                file: file,
                isPresented: Binding(get: { comparing != nil },
                                     set: { if !$0 { comparing = nil } }))
        }
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity)
    }

    private func row(_ file: RecoverableFile) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.modName)
                    .font(.system(size: 13))
                HStack(spacing: 6) {
                    Text(file.relativePath)
                        .font(.system(size: 10, design: .monospaced))
                    Text(reasonLabel(file.reason))
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            // Un fichier de traduction se compare clé à clé : le remplacer en
            // entier coûterait au traducteur ce qu'il a écrit depuis.
            if file.relativePath.hasPrefix("i18n/") {
                Button(localization.L(L10n.Recovery.compareKeys)) { comparing = file }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .pointingHandCursor()
            }
            // L'aperçu avant l'écriture : on n'écrase pas un fichier du dossier
            // d'un mod sans avoir montré ce qu'on y met.
            Button(localization.L(L10n.Recovery.preview)) { togglePreview(file) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointingHandCursor()
            // Rien à remplacer quand le fichier installé n'a rien perdu : le
            // proposer inviterait à écraser le plus récent par le plus ancien.
            if file.reason != .translationDiffers {
                Button(localization.L(L10n.Recovery.recover)) { vm.recoverFile(file) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .pointingHandCursor()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    /// Le mod n'est plus installé : rien où remettre le fichier, on le montre.
    private func goneRow(_ copy: MaintenanceInventory.SoleCopyFile) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(copy.modFolder)
                    .font(.system(size: 13))
                HStack(spacing: 6) {
                    Text(copy.relativePath)
                        .font(.system(size: 10, design: .monospaced))
                    Text(localization.L(L10n.Maintenance.reasonGone))
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                .foregroundColor(.secondary)
            }
            Spacer()
            Button(localization.L(L10n.Maintenance.actionReveal)) {
                if let path = vm.maintenanceProtectedFilePath(session: copy.session,
                                                              relativePath: copy.relativePath) {
                    vm.revealProtectedBackup(atPath: path)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointingHandCursor()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func refreshSoleCopies() {
        guard let report = vm.maintenanceReport else { return }
        soleCopies = MaintenanceInventory.soleCopyFiles(
            in: report, excluding: Set(vm.recoverableFiles.map(\.id)))
        resolved = vm.maintenanceRecoverableFiles(soleCopies)
    }

    private var preview: some View {
        ScrollView {
            Text(previewText)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(height: 180)
        .background(Color(nsColor: .textBackgroundColor))
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func togglePreview(_ file: RecoverableFile) {
        if previewing?.id == file.id {
            previewing = nil
            previewText = ""
            return
        }
        previewing = file
        // Tronqué : un `fr.json` de mod dépasse les vingt mille caractères, et
        // l'aperçu sert à reconnaître le fichier, pas à le relire en entier.
        let raw = (try? String(contentsOfFile: file.backupPath, encoding: .utf8)) ?? ""
        previewText = raw.count > 4000 ? String(raw.prefix(4000)) + "\n…" : raw
    }

    private func reasonLabel(_ reason: RecoveryReason) -> String {
        switch reason {
        case .absentFromInstall:
            return localization.L(L10n.Recovery.reasonAbsent)
        case .keysLostSinceBackup(let keys):
            return String(format: localization.L(L10n.Recovery.reasonLostKeys), Int64(keys.count))
        case .translationDiffers:
            return localization.L(L10n.Recovery.reasonDiffers)
        }
    }
}
