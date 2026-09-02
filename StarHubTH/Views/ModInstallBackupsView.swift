import SwiftUI

/// Les trois confirmations de la vue passent par **un seul** modificateur
/// `.alert`, porté par cette valeur — patron `SaveEditorConfirmation`
/// (`SavesView.swift`) : deux présentateurs sur la même vue ne se
/// présentent pas tous les deux (mesuré le 2026-09-02, dans les deux sens).
/// Le compte rendu de restauration n'y figure plus : c'est désormais un
/// panneau sous la liste (`restoreReport`), pas une alerte — une alerte ne
/// peut pas porter un tableau.
private enum ModInstallBackupsConfirmation {
    case error(String)
    case restore(ModInstallBackup)
    case delete(ModInstallBackup)
}

/// View for managing mod installation backups (complete mod folders).
struct ModInstallBackupsView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var backups: [ModInstallBackup] = []
    @State private var showRecoverable = false
    @State private var confirmation: ModInstallBackupsConfirmation?
    /// Le compte rendu de la dernière restauration — ce qui a été écrit, où,
    /// et ce qu'il est advenu de la version remplacée. La vue ne fait que le
    /// rendre : tout y est calculé par `ModInstallBackupManager` (B4-T2).
    /// Rendu en panneau sous la liste (T9 H-T6), pas dans une alerte.
    @State private var restoreReport: ModInstallRestoreReport?
    /// Guards against a rapid double-click dispatching two concurrent
    /// restore/delete operations on the same backup. Carries the id of the
    /// backup currently in flight so the matching row can show a spinner.
    @State private var busyBackupId: UUID? = nil
    /// Recherche, tri et dépliage : ce que la page doit à un parc où l'on
    /// mesure 1 494 sauvegardes pour 145 mods. La liste plate d'avant ne
    /// permettait pas d'en retrouver une.
    @State private var search = ""
    @State private var sort: BackupBrowser.Sort = .mostRecent
    @State private var expandedGroups: Set<String> = []

    private let backupManager = ModInstallBackupManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.L(L10n.ModInstall.manageBackups))
                        .font(.system(size: 18, weight: .semibold))
                    // Clé dédiée : mettre en minuscules le titre « Gérer les
                    // sauvegardes » donnait « 12 gérer les sauvegardes ».
                    Text(String(format: vm.L(L10n.ModInstall.backupsModsCount),
                                Int64(groups.count), Int64(backups.count)))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                // Ce que les sauvegardes savent rendre **sans** restaurer un
                // mod entier : une traduction, des réglages. C'est leur usage
                // le plus fin, et il n'avait pas de porte d'entrée.
                Button(vm.L(L10n.Recovery.title)) { showRecoverable = true }
                    .buttonStyle(.bordered)
                    .pointingHandCursor()
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

            searchAndSortBar

            Divider()

            // Retention policy info banner
            retentionInfoBanner

            Divider()

            // Content
            if backups.isEmpty {
                emptyState
            } else if groups.isEmpty {
                noMatchState
            } else {
                backupList
            }

            // Le compte rendu de la dernière restauration : un panneau fixe
            // sous la liste, pas une alerte — sept champs ne tiennent pas
            // dans un paragraphe (T9 H-T6).
            if let report = restoreReport {
                Divider()
                restoreReportPanel(report)
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
        .sheet(isPresented: $showRecoverable) {
            RecoverableFilesView(vm: vm, isPresented: $showRecoverable)
        }
        // Un seul présentateur pour les trois confirmations restantes — voir
        // `ModInstallBackupsConfirmation`. `presenting:` porte la valeur ;
        // les actions lisent `pending`, jamais `confirmation` (déjà remis à
        // `nil` au moment où l'action s'exécute, après la fermeture).
        .alert(confirmationTitle,
               isPresented: Binding(get: { confirmation != nil },
                                    set: { if !$0 { confirmation = nil } }),
               presenting: confirmation) { pending in
            switch pending {
            case .error:
                Button(vm.L(L10n.Main.ok)) { }
            case .restore(let backup):
                Button(vm.L(L10n.ModInstall.restoreBackup), role: .destructive) {
                    performRestore(backup)
                }
                Button(vm.L(L10n.ModInstall.cancel), role: .cancel) { }
            case .delete(let backup):
                Button(vm.L(L10n.ModInstall.deleteBackup), role: .destructive) {
                    performDelete(backup)
                }
                Button(vm.L(L10n.ModInstall.cancel), role: .cancel) { }
            }
        } message: { pending in
            switch pending {
            case .error(let message): Text(message)
            case .restore: Text(vm.L(L10n.ModInstall.restoreConfirmMessage))
            case .delete: Text(vm.L(L10n.ModInstall.deleteConfirmMessage))
            }
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .error: return vm.L(L10n.ModInstall.operationFailed)
        case .restore: return vm.L(L10n.ModInstall.restoreConfirm)
        case .delete: return vm.L(L10n.ModInstall.deleteConfirm)
        case nil: return ""
        }
    }

    /// Les sept champs de `ModInstallRestoreReport` en lignes étiquetées.
    /// `landedEnabled` porte son propre badge (`SeverityBadge`) : un mod qui
    /// atterrit en pause n'est pas chargé par SMAPI, et rien d'autre à
    /// l'écran ne le dit.
    private func restoreReportPanel(_ report: ModInstallRestoreReport) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            HStack {
                Text(vm.L(L10n.ModInstall.restoreReportTitle))
                    .font(AppDesign.Font.headline)
                Spacer()
                Button {
                    restoreReport = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppDesign.Font.caption)
                        .foregroundColor(AppDesign.Color.secondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            StatColumn(label: vm.L(L10n.ModInstall.labelName), value: report.modName)
            StatColumn(label: vm.L(L10n.ModInstall.labelVersion), value: report.version)
            StatColumn(label: vm.L(L10n.ModInstall.labelFolder), value: report.displayPath)
            StatColumn(label: vm.L(L10n.ModInstall.labelFilesWritten), value: "\(report.fileCount)")
            SeverityBadge(severity: report.landedEnabled ? .info : .warning,
                          label: vm.L(report.landedEnabled ? L10n.ModInstall.landedActiveBadge
                                                            : L10n.ModInstall.landedPausedBadge))
            if !report.replacedVersions.isEmpty {
                StatColumn(label: vm.L(L10n.ModInstall.labelKeptVersions),
                           value: report.replacedVersions.joined(separator: ", "))
            }
            Button(vm.L(L10n.ModInstall.revealInFinder)) {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [URL(fileURLWithPath: report.destinationPath)])
            }
            .buttonStyle(.bordered)
            .pointingHandCursor()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppDesign.Spacing.lg)
        .background(AppDesign.Color.controlBg)
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

    /// Les groupes affichés, recalculés à chaque frappe. Le coût est un tri
    /// sur quelques milliers d'entrées — négligeable devant la lecture disque
    /// qui les a chargées.
    private var groups: [BackupBrowser.ModGroup] {
        BackupBrowser.groups(from: backups, search: search, sort: sort)
    }

    private var searchAndSortBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField(vm.L(L10n.ModInstall.backupsSearch), text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor)))

            Picker(vm.L(L10n.ModInstall.backupsSort), selection: $sort) {
                Text(vm.L(L10n.ModInstall.sortRecent)).tag(BackupBrowser.Sort.mostRecent)
                Text(vm.L(L10n.ModInstall.sortNameAsc)).tag(BackupBrowser.Sort.nameAscending)
                Text(vm.L(L10n.ModInstall.sortNameDesc)).tag(BackupBrowser.Sort.nameDescending)
                Text(vm.L(L10n.ModInstall.sortCount)).tag(BackupBrowser.Sort.count)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .font(.system(size: 12))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var noMatchState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26))
                .foregroundColor(.secondary.opacity(0.6))
            Text(String(format: vm.L(L10n.ModInstall.backupsNoMatch), search))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var backupList: some View {
        // Calculés **une fois** par passe de rendu : lire la propriété dans
        // chaque carte referait le regroupement complet à chaque ligne, soit
        // 145 balayages de 1 494 sauvegardes pour un seul affichage.
        let shown = groups
        // Une recherche qui ne laisse qu'un mod le déplie d'office :
        // chercher, c'est déjà avoir choisi. Sans recherche, non — sinon
        // celui qui n'a qu'un mod se retrouve avec un chevron inerte.
        let autoExpand = !search.trimmingCharacters(in: .whitespaces).isEmpty && shown.count == 1
        return ScrollView {
            // Paresseuse : tout déplier ferait construire des milliers de
            // lignes d'un coup sur un parc réel.
            LazyVStack(spacing: 8) {
                ForEach(shown) { group in
                    modGroupCard(group, autoExpand: autoExpand)
                }
            }
            .padding(20)
        }
    }

    /// Un mod, replié par défaut.
    private func modGroupCard(_ group: BackupBrowser.ModGroup,
                              autoExpand: Bool) -> some View {
        let isExpanded = expandedGroups.contains(group.id) || autoExpand
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if expandedGroups.contains(group.id) {
                    expandedGroups.remove(group.id)
                } else {
                    expandedGroups.insert(group.id)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    ZStack {
                        Circle().fill(Color.pink.opacity(0.12)).frame(width: 30, height: 30)
                        Image(systemName: "shippingbox")
                            .font(.system(size: 12))
                            .foregroundColor(.pink)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.displayName)
                            .font(.system(size: 13, weight: .medium))
                        Text(group.folderName)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(group.backups.count == 1
                             ? vm.L(L10n.ModInstall.backupsGroupSingle)
                             : String(format: vm.L(L10n.ModInstall.backupsGroupSummary),
                                      Int64(group.backups.count), Int64(group.versions.count)))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(group.backups.first?.formattedDate ?? "")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(group.versions) { version in
                        // L'intitulé de version ne s'affiche que s'il y en a
                        // plusieurs : sur ce parc, la moitié des mods n'a
                        // qu'une sauvegarde, et le rappeler serait du bruit.
                        if group.versions.count > 1 {
                            Text("v\(version.version)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                        ForEach(version.backups) { backup in
                            backupRow(backup)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
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
                        confirmation = .restore(backup)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(busyBackupId != nil)
                    .help(vm.L(L10n.ModInstall.restoreBackup))

                    Button {
                        confirmation = .delete(backup)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // Pas de cadre à elle : la ligne vit désormais **dans** la carte de
        // son mod, et un encadré dans un encadré donnait une boîte par
        // sauvegarde à l'intérieur de la boîte du mod.
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.035))
        )
        .opacity(busyBackupId == backup.id ? 0.6 : 1.0)
        .contextMenu {
            Button(vm.L(L10n.ModInstall.restoreBackup)) {
                confirmation = .restore(backup)
            }
            Divider()
            Button(vm.L(L10n.ModInstall.deleteBackup), role: .destructive) {
                confirmation = .delete(backup)
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

    /// Met le compte rendu en phrases, pour la ligne de journal. Le panneau
    /// affiché sous la liste (`restoreReportPanel`) rend les mêmes sept
    /// champs en lignes étiquetées ; cette fonction ne sert plus qu'au log
    /// (elle a servi au message de l'alerte avant T9 H-T6).
    private func restoreReportMessage(_ report: ModInstallRestoreReport) -> String {
        var lines = [
            String(format: vm.L(L10n.ModInstall.restoreReportWritten),
                   report.modName, report.version, report.displayPath),
            String(format: vm.L(L10n.ModInstall.restoreReportFiles), Int64(report.fileCount)),
            vm.L(report.landedEnabled ? L10n.ModInstall.restoreReportActive
                                      : L10n.ModInstall.restoreReportPaused)
        ]
        if !report.replacedVersions.isEmpty {
            let key = report.replacedVersions.count == 1
                ? L10n.ModInstall.restoreReportReplaced
                : L10n.ModInstall.restoreReportReplacedMany
            lines.append(String(format: vm.L(key),
                                report.replacedVersions.joined(separator: ", ")))
        }
        return lines.joined(separator: "\n")
    }

    private func performRestore(_ backup: ModInstallBackup) {
        guard busyBackupId == nil else { return }
        guard !vm.gameDir.isEmpty else {
            // Ce garde s'exécute dans le même battement que la fermeture de
            // l'alerte qui a déclenché `performRestore` (le bouton « Restaurer »)
            // — `confirmation` vient d'être remis à `nil` par le binding.
            // Différer d'un tick évite d'écrire la nouvelle valeur dans la
            // même transaction que cette remise à zéro (patron des autres
            // sites d'erreur de ce fichier, tous en `DispatchQueue.main.async`).
            DispatchQueue.main.async {
                confirmation = .error(vm.L(L10n.Settings.gameDirNotSet))
            }
            return
        }

        busyBackupId = backup.id
        let gameDir = vm.gameDir
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let report = try backupManager.restoreBackup(backup, gameDir: gameDir)
                DispatchQueue.main.async {
                    busyBackupId = nil
                    vm.log(restoreReportMessage(report), level: .info)
                    restoreReport = report
                    // Restaurer, c'est poser une version connue sur le
                    // disque : la même chose qu'une installation, et le
                    // même ancrage. Sans lui, l'ancre reste sur la version
                    // remplacée — `afterDiskChange` refuse de la faire
                    // descendre, tenant une régression pour une mise à jour
                    // inachevée — et smapi.io continue de recevoir la
                    // version d'avant : le retour arrière que l'utilisateur
                    // vient de faire lui serait annoncé « à jour ».
                    vm.anchorInstalledMods(installedFolderPaths: [report.destinationPath])
                    vm.refresh()
                    loadBackups()
                }
            } catch {
                DispatchQueue.main.async {
                    busyBackupId = nil
                    confirmation = .error(vm.installErrorMessage(error))
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
                    confirmation = .error(vm.installErrorMessage(error))
                }
            }
        }
    }
}