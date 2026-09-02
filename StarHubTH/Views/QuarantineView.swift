import SwiftUI

// MARK: - Quarantine View

/// Shows the last folder-repair report and provides actions to open the
/// `_Trash_` quarantine folder or empty it to the Mac Trash (with
/// confirmation). Quarantined items are never deleted directly — "empty"
/// moves them to the Mac Trash where they can be recovered until the user
/// empties the Trash themselves.
struct QuarantineView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var showEmptyConfirmation = false

    var body: some View {
        let quarantineDir = quarantinePath

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(vm.L(L10n.Quarantine.title))
                        .font(.system(size: 20, weight: .bold))
                    Text(vm.L(L10n.Quarantine.subtitle))
                        .font(.system(size: 13))
                        .foregroundColor(AppDesign.Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Last repair report (or empty state when none yet).
                if let report = vm.lastRepairReport {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(vm.L(L10n.Quarantine.lastRepair))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppDesign.Color.primary)

                        if report.quarantined.isEmpty && report.duplicates.isEmpty {
                            Text(vm.L(L10n.Quarantine.noQuarantine))
                                .font(.system(size: 13))
                                .foregroundColor(AppDesign.Color.secondary)
                        } else {
                            Label(
                                String(format: vm.L(L10n.Quarantine.itemsQuarantined), Int64(report.quarantined.count)),
                                systemImage: "tray.and.arrow.down.fill"
                            )
                            .font(.system(size: 13))
                            // Constat, pas panne : les éléments listés ici sont déjà
                            // déplacés en lieu sûr. `.purple` distinguait visuellement
                            // ce bloc du bloc doublons (`.orange`) qui, lui, réclame une
                            // action ; `secondary` garde cette distinction sans réutiliser
                            // `warning` (= `.orange`, cf. AppDesignUI) qui ferait « jurer »
                            // les deux blocs en un seul signal.
                            .foregroundColor(AppDesign.Color.secondary)

                            // Identité par la valeur seule : `relativePath` est un chemin
                            // disque réel, unique par construction dans un même rapport
                            // (repairFolder + sweepJunkInsideMods ne peuvent pas produire
                            // deux Item pour le même fichier physique — cf. rapport de
                            // tâche). `id: \.offset` ferait fuiter l'@State d'une ligne
                            // vers une autre au prochain scan (piège CLAUDE.md §SwiftUI).
                            ForEach(Array(report.quarantined.prefix(20).enumerated()), id: \.element.relativePath) { _, item in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "archivebox.fill")
                                        // Pas de `.opacity(0.7)` supplémentaire ici :
                                        // `secondary` est déjà une couleur hiérarchique
                                        // atténuée (~0.5 alpha) — la multiplier aurait
                                        // rendu ce glyphe de 10pt quasi invisible.
                                        .foregroundColor(AppDesign.Color.secondary)
                                        .font(.system(size: 10))
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.relativePath)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(AppDesign.Color.primary)
                                        Text(item.reason)
                                            .font(.system(size: 11))
                                            .foregroundColor(AppDesign.Color.secondary)
                                    }
                                }
                            }
                            if report.quarantined.count > 20 {
                                Text(String(format: vm.L(L10n.Quarantine.andNMore), Int64(report.quarantined.count - 20)))
                                    .font(.system(size: 11))
                                    .foregroundColor(AppDesign.Color.secondary)
                                    .italic()
                            }
                        }

                        if !report.duplicates.isEmpty {
                            Label(
                                String(format: vm.L(L10n.Quarantine.duplicatesFound), Int64(report.duplicates.count)),
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.system(size: 13))
                            // Vrai avertissement, à la différence du bloc quarantine
                            // ci-dessus : un doublon d'UniqueID n'est pas auto-résolu,
                            // il attend une décision de l'utilisateur.
                            .foregroundColor(AppDesign.Color.warning)

                            // `Duplicate` n'est pas garanti unique par la valeur : un
                            // pack livrant deux manifest.json sous le même UniqueID et
                            // le même dossier désactivé produit deux `Duplicate`
                            // identiques (uniqueId + enabledFolder + disabledFolder).
                            // Contrairement à `quarantined` (chemin disque réel, donc
                            // unique), la valeur seule collisionnerait ici — d'où le
                            // rang ajouté au contenu (`DuplicateRow`), jamais le rang
                            // seul (id: \.offset fuiterait l'@State au prochain scan).
                            ForEach(duplicateRows(from: report.duplicates)) { row in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "doc.on.doc.fill")
                                        .foregroundColor(AppDesign.Color.warning.opacity(0.7))
                                        .font(.system(size: 10))
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.duplicate.uniqueId)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(AppDesign.Color.primary)
                                        Text("\(row.duplicate.enabledFolder)  ⇄  \(row.duplicate.disabledFolder)")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppDesign.Color.secondary)
                                    }
                                }
                            }
                            if report.duplicates.count > 20 {
                                Text(String(format: vm.L(L10n.Quarantine.andNMore), Int64(report.duplicates.count - 20)))
                                    .font(.system(size: 11))
                                    .foregroundColor(AppDesign.Color.secondary)
                                    .italic()
                            }
                        }
                    }
                    .padding(20)
                    .background(AppDesign.Color.primary.opacity(0.04))
                    .cornerRadius(12)
                } else {
                    // Atteignable depuis que l'entrée est permanente (B2-T3) :
                    // aucune analyse n'a encore tourné (jeu non configuré, ou
                    // rapport jamais produit). Même message que le rapport
                    // vide, plutôt qu'un blanc entre le sous-titre et les
                    // boutons.
                    Text(vm.L(L10n.Quarantine.noQuarantine))
                        .font(.system(size: 13))
                        .foregroundColor(AppDesign.Color.secondary)
                }

                // Actions
                HStack(spacing: 12) {
                    Button(action: { vm.refresh() }) {
                        Label(vm.L(L10n.Quarantine.rescan), systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    // `refresh()` est le « rafraîchissement manuel » établi —
                    // celui des installations et de l'accueil — et c'est le seul
                    // chemin qui relance la réparation dont cette page publie
                    // le rapport. Inactif pendant le scan : un second clic
                    // lancerait une double traversée du parc.
                    .disabled(vm.scanProgress != nil)
                    if vm.scanProgress != nil {
                        ProgressView().controlSize(.small)
                    }

                    Button(action: openQuarantineFolder) {
                        Label(vm.L(L10n.Quarantine.openFolder), systemImage: "folder.fill")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppDesign.Color.info)
                    .disabled(quarantineDir == nil)

                    Button(role: .destructive, action: { showEmptyConfirmation = true }) {
                        Label(vm.L(L10n.Quarantine.emptyTrash), systemImage: "trash.fill")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .disabled(quarantineDir == nil)
                }

                if let result = vm.quarantineActionMessage {
                    Label(result.text, systemImage: result.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(result.isError ? AppDesign.Color.error : AppDesign.Color.success)
                        .padding(12)
                        .background((result.isError ? AppDesign.Color.error : AppDesign.Color.success).opacity(0.08))
                        .cornerRadius(8)
                }

                Spacer(minLength: 20)
            }
            .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppDesign.Color.windowBg)
        .confirmationDialog(
            vm.L(L10n.Quarantine.emptyConfirmTitle),
            isPresented: $showEmptyConfirmation,
            titleVisibility: .visible
        ) {
            Button(vm.L(L10n.Quarantine.emptyTrash), role: .destructive) {
                emptyToMacTrash()
            }
            Button(vm.L(L10n.Main.ok), role: .cancel) {}
        } message: {
            Text(vm.L(L10n.Quarantine.emptyConfirmMessage))
        }
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
    private struct DuplicateRow: Identifiable {
        let id: String
        let duplicate: ModFolderRepairer.Duplicate
    }

    private func duplicateRows(from duplicates: [ModFolderRepairer.Duplicate]) -> [DuplicateRow] {
        Array(duplicates.prefix(20).enumerated()).map { offset, dup in
            DuplicateRow(id: "\(offset)-\(dup.uniqueId)-\(dup.enabledFolder)-\(dup.disabledFolder)", duplicate: dup)
        }
    }

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
        if let reported = vm.lastRepairReport?.trashPath,
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
            vm.quarantineActionMessage = .init(text: vm.L(L10n.Quarantine.noQuarantine), isError: false)
            return
        }

        NSWorkspace.shared.recycle(trashURLs, completionHandler: { _, error in
            DispatchQueue.main.async {
                if let error = error {
                    vm.quarantineActionMessage = .init(text: error.localizedDescription, isError: true)
                } else {
                    vm.quarantineActionMessage = .init(text: vm.L(L10n.Quarantine.emptied), isError: false)
                    vm.lastRepairReport = nil
                }
            }
        })
    }
}
