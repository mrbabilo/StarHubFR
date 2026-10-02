import SwiftUI

// MARK: - Quarantine View

/// Shows the last folder-repair report and provides actions to open the
/// `_Trash_` quarantine folder or empty it to the Mac Trash (with
/// confirmation). Quarantined items are never deleted directly — "empty"
/// moves them to the Mac Trash where they can be recovered until the user
/// empties the Trash themselves.
struct QuarantineView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State private var showEmptyConfirmation = false

    var body: some View {
        let quarantineDir = quarantinePath

        VStack(spacing: 0) {
            // En-tête commun des pages (audit UX 2026-10-02) : ce que fait la
            // quarantaine, et ses trois gestes. ~624 pt de libellés FR pour
            // 500 à la fenêtre minimale : icônes seules (infobulles) quand ça
            // ne tient pas.
            PageHeader(icon: "tray.full.fill", title: localization.L(L10n.Quarantine.title),
                       subtitle: localization.L(L10n.Quarantine.subtitleShort)) {
                AdaptiveLabels { HStack(spacing: AppDesign.Spacing.sm) { actions(quarantineDir) } }
            }
            .padding(.horizontal, AppDesign.Spacing.xl)
            .padding(.vertical, AppDesign.Spacing.md)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
                        // En entier, jamais tronqué par l'en-tête : c'est la
                        // promesse que rien n'est supprimé directement.
                        Label(localization.L(L10n.Quarantine.subtitle), systemImage: "info.circle.fill")
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let result = vm.maintenanceStore.quarantineMessage {
                            Label(result.text, systemImage: result.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                                .font(AppDesign.Font.body)
                                .foregroundColor(result.isError ? AppDesign.Color.error : AppDesign.Color.success)
                                .padding(AppDesign.Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background((result.isError ? AppDesign.Color.error : AppDesign.Color.success).opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: AppDesign.Radius.lg, style: .continuous))
                        }
                        // Dernier rapport de réparation, ou l'état vide : atteignable
                        // depuis que l'entrée est permanente (B2-T3) — aucune analyse
                        // n'a encore tourné (jeu non configuré, rapport jamais produit).
                        if let report = vm.maintenanceStore.lastRepairReport {
                            RepairReportSummary(report: report, localization: localization) { section in
                                withMotion(.snappy) { proxy.scrollTo(section, anchor: .top) }
                            }
                            RepairReportCard(report: report, localization: localization, gameDir: vm.gameDir)
                        } else {
                            VStack(spacing: AppDesign.Spacing.md) {
                                IconTile(icon: "tray", tint: AppDesign.Color.success, size: 64)
                                Text(localization.L(L10n.Quarantine.noQuarantine))
                                    .font(AppDesign.Font.body)
                                    .foregroundColor(AppDesign.Color.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, AppDesign.Spacing.xl)
                        }
                    }
                    .padding(AppDesign.Spacing.xl)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppDesign.Color.windowBg)
        .confirmationDialog(
            localization.L(L10n.Quarantine.emptyConfirmTitle),
            isPresented: $showEmptyConfirmation,
            titleVisibility: .visible
        ) {
            Button(localization.L(L10n.Quarantine.emptyTrash), role: .destructive) {
                emptyToMacTrash()
            }
            Button(localization.L(L10n.Main.ok), role: .cancel) {}
        } message: {
            Text(localization.L(L10n.Quarantine.emptyConfirmMessage))
        }
    }

    /// Les trois gestes de la page, dans l'en-tête.
    @ViewBuilder
    private func actions(_ quarantineDir: String?) -> some View {
        Button(action: { vm.refresh() }) {
            Label(localization.L(L10n.Quarantine.rescan), systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(localization.L(L10n.Quarantine.rescan))
        // `refresh()` est le « rafraîchissement manuel » établi — celui des
        // installations et de l'accueil — et c'est le seul chemin qui relance
        // la réparation dont cette page publie le rapport. Inactif pendant le
        // scan : un second clic lancerait une double traversée du parc.
        .disabled(vm.scanStore.scanProgress != nil)
        if vm.scanStore.scanProgress != nil {
            ProgressView().controlSize(.small)
        }

        Button(action: openQuarantineFolder) {
            Label(localization.L(L10n.Quarantine.openFolder), systemImage: "folder.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(localization.L(L10n.Quarantine.openFolder))
        .disabled(quarantineDir == nil)

        Button(role: .destructive, action: { showEmptyConfirmation = true }) {
            Label(localization.L(L10n.Quarantine.emptyTrash), systemImage: "trash.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(localization.L(L10n.Quarantine.emptyTrash))
        .disabled(quarantineDir == nil)
    }

    // MARK: - Duplicate rows (composite identity)

    /// Row wrapper giving each `ModFolderRepairer.Duplicate` a stable,
    /// collision-free `ForEach` identity. `Duplicate` is a plain value type:
    /// two entries can legitimately carry the same
    /// uniqueId/enabledFolder/disabledFolder triple (a pack shipping two
    /// `manifest.json` under the same UniqueID inside the same disabled
    /// folder), so content alone is not a safe id. Rank alone is unsafe too
    /// (the `id: \.offset` leak documented in CLAUDE.md). Combining both
    /// keeps the id unique without losing content-based identity across
    /// rescans.
    // MARK: - Actions

    /// Resolves the most recent `_Trash_` folder in the game dir (if any).
    /// The reported path is validated to be inside the game directory and
    /// start with `_Trash_` before being returned, preventing a crafted
    /// or stale report from escaping the expected containment.
    private var quarantinePath: String? {
        guard !vm.gameDir.isEmpty else { return nil }
        let gameDirURL = URL(fileURLWithPath: vm.gameDir).resolvingSymlinksInPath()
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: gameDirURL.path) else { return nil }
        // Prefer the path from the last report, fall back to the newest
        // _Trash_* folder on disk.
        if let reported = vm.maintenanceStore.lastRepairReport?.trashPath,
           FileManager.default.fileExists(atPath: reported) {
            let reportedURL = URL(fileURLWithPath: reported).resolvingSymlinksInPath()
            let lastComponent = reportedURL.lastPathComponent
            // Containment: must be inside gameDir and have the quarantine
            // naming prefix so a stale/malformed report can't point
            // outside the expected tree.
            if lastComponent.hasPrefix("_Trash_"),
               reportedURL.path.hasPrefix(gameDirURL.path + "/") {
                return reported
            }
        }
        let trashFolders = entries
            .filter { $0.hasPrefix("_Trash_") }
            .sorted()
        guard let newest = trashFolders.last else { return nil }
        return (vm.gameDir as NSString).appendingPathComponent(newest)
    }

    private func openQuarantineFolder() {
        guard let path = quarantinePath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Moves all `_Trash_*` folders in the game dir to the Mac Trash using
    /// the standard NSWorkspace API. On success, clears the repair report so
    /// the sidebar badge disappears. The result is published on the VM (not
    /// @State on this struct) because the recycle completion fires
    /// asynchronously after this View struct may have been recreated.
    private func emptyToMacTrash() {
        let vm = self.vm
        guard !vm.gameDir.isEmpty else { return }
        let fm = FileManager.default
        let gameDirURL = URL(fileURLWithPath: vm.gameDir).resolvingSymlinksInPath()
        guard let entries = try? fm.contentsOfDirectory(atPath: gameDirURL.path) else { return }
        let trashURLs = entries
            .filter { $0.hasPrefix("_Trash_") }
            .map { gameDirURL.appendingPathComponent($0) }

        guard !trashURLs.isEmpty else {
            vm.maintenanceStore.setQuarantineMessage(.init(text: localization.L(L10n.Quarantine.noQuarantine), isError: false))
            return
        }

        NSWorkspace.shared.recycle(trashURLs, completionHandler: { _, error in
            DispatchQueue.main.async {
                if let error = error {
                    vm.maintenanceStore.setQuarantineMessage(.init(text: error.localizedDescription, isError: true))
                } else {
                    vm.maintenanceStore.setQuarantineMessage(.init(text: localization.L(L10n.Quarantine.emptied), isError: false))
                    vm.maintenanceStore.setRepairReport(nil)
                }
                // X114 — le badge lit le disque : le recount suit le vidage,
                // succès comme échec partiel.
                vm.refreshTrash()
            }
        })
    }
}
