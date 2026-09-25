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
    /// X103-B — purge de la corbeille : toute entière, ou une entrée nommée.
    /// Le nom d'événement et l'entrée sont portés par la confirmation (pas
    /// d'état de vue en plus).
    case purgeTrashAll(events: Int)
    case purgeTrashEntry(event: String, entry: String)
    /// X103-C — les archives Nexus conservées : toutes (`nil`), ou une seule.
    case purgeArchives(only: NexusArchiveEntry?)
}

/// L'écran « Entretien » (X25) : ce que StarHubFR occupe, et de quoi le rendre
/// sans jamais détruire la seule copie d'un fichier écrit par l'utilisateur.
///
/// Trois états distincts — chargement, « rien à faire », rapport garni — parce
/// que « pas encore mesuré » et « rien à mesurer » ne s'affichent pas pareil.
struct MaintenanceView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    @State private var confirmation: MaintenanceConfirmation?
    /// X103-C — l'écran doit dire ce que la fonction *ferait* quand elle est
    /// éteinte, plutôt que de rester vide sans explication.
    @AppStorage(UDKey.keepNexusArchives) private var keepNexusArchives: Bool = false

    // MARK: - Corps

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let report = vm.maintenanceReport {
                // La corbeille (X103-B) se montre même sur un entretien sans
                // objet : des sauvegardes à rien à dire et des mods en
                // corbeille sont deux vérités indépendantes.
                if !report.isEmpty || !vm.trashEvents.isEmpty || keepNexusArchives
                    || !vm.nexusArchives.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if report.isEmpty {
                                nothingToDoInline
                            } else {
                                content(report)
                            }
                            trashSection
                            archivesSection
                        }
                        .padding()
                    }
                } else {
                    emptyState
                }
            } else {
                loadingState
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        // Passe de 0,86 s : au `.onAppear` seulement, sans chevauchement
        // (garde de `buildMaintenanceReport`) ; l'ancien rapport reste affiché.
        .onAppear {
            vm.buildMaintenanceReport()
            vm.refreshTrash()
            vm.refreshNexusArchives()
        }
        // Un seul présentateur pour les trois confirmations — voir
        // `MaintenanceConfirmation`.
        .alert(alertTitle,
               isPresented: Binding(get: { confirmation != nil },
                                    set: { if !$0 { confirmation = nil } }),
               presenting: confirmation) { pending in
            switch pending {
            case .purge(let keep, _, _):
                Button(localization.L(L10n.Maintenance.confirmTrash), role: .destructive) {
                    vm.purgeInstallBackups(keepPerMod: keep)
                }
                Button(localization.L(L10n.Maintenance.cancel), role: .cancel) { }
            case .cleanStale:
                Button(localization.L(L10n.Maintenance.confirmRemove), role: .destructive) {
                    vm.cleanStaleMaintenanceEntries()
                }
                Button(localization.L(L10n.Maintenance.cancel), role: .cancel) { }
            case .removeProtected(let session, _):
                Button(localization.L(L10n.Maintenance.actionRemoveAnyway), role: .destructive) {
                    vm.purgeProtectedBackup(session: session)
                }
                Button(localization.L(L10n.Maintenance.cancel), role: .cancel) { }
            case .purgeTrashAll:
                Button(localization.L(L10n.Maintenance.confirmRemove), role: .destructive) {
                    vm.purgeAllTrash()
                }
                Button(localization.L(L10n.Maintenance.cancel), role: .cancel) { }
            case .purgeTrashEntry(let event, let entry):
                Button(localization.L(L10n.Maintenance.confirmRemove), role: .destructive) {
                    vm.purgeTrashEntry(event: event, entry: entry)
                }
                Button(localization.L(L10n.Maintenance.cancel), role: .cancel) { }
            case .purgeArchives(let only):
                Button(localization.L(L10n.Maintenance.confirmRemove), role: .destructive) {
                    if let only { vm.deleteNexusArchive(only) } else { vm.purgeNexusArchives() }
                }
                Button(localization.L(L10n.Maintenance.cancel), role: .cancel) { }
            }
        } message: { pending in
            switch pending {
            case .purge(_, let doomed, let freed):
                Text(String(format: localization.L(L10n.Maintenance.purgeMessage),
                            doomed, Self.bytes(freed)))
            case .cleanStale(let orphans, let keys):
                Text(String(format: localization.L(L10n.Maintenance.cleanMessage),
                            orphans, keys))
            case .removeProtected(_, let modName):
                Text(String(format: localization.L(L10n.Maintenance.protectedRemoveMessage),
                            modName))
            case .purgeTrashAll(let events):
                Text(String(format: localization.L(L10n.Maintenance.trashPurgeAllMessage), events))
            case .purgeTrashEntry(_, let entry):
                Text(String(format: localization.L(L10n.Maintenance.trashPurgeOneMessage), entry))
            case .purgeArchives(let only):
                Text(only.map { String(format: localization.L(L10n.Maintenance.archivesDeleteConfirm), $0.modName,
                                       $0.version) } ?? localization.L(L10n.Maintenance.archivesPurgeConfirm))
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text(localization.L(L10n.Maintenance.title))
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
            if vm.isBuildingMaintenanceReport {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(localization.L(L10n.Maintenance.loading))
                        .font(AppDesign.Font.caption)
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

    /// Le « rien à faire » de l'entretien, en version encastrée — la
    /// corbeille peut avoir des choses à dire juste en dessous.
    private var nothingToDoInline: some View {
        VStack(spacing: AppDesign.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 34))
                .foregroundColor(.secondary.opacity(0.5))
            Text(localization.L(L10n.Maintenance.nothingToDo))
                .multilineTextAlignment(.center)
                .font(AppDesign.Font.rowTitle)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppDesign.Spacing.xl)
    }

    private var trashSection: some View {
        MaintenanceTrashSection(
            viewModel: vm, localization: localization,
            onPurgeAll: { confirmation = .purgeTrashAll(events: $0) },
            onPurgeEntry: { confirmation = .purgeTrashEntry(event: $0, entry: $1) })
    }

    /// X103-C — les archives Nexus conservées : ce qu'elles pèsent, et de quoi
    /// réinstaller un mod supprimé sans réseau.
    ///
    /// La section se montre **aussi quand elle est vide**, et dit alors deux
    /// choses différentes selon que la fonction est allumée ou non. Une
    /// fonction éteinte par défaut qui n'expliquerait nulle part ce qu'elle
    /// fait ne serait jamais découverte.
    @ViewBuilder
    private var archivesSection: some View {
        if keepNexusArchives || !vm.nexusArchives.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(localization.L(L10n.Maintenance.archivesTitle))
                        .font(AppDesign.Font.body(.semibold))
                    Spacer()
                    if !vm.nexusArchives.isEmpty {
                        Text(String(format: localization.L(L10n.Maintenance.archivesCount),
                                    vm.nexusArchives.count,
                                    Self.bytes(vm.nexusArchives.reduce(0) { $0 + $1.byteSize })))
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary)
                        Button(localization.L(L10n.Maintenance.archivesPurge), role: .destructive) {
                            confirmation = .purgeArchives(only: nil)
                        }
                        .controlSize(.small)
                        .foregroundColor(AppDesign.Color.error)
                    }
                }

                if vm.nexusArchives.isEmpty {
                    Text(localization.L(keepNexusArchives
                              ? L10n.Maintenance.archivesEmptyOn
                              : L10n.Maintenance.archivesEmptyOff))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(vm.nexusArchives) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.modName)
                                    .font(AppDesign.Font.caption)
                                Text("\(entry.version) · \(Self.bytes(entry.byteSize))")
                                    .font(AppDesign.Font.monoIconXS)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(localization.L(L10n.Maintenance.archivesReinstall)) {
                                vm.reinstallFromArchive(entry)
                            }
                            .controlSize(.small)
                            Button(localization.L(L10n.Maintenance.archivesDelete), role: .destructive) {
                                confirmation = .purgeArchives(only: entry)
                            }
                            .controlSize(.small)
                            .foregroundColor(AppDesign.Color.error)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(AppDesignCore.Radius.md)
                    }
                }
            }
        }
    }

    /// Le total et sa décomposition — le chiffre que l'utilisateur est venu voir.
    private func summarySection(_ report: MaintenanceInventory.Report) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(localization.L(L10n.Maintenance.total))
                .font(AppDesign.Font.body(.semibold))
                .foregroundColor(.secondary)
            Text(Self.bytes(report.totalBytes))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 3) {
                row(localization.L(L10n.Maintenance.installBackups),
                    "\(report.backups.count) · \(Self.bytes(report.backupBytes))")
                row(localization.L(L10n.Maintenance.configBackups),
                    "\(report.configBackupCount) · \(Self.bytes(report.configBackupBytes))")
                if !report.orphanSessions.isEmpty {
                    row(localization.L(L10n.Maintenance.orphanSessions),
                        String(report.orphanSessions.count))
                }
                if !report.stalePreferenceKeys.isEmpty {
                    row(localization.L(L10n.Maintenance.staleKeys),
                        String(report.stalePreferenceKeys.count))
                }
            }
            .font(AppDesign.Font.caption)
            .foregroundColor(.secondary)
        }
    }

    /// Les trois crans. Le gain annoncé vient de `report.freedBytes` — le même
    /// chemin que la purge : un chiffre qui divergerait de ce qui part serait
    /// un mensonge.
    private func purgeSection(_ report: MaintenanceInventory.Report) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
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
                    Text(String(format: localization.L(L10n.Maintenance.keepPerMod),
                                keep, Self.bytes(freed)))
                        .font(AppDesign.Font.body(.medium))
                }
                .buttonStyle(.borderedProminent)
                .disabled(freed <= 0)
            }
            Text(localization.L(L10n.Maintenance.trashHint))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func cleanSection(_ report: MaintenanceInventory.Report) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Button {
                confirmation = .cleanStale(orphans: report.orphanSessions.count,
                                           keys: report.stalePreferenceKeys.count)
            } label: {
                Label(localization.L(L10n.Maintenance.actionClean),
                      systemImage: "paintbrush")
                    .font(AppDesign.Font.body(.medium))
            }
            .buttonStyle(.bordered)
        }
    }

    /// Les sauvegardes qui ne partent pas, et pourquoi. La raison distingue
    /// « le mod n'est plus installé » (on ne peut que montrer le fichier) de
    /// « la mise à jour l'a emporté » (on peut le remettre).
    private func protectedSection(_ report: MaintenanceInventory.Report) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(format: localization.L(L10n.Maintenance.protectedTitle),
                        report.protectedCount))
                .font(AppDesign.Font.body(.semibold))
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
                    .foregroundColor(AppDesign.Color.warning)
                Text(row.modFolder)
                    .font(AppDesign.Font.body(.medium))
                Spacer()
                Text(row.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ForEach(row.files, id: \.relativePath) { file in
                HStack(alignment: .firstTextBaseline) {
                    Text(file.relativePath)
                        .font(AppDesign.Font.monoCaption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(localization.L(row.isGone ? L10n.Maintenance.reasonGone
                                         : L10n.Maintenance.reasonMissing))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if row.isGone {
                        Button(localization.L(L10n.Maintenance.actionReveal)) {
                            if let path = vm.maintenanceProtectedFilePath(
                                session: row.session, relativePath: file.relativePath) {
                                vm.revealProtectedBackup(atPath: path)
                            }
                        }
                        .controlSize(.small)
                    } else {
                        // I-T8 — la remise vit dans « Sauvegardes des mods »,
                        // segment Fichiers récupérables : aperçu compris.
                        Button(localization.L(L10n.Maintenance.actionOpenRecovery)) {
                            vm.navigationStore.backupsSegment = .files
                            vm.requestTab(.backups)
                        }
                        .controlSize(.small)
                    }
                }
            }
            Button(localization.L(L10n.Maintenance.actionRemoveAnyway), role: .destructive) {
                confirmation = .removeProtected(session: row.session,
                                                modName: row.modFolder)
            }
            .controlSize(.small)
            .foregroundColor(AppDesign.Color.error)
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
        VStack(spacing: AppDesign.Spacing.lg) {
            Spacer()
            ProgressView()
            Text(localization.L(L10n.Maintenance.loading))
                .font(AppDesign.Font.rowTitle)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: AppDesign.Spacing.lg) {
            Spacer()
            Image(systemName: "sparkles")
                .font(AppDesign.Font.emptyScopeGlyph)
                .foregroundColor(.secondary.opacity(0.5))
            Text(localization.L(L10n.Maintenance.nothingToDo))
                .multilineTextAlignment(.center)
                .font(AppDesign.Font.rowTitle)
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
        case .purge: return localization.L(L10n.Maintenance.purgeTitle)
        case .cleanStale: return localization.L(L10n.Maintenance.cleanTitle)
        case .removeProtected: return localization.L(L10n.Maintenance.protectedRemoveTitle)
        case .purgeTrashAll, .purgeTrashEntry:
            return localization.L(L10n.Maintenance.trashSectionTitle)
        case .purgeArchives: return localization.L(L10n.Maintenance.archivesTitle)
        case nil: return ""
        }
    }
}
