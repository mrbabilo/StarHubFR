import SwiftUI

/// C5-T1 — « Traductions FR » : les traductions françaises disponibles sur
/// Nexus pour tous les mods installés (en pause compris), et les mises à jour
/// de celles déjà posées. Remplace l'entrée du hub thaï.
///
/// La page ne cherche rien d'office : un bouton lance la recherche
/// (`FrenchTranslationSweepStore`, qui vit sur le ViewModel et survit au
/// changement d'onglet). Le statut de chaque mod se **dérive** à l'affichage
/// (`FrenchTranslationSweep.status`) : poser une traduction d'ici la fait
/// passer dans « Posées » sans nouvelle recherche.
///
/// Les gestes sont ceux de la fiche (A3-T3) : `installTranslation` dépose dans
/// le mod de premier niveau, dossier physique compris — un mod en pause vit
/// dans `Mods/.X`.
struct FrenchTranslationsView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var currentTab: SidebarDestination

    private var store: FrenchTranslationSweepStore { vm.translationSweep }

    /// C3-T5 — la session de fusion des lots humains, portée par la vue :
    /// elle ne survit pas au changement d'onglet, comme les autres états de
    /// détail (`MainView` remet ses états à `nil`).
    @State private var mergeStore = TranslationLotMergeStore()
    @State private var showArbitration = false

    /// Une ligne : le mod, son statut, et le `ModItem` vivant pour agir.
    private struct Row: Identifiable {
        let candidate: FrenchTranslationSweep.Candidate
        let mod: ModItem
        let status: FrenchTranslationSweep.Status
        var id: String { candidate.id }
    }

    private var rows: [Row] {
        let byFolder = Dictionary(vm.mods.map { ($0.folderName, $0) }, uniquingKeysWith: { first, _ in first })
        return FrenchTranslationSweep.candidates(
            among: vm.mods,
            hasInstalledTranslation: { vm.translation(for: $0) != nil },
            nexusModId: { Int(vm.resolvedNexusModId(for: $0)) })
        .compactMap { candidate in
            guard let mod = byFolder[candidate.folderName] else { return nil }
            return Row(candidate: candidate, mod: mod,
                       status: FrenchTranslationSweep.status(entry: store.entries[candidate.folderName],
                                                             installed: vm.translation(for: mod)))
        }
    }

    var body: some View {
        let all = rows
        VStack(alignment: .leading, spacing: 0) {
            header(all)
                .padding(AppDesign.Spacing.lg)
            Divider()
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                TranslationLotShuttleView(viewModel: vm, localization: localization,
                                          mergeStore: $mergeStore,
                                          onMergeReady: { showArbitration = $0 })
                    .padding(.horizontal, AppDesign.Spacing.lg)
                    .padding(.top, AppDesign.Spacing.sm)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                    sections(all)
                }
                .padding(AppDesign.Spacing.lg)
            }
        }
        .sheet(isPresented: $showArbitration) {
            TranslationArbitrationSheet(store: mergeStore, viewModel: vm,
                                        localization: localization,
                                        freshRows: { mod in
                                            await vm.translationDiff(for: mod)
                                        },
                                        onWrote: { _ in },
                                        onClose: {
                                            showArbitration = false
                                            mergeStore.reset()
                                        })
        }
    }

    // MARK: - En-tête

    @ViewBuilder
    private func header(_ all: [Row]) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            HStack {
                Text(localization.L(L10n.FrTranslations.title))
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                if store.isRunning {
                    Button(localization.L(L10n.FrTranslations.cancel)) { store.cancel() }
                        .controlSize(.small)
                } else {
                    Button {
                        store.run(all.map(\.candidate)) { vm.log($0) }
                    } label: {
                        Label(localization.L(L10n.FrTranslations.search), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(all.isEmpty)
                }
            }
            Text(localization.L(L10n.FrTranslations.subtitle))
                .font(.system(size: 12)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.isRunning {
                HStack(spacing: AppDesign.Spacing.sm) {
                    ProgressView(value: Double(store.done), total: Double(max(store.total, 1)))
                        .frame(maxWidth: 220)
                    Text(String(format: localization.L(L10n.FrTranslations.progress),
                                store.done, store.total, store.currentName ?? ""))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            } else if let oldest = store.oldestSearch(among: all.map(\.candidate)) {
                Text(summary(all) + " · "
                     + String(format: localization.L(L10n.FrTranslations.checkedAt),
                              oldest.formatted(date: .abbreviated, time: .shortened)))
                    .font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                Text(String(format: localization.L(L10n.FrTranslations.never), all.count))
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            if let reason = store.stopReason {
                Label(stopText(reason), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(reason == .cancelled ? .secondary : .orange)
            }
        }
    }

    /// « N cherchés, M sans résultat » : un zéro doit se voir comme un zéro,
    /// pas comme une page vide.
    private func summary(_ all: [Row]) -> String {
        let available = all.filter { if case .available = $0.status { return true }; return false }.count
        let none = all.filter { $0.status == .nothingFound }.count
        return String(format: localization.L(L10n.FrTranslations.summary), all.count, available, none)
    }

    private func stopText(_ reason: FrenchTranslationSweepStore.StopReason) -> String {
        switch reason {
        case .noApiKey:    return localization.L(L10n.FrTranslations.stopNoKey)
        case .rateLimited: return localization.L(L10n.FrTranslations.stopRateLimit)
        case .cancelled:   return localization.L(L10n.FrTranslations.stopCancelled)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func sections(_ all: [Row]) -> some View {
        let updates = all.filter { if case .updateAvailable = $0.status { return true }; return false }
        let available = all.filter { if case .available = $0.status { return true }; return false }
        let installed = all.filter { $0.status == .installed }
        let unverified = all.filter { $0.status == .installedUnverified }
        let failed = all.filter { $0.status == .failed }
        let none = all.filter { $0.status == .nothingFound }
        let notSearched = all.filter { $0.status == .notSearched }
        section(L10n.FrTranslations.sectionUpdates, updates, open: true)
        section(L10n.FrTranslations.sectionAvailable, available, open: true)
        section(L10n.FrTranslations.sectionFailed, failed, open: true)
        section(L10n.FrTranslations.sectionUnverified, unverified, open: false)
        section(L10n.FrTranslations.sectionInstalled, installed, open: false)
        section(L10n.FrTranslations.sectionNone, none, open: false)
        section(L10n.FrTranslations.sectionNotSearched, notSearched, open: false)
    }

    @ViewBuilder
    private func section(_ key: String, _ rows: [Row], open: Bool) -> some View {
        if !rows.isEmpty {
            FrenchTranslationSection(title: String(format: localization.L(key), rows.count),
                                     startsOpen: open) {
                ForEach(rows) { row in
                    FrenchTranslationRow(vm: vm, localization: localization, mod: row.mod,
                                         candidate: row.candidate, status: row.status,
                                         entry: store.entries[row.candidate.folderName],
                                         openMod: { openMod(row.mod) })
                }
            }
        }
    }

    /// La fiche, onglet Traduction — là où vivent le retrait et le
    /// rattachement. L'intention traverse le changement d'onglet (patron B3-T4).
    private func openMod(_ mod: ModItem) {
        vm.navigationStore.pendingModDetailFocus = mod.folderName
        vm.navigationStore.pendingDetailTab = .translation
        currentTab = .mods
    }
}

/// Un groupe repliable ; son état vit ici, pas dans la page, pour que chaque
/// section garde le sien.
private struct FrenchTranslationSection<Content: View>: View {
    let title: String
    let startsOpen: Bool
    @ViewBuilder let content: () -> Content
    @State private var isOpen: Bool?

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { isOpen ?? startsOpen }, set: { isOpen = $0 })) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) { content() }
                .padding(.top, AppDesign.Spacing.xs)
        } label: {
            Text(title).font(.system(size: 13, weight: .semibold))
        }
    }
}

/// Un mod et ce que Nexus propose pour lui.
private struct FrenchTranslationRow: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem
    let candidate: FrenchTranslationSweep.Candidate
    let status: FrenchTranslationSweep.Status
    let entry: FrenchTranslationSweep.Entry?
    let openMod: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: AppDesign.Spacing.sm) {
                Text(candidate.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if !candidate.isActive {
                    Text(localization.L(L10n.FrTranslations.paused))
                        .font(.system(size: 10)).foregroundColor(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15)).cornerRadius(4)
                }
                if vm.translationHub.isBusy(mod.folderName) { ProgressView().controlSize(.small) }
                Spacer()
                Button(localization.L(L10n.FrTranslations.openMod), action: openMod)
                    .buttonStyle(.borderless).controlSize(.small).pointingHandCursor()
            }
            switch status {
            case .available(let hits):
                // Le plus sûr d'abord : confirmée, liée, puis par nom.
                ForEach(hits.sorted { rank($0) < rank($1) }) { hitLine($0, action: L10n.FrTranslations.install) }
            case .updateAvailable(let newer):
                hitLine(newer, action: L10n.FrTranslations.update)
            case .installed, .installedUnverified, .failed, .nothingFound, .notSearched:
                EmptyView()
            }
        }
        .padding(AppDesign.Spacing.sm)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    private func confidence(_ hit: NexusModSearch.Hit) -> FrenchTranslationSweep.Confidence {
        entry?.confidence(of: hit, hostName: candidate.name) ?? .nameOnly
    }

    private func rank(_ hit: NexusModSearch.Hit) -> Int {
        switch confidence(hit) {
        case .confirmed: return 0
        case .linkedOnly: return 1
        case .nameOnly: return 2
        }
    }

    /// La marque d'un résultat qui demande à être vérifié ; rien quand le lien
    /// et le titre concordent.
    @ViewBuilder private func caution(_ hit: NexusModSearch.Hit) -> some View {
        switch confidence(hit) {
        case .confirmed:
            EmptyView()
        case .linkedOnly:
            Text(localization.L(L10n.FrTranslations.linkedOnly))
                .font(.system(size: 10)).foregroundColor(.orange)
                .help(localization.L(L10n.FrTranslations.linkedOnlyHelp))
        case .nameOnly:
            Text(localization.L(L10n.FrTranslations.byName))
                .font(.system(size: 10)).foregroundColor(.orange)
                .help(localization.L(L10n.FrTranslations.byNameHelp))
        }
    }

    private func hitLine(_ hit: NexusModSearch.Hit, action: String) -> some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(hit.name).font(.system(size: 11, weight: .medium))
                        .lineLimit(1).truncationMode(.middle)
                    caution(hit)
                }
                Text(String(format: localization.L(L10n.Mods.translationFromNexus), hit.uploader,
                            hit.updatedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"))
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            Button(localization.L(action)) { vm.installTranslation(hit, into: mod) }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(vm.translationHub.isBusy(mod.folderName))
                .pointingHandCursor()
            Button {
                if let url = URL(string: "https://www.nexusmods.com/stardewvalley/mods/\(hit.modId)?tab=files") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(localization.L(L10n.Mods.translationOpenNexus), systemImage: "arrow.up.right.square")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered).controlSize(.small).pointingHandCursor()
        }
        .padding(.leading, AppDesign.Spacing.md)
    }
}
