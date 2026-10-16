import SwiftUI

/// Les trois confirmations de la vue passent par **un seul** modificateur
/// `.alert` — patron `SaveEditorConfirmation` (`SavesView.swift`) : deux
/// présentateurs sur la même vue ne se présentent pas tous les deux
/// (mesuré le 2026-09-02, dans les deux sens).
private enum ModConfigBackupsConfirmation {
    /// Les éléments voyagent avec la demande : relire la sélection au moment
    /// de l'action restaurerait ce qu'une autre vue avait coché.
    case restore(ModConfigBackup, [ModConfigBackupItem])
    case delete(ModConfigBackup)
    case cleanup(String)
}

struct ModConfigBackupsView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// R8 — le mod venu de l'éditeur de config (« Toutes les sauvegardes de ce mod… »).
    @Binding var modFilter: String?

    @State private var backups: [ModConfigBackup] = []
    private var shown: [ModConfigBackup] {
        guard let modFilter else { return backups }
        return backups.filter { $0.items.contains { $0.modFolderName == modFilter } }
    }
    @State private var expandedBackupId: UUID?
    @State private var selectedItemIds: Set<UUID> = []
    @State private var isBusy = false

    @State private var confirmation: ModConfigBackupsConfirmation?

    /// `nil` when a backup can be created; otherwise the localized reason
    /// shown as a tooltip on the disabled button.
    private var createDisabledReason: String? {
        if vm.gameDir.isEmpty { return localization.L(L10n.ModConfigBackups.noGameDir) }
        if vm.enabledMods.isEmpty { return localization.L(L10n.ModConfigBackups.noEnabledMods) }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if shown.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .onAppear { reload() }
        // Un seul présentateur pour les trois confirmations — voir
        // `ModConfigBackupsConfirmation`. `presenting:` porte la valeur ;
        // les actions lisent `pending`, jamais `confirmation` (déjà remis à
        // `nil` au moment où l'action s'exécute, après la fermeture).
        .alert(confirmationTitle,
               isPresented: Binding(get: { confirmation != nil },
                                    set: { if !$0 { confirmation = nil } }),
               presenting: confirmation) { pending in
            switch pending {
            case .restore(let backup, let items):
                Button(localization.L(L10n.ModConfigBackups.restoreBackup), role: .destructive) {
                    performRestore(backup, items)
                }
                Button(localization.L(L10n.ModConfigBackups.cancel), role: .cancel) { }
            case .delete(let backup):
                Button(localization.L(L10n.ModConfigBackups.deleteBackup), role: .destructive) {
                    performDelete(backup)
                }
                Button(localization.L(L10n.ModConfigBackups.cancel), role: .cancel) { }
            case .cleanup:
                Button(localization.L(L10n.Main.ok)) { }
            }
        } message: { pending in
            switch pending {
            case .restore(_, let items): Text(restoreWarning(items))
            case .delete: EmptyView()
            case .cleanup(let message): Text(message)
            }
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .restore: return localization.L(L10n.ModConfigBackups.restoreWarning)
        case .delete: return localization.L(L10n.ModConfigBackups.deleteConfirm)
        case .cleanup: return localization.L(L10n.ModConfigBackups.title)
        case nil: return ""
        }
    }

    // MARK: - Header

    /// Le titre est celui de la page et du segment : ici, le compte et le
    /// geste de création.
    private var header: some View {
        HStack {
            Text(String(format: localization.L(L10n.ModConfigBackups.headerCount), Int64(shown.count)))
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            if let modFilter {
                Button { self.modFilter = nil } label: { Label(modFilter, systemImage: "xmark.circle.fill") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help(localization.L(L10n.Backups.configFilterClear))
            }

            Spacer()

            Button(action: createBackup) {
                HStack(spacing: 4) {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                    Text(localization.L(isBusy ? L10n.ModConfigBackups.creatingBackup : L10n.ModConfigBackups.createBackup))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isBusy || createDisabledReason != nil)
            .help(createDisabledReason ?? "")
        }
        .padding(.horizontal, AppDesign.Spacing.xl)
        .padding(.vertical, AppDesign.Spacing.sm)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            IconTile(icon: "archivebox", tint: AppDesign.Color.accent, size: 64)
            Text(localization.L(L10n.ModConfigBackups.noBackups))
                .multilineTextAlignment(.center).font(AppDesign.Font.rowTitle).foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var list: some View {
        BackToTopScrollView(localization) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(shown) { backup in
                    ModConfigBackupRow(
                        vm: vm,
                        localization: localization,
                        backup: backup,
                        isExpanded: expandedBackupId == backup.id,
                        selectedItemIds: expandedBackupId == backup.id ? $selectedItemIds : .constant([]),
                        onToggleExpand: { toggleExpand(backup) },
                        onRestoreSelected: {
                            confirmation = .restore(backup, backup.items.filter { selectedItemIds.contains($0.id) })
                        },
                        onDelete: { confirmation = .delete(backup) }
                    )
                }
            }
            .padding(AppDesign.Spacing.xl)
        }
    }

    // MARK: - Actions

    private func reload() {
        Task { backups = await Task.detached(priority: .userInitiated) { ModConfigBackupManager.shared.loadBackups() }.value }
    }

    private func toggleExpand(_ backup: ModConfigBackup) {
        if expandedBackupId == backup.id {
            expandedBackupId = nil
            selectedItemIds = []
        } else {
            expandedBackupId = backup.id  // rien de coché, sauf le mod demandé par l'éditeur
            selectedItemIds = Set(backup.items.filter { $0.modFolderName == modFilter }.map(\.id))
        }
    }

    private func createBackup() {
        guard !isBusy, createDisabledReason == nil else { return }
        isBusy = true
        let gameDir = vm.gameDir
        let mods = vm.enabledMods
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let manager = ModConfigBackupManager.shared
                _ = try manager.createBackup(gameDir: gameDir, mods: mods)
                let deletedCount = manager.cleanupOldBackups(), fetched = manager.loadBackups()
                DispatchQueue.main.async {
                    self.backups = fetched
                    self.isBusy = false
                    // Pose spontanée (fin de tâche de fond, pas un geste de
                    // l'utilisateur) : `isBusy` ne verrouille que le bouton
                    // de création, pas la liste — restaurer/supprimer une
                    // ligne pendant la création reste possible et ouvre déjà
                    // une confirmation. Sur un bouton destructeur, écraser
                    // cette confirmation ferait valider autre chose que ce
                    // que l'utilisateur croit voir. On préfère perdre le
                    // message de fin de purge que détourner son clic.
                    if deletedCount > 0 && self.confirmation == nil {
                        self.confirmation = .cleanup(String(format: self.localization.L(L10n.ModConfigBackups.cleanupComplete), deletedCount))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.vm.alertStore.show(self.localizedMessage(for: error, genericKey: L10n.ModConfigBackups.backupFailed))
                }
            }
        }
    }

    /// `ModConfigBackupManager.BackupError` cases are messages this app
    /// authors itself, so they get a proper localized string; any other
    /// error (file I/O, etc.) falls back to its (English) system
    /// description substituted into the localized generic template.
    private func localizedMessage(for error: Error, genericKey: String) -> String {
        if let backupError = error as? ModConfigBackupManager.BackupError {
            switch backupError {
            case .gameDirEmpty: return localization.L(L10n.ModConfigBackups.noGameDir)
            case .noEnabledMods: return localization.L(L10n.ModConfigBackups.noEnabledMods)
            case .nothingToBackUp: return localization.L(L10n.ModConfigBackups.nothingToBackUp)
            }
        }
        return String(format: localization.L(genericKey), error.localizedDescription)
    }

    /// Ce que la restauration annonce : « restaurée avec succès » seulement
    /// si rien n'a sauté (mod plus installé, dossier absent, écriture
    /// refusée) — avant, zéro fichier écrit s'annonçait comme douze.
    private func restoreReportMessage(_ report: ModConfigRestoreReport) -> String {
        if report.isComplete {
            return localization.L(L10n.ModConfigBackups.backupRestored)
        }
        var lines: [String] = []
        if report.filesWritten == 0 {
            lines.append(localization.L(L10n.ModConfigBackups.restoreReportNothing))
        } else {
            lines.append(String(format: localization.L(L10n.ModConfigBackups.restoreReportWritten),
                                Int64(report.filesWritten), Int64(report.modsRestored)))
        }
        if !report.skippedMods.isEmpty {
            lines.append(String(format: localization.L(L10n.ModConfigBackups.restoreReportSkippedMods),
                                report.skippedMods.joined(separator: ", ")))
        }
        if !report.skippedFiles.isEmpty {
            lines.append(String(format: localization.L(L10n.ModConfigBackups.restoreReportSkippedFiles),
                                report.skippedFiles.joined(separator: ", ")))
        }
        return lines.joined(separator: "\n\n")
    }

    /// La confirmation nomme ce qui sera remplacé : une sauvegarde de config
    /// porte aussi les i18n, donc les traductions faites dans l'app.
    private func restoreWarning(_ items: [ModConfigBackupItem]) -> String {
        let lines = items.prefix(8).map { "• \($0.modDisplayName) — \($0.files.joined(separator: ", "))" }
            + (items.count > 8 ? ["…"] : [])
        return localization.L(L10n.ModConfigBackups.restoreWarningCreateBackup) + "\n\n"
            + localization.L(L10n.ModConfigBackups.restoreFiles) + "\n" + lines.joined(separator: "\n")
    }

    private func performRestore(_ backup: ModConfigBackup, _ selected: [ModConfigBackupItem]) {
        guard !selected.isEmpty else { return }
        isBusy = true
        let gameDir = vm.gameDir
        // Tous les mods, pas seulement les actifs : le filet pris avant
        // d'écraser doit couvrir les mods **en pause**, où vivent presque
        // toutes les configurations du parc.
        let currentMods = vm.scanStore.mods
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let report = try ModConfigBackupManager.shared.restoreBackup(
                    gameDir: gameDir,
                    backup: backup,
                    selectedItems: selected,
                    currentMods: currentMods
                )
                let fetched = ModConfigBackupManager.shared.loadBackups()
                DispatchQueue.main.async {
                    self.backups = fetched
                    self.isBusy = false
                    self.vm.alertStore.show(self.restoreReportMessage(report))
                    self.vm.log(self.restoreReportMessage(report),
                                level: report.isComplete ? .info : .warning)
                    // Des `config.json` viennent d'être réécrits, et le parc
                    // n'a pas bougé : sans ça, le rapport de raccourcis reste
                    // sur l'état d'avant la restauration (X66).
                    self.vm.rescanKeybindsAfterConfigWrite()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.vm.alertStore.show(self.localizedMessage(for: error, genericKey: L10n.ModConfigBackups.restoreFailed))
                }
            }
        }
    }

    private func performDelete(_ backup: ModConfigBackup) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try ModConfigBackupManager.shared.trashBackup(backup)
                let fetched = ModConfigBackupManager.shared.loadBackups()
                DispatchQueue.main.async {
                    self.backups = fetched
                    if self.expandedBackupId == backup.id {
                        self.expandedBackupId = nil
                        self.selectedItemIds = []
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.vm.alertStore.show(self.localizedMessage(for: error, genericKey: L10n.ModConfigBackups.deleteFailed))
                }
            }
        }
    }
}
