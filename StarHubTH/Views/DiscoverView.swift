import SwiftUI

/// L'onglet « Découvrir » : tendances, récents, sélection FR, recherche —
/// et le croisement permanent avec le parc installé (spec §7).
///
/// La fiche vit en **sheet interne** : les états globaux de MainView sont
/// remis à nil au changement d'onglet, et cette vue ne doit ni les vider ni
/// en dépendre (spec §7.1).
struct DiscoverView: View {
    @ObservedObject var vm: StarHubTHViewModel
    /// L'onglet courant de `MainView` : sans clé d'API la vitrine ne peut
    /// rien montrer, et le dire sans offrir le chemin des réglages laisse
    /// l'utilisateur le chercher.
    @Binding var currentTab: String
    @AppStorage("discoveryHideInstalled") private var hideInstalled = false
    @State private var searchText = ""
    @State private var detailRow: StarHubTHViewModel.DiscoveryRow?
    /// Combien de cartes chaque section montre. Une vitrine s'aperçoit d'un
    /// coup d'œil : quatre par section tiennent sur un écran avec les trois
    /// sections, « voir plus » déplie la suite. Vingt d'emblée noyaient les
    /// deux sections du bas sous la première.
    @State private var shownLimits: [ModCatalog.SectionKind: Int] = [:]

    /// Le premier palier, et le pas de chaque « voir plus » : la vitrine
    /// grandit de quatre en quatre — quatre, huit, douze — pour que chaque
    /// clic ajoute une rangée lisible plutôt qu'un bloc à retrouver. Le
    /// réseau, lui, continue de livrer par vingt : cinq clics avant une
    /// nouvelle requête.
    private static let firstGlance = 4
    private static let moreStep = 4

    var body: some View {
        ScrollViewReader { scroller in
            content.onChange(of: jumpTarget) { _, target in
                guard let target else { return }
                withAnimation { scroller.scrollTo(target, anchor: .top) }
                jumpTarget = nil
            }
        }
    }

    /// La section vers laquelle sauter. Passer par un état plutôt que
    /// d'appeler `scrollTo` depuis le bouton garde le `ScrollViewReader` en
    /// dehors de chaque en-tête de section.
    @State private var jumpTarget: ModCatalog.SectionKind?

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
                toolbar
                if let error = vm.lastDiscoveryError { discoveryErrorBanner(error) }
                if let search = vm.discoverySearch {
                    searchResults(search)
                } else {
                    sectionJumpBar
                    ForEach(ModCatalog.SectionKind.allCases, id: \.self) { kind in
                        section(kind).id(kind)
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

    /// Une seule rangée de commandes au lieu de trois : recherche, catégorie,
    /// « masquer les installés », et **un** rafraîchissement. Les trois ⟳ des
    /// en-têtes de section appelaient tous le même rechargement global — trois
    /// boutons pour un geste.
    private var toolbar: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
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
                .buttonStyle(.borderless)
                .help(vm.L(L10n.Discovery.clearSearch))
            }
            categoryPicker
            // « Masquer les installés » ne vaut que pour les sections : une
            // recherche par nom rend ce qu'on lui a demandé, installé ou non.
            if vm.discoverySearch == nil {
                Toggle(vm.L(L10n.Discovery.hideInstalled), isOn: $hideInstalled)
                    .font(AppDesign.Font.body)
                    .fixedSize()
            }
            Button {
                vm.loadDiscovery(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(vm.L(L10n.Discovery.refresh))
            .disabled(vm.discoveryLoading)
        }
    }

    /// Le filtre de catégorie : les 26 catégories Nexus du jeu, dans l'ordre
    /// de leur nom traduit. Il part au serveur — chaque choix redemande les
    /// trois sections, et chaque catégorie a son propre cache de 24 h.
    private var categoryPicker: some View {
        // Un `Picker` lié à une valeur, et non un `Menu` de `Button` : chaque
        // choix remplace la vitrine **et** la recherche affichée, donc
        // reconstruit la hiérarchie sous le menu ouvert — un second choix ne
        // partait plus. Un `Picker` porte sa sélection, il survit à la
        // reconstruction.
        Picker(vm.L(L10n.Mods.categoryFilter), selection: categorySelection) {
            Text(vm.L(L10n.Mods.categoryFilterAll)).tag(0)
            Divider()
            ForEach(sortedCategories, id: \.id) { category in
                // Un menu SwiftUI rend l'item en texte simple : le glyphe doit
                // tenir dans le `Text`, un `Label` le perdrait.
                Text(category.emoji + " " + category.localizedName(vm.L)).tag(category.id)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 260)
        .help(vm.L(L10n.Mods.categoryFilter))
    }

    /// `0` = toutes les catégories : `NexusCategory` n'utilise pas cet
    /// identifiant (la racine `1` non plus n'est jamais assignée).
    private var categorySelection: Binding<Int> {
        Binding(get: { vm.discoveryCategory?.id ?? 0 },
                set: { vm.setDiscoveryCategory($0 == 0 ? nil : NexusCategory.from(id: $0)) })
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

    /// Aller droit à une section. Une fois « voir plus » déplié sur les
    /// tendances, la sélection française est à des dizaines de cartes plus
    /// bas : sans ce raccourci, il faut la chercher à la molette.
    private var sectionJumpBar: some View {
        HStack(spacing: 8) {
            ForEach(ModCatalog.SectionKind.allCases, id: \.self) { kind in
                Button(title(for: kind)) { jumpTarget = kind }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    private func section(_ kind: ModCatalog.SectionKind) -> some View {
        let (rows, _, loaded, total) = vm.discoveryRows(for: kind,
                                                        hidingInstalled: hideInstalled)
        let limit = shownLimits[kind] ?? Self.firstGlance
        let visible = Array(rows.prefix(limit))
        // Reste-t-il quelque chose à montrer ? Soit des cartes déjà reçues et
        // repliées, soit une tranche que le serveur a encore.
        let hasMore = rows.count > visible.count || loaded < total
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title(for: kind)).font(.title3.bold())
                Spacer()
                // Ce qui est montré comparé à ce qui a été **reçu** : un
                // filtre ne doit pas masquer qu'il a filtré (spec §7.1). Le
                // comparer au catalogue entier — « 20 affichés sur 33 204 »
                // — ne comparait rien à rien.
                Text(String(format: vm.L(L10n.Discovery.shownOfLoaded),
                            visible.count, loaded))
                    .font(.caption).foregroundStyle(.secondary)
                if hasMore {
                    // Un seul bouton pour deux gestes : déplier ce qui est
                    // déjà reçu, et demander la suite au serveur quand le
                    // palier dépasse ce qu'on a. Deux boutons auraient obligé
                    // l'utilisateur à savoir lequel des deux il lui faut.
                    Button(vm.L(L10n.Discovery.loadMore)) {
                        let next = limit + Self.moreStep
                        shownLimits[kind] = next
                        if next > rows.count && loaded < total {
                            vm.loadMoreDiscovery(kind)
                        }
                    }
                    .buttonStyle(.link)
                    .disabled(vm.discoveryLoading)
                }
            }
            switch vm.discovery[kind] ?? .empty(.neverLoaded) {
            case .empty(let reason):
                emptySection(reason)
            default:
                if rows.isEmpty {
                    noMatchState
                } else {
                    // En grille, pas en bande qui défile : sur la largeur
                    // d'un écran, une bande horizontale ne montrait que 4 ou
                    // 5 mods sur 20, sans ascenseur pour dire qu'il y en
                    // avait d'autres — et les vingt suivants demandés par
                    // « voir plus » atterrissaient hors de vue.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)],
                              spacing: 12) {
                        ForEach(visible) { card($0) }
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

    /// Jamais de section muette (spec §8) : chaque raison a son texte, son
    /// icône **et l'action qui la lève** — un état sans issue n'est qu'un
    /// constat d'échec.
    @ViewBuilder private func emptySection(_ reason: ModCatalog.EmptyReason) -> some View {
        switch reason {
        case .neverLoaded:
            StateCard(icon: "square.grid.2x2", text: vm.L(L10n.Discovery.neverLoaded),
                      actionTitle: vm.L(L10n.Discovery.retry)) { vm.loadDiscovery(force: true) }
        case .failed:
            switch vm.lastDiscoveryError {
            case .noApiKey:
                // La clé sert déjà aux mises à jour : le chemin, pas seulement
                // le diagnostic.
                StateCard(icon: "key", text: vm.L(L10n.Discovery.noKey),
                          actionTitle: vm.L(L10n.Discovery.openSettings)) {
                    currentTab = "Settings"
                }
            case .rateLimited:
                StateCard(icon: "hourglass", text: vm.L(L10n.Discovery.rateLimited),
                          actionTitle: vm.L(L10n.Discovery.retry)) { vm.loadDiscovery(force: true) }
            default:
                StateCard(icon: "wifi.exclamationmark", text: vm.L(L10n.Discovery.error),
                          actionTitle: vm.L(L10n.Discovery.retry)) { vm.loadDiscovery(force: true) }
            }
        }
    }

    /// La section a répondu, les filtres n'ont rien laissé passer. L'action
    /// est de **retirer les filtres**, pas de rafraîchir : rafraîchir
    /// rapporterait les mêmes mods, écartés par les mêmes règles.
    @ViewBuilder private var noMatchState: some View {
        if vm.discoveryCategory != nil || hideInstalled {
            StateCard(icon: "line.3.horizontal.decrease.circle",
                      text: vm.L(L10n.Discovery.noMatch),
                      actionTitle: vm.L(L10n.Discovery.clearFilters)) {
                hideInstalled = false
                vm.setDiscoveryCategory(nil)
            }
        } else {
            StateCard(icon: "line.3.horizontal.decrease.circle",
                      text: vm.L(L10n.Discovery.noMatch), actionTitle: nil, action: {})
        }
    }

    /// La carte : vignette **pleine largeur en 16/9**, « installé » posé
    /// dessus, puis titre, auteur, et une seule ligne de métadonnées.
    ///
    /// Elle mesurait 220 pt pour une vignette de 200×90 : deux marges grises
    /// autour de l'image, et une largeur figée qui laissait des gouttières
    /// inégales dans une grille adaptative. Elle occupe maintenant sa case.
    private func card(_ row: StarHubTHViewModel.DiscoveryRow) -> some View {
        Button { detailRow = row } label: {
            VStack(alignment: .leading, spacing: 0) {
                thumbnail(row)
                VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                    Text(row.hit.name)
                        .font(AppDesign.Font.body(.semibold))
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    Text(row.hit.uploader)
                        .font(AppDesign.Font.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    metaRow(row)
                }
                .padding(.horizontal, AppDesign.Spacing.md)
                .padding(.top, 10)
                .padding(.bottom, AppDesign.Spacing.md)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.section))
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.section)
                    .stroke(Color.primary.opacity(AppDesign.Opacity.light), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// La place de la vignette est **toujours** réservée : sur la sélection
    /// FR, où beaucoup de traductions n'ont pas d'image, une carte plus
    /// courte que sa voisine décalerait toute la rangée. Le rectangle gris
    /// couvre aussi l'attente et l'échec de chargement.
    private func thumbnail(_ row: StarHubTHViewModel.DiscoveryRow) -> some View {
        Rectangle().fill(.quaternary)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                // `CachedAsyncImage` garde les images en mémoire : dérouler
                // la vitrine redemanderait sinon les mêmes vignettes au
                // réseau à chaque passage.
                if let thumbnail = row.hit.thumbnailUrl,
                   let url = URL(string: thumbnail) {
                    CachedAsyncImage(url: url)
                }
            }
            .clipped()
            // « Installé » sur l'image, pas en bas de pile : c'est ce qu'on
            // cherche en balayant une grille.
            .overlay(alignment: .topTrailing) {
                if row.installed {
                    // Pastille **pleine**, pas translucide : posée sur un
                    // matériau, elle se noyait dans les vignettes claires. Du
                    // blanc sur vert tient sur n'importe quelle image, et
                    // l'ombre la décolle du fond.
                    Label(vm.L(L10n.Discovery.installedBadge),
                          systemImage: "checkmark.circle.fill")
                        .font(AppDesign.Font.caption(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppDesign.Spacing.sm)
                        .padding(.vertical, AppDesign.Spacing.xs)
                        .background(Color.green, in: Capsule())
                        .shadow(color: .black.opacity(AppDesign.Opacity.strong),
                                radius: 3, y: 1)
                        .padding(AppDesign.Spacing.sm)
                }
            }
    }

    /// Une seule ligne : la catégorie à gauche, les endossements à droite.
    /// Sa hauteur est réservée — sans catégorie servie, une carte plus courte
    /// décalerait ses voisines.
    private func metaRow(_ row: StarHubTHViewModel.DiscoveryRow) -> some View {
        HStack(spacing: AppDesign.Spacing.xs + 2) {
            if let category = row.hit.categoryId.flatMap(NexusCategory.from(id:)) {
                CategoryBadge(category: category, L: vm.L)
            }
            if row.hit.tags.contains(NexusModSearch.frenchTag) {
                badge("FR")
            }
            Spacer(minLength: 0)
            if let endorsements = row.hit.endorsements {
                Label("\(endorsements)", systemImage: "hand.thumbsup")
                    .font(AppDesign.Font.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 18)
        .padding(.top, 2)
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.fill.tertiary, in: Capsule())
    }

    /// Une seule panne, un seul message : les sections ne répètent pas. La vue
    /// résout le texte et l'action, le bandeau se contente de les rendre.
    ///
    /// Trois messages mais **deux** issues seulement : hors « pas de clé », la
    /// panne se réessaie. Les séparer en trois branches dupliquait l'action
    /// sans rien clarifier.
    private func discoveryErrorBanner(_ error: NexusSearchClient.SearchError) -> some View {
        let text: String
        switch error {
        case .noApiKey: text = vm.L(L10n.Discovery.noKey)
        case .rateLimited: text = vm.L(L10n.Discovery.rateLimited)
        default: text = vm.L(L10n.Discovery.error)
        }
        if case .noApiKey = error {
            // La clé sert déjà aux mises à jour : le chemin, pas seulement le
            // diagnostic.
            return ErrorBanner(text: text,
                               actionTitle: vm.L(L10n.Discovery.openSettings)) {
                currentTab = "Settings"
            }
        }
        return ErrorBanner(text: text,
                           actionTitle: vm.L(L10n.Discovery.retry)) {
            vm.loadDiscovery(force: true)
        }
    }
}

/// Met en avant celui des deux boutons qui **fonctionne**. SwiftUI n'a pas
/// de `ButtonStyle` effaçable en type : la branche vit ici plutôt que dans un
/// ternaire impossible à écrire.
private struct ProminentButton: ViewModifier {
    let prominent: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
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
        VStack(alignment: .leading, spacing: 0) {
            hero
            statStrip
            Divider()
            actions
            switch vm.discoveryDetailState {
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding()
            case .failed:
                Text(vm.L(L10n.Discovery.detailFailed))
                    .font(AppDesign.Font.body).foregroundStyle(.secondary).padding()
            case .idle, .loaded:
                if let detail = vm.discoveryDetail {
                    detailBody(detail)
                } else {
                    Text(vm.L(L10n.Discovery.neverLoaded))
                        .font(AppDesign.Font.body).foregroundStyle(.secondary).padding()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 560, height: 640)
        .onAppear { vm.loadDiscoveryDetail(modId: row.hit.modId) }
        .onDisappear { vm.closeDiscoveryDetail() }
    }

    /// Le bandeau : la vignette du mod, son nom et son auteur par-dessus. Le
    /// titre nu sur fond blanc ne disait pas de quel mod on parlait tant que
    /// la description n'était pas chargée.
    private var hero: some View {
        Rectangle().fill(.quaternary)
            .frame(height: 150)
            .overlay {
                if let thumbnail = row.hit.thumbnailUrl, let url = URL(string: thumbnail) {
                    CachedAsyncImage(url: url)
                }
            }
            .clipped()
            .overlay {
                // Le texte se lit sur n'importe quelle image : le dégradé est
                // la seule garantie de contraste qu'on maîtrise.
                LinearGradient(colors: [.clear, .black.opacity(0.65)],
                               startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.hit.name)
                        .font(AppDesign.Font.viewTitle)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(row.hit.uploader)
                        .font(AppDesign.Font.caption)
                        .foregroundStyle(.white.opacity(AppDesign.Opacity.secondary))
                }
                .padding(AppDesign.Spacing.lg)
            }
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(AppDesign.Opacity.secondary))
                }
                .buttonStyle(.plain)
                .padding(AppDesign.Spacing.sm)
            }
    }

    /// Ce que la carte ne disait pas, en une bande : endossements, version,
    /// âge de la mise à jour, catégorie. Ces quatre chiffres décident de
    /// l'installation plus sûrement qu'un paragraphe de description.
    private var statStrip: some View {
        HStack(alignment: .top, spacing: 0) {
            stat(vm.L(L10n.Discovery.statEndorsements),
                 (vm.discoveryDetail?.endorsements ?? row.hit.endorsements)
                     .map { "\($0)" } ?? "—")
            stat(vm.L(L10n.ModInstall.labelVersion),
                 vm.discoveryDetail?.version.isEmpty == false
                     ? vm.discoveryDetail!.version
                     : (row.hit.version.isEmpty ? "—" : row.hit.version))
            stat(vm.L(L10n.Discovery.statUpdated), updatedText)
            stat(vm.L(L10n.Mods.categoryFilter),
                 row.hit.categoryId.flatMap(NexusCategory.from(id:))?.localizedName(vm.L)
                     ?? (row.hit.categoryName.isEmpty ? "—" : row.hit.categoryName))
        }
        .padding(.horizontal, AppDesign.Spacing.lg)
        .padding(.vertical, AppDesign.Spacing.md)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            Text(value).font(AppDesign.Font.body(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var updatedText: String {
        guard let date = vm.discoveryDetail?.updatedAt ?? row.hit.updatedAt else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Les deux actions ne dépendent que du `modId` de la carte, pas de la
    /// fiche : elles restent offertes quand Nexus ne rend pas la fiche (quota,
    /// panne). Les enfermer dans le corps chargé aurait retiré la porte de
    /// sortie au moment précis où elle sert.
    ///
    /// **Celle qui marche est la proéminente** : sur un compte gratuit
    /// l'installation directe est refusée par l'API, alors le site prend le
    /// bouton bleu.
    private var actions: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            installButton
            if let url = nexusURL {
                // Un `Button` et non un `Link` : la fiche doit se fermer en
                // même temps que la page s'ouvre, et un `Link` ne laisse pas
                // la main pour `dismiss()`.
                Button {
                    NSWorkspace.shared.open(url)
                    dismiss()
                } label: {
                    Label(vm.L(L10n.Discovery.openNexus), systemImage: "arrow.up.forward.square")
                }
                .modifier(ProminentButton(prominent: !installOffered))
            }
            Spacer(minLength: 0)
            if row.installed {
                Label(vm.L(L10n.Discovery.installedBadge), systemImage: "checkmark.circle.fill")
                    .font(AppDesign.Font.footnote)
                    .foregroundStyle(Color.green)
            }
        }
        .padding(.horizontal, AppDesign.Spacing.lg)
        .padding(.vertical, AppDesign.Spacing.md)
    }

    /// L'installation directe est-elle réellement praticable ici ?
    private var installOffered: Bool {
        !vm.nexusDirectDownloadUnavailable && !row.installed
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
        .modifier(ProminentButton(prominent: installOffered))
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
            VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                // Les endossements sont montés dans la bande de chiffres : les
                // répéter ici doublonnait.
                if let summary = detail.summary {
                    Text(summary).font(AppDesign.Font.body).italic()
                        .foregroundStyle(.secondary)
                }
                // La description Nexus est du **BBCode** (`[b]`, `[img]`, `<br />`…)
                // — le même rendu que la fiche mod : blocs parsés, images à taille
                // native via cache, liens cliquables. Les captures y sont déjà des
                // `[img]` : l'image d'en-tête du schéma serait un doublon.
                DescriptionBlocksView(blocks: DescriptionBlockParser.parse(
                    detail.descriptionText ?? ""), vm: vm)
            }
            .padding(.horizontal, AppDesign.Spacing.lg)
            .padding(.bottom, AppDesign.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
