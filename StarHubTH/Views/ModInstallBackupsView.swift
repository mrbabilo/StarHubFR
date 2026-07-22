import SwiftUI

/// View for managing mod installation backups (complete mod folders).
struct ModInstallBackupsView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var backups: [ModInstallBackup] = []
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false
    @State private var backupToDelete: ModInstallBackup?
    @State private var showRestoreConfirm = false
    @State private var backupToRestore: ModInstallBackup?
    /// Guards against a rapid double-click dispatching two concurrent
    /// restore/delete operations on the same backup.
    @State private var isBusy = false

    private let backupManager = ModInstallBackupManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(vm.L(L10n.ModInstall.manageBackups))
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button {
                    loadBackups()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help(vm.L(L10n.ModInstall.refreshBackups))
            }
            .padding()

            Divider()

            // Content
            if backups.isEmpty {
                emptyState
            } else {
                backupList
            }
        }
        .frame(minWidth: 500, minHeight: 300)
        .onAppear {
            // Opportunistically prune expired backups before showing the
            // list, so what the user sees reflects the retention policy.
            DispatchQueue.global(qos: .utility).async {
                _ = backupManager.cleanupOldBackups()
                DispatchQueue.main.async {
                    loadBackups()
                }
            }
        }
        .alert(vm.L(L10n.ModInstall.operationFailed), isPresented: $showError) {
            Button(vm.L(L10n.Main.ok)) { }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .confirmationDialog(vm.L(L10n.ModInstall.restoreConfirm), isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button(vm.L(L10n.ModInstall.restoreBackup), role: .destructive) {
                if let backup = backupToRestore {
                    performRestore(backup)
                }
            }
            Button(vm.L(L10n.ModInstall.cancel), role: .cancel) { }
        } message: {
            Text(vm.L(L10n.ModInstall.restoreConfirmMessage))
        }
        .confirmationDialog(vm.L(L10n.ModInstall.deleteConfirm), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(vm.L(L10n.ModInstall.deleteBackup), role: .destructive) {
                if let backup = backupToDelete {
                    performDelete(backup)
                }
            }
            Button(vm.L(L10n.ModInstall.cancel), role: .cancel) { }
        } message: {
            Text(vm.L(L10n.ModInstall.deleteConfirmMessage))
        }
    }

    private func reasonText(for reason: BackupReason) -> String {
        switch reason {
        case .beforeInstall: return vm.L(L10n.ModInstall.backupReasonInstall)
        case .beforeUpdate: return vm.L(L10n.ModInstall.backupReasonUpdate)
        case .beforeRestore: return vm.L(L10n.ModInstall.backupReasonRestore)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text(vm.L(L10n.ModInstall.noBackups))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var backupList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(backups) { backup in
                    backupRow(backup)
                    if backup.id != backups.last?.id {
                        Divider()
                    }
                }
            }
            .padding()
        }
    }

    private func backupRow(_ backup: ModInstallBackup) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(backup.modMetadata.name)
                    .font(.system(size: 13, weight: .medium))
                Text("v\(backup.modMetadata.version) • \(backup.modMetadata.author)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(backup.originalFolderName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(backup.formattedDate)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(reasonText(for: backup.reason))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
            }

            HStack(spacing: 8) {
                Button {
                    backupToRestore = backup
                    showRestoreConfirm = true
                } label: {
                    Label(vm.L(L10n.ModInstall.restoreBackup), systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy)

                Button {
                    backupToDelete = backup
                    showDeleteConfirm = true
                } label: {
                    Label(vm.L(L10n.ModInstall.deleteBackup), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy)
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button(vm.L(L10n.ModInstall.restoreBackup)) {
                backupToRestore = backup
                showRestoreConfirm = true
            }
            Divider()
            Button(vm.L(L10n.ModInstall.deleteBackup), role: .destructive) {
                backupToDelete = backup
                showDeleteConfirm = true
            }
        }
        .disabled(isBusy)
    }

    private func loadBackups() {
        backups = backupManager.loadBackups()
    }

    private func performRestore(_ backup: ModInstallBackup) {
        guard !isBusy else { return }
        guard !vm.gameDir.isEmpty else {
            errorMessage = vm.L(L10n.Settings.gameDirNotSet)
            showError = true
            return
        }

        isBusy = true
        let gameDir = vm.gameDir
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try backupManager.restoreBackup(backup, gameDir: gameDir)
                DispatchQueue.main.async {
                    isBusy = false
                    vm.log(vm.L(L10n.ModInstall.backupRestored), level: .info)
                    vm.refresh()
                    loadBackups()
                }
            } catch {
                DispatchQueue.main.async {
                    isBusy = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func performDelete(_ backup: ModInstallBackup) {
        guard !isBusy else { return }
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try backupManager.deleteBackup(backup)
                DispatchQueue.main.async {
                    isBusy = false
                    loadBackups()
                }
            } catch {
                DispatchQueue.main.async {
                    isBusy = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}