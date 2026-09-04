import SwiftUI

/// Les trois confirmations de la vue passent par **un seul** modificateur
/// `.alert` — patron `ModConfigBackupsConfirmation` (`ModConfigBackupsView.swift`) :
/// deux présentateurs sur la même vue ne se présentent pas tous les deux.
private enum MaintenanceConfirmation {
    /// Le cran de purge : combien garder par mod, et ce que la confirmation
    /// doit nommer (entrées condamnées, poids libéré).
    case purge(keepPerMod: Int, doomed: Int, freedBytes: Int64)
    case cleanStale(orphans: Int, keys: Int)
    case removeProtected(session: String, modName: String)
}

/// L'écran « Entretien » (X25) : ce que StarHubFR occupe, et de quoi le rendre
/// sans jamais détruire la seule copie d'un fichier écrit par l'utilisateur.
///
/// Trois états distincts — chargement, « rien à faire », rapport garni — parce
/// que « pas encore mesuré » et « rien à mesurer » ne s'affichent pas pareil.
struct MaintenanceView: View {
    @ObservedObject var vm: StarHubTHViewModel

    @State private var confirmation: MaintenanceConfirmation?

    // MARK: - Corps

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let report = vm.maintenanceReport {
                if report.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        content(report).padding()
                    }
                }
            } else {
                loadingState
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        // Une passe coûte 0,86 s mesurées : au `.onAppear` seulement, et le
        // garde de `buildMaintenanceReport` refuse le chevauchement. Le rapport
        // déjà posé reste affiché pendant la refonte.
        .onAppear { vm.buildMaintenanceReport() }
        // Un seul présentateur pour les trois confirmations — voir
        // `MaintenanceConfirmation`.
        .alert(alertTitle,
               isPresented: Binding(get: { confirmation != nil },
                                    set: { if !$0 { confirmation = nil } }),
               presenting: confirmation) { pending in
            switch pending {
            case .purge(let keep, _, _):
                Button(vm.L(L10n.Maintenance.confirmTrash), role: .destructive) {
                    vm.purgeInstallBackups(keepPerMod: keep)
                }
                Button(vm.L(L10n.Maintenance.cancel), role: .cancel) { }
            case .cleanStale:
                Button(vm.L(L10n.Maintenance.confirmRemove), role: .destructive) {
                    vm.cleanStaleMaintenanceEntries()
                }
                Button(vm.L(L10n.Maintenance.cancel), role: .cancel) { }
            case .removeProtected(let session, _):
                Button(vm.L(L10n.Maintenance.actionRemoveAnyway), role: .destructive) {
                    vm.purgeProtectedBackup(session: session)
                }
                Button(vm.L(L10n.Maintenance.cancel), role: .cancel) { }
            }
        } message: { pending in
            switch pending {
            case .purge(_, let doomed, let freed):
                Text(String(format: vm.L(L10n.Maintenance.purgeMessage),
                            doomed, Self.bytes(freed)))
            case .cleanStale(let orphans, let keys):
                Text(String(format: vm.L(L10n.Maintenance.cleanMessage),
                            orphans, keys))
            case .removeProtected(_, let modName):
                Text(String(format: vm.L(L10n.Maintenance.protectedRemoveMessage),
                            modName))
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text(vm.L(L10n.Maintenance.title))
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
            if vm.isBuildingMaintenanceReport {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(vm.L(L10n.Maintenance.loading))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func content(_ report: MaintenanceInventory.Report) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            summarySection(report)
            purgeSection(report)
            if !report.orphanSessions.isEmpty || !report.stalePreferenceKeys.isEmpty {
                cleanSection(report)
            }
            if report.protectedCount > 0 {
                protectedSection(report)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Le total et sa décomposition — le chiffre que l'utilisateur est venu voir.
    private func summarySection(_ report: MaintenanceInventory.Report) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vm.L(L10n.Maintenance.total))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            Text(Self.bytes(report.totalBytes))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 3) {
                row(vm.L(L10n.Maintenance.installBackups),
                    "\(report.backups.count) · \(Self.bytes(report.backupBytes))")
                row(vm.L(L10n.Maintenance.configBackups),
                    "\(report.configBackupCount) · \(Self.bytes(report.configBackupBytes))")
                if !report.orphanSessions.isEmpty {
                    row(vm.L(L10n.Maintenance.orphanSessions),
                        String(report.orphanSessions.count))
                }
                if !report.stalePreferenceKeys.isEmpty {
                    row(vm.L(L10n.Maintenance.staleKeys),
                        String(report.stalePreferenceKeys.count))
                }
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
    }

    /// Les trois crans. Le gain annoncé vient de `report.freedBytes` — le même
    /// chemin que la purge : un chiffre qui divergerait de ce qui part serait
    /// un mensonge.
    private func purgeSection(_ report: MaintenanceInventory.Report) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([1, 3, 5], id: \.self) { keep in
                let freed = report.freedBytes(keepPerMod: keep)
                Button {
                    let plan = MaintenanceInventory.plan(keepPerMod: keep,
                                                         entries: report.backups,
                                                         protections: report.protections)
                    confirmation = .purge(keepPerMod: keep,
                                           doomed: plan.doomed.count,
                                           freedBytes: plan.freedBytes)
                } label: {
                    Text(String(format: vm.L(L10n.Maintenance.keepPerMod),
                                keep, Self.bytes(freed)))
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .disabled(freed <= 0)
            }
            Text(vm.L(L10n.Maintenance.trashHint))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func cleanSection(_ report: MaintenanceInventory.Report) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                confirmation = .cleanStale(orphans: report.orphanSessions.count,
                                           keys: report.stalePreferenceKeys.count)
            } label: {
                Label(vm.L(L10n.Maintenance.actionClean),
                      systemImage: "paintbrush")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
        }
    }

    /// Les sauvegardes qui ne partent pas, et pourquoi. La raison distingue
    /// « le mod n'est plus installé » (on ne peut que montrer le fichier) de
    /// « la mise à jour l'a emporté » (on peut le remettre).
    private func protectedSection(_ report: MaintenanceInventory.Report) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(format: vm.L(L10n.Maintenance.protectedTitle),
                        report.protectedCount))
                .font(.system(size: 13, weight: .semibold))
            ForEach(protectedRows(report)) { row in
                protectedCard(row)
            }
        }
    }

    private func protectedCard(_ row: ProtectedRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: row.isGone ? "exclamationmark.triangle"
                                             : "arrow.uturn.backward")
                    .foregroundColor(.orange)
                Text(row.modFolder)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(row.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ForEach(row.files, id: \.relativePath) { file in
                HStack(alignment: .firstTextBaseline) {
                    Text(file.relativePath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(vm.L(row.isGone ? L10n.Maintenance.reasonGone
                                         : L10n.Maintenance.reasonMissing))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if row.isGone {
                        Button(vm.L(L10n.Maintenance.actionReveal)) {
                            if let path = vm.maintenanceProtectedFilePath(
                                session: row.session, relativePath: file.relativePath) {
                                vm.revealProtectedBackup(atPath: path)
                            }
                        }
                        .controlSize(.small)
                    } else {
                        Button(vm.L(L10n.Maintenance.actionRecover)) {
                            if let recoverable = vm.maintenanceRecoverableFile(
                                session: row.session, relativePath: file.relativePath) {
                                vm.recoverProtectedFile(recoverable)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
            Button(vm.L(L10n.Maintenance.actionRemoveAnyway)) {
                confirmation = .removeProtected(session: row.session,
                                                modName: row.modFolder)
            }
            .controlSize(.small)
            .foregroundColor(.red)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
        }
    }

    // MARK: - États

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text(vm.L(L10n.Maintenance.loading))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text(vm.L(L10n.Maintenance.nothingToDo))
                .multilineTextAlignment(.center)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Aides

    /// Une ligne par sauvegarde protégée. Identifiée par la session, jamais par
    /// position — deux mods peuvent partager un nom logique.
    private struct ProtectedRow: Identifiable {
        let session: String
        let modFolder: String
        let timestamp: Date
        let files: [MaintenanceInventory.UserFile]
        let isGone: Bool
        var id: String { session }
    }

    private func protectedRows(_ report: MaintenanceInventory.Report) -> [ProtectedRow] {
        report.backups.compactMap { entry in
            guard case .soleCopy(let files)? = report.protections[entry.id],
                  !files.isEmpty else { return nil }
            return ProtectedRow(session: entry.id,
                                modFolder: entry.modFolder,
                                timestamp: entry.timestamp,
                                files: files,
                                isGone: report.missingMods.contains(entry.id))
        }
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private var alertTitle: String {
        switch confirmation {
        case .purge: return vm.L(L10n.Maintenance.purgeTitle)
        case .cleanStale: return vm.L(L10n.Maintenance.cleanTitle)
        case .removeProtected: return vm.L(L10n.Maintenance.protectedRemoveTitle)
        case nil: return ""
        }
    }
}
