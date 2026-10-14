import SwiftUI

/// I-T21 lot 2 — la liste découpée par « Regrouper par » : sections, bandeaux,
/// pagination par places (`ModGroupPages`), et la carte de grille commune aux
/// deux rendus. Fichier à part : `ModListView.swift` est verrouillé par le
/// cliquet de taille.
extension ModListView {
    /// Le nom long de `vm` (§1.4) pour tout ce fichier.
    var viewModel: StarHubTHViewModel { vm }

    struct GroupedLayout {
        /// Vide hors regroupement : la liste garde son rendu d'avant.
        let pages: [[ModListPageSection]]
        /// L'ordre de navigation et de sélection : sans les sections repliées.
        let navigable: [ModItem]

        func shown(page: Int) -> Int? {
            guard pages.indices.contains(page - 1) else { return nil }
            return pages[page - 1].reduce(0) { $0 + $1.mods.count }
        }
    }

    func groupedLayout(_ display: [ModItem]) -> GroupedLayout {
        let grouping = ModGrouping(rawValue: groupingRaw) ?? .none
        guard grouping != .none, !display.isEmpty else { return GroupedLayout(pages: [], navigable: display) }
        let sections = ModGroupPages.sections(display: display, mode: grouping, state: viewModel.groups.state,
                                              category: { mod in viewModel.category(for: mod).map {
                                                  (id: $0.id, name: $0.localizedName(localization.L)) } })
        return GroupedLayout(pages: ModGroupPages.pages(sections, pageSize: pageSize),
                             navigable: sections.filter { !$0.collapsed }.flatMap(\.mods))
    }

    @ViewBuilder
    func groupedPage(_ page: [ModListPageSection]) -> some View {
        ForEach(page, id: \.section.key) { part in
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                ModListSectionHeader(page: part, viewModel: viewModel, localization: localization, listState: listState) {
                    toggleCollapse(part.section)
                }
                if !part.mods.isEmpty {
                    switch listLayout {
                    case .list:
                        ModRowsStack(mods: part.mods, viewModel: viewModel, localization: localization, listState: listState)
                    case .grid:
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: AppDesign.Grid.minCardWidth),
                                                    spacing: AppDesign.Grid.gutter)],
                                  spacing: AppDesign.Grid.gutter) {
                            ForEach(part.mods) { mod in modGridCard(mod) }
                        }
                    }
                }
            }
        }
    }

    func toggleCollapse(_ section: ModListSectionModel) {
        if case .group(let id) = section.key {
            viewModel.groups.update { $0.setCollapsed(group: id, !section.collapsed) }
        } else {
            viewModel.groups.update { $0.setCollapsed(category: section.key.collapseKey, !section.collapsed) }
        }
    }

    /// « Regrouper par » : aucun, mes groupes, catégorie.
    var groupingPicker: some View {
        Picker(localization.L(L10n.Mods.grouping), selection: $groupingRaw) {
            Text(localization.L(L10n.Mods.groupingNone)).tag(ModGrouping.none.rawValue)
            Text(localization.L(L10n.Mods.groupingGroups)).tag(ModGrouping.groups.rawValue)
            Text(localization.L(L10n.Mods.groupingCategory)).tag(ModGrouping.category.rawValue)
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help(localization.L(L10n.Mods.grouping))
        .onChange(of: groupingRaw) { _, _ in listState.filters.page = 1 }
    }

    /// Une carte de la grille — la même dans le rendu groupé et l'autre.
    @ViewBuilder
    func modGridCard(_ mod: ModItem) -> some View {
        let values = ModGridCardValues.card(
            mod: mod,
            versionPrefix: localization.L(L10n.Mods.versionPrefix),
            pictureURL: gridPictureURL(for: mod))
        let active = values.state == .active
        let age = filters.sort == .lastNexusUpdate
            ? viewModel.nexusLastUpdated(for: mod).map { NexusUpdateAge.line(for: $0) } : nil
        ModCard(title: values.title,
                subtitle: age.map { "\(values.subtitle) · \($0)" } ?? values.subtitle,
                thumbnailURL: values.thumbnailURL,
                // L'**état**, pas « installé » :
                // les deux se posent (P6).
                installedLabel: localization.L(active
                    ? L10n.Mods.cardActive
                    : L10n.Mods.cardPaused),
                badgeTint: active
                    ? AppDesign.Color.installed
                    : AppDesign.Color.paused,
                badgeSystemImage: active
                    ? "checkmark.circle.fill"
                    : "pause.circle.fill",
                // Assignée, Nexus ou dominante
                // d'un pack (`category(for:)`).
                category: viewModel.category(for: mod),
                neutralBadge: values.neutralBadge,
                endorsements: viewModel.nexusEndorsementCount(for: mod),
                endorsedByMe: ModEndorsement.isEndorsed(mod, viewModel: viewModel),
                usesDefaultArtwork: true,
                attributes: gridAttributes(for: mod),
                pageState: viewModel.nexusPageState(for: mod)?.state,
                L: localization.L,
                action: { viewModel.navigationStore.setViewingModDetail(mod) })
        .contextMenu { endorseMenuItem(mod) }
    }
}
