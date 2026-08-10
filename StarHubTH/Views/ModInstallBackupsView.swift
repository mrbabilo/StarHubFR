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
    /// restore/delete operations on the same backup. Carries the id of the
    /// backup currently in flight so the matching row can show a spinner.
    @State private var busyBackupId: UUID? = nil

    private let backupManager = ModInstallBackupManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.L(L10n.ModInstall.manageBackups))
                        .font(.system(size: 18, weight: .semibold))
                    Text("\(backups.count) \(vm.L(L10n.ModInstall.manageBackups).lowercased())")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    loadBackups()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .help(vm.L(L10n.ModInstall.refreshBackups))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // Retention policy info banner
            retentionInfoBanner

            Divider()

            // Content
            if backups.isEmpty {
                emptyState
            } else {
                backupList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            Text(vm.L(L10n.ModInstall.noBackups))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Text(vm.L(L10n.ModInstall.noBackupsHint))
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var backupList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(backups) { backup in
                    backupRow(backup)
                }
            }
            .padding(20)
        }
    }

    private func backupRow(_ backup: ModInstallBackup) -> some View {
        HStack(spacing: 12) {
            // Reason icon badge
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: reasonIcon(for: backup.reason))
                    .font(.system(size: 13))
                    .foregroundColor(.pink)
            }

            VStack(alignment: .leading, spacing: 3) {
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

            VStack(alignment: .trailing, spacing: 3) {
                Text(backup.formattedDate)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(reasonText(for: backup.reason))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
            }

            // Action buttons: while this row's operation is in flight, the
            // buttons collapse to a single spinner (and every other row is
            // disabled via the `.disabled(busyBackupId != nil)` below).
            if busyBackupId == backup.id {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 56, alignment: .center)
                    .help(vm.L(L10n.ModInstall.manageBackups))
            } else {
                HStack(spacing: 6) {
                    Button {
                        backupToRestore = backup
                        showRestoreConfirm = true
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(busyBackupId != nil)
                    .help(vm.L(L10n.ModInstall.restoreBackup))

                    Button {
                        backupToDelete = backup
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(busyBackupId != nil)
                    .help(vm.L(L10n.ModInstall.deleteBackup))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
        .opacity(busyBackupId == backup.id ? 0.6 : 1.0)
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
        .disabled(busyBackupId != nil)
    }

    private func reasonIcon(for reason: BackupReason) -> String {
        switch reason {
        case .beforeInstall: return "plus.circle"
        case .beforeUpdate: return "arrow.up.circle"
        case .beforeRestore: return "arrow.uturn.backward.circle"
        }
    }

    private var retentionInfoBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(.accentColor.opacity(0.7))
            Text(vm.L(L10n.ModInstall.retentionPolicy))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func loadBackups() {
        backups = backupManager.loadBackups()
    }

    private func performRestore(_ backup: ModInstallBackup) {
        guard busyBackupId == nil else { return }
        guard !vm.gameDir.isEmpty else {
            errorMessage = vm.L(L10n.Settings.gameDirNotSet)
            showError = true
            return
        }

        busyBackupId = backup.id
        let gameDir = vm.gameDir
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try backupManager.restoreBackup(backup, gameDir: gameDir)
                DispatchQueue.main.async {
                    busyBackupId = nil
                    vm.log(vm.L(L10n.ModInstall.backupRestored), level: .info)
                    vm.refresh()
                    loadBackups()
                }
            } catch {
                DispatchQueue.main.async {
                    busyBackupId = nil
                    errorMessage = vm.installErrorMessage(error)
                    showError = true
                }
            }
        }
    }

    private func performDelete(_ backup: ModInstallBackup) {
        guard busyBackupId == nil else { return }
        busyBackupId = backup.id
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try backupManager.deleteBackup(backup)
                DispatchQueue.main.async {
                    busyBackupId = nil
                    loadBackups()
                }
            } catch {
                DispatchQueue.main.async {
                    busyBackupId = nil
                    errorMessage = vm.installErrorMessage(error)
                    showError = true
                }
            }
        }
    }
}