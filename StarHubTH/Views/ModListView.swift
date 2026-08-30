import SwiftUI

/// Scope filter for the mods list.
enum ModFilter: String, CaseIterable, Identifiable {
    case all, enabled, disabled, issues
    var id: String { rawValue }
}

/// Three-state French-translation filter: off (all mods), only mods that ship
/// an `fr` i18n file, or only mods that don't. Matches `ModItem.languages`
/// (lowercased codes from the mod's `i18n/` folder).
enum FrenchTranslationScope: Equatable {
    case off
    case available   // ships an i18n/fr.json
    /// Traduit, mais pas entièrement — ceux sur lesquels il reste à faire.
    /// Sur le parc, 31 mods contre 392 complets : sans ce cadrage ils sont
    /// introuvables.
    case partial
    case missing     // translatable, but ships no i18n/fr.json
    /// Traduit, mais l'anglais a bougé depuis — par la date du fichier ou par
    /// une clé dont la référence ne correspond plus. 18 mods du parc au premier
    /// lancement, sans qu'aucun diff ait été ouvert.
    case stale
}

/// Scope for the category-filter menu: show everything, scope to one Nexus
/// category, or scope to mods with no category assigned. A single enum
/// (rather than `NexusCategory?` plus a separate boolean) keeps these three
/// states mutually exclusive by construction.
enum CategoryScope: Equatable {
    case all
    case category(NexusCategory)
    case inferredTag(String)   // stable inferTag key, for mods with no Nexus category
    case uncategorized         // mods with no Nexus category whose inferred tag is "Other"
}

/// Sort order for the mods list. `.name` matches `vm.mods`'s existing
/// alphabetical order (so no extra sort is needed for it); `.activationOrder`
/// sorts by `vm.modActivationTimestamps`, most recent first; `.installDate`
/// sorts by `installedFileDate` (folder mod date), most recent first.
enum ModSortOrder: String, CaseIterable, Identifiable {
    case name, nameDescending, activationOrder, installDate, author, version, size
    var id: String { rawValue }
}

/// A single slot in the pagination footer: either a numbered page button or
/// an ellipsis gap. Using an enum (instead of a sentinel like `-1`) makes it
/// impossible for an ellipsis to collide with a page number identity, which
/// would crash SwiftUI if duplicate `id` values appeared in `ForEach`.
private enum PageSlot {
    case page(Int)
    case ellipsis
}

struct ModListView: View {
    @ObservedObject var vm: StarHubTHViewModel
    /// L'onglet affiché, pour les rares endroits d'où la liste **mène
    /// ailleurs** (le badge de profil actif). Même patron que
    /// `ModProfilesView`, `UpdatesView` et `SystemAlertsView`.
    @Binding var currentTab: String
    /// Le cadrage de la liste, observé **à part** du ViewModel pour que taper
    /// dans la recherche ne redessine pas toute la fenêtre — voir `ModListState`.
    @ObservedObject private var listState: ModListState

    init(vm: StarHubTHViewModel, currentTab: Binding<String>) {
        self.vm = vm
        self.listState = vm.modList
        self._currentTab = currentTab
    }

    /// Lecture seule du cadrage courant (recherche, filtres, tri, page). Les
    /// écritures passent par `listState.filters` en clair, pour qu'on voie au
    /// premier coup d'œil ce qui modifie un état partagé.
    private var filters: ModListFilters { listState.filters }
    /// Number of mods rendered per page. Tuned so the list stays responsive
    /// even with several hundred installed mods.
    private let pageSize: Int = 15
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

    /// Whether `mod` itself satisfies `predicate`, or — for a group — any of
    /// its children do. Standalone mods just apply the predicate directly.
    /// The single "does this row match X" test shared by search and the
    /// issues filter, so the two can't independently drift out of sync (a
    /// group's own `dependencies`/`uniqueId` are empty, so checking the
    /// group itself before its children is always safe and often a no-op).
    private func matchesSelfOrAnyChild(_ mod: ModItem, _ predicate: (ModItem) -> Bool) -> Bool {
        if predicate(mod) { return true }
        if mod.isGroup, let children = mod.children {
            return children.contains(where: predicate)
        }
        return false
    }

    /// Whether `mod` is enabled and has at least one problematic required
    /// dependency (missing entirely, or installed but disabled). A disabled
    /// mod isn't currently relying on its dependencies, so it's excluded
    /// even if one is missing/disabled. Shared by `modsWithIssues` and
    /// `scopeCounts` so their notion of "has issues" can't drift apart.
    /// Délègue au ViewModel : la pastille d'anomalie s'appuie sur la même
    /// règle, et deux définitions de « ce mod a un problème » divergeraient.
    /// **La même règle que la pastille, désormais.** Elle ne l'était pas : le
    /// cadrage ne regardait que les dépendances quand la pastille couvrait
    /// aussi les erreurs du journal et les manifestes sans identifiant — un mod
    /// portant une pastille pouvait manquer à l'onglet censé les réunir.
    /// Mesuré avant de les réunir : sur les versions installées du parc, cela
    /// n'ajoute qu'une erreur et cinq avertissements.
    private func hasIssues(_ mod: ModItem) -> Bool { vm.anomaly(for: mod) != nil }

    /// Scopes the list to the mod the user asked to jump to, clearing anything
    /// that could filter it out, then clears the request so it fires once.
    private func consumePendingModFocus() {
        guard let modName = vm.pendingModFocus else { return }
        // Prefer the resolved mod's own name: SMAPI logs a display name that can
        // differ from the manifest, and the search matches on name/uniqueId.
        // The request may also carry a folder name (the guided search works in
        // those) — `ModFocusResolver` accepts either.
        let resolved = ModFocusResolver.resolve(modName, in: vm.mods)
        listState.filters.focus(on: resolved?.name ?? modName)
        vm.pendingModFocus = nil
    }

    // MARK: - Les prédicats de cadrage
    //
    // Un filtre, une fonction. `filteredMods` les compose pour la liste ; les
    // menus les recomposent **en laissant tomber le leur** pour compter ce que
    // la vue active contient. Deux pipelines jumeaux auraient divergé à la
    // première retouche — le dépôt l'a déjà payé ailleurs.

    private func matchesSearch(_ mod: ModItem) -> Bool {
        filters.search.isEmpty || matchesSelfOrAnyChild(mod) {
            $0.name.localizedCaseInsensitiveContains(filters.search) || $0.uniqueId.localizedCaseInsensitiveContains(filters.search)
        }
    }

    private func matchesCategory(_ mod: ModItem) -> Bool {
        switch filters.category {
        case .all:
            return true
        case .category(let cat):
            // `vm.category(for:)` already resolves a group to its
            // dominant child category, so this agrees with the badge
            // shown on the group's own row by construction.
            return vm.category(for: mod)?.id == cat.id
        case .inferredTag(let tag):
            return vm.category(for: mod) == nil && vm.inferredTagKey(for: mod) == tag
        case .uncategorized:
            // Same reasoning: `vm.category(for:)` returns nil for a
            // group exactly when none of its children have a known
            // category, matching what its badge (absence) shows.
            return vm.category(for: mod) == nil && vm.inferredTagKey(for: mod) == "Other"
        }
    }

    private func matchesConfig(_ mod: ModItem) -> Bool {
        !filters.configOnly || matchesSelfOrAnyChild(mod) { $0.hasConfigFile }
    }

    /// Le favori se marque sur la ligne de premier niveau, donc se teste sur
    /// elle : un pack est favori pour lui-même, pas par l'un de ses composants.
    private func matchesFavorites(_ mod: ModItem) -> Bool {
        !filters.favoritesOnly || vm.isFavorite(mod)
    }

    private func matchesTranslation(_ mod: ModItem, _ scope: FrenchTranslationScope) -> Bool {
        switch scope {
        case .off:
            return true
        case .available:
            // A group matches if any child ships an fr translation.
            return matchesSelfOrAnyChild(mod) { $0.languages.contains("fr") }
        case .partial:
            // Ne montre que les mods **déjà mesurés** : la couverture
            // se calcule en tâche de fond, et annoncer « complet » sur
            // un mod qu'on n'a pas encore lu serait faux. La liste se
            // complète donc à mesure que le calcul avance.
            return matchesSelfOrAnyChild(mod) { child in
                guard let coverage = vm.frenchCoverage(for: child) else { return false }
                return coverage < 100
            }
        case .missing:
            // « Pas de français » ne veut rien dire d'un mod qui n'a
            // aucun `i18n` : il n'a pas de texte à traduire, et l'y
            // faire figurer noyait le filtre. Mesuré sur le parc : 397
            // mods sans français, dont **310 sans le moindre fichier de
            // traduction**. Le filtre servait à trouver ce qu'on
            // pourrait traduire ; il rendait 8 fois plus de bruit que de
            // signal.
            //
            // `languages` porte `en` dès qu'un `default.json` existe :
            // un mod traduisible en a donc au moins un.
            let translatable = matchesSelfOrAnyChild(mod) { !$0.languages.isEmpty }
            return translatable
                && !matchesSelfOrAnyChild(mod) { $0.languages.contains("fr") }
        case .stale:
            // Les deux signaux réunis : la date, connue de tous les
            // mods dès le scan, et les clés, connues des seuls mods
            // dont on a déjà ouvert le diff.
            return matchesSelfOrAnyChild(mod) { child in
                vm.staleTranslationMods.contains(child.folderName)
                    || vm.outdatedKeyCount(for: child) > 0
            }
        }
    }

    var filteredMods: [ModItem] {
        vm.mods
            .filter { mod in
                matchesSearch(mod)
                    && matchesCategory(mod)
                    && matchesConfig(mod)
                    && matchesFavorites(mod)
                    && matchesTranslation(mod, filters.frenchTranslation)
            }
            .sorted { lhs, rhs in
                switch filters.sort {
                case .name:
                    // `vm.mods` is already alphabetical (see `scanMods()`),
                    // and `.sorted` is stable, so this is a no-op ordering
                    // pass — kept as an explicit case so the switch stays
                    // exhaustive and self-documenting.
                    return false
                case .activationOrder:
                    let lhsDate = vm.modActivationTimestamps[lhs.folderName]
                    let rhsDate = vm.modActivationTimestamps[rhs.folderName]
                    switch (lhsDate, rhsDate) {
                    case (let l?, let r?):
                        return l > r
                    case (.some, nil):
                        return true
                    case (nil, .some):
                        return false
                    case (nil, nil):
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                case .installDate:
                    let lhsDate = lhs.effectiveInstallDate
                    let rhsDate = rhs.effectiveInstallDate
                    switch (lhsDate, rhsDate) {
                    case (let l?, let r?):
                        return l > r
                    case (.some, nil):
                        return true
                    case (nil, .some):
                        return false
                    case (nil, nil):
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                case .nameDescending:
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
                case .author:
                    let authorOrder = lhs.author.localizedCaseInsensitiveCompare(rhs.author)
                    if authorOrder != .orderedSame { return authorOrder == .orderedAscending }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                case .version:
                    let versionOrder = NexusUpdateChecker.compare(lhs.version, rhs.version)
                    if versionOrder != .orderedSame { return versionOrder == .orderedDescending }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                case .size:
                    // Le plus lourd d'abord : c'est le sens dans lequel on
                    // cherche. Les non mesurés ferment la marche, par nom —
                    // et ils sont nombreux par construction : rien n'est
                    // mesuré tant que la première passe n'a pas abouti, ni
                    // pendant les secondes qui suivent une bascule.
                    switch (vm.sizeOnDisk(of: lhs), vm.sizeOnDisk(of: rhs)) {
                    case (let l?, let r?):
                        if l != r { return l > r }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    case (.some, nil):
                        return true
                    case (nil, .some):
                        return false
                    case (nil, nil):
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                }
            }
    }

    func activeMods(from filtered: [ModItem]) -> [ModItem] { filtered.filter { $0.isEnabled } }
    func inactiveMods(from filtered: [ModItem]) -> [ModItem] { filtered.filter { !$0.isEnabled } }

    /// Enabled mods (or packs containing an enabled child) with at least one
    /// problematic required dependency — either completely missing or
    /// installed-but-disabled. A disabled mod isn't currently relying on its
    /// dependencies, so it's excluded even if one is missing/disabled. Packs
    /// (groups) appear if any enabled child matches.
    func modsWithIssues(from filtered: [ModItem]) -> [ModItem] {
        filtered.filter { matchesSelfOrAnyChild($0, hasIssues) }
    }

    /// The full ordered list of mods that should be displayed under the current
    /// scope (search + category + enabled/disabled filter). Pagination slices
    /// this list; the scope section headers (Enabled/Disabled) are derived from
    /// each page's slice.
    ///
    /// Takes `filtered` (rather than re-deriving it) so callers that already
    /// computed it once per render don't trigger the search/category/sort
    /// pass again.
    private func displayMods(from filtered: [ModItem]) -> [ModItem] {
        switch filters.scope {
        // **Pas** de partition actifs/en pause : le cadrage « Tous » rend
        // l'ordre du tri tel quel. Grouper d'abord par état écrasait le tri
        // choisi — trier par poids remontait le plus gros mod *actif*, jamais
        // le plus gros du parc, alors que les trois quarts du poids dorment
        // dans des mods en pause. L'état reste lisible ligne à ligne : barre
        // d'accent verte ou grise, et le point à côté du nom.
        case .all:      return filtered
        case .enabled:  return activeMods(from: filtered)
        case .disabled: return inactiveMods(from: filtered)
        case .issues:   return modsWithIssues(from: filtered)
        }
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
        let scoped = displayMods(from: vm.mods.filter { mod in
            matchesSearch(mod) && matchesConfig(mod) && matchesFavorites(mod)
        })
        return (category: scoped.filter { matchesTranslation($0, filters.frenchTranslation) },
                translation: scoped.filter { matchesCategory($0) })
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
            .sorted { $0.category.localizedName(vm.L)
                .localizedCaseInsensitiveCompare($1.category.localizedName(vm.L)) == .orderedAscending }
    }

    /// (tag key, localized label, count) for top-level mods with no Nexus
    /// category and a non-"Other" inferred tag — the offline fallback buckets.
    private func inferredTagBuckets(from base: [ModItem]) -> [(tag: String, label: String, count: Int)] {
        var counts: [String: Int] = [:]
        for mod in base where vm.category(for: mod) == nil {
            let tag = vm.inferredTagKey(for: mod)
            if tag != "Other" { counts[tag, default: 0] += 1 }
        }
        return counts.map { (tag: $0.key, label: vm.L(L10n.ModTag.key(for: $0.key)), count: $0.value) }
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
    /// over `filtered`. Avoids recomputing `modsWithIssues` (which does a
    /// per-mod dependency scan) every time the Picker label is evaluated.
    /// `issues` mirrors `modsWithIssues`'s enabled-only rule (see its doc).
    private func scopeCounts(for filtered: [ModItem]) -> (all: Int, enabled: Int, disabled: Int, issues: Int) {
        var enabled = 0, disabled = 0, issues = 0
        for mod in filtered {
            if mod.isEnabled { enabled += 1 } else { disabled += 1 }
            if matchesSelfOrAnyChild(mod, hasIssues) { issues += 1 }
        }
        return (filtered.count, enabled, disabled, issues)
    }

    /// Le titre de la section courante — les quatre scopes ne diffèrent que
    /// par lui. La liste et la grille le partagent : le scope actif se lit
    /// de la même façon dans les deux denses (P2).
    private var scopeSectionTitle: String {
        switch filters.scope {
        case .all: return vm.L(L10n.Mods.filterAll)
        case .enabled: return vm.L(L10n.Mods.enabled)
        case .disabled: return vm.L(L10n.Mods.disabled)
        case .issues: return vm.L(L10n.Mods.filterIssues)
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
            attributes.append(CardAttribute(id: "profileConfig",
                                            systemImage: "slider.horizontal.3",
                                            help: vm.L(L10n.Mods.profileConfigBadge)))
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
                        Text("\(vm.L(L10n.Mods.filterAll)) (\(counts.all))")
                            .tag(ModFilter.all)
                        Text("\(vm.L(L10n.Mods.enabled)) (\(counts.enabled))")
                            .tag(ModFilter.enabled)
                        Text("\(vm.L(L10n.Mods.disabled)) (\(counts.disabled))")
                            .tag(ModFilter.disabled)
                        Label("\(vm.L(L10n.Mods.filterIssues)) (\(counts.issues))",
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
                        TextField(vm.L(L10n.Mods.searchMods),
                                  text: $listState.filters.search)
                            .textFieldStyle(.plain)
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
                            .help(vm.L(L10n.Discovery.clearSearch))
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
                    Picker(vm.L(L10n.Mods.layoutList), selection: $listLayout) {
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
                          ? vm.L(L10n.Mods.layoutList)
                          : vm.L(L10n.Mods.layoutGrid))

                    // Bulk enable/disable all mods at once. Disabled when
                    // there is nothing to act on (empty list, or every mod
                    // is already in the target state), or while a bulk
                    // toggle operation is already in flight.
                    bulkToggleMenu
                        .disabled(vm.mods.isEmpty || vm.bulkToggleProgress != nil)

                    Button {
                        showInstallSheet = true
                    } label: {
                        Label(vm.L(L10n.ModInstall.installButton), systemImage: "plus.circle")
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

                    Divider()
                        .frame(height: 16)

                    frenchTranslationPicker(counts: translationCounts)

                    categoryPicker(categories: categories, uncatCount: uncatCount, tagBuckets: tagBuckets)
                        .disabled(categories.isEmpty && uncatCount == 0 && tagBuckets.isEmpty)
                        .help(categories.isEmpty && uncatCount == 0 && tagBuckets.isEmpty
                              ? vm.L(L10n.Mods.categoryFilterEmptyHint)
                              : vm.L(L10n.Mods.categoryFilterHint))

                    Spacer()

                    scopeWeightLabel(for: display)

                    if categories.isEmpty && uncatCount == 0 && tagBuckets.isEmpty {
                        Text(vm.L(L10n.Mods.categoryFilterEmptyHint))
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary.opacity(AppDesign.Opacity.secondary))
                    }

                    // Le profil appliqué — et le chemin vers la page qui le
                    // gère : c'est là qu'on va quand on le lit ici.
                    if let profile = vm.activeProfile {
                        Button {
                            currentTab = "Profiles"
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "person.crop.circle")
                                    .font(AppDesign.Font.footnote)
                                Text(String(format: vm.L(L10n.Profiles.activeLabel), profile.name))
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
                        .help(vm.L(L10n.Profiles.title))
                        .accessibilityLabel(String(format: vm.L(L10n.Profiles.activeLabel), profile.name))
                        .accessibilityHint(vm.L(L10n.Profiles.title))
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
                        if vm.mods.isEmpty {
                            // Première utilisation : zone de drop XXL
                            EmptyStateDropZone(vm: vm, onInstall: { showInstallSheet = true })
                                .padding(.top, 40)
                        } else {
                            // Recherche sans résultat
                            VStack(spacing: AppDesign.Spacing.lg) {
                                Image(systemName: "puzzlepiece.extension")
                                    .font(AppDesign.Font.emptyStateGlyph)
                                    .foregroundColor(.secondary.opacity(AppDesign.Opacity.disabled))
                                Text(String(format: vm.L(L10n.Mods.noModFound), filters.search))
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
                            ModSectionGroup(title: scopeSectionTitle, mods: paged, vm: vm)
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
                                            versionPrefix: vm.L(L10n.Mods.versionPrefix),
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
                                                installedLabel: vm.L(active
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
                                                L: vm.L,
                                                action: { vm.viewingModDetail = mod })
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
        .onChange(of: vm.mods.count)    { _, _ in listState.filters.page = 1 }
        // Clicking a mod name in the logs must land on that mod, not on the full
        // list. `selectedModID` alone only tints the row — with filters and
        // pagination the mod may not even be on the visible page — so scope the
        // list to it and clear anything that could filter it out.
        // A jump request can arrive before this view exists (from the Logs tab),
        // so it's read on appear as well as while already on screen.
        .onAppear { consumePendingModFocus() }
        .onChange(of: vm.pendingModFocus) { _, _ in consumePendingModFocus() }
        .sheet(isPresented: $showInstallSheet) {
            ModInstallView(vm: vm, isPresented: $showInstallSheet)
        }
        .confirmationDialog(
            bulkToggleTarget == true
                ? vm.L(L10n.Mods.enableAllConfirm)
                : vm.L(L10n.Mods.disableAllConfirm),
            isPresented: Binding(
                get: { bulkToggleTarget != nil },
                set: { if !$0 { bulkToggleTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(bulkToggleTarget == true
                   ? vm.L(L10n.Mods.enableAll)
                   : vm.L(L10n.Mods.disableAll),
                   role: .destructive) {
                if let target = bulkToggleTarget {
                    vm.toggleAllMods(enable: target)
                }
                bulkToggleTarget = nil
            }
            Button(vm.L(L10n.Saves.cancel), role: .cancel) {
                bulkToggleTarget = nil
            }
        } message: {
            Text(bulkToggleTarget == true
                 ? vm.L(L10n.Mods.enableAllMessage)
                 : vm.L(L10n.Mods.disableAllMessage))
        }
    }

    /// Placeholder shown when the current scope has no mods to display
    /// (e.g. "Disabled" selected but every mod is enabled).
    private var emptyScopeMessage: some View {
        VStack(spacing: AppDesign.Spacing.md) {
            Image(systemName: "checkmark.seal")
                .font(AppDesign.Font.emptyScopeGlyph)
                .foregroundColor(.secondary.opacity(AppDesign.Opacity.disabled))
            Text(vm.L(filters.scope == .enabled
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
            Text(vm.L(L10n.Mods.filterIssues))
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
                .help(vm.L(L10n.Mods.prevPageHint))

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
                .help(vm.L(L10n.Mods.nextPageHint))
            }

            Text(String(format: vm.L(L10n.Mods.pageShowing), rangeStart, rangeEnd, total))
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
    /// Somme le cadrage **entier**, pas la page affichée. `vm.mods` ne porte
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
                Text(String(format: vm.L(L10n.Mods.pageWeight),
                            ByteCountFormatter.string(fromByteCount: total, countStyle: .file)))
                    .font(AppDesign.Font.footnote)
            }
            .foregroundColor(.secondary.opacity(AppDesign.Opacity.secondary))
        }
    }

    @ViewBuilder
    /// Un tri du menu. L'icône **ne se remplace pas** par une coche quand le
    /// tri est actif : le bouton du menu affiche déjà le libellé du tri en
    /// cours (`sortLabel`), donc la coche ne disait rien de plus — elle
    /// effaçait juste l'icône, et l'entrée par défaut (« Nom (A-Z) ») en
    /// paraissait dépourvue.
    private func sortItem(_ order: ModSortOrder, label: String, icon: String) -> some View {
        Button {
            listState.filters.sort = order
        } label: {
            Label(vm.L(label), systemImage: icon)
        }
    }

    /// Une option du menu traduction, avec son compte dans la vue active.
    ///
    /// Le compte, et rien d'autre : l'entrée ne s'éteint pas à zéro. « À
    /// revoir » et « Partiellement traduits » se lisent dans des mesures qui
    /// se font en tâche de fond — au lancement elles valent zéro pour un
    /// moment, et une entrée grisée aurait dit « il n'y en a pas » là où il
    /// fallait lire « pas encore compté ».
    private func translationItem(_ scope: FrenchTranslationScope,
                                 label: String,
                                 icon: String,
                                 count: Int) -> some View {
        Button {
            listState.filters.frenchTranslation = scope
        } label: {
            Label("\(vm.L(label)) (\(count))", systemImage: icon)
        }
    }

    private var sortPicker: some View {
        Menu {
            // `arrow.up`/`arrow.down` et non la paire
            // `arrow.up.arrow.down`/`arrow.down.arrow.up` : la seconde
            // **n'existe pas** sur macOS 26 (vérifié par
            // `NSImage(systemSymbolName:)`), et un symbole absent ne dessine
            // rien — l'entrée paraissait sans icône.
            sortItem(.name, label: L10n.Mods.sortName, icon: "arrow.up")
            sortItem(.nameDescending, label: L10n.Mods.sortNameDescending, icon: "arrow.down")
            sortItem(.activationOrder, label: L10n.Mods.sortActivationOrder, icon: "clock.arrow.circlepath")
            sortItem(.installDate, label: L10n.Mods.sortInstallDate, icon: "calendar")
            sortItem(.author, label: L10n.Mods.sortAuthor, icon: "person.fill")
            sortItem(.version, label: L10n.Mods.sortVersion, icon: "tag")
            sortItem(.size, label: L10n.Mods.sortSize, icon: "internaldrive")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(AppDesign.Font.footnote)
                Text(sortLabel)
                    .font(AppDesign.Font.caption(.medium))
                Image(systemName: "chevron.down")
                    .font(AppDesign.Font.iconXXS(.bold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .fill(Color.secondary.opacity(AppDesign.Opacity.light))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .stroke(Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var sortLabel: String {
        switch filters.sort {
        case .name: return vm.L(L10n.Mods.sortName)
        case .nameDescending: return vm.L(L10n.Mods.sortNameDescending)
        case .activationOrder: return vm.L(L10n.Mods.sortActivationOrder)
        case .installDate: return vm.L(L10n.Mods.sortInstallDate)
        case .author: return vm.L(L10n.Mods.sortAuthor)
        case .version: return vm.L(L10n.Mods.sortVersion)
        case .size: return vm.L(L10n.Mods.sortSize)
        }
    }

    // MARK: - Config-only filter toggle

    /// Toggle button scoping the list to mods with a `config.json` (see
    /// `filters.configOnly`). Same visual family as `sortPicker`/
    /// `categoryPicker` (rounded chip, same padding/font), but a plain
    /// toggle rather than a menu — there's only one on/off state, not a
    /// set of choices.
    private var configFilterToggle: some View {
        Button {
            listState.filters.configOnly.toggle()
        } label: {
            // Le glyph seul : le libellé vit à l'infobulle. La cible reste
            // large (10/5 de marge autour d'un glyph de 11 pt), bien au-delà
            // du 18×18 qu'exige une infobulle vivante.
            Image(systemName: "gearshape")
                .font(AppDesign.Font.footnote)
                .foregroundColor(filters.configOnly ? Color.accentColor : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                        .fill(filters.configOnly ? Color.accentColor.opacity(AppDesign.Opacity.medium) : Color.secondary.opacity(AppDesign.Opacity.light))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                        .stroke(filters.configOnly ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .help(vm.L(L10n.Mods.configFilterLabel))
        // Sans texte visible, l'infobulle ne suffit pas : VoiceOver n'a plus
        // que ce libellé.
        .accessibilityLabel(vm.L(L10n.Mods.configFilterLabel))
    }

    // MARK: - Favourites filter toggle (B3-T2)

    /// Cadre la liste sur les mods marqués d'une étoile. Même famille visuelle
    /// que `configFilterToggle`.
    ///
    /// Une pastille de plus dans une barre qui en portait déjà cinq, et c'est
    /// justifié ici alors que le poids s'en est passé (B2-T9) : le poids se
    /// cadrait par « en pause » + tri, les favoris n'ont aucun équivalent. Sans
    /// ce cadrage, un jeu de favoris se perdrait dans 36 pages de liste.
    ///
    /// Quand rien n'est marqué, la pastille dit **où** marquer plutôt que de
    /// mener à une liste vide.
    private var favoritesFilterToggle: some View {
        let active = filters.favoritesOnly
        let empty = vm.favoriteMods.isEmpty
        return Button {
            listState.filters.favoritesOnly.toggle()
        } label: {
            // Le libellé passe à l'infobulle ; le **compte** reste, lui : il
            // ne se lit nulle part ailleurs dans la barre.
            //
            // Sauf quand rien n'est marqué : la pastille est alors *désactivée*,
            // et l'infobulle d'un contrôle désactivé ne se montre pas toujours
            // sur macOS. Réduite à une étoile grise, elle ne dirait plus rien —
            // elle garde donc son libellé dans ce seul état, celui où elle a
            // justement quelque chose à expliquer.
            HStack(spacing: 4) {
                Image(systemName: active ? "star.fill" : "star")
                    .font(AppDesign.Font.footnote)
                if empty {
                    Text(vm.L(L10n.Mods.filterFavorites))
                        .font(AppDesign.Font.caption(.medium))
                } else {
                    Text("\(vm.favoriteMods.count)")
                        .font(AppDesign.Font.iconXS(.semibold).monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(active ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .fill(active ? Color.accentColor.opacity(AppDesign.Opacity.medium) : Color.secondary.opacity(AppDesign.Opacity.light))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .stroke(active ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(empty && !active)
        .help(vm.L(empty ? L10n.Mods.filterFavoritesEmptyHint : L10n.Mods.filterFavoritesHint))
        .accessibilityLabel(vm.L(L10n.Mods.filterFavorites))
        // Le compte est à l'écran : sans cette valeur, VoiceOver le perdrait
        // avec le libellé.
        .accessibilityValue(empty ? "" : "\(vm.favoriteMods.count)")
    }

    // MARK: - French-translation filter picker

    /// Three-state menu scoping the list to mods that ship (or don't ship) an
    /// `i18n/fr.json` translation file. Same chip visual family as the
    /// config-only toggle and the category picker.
    /// Combien de mods la vue active contient pour chaque état de traduction.
    /// Les options qui n'y mènent nulle part se **désactivent** — elles ne
    /// disparaissent pas : un menu dont les entrées vont et viennent ne se
    /// mémorise pas.
    private func frenchTranslationCounts(from base: [ModItem]) -> [FrenchTranslationScope: Int] {
        var counts: [FrenchTranslationScope: Int] = [:]
        for scope in [FrenchTranslationScope.available, .partial, .missing, .stale] {
            counts[scope] = base.filter { matchesTranslation($0, scope) }.count
        }
        return counts
    }

    private func frenchTranslationPicker(counts: [FrenchTranslationScope: Int]) -> some View {
        let isActive = filters.frenchTranslation != .off
        let label: String = {
            switch filters.frenchTranslation {
            case .off:       return vm.L(L10n.Mods.frTranslationFilterLabel)
            case .available: return vm.L(L10n.Mods.frTranslationAvailable)
            case .partial:   return vm.L(L10n.Mods.frTranslationPartial)
            case .missing:   return vm.L(L10n.Mods.frTranslationMissing)
            case .stale:     return vm.L(L10n.Mods.frTranslationStale)
            }
        }()
        let icon: String = {
            switch filters.frenchTranslation {
            case .off:       return "character.bubble"
            case .available: return "checkmark.bubble"
            case .partial:   return "ellipsis.bubble"
            // Le symbole `xmark` sur bulle n'existe pas sur macOS 26
            // (mesuré) : l'entrée « À traduire » n'affichait rien.
            case .missing:   return "exclamationmark.bubble"
            case .stale:     return "clock.badge.exclamationmark"
            }
        }()
        return Menu {
            Button {
                listState.filters.frenchTranslation = .off
            } label: {
                Label(vm.L(L10n.Mods.frTranslationFilterLabel), systemImage: "character.bubble")
            }
            translationItem(.available, label: L10n.Mods.frTranslationAvailable,
                            icon: "checkmark.bubble", count: counts[.available] ?? 0)
            translationItem(.partial, label: L10n.Mods.frTranslationPartial,
                            icon: "ellipsis.bubble", count: counts[.partial] ?? 0)
            translationItem(.missing, label: L10n.Mods.frTranslationMissing,
                            icon: "exclamationmark.bubble", count: counts[.missing] ?? 0)
            translationItem(.stale, label: L10n.Mods.frTranslationStale,
                            icon: "clock.badge.exclamationmark", count: counts[.stale] ?? 0)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(AppDesign.Font.footnote)
                Text(label)
                    .font(AppDesign.Font.caption(.medium))
                Image(systemName: "chevron.down")
                    .font(AppDesign.Font.iconXXS(.bold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(isActive ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .fill(isActive ? Color.accentColor.opacity(AppDesign.Opacity.medium) : Color.secondary.opacity(AppDesign.Opacity.light))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(vm.L(L10n.Mods.frTranslationFilterLabel))
    }

    /// Full-screen overlay shown while a bulk enable/disable-all operation is
    /// moving mod folders. Blocks all interaction with the list so the user
    /// can't start a conflicting toggle mid-operation. Shows a determinate
    /// progress bar with the current/total count.
    private func bulkToggleOverlay(done: Int, total: Int) -> some View {
        ModalProgressOverlay(
            label: vm.bulkToggleEnabling
                ? vm.L(L10n.Mods.enablingAllProgress)
                : vm.L(L10n.Mods.disablingAllProgress),
            done: done,
            total: total)
    }

    /// Menu offering to enable or disable every installed mod at once. Each
    /// entry is disabled individually when there is nothing to move in that
    /// direction (all already enabled / all already disabled), so the user
    /// sees why an action isn't available rather than a dead button.
    private var bulkToggleMenu: some View {
        let anyDisabled = vm.mods.contains { !$0.isEnabled }
        let anyEnabled = vm.mods.contains { $0.isEnabled }
        return Menu {
            Button {
                bulkToggleTarget = true
            } label: {
                Label(vm.L(L10n.Mods.enableAll), systemImage: "checkmark.circle")
            }
            .disabled(!anyDisabled)

            Button {
                bulkToggleTarget = false
            } label: {
                Label(vm.L(L10n.Mods.disableAll), systemImage: "xmark.circle")
            }
            .disabled(!anyEnabled)
        } label: {
            Label(vm.L(L10n.Mods.toggleAllHint), systemImage: "power")
                .labelStyle(.iconOnly)
                .font(AppDesign.Font.body)
        }
        .help(vm.L(L10n.Mods.toggleAllHint))
    }

    // MARK: - Category picker

    /// Dropdown listing every category present in the installed mods list.
    /// Selecting one scopes the list to that category; selecting "All" clears
    /// it. Each row shows the category color + localized name + mod count.
    private func categoryPicker(categories: [(category: NexusCategory, count: Int)], uncatCount: Int, tagBuckets: [(tag: String, label: String, count: Int)]) -> some View {
        Menu {
            Button {
                listState.filters.category = .all
            } label: {
                Label(vm.L(L10n.Mods.categoryFilterAll), systemImage: "square.grid.2x2")
            }
            if uncatCount > 0 {
                Button {
                    listState.filters.category = .uncategorized
                } label: {
                    Label("\(vm.L(L10n.Mods.categoryFilterUncategorized))   (\(uncatCount))", systemImage: "circle.dashed")
                }
            }
            if !categories.isEmpty {
                Divider()
            }
            ForEach(categories, id: \.category.id) { entry in
                Button {
                    listState.filters.category = .category(entry.category)
                } label: {
                    // SwiftUI Menus render Button labels as plain text — an
                    // HStack would only show its first child. Concatenating
                    // Text views (or building a single string) keeps both the
                    // icon and the category name visible in the row.
                    Text(entry.category.emoji + " " + entry.category.localizedName(vm.L) + "   (\(entry.count))")
                }
            }
            // Offline fallback: mods with no Nexus category, grouped by their
            // inferred type tag instead of a single "uncategorized" bucket.
            if !tagBuckets.isEmpty {
                Divider()
                ForEach(tagBuckets, id: \.tag) { bucket in
                    Button {
                        listState.filters.category = .inferredTag(bucket.tag)
                    } label: {
                        Text("\(bucket.label)   (\(bucket.count))")
                    }
                }
            }
            if filters.category != .all {
                Divider()
                Button(role: .destructive) {
                    listState.filters.category = .all
                } label: {
                    Label(vm.L(L10n.Mods.categoryFilterClear), systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: 6) {
                switch filters.category {
                case .all:
                    Image(systemName: "tag")
                        .font(AppDesign.Font.footnote)
                    Text(vm.L(L10n.Mods.categoryFilter))
                        .font(AppDesign.Font.caption(.medium))
                case .category(let cat):
                    Circle()
                        .fill(cat.color)
                        .frame(width: 9, height: 9)
                    Text(cat.localizedName(vm.L))
                        .font(AppDesign.Font.caption(.medium))
                case .inferredTag(let tag):
                    Image(systemName: "tag.circle")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                    Text(vm.L(L10n.ModTag.key(for: tag)))
                        .font(AppDesign.Font.caption(.medium))
                case .uncategorized:
                    Image(systemName: "circle.dashed")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                    Text(vm.L(L10n.Mods.categoryFilterUncategorized))
                        .font(AppDesign.Font.caption(.medium))
                }
                Image(systemName: "chevron.down")
                    .font(AppDesign.Font.iconXXS(.bold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .fill(Color.secondary.opacity(AppDesign.Opacity.light))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .stroke(Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

}

// MARK: - Section Group
struct ModSectionGroup: View {
    let title: String
    let mods: [ModItem]
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        StandardSection(title: title) {
            VStack(spacing: 0) {
                ForEach(Array(mods.enumerated()), id: \.element.id) { idx, mod in
                    if mod.isGroup, let children = mod.children {
                        ModGroupRow(mod: mod, children: children, vm: vm)
                    } else {
                        ModListRow(mod: mod, vm: vm, isChild: false, isGroupHeader: false, isExpanded: .constant(false))
                    }
                    
                    if idx < mods.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(AppDesign.Opacity.subtle))
                            .frame(height: 1)
                            .padding(.leading, 48)
                            .padding(.vertical, 2)
                    }
                }
            }
            .padding(.vertical, -8)
        }
    }
}

// MARK: - Mod Group Row
struct ModGroupRow: View {
    let mod: ModItem
    let children: [ModItem]
    @ObservedObject var vm: StarHubTHViewModel
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            ModListRow(mod: mod, vm: vm, isChild: false, isGroupHeader: true, isExpanded: $isExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { cIdx, child in
                        ModListRow(mod: child, vm: vm, isChild: true, isGroupHeader: false, isExpanded: .constant(false))
                        if cIdx < children.count - 1 {
                            Rectangle()
                                .fill(Color.primary.opacity(AppDesign.Opacity.subtle))
                                .frame(height: 1)
                                .padding(.leading, 64)
                                .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - Row
struct ModListRow: View {
    let mod: ModItem
    @ObservedObject var vm: StarHubTHViewModel
    @State private var isHovered = false
    var isChild: Bool = false
    var isGroupHeader: Bool = false
    @Binding var isExpanded: Bool
    @State private var localIsOn: Bool?
    /// Debounce du toggle : annule un toggle en attente si l'utilisateur
    /// rebascule avant le délai — sinon un double-clic laissait les deux timers
    /// tirer et le 1er clic gagnait (l'utilisateur finit sur OFF, le mod s'active).
    @State private var pendingToggle: DispatchWorkItem?
    /// Drives the confirmation dialog before deleting this row's mod.
    @State private var showDeleteConfirm = false
    /// L'infobulle demande deux secondes de curseur immobile, et ne se lit
    /// pas au clavier : la note et l'anomalie s'ouvrent aussi **au clic**,
    /// dans un popover qui les montre en entier.
    @State private var showingNote = false
    @State private var showingAnomaly = false
    /// Le mod dont l'activation attend une confirmation : smapi.io le signale
    /// cassé. Voir `CompatibilityWarning`.
    @State private var pendingActivation: ModItem?
    /// Même rôle, source différente : un conflit déclaré ou observé dans le
    /// journal avec un mod déjà actif (tâche 9). Voir `ConflictActivationGate`.
    @State private var pendingConflict: ConflictActivation?

    private var modRowA11yLabel: String {
        String(
            format: vm.L(L10n.Mods.rowA11yLabel),
            mod.name,
            mod.author,
            String(format: vm.L(L10n.Mods.versionPrefix), mod.version)
        )
    }

    /// The effective enabled state, honoring the optimistic `localIsOn` value
    /// so the visual styling reacts instantly when the toggle is flipped
    /// (before `vm.mods` catches up).
    private var effectiveEnabled: Bool { localIsOn ?? mod.isEnabled }

    /// Compact metadata strip shown under the category/author/version line:
    /// languages (FR highlighted), last-update date, install date. Returns nil
    /// when nothing is known so no empty row is rendered. Uses relative dates
    /// (short form) to keep the line scannable; full dates live in the detail
    /// pane.
    /// Les largeurs des colonnes, à un seul endroit.
    ///
    /// **Fixes, et non minimales.** Un `minWidth` laisse la colonne grandir
    /// avec son contenu : l'auteur, mesuré de 1 à 99 caractères sur le parc
    /// réel, décalait donc le numéro de version d'une ligne à l'autre — c'est
    /// justement ce qu'un alignement doit empêcher. Une valeur absente garde
    /// sa place pour la même raison : ce qui suit ne doit pas remonter.
    ///
    /// Sans risque pour le nom du mod : il occupe sa propre ligne au-dessus, et
    /// ne partage la largeur avec aucune de ces colonnes. Total des deux
    /// bandes : 340 et 470 points environ, sous la largeur d'une fenêtre même
    /// étroite.
    enum Column {
        static let category: CGFloat = 110
        static let author: CGFloat = 150
        static let version: CGFloat = 80

        /// « FR 100 % » en français, espace insécable compris : huit signes,
        /// pas quatre.
        static let french: CGFloat = 66
        static let updated: CGFloat = 110
        static let installed: CGFloat = 105
        static let weight: CGFloat = 82
        static let languages: CGFloat = 120
    }

    /// L'auteur, dans un créneau borné.
    ///
    /// Le parc réel va de 1 à **99 caractères** (« Brandon Marquis Markail
    /// Green (Space Baby), 1.6 update by Nikki864, GMCM menu by MickeyMik »),
    /// avec une médiane à 9 : sans borne, un seul auteur bavard poussait la
    /// version et tout ce qui suit hors de leur colonne pour cette ligne-là.
    ///
    /// Troncature au **milieu** et non à la fin : ces noms à rallonge disent
    /// « X, repris par Y », et couper la fin masquerait justement qui maintient
    /// le mod aujourd'hui. L'infobulle porte la valeur entière.
    ///
    /// Vide plutôt que « Unknown » — le littéral que porte un manifeste sans
    /// auteur, déjà écarté de la même façon sur la fiche du mod.
    @ViewBuilder
    private var authorLabel: some View {
        let author = mod.isGroup ? vm.displayAuthor(for: mod) : mod.author
        if !author.isEmpty, author != "Unknown" {
            Text(author)
                .font(AppDesign.Font.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(author)
        } else {
            // Un créneau tenu vide : la colonne suivante doit rester en place.
            Color.clear.frame(height: 1)
        }
    }

    /// Une valeur de la bande, précédée de son icône.
    private func metaValue(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(AppDesign.Font.iconXXS)
            Text(text).lineLimit(1)
        }
    }

    /// Bande compacte sous la ligne catégorie/auteur/version : couverture
    /// française, dates, poids, puis les langues.
    ///
    /// Des créneaux de largeur **minimale**, pour que les mêmes valeurs se
    /// retrouvent à la même abscisse d'une ligne à l'autre : sur 863 mods,
    /// comparer deux poids ou deux dates demandait jusqu'ici de les chercher.
    /// `minWidth` et non `width` — la colonne s'aligne quand la place est là et
    /// reflue quand la fenêtre se resserre, plutôt que de rogner le nom du mod
    /// au-dessus.
    ///
    /// Chaque valeur garde son créneau même absente : sans quoi ce qui la suit
    /// remonte d'un cran et la colonne se défait — la moitié du parc n'ayant
    /// aucune langue déclarée (445 dossiers sur 863), une ligne sur deux
    /// décalait tout ce qui venait après. Les puces « • » qui séparaient les
    /// champs n'ont plus lieu d'être : des colonnes n'ont pas de séparateurs.
    private var rowMetadataLine: AnyView? {
        let updated = vm.nexusLastUpdated(for: mod)
        // La date **effective** : un en-tête de pack n'a pas de
        // `manifest.json`, donc pas de date propre — il hérite de la plus
        // récente de ses composants (`ModItem.effectiveInstallDate`). Lue
        // brute, la colonne restait vide sur toutes les lignes de pack.
        let installed = mod.effectiveInstallDate
        let langs = mod.languages
        // `mod` vient de `vm.mods`, donc de la même analyse que la mesure : sa
        // clé physique désigne le dossier tel qu'il était sur le disque quand
        // le poids a été relevé. Un composant de pack n'en a pas — c'est
        // l'en-tête du pack qui porte le poids du dossier entier.
        let size = vm.sizeOnDisk(of: mod)
        // Les attributs comptent aussi : un mod qui n'a qu'une note doit
        // montrer sa bande, sinon la note disparaîtrait avec elle.
        let hasAttribute = vm.anomaly(for: mod) != nil
            || vm.modNote(for: mod) != nil
            || vm.isProfileConfigManaged(mod)
        guard updated != nil || installed != nil || !langs.isEmpty || size != nil || hasAttribute else {
            return nil
        }
        return AnyView(
            HStack(spacing: 10) {
                updatedSlot(updated)
                installedSlot(installed)
                weightSlot(size)
                languagesLabel(langs)
                frenchSlot(langs: langs)
                anomalySlot
                noteSlot
                profileConfigSlot
            }
        )
    }

    /// La largeur d'un créneau d'attribut : la cible de 18 pt qu'exige une
    /// infobulle vivante sur macOS, plus l'air qui la sépare de sa voisine.
    private static let attributeSlot: CGFloat = 22

    /// L'anomalie du mod, dans un créneau tenu. Elle vivait à côté du nom, où
    /// son abscisse suivait la longueur de celui-ci : d'une ligne à l'autre,
    /// rien ne tombait au même endroit. Elle ferme désormais la bande de
    /// métadonnées, comme le reste, en colonnes.
    @ViewBuilder
    private var anomalySlot: some View {
        Group {
            if let anomaly = vm.anomaly(for: mod) {
                Button { showingAnomaly = true } label: {
                    AnomalyBadge(anomaly: anomaly, vm: vm)
                }
                .buttonStyle(PlainButtonStyle())
                .pointingHandCursor()
                .popover(isPresented: $showingAnomaly, arrowEdge: .bottom) {
                    attributePopover(title: vm.L(L10n.Mods.filterIssues),
                                     systemImage: "exclamationmark.triangle.fill",
                                     text: anomalyReasons(anomaly, vm: vm))
                }
            }
        }
        .frame(width: Self.attributeSlot, alignment: .leading)
    }

    /// La note du mod, même traitement — et le clic la donne en entier : une
    /// note de plusieurs lignes ne tient pas dans une infobulle.
    @ViewBuilder
    private var noteSlot: some View {
        Group {
            if let note = vm.modNote(for: mod) {
                Button { showingNote = true } label: {
                    Image(systemName: "note.text")
                        .font(AppDesign.Font.iconXS)
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(.rect)
                }
                .buttonStyle(PlainButtonStyle())
                .pointingHandCursor()
                .help(note)
                .popover(isPresented: $showingNote, arrowEdge: .bottom) {
                    attributePopover(title: vm.L(L10n.Mods.noteTitle),
                                     systemImage: "note.text",
                                     text: note)
                }
            }
        }
        .frame(width: Self.attributeSlot, alignment: .leading)
    }

    /// Le mod garde un `config.json` par profil. Elle suit ses deux voisines
    /// dans la bande : restée près du nom, elle y serait seule de son espèce.
    @ViewBuilder
    private var profileConfigSlot: some View {
        Group {
            if vm.isProfileConfigManaged(mod) {
                Image(systemName: "slider.horizontal.3")
                    .font(AppDesign.Font.iconXS)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(.rect)
                    .help(vm.L(L10n.Mods.profileConfigBadge))
            }
        }
        .frame(width: Self.attributeSlot, alignment: .leading)
    }

    /// Ce qu'un clic sur un attribut montre : le texte en entier, borné en
    /// largeur pour qu'une note longue s'enroule au lieu de fuir hors écran.
    private func attributePopover(title: String, systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Label(title, systemImage: systemImage)
                .font(AppDesign.Font.caption(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(AppDesign.Font.footnote)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppDesign.Spacing.md)
        .frame(width: 320, alignment: .leading)
    }

    /// La couverture française **ferme** la bande, juste après les codes de
    /// langue dont elle précise l'un des membres : les deux se lisent ensemble,
    /// et le bout de ligne en fait un point d'arrivée du regard plutôt qu'un
    /// préambule à franchir avant les dates.
    @ViewBuilder
    private func frenchSlot(langs: [String]) -> some View {
        Group {
            if langs.contains("fr") {
                FrenchCoverageBadge(
                    percent: vm.frenchCoverage(for: mod),
                    // Un code de langue, pas une phrase : il ne se traduit pas,
                    // exactement comme la liste des langues à côté.
                    unmeasuredLabel: "FR",
                    percentFormat: vm.L(L10n.Mods.frCoveragePercent)
                )
            }
        }
        .frame(width: ModListRow.Column.french, alignment: .leading)
    }

    @ViewBuilder
    private func updatedSlot(_ updated: Date?) -> some View {
        Group {
            if let updated {
                metaValue("clock.arrow.circlepath",
                          updated.formatted(.relative(presentation: .named)))
            }
        }
        .frame(width: ModListRow.Column.updated, alignment: .leading)
    }

    @ViewBuilder
    private func installedSlot(_ installed: Date?) -> some View {
        Group {
            if let installed {
                metaValue("tray.and.arrow.down",
                          installed.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .frame(width: ModListRow.Column.installed, alignment: .leading)
    }

    @ViewBuilder
    private func weightSlot(_ size: Int64?) -> some View {
        Group {
            if let size { ModWeightLabel(bytes: size) }
        }
        .frame(width: ModListRow.Column.weight, alignment: .leading)
    }

    /// Jusqu'à 76 caractères de codes sur le parc réel : borné à ce que la
    /// place permet, avec la liste entière à l'infobulle.
    @ViewBuilder
    private func languagesLabel(_ langs: [String]) -> some View {
        let codes = langs.map { $0.uppercased() }.joined(separator: " ")
        Group {
            if !langs.isEmpty {
                metaValue("globe", codes)
                    .truncationMode(.tail)
                    .help(codes)
            }
        }
        .frame(width: ModListRow.Column.languages, alignment: .leading)
    }

    /// L'étoile de favori, sur les lignes de **premier niveau** seulement.
    ///
    /// Un composant de pack n'en porte pas : il ne s'active pas seul — c'est le
    /// pack qu'on met en pause, qu'on installe et qu'on met dans un profil. Le
    /// marquer séparément laisserait croire l'inverse.
    ///
    /// Toujours visible, pleine ou vide, plutôt qu'au survol : une étoile qui
    /// n'apparaît qu'au passage de la souris ne se découvre pas, et on ne peut
    /// pas lire d'un coup d'œil ce qui est marqué.
    @ViewBuilder
    private var favoriteStar: some View {
        let on = vm.isFavorite(mod)
        Button {
            vm.toggleFavorite(mod)
        } label: {
            Image(systemName: on ? "star.fill" : "star")
                .font(AppDesign.Font.footnote)
                .foregroundColor(on ? .yellow : .secondary.opacity(isHovered ? 0.6 : 0.25))
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHandCursor()
        .help(vm.L(on ? L10n.Mods.favoriteRemove : L10n.Mods.favoriteAdd))
        .accessibilityLabel(vm.L(on ? L10n.Mods.favoriteRemove : L10n.Mods.favoriteAdd))
    }

    var body: some View {
        HStack(spacing: 0) {

            // Status accent bar — instant at-a-glance enabled/disabled
            // reading. Green for enabled, muted for disabled. Wider for
            // top-level rows, slimmer for pack children.
            RoundedRectangle(cornerRadius: 2)
                .fill(effectiveEnabled
                      ? AppDesign.Color.installed
                      : Color.secondary.opacity(AppDesign.Opacity.strong))
                .frame(width: isChild ? 2.5 : 3.5)

            HStack(spacing: AppDesign.Spacing.md) {
            
            // Chevron space (ensures perfect alignment for all top-level items)
            if !isChild {
                ZStack {
                    if isGroupHeader {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(AppDesign.Font.iconXS(.bold))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 14, alignment: .center)

                favoriteStar
                    // Largeur fixe : sans elle, l'étoile mesure ce que son
                    // glyph veut, et l'indentation des composants ci-dessous
                    // ne pouvait pas s'y accorder.
                    .frame(width: 16, alignment: .center)
            } else {
                // L'indentation d'un composant se **calcule** sur ce qui la
                // précède chez son pack — chevron (14) + espace (12) + étoile
                // (16) — plus un cran. Le 32 forfaitaire d'avant tombait en
                // deçà : le nom d'un composant commençait à *gauche* de celui
                // de son pack, et toute sa bande de métadonnées avec.
                Spacer().frame(width: 14 + AppDesign.Spacing.md + 16 + AppDesign.Spacing.md)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(mod.name)
                        .font(AppDesign.Font.body(.medium))
                        .foregroundColor(effectiveEnabled ? .primary : .secondary)
                        .lineLimit(1)
                    // Le glyph de l'état « en pause » (P6 : glyph + couleur
                    // + barre d'accent — jamais la couleur seule). Redondant
                    // avec la barre d'accent : chaque signal seul suffit.
                    if !effectiveEnabled && !isChild {
                        Image(systemName: "pause.circle")
                            .font(AppDesign.Font.iconXS)
                            .foregroundColor(.secondary)
                    }
                    // L'anomalie, la note et la config de profil sont parties
                    // dans la bande de métadonnées : à côté du nom, leur
                    // abscisse suivait la longueur de celui-ci et rien ne
                    // tombait au même endroit d'une ligne à l'autre. Reste
                    // ici ce qui parle du **nom** : son état.
                }
                
                if mod.name != mod.folderName {
                    Text(mod.folderName)
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                }
                
                // Une seule forme pour les deux cas : un en-tête de pack rend
                // les mêmes champs, agrégés de ses composants. Deux `HStack`
                // jumeaux les auraient fait diverger dès la première retouche —
                // et un pack mal aligné au milieu de la liste se voit.
                HStack(spacing: 8) {
                    // Category badge — only for mods whose category was
                    // fetched from Nexus or manually pinned. Otherwise
                    // fall back to the offline-inferred type tag.
                    Group {
                        if let cat = vm.category(for: mod) {
                            CategoryBadge(category: cat, L: vm.L)
                        } else {
                            InferredTagBadge(label: vm.L(L10n.ModTag.key(for: vm.inferredTagKey(for: mod))))
                        }
                    }
                    .frame(width: ModListRow.Column.category, alignment: .leading)

                    authorLabel
                        .frame(width: ModListRow.Column.author, alignment: .leading)

                    VersionBadge(version: mod.isGroup ? vm.displayVersion(for: mod) : mod.version)
                        .frame(width: ModListRow.Column.version, alignment: .leading)

                    if mod.isGroup {
                        // Le nombre de composants ferme la ligne : il varie, et
                        // plus rien ne le suit dont il pourrait décaler la place.
                        Text(mod.description)
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                // Compact metadata strip: languages + dates. Only shown when
                // at least one value is known, to avoid an empty row.
                if let metaLine = rowMetadataLine {
                    metaLine
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                let missingDeps = vm.getMissingDependencies(for: mod)
                let disabledDeps = vm.getDisabledDependencies(for: mod)
                if !missingDeps.isEmpty || !disabledDeps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        if !missingDeps.isEmpty {
                            HStack(spacing: AppDesign.Spacing.xs) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                // Chaque dépendance manquante est cliquable :
                                // ouvre la recherche Nexus Mods pour ce nom.
                                Text("\(vm.L(L10n.Mods.missingDependenciesPrefix)) ")
                                    .foregroundColor(.secondary)
                                ForEach(Array(missingDeps.enumerated()), id: \.offset) { idx, depId in
                                    HStack(spacing: 2) {
                                        if idx > 0 { Text(",") }
                                        let modName = depId.smapiModName
                                        let author = depId.smapiAuthor
                                        // Au clic, propose deux recherches Nexus :
                                        // par nom du mod (défaut) ou par auteur.
                                        Menu {
                                            Button {
                                                openNexusSearch(for: modName)
                                            } label: {
                                                Label(String(format: vm.L(L10n.Mods.searchNexusByModName), modName),
                                                      systemImage: "magnifyingglass")
                                            }
                                            if !author.isEmpty {
                                                Button {
                                                    openNexusAuthorSearch(for: author)
                                                } label: {
                                                    Label(String(format: vm.L(L10n.Mods.searchNexusByAuthor), author),
                                                          systemImage: "person")
                                                }
                                            }
                                        } label: {
                                            Text(modName)
                                                .underline()
                                                .pointingHandCursor()
                                        }
                                        .menuStyle(.button)
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .foregroundColor(.red)
                        }
                        if !disabledDeps.isEmpty {
                            HStack(spacing: AppDesign.Spacing.xs) {
                                Image(systemName: "exclamationmark.octagon.fill")
                                Text(String(format: vm.L(L10n.Mods.disabledRequiredDeps), disabledDeps.joined(separator: ", ")))
                            }
                            .foregroundColor(.orange)
                        }
                    }
                    .font(AppDesign.Font.footnote)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(red: 0.85, green: 0.25, blue: 0.20).opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(red: 0.85, green: 0.25, blue: 0.20).opacity(0.2), lineWidth: 0.5)
                    )
                    .padding(.top, 2)
                }
            }

            Spacer()

            // Actions (always visible)
            HStack(spacing: AppDesign.Spacing.md) {
                Button {
                    let url = URL(fileURLWithPath: vm.gameDir)
                        .appendingPathComponent("Mods")
                        .appendingPathComponent(mod.physicalFolderName)
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "folder")
                        .font(AppDesign.Font.rowTitle)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(vm.L(L10n.Mods.openFolder))
                .accessibilityLabel(vm.L(L10n.Mods.openFolder))
                .accessibilityHint(vm.L(L10n.Mods.openFolderA11yHint))
                .pointingHandCursor()

                // Direct config-editor access, mirroring upstream's
                // discoverability: visible only for a standalone mod (never
                // a pack header, which has no config.json of its own) that
                // actually has a config.json. The right-click "Code Editor"
                // context-menu entry stays as an additional entry point.
                if !mod.isGroup && mod.hasConfigFile {
                    Button {
                        vm.editingModConfig = mod
                    } label: {
                        Image(systemName: "gearshape")
                            .font(AppDesign.Font.rowTitle)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(vm.L(L10n.Settings.configModSettings))
                    .accessibilityLabel(vm.L(L10n.Settings.configModSettings))
                    .accessibilityHint(vm.L(L10n.Settings.configModSettingsA11yHint))
                    .pointingHandCursor()
                }

                // Direct "open on Nexus" button — visible whenever the mod has
                // an effective Nexus id (manifest-declared or user-assigned).
                let link = vm.nexusLink(for: mod)
                if !link.isEmpty {
                    Button {
                        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
                    } label: {
                        Image(systemName: "safari")
                            .font(AppDesign.Font.rowTitle)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(vm.L(L10n.Mods.viewOnNexus))
                    .accessibilityLabel(vm.L(L10n.Mods.viewOnNexus))
                    .accessibilityHint(vm.L(L10n.Mods.viewOnNexusA11yHint))
                    .pointingHandCursor()
                }

                // Info button — always visible so the user can edit the mod's
                // category / Nexus link even when it has no dependencies or
                // pre-existing Nexus URL.
                Button {
                    vm.viewingModDetail = mod
                } label: {
                    Image(systemName: "info.circle")
                        .font(AppDesign.Font.rowTitle)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(vm.L(L10n.Mods.openDetails))
                .accessibilityLabel(vm.L(L10n.Mods.openDetails))
                .accessibilityHint(vm.L(L10n.Mods.openDetailsHint))
                .pointingHandCursor()

                // Delete button — permanently removes the mod (or pack) from
                // disk. Hidden for child rows inside a pack, since the pack
                // header carries the delete action for all children. A
                // confirmation dialog fires before the actual deletion.
                // While the deletion is in flight (folder removal + rescan),
                // a spinner replaces the trash icon on this row.
                if !isChild {
                    if vm.pendingDeleteFolder == mod.folderName {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                            .help(vm.L(L10n.Mods.deleteMod))
                    } else {
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(AppDesign.Font.rowTitle)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(vm.pendingDeleteFolder != nil)
                        .help(vm.L(L10n.Mods.deleteMod))
                        .accessibilityLabel(vm.L(L10n.Mods.deleteMod))
                        .accessibilityHint(vm.L(L10n.Mods.deleteModA11yHint))
                        .pointingHandCursor()
                    }
                }
            }
            .padding(.trailing, 8)


            // macOS Native Switch Toggle
            if !isChild {
                HStack(spacing: AppDesign.Spacing.xs) {
                    // Spinner pendant l'opération de toggle (rename du
                    // dossier dans Mods/ entre X et .X). Disparaît dès
                    // que pendingToggleFolder est remis à nil par le VM.
                    if vm.pendingToggleFolder == mod.folderName {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    }
                    Toggle("", isOn: Binding(
                        get: { localIsOn ?? mod.isEnabled },
                        set: { newValue in
                            localIsOn = newValue
                            // Annule un toggle en attente : sans cela, un
                            // double-clic laissait deux timers tirer et le 1er
                            // clic gagnait au lieu du dernier.
                            pendingToggle?.cancel()
                            let work = DispatchWorkItem {
                                if newValue != mod.isEnabled {
                                    // Activer un mod que smapi.io signale cassé
                                    // demande une confirmation ; le mettre en
                                    // pause, jamais. La bascule optimiste est
                                    // rendue tout de suite : l'interrupteur ne
                                    // doit pas rester sur « actif » pendant que
                                    // l'alerte attend une réponse.
                                    if vm.activationWarning(for: mod) != nil {
                                        localIsOn = nil
                                        pendingActivation = mod
                                        return
                                    }
                                    // Même porte, source différente : un conflit
                                    // déclaré ou observé dans le journal avec un
                                    // mod déjà actif (tâche 9).
                                    if let other = vm.conflictWarning(for: mod) {
                                        localIsOn = nil
                                        pendingConflict = ConflictActivation(mod: mod, other: other)
                                        return
                                    }
                                    // Keep the optimistic value until toggleMod's completion
                                    // confirms vm.mods has actually caught up — clearing it
                                    // eagerly here races the background scanMods() and made
                                    // the switch visibly snap back to its old position.
                                    vm.toggleMod(mod) {
                                        localIsOn = nil
                                    }
                                } else {
                                    localIsOn = nil
                                }
                            }
                            pendingToggle = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
                        }
                    ))
                        .toggleStyle(SwitchToggleStyle(tint: AppDesign.Color.installed))
                        .controlSize(.small)
                        // Annuler un toggle en attente quand la rangée disparaît
                        // (virtualisation, navigation) : sinon le debounce 300 ms
                        // tirait pour un mod désaffiché.
                        .onDisappear { pendingToggle?.cancel() }
                        .labelsHidden()
                        .accessibilityLabel(String(format: vm.L(L10n.Mods.toggleA11yLabel), mod.name))
                        .accessibilityHint(vm.L(L10n.Mods.toggleA11yHint))
                        .accessibilityValue(mod.isEnabled ? vm.L(L10n.Mods.enabled) : vm.L(L10n.Mods.disabled))
                }
            } else {
                Toggle("", isOn: .constant(false))
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .controlSize(.small)
                    .labelsHidden()
                    .opacity(0)
            }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            // Dim the content (not the toggle/accent bar) for disabled mods to
            // create visual hierarchy — active mods draw the eye first.
            .opacity(effectiveEnabled ? 1.0 : 0.72)
        }
        .background(
            // Hover: accent-tinted fill for a clearer "interactive" feel.
            isHovered ? Color.accentColor.opacity(0.06) : Color.clear
        )
        .background(
            vm.selectedModID == mod.folderName
                ? Color.accentColor.opacity(0.08)
                : Color.clear
        )
        .cornerRadius(6)
        .overlay(
            // Subtle accent border on hover — polished focus ring.
            RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                .stroke(isHovered ? Color.accentColor.opacity(0.2) : Color.clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: effectiveEnabled)
        .onHover { isHovered = $0 }
        // Accessibility : VoiceOver annonce le mod comme un élément unifié
        // avec son nom, auteur, version et état (activé/désactivé).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(modRowA11yLabel)
        .accessibilityValue(mod.isEnabled ? vm.L(L10n.Mods.enabled) : vm.L(L10n.Mods.disabled))
        .accessibilityHint(vm.L(L10n.Mods.openDetailsHint))
        .contextMenu {
            Button(vm.L(L10n.Mods.openInFinder)) {
                let url = URL(fileURLWithPath: vm.gameDir)
                    .appendingPathComponent("Mods")
                    .appendingPathComponent(mod.physicalFolderName)
                NSWorkspace.shared.open(url)
            }
            Button(vm.L(L10n.Settings.configModSettings)) {
                vm.editingModConfig = mod
            }
            let effectiveLink = vm.nexusLink(for: mod)
            if !effectiveLink.isEmpty {
                Button(vm.L(L10n.Mods.viewDetailsOnNexus)) {
                    if let url = URL(string: effectiveLink) { NSWorkspace.shared.open(url) }
                }
            }
            if !isChild {
                Divider()
                Button(vm.L(L10n.Mods.deleteMod), role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .confirmationDialog(
            String(format: vm.L(L10n.Mods.deleteConfirmTitle), mod.name),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(vm.L(L10n.Mods.deleteMod), role: .destructive) {
                vm.deleteMod(mod)
            }
            Button(vm.L(L10n.Saves.cancel), role: .cancel) { }
        } message: {
             Text(mod.isGroup
                 ? vm.L(L10n.Mods.deleteConfirmPack)
                 : vm.L(L10n.Mods.deleteConfirmMessage))
        }
        .compatibilityGate(vm: vm, pending: $pendingActivation) { target in
            vm.toggleMod(target)
        }
        .conflictActivationGate(vm: vm, pending: $pendingConflict) { target in
            vm.toggleMod(target)
        }
    }

    /// Ouvre la recherche Nexus Mods pour une dépendance manquante.
    /// Le terme de recherche utilise le nom lisible (ex. "Content Patcher"
    /// plutôt que l'identifiant unique "Pathoschild.ContentPatcher") pour
    /// exploiter l'indexation par nom de Nexus.
    private func openNexusSearch(for searchTerm: String) {
        let encoded = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchTerm
        if let url = URL(string: "https://www.nexusmods.com/stardewvalley/search/?gsearch=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Ouvre la liste des mods d'un auteur sur Nexus Mods. Le filtre `?author=`
    /// est plus précis qu'une recherche plein texte pour retrouver tous les
    /// mods d'un même auteur.
    private func openNexusAuthorSearch(for author: String) {
        let encoded = author.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? author
        if let url = URL(string: "https://www.nexusmods.com/games/stardewvalley/mods?author=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Neutral badge shown in place of `CategoryBadge` when a mod has no Nexus
/// category: displays its offline-inferred type tag (see `ModItem.inferTag`)
/// instead, so uncategorized mods still carry some at-a-glance grouping info.
private struct InferredTagBadge: View {
    let label: String
    var body: some View {
        Text(label)
            .lineLimit(1)
            .font(AppDesign.Font.iconXS(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(AppDesign.Opacity.medium))
            .foregroundColor(.secondary)
            .clipShape(Capsule())
    }
}

/// Pastille de couverture française, dans le vocabulaire de `VersionBadge` :
/// une unité compacte et scannable plutôt qu'un mot noyé dans la ligne grise.
///
/// **Le nombre porte l'information, la couleur la renforce** — jamais
/// l'inverse. Un badge dont le sens tiendrait au seul vert contre orange serait
/// illisible pour un daltonien et invisible en balayage rapide ; c'est le taux
/// écrit qui se compare d'une ligne à l'autre.
///
/// Trois états, parce qu'il y en a trois : mesuré et complet, mesuré et
/// partiel, et **pas encore mesuré** — le calcul se fait en tâche de fond après
/// le scan. Ce dernier état se lit en gris et sans nombre : annoncer un taux
/// qu'on ignore serait pire que de ne rien annoncer.
private struct FrenchCoverageBadge: View {
    /// `nil` tant que la mesure n'a pas abouti.
    let percent: Int?
    let unmeasuredLabel: String
    let percentFormat: String

    private var tint: Color {
        guard let percent else { return .secondary }
        return percent >= 100 ? Color(red: 0.20, green: 0.62, blue: 0.34) : .orange
    }

    var body: some View {
        Text(percent.map { String(format: percentFormat, $0) } ?? unmeasuredLabel)
            // Chiffres à chasse fixe : dans une liste, « 8 % » et « 72 % »
            // doivent s'aligner verticalement pour se comparer d'un coup d'œil,
            // sinon chaque pastille danse d'une ligne à l'autre.
            .font(AppDesign.Font.iconXS(.semibold).monospacedDigit())
            // Sur une seule ligne, quoi qu'il arrive : dans une colonne de
            // largeur fixe, « FR 100 % » se repliait et poussait le « % » sous
            // le reste. `fixedSize` prime sur la contrainte de la colonne.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(tint.opacity(AppDesign.Opacity.medium))
            )
            .overlay(
                // Un liseré porte le contour que l'aplat à 15 % ne donne pas —
                // sans lui la pastille se dissout sur un fond clair.
                Capsule().stroke(tint.opacity(AppDesign.Opacity.strong), lineWidth: 0.5)
            )
    }
}

/// Compact monospaced pill for a mod's version number. Replaces the bare
/// `Text("v\(version)")` so the version reads as a distinct, scannable unit
/// rather than blending into the metadata row's bullet-separated text.
private struct VersionBadge: View {
    let version: String
    var body: some View {
        Text("v\(version)")
            .font(AppDesign.Font.iconXS(.medium).monospaced())
            // Le parc réel monte à 28 signes (« 0.6.3-unofficial-mushymato.1 »,
            // « %ProjectVersion% ») : sans garde, la capsule se repliait sur
            // deux lignes et faisait enfler la rangée. Coupée au milieu, le
            // numéro majeur et le suffixe restent tous deux lisibles.
            .lineLimit(1)
            .truncationMode(.middle)
            .help(version)
            .foregroundColor(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(AppDesign.Opacity.light))
            )
    }
}


/// Le poids d'un mod dans sa ligne de liste.
///
/// Affiché sur **toutes** les lignes, mais teinté au-delà de 100 Mo. Le parc
/// réel explique les deux décisions : sa médiane est de 213 Ko et 650 dossiers
/// sur 863 pèsent moins d'un mégaoctet — un chiffre neutre partout serait du
/// bruit — tandis que **22 dossiers portent 87 % des 16,8 Go**. La teinte les
/// désigne sans qu'il faille lire 863 lignes, et reste assez rare pour valoir
/// signal.
private struct ModWeightLabel: View {
    let bytes: Int64

    /// 22 mods du parc réel passent ce seuil, et ils portent 87 % du poids.
    /// Plus bas (50 Mo : 31 mods) la teinte se banalise, plus haut (300 Mo :
    /// 11 mods) elle laisse de côté des dossiers qui pèsent encore lourd.
    private static let heavyThreshold: Int64 = 100_000_000

    private var isHeavy: Bool { bytes >= Self.heavyThreshold }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "internaldrive")
                .font(AppDesign.Font.iconXXS)
            // Chiffres à chasse fixe, comme la pastille de couverture : d'une
            // ligne à l'autre les tailles doivent s'aligner pour se comparer.
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .font(AppDesign.Font.iconXS(isHeavy ? .semibold : .regular).monospacedDigit())
        }
        .foregroundColor(isHeavy ? .orange : .secondary)
    }
}


// MARK: - Pastille d'anomalie (B1-T3)

/// Ce qui empêche un mod de bien tourner, sur sa ligne.
///
/// Trois signaux sous une seule pastille : erreurs et avertissements relevés
/// dans les journaux SMAPI **pour la version installée**, dépendance requise
/// absente ou en pause, manifeste sans identifiant. Le détail passe par
/// l'infobulle — la ligne porte déjà beaucoup.
///
/// Sur un parc réel, six mods sur 863 en portent une, dont un seul en rouge :
/// c'est peu, et c'est le résultat attendu. Une pastille qui s'allumerait
/// souvent ne dirait plus rien.
private struct AnomalyBadge: View {
    let anomaly: ModAnomaly
    @ObservedObject var vm: StarHubTHViewModel

    private var tint: Color { anomaly.severity == .error ? .orange : .yellow }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppDesign.Font.iconXXS)
            if anomaly.badgeCount > 0 {
                Text("\(anomaly.badgeCount)")
                    .font(AppDesign.Font.iconXS(.semibold).monospacedDigit())
            }
        }
        .foregroundColor(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Capsule().fill(tint.opacity(AppDesign.Opacity.medium)))
        // La capsule mesurait ~13 pt de haut : trop court pour que macOS
        // accepte de garder son curseur « tout à l'intérieur » les ~2 s
        // qu'exige une infobulle — le timer se réinitialisait et l'aide ne
        // venait jamais. Même correction que la note et la config voisines :
        // une cible d'au moins 18×18, et une forme qui la porte.
        .frame(minWidth: 18, minHeight: 18)
        .contentShape(.rect)
        .help(reasons)
        .accessibilityLabel(reasons)
    }

    private var reasons: String { anomalyReasons(anomaly, vm: vm) }
}

/// Toutes les raisons d'une anomalie, une par ligne : un mod peut cumuler une
/// dépendance manquante et des erreurs, et n'en montrer qu'une enverrait sur
/// une fausse piste.
///
/// Une fonction et non une propriété de la pastille : la rangée en a besoin
/// pour son popover, et fabriquer une pastille jetable pour lire son texte
/// aurait été un détour.
private func anomalyReasons(_ anomaly: ModAnomaly, vm: StarHubTHViewModel) -> String {
    var lines: [String] = []
    if anomaly.isUnloadable { lines.append(vm.L(L10n.Mods.anomalyUnloadable)) }
    if anomaly.hasDependencyIssue { lines.append(vm.L(L10n.Mods.anomalyDependency)) }
    if let duplicate = anomaly.duplicate {
        // Les dossiers **nommés** : un compte seul laisserait chercher
        // lequel supprimer parmi 863.
        lines.append(String(format: vm.L(duplicate.isActive
                                         ? L10n.Mods.anomalyDuplicateActive
                                         : L10n.Mods.anomalyDuplicateDormant),
                            duplicate.copies,
                            duplicate.folders.joined(separator: ", ")))
    }
    if let status = anomaly.compatibility {
        lines.append(String(format: vm.L(L10n.Mods.anomalyCompat),
                            CompatibilityWarning.label(status, vm)))
    }
    if anomaly.errorCount > 0 {
        lines.append(String(format: vm.L(L10n.Mods.anomalyErrors), anomaly.errorCount))
    }
    if anomaly.warningCount > 0 {
        lines.append(String(format: vm.L(L10n.Mods.anomalyWarnings), anomaly.warningCount))
    }
    return lines.joined(separator: "\n")
}
