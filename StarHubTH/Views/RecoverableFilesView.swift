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
    var viewModel: StarHubTHViewModel
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
    /// N-11 — le dossier du mod dont la fiche a mené ici ; `nil` = tout.
    @State private var modFilter: String?

    private var shownFiles: [RecoverableFile] {
        viewModel.recoverableFiles.filter { modFilter == nil || $0.folderName == modFilter }
    }
    private var shownSoleCopies: [MaintenanceInventory.SoleCopyFile] {
        soleCopies.filter { modFilter == nil || $0.modFolder == modFilter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Le titre de la page et du segment suffit : reste ce qui le
            // précise — pourquoi ces fichiers ne vivent plus qu'en sauvegarde.
            Label(localization.L(L10n.Recovery.note), systemImage: "info.circle.fill")
                .font(AppDesign.Font.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppDesign.Spacing.xl)
                .padding(.vertical, AppDesign.Spacing.sm)

            Divider()

            if let modFilter {
                HStack {
                    Text(String(format: localization.L(L10n.Recovery.filteredOn), modFilter))
                        .font(AppDesign.Font.footnote(.medium))
                    Spacer()
                    Button(localization.L(L10n.Recovery.showAll)) { self.modFilter = nil }
                        .buttonStyle(.hoverLink)
                        .font(AppDesign.Font.footnote)
                }
                .padding(.horizontal, AppDesign.Spacing.xl)
                .padding(.vertical, AppDesign.Spacing.sm)
                Divider()
            }

            if viewModel.isScanningRecoverableFiles
                || (viewModel.maintenanceReport == nil && viewModel.maintenanceStore.isBuilding) {
                centered { ProgressView() }
            } else if shownFiles.isEmpty && shownSoleCopies.isEmpty {
                centered {
                    Text(localization.L(L10n.Recovery.empty))
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                BackToTopScrollView(localization) {
                    // Une carte, lignes paresseuses : les seules copies de
                    // l'Entretien peuvent se compter par dizaines.
                    LazyVStack(spacing: 0) {
                        ForEach(shownFiles) { file in
                            row(file)
                            if previewing?.id == file.id { preview }
                            Divider().padding(.leading, 20)
                        }
                        ForEach(shownSoleCopies) { copy in
                            if let file = resolved[copy.id] {
                                row(file)
                                if previewing?.id == file.id { preview }
                            } else {
                                goneRow(copy)
                            }
                            Divider().padding(.leading, 20)
                        }
                    }
                    .cardSurface(padding: 0)
                    .padding(AppDesign.Spacing.xl)
                }
            }

            Divider()

            HStack {
                Button(localization.L(L10n.ModInstall.refreshBackups)) {
                    viewModel.scanRecoverableFiles()
                    viewModel.buildMaintenanceReport()
                }
                .disabled(viewModel.isScanningRecoverableFiles)
                Spacer()
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if viewModel.recoverableFiles.isEmpty { viewModel.scanRecoverableFiles() }
            // Garde anti-chevauchement dans `buildMaintenanceReport` ; le
            // rapport déjà posé sert pendant la refonte.
            viewModel.buildMaintenanceReport()
            refreshSoleCopies()
            consumePendingFocus()
        }
        .onChange(of: viewModel.navigationStore.pendingBackupsFocus) { consumePendingFocus() }
        .onChange(of: viewModel.maintenanceReport) { refreshSoleCopies() }
        .onChange(of: viewModel.recoverableFiles) { refreshSoleCopies() }
        .sheet(item: $comparing) { file in
            TranslationRecoveryDiffView(
                vm: viewModel,
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
                    .font(AppDesign.Font.body)
                HStack(spacing: 6) {
                    Text(file.relativePath)
                        .font(AppDesign.Font.monoIconXS)
                    Text(reasonLabel(file.reason))
                        .font(AppDesign.Font.iconXS)
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
                Button(localization.L(L10n.Recovery.recover)) { viewModel.recoverFile(file) }
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
                    .font(AppDesign.Font.body)
                HStack(spacing: 6) {
                    Text(copy.relativePath)
                        .font(AppDesign.Font.monoIconXS)
                    Text(localization.L(L10n.Maintenance.reasonGone))
                        .font(AppDesign.Font.iconXS)
                        .foregroundColor(.orange)
                }
                .foregroundColor(.secondary)
            }
            Spacer()
            Button(localization.L(L10n.Maintenance.actionReveal)) {
                if let path = viewModel.maintenanceProtectedFilePath(session: copy.session,
                                                              relativePath: copy.relativePath) {
                    viewModel.revealProtectedBackup(atPath: path)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointingHandCursor()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    /// N-11 : filtrer sur le mod de la fiche, une fois (patron I-T5).
    private func consumePendingFocus() {
        guard let folder = viewModel.navigationStore.pendingBackupsFocus else { return }
        modFilter = folder
        viewModel.navigationStore.pendingBackupsFocus = nil
    }

    private func refreshSoleCopies() {
        guard let report = viewModel.maintenanceReport else { return }
        soleCopies = MaintenanceInventory.soleCopyFiles(
            in: report, excluding: Set(viewModel.recoverableFiles.map(\.id)))
        resolved = viewModel.maintenanceRecoverableFiles(soleCopies)
    }

    private var preview: some View {
        ScrollView {
            Text(previewText)
                .font(AppDesign.Font.monoFootnote)
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
