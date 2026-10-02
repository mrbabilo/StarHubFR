import SwiftUI

// MARK: - SavesView

struct SavesView: View {
    /// ⌘F amène ici (voir `SearchFieldShortcut`).
    @FocusState private var searchFocused: Bool

     @Bindable var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State private var searchText = ""

    var filteredSaves: [SaveGameInfo] {
        vm.saves.filter {
            $0.playerName.localizedCaseInsensitiveContains(searchText) ||
            $0.farmName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        // Patron page de liste du dépôt : en-tête fixe en deux rangées
        // (en-tête de page + actions ; recherche, tri et filtre en chips),
        // contenu qui défile, pied fixe portant le compte honnête.
        VStack(spacing: 0) {
            // ── En-tête fixe ────────────────────────────────────────────
            // En-tête commun des pages (audit UX 2026-10-02) : la tuile de la
            // barre latérale, le titre, ce qui existe ; disposition,
            // rechargement et données à droite.
            VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                PageHeader(icon: "folder.fill", title: localization.L(L10n.Saves.saves),
                           subtitle: headerSummary) {
                    Picker(localization.L(L10n.Saves.listViewHint), selection: $vm.saveViewMode) {
                        Image(systemName: "list.bullet")
                            .tag(SaveViewMode.list)
                        Image(systemName: "square.grid.2x2")
                            .tag(SaveViewMode.grid)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 64)
                    .help(vm.saveViewMode == .list
                          ? localization.L(L10n.Saves.listViewHint)
                          : localization.L(L10n.Saves.gridViewHint))

                    Button(action: { vm.reloadSaves() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(AppDesign.Font.caption)
                    }
                    .buttonStyle(.bordered)
                    .iconHelp(localization.L(L10n.Saves.reloadHint))
                    SavesDataActions(vm: vm, localization: localization) // sorti des Réglages
                }

                // Rangée « affiner la liste » : recherche à la frappe, tri et
                // filtre par tag en chips au motif Mods. La barre système
                // `.searchable` est partie : un geste, une place (P3).
                HStack(spacing: AppDesign.Spacing.sm) {
                    searchField

                    Divider()
                        .frame(height: 16)

                    sortMenu

                    Divider()
                        .frame(height: 16)

                    tagMenu

                    Spacer()
                }
            }
            .padding(.horizontal, AppDesign.Spacing.xl)
            .padding(.vertical, AppDesign.Spacing.md)
            .background(AppDesign.Color.windowBg)

            Divider()

            // ── Contenu ─────────────────────────────────────────────────
            if vm.saves.isEmpty {
                VStack(spacing: AppDesign.Spacing.lg) {
                    Spacer()
                    IconTile(icon: "folder.badge.questionmark", tint: AppDesign.Color.accent, size: 64)
                    Text(localization.L(L10n.Saves.noSaves))
                        .multilineTextAlignment(.center)
                        .font(AppDesign.Font.body)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if vm.saveViewMode == .grid {
                SavesGridView(vm: vm, localization: localization, saves: searchText.isEmpty ? vm.savesHierarchy.map(\.info) : filteredSaves)
            } else {
                // La liste, sortie du `Form` : le compte et la note de
                // récupération vivent dans le footer fixe ci-dessous, plus
                // dans un header/footer de Section.
                ScrollView(showsIndicators: false) {
                    // La liste en une carte : les lignes et leurs branches de
                    // sauvegardes de secours restent paresseuses.
                    LazyVStack(spacing: 0) {
                        if searchText.isEmpty {
                            SaveTreeListView(vm: vm, localization: localization, nodes: vm.savesHierarchy, depth: 0)
                        } else {
                            ForEach(filteredSaves, id: \.id) { save in
                                Button(action: { vm.navigationStore.setEditingSave(save) }) {
                                    SaveRow(vm: vm, localization: localization, save: save, depth: 0, hasChildren: false, isExpanded: false, onToggleExpand: nil)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .cardSurface(padding: AppDesign.Spacing.sm)
                    .padding(.horizontal, AppDesign.Spacing.xl)
                    .padding(.vertical, AppDesign.Spacing.lg)
                }
            }

            // ── Footer fixe ─────────────────────────────────────────────
            // Le compte honnête (P2) : ce qui est montré sur ce qui existe,
            // liste comme grille — l'ancien header de Section ne le portait
            // qu'en liste.
            if !vm.saves.isEmpty {
                Divider()
                HStack {
                    Text(String(format: localization.L(L10n.Saves.allSaves), Int64(displayedCount)))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(localization.L(L10n.Saves.autoFetch))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, AppDesign.Spacing.xl)
                .padding(.vertical, 10)
                .background(AppDesign.Color.windowBg)
            }
        }
        .background(AppDesign.Color.windowBg)
        .sheet(item: $vm.saveToDuplicate) { save in
            DuplicateSaveSheet(vm: vm, localization: localization, save: save)
        }
    }

    /// « 4 parties · dernière jouée : Zofia (Ferme Lune) » — ce qui existe et
    /// ce qu'on reprendra, avant la liste.
    private var headerSummary: String? {
        let farms = vm.savesHierarchy.map(\.info)
        guard let last = farms.max(by: { $0.lastModified < $1.lastModified }) else { return nil }
        return String(format: localization.L(L10n.Saves.headerSummary),
                      Int64(farms.count), last.playerName, last.farmName)
    }

    /// L'effectif affiché par le mode courant : la hiérarchie complète, ou
    /// le filtré quand la recherche est à l'œuvre. Liste et grille montrent
    /// le même compte — la densité ne change pas ce qui existe.
    private var displayedCount: Int {
        searchText.isEmpty ? vm.savesHierarchy.count : filteredSaves.count
    }

    /// La recherche en toolbar, au motif des journaux et de Mods : loupe,
    /// champ plein texte, effacement 18×18 (un glyph nu rendrait `.help`
    /// muet — a11y §7). Filtrage à la frappe, comme `.searchable` le
    /// donnait ; le même prédicat qu'avant (joueur ∪ ferme).
    private var searchField: some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(AppDesign.Font.iconXS)
                .foregroundColor(.secondary)
            TextField(localization.L(L10n.Saves.searchPlaceholder), text: $searchText)
                .textFieldStyle(.plain)
                .searchFieldShortcut($searchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .frame(width: 18, height: 18)
                .contentShape(.rect)
                .iconHelp(localization.L(L10n.Discovery.clearSearch))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(AppDesign.Opacity.light))
        .cornerRadius(AppDesign.Radius.sm)
        .frame(maxWidth: 220)
    }

    /// Le tri, en chip au motif Mods. Items et coches inchangés.
    private var sortMenu: some View {
        Menu {
            Button(action: { vm.saveSortOption = .lastPlayed }) {
                HStack { Image(systemName: "clock"); Text(localization.L(L10n.Saves.sortLastPlayed)) }
                if vm.saveSortOption == .lastPlayed { Image(systemName: "checkmark") }
            }
            Button(action: { vm.saveSortOption = .name }) {
                HStack {
                    Image(systemName: "a.square")
                    Text(localization.L(L10n.Saves.sortName))
                }
                if vm.saveSortOption == .name { Image(systemName: "checkmark") }
            }
            Button(action: { vm.saveSortOption = .money }) {
                HStack { Image(systemName: "dollarsign"); Text(localization.L(L10n.Saves.sortMoney)) }
                if vm.saveSortOption == .money { Image(systemName: "checkmark") }
            }
        } label: {
            chipLabel(icon: "arrow.up.arrow.down",
                      text: sortLabel,
                      prominent: false)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// Le filtre par tag, en chip. Le chip s'allume quand un tag retient
    /// la liste — l'état du filtre se voit avant d'ouvrir le menu.
    private var tagMenu: some View {
        Menu {
            Button(action: { vm.saveFilterTag = "" }) {
                HStack { Image(systemName: "tray.2"); Text(localization.L(L10n.Saves.filterAll)) }
                if vm.saveFilterTag.isEmpty { Image(systemName: "checkmark") }
            }
            Divider()
            ForEach(vm.availableFilterTags, id: \.self) { tag in
                Button(action: { vm.saveFilterTag = (vm.saveFilterTag == tag ? "" : tag) }) {
                    Text(tag)
                    if vm.saveFilterTag == tag { Image(systemName: "checkmark") }
                }
            }
        } label: {
            chipLabel(icon: vm.saveFilterTag.isEmpty ? "tag" : "tag.fill",
                      text: vm.saveFilterTag.isEmpty ? localization.L(L10n.Saves.filterTag) : vm.saveFilterTag,
                      prominent: !vm.saveFilterTag.isEmpty)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// L'habillage commun des chips de la rangée secondaire.
    private func chipLabel(icon: String, text: String, prominent: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(AppDesign.Font.footnote)
            Text(text)
                .font(AppDesign.Font.caption(.medium))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(AppDesign.Font.iconXXS(.bold))
                .foregroundColor(.secondary)
        }
        .foregroundColor(prominent ? .accentColor : .primary)
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
    
    var sortLabel: String {
        switch vm.saveSortOption {
        case .name:       return localization.L(L10n.Saves.sortLabelName)
        case .lastPlayed: return localization.L(L10n.Saves.sortLabelLastPlayed)
        case .money:      return localization.L(L10n.Saves.sortLabelMoney)
        }
    }
}
