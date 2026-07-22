import SwiftUI

struct ModConfigBackupsView: View {
    @ObservedObject var vm: StarHubTHViewModel

    @State private var backups: [ModConfigBackup] = []
    @State private var expandedBackupId: UUID?
    @State private var selectedItemIds: Set<UUID> = []
    @State private var isBusy = false

    @State private var backupToRestore: ModConfigBackup?
    @State private var backupToDelete: ModConfigBackup?
    @State private var cleanupMessage: String?

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
        .alert(vm.L(L10n.ModConfigBackups.restoreWarning), isPresented: Binding(
            get: { backupToRestore != nil },
            set: { if !$0 { backupToRestore = nil } }
        )) {
            Button(vm.L(L10n.ModConfigBackups.restoreBackup), role: .destructive) {
                if let backup = backupToRestore { performRestore(backup) }
                backupToRestore = nil
            }
            Button(vm.L(L10n.ModConfigBackups.cancel), role: .cancel) { backupToRestore = nil }
        } message: {
            Text(vm.L(L10n.ModConfigBackups.restoreWarningCreateBackup))
        }
        .alert(vm.L(L10n.ModConfigBackups.deleteConfirm), isPresented: Binding(
            get: { backupToDelete != nil },
            set: { if !$0 { backupToDelete = nil } }
        )) {
            Button(vm.L(L10n.ModConfigBackups.deleteBackup), role: .destructive) {
                if let backup = backupToDelete { performDelete(backup) }
                backupToDelete = nil
            }
            Button(vm.L(L10n.ModConfigBackups.cancel), role: .cancel) { backupToDelete = nil }
        }
        .alert(vm.L(L10n.ModConfigBackups.title), isPresented: Binding(
            get: { cleanupMessage != nil },
            set: { if !$0 { cleanupMessage = nil } }
        )) {
            Button(vm.L(L10n.Main.ok)) { cleanupMessage = nil }
        } message: {
            Text(cleanupMessage ?? "")
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
                        onRestoreSelected: { backupToRestore = backup },
                        onDelete: { backupToDelete = backup }
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
                    if deletedCount > 0 {
                        self.cleanupMessage = String(format: self.vm.L(L10n.ModConfigBackups.cleanupComplete), deletedCount)
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
        let currentMods = vm.enabledMods
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
            try? ModConfigBackupManager.shared.deleteBackup(backup)
            let fetched = ModConfigBackupManager.shared.loadBackups()
            DispatchQueue.main.async {
                self.backups = fetched
                if self.expandedBackupId == backup.id {
                    self.expandedBackupId = nil
                    self.selectedItemIds = []
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
