import SwiftUI

/// Preview of mods to be installed with conflict resolution and dependency information.
struct InstallPreview: View {
    let zipModInfo: ZipModInfo
    let installer: ModZipInstaller
    @ObservedObject var vm: StarHubTHViewModel
    @Binding var tempDir: URL?
    @Binding var isInstalling: Bool

    let onInstall: ([InstallSelection]) -> Void
    let onCancel: () -> Void

    @State private var selections: [UUID: InstallSelection] = [:]
    @State private var selectAll: Bool = true
    @State private var cachedDependencies: [ModDependencyReport] = []

    /// Status of a single dependency relative to the installed mods + the
    /// current zip pack.
    enum DepStatus {
        case satisfied       // installed and enabled
        case installedDisabled // installed but disabled
        case inPack          // not installed yet but included in this zip
        case missing         // not installed, not in zip
    }

    struct DepEntry: Identifiable {
        let id = UUID()
        let uniqueId: String
        let isRequired: Bool
        let status: DepStatus
        let nexusUrl: String?
    }

    struct ModDependencyReport: Identifiable {
        let id = UUID()
        let modName: String
        let entries: [DepEntry]
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header info
            headerInfo

            // Mods list
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(zipModInfo.detectedMods) { mod in
                        DetectedModRow(
                            mod: mod,
                            selection: selections[mod.id],
                            onSelectionChange: { newSelection in
                                selections[mod.id] = newSelection
                            },
                            existingMods: vm.mods,
                            vm: vm
                        )
                    }
                }
            }

            // Dependencies section
            if !cachedDependencies.isEmpty {
                dependenciesSection
            }

            // Conflicts section
            if !conflicts.isEmpty {
                conflictsSection
            }

            // Actions
            actionButtons
        }
        .onAppear {
            initializeSelections()
            computeDependencies()
        }
    }

    private var headerInfo: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(zipModInfo.zipName)
                    .font(.system(size: 14, weight: .medium))
                HStack(spacing: 16) {
                    Text(String(format: vm.L(L10n.ModInstall.modsInZip), zipModInfo.detectedMods.count))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(zipModInfo.formattedSize)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $selectAll)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: selectAll) { _, newValue in
                    updateAllSelections(selected: newValue)
                }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    /// Classifies each dependency of each detected mod into one of four
    /// statuses (satisfied / installedDisabled / inPack / missing) once on
    /// appear, so it isn't re-scanned on every render.
    private func computeDependencies() {
        let detectedUniqueIds = Set(zipModInfo.detectedMods.map { $0.uniqueId.lowercased() })
        // Build a UniqueID → nexusUrl map from the mods included in this zip
        // (for deps that are also in the pack).
        var packNexusUrls: [String: String] = [:]
        for mod in zipModInfo.detectedMods where !mod.nexusUrl.isEmpty {
            packNexusUrls[mod.uniqueId.lowercased()] = mod.nexusUrl
        }

        cachedDependencies = zipModInfo.detectedMods.compactMap { mod in
            guard !mod.dependencies.isEmpty else { return nil }

            var entries: [DepEntry] = []
            for depDetail in mod.dependencyDetails {
                let depId = depDetail.uniqueId
                let depIdLower = depId.lowercased()

                // Check installed mods.
                if let installed = vm.mods.first(where: { $0.uniqueId.caseInsensitiveCompare(depId) == .orderedSame }) {
                    if installed.isEnabled {
                        entries.append(DepEntry(uniqueId: depId, isRequired: depDetail.isRequired, status: .satisfied, nexusUrl: nil))
                    } else {
                        entries.append(DepEntry(uniqueId: depId, isRequired: depDetail.isRequired, status: .installedDisabled, nexusUrl: nil))
                    }
                } else if detectedUniqueIds.contains(depIdLower) {
                    // Dependency is one of the mods in this zip pack.
                    let url = packNexusUrls[depIdLower]
                    entries.append(DepEntry(uniqueId: depId, isRequired: depDetail.isRequired, status: .inPack, nexusUrl: url))
                } else {
                    // Truly missing — provide a Nexus search link by UniqueID.
                    let searchUrl = "https://www.nexusmods.com/stardewvalley/mods/?terms=\(depId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? depId)"
                    entries.append(DepEntry(uniqueId: depId, isRequired: depDetail.isRequired, status: .missing, nexusUrl: searchUrl))
                }
            }

            guard !entries.isEmpty else { return nil }
            return ModDependencyReport(modName: mod.name, entries: entries)
        }
    }

    @ViewBuilder
    private var dependenciesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vm.L(L10n.ModInstall.dependenciesTitle))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(cachedDependencies) { report in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.modName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)

                        ForEach(report.entries) { entry in
                            DependencyRow(entry: entry, vm: vm)
                        }
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(6)
        }
    }

    private var conflicts: [ModConflict] {
        zipModInfo.conflicts
    }

    @ViewBuilder
    private var conflictsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vm.L(L10n.ModInstall.conflictsTitle))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(zipModInfo.conflicts) { conflict in
                    ConflictRow(
                        conflict: conflict,
                        resolution: conflictResolutionBinding(for: conflict),
                        vm: vm
                    )
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(vm.L(L10n.ModInstall.cancel)) {
                onCancel()
            }
            .buttonStyle(.bordered)
            .disabled(isInstalling)

            Spacer()

            let selectedCount = selections.values.filter { $0.selected }.count
            Text(selectedCount > 0 ? String(format: vm.L(L10n.ModInstall.installSelected), selectedCount) : vm.L(L10n.ModInstall.cannotInstallEmpty))
                .font(.system(size: 12))
                .foregroundColor(selectedCount > 0 ? .primary : .red)

            Button(vm.L(L10n.ModInstall.installSelected)) {
                let selected = selections.values.filter { $0.selected }
                if !selected.isEmpty {
                    onInstall(Array(selected))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCount == 0 || isInstalling)

            if isInstalling {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private func initializeSelections() {
        for mod in zipModInfo.detectedMods {
            let hasConflict = conflicts.contains { $0.folderName == mod.folderName }
            let defaultResolution: ConflictResolution? = hasConflict ? .overwriteWithBackup : nil

            selections[mod.id] = InstallSelection(
                modId: mod.id,
                selected: true,
                conflictResolution: defaultResolution,
                configResolution: nil
            )
        }
    }

    private func updateAllSelections(selected: Bool) {
        for mod in zipModInfo.detectedMods {
            if let existing = selections[mod.id] {
                selections[mod.id] = InstallSelection(
                    modId: existing.modId,
                    selected: selected,
                    conflictResolution: existing.conflictResolution,
                    configResolution: existing.configResolution
                )
            }
        }
    }

    /// Two-way binding between a conflict's resolution and the underlying
    /// selection entry of the mod sharing the same folder name.
    private func conflictResolutionBinding(for conflict: ModConflict) -> Binding<ConflictResolution> {
        Binding(
            get: { [self] in
                if let mod = zipModInfo.detectedMods.first(where: { $0.folderName == conflict.folderName }),
                   let sel = selections[mod.id] {
                    return sel.conflictResolution ?? .overwriteWithBackup
                }
                return .overwriteWithBackup
            },
            set: { [self] newValue in
                guard let mod = zipModInfo.detectedMods.first(where: { $0.folderName == conflict.folderName }) else { return }
                let current = selections[mod.id]
                selections[mod.id] = InstallSelection(
                    modId: mod.id,
                    selected: current?.selected ?? true,
                    conflictResolution: newValue,
                    configResolution: current?.configResolution
                )
            }
        )
    }
}

/// Row showing the status of a single dependency (installed / disabled /
/// in-pack / missing) with optional Nexus link.
struct DependencyRow: View {
    let entry: InstallPreview.DepEntry
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        HStack(spacing: 8) {
            switch entry.status {
            case .satisfied:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(entry.uniqueId)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(vm.L(L10n.ModInstall.depInstalled))
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            case .installedDisabled:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(entry.uniqueId)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                Text(vm.L(L10n.ModInstall.depDisabled))
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            case .inPack:
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)
                Text(entry.uniqueId)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                Text(vm.L(L10n.ModInstall.depInPack))
                    .font(.system(size: 10))
                    .foregroundColor(.blue)
            case .missing:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(entry.uniqueId)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                if entry.isRequired {
                    Text(vm.L(L10n.ModInstall.depRequiredMissing))
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
                if let url = entry.nexusUrl {
                    Spacer()
                    if let nexusUrl = URL(string: url) {
                        Link(destination: nexusUrl) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 10))
                                Text(vm.L(L10n.ModInstall.depDownload))
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if entry.status != .missing {
                Spacer()
            }
            if !entry.isRequired && entry.status != .satisfied {
                Text(vm.L(L10n.ModInstall.depOptional))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Row showing a single conflict with resolution options.
struct ConflictRow: View {
    let conflict: ModConflict
    @Binding var resolution: ConflictResolution
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(conflict.folderName)
                    .font(.system(size: 12, weight: .medium))
            }

            HStack(spacing: 8) {
                Text(String(format: vm.L(L10n.ModInstall.existingVersion), conflict.existingVersion))
                    .font(.system(size: 11))
                Text("→")
                    .foregroundColor(.secondary)
                Text(String(format: vm.L(L10n.ModInstall.newVersion), conflict.newVersion))
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary)

            Picker("", selection: $resolution) {
                Text(vm.L(L10n.ModInstall.backupBeforeOverwrite)).tag(ConflictResolution.overwriteWithBackup)
                Text(vm.L(L10n.ModInstall.renameMod)).tag(ConflictResolution.rename)
                Text(vm.L(L10n.ModInstall.skipMod)).tag(ConflictResolution.skip)
            }
            .pickerStyle(.radioGroup)
        }
        .padding()
        .background(Color.red.opacity(0.05))
        .cornerRadius(6)
    }
}

/// Row for a single detected mod in the install preview.
struct DetectedModRow: View {
    let mod: DetectedMod
    let selection: InstallSelection?
    let onSelectionChange: (InstallSelection) -> Void
    let existingMods: [ModItem]
    @ObservedObject var vm: StarHubTHViewModel

    @State private var showDetails = false

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { selection?.selected ?? false },
                set: { newValue in
                    let newSelection = InstallSelection(
                        modId: mod.id,
                        selected: newValue,
                        conflictResolution: selection?.conflictResolution,
                        configResolution: selection?.configResolution
                    )
                    onSelectionChange(newSelection)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 4) {
                Text(mod.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Text("v\(mod.version)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))

                    Text(mod.author)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if let existing = mod.existingVersion {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(String(format: vm.L(L10n.ModInstall.existingVersion), existing.version))
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }

                if !mod.dependencies.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .foregroundColor(.secondary)
                        Text(String(format: vm.L(L10n.ModInstall.depCount), mod.dependencies.count))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                showDetails = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(6)
        .popover(isPresented: $showDetails) {
            VStack(alignment: .leading, spacing: 8) {
                Text(vm.L(L10n.ModInstall.modInfo))
                    .font(.headline)
                infoRow(vm.L(L10n.ModInstall.labelName), mod.name)
                infoRow(vm.L(L10n.ModInstall.labelVersion), mod.version)
                infoRow(vm.L(L10n.ModInstall.labelAuthor), mod.author)
                infoRow(vm.L(L10n.ModInstall.labelUniqueId), mod.uniqueId)
                if !mod.dependencies.isEmpty {
                    Text(vm.L(L10n.ModInstall.dependenciesTitle))
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.top, 4)
                    ForEach(mod.dependencies, id: \.self) { dep in
                        let depMod = existingMods.first { $0.uniqueId.caseInsensitiveCompare(dep) == .orderedSame }
                        HStack {
                            if depMod != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                            Text(dep)
                                .font(.system(size: 11))
                        }
                    }
                }
            }
            .padding()
            .frame(width: 250)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11))
            Spacer()
        }
    }
}