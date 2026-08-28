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
                HStack(spacing: 12) {
                    // « Masquer les installés » ne vaut que pour les sections :
                    // une recherche par nom rend ce qu'on lui a demandé,
                    // installé ou non. La catégorie, elle, s'applique aux deux
                    // — et la recherche se refait quand elle change.
                    if vm.discoverySearch == nil {
                        Toggle(vm.L(L10n.Discovery.hideInstalled), isOn: $hideInstalled)
                    }
                    categoryPicker
                }
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
            if !searchText.isEmpty || vm.discoverySearch != nil {
                Button {
                    searchText = ""
                    vm.clearDiscoverySearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .help(vm.L(L10n.Discovery.clearSearch))
            }
        }
    }

    /// Le filtre de catégorie : les 26 catégories Nexus du jeu, dans l'ordre
    /// de leur nom traduit. Il part au serveur — chaque choix redemande les
    /// trois sections, et chaque catégorie a son propre cache de 24 h.
    private var categoryPicker: some View {
        Menu {
            Button {
                vm.setDiscoveryCategory(nil)
            } label: {
                Label(vm.L(L10n.Mods.categoryFilterAll), systemImage: "square.grid.2x2")
            }
            Divider()
            ForEach(sortedCategories, id: \.id) { category in
                Button {
                    vm.setDiscoveryCategory(category)
                } label: {
                    // Un menu SwiftUI rend le label en texte simple : le glyphe
                    // doit tenir dans le `Text`, un `Label` le perdrait.
                    Text(category.emoji + " " + category.localizedName(vm.L))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                Text(vm.discoveryCategory?.localizedName(vm.L)
                     ?? vm.L(L10n.Mods.categoryFilter))
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(vm.L(L10n.Mods.categoryFilter))
    }

    private var sortedCategories: [NexusCategory] {
        NexusCategory.all.sorted {
            $0.localizedName(vm.L)
                .localizedCaseInsensitiveCompare($1.localizedName(vm.L)) == .orderedAscending
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
            if search.loaded < search.totalCount {
                Button {
                    vm.loadMoreDiscoverySearch()
                } label: {
                    Label(vm.L(L10n.Discovery.loadMore), systemImage: "ellipsis.circle")
                }
                .disabled(vm.discoveryLoading)
            }
        }
    }

    private func section(_ kind: ModCatalog.SectionKind) -> some View {
        let (rows, shown, loaded, total) = vm.discoveryRows(for: kind,
                                                            hidingInstalled: hideInstalled)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title(for: kind)).font(.title3.bold())
                Spacer()
                // Ce qui est montré comparé à ce qui a été **reçu** : un
                // filtre ne doit pas masquer qu'il a filtré (spec §7.1). Le
                // comparer au catalogue entier — « 20 affichés sur 33 204 »
                // — ne comparait rien à rien.
                Text(String(format: vm.L(L10n.Discovery.shownOfLoaded), shown, loaded))
                    .font(.caption).foregroundStyle(.secondary)
                // Dans l'en-tête, pas au bout de la bande : à la fin de vingt
                // cartes qui défilent horizontalement, un bouton est un
                // bouton que personne ne trouve.
                if loaded < total {
                    Button(vm.L(L10n.Discovery.loadMore)) {
                        vm.loadMoreDiscovery(kind)
                    }
                    .buttonStyle(.link)
                    .disabled(vm.discoveryLoading)
                }
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
                    // La section a bien répondu : ce sont les filtres qui ne
                    // laissent rien passer. Dire « rien n'est encore chargé »
                    // ici serait faux, et enverrait rafraîchir pour rien.
                    Text(vm.L(L10n.Discovery.noMatch))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(rows) { card($0) }
                        }
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

    /// Carte avec vignette quand la réponse en porte une (4/4 en tête de
    /// tendances, capture 2026-08-27) — sans elle, la carte reste textuelle.
    private func card(_ row: StarHubTHViewModel.DiscoveryRow) -> some View {
        Button { detailRow = row } label: {
            VStack(alignment: .leading, spacing: 6) {
                // La place de la vignette est **toujours** réservée : sur la
                // sélection FR, où beaucoup de traductions n'ont pas d'image,
                // une carte plus courte que sa voisine décalerait toute la
                // rangée. Le rectangle gris couvre aussi l'attente et l'échec
                // de chargement.
                Rectangle().fill(.quaternary)
                    .overlay {
                        // `CachedAsyncImage` garde les images en mémoire :
                        // trois bandes qui défilent redemanderaient sinon les
                        // mêmes vignettes au réseau à chaque passage.
                        if let thumbnail = row.hit.thumbnailUrl,
                           let url = URL(string: thumbnail) {
                            CachedAsyncImage(url: url)
                        }
                    }
                    .frame(width: 200, height: 90)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(row.hit.name).font(.headline).lineLimit(2, reservesSpace: true)
                Text(row.hit.uploader).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                // La catégorie, avec la couleur et le nom traduit de la liste
                // des mods installés — la même pastille des deux côtés de
                // l'app. Sa place est réservée : sans elle, une carte sans
                // catégorie serait plus courte que ses voisines.
                Group {
                    if let category = row.hit.categoryId.flatMap(NexusCategory.from(id:)) {
                        CategoryBadge(category: category, L: vm.L)
                    }
                }
                .frame(height: 18, alignment: .leading)
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

    /// L'onglet **Files** directement : c'est là qu'on va quand on ouvre la
    /// page depuis la vitrine — la description, on vient de la lire ici.
    private var nexusURL: URL? {
        URL(string: "https://www.nexusmods.com/stardewvalley/mods/\(row.hit.modId)?tab=files")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(row.hit.name).font(.title2.bold()).lineLimit(2)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            // Les deux actions ne dépendent que du `modId` de la carte, pas
            // de la fiche : elles restent offertes quand Nexus ne rend pas la
            // fiche (quota, panne). Les enfermer dans le corps chargé aurait
            // retiré la porte de sortie au moment précis où elle sert.
            HStack(spacing: 12) {
                if let url = nexusURL {
                    // Un `Button` et non un `Link` : la fiche doit se fermer
                    // en même temps que la page s'ouvre, et un `Link` ne
                    // laisse pas la main pour `dismiss()`.
                    Button {
                        NSWorkspace.shared.open(url)
                        dismiss()
                    } label: {
                        Label(vm.L(L10n.Discovery.openNexus), systemImage: "safari")
                    }
                }
                installButton
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

    /// Installer sans passer par le site (G-T3) : le mod non installé emprunte
    /// le **pipeline des mises à jour** — `downloadModFromNexus` résout le
    /// fichier principal, télécharge, et la feuille d'installation prend le
    /// relais. Aucune voie parallèle : c'est le même chemin, éprouvé, que le
    /// bouton des mises à jour et que `nxm://`.
    ///
    /// Trois raisons de le refuser, chacune avec son explication au survol :
    /// un téléchargement déjà en cours, un compte non premium (l'API de lien
    /// répond 403 — le site et `nxm://` restent la voie gratuite), et un mod
    /// déjà installé, qui se met à jour depuis la liste des mods.
    @ViewBuilder private var installButton: some View {
        Button {
            // La fiche se ferme **avant** de lancer : la feuille
            // d'installation est présentée par MainView quelques secondes
            // plus tard, et deux feuilles empilées ne s'affichent pas.
            dismiss()
            vm.downloadModFromNexus(nexusId: row.hit.modId)
        } label: {
            Label(vm.L(L10n.Discovery.install), systemImage: "arrow.down.circle")
        }
        .disabled(vm.isDownloadingFromNexus || vm.nexusDirectDownloadUnavailable
                  || row.installed)
        .help(installHint)
    }

    private var installHint: String {
        if row.installed { return vm.L(L10n.Discovery.alreadyInstalled) }
        if vm.nexusDirectDownloadUnavailable { return vm.L(L10n.Mods.premiumOnlyHint) }
        return vm.L(L10n.Discovery.install)
    }

    @ViewBuilder private func detailBody(_ detail: NexusModSearch.Detail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let endorsements = detail.endorsements {
                    Text(String(format: vm.L(L10n.Discovery.endorsements), endorsements))
                        .font(.caption).foregroundStyle(.secondary)
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
