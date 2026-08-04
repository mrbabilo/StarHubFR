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
                // concurrencé l'épinglage des en-têtes de composant ; au-dessus,
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
            isLoading = false
        }
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
            TextField(vm.L(L10n.Mods.diffSearch), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
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
                if let state { Image(systemName: glyph(for: state)).font(.system(size: 9)) }
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
            .foregroundColor(state.map(tint) ?? .primary)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - Table

    private var table: some View {
        let visible = filteredRows
        return Group {
            if visible.isEmpty {
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
                        ForEach(groupedRows, id: \.component) { group in
                            Section {
                                ForEach(group.rows) { row in
                                    DiffRowView(row: row,
                                                emptyPlaceholder: vm.L(L10n.Mods.diffEmptyValue))
                                    Divider()
                                }
                            } header: {
                                // Un mod à un seul dossier `i18n` n'a pas
                                // d'en-tête : répéter son nom sur chaque écran
                                // serait du bruit.
                                if let component = group.component {
                                    componentHeader(component)
                                }
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

    private func componentHeader(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Données dérivées

    private var filteredRows: [TranslationCoverage.DiffRow] {
        var visible = stateFilter.map { state in rows.filter { $0.state == state } } ?? rows
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return visible }
        visible = visible.filter {
            $0.key.lowercased().contains(query)
                || $0.english.lowercased().contains(query)
                || $0.french.lowercased().contains(query)
        }
        return visible
    }

    /// Les rangées regroupées par composant, dans l'ordre où le Core les a
    /// rendues — il les a déjà triées, on ne retrie pas.
    private var groupedRows: [(component: String?, rows: [TranslationCoverage.DiffRow])] {
        var groups: [(component: String?, rows: [TranslationCoverage.DiffRow])] = []
        for row in filteredRows {
            if let last = groups.last, last.component == row.component {
                groups[groups.count - 1].rows.append(row)
            } else {
                groups.append((row.component, [row]))
            }
        }
        return groups
    }

    // MARK: - Vocabulaire des états

    private func label(for state: TranslationCoverage.DiffRow.State) -> String {
        switch state {
        case .translated:        return vm.L(L10n.Mods.diffStateTranslated)
        case .missing:           return vm.L(L10n.Mods.diffStateMissing)
        case .empty:             return vm.L(L10n.Mods.diffStateEmpty)
        case .identicalToSource: return vm.L(L10n.Mods.diffStateIdentical)
        case .orphan:            return vm.L(L10n.Mods.diffStateOrphan)
        }
    }

    private func glyph(for state: TranslationCoverage.DiffRow.State) -> String {
        switch state {
        case .translated:        return "checkmark.circle"
        case .missing:           return "text.badge.minus"
        case .empty:             return "exclamationmark.triangle.fill"
        case .identicalToSource: return "equal.circle"
        case .orphan:            return "questionmark.circle"
        }
    }

    private func tint(for state: TranslationCoverage.DiffRow.State) -> Color {
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
            Image(systemName: glyph)
                .font(.system(size: 10))
                .foregroundColor(tint)
                .frame(width: DiffMetrics.glyphWidth)
            Text(row.key)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: DiffMetrics.keyWidth, alignment: .leading)
                .textSelection(.enabled)
            Text(row.english)
                .font(.system(size: 11))
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
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(row.french)
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var glyph: String {
        switch row.state {
        case .translated:        return "checkmark.circle"
        case .missing:           return "text.badge.minus"
        case .empty:             return "exclamationmark.triangle.fill"
        case .identicalToSource: return "equal.circle"
        case .orphan:            return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch row.state {
        case .translated:        return Color(red: 0.20, green: 0.62, blue: 0.34)
        case .empty:             return .orange
        case .missing, .identicalToSource, .orphan: return .secondary
        }
    }
}
