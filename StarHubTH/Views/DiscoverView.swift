import SwiftUI

/// L'onglet « Découvrir » : tendances, récents, sélection FR, recherche —
/// et le croisement permanent avec le parc installé (spec §7).
///
/// La fiche vit en **sheet interne** : les états globaux de MainView sont
/// remis à nil au changement d'onglet, et cette vue ne doit ni les vider ni
/// en dépendre (spec §7.1).
struct DiscoverView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @AppStorage("discoveryHideInstalled") private var hideInstalled = false
    @State private var searchText = ""
    @State private var detailRow: StarHubTHViewModel.DiscoveryRow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchField
                if let error = vm.lastDiscoveryError { errorBanner(error) }
                Toggle(vm.L(L10n.Discovery.hideInstalled), isOn: $hideInstalled)
                if let search = vm.discoverySearch {
                    searchResults(search)
                } else {
                    ForEach(ModCatalog.SectionKind.allCases, id: \.self) { kind in
                        section(kind)
                    }
                }
            }
            .padding()
        }
        .onAppear { vm.loadDiscovery() }
        .sheet(item: $detailRow) { row in
            DiscoveryDetailSheet(vm: vm, row: row)
        }
    }

    private var searchField: some View {
        HStack {
            TextField(vm.L(L10n.Discovery.searchPlaceholder), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { vm.searchDiscovery(name: searchText) }
            Button {
                vm.searchDiscovery(name: searchText)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help(vm.L(L10n.Main.search))
            .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func searchResults(_ search: StarHubTHViewModel.DiscoverySearchResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Le total toujours rendu : la poignée affichée n'est pas tout ce
            // qui existe (« Content Patcher » en rend 428).
            Text(String(format: vm.L(L10n.Discovery.shownOfTotal),
                        search.rows.count, search.totalCount))
                .font(.caption).foregroundStyle(.secondary)
            // Grille adaptative — comme les sections, en cartes, pas une pile
            // verticale de bandes.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)],
                      spacing: 12) {
                ForEach(search.rows) { row in card(row) }
            }
        }
    }

    private func section(_ kind: ModCatalog.SectionKind) -> some View {
        let (rows, shown, total) = vm.discoveryRows(for: kind, hidingInstalled: hideInstalled)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title(for: kind)).font(.title3.bold())
                Spacer()
                // Un filtre ne doit pas masquer qu'il a filtré (spec §7.1) —
                // « 3 affichés sur 20 ».
                Text(String(format: vm.L(L10n.Discovery.shownOfTotal), shown, total))
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    vm.loadDiscovery(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(vm.L(L10n.Discovery.refresh))
            }
            switch vm.discovery[kind] ?? .empty(.neverLoaded) {
            case .empty(let reason):
                emptySection(reason)
            default:
                if rows.isEmpty {
                    Text(vm.L(L10n.Discovery.neverLoaded))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) { ForEach(rows) { card($0) } }
                    }
                }
            }
        }
    }

    private func title(for kind: ModCatalog.SectionKind) -> String {
        switch kind {
        case .trending: return vm.L(L10n.Discovery.trending)
        case .recent: return vm.L(L10n.Discovery.recent)
        case .french: return vm.L(L10n.Discovery.french)
        }
    }

    /// Jamais de section muette (spec §8) : chaque raison a son texte.
    private func emptySection(_ reason: ModCatalog.EmptyReason) -> some View {
        let text: String
        switch reason {
        case .neverLoaded:
            text = vm.L(L10n.Discovery.neverLoaded)
        case .failed:
            switch vm.lastDiscoveryError {
            case .noApiKey: text = vm.L(L10n.Discovery.noKey)
            case .rateLimited: text = vm.L(L10n.Discovery.rateLimited)
            default: text = vm.L(L10n.Discovery.error)
            }
        }
        return HStack {
            Text(text).font(.callout).foregroundStyle(.secondary)
            Button(vm.L(L10n.Discovery.retry)) { vm.loadDiscovery(force: true) }
                .buttonStyle(.borderless)
        }
    }

    /// Carte compacte **textuelle** : v1 sans vignettes (spec §7.1) —
    /// `thumbnailUrl` existe au schéma, il restera pour une itération.
    private func card(_ row: StarHubTHViewModel.DiscoveryRow) -> some View {
        Button { detailRow = row } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.hit.name).font(.headline).lineLimit(2, reservesSpace: true)
                Text(row.hit.uploader).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let endorsements = row.hit.endorsements {
                        Label(String(format: vm.L(L10n.Discovery.endorsements), endorsements),
                              systemImage: "hand.thumbsup")
                            .font(.caption2)
                    }
                    if row.hit.tags.contains(NexusModSearch.frenchTag) {
                        badge("FR")
                    }
                    if row.installed { badge(vm.L(L10n.Discovery.installedBadge)) }
                }
            }
            .padding(10)
            .frame(width: 220, alignment: .leading)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.fill.tertiary, in: Capsule())
    }

    /// Une seule panne, un seul message : les sections ne répètent pas.
    @ViewBuilder private func errorBanner(_ error: NexusSearchClient.SearchError) -> some View {
        switch error {
        case .noApiKey: Text(vm.L(L10n.Discovery.noKey))
        case .rateLimited: Text(vm.L(L10n.Discovery.rateLimited))
        default: Text(vm.L(L10n.Discovery.error))
        }
    }
}

/// La fiche éclair (spec §7.2) : sheet, jamais un état global.
struct DiscoveryDetailSheet: View {
    @ObservedObject var vm: StarHubTHViewModel
    let row: StarHubTHViewModel.DiscoveryRow
    @Environment(\.dismiss) private var dismiss

    private var nexusURL: URL? {
        URL(string: "https://www.nexusmods.com/stardewvalley/mods/\(row.hit.modId)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(row.hit.name).font(.title2.bold()).lineLimit(2)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            switch vm.discoveryDetailState {
            case .loading:
                ProgressView().frame(maxWidth: .infinity)
            case .failed:
                Text(vm.L(L10n.Discovery.detailFailed)).foregroundStyle(.secondary)
            case .idle, .loaded:
                if let detail = vm.discoveryDetail {
                    detailBody(detail)
                } else {
                    Text(vm.L(L10n.Discovery.neverLoaded)).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 520, height: 460)
        .onAppear { vm.loadDiscoveryDetail(modId: row.hit.modId) }
        .onDisappear { vm.closeDiscoveryDetail() }
    }

    @ViewBuilder private func detailBody(_ detail: NexusModSearch.Detail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let endorsements = detail.endorsements {
                    Text(String(format: vm.L(L10n.Discovery.endorsements), endorsements))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let url = nexusURL {
                    Link(destination: url) {
                        Label(vm.L(L10n.Discovery.openNexus), systemImage: "safari")
                    }
                }
                if let summary = detail.summary {
                    Text(summary).font(.callout).italic()
                }
                // La description Nexus est du **BBCode** (`[b]`, `[img]`, `<br />`…)
                // — le même rendu que la fiche mod : blocs parsés, images à taille
                // native via cache, liens cliquables. Les captures y sont déjà des
                // `[img]` : l'image d'en-tête du schéma serait un doublon.
                DescriptionBlocksView(blocks: DescriptionBlockParser.parse(
                    detail.descriptionText ?? ""), vm: vm)
            }
        }
    }
}
