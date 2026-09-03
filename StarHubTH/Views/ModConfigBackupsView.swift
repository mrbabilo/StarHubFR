import SwiftUI

/// Les trois confirmations de la vue passent par **un seul** modificateur
/// `.alert` — patron `SaveEditorConfirmation` (`SavesView.swift`) : deux
/// présentateurs sur la même vue ne se présentent pas tous les deux
/// (mesuré le 2026-09-02, dans les deux sens).
private enum ModConfigBackupsConfirmation {
    case restore(ModConfigBackup)
    case delete(ModConfigBackup)
    case cleanup(String)
}

struct ModConfigBackupsView: View {
    @ObservedObject var vm: StarHubTHViewModel

    @State private var backups: [ModConfigBackup] = []
    @State private var expandedBackupId: UUID?
    @State private var selectedItemIds: Set<UUID> = []
    @State private var isBusy = false

    @State private var confirmation: ModConfigBackupsConfirmation?

    /// `nil` when a backup can be created; otherwise the localized reason
    /// shown as a tooltip on the disabled button.
    private var createDisabledReason: String? {
        if vm.gameDir.isEmpty { return vm.L(L10n.ModConfigBackups.noGameDir) }
        if vm.enabledMods.isEmpty { return vm.L(L10n.ModConfigBackups.noEnabledMods) }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if backups.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
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
            case .restore(let backup):
                Button(vm.L(L10n.ModConfigBackups.restoreBackup), role: .destructive) {
                    performRestore(backup)
                }
                Button(vm.L(L10n.ModConfigBackups.cancel), role: .cancel) { }
            case .delete(let backup):
                Button(vm.L(L10n.ModConfigBackups.deleteBackup), role: .destructive) {
                    performDelete(backup)
                }
                Button(vm.L(L10n.ModConfigBackups.cancel), role: .cancel) { }
            case .cleanup:
                Button(vm.L(L10n.Main.ok)) { }
            }
        } message: { pending in
            switch pending {
            case .restore: Text(vm.L(L10n.ModConfigBackups.restoreWarningCreateBackup))
            case .delete: EmptyView()
            case .cleanup(let message): Text(message)
            }
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .restore: return vm.L(L10n.ModConfigBackups.restoreWarning)
        case .delete: return vm.L(L10n.ModConfigBackups.deleteConfirm)
        case .cleanup: return vm.L(L10n.ModConfigBackups.title)
        case nil: return ""
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(vm.L(L10n.ModConfigBackups.title))
                .font(.headline)
                .foregroundColor(.primary)

            Spacer()

            Button(action: createBackup) {
                HStack(spacing: 4) {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                    Text(vm.L(isBusy ? L10n.ModConfigBackups.creatingBackup : L10n.ModConfigBackups.createBackup))
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .disabled(isBusy || createDisabledReason != nil)
            .help(createDisabledReason ?? "")
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "archivebox")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text(vm.L(L10n.ModConfigBackups.noBackups))
                .multilineTextAlignment(.center)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(backups) { backup in
                    ModConfigBackupRow(
                        vm: vm,
                        backup: backup,
                        isExpanded: expandedBackupId == backup.id,
                        selectedItemIds: expandedBackupId == backup.id ? $selectedItemIds : .constant([]),
                        onToggleExpand: { toggleExpand(backup) },
                        onRestoreSelected: { confirmation = .restore(backup) },
                        onDelete: { confirmation = .delete(backup) }
                    )
                }
            }
            .padding(20)
        }
    }

    // MARK: - Actions

    private func reload() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetched = ModConfigBackupManager.shared.loadBackups()
            DispatchQueue.main.async {
                self.backups = fetched
            }
        }
    }

    private func toggleExpand(_ backup: ModConfigBackup) {
        if expandedBackupId == backup.id {
            expandedBackupId = nil
            selectedItemIds = []
        } else {
            expandedBackupId = backup.id
            selectedItemIds = Set(backup.items.map { $0.id })
        }
    }

    private func createBackup() {
        guard !isBusy, createDisabledReason == nil else { return }
        isBusy = true
        let gameDir = vm.gameDir
        let mods = vm.enabledMods
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try ModConfigBackupManager.shared.createBackup(gameDir: gameDir, mods: mods)
                let deletedCount = ModConfigBackupManager.shared.cleanupOldBackups()
                let fetched = ModConfigBackupManager.shared.loadBackups()
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
                        self.confirmation = .cleanup(String(format: self.vm.L(L10n.ModConfigBackups.cleanupComplete), deletedCount))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.vm.alertMessage = self.localizedMessage(for: error, genericKey: L10n.ModConfigBackups.backupFailed)
                    self.vm.showAlert = true
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
            case .gameDirEmpty: return vm.L(L10n.ModConfigBackups.noGameDir)
            case .noEnabledMods: return vm.L(L10n.ModConfigBackups.noEnabledMods)
            case .nothingToBackUp: return vm.L(L10n.ModConfigBackups.nothingToBackUp)
            }
        }
        return String(format: vm.L(genericKey), error.localizedDescription)
    }

    private func performRestore(_ backup: ModConfigBackup) {
        let selected = backup.items.filter { selectedItemIds.contains($0.id) }
        guard !selected.isEmpty else { return }
        isBusy = true
        let gameDir = vm.gameDir
        // Tous les mods, pas seulement les actifs : le filet pris avant
        // d'écraser doit couvrir les mods **en pause**, où vivent presque
        // toutes les configurations du parc.
        let currentMods = vm.mods
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try ModConfigBackupManager.shared.restoreBackup(
                    gameDir: gameDir,
                    backup: backup,
                    selectedItems: selected,
                    currentMods: currentMods
                )
                let fetched = ModConfigBackupManager.shared.loadBackups()
                DispatchQueue.main.async {
                    self.backups = fetched
                    self.isBusy = false
                    self.vm.alertMessage = self.vm.L(L10n.ModConfigBackups.backupRestored)
                    self.vm.showAlert = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.vm.alertMessage = self.localizedMessage(for: error, genericKey: L10n.ModConfigBackups.restoreFailed)
                    self.vm.showAlert = true
                }
            }
        }
    }

    private func performDelete(_ backup: ModConfigBackup) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try ModConfigBackupManager.shared.deleteBackup(backup)
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
                    self.vm.alertMessage = self.localizedMessage(for: error, genericKey: L10n.ModConfigBackups.deleteFailed)
                    self.vm.showAlert = true
                }
            }
        }
    }
}

// MARK: - Row

private struct ModConfigBackupRow: View {
    @ObservedObject var vm: StarHubTHViewModel
    let backup: ModConfigBackup
    let isExpanded: Bool
    @Binding var selectedItemIds: Set<UUID>
    let onToggleExpand: () -> Void
    let onRestoreSelected: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onToggleExpand) {
                    HStack(spacing: 10) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(backup.formattedDate)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            Text("\(String(format: vm.L(L10n.ModConfigBackups.filesCount), backup.totalFiles)) · \(backup.formattedSize)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(vm.L(L10n.ModConfigBackups.deleteBackup))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .onHover { isHovered = $0 }

            if isExpanded {
                Divider().padding(.leading, 14)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(backup.items) { item in
                        Toggle(isOn: Binding(
                            get: { selectedItemIds.contains(item.id) },
                            set: { isOn in
                                if isOn { selectedItemIds.insert(item.id) } else { selectedItemIds.remove(item.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.modDisplayName)
                                    .font(.system(size: 12, weight: .medium))
                                let subtitle = item.parentFolderName.map {
                                    "\(item.files.joined(separator: ", ")) — \(String(format: vm.L(L10n.ModConfigBackups.partOfGroup), $0))"
                                } ?? item.files.joined(separator: ", ")
                                Text(subtitle)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }

                    HStack {
                        Spacer()
                        Button(vm.L(L10n.ModConfigBackups.restoreBackup)) {
                            onRestoreSelected()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(selectedItemIds.isEmpty)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}
