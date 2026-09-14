import SwiftUI

// Les enums de cadrage de la liste (`ModFilter`, `FrenchTranslationScope`,
// `CategoryScope`, `ModSortOrder`) vivent désormais dans
// `Models/ModListFilters.swift` : ils sont entrés dans `StarHubTHCore` pour
// se tester (F1 — voir l'en-tête de ce fichier).

/// A single slot in the pagination footer: either a numbered page button or
/// an ellipsis gap. Using an enum (instead of a sentinel like `-1`) makes it
/// impossible for an ellipsis to collide with a page number identity, which
/// would crash SwiftUI if duplicate `id` values appeared in `ForEach`.
private enum PageSlot {
    case page(Int)
    case ellipsis
}

struct ModListView: View {
    /// ⌘F amène ici (voir `SearchFieldShortcut`).
    @FocusState private var searchFocused: Bool

    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// L'onglet affiché, pour les rares endroits d'où la liste **mène
    /// ailleurs** (le badge de profil actif). Même patron que
    /// `ModProfilesView`, `UpdatesView` et `SystemAlertsView`.
    @Binding var currentTab: SidebarDestination
    /// Le cadrage de la liste, observé **à part** du ViewModel pour que taper
    /// dans la recherche ne redessine pas toute la fenêtre — voir `ModListState`.
    /// internal : lu par l'extension du panneau (P8, geste A).
    @ObservedObject var listState: ModListState

    init(vm: StarHubTHViewModel, localization: LocalizationStore, currentTab: Binding<SidebarDestination>) {
        self.localization = localization
        self.vm = vm
        self.listState = vm.modList
        self._currentTab = currentTab
    }

    /// Lecture seule du cadrage courant (recherche, filtres, tri, page). Les
    /// écritures passent par `listState.filters` en clair, pour qu'on voie au
    /// premier coup d'œil ce qui modifie un état partagé.
    /// internal : lu par l'extension du panneau (`ModListView+Filters.swift`) —
    /// `private` est file-scopé pour les extensions (P8, geste A).
    var filters: ModListFilters { listState.filters }
    /// Nombre de mods rendus par page — liste **et** grille, une seule
    /// constante pour les deux dispositions. 12 depuis le 2026-09-09 (15
    /// auparavant), à la demande de l'auteur.
    private let pageSize: Int = 12
    @State private var showInstallSheet = false
    /// La grille optionnelle du lot Mods (H-T4). Liste par défaut : 966 mods
    /// se parcourent en rangées denses. `@AppStorage` suit le patron de
    /// `discoveryHideInstalled` (`DiscoverView.swift:15`) — c'est une
    /// habitude de parcours, pas un état de session.
    enum ModsListLayout: String { case list, grid }
    @AppStorage("modsListLayout") private var listLayout: ModsListLayout = .list
    /// Drives the confirmation dialog when the user picks "Enable All" or
    /// "Disable All" from the bulk-actions menu. `true` = enabling, `false`
    /// = disabling — kept as a single optional so the dialog binds cleanly.
    @State private var bulkToggleTarget: Bool? = nil

    /// Scopes the list to the mod the user asked to jump to, clearing anything
    /// that could filter it out, then clears the request so it fires once.
    private func consumePendingModFocus() {
        guard let modName = vm.navigationStore.pendingModFocus else { return }
        // Prefer the resolved mod's own name: SMAPI logs a display name that can
        // differ from the manifest, and the search matches on name/uniqueId.
        // The request may also carry a folder name (the guided search works in
        // those) — `ModFocusResolver` accepts either.
        let resolved = ModFocusResolver.resolve(modName, in: vm.scanStore.mods)
        listState.filters.focus(on: resolved?.name ?? modName)
        vm.navigationStore.pendingModFocus = nil
    }

    // MARK: - Cadrage : amincissements de la règle du ViewModel
    //
    // La règle de cadrage (les cinq filtres, le tri, le scope) vit dans le
    // ViewModel — `mods(matching:)` et `scopedMods(from:scope:)` — pour que
    // la liste et la bascule en masse (« Tout activer », X57) la partagent
    // au lieu de la recopier. La vue n'en garde que des raccourcis de
    // lecture ; les facettes recomposent les prédicats **en laissant tomber
    // le leur** pour compter ce que la vue active contient.

    var filteredMods: [ModItem] { vm.mods(matching: filters) }

    /// The full ordered list of mods that should be displayed under the current
    /// scope (search + category + enabled/disabled filter). Pagination slices
    /// this list; the scope section headers (Enabled/Disabled) are derived from
    /// each page's slice.
    ///
    /// Takes `filtered` (rather than re-deriving it) so callers that already
    /// computed it once per render don't trigger the search/category/sort
    /// pass again.
    private func displayMods(from filtered: [ModItem]) -> [ModItem] {
        vm.scopedMods(from: filtered, scope: filters.scope)
    }

    private func totalPages(for mods: [ModItem]) -> Int {
        guard !mods.isEmpty else { return 1 }
        return Int(ceil(Double(mods.count) / Double(pageSize)))
    }

    /// The clamped page used for both the slice and the footer, so they can
    /// never disagree even during the transient render before `ModListFilters`
    /// resets the page.
    private func effectivePage(totalPages: Int) -> Int {
        min(max(1, filters.page), totalPages)
    }

    /// Mods on the current page. Always clamped so a shrinking result set
    /// (e.g. typing more search characters) never produces an out-of-range
    /// index.
    private func pageMods(from mods: [ModItem], page: Int) -> [ModItem] {
        let total = mods.count
        guard total > 0 else { return [] }
        let start = (page - 1) * pageSize
        let end = min(start + pageSize, total)
        return Array(mods[start..<end])
    }

    /// Les mods sur lesquels un menu compte ses options : ceux que la vue
    /// active contient — cadrage compris (« Tous », « Activés », « En pause »,
    /// « Problèmes ») — **moins le filtre du menu lui-même**. Sans cette
    /// exception, choisir une catégorie réduirait le menu à cette seule
    /// catégorie et on ne pourrait plus en changer.
    ///
    /// Les deux bases sortent d'un **seul** cadrage : `displayMods` fait, sous
    /// « Problèmes », un scan de dépendances par mod — c'est précisément ce que
    /// `scopeCounts` avait été écrit pour ne pas refaire à chaque évaluation.
    /// Les filtres commutant entre eux, retrancher le sien après le cadrage
    /// donne le même ensemble pour un parcours de moins.
    ///
    /// Le tri n'entre pas ici : il ne change pas quels mods sont là.
    private func facetBases() -> (category: [ModItem], translation: [ModItem]) {
        let scoped = vm.scopedMods(from: vm.scanStore.mods.filter { mod in
            vm.matchesSearch(mod, filters: filters)
                && vm.matchesConfig(mod, filters: filters)
                && vm.matchesFavorites(mod, filters: filters)
                && vm.matchesBlacklisted(mod, filters: filters)
        }, scope: filters.scope)
        return (category: scoped.filter { vm.matchesTranslation($0, filters.frenchTranslation) },
                translation: scoped.filter { vm.matchesCategory($0, filters: filters) })
    }

    /// Categories actually present among the currently installed mods, sorted
    /// alphabetically by localized name. Drives the category-picker menu so the
    /// user never sees an empty scope. Computed from the *effective* category
    /// of every mod (manual override wins over the API-fetched category), so
    /// user-categorized mods appear in the picker as soon as they're pinned.
    private func availableCategories(from base: [ModItem]) -> [(category: NexusCategory, count: Int)] {
        var counts: [Int: Int] = [:]
        // Counts must be derived the exact same way the `.category` filter
        // branch resolves a mod (`vm.category(for: mod)` on the top-level
        // mod, which already resolves a group to its dominant child
        // category) — counting each child's own category individually (as
        // this used to) could show a non-zero count for a category that,
        // once selected, filters nothing in because it's a group's minority
        // category rather than its dominant one.
        for mod in base {
            if let cid = vm.category(for: mod)?.id { counts[cid, default: 0] += 1 }
        }
        return NexusCategory.all
            .filter { counts[$0.id] != nil }
            .map { ($0, counts[$0.id] ?? 0) }
            .sorted { $0.category.localizedName(localization.L)
                .localizedCaseInsensitiveCompare($1.category.localizedName(localization.L)) == .orderedAscending }
    }

    /// (tag key, localized label, count) for top-level mods with no Nexus
    /// category and a non-"Other" inferred tag — the offline fallback buckets.
    private func inferredTagBuckets(from base: [ModItem]) -> [(tag: String, label: String, count: Int)] {
        var counts: [String: Int] = [:]
        for mod in base where vm.category(for: mod) == nil {
            let tag = vm.inferredTagKey(for: mod)
            if tag != "Other" { counts[tag, default: 0] += 1 }
        }
        return counts.map { (tag: $0.key, label: localization.L(L10n.ModTag.key(for: $0.key)), count: $0.value) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Count of top-level mods (standalone mods + whole packs) with no
    /// category assigned AND an inferred tag of "Other" — matching the
    /// `.uncategorized` filter case above (mods with a more specific inferred
    /// tag are counted in `inferredTagBuckets` instead). Drives the
    /// "No Category (N)" menu entry and its visibility.
    private func uncategorizedCount(from base: [ModItem]) -> Int {
        base.filter { vm.category(for: $0) == nil && vm.inferredTagKey(for: $0) == "Other" }.count
    }

    /// Precomputed counts for all four scope filters, derived in a single pass
    /// over `filtered`. Avoids recomputing the `.issues` scope (which does a
    /// per-mod dependency scan) every time the Picker label is evaluated.
    /// `issues` applique le même verdict d'anomalie que
    /// `ModListScoping.scoped(_:scope:hasAnomaly:)` — voir son commentaire pour
    /// ce que « en pause » y change, et ce qu'il n'y change pas.
    private func scopeCounts(for filtered: [ModItem]) -> (all: Int, enabled: Int, disabled: Int, issues: Int) {
        var enabled = 0, disabled = 0, issues = 0
        for mod in filtered {
            if mod.isEnabled { enabled += 1 } else { disabled += 1 }
            if vm.matchesSelfOrAnyChild(mod, { vm.hasIssues($0) }) { issues += 1 }
        }
        return (filtered.count, enabled, disabled, issues)
    }

    /// Le titre de la section courante — les quatre scopes ne diffèrent que
    /// par lui. La liste et la grille le partagent : le scope actif se lit
    /// de la même façon dans les deux denses (P2).
    private var scopeSectionTitle: String {
        switch filters.scope {
        case .all: return localization.L(L10n.Mods.filterAll)
        case .enabled: return localization.L(L10n.Mods.enabled)
        case .disabled: return localization.L(L10n.Mods.disabled)
        case .issues: return localization.L(L10n.Mods.filterIssues)
        }
    }

    /// Les attributs que la carte porte — les mêmes que la rangée de la
    /// liste, dans le même ordre : anomalie, note, config gardée par le
    /// profil. Sur la carte ils ne s'ouvrent pas au clic (celui-ci mène à la
    /// fiche, qui les détaille) ; leur infobulle porte le texte entier.
    private func gridAttributes(for mod: ModItem) -> [CardAttribute] {
        var attributes: [CardAttribute] = []
        if let anomaly = vm.anomaly(for: mod) {
            attributes.append(CardAttribute(id: "anomaly",
                                            systemImage: "exclamationmark.triangle.fill",
                                            tint: anomaly.severity == .error ? .orange : .yellow,
                                            help: anomalyReasons(anomaly, vm: vm)))
        }
        if let note = vm.modNote(for: mod) {
            attributes.append(CardAttribute(id: "note", systemImage: "note.text", help: note))
        }
        if vm.isProfileConfigManaged(mod) {
            // Même glyphe que la rangée (voir `profileConfigSlot`) : des
            // curseurs à 10 pt s'y lisaient comme une note.
            attributes.append(CardAttribute(id: "profileConfig",
                                            systemImage: "gearshape",
                                            help: localization.L(L10n.Mods.profileConfigBadge)))
        }
        return attributes
    }

    /// L'adresse de la capture Nexus déjà en cache pour ce mod — celle que la
    /// fiche affiche (`nexusCachedExtras`, persisté : 769 de ses 791 entrées
    /// en portent une). Aucun réseau de plus n'est demandé ici : seules les
    /// cartes visibles chargent leur image, et `CachedAsyncImage` la garde
    /// (`NSCache` borné à 400 images / 128 Mo).
    ///
    /// L'identifiant passe par `sharedNexusId` : un pack **à plat** n'hérite
    /// pas de la capture de son premier composant.
    private func gridPictureURL(for mod: ModItem) -> String? {
        guard let id = ModGridCardValues.sharedNexusId(of: mod, effectiveId: {
            vm.effectiveNexusModId(for: $0)
        }) else { return nil }
        return vm.nexusModExtras[id]?.pictureUrl
    }

    var body: some View {
        // Compute the expensive derived data once per render instead of
        // re-evaluating the search/category/sort pass (and everything
        // downstream of it) on every Picker label and list access.
        let filtered = filteredMods
        let counts = scopeCounts(for: filtered)
        // Un seul cadrage par rendu pour les quatre facettes : chacune le
        // refaisait, et le rendu suit la frappe dans la recherche.
        let facets = facetBases()
        let categories = availableCategories(from: facets.category)
        let uncatCount = uncategorizedCount(from: facets.category)
        let tagBuckets = inferredTagBuckets(from: facets.category)
        let translationCounts = frenchTranslationCounts(from: facets.translation)
        let display = displayMods(from: filtered)
        let pages = totalPages(for: display)
        let page = effectivePage(totalPages: pages)
        let paged = pageMods(from: display, page: page)
        // L'instantané que le pager de la fiche lira (H-T4b) : le cadrage
        // ordonné **complet**, pas la tranche de page courante.
        let displayIds = display.map(\.folderName)
        VStack(spacing: 0) {

            // ── Sticky header ────────────────────────────────────────────
            // The toolbar (scope picker + filters + sort) stays fixed above
            // the scrolling list, mirroring LogsView's sticky header layout.
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                // Primary row: scope picker (left) + primary action (right).
                // Keeps the most-used navigation and the key CTA at the
                // same visual priority, above the secondary filters.
                HStack {
                    Picker("", selection: $listState.filters.scope) {
                        Text("\(localization.L(L10n.Mods.filterAll)) (\(counts.all))")
                            .tag(ModFilter.all)
                        Text("\(localization.L(L10n.Mods.enabled)) (\(counts.enabled))")
                            .tag(ModFilter.enabled)
                        Text("\(localization.L(L10n.Mods.disabled)) (\(counts.disabled))")
                            .tag(ModFilter.disabled)
                        Label("\(localization.L(L10n.Mods.filterIssues)) (\(counts.issues))",
                              systemImage: "exclamationmark.triangle")
                            .tag(ModFilter.issues)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 480)

                    // La recherche vit ici, au motif des journaux
                    // (`LogsView.swift:182`) — la barre système `.searchable`
                    // disparaît : un geste, une place (P3). Filtrage à la
                    // frappe, comme `.searchable` le donnait ; le motif
                    // Découvrir est submit-only et l'aurait régressé.
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(AppDesign.Font.iconXS)
                            .foregroundColor(.secondary)
                        TextField(localization.L(L10n.Mods.searchMods),
                                  text: $listState.filters.search)
                            .textFieldStyle(.plain)
                            .searchFieldShortcut($searchFocused)
                        if !listState.filters.search.isEmpty {
                            Button {
                                listState.filters.search = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            // Cible 18×18 + contentShape : un glyphe nu de
                            // ~12 pt rend `.help` muet (contrainte a11y du
                            // lot ; patron `ModListView` ligne ~1500).
                            .frame(width: 18, height: 18)
                            .contentShape(.rect)
                            .help(localization.L(L10n.Discovery.clearSearch))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(AppDesign.Opacity.light))
                    .cornerRadius(6)
                    .frame(maxWidth: 220)

                    Spacer()

                    // La grille optionnelle (H-T4) : liste dense par défaut,
                    // cartes au-dessus. Choix persisté — c'est une habitude
                    // de parcours, pas un état de session.
                    Picker(localization.L(L10n.Mods.layoutList), selection: $listLayout) {
                        // `list.bullet` et non un glyph de disposition : à
                        // 32 pt de demi-segment, tout ce qui dessine des
                        // quartiers devient illisible.
                        Image(systemName: "list.bullet")
                            .tag(ModsListLayout.list)
                        Image(systemName: "square.grid.2x2")
                            .tag(ModsListLayout.grid)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 64)
                    .help(listLayout == .list
                          ? localization.L(L10n.Mods.layoutList)
                          : localization.L(L10n.Mods.layoutGrid))

                    // Bulk enable/disable all mods at once. Disabled when
                    // there is nothing to act on (empty list, or every mod
                    // is already in the target state), or while a bulk
                    // toggle operation is already in flight.
                    bulkToggleMenu(scoped: display)
                        .disabled(vm.scanStore.mods.isEmpty || vm.bulkToggleProgress != nil)

                    Button {
                        showInstallSheet = true
                    } label: {
                        Label(localization.L(L10n.ModInstall.installButton), systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Secondary row: filters and sort, grouped as chips.
                // Wraps the set of filter controls in a single HStack so
                // they read as one visual unit ("refine the list"),
                // separate from the primary scope/actions above.
                HStack(spacing: 6) {
                    sortPicker

                    Divider()
                        .frame(height: 16)

                    configFilterToggle

                    favoritesFilterToggle

                    blacklistedFilterToggle

                    Divider()
                        .frame(height: 16)

                    frenchTranslationPicker(counts: translationCounts)

                    categoryPicker(categories: categories, uncatCount: uncatCount, tagBuckets: tagBuckets)
                        .disabled(categories.isEmpty && uncatCount == 0 && tagBuckets.isEmpty)
                        .help(categories.isEmpty && uncatCount == 0 && tagBuckets.isEmpty
                              ? localization.L(L10n.Mods.categoryFilterEmptyHint)
                              : localization.L(L10n.Mods.categoryFilterHint))

                    Spacer()

                    scopeWeightLabel(for: display)

                    if categories.isEmpty && uncatCount == 0 && tagBuckets.isEmpty {
                        Text(localization.L(L10n.Mods.categoryFilterEmptyHint))
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary.opacity(AppDesign.Opacity.secondary))
                    }

                    // Le profil appliqué — et le chemin vers la page qui le
                    // gère : c'est là qu'on va quand on le lit ici.
                    if let profile = vm.activeProfile {
                        Button {
                            currentTab = .profiles
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "person.crop.circle")
                                    .font(AppDesign.Font.footnote)
                                Text(String(format: localization.L(L10n.Profiles.activeLabel), profile.name))
                                    .font(AppDesign.Font.footnote(.medium))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .pointingHandCursor()
                        .help(localization.L(L10n.Profiles.title))
                        .accessibilityLabel(String(format: localization.L(L10n.Profiles.activeLabel), profile.name))
                        .accessibilityHint(localization.L(L10n.Profiles.title))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // ── Scrollable list ──────────────────────────────────────────
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.xxl) {
                    if filtered.isEmpty {
                        if vm.scanStore.mods.isEmpty {
                            // Première utilisation : zone de drop XXL
                            EmptyStateDropZone(vm: vm, localization: localization, onInstall: { showInstallSheet = true })
                                .padding(.top, 40)
                        } else {
                            // Recherche sans résultat
                            VStack(spacing: AppDesign.Spacing.lg) {
                                Image(systemName: "puzzlepiece.extension")
                                    .font(AppDesign.Font.emptyStateGlyph)
                                    .foregroundColor(.secondary.opacity(AppDesign.Opacity.disabled))
                                Text(String(format: localization.L(L10n.Mods.noModFound), filters.search))
                                    .multilineTextAlignment(.center)
                                    .font(AppDesign.Font.rowTitle)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        }
                    } else if display.isEmpty {
                        // Scope eliminated every mod (e.g. "Disabled" picked but
                        // everything is enabled, or "Issues" with no problems).
                        if filters.scope == .issues { noIssuesMessage } else { emptyScopeMessage }
                    } else {
                        // Render the current page only. Une seule section sous
                        // « Tous » : la couper en Activés / En pause imposait un
                        // ordre que le tri choisi n'avait pas demandé.
                        switch listLayout {
                        case .list:
                            ModSectionGroup(title: scopeSectionTitle, mods: paged, vm: vm, localization: localization, listState: listState)
                        case .grid:
                            // Même section, même titre, même page que la liste
                            // (P2 : le compte honnête ne change pas avec la
                            // densité) — seule la manière de rendre change.
                            // L'expansion des packs n'existe pas ici : une
                            // carte par pack, ses composants s'ouvrent depuis
                            // la fiche (voir « Ce que ce plan ne fait pas »).
                            StandardSection(title: scopeSectionTitle) {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: AppDesign.Grid.minCardWidth),
                                                            spacing: AppDesign.Grid.gutter)],
                                          spacing: AppDesign.Grid.gutter) {
                                    ForEach(paged) { mod in
                                        let values = ModGridCardValues.card(
                                            mod: mod,
                                            versionPrefix: localization.L(L10n.Mods.versionPrefix),
                                            pictureURL: gridPictureURL(for: mod))
                                        let active = values.state == .active
                                        ModCard(title: values.title,
                                                subtitle: values.subtitle,
                                                thumbnailURL: values.thumbnailURL,
                                                // La pastille dit l'**état**,
                                                // pas « installé » : tout l'est
                                                // ici. Les deux états se posent,
                                                // jamais l'un par l'absence de
                                                // l'autre (P6).
                                                installedLabel: localization.L(active
                                                    ? L10n.Mods.cardActive
                                                    : L10n.Mods.cardPaused),
                                                badgeTint: active
                                                    ? AppDesign.Color.installed
                                                    : AppDesign.Color.paused,
                                                badgeSystemImage: active
                                                    ? "checkmark.circle.fill"
                                                    : "pause.circle.fill",
                                                // La catégorie que la liste
                                                // connaît déjà : celle que
                                                // l'utilisateur a assignée, celle
                                                // de Nexus, ou la dominante d'un
                                                // pack (`category(for:)`).
                                                category: vm.category(for: mod),
                                                neutralBadge: values.neutralBadge,
                                                endorsements: values.endorsements,
                                                usesDefaultArtwork: true,
                                                attributes: gridAttributes(for: mod),
                                                L: localization.L,
                                                action: { vm.navigationStore.setViewingModDetail(mod) })
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, AppDesign.Spacing.lg)
            }

            // ── Sticky pagination footer ─────────────────────────────────
            // Stays pinned at the bottom of the view while the list scrolls,
            // mirroring LogsView's sticky status bar.
            if !filtered.isEmpty && !display.isEmpty && pages > 1 {
                Divider()
                paginationFooter(total: display.count, shown: paged.count, page: page, totalPages: pages)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            if let prog = vm.bulkToggleProgress, prog.total > 0 {
                bulkToggleOverlay(done: prog.done, total: prog.total)
            }
        }
        // Les cinq `.onChange` par critère sont partis dans `ModListFilters` :
        // la règle y est portée par le type, donc un filtre ajouté plus tard ne
        // peut plus oublier sa remise à la page 1. Reste celui-ci, qui ne
        // dépend d'aucun filtre : la liste a changé de taille sous nos pieds
        // (installation, suppression, activation d'un profil).
        .onChange(of: vm.scanStore.mods.count)    { _, _ in listState.filters.page = 1 }
        // Clicking a mod name in the logs must land on that mod, not on the full
        // list. `selectedModID` alone only tints the row — with filters and
        // pagination the mod may not even be on the visible page — so scope the
        // list to it and clear anything that could filter it out.
        // A jump request can arrive before this view exists (from the Logs tab),
        // so it's read on appear as well as while already on screen.
        .onAppear { consumePendingModFocus() }
        .onChange(of: vm.navigationStore.pendingModFocus) { _, _ in consumePendingModFocus() }
        // Publier l'instantané du cadrage au patrimoine commun : la fiche
        // (qui s'exclut de la liste dans MainView) y lira l'ordre de son
        // pager. Non publié sur ModListState — voir là-bas le pourquoi.
        .onAppear { vm.modList.displayOrder = displayIds }
        .onChange(of: displayIds) { _, order in vm.modList.displayOrder = order }
        .sheet(isPresented: $showInstallSheet) {
            ModInstallView(vm: vm, localization: localization, currentTab: $currentTab, isPresented: $showInstallSheet)
        }
        .confirmationDialog(
            bulkToggleTarget == true
                ? localization.L(L10n.Mods.enableAllConfirm)
                : localization.L(L10n.Mods.disableAllConfirm),
            isPresented: Binding(
                get: { bulkToggleTarget != nil },
                set: { if !$0 { bulkToggleTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(bulkToggleTarget == true
                   ? localization.L(L10n.Mods.enableAll)
                   : localization.L(L10n.Mods.disableAll),
                   role: .destructive) {
                if let target = bulkToggleTarget {
                    vm.toggleAllMods(enable: target)
                }
                bulkToggleTarget = nil
            }
            Button(localization.L(L10n.Saves.cancel), role: .cancel) {
                bulkToggleTarget = nil
            }
        } message: {
            // Le compte dit la portée réelle — celle du cadrage courant, pas
            // du parc entier (X57). C'est lui qui rend « Tout » lisible :
            // filtrer sur une catégorie puis « Tout désactiver » annonce les
            // mods de cette catégorie, tous confondus sinon.
            let count = display.filter { $0.isEnabled != (bulkToggleTarget ?? true) }.count
            Text(String(format: localization.L(bulkToggleTarget == true
                 ? L10n.Mods.enableAllMessage
                 : L10n.Mods.disableAllMessage), count))
        }
    }

    /// Placeholder shown when the current scope has no mods to display
    /// (e.g. "Disabled" selected but every mod is enabled).
    private var emptyScopeMessage: some View {
        VStack(spacing: AppDesign.Spacing.md) {
            Image(systemName: "checkmark.seal")
                .font(AppDesign.Font.emptyScopeGlyph)
                .foregroundColor(.secondary.opacity(AppDesign.Opacity.disabled))
            Text(localization.L(filters.scope == .enabled
                      ? L10n.Mods.disabled
                      : L10n.Mods.enabled))
                .font(AppDesign.Font.rowTitle)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    /// Placeholder shown when the "Issues" scope has no problematic mods.
    private var noIssuesMessage: some View {
        VStack(spacing: AppDesign.Spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(AppDesign.Font.emptyScopeGlyph)
                .foregroundColor(.green.opacity(0.6))
            Text(localization.L(L10n.Mods.filterIssues))
                .font(AppDesign.Font.rowTitle)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    /// Prev/Next navigation + numbered page buttons shown below the mod list
    /// when the result set spans more than one page. Takes the already-computed
    /// total/shown/page/totalPages from `body` instead of re-deriving them.
    ///
    /// Shows up to 7 page slots with smart ellipsis: first, last, current,
    /// and neighbors — so the user can jump visually without typing.
    private func paginationFooter(total: Int, shown: Int, page: Int, totalPages: Int) -> some View {
        let rangeStart = (page - 1) * pageSize + 1
        let rangeEnd = rangeStart + shown - 1
        return VStack(spacing: AppDesign.Spacing.sm) {
            HStack(spacing: 6) {
                Button {
                    if filters.page > 1 { listState.filters.page -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(AppDesign.Font.iconXS(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(filters.page == 1)
                .help(localization.L(L10n.Mods.prevPageHint))

                // Numbered page buttons with ellipsis logic.
                ForEach(Array(pageSlots(current: page, total: totalPages).enumerated()), id: \.offset) { _, slot in
                    switch slot {
                    case .ellipsis:
                        Text("…")
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary.opacity(0.6))
                            .frame(width: 24)
                    case .page(let n):
                        Button {
                            listState.filters.page = n
                        } label: {
                            Text("\(n)")
                                .font(AppDesign.Font.caption(n == page ? .semibold : .regular))
                                .foregroundColor(n == page ? .white : .primary)
                                .frame(width: 24, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(n == page ? Color.accentColor : Color.secondary.opacity(0.08))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .pointingHandCursor()
                    }
                }

                Button {
                    if filters.page < totalPages { listState.filters.page += 1 }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(AppDesign.Font.iconXS(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(filters.page == totalPages)
                .help(localization.L(L10n.Mods.nextPageHint))
            }

            Text(String(format: localization.L(L10n.Mods.pageShowing), rangeStart, rangeEnd, total))
                .font(AppDesign.Font.iconXS)
                .foregroundColor(.secondary.opacity(AppDesign.Opacity.secondary))
        }
        .padding(.top, 4)
    }

    /// Builds the list of page-number slots to render. Always includes first,
    /// last, current, and the current's immediate neighbors; collapses the
    /// middle with `.ellipsis` when the total exceeds 7 slots. The enum makes
    /// it impossible for an ellipsis to collide with a page number.
    private func pageSlots(current: Int, total: Int) -> [PageSlot] {
        if total <= 7 {
            return (1...total).map { .page($0) }
        }
        var slots: [PageSlot] = [.page(1)]
        let lower = max(2, current - 1)
        let upper = min(total - 1, current + 1)
        if lower > 2 { slots.append(.ellipsis) }
        slots.append(contentsOf: (lower...upper).map { .page($0) })
        if upper < total - 1 { slots.append(.ellipsis) }
        slots.append(.page(total))
        return slots
    }

    /// Dropdown choosing how the mods list is ordered. `.name` mirrors the
    /// list's default (already-alphabetical) order; `.activationOrder`
    /// sorts by `vm.modActivationTimestamps`; `.installDate` sorts by
    /// `installedFileDate` (folder mod date), most recent first.
    /// `sortItem` shows a checkmark on the currently active option so the
    /// user can see which sort is applied without scanning the chip label.
    /// Ce que pèse le cadrage courant — « 12,7 Go dans ce cadrage ».
    ///
    /// C'est ce qui rend le tri par poids utilisable comme un outil : cadrer
    /// sur les mods en pause et lire le total répond à « combien y a-t-il à
    /// récupérer », sans additionner les lignes soi-même. Sur le parc réel,
    /// ce cadrage-là annonce 12,71 Go.
    ///
    /// Placé dans la barre d'outils et non dans le pied de pagination : ce
    /// dernier ne s'affiche qu'à partir de deux pages, et disparaîtrait donc
    /// juste au moment où un filtre resserré rend le total le plus parlant.
    ///
    /// Somme le cadrage **entier**, pas la page affichée. `vm.scanStore.mods` ne porte
    /// que des mods de premier niveau et des en-têtes de pack, jamais de
    /// composant : chaque ligne comptée a bien un poids à elle.
    ///
    /// Sans aucun filtre, ce total peut rester **légèrement sous** celui du
    /// pied de barre latérale, et c'est correct : le pied pèse tout ce que
    /// contient `Mods/`, la liste ne montre que les dossiers portant un
    /// `manifest.json`. Sur le parc réel l'écart vaut 60 Mo sur 16,84 Go —
    /// cinq dossiers d'outils déposés là, qui occupent bien la place sans
    /// être des mods. Les deux chiffres répondent à deux questions : ce que
    /// pèse le dossier, et ce que pèse ce qu'on regarde.
    @ViewBuilder
    private func scopeWeightLabel(for display: [ModItem]) -> some View {
        let total = display.compactMap { vm.sizeOnDisk(of: $0) }.reduce(Int64(0), +)
        if total > 0 {
            HStack(spacing: 3) {
                Image(systemName: "internaldrive")
                    .font(AppDesign.Font.iconXXS)
                Text(String(format: localization.L(L10n.Mods.pageWeight),
                            ByteCountFormatter.string(fromByteCount: total, countStyle: .file)))
                    .font(AppDesign.Font.footnote)
            }
            .foregroundColor(.secondary.opacity(AppDesign.Opacity.secondary))
        }
    }

    /// Full-screen overlay shown while a bulk enable/disable-all operation is
    /// moving mod folders. Blocks all interaction with the list so the user
    /// can't start a conflicting toggle mid-operation. Shows a determinate
    /// progress bar with the current/total count.
    private func bulkToggleOverlay(done: Int, total: Int) -> some View {
        ModalProgressOverlay(
            label: vm.bulkToggleEnabling
                ? localization.L(L10n.Mods.enablingAllProgress)
                : localization.L(L10n.Mods.disablingAllProgress),
            done: done,
            total: total)
    }

    /// Menu offering to enable or disable the framed mods at once. Each entry
    /// is disabled individually when the **current framing** (search, category,
    /// translation, scope — the same rule `toggleAllMods` applies, X57) has
    /// nothing to move in that direction, so an available entry says exactly
    /// what would move, and the user sees why an action isn't available
    /// rather than a dead button.
    ///
    /// Takes the scoped list computed once per render by `body` (`display`)
    /// rather than re-deriving it : the rule is the ViewModel's, the menu
    /// only reads its result.
    private func bulkToggleMenu(scoped: [ModItem]) -> some View {
        let anyDisabled = scoped.contains { !$0.isEnabled }
        let anyEnabled = scoped.contains { $0.isEnabled }
        return Menu {
            Button {
                bulkToggleTarget = true
            } label: {
                Label(localization.L(L10n.Mods.enableAll), systemImage: "checkmark.circle")
            }
            .disabled(!anyDisabled)

            Button {
                bulkToggleTarget = false
            } label: {
                Label(localization.L(L10n.Mods.disableAll), systemImage: "xmark.circle")
            }
            .disabled(!anyEnabled)
        } label: {
            Label(localization.L(L10n.Mods.toggleAllHint), systemImage: "power")
                .labelStyle(.iconOnly)
                .font(AppDesign.Font.body)
        }
        .help(localization.L(L10n.Mods.toggleAllHint))
    }
}
