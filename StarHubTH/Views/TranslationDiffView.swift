import SwiftUI

/// Le diff EN/FR d'un mod, clé par clé.
///
/// C'est ce que ni la pastille de la liste ni la fiche ne peuvent dire : la
/// pastille donne un taux, la fiche donne des comptes, celle-ci donne **les
/// clés**. C'est l'écran où l'on voit ce qu'il reste à faire.
///
/// Trois partis pris, tous payés par l'expérience :
///
/// - **`LazyVStack` dans une `ScrollView`, jamais `List`.** `East Scarp NPCs`
///   compte 11 021 clés. Un `List` construit toutes ses rangées d'un coup — il
///   avait produit huit à dix secondes de roue multicolore sur 2 000 lignes de
///   journal, et c'est le même piège ici en cinq fois pire.
/// - **Un état se lit par la teinte *et* un glyphe**, chacun suffisant seul. Un
///   diff dont le sens tiendrait à la couleur serait illisible pour un
///   daltonien. Règle reprise de `stardew-i18n-translator`, cf.
///   `docs/audit-nana-ux.md` §1.
/// - **Le compte est dans le libellé du filtre.** On sait ce qu'on va trouver
///   avant de cliquer, et « Vides 3 » attire l'œil là où il faut.
struct TranslationDiffView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ModItem

    /// Ce que la barre de filtres peut cadrer : un état du diff, ou le
    /// drapeau « À relire » posé par le lot.
    enum DiffFilter: Equatable {
        case state(TranslationCoverage.DiffRow.State)
        case reviewNeeded
    }

    @State private var rows: [TranslationCoverage.DiffRow] = []
    @State private var isLoading = true
    /// Le cadrage choisi. Un état du diff, ou « À relire » — qui n'est pas un
    /// état mais un drapeau du magasin de références : il vit ici, à côté de
    /// son modèle, pour être filtré par la même barre.
    @State private var filter: DiffFilter?
    @State private var searchText = ""
    /// Les clés « à relire » de ce mod (issues du lot), au format de
    /// `DiffRow.id` : c'est ce qui fait vivre le badge et le filtre.
    @State private var reviewNeededIDs: Set<String> = []
    /// La feuille du lot de pré-traduction.
    @State private var isShowingBatch = false
    /// Les groupes tels que le fichier les donne, calculés **une fois** sur les
    /// rangées complètes. Leur identité ne dépend donc jamais du filtre en
    /// cours : c'est ce qui permet à un repli de désigner toujours la même
    /// section, quoi qu'on tape dans la recherche.
    @State private var allGroups: [TranslationCoverage.DiffGroup] = []
    /// Les comptes de la barre de filtres, refaits par `rebuildGroups()` et
    /// non dans `body` : pendant un lot, le ViewModel republie une fois par
    /// clé traduite, et trois parcours des rangées (jusqu'à 17 910 sur East
    /// Scarp) à chaque republication tenaient le fil principal occupé du
    /// début à la fin du lot.
    @State private var filterSummary = FilterSummary()
    /// Ce que la vue affiche : les mêmes groupes, réduits aux rangées retenues.
    @State private var groups: [TranslationCoverage.DiffGroup] = []
    /// Les sections repliées, par identité de groupe. Déplié par défaut : le
    /// repliage est une aide à la navigation, pas un correctif de performance —
    /// le `LazyVStack` encaisse déjà 11 021 clés.
    @State private var collapsed: Set<String> = []
    @State private var isShowingSectionIndex = false
    /// La section à rejoindre, posée par la table des matières et consommée par
    /// le `ScrollViewReader`.
    @State private var scrollTarget: String?
    /// L'anglais de ce mod a-t-il été touché après son français ? Rappelé ici
    /// même si la fiche l'affiche déjà : c'est là qu'on travaille effectivement
    /// la traduction.
    @State private var staleness: TranslationFreshness.Staleness?
    /// La ligne ouverte dans l'éditeur, ou `nil`. `DiffRow.id` vaut
    /// `component/key` (ou `key` seul) : deux composants définissant la même
    /// clé restent deux lignes distinctes, et `.sheet(item:)` rouvre toujours
    /// la bonne.
    @State private var editing: TranslationCoverage.DiffRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                loadingRow
            } else if rows.isEmpty {
                emptyRow(vm.L(L10n.Mods.diffNone))
            } else {
                filterBar
                if let staleness {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 10))
                        Text(staleness.note(
                            sourceNewerFormat: vm.L(L10n.Mods.translationSourceNewer),
                            sameDayFormat: vm.L(L10n.Mods.translationSourceNewerToday),
                            oneDayFormat: vm.L(L10n.Mods.translationSourceNewerOneDay),
                            dateText: staleness.sourceDate.formatted(date: .abbreviated,
                                                                     time: .omitted)))
                            .font(.system(size: 11))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                }
                Divider()
                // En-tête **hors** de la zone défilante : sans lui, rien ne
                // disait laquelle des deux colonnes portait l'anglais et
                // laquelle le français. L'épingler dans la `ScrollView` aurait
                // concurrencé l'épinglage des en-têtes de section ; au-dessus,
                // il reste visible sans rien disputer.
                columnHeader
                Divider()
                table
            }
        }
        .task {
            // Chargement détaché côté ViewModel : lire et analyser 11 021 clés
            // sur le fil principal figerait la fenêtre.
            rows = await vm.translationDiff(for: mod)
            staleness = await vm.translationStaleness(for: mod)
            reviewNeededIDs = await vm.reviewNeededRowIDs(for: mod)
            // Le regroupement une seule fois, sur les rangées complètes.
            allGroups = TranslationCoverage.diffGroups(rows: rows)
            // Les groupes avant le drapeau : sans quoi une passe de rendu
            // pourrait tomber sur des rangées sans groupes et afficher
            // brièvement « aucune clé ne correspond ».
            rebuildGroups()
            isLoading = false
            // Après l'affichage, jamais avant : une mise à jour du jeu réécrit
            // `Content/Strings` et le glossaire en cache se refait alors — un
            // parcours des dates du dossier, parfois une reconstruction. Rien
            // ici n'a besoin du glossaire ; les chips et la pré-traduction, si,
            // et elles viennent après. Une fois par lancement.
            await vm.refreshGlossaryIfSourcesChanged()
        }
        // Le regroupement ne peut pas vivre dans `body` : regrouper 17 910
        // lignes à chaque frappe rendrait la recherche inutilisable.
        .onChange(of: filter) { _, _ in rebuildGroups() }
        .onChange(of: searchText) { _, _ in rebuildGroups() }
    }

    // MARK: - Chargement et vides

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(vm.L(L10n.Mods.diffLoading))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .padding(.vertical, 12)
    }

    // MARK: - Filtres

    /// Un bouton par état, chacun portant son compte. Les états absents du mod
    /// ne s'affichent pas : proposer « Vides 0 » ferait chercher un problème
    /// qui n'existe pas.
    private var filterBar: some View {
        let counts = filterSummary.counts
        let reviewCount = filterSummary.reviewCount
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                filterChip(nil, label: vm.L(L10n.Mods.diffStateAll), count: rows.count)
                ForEach(TranslationCoverage.DiffRow.State.allCases, id: \.self) { state in
                    if let count = counts[state], count > 0 {
                        filterChip(.state(state), label: label(for: state), count: count)
                    }
                }
                if reviewCount > 0 {
                    // Comme les autres : glyphe et compte dans le libellé, on
                    // sait ce qu'on va trouver avant de cliquer.
                    filterChip(.reviewNeeded,
                               label: vm.L(L10n.Mods.translationReviewNeeded),
                               count: reviewCount,
                               glyph: "text.magnifyingglass",
                               tint: .orange)
                }
            }
            HStack(spacing: 8) {
                // Le lot : visible seulement s'il reste du travail pour lui
                // et qu'une IA est configurée (spec §7) — sinon il n'aurait
                // rien à proposer et cacher le bouton vaut mieux qu'un clic
                // qui échoue.
                if vm.isLocalAIConfigured && filterSummary.hasBatchWork {
                    Button {
                        isShowingBatch = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.rays").font(.system(size: 10))
                            Text(vm.L(L10n.Mods.translationBatchButton))
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help(vm.L(L10n.Mods.translationBatchButton))
                    .accessibilityLabel(vm.L(L10n.Mods.translationBatchButton))
                    .sheet(isPresented: $isShowingBatch) {
                        TranslationBatchView(
                            vm: vm, mod: mod, locale: "fr", rows: rows,
                            onClose: {
                                isShowingBatch = false
                                // Recharger ce que le lot vient d'écrire, et
                                // rouvrir cadré sur ce qu'il a produit :
                                // c'est là qu'il faut relire.
                                filter = .reviewNeeded
                                Task {
                                    rows = await vm.translationDiff(for: mod)
                                    reviewNeededIDs = await vm.reviewNeededRowIDs(for: mod)
                                    allGroups = TranslationCoverage.diffGroups(rows: rows)
                                    rebuildGroups()
                                }
                            })
                    }
                }
                TextField(vm.L(L10n.Mods.diffSearch), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                if hasSections {
                    Button {
                        isShowingSectionIndex = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet.indent").font(.system(size: 10))
                            Text(vm.L(L10n.Mods.diffSections)).font(.system(size: 10, weight: .medium))
                            // `groups.count`, pas les seuls groupes titrés : c'est
                            // exactement ce que le popover ci-dessous liste (blocs
                            // sans titre et orphelin compris). Annoncer les titrés
                            // pour une liste qui en montre plus serait un compte
                            // faux — mesuré sur Ridgeside : 1878 annoncés pour 1881
                            // lignes listées.
                            Text("\(groups.count)")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .popover(isPresented: $isShowingSectionIndex, arrowEdge: .bottom) {
                        TranslationSectionIndexView(
                            groups: groups,
                            searchPlaceholder: vm.L(L10n.Mods.diffSectionsSearch),
                            noMatchLabel: vm.L(L10n.Mods.diffSectionsNoMatch),
                            untitledLabel: vm.L(L10n.Mods.diffSectionUntitled),
                            orphanLabel: vm.L(L10n.Mods.diffStateOrphan)
                        ) { group in
                            isShowingSectionIndex = false
                            // Déplier avant de viser : dans une section repliée
                            // les lignes ne sont pas dans la hiérarchie, mais
                            // l'en-tête, lui, l'est toujours.
                            collapsed.remove(group.id)
                            scrollTarget = group.id
                        }
                    }
                }
                // `fileHasTitledSections` en plus de `allGroups.count > 1` : un
                // fichier sans section titrée mais avec des orphelines forme deux
                // groupes sans qu'aucun en-tête ne soit affiché (cf. `table`) —
                // replier n'a de sens que là où quelque chose nomme ce qu'on replie.
                if allGroups.count > 1 && fileHasTitledSections {
                    Button(vm.L(collapsed.isEmpty ? L10n.Mods.diffCollapseAll
                                                  : L10n.Mods.diffExpandAll)) {
                        // Sur `allGroups`, volontairement, pas `groups` : l'état de
                        // repliage est indépendant du filtre — c'est tout l'intérêt
                        // d'avoir des identités stables — donc « Tout replier » doit
                        // aussi replier ce que le filtre masque. Sinon, replier sous
                        // un filtre puis l'effacer ferait réapparaître des sections
                        // dépliées pendant que le bouton proposerait encore
                        // « Tout déplier ».
                        collapsed = collapsed.isEmpty ? Set(allGroups.map(\.id)) : []
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                }
            }
        }
        .padding(.bottom, 10)
    }

    private func filterChip(_ criterion: DiffFilter?,
                            label: String, count: Int,
                            glyph: String? = nil,
                            tint: Color? = nil) -> some View {
        let isSelected = filter == criterion
        return Button {
            filter = isSelected ? nil : criterion
        } label: {
            HStack(spacing: 4) {
                if let glyph {
                    Image(systemName: glyph).font(.system(size: 9))
                } else if case .state(let state) = criterion {
                    Image(systemName: DiffStateStyle.glyph(state)).font(.system(size: 9))
                }
                Text(label).font(.system(size: 10, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isSelected
                               ? Color.accentColor.opacity(AppDesign.Opacity.strong)
                               : Color.secondary.opacity(AppDesign.Opacity.light))
            )
            .foregroundColor(derivedTint(criterion, override: tint))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func derivedTint(_ criterion: DiffFilter?, override: Color?) -> Color {
        if let override { return override }
        if case .state(let state) = criterion { return DiffStateStyle.tint(state) }
        return .primary
    }

    // MARK: - Table

    private var table: some View {
        Group {
            if groups.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    emptyRow(vm.L(L10n.Mods.diffNoMatch))
                    // L'échappatoire : sans elle, un filtre trop étroit est une
                    // impasse dont on ne voit pas la sortie.
                    Button(vm.L(L10n.Mods.diffClearFilters)) {
                        searchText = ""
                        filter = nil
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(groups) { group in
                                Section {
                                    if !collapsed.contains(group.id) {
                                        ForEach(group.rows) { row in
                                            DiffRowView(row: row,
                                                        emptyPlaceholder: vm.L(L10n.Mods.diffEmptyValue),
                                                        previousEnglishLabel: vm.L(L10n.Mods.diffPreviousEnglish),
                                                        needsReview: reviewNeededIDs.contains(row.id),
                                                        reviewLabel: vm.L(L10n.Mods.translationReviewNeeded))
                                                .contentShape(Rectangle())
                                                .onTapGesture { editing = row }
                                                // Rien n'indiquait qu'une
                                                // rangée s'ouvre : le curseur
                                                // le dit avant le clic.
                                                .pointingHandCursor()
                                            Divider()
                                        }
                                    }
                                } header: {
                                    // Rien pour un mod sans commentaire : avant ce
                                    // travail, un tel fichier n'affichait aucun
                                    // en-tête, et c'est la majorité du parc. Dès
                                    // qu'une section est titrée, tous les en-têtes
                                    // s'affichent — y compris celui du bloc sans
                                    // titre et celui de l'orphelin, qui séparent
                                    // alors utilement le contenu au lieu de mentir
                                    // sur une structure que le fichier n'a pas.
                                    if fileHasTitledSections {
                                        sectionHeader(group).id(group.id)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 460)
                    .onChange(of: scrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                        scrollTarget = nil
                    }
                    .sheet(item: $editing) { row in
                        // L'ordre **affiché**, filtre compris : « suivant »
                        // doit mener où l'œil irait, pas dans la liste
                        // complète que le filtre vient d'écarter. Les groupes
                        // repliés restent du voyage — replier est un confort
                        // de lecture, pas une exclusion.
                        let shown = groups.flatMap(\.rows)
                        let here = shown.firstIndex { $0.id == row.id }
                        TranslationEditorView(
                            vm: vm, mod: mod, locale: "fr", row: row,
                            previous: here.flatMap { $0 > 0 ? shown[$0 - 1] : nil },
                            next: here.flatMap { $0 + 1 < shown.count ? shown[$0 + 1] : nil },
                            onNavigate: { editing = $0 },
                            // Reprend exactement la séquence du `.task` initial :
                            // `rebuildGroups()` seul ne suffit pas, il filtre
                            // `allGroups`, qui ne serait pas recalculé — la ligne
                            // enregistrée garderait son ancien état à l'écran.
                            // `staleness` aussi : sans ce recalcul, le bandeau
                            // « l'anglais a changé après le français » pouvait
                            // rester affiché sur une clé qu'on vient justement
                            // de retraduire.
                            onSaved: {
                                Task {
                                    rows = await vm.translationDiff(for: mod)
                                    staleness = await vm.translationStaleness(for: mod)
                                    // Le drapeau part à l'enregistrement : le
                                    // badge et le compte du filtre suivent.
                                    reviewNeededIDs = await vm.reviewNeededRowIDs(for: mod)
                                    allGroups = TranslationCoverage.diffGroups(rows: rows)
                                    rebuildGroups()
                                }
                            },
                            isPresented: Binding(get: { editing != nil },
                                                 set: { if !$0 { editing = nil } }))
                    }
                }
            }
        }
    }

    /// Le nom des colonnes. Reprend les métriques partagées, sans quoi
    /// l'en-tête et les lignes dériveraient l'un de l'autre au premier
    /// ajustement.
    private var columnHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: DiffMetrics.spacing) {
            Color.clear.frame(width: DiffMetrics.glyphWidth, height: 1)
            Text(vm.L(L10n.Mods.diffColKey))
                .frame(width: DiffMetrics.keyWidth, alignment: .leading)
            Text(vm.L(L10n.Mods.diffColEnglish))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(vm.L(L10n.Mods.diffColFrench))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.secondary)
        .padding(.vertical, 5)
    }

    /// L'en-tête d'une section : ce qui la nomme, et ce qu'il y reste à faire.
    ///
    /// Le reste à faire se lit par un glyphe **et** une teinte, jamais par la
    /// couleur seule (`docs/audit-nana-ux.md` §1). Une section complète n'affiche
    /// rien : l'œil doit tomber sur ce qui reste.
    private func sectionHeader(_ group: TranslationCoverage.DiffGroup) -> some View {
        let isCollapsed = collapsed.contains(group.id)
        return Button {
            if isCollapsed { collapsed.remove(group.id) } else { collapsed.insert(group.id) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(title(of: group))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    // Le titre est tronqué à une ligne : deux sections homonymes
                    // (65 « Spring » sur Ridgeside) y restent indiscernables. La
                    // première clé du groupe est le discriminant qui existe déjà
                    // ailleurs (table des matières) ; l'offrir ici aussi en info-bulle.
                    .help(group.firstKey)
                Spacer(minLength: 8)
                RemainderBadges(group: group)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(AppDesign.Opacity.light))
            .overlay(alignment: .bottom) { Divider() }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    /// Le nom du groupe : sa section, préfixée du composant quand le mod en a
    /// plusieurs.
    ///
    /// Deux groupes n'ont pas de titre, et pour des raisons opposées : les clés
    /// d'avant le premier commentaire, en tête du fichier, et les orphelines —
    /// qui n'existent qu'en français et viennent après tout. Les coiffer du même
    /// « Avant la première section » serait faux dans les deux sens.
    ///
    /// Règle de préfixe partagée avec la table des matières via
    /// `DiffGroup.displayTitle` : deux copies avaient déjà divergé une fois
    /// dans ce fichier (`DiffStateStyle`), pas de raison d'en ouvrir une
    /// troisième.
    private func title(of group: TranslationCoverage.DiffGroup) -> String {
        group.displayTitle(fallback: vm.L(L10n.Mods.diffSectionUntitled),
                            orphan: vm.L(L10n.Mods.diffStateOrphan))
    }

    // MARK: - Données dérivées

    /// Vrai si **le fichier** porte au moins une section titrée par l'auteur —
    /// indépendant du filtre en cours. Gouverne l'affichage des en-têtes
    /// eux-mêmes (`table`, ci-dessus) : un mod sans commentaire ne doit jamais
    /// hériter d'un en-tête, filtre ou pas, sous peine d'une barre « Avant la
    /// première section » cliquable et repliable sur un tableau qui n'a pas de
    /// section — la régression corrigée dans cette passe.
    ///
    /// À dessein sur `allGroups`, pas `groups` : la présence des en-têtes ne
    /// doit pas clignoter au gré d'une recherche, seulement dépendre de ce que
    /// l'auteur a écrit dans le fichier.
    private var fileHasTitledSections: Bool {
        allGroups.contains { $0.title != nil }
    }

    /// Vrai si le bouton « Sections » a quelque chose à proposer **dans le
    /// filtre courant**. Porte sur `groups`, comme le popover qu'il ouvre : un
    /// `hasSections` lu sur `allGroups` survivrait à un filtre qui a vidé
    /// toutes les sections, pour ouvrir sur « aucune section ne correspond ».
    /// Et une entrée de la table des matières ne peut viser qu'un en-tête
    /// réellement présent dans la hiérarchie affichée — sinon le `scrollTo`
    /// qu'elle déclenche n'a pas de cible.
    private var hasSections: Bool {
        groups.contains { $0.title != nil }
    }

    /// Le filtre courant, appliqué rangée par rangée. `query` est calculée une
    /// fois par `rebuildGroups()`, pas ici : la recomputer à chaque rangée
    /// l'aurait fait jusqu'à ~17 910 fois par frappe, alors qu'une seule
    /// suffit.
    private func matches(_ row: TranslationCoverage.DiffRow, query: String) -> Bool {
        switch filter {
        case .state(let state) where row.state != state: return false
        case .reviewNeeded where !reviewNeededIDs.contains(row.id): return false
        default: break
        }
        guard !query.isEmpty else { return true }
        return row.key.lowercased().contains(query)
            || row.english.lowercased().contains(query)
            || row.french.lowercased().contains(query)
    }

    /// Réduit les groupes du fichier à ce que le filtre laisse voir. Les groupes
    /// eux-mêmes ne sont **pas** recalculés : leur identité vient du fichier, et
    /// un repli doit désigner la même section avant et après une frappe.
    private func rebuildGroups() {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        groups = allGroups.compactMap { group in group.filtered { matches($0, query: query) } }
        filterSummary = FilterSummary(rows: rows, reviewNeededIDs: reviewNeededIDs)
    }

    /// Ce que la barre de filtres a besoin de savoir des rangées : un compte
    /// par état, le compte « À relire » et s'il reste du travail pour le lot.
    private struct FilterSummary {
        var counts: [TranslationCoverage.DiffRow.State: Int] = [:]
        var reviewCount = 0
        var hasBatchWork = false

        init() {}

        init(rows: [TranslationCoverage.DiffRow], reviewNeededIDs: Set<String>) {
            counts = Dictionary(grouping: rows, by: \.state).mapValues(\.count)
            // « À relire » compte les clés du drapeau encore présentes dans
            // les rangées : les drapeaux des clés disparues ne grossissent
            // pas le filtre, elles ne mènent nulle part.
            reviewCount = rows.filter { reviewNeededIDs.contains($0.id) }.count
            hasBatchWork = !TranslationBatchPlanner.eligibleRows(rows).isEmpty
        }
    }

    // MARK: - Vocabulaire des états

    private func label(for state: TranslationCoverage.DiffRow.State) -> String {
        let key: String
        switch state {
        case .translated:        key = L10n.Mods.diffStateTranslated
        case .missing:           key = L10n.Mods.diffStateMissing
        case .empty:             key = L10n.Mods.diffStateEmpty
        case .identicalToSource: key = L10n.Mods.diffStateIdentical
        case .orphan:            key = L10n.Mods.diffStateOrphan
        case .outdated:          key = L10n.Mods.diffStateOutdated
        }
        return vm.L(key)
    }
}

/// Le vocabulaire visuel d'un état, partagé par la barre de filtres, les
/// en-têtes de section, les lignes et la table des matières.
///
/// Un seul exemplaire : des copies divergentes de la même logique ont déjà
/// coûté un bug d'affichage ici. Un état se lit par le glyphe **et** par la
/// teinte, chacun suffisant seul — un diff dont le sens tiendrait à la couleur
/// serait illisible pour un daltonien (`docs/audit-nana-ux.md` §1).
enum DiffStateStyle {
    static func glyph(_ state: TranslationCoverage.DiffRow.State) -> String {
        switch state {
        case .translated:        return "checkmark.circle"
        case .missing:           return "text.badge.minus"
        case .empty:             return "exclamationmark.triangle.fill"
        case .identicalToSource: return "equal.circle"
        case .orphan:            return "questionmark.circle"
        case .outdated:          return "clock.badge.exclamationmark"
        }
    }

    static func tint(_ state: TranslationCoverage.DiffRow.State) -> Color {
        switch state {
        case .translated:
            return Color(red: 0.20, green: 0.62, blue: 0.34)
        case .empty:
            // Le seul état qui casse vraiment l'affichage : rien ne s'affiche
            // en jeu, sans même retomber sur l'anglais.
            return .orange
        case .missing, .identicalToSource, .orphan:
            // Une clé absente laisse l'anglais s'afficher — c'est du travail
            // restant, pas une panne. La peindre en rouge crierait au loup.
            return .secondary
        case .outdated:
            // Violet : ni alarmant comme le rouge — le mod fonctionne — ni
            // satisfait comme le vert. Ce violet d'état ne paraît jamais dans
            // le texte d'une valeur, où seul le violet des tokens a cours :
            // deux teintes, deux significations, jamais sur la même surface.
            return Color(red: 0.55, green: 0.35, blue: 0.75)
        }
    }
}

/// Ce qu'il reste à faire dans un groupe : les vides d'abord — le seul état
/// qui casse l'affichage en jeu —, puis les obsolètes, puis les manquantes.
/// Ces trois-là seulement : ce sont les états qui représentent du travail
/// restant, à la différence de « traduite » ou « identique à l'anglais ».
/// Sans les obsolètes ici, une section entièrement dépassée par l'anglais
/// s'afficherait comme si elle était finie — sur un fichier à 1 881 sections,
/// c'est justement là qu'on repère où se trouve le travail. Partagé par
/// l'en-tête de section et la table des matières : une même composition qui
/// existait en double a déjà divergé une fois dans ce fichier
/// (`DiffStateStyle`), pas de raison de reproduire l'erreur ici. Seul
/// l'espacement extérieur varie d'un endroit à l'autre.
struct RemainderBadges: View {
    let group: TranslationCoverage.DiffGroup
    var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            ForEach([TranslationCoverage.DiffRow.State.empty, .outdated, .missing], id: \.self) { state in
                let count = group.remaining(state)
                if count > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: DiffStateStyle.glyph(state)).font(.system(size: 9))
                        Text("\(count)")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    }
                    .foregroundColor(DiffStateStyle.tint(state))
                }
            }
        }
    }
}

/// Les largeurs de colonne, partagées par l'en-tête et les lignes. Deux jeux de
/// nombres séparés auraient dérivé au premier ajustement, et l'en-tête aurait
/// alors désigné la mauvaise colonne — pire que pas d'en-tête du tout.
private enum DiffMetrics {
    static let spacing: CGFloat = 10
    static let glyphWidth: CGFloat = 14
    static let keyWidth: CGFloat = 150
}

/// Une ligne du diff : la clé, l'anglais, le français, et l'état marqué à la
/// fois par un glyphe et par la teinte.
private struct DiffRowView: View {
    let row: TranslationCoverage.DiffRow
    let emptyPlaceholder: String
    let previousEnglishLabel: String
    /// « Écrit sans être relu » par le lot : un badge discret, jamais un
    /// état — la rangée reste ce qu'elle est, le drapeau dit d'où vient sa
    /// valeur.
    let needsReview: Bool
    let reviewLabel: String

    var body: some View {
        HStack(alignment: .top, spacing: DiffMetrics.spacing) {
            // Aucun `.textSelection(.enabled)` sur cette rangée, et c'est
            // délibéré : il couvrait la clé et les deux colonnes, donc presque
            // toute la surface, et **avalait le clic** — seuls l'icône d'état
            // et les marges ouvraient l'éditeur, le reste affichant un curseur
            // de sélection. La rangée a une action principale, ouvrir
            // l'éditeur ; copier un texte reste possible dans l'éditeur, où les
            // deux valeurs sont sélectionnables.
            Image(systemName: DiffStateStyle.glyph(row.state))
                .font(.system(size: 10))
                .foregroundColor(DiffStateStyle.tint(row.state))
                .frame(width: DiffMetrics.glyphWidth)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(row.key)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                if needsReview {
                    // Discret : un glyphe orange collé à la clé, nommé au
                    // survol — le glyphe ET la teinte, comme pour les états.
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                        .help(reviewLabel)
                        .accessibilityLabel(reviewLabel)
                }
            }
            .frame(width: DiffMetrics.keyWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                tokenised(row.english)
                // L'ancien anglais sous le nouveau, barré : c'est ce qui permet
                // de juger si le français tient encore. Un simple « obsolète »
                // obligerait à aller chercher soi-même ce qui a changé.
                if let previous = row.previousEnglish {
                    Text(String(format: previousEnglishLabel, previous))
                        .font(.system(size: 10))
                        .strikethrough()
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            frenchColumn
        }
        .padding(.vertical, 4)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Une valeur vide ne peut pas s'afficher comme une chaîne vide : la ligne
    /// paraîtrait simplement non traduite, alors que c'est le cas le plus grave.
    @ViewBuilder
    private var frenchColumn: some View {
        if row.state == .empty {
            Text(emptyPlaceholder)
                .font(.system(size: 11).italic())
                .foregroundColor(DiffStateStyle.tint(.empty))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            tokenised(row.french)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Rend la valeur en distinguant ce qui se traduit de ce qui doit être
    /// repris tel quel.
    ///
    /// Un token n'est pas du texte : le montrer comme tel laisse un traducteur
    /// le réécrire de bonne foi, et le mod cesse alors de fonctionner. La chasse
    /// fixe et le fond le sortent de la phrase sans le masquer — il faut
    /// pouvoir le recopier.
    private func tokenised(_ value: String) -> Text {
        TranslationTokens.split(value).reduce(Text("")) { accumulated, segment in
            let piece = segment.isCode
                ? Text(segment.text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.purple)
                : Text(segment.text).font(.system(size: 11))
            return accumulated + piece
        }
    }
}
