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

    @State private var rows: [TranslationCoverage.DiffRow] = []
    @State private var isLoading = true
    @State private var stateFilter: TranslationCoverage.DiffRow.State?
    @State private var searchText = ""
    /// Les groupes tels que le fichier les donne, calculés **une fois** sur les
    /// rangées complètes. Leur identité ne dépend donc jamais du filtre en
    /// cours : c'est ce qui permet à un repli de désigner toujours la même
    /// section, quoi qu'on tape dans la recherche.
    @State private var allGroups: [TranslationCoverage.DiffGroup] = []
    /// Ce que la vue affiche : les mêmes groupes, réduits aux rangées retenues.
    @State private var groups: [TranslationCoverage.DiffGroup] = []
    /// Les sections repliées, par identité de groupe. Déplié par défaut : le
    /// repliage est une aide à la navigation, pas un correctif de performance —
    /// le `LazyVStack` encaisse déjà 11 021 clés.
    @State private var collapsed: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                loadingRow
            } else if rows.isEmpty {
                emptyRow(vm.L(L10n.Mods.diffNone))
            } else {
                filterBar
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
            // Le regroupement une seule fois, sur les rangées complètes.
            allGroups = TranslationCoverage.diffGroups(rows: rows)
            // Les groupes avant le drapeau : sans quoi une passe de rendu
            // pourrait tomber sur des rangées sans groupes et afficher
            // brièvement « aucune clé ne correspond ».
            rebuildGroups()
            isLoading = false
        }
        // Le regroupement ne peut pas vivre dans `body` : regrouper 17 910
        // lignes à chaque frappe rendrait la recherche inutilisable.
        .onChange(of: stateFilter) { _, _ in rebuildGroups() }
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
        let counts = Dictionary(grouping: rows, by: \.state).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                filterChip(nil, label: vm.L(L10n.Mods.diffStateAll), count: rows.count)
                ForEach(TranslationCoverage.DiffRow.State.allCases, id: \.self) { state in
                    if let count = counts[state], count > 0 {
                        filterChip(state, label: label(for: state), count: count)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField(vm.L(L10n.Mods.diffSearch), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                if groups.count > 1 {
                    Button(vm.L(collapsed.isEmpty ? L10n.Mods.diffCollapseAll
                                                  : L10n.Mods.diffExpandAll)) {
                        collapsed = collapsed.isEmpty ? Set(groups.map(\.id)) : []
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                }
            }
        }
        .padding(.bottom, 10)
    }

    private func filterChip(_ state: TranslationCoverage.DiffRow.State?,
                            label: String, count: Int) -> some View {
        let isSelected = stateFilter == state
        return Button {
            stateFilter = isSelected ? nil : state
        } label: {
            HStack(spacing: 4) {
                if let state { Image(systemName: DiffStateStyle.glyph(state)).font(.system(size: 9)) }
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
            .foregroundColor(state.map(DiffStateStyle.tint) ?? .primary)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
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
                        stateFilter = nil
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups) { group in
                            Section {
                                if !collapsed.contains(group.id) {
                                    ForEach(group.rows) { row in
                                        DiffRowView(row: row,
                                                    emptyPlaceholder: vm.L(L10n.Mods.diffEmptyValue))
                                        Divider()
                                    }
                                }
                            } header: {
                                sectionHeader(group)
                            }
                        }
                    }
                }
                .frame(maxHeight: 460)
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
                Spacer(minLength: 8)
                remainderBadges(group)
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

    /// Ce qu'il reste à faire dans la section, tel que le filtre en cours le
    /// laisse voir. Les vides d'abord : c'est le seul état qui casse l'affichage
    /// en jeu.
    @ViewBuilder
    private func remainderBadges(_ group: TranslationCoverage.DiffGroup) -> some View {
        HStack(spacing: 8) {
            ForEach([TranslationCoverage.DiffRow.State.empty, .missing], id: \.self) { state in
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

    /// Le nom du groupe : sa section, préfixée du composant quand le mod en a
    /// plusieurs.
    ///
    /// Deux groupes n'ont pas de titre, et pour des raisons opposées : les clés
    /// d'avant le premier commentaire, en tête du fichier, et les orphelines —
    /// qui n'existent qu'en français et viennent après tout. Les coiffer du même
    /// « Avant la première section » serait faux dans les deux sens.
    private func title(of group: TranslationCoverage.DiffGroup) -> String {
        let fallback = group.isOrphan ? L10n.Mods.diffStateOrphan
                                      : L10n.Mods.diffSectionUntitled
        let section = (group.isOrphan ? nil : group.title) ?? vm.L(fallback)
        return group.component.map { "\($0) — \(section)" } ?? section
    }

    // MARK: - Données dérivées

    /// Le filtre courant, appliqué rangée par rangée. `query` est calculée une
    /// fois par `rebuildGroups()`, pas ici : la recomputer à chaque rangée
    /// l'aurait fait jusqu'à ~17 910 fois par frappe, alors qu'une seule
    /// suffit.
    private func matches(_ row: TranslationCoverage.DiffRow, query: String) -> Bool {
        if let stateFilter, row.state != stateFilter { return false }
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

    var body: some View {
        HStack(alignment: .top, spacing: DiffMetrics.spacing) {
            Image(systemName: DiffStateStyle.glyph(row.state))
                .font(.system(size: 10))
                .foregroundColor(DiffStateStyle.tint(row.state))
                .frame(width: DiffMetrics.glyphWidth)
            Text(row.key)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: DiffMetrics.keyWidth, alignment: .leading)
                .textSelection(.enabled)
            tokenised(row.english)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
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
                .textSelection(.enabled)
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
