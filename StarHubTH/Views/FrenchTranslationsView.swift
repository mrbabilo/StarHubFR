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
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var currentTab: SidebarDestination

    private var store: FrenchTranslationSweepStore { viewModel.translationSweep }

    /// C3-T5 — la session de fusion des lots humains, portée par la vue :
    /// elle ne survit pas au changement d'onglet, comme les autres états de
    /// détail (`MainView` remet ses états à `nil`).
    @State private var mergeStore = TranslationLotMergeStore()
    @State private var showArbitration = false
    /// Section demandée par la légende de l'anneau : ouverte puis atteinte.
    @State private var revealKey: String?
    /// R3 — fixé une fois à l'apparition (« À finir », sauf liste vide et
    /// mesure finie) : la page ne bascule pas sous les yeux.
    @State private var segment: Segment?

    private enum Segment: Hashable { case worklist, nexus }

    /// Les mêmes magasins que le filtre « Trad. FR » de la liste.
    private var worklistState: ModListScoping.TranslationState {
        let model = viewModel
        return .init(coverage: model.frenchCoverageByMod, stale: model.staleTranslationMods,
                     outdatedKeys: model.outdatedKeysByMod)
    }

    /// Une ligne : le mod, son statut, et le `ModItem` vivant pour agir.
    private struct Row: Identifiable {
        let candidate: FrenchTranslationSweep.Candidate
        let mod: ModItem
        let status: FrenchTranslationSweep.Status
        var id: String { candidate.id }
    }

    private var rows: [Row] {
        let model = viewModel
        let byFolder = Dictionary(model.mods.map { ($0.folderName, $0) }, uniquingKeysWith: { first, _ in first })
        return FrenchTranslationSweep.candidates(
            among: model.mods,
            hasInstalledTranslation: { model.tracksTranslation(for: $0) },
            nexusModId: { Int(model.resolvedNexusModId(for: $0)) })
        .compactMap { candidate in
            guard let mod = byFolder[candidate.folderName] else { return nil }
            return Row(candidate: candidate, mod: mod,
                       status: FrenchTranslationSweep.status(
                           entry: store.entry(for: candidate.folderName),
                           installed: model.translation(for: mod) ?? model.declaredTracked(for: mod)))
        }
    }

    var body: some View {
        let all = rows
        let mods = viewModel.mods, state = worklistState
        let work = TranslationWorklist.items(in: mods, state: state)
        let unmeasured = TranslationWorklist.unmeasuredCount(in: mods, pass: viewModel.frenchCoverage)
        let shown = segment ?? (work.isEmpty && unmeasured == 0 ? .nexus : .worklist)
        VStack(alignment: .leading, spacing: 0) {
            header(all, shown: shown, workCount: work.count)
                .padding(AppDesign.Spacing.lg)
            Divider()
            if shown == .worklist {
                BackToTopScrollView(localization) {
                    FrenchTranslationsWorklist(localization: localization, items: work,
                                               untranslated: TranslationWorklist.untranslatedCount(in: mods, state: state),
                                               unmeasured: unmeasured,
                                               open: { folder in openMod(folder) },
                                               showNexus: { segment = .nexus })
                }
            } else {
            ScrollViewReader { proxy in
                BackToTopScrollView(localization) {
                    let groups = self.groups(all)
                    LazyVStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                        if !all.isEmpty {
                            FrenchTranslationsOverview(
                                slices: groups.map { .init(key: $0.key, count: $0.rows.count) },
                                L: localization.L,
                                select: { key in
                                    revealKey = key
                                    withMotion { proxy.scrollTo(key, anchor: .top) }
                                })
                        }
                        ForEach(groups, id: \.key) { group in
                            section(group.key, group.rows, open: group.open)
                        }
                        DismissedTranslationHits(viewModel: viewModel, localization: localization)
                    }
                    .padding(AppDesign.Spacing.lg)
                }
            }
            }
        }
        .onAppear { if segment == nil { segment = shown } }
        .sheet(isPresented: $showArbitration) {
            TranslationArbitrationSheet(store: mergeStore, viewModel: viewModel,
                                        localization: localization,
                                        freshRows: { mod in
                                            await viewModel.translationDiff(for: mod)
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
    private func header(_ all: [Row], shown: Segment, workCount: Int) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            PageHeader(icon: "character.bubble.fill",
                       title: localization.L(L10n.FrTranslations.title)) {
                if shown == .worklist {
                    EmptyView()
                } else if store.isRunning {
                    Button(localization.L(L10n.FrTranslations.cancel)) { store.cancel() }
                        .controlSize(.small)
                } else {
                    // Incrémental par défaut : un parc stable se lit au cache
                    // en secondes ; le passage total vit derrière le glyph.
                    // Un Menu seul ne convient pas : son clic OUVRIT le menu,
                    // dont l'unique item était « tout re-balayer » — le
                    // bouton principal n'avait aucune action propre
                    // (2026-10-05). Et `.primaryAction()` n'existe pas sur
                    // Menu dans ce SDK.
                    HStack(spacing: 4) {
                        Button {
                            store.run(all.map(\.candidate)) { viewModel.log($0) }
                        } label: {
                            Label(localization.L(L10n.FrTranslations.rescan),
                                  systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(all.isEmpty)
                        .help(localization.L(L10n.FrTranslations.rescanHint))
                        Menu {
                            Button(localization.L(L10n.FrTranslations.rescanAll)) {
                                store.run(all.map(\.candidate), forceAll: true) { viewModel.log($0) }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                        .controlSize(.small)
                        .disabled(all.isEmpty)
                        .help(localization.L(L10n.FrTranslations.rescanAll))
                    }
                }
            }
            Text(localization.L(L10n.FrTranslations.subtitle))
                .font(AppDesign.Font.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: AppDesign.Spacing.md) {
                Picker("", selection: Binding(get: { shown }, set: { segment = $0 })) {
                    Text(String(format: localization.L(L10n.FrTranslations.segmentWorklist), workCount))
                        .tag(Segment.worklist)
                    Text(String(format: localization.L(L10n.FrTranslations.segmentNexus), all.count))
                        .tag(Segment.nexus)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer(minLength: 0)
                TranslationLotShuttleView(viewModel: viewModel, localization: localization,
                                          mergeStore: $mergeStore,
                                          onMergeReady: { showArbitration = $0 })
            }
            if shown == .worklist {
                EmptyView()
            } else if store.isRunning {
                HStack(spacing: AppDesign.Spacing.sm) {
                    ProgressView(value: Double(store.done), total: Double(max(store.total, 1)))
                        .frame(maxWidth: 220)
                    Text(String(format: localization.L(L10n.FrTranslations.progress),
                                store.done, store.total, store.currentNames.joined(separator: " · ")))
                        .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            } else if let oldest = store.oldestSearch(among: all.map(\.candidate)) {
                // Un « à jour au » global mentirait dès qu'un passage
                // incrémental ne re-cherche qu'une partie : compter ce que le
                // cache couvre encore.
                let fresh = store.freshCount(among: all.map(\.candidate))
                Text(summary(all) + " · "
                     + String(format: localization.L(L10n.FrTranslations.checkedAt),
                              fresh, all.count,
                              oldest.formatted(date: .abbreviated, time: .shortened)))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            } else {
                Text(String(format: localization.L(L10n.FrTranslations.never), all.count))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
            // R7 — la clé absente a son remède commun ; un quota épuisé ou un
            // arrêt demandé gardent leur constat (ils ne se règlent pas aux
            // Réglages).
            if shown == .nexus, let reason = store.stopReason {
                if reason == .noApiKey {
                    NexusAccessNote(message: stopText(reason), navigation: viewModel.navigationStore,
                                    localization: localization)
                } else {
                    Label(stopText(reason), systemImage: "exclamationmark.triangle.fill")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(reason == .cancelled ? .secondary : AppDesign.Color.warning)
                }
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

    /// Les statuts dans l'ordre de gravité puis d'action : ce qui demande
    /// un geste d'abord, ce qui est réglé ensuite.
    private func groups(_ all: [Row]) -> [(key: String, rows: [Row], open: Bool)] {
        [
            (L10n.FrTranslations.sectionUpdates, all.filter { if case .updateAvailable = $0.status { return true }; return false }, true),
            (L10n.FrTranslations.sectionAvailable, all.filter { if case .available = $0.status { return true }; return false }, true),
            (L10n.FrTranslations.sectionFailed, all.filter { $0.status == .failed }, true),
            (L10n.FrTranslations.sectionUnverified, all.filter { $0.status == .installedUnverified }, false),
            (L10n.FrTranslations.sectionInstalled, all.filter { $0.status == .installed }, false),
            (L10n.FrTranslations.sectionNone, all.filter { $0.status == .nothingFound }, false),
            (L10n.FrTranslations.sectionNotSearched, all.filter { $0.status == .notSearched }, false),
        ]
    }

    @ViewBuilder
    private func section(_ key: String, _ rows: [Row], open: Bool) -> some View {
        if !rows.isEmpty {
            FrenchTranslationSection(title: String(format: localization.L(key), rows.count),
                                     style: FrenchTranslationsOverview.style(for: key),
                                     startsOpen: open, reveal: revealKey == key) {
                ForEach(rows) { row in
                    FrenchTranslationRow(viewModel: viewModel, localization: localization, mod: row.mod,
                                         candidate: row.candidate, status: row.status,
                                         entry: store.entry(for: row.candidate.folderName),
                                         openMod: { openMod(row.mod.folderName) })
                }
            }
            .id(key)
        }
    }

    /// La fiche, onglet Traduction — là où vivent le retrait et le
    /// rattachement. L'intention traverse le changement d'onglet (patron B3-T4).
    private func openMod(_ folderName: String) {
        viewModel.navigationStore.openModDetail(folderName: folderName, door: .frenchTranslations)
    }
}
