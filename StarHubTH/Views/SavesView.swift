import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Presets shared by both save-avatar renderers below (identifier → SF Symbol name).
private let saveAvatarPresets: [(String, String)] = [
    ("preset:person", "person.crop.circle.fill"),
    ("preset:star", "star.fill"),
    ("preset:leaf", "leaf.fill"),
    ("preset:heart", "heart.fill"),
    ("preset:cat", "cat.fill"),
    ("preset:dog", "dog.fill"),
    ("preset:hare", "hare.fill"),
    ("preset:ant", "ant.fill"),
]

// MARK: - SaveAvatarViewLocal (renders a resolved iconPath, no vm needed)
struct SaveAvatarViewLocal: View {
    let iconPath: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))

            if iconPath.hasPrefix("preset:") {
                let sfName = saveAvatarPresets.first(where: { $0.0 == iconPath })?.1 ?? "person.crop.circle.fill"
                Image(systemName: sfName)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color.accentColor.opacity(0.8))
                    .padding(size * 0.18)
            } else if !iconPath.isEmpty, let img = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundColor(Color.accentColor.opacity(0.8))
                    .frame(width: size * 0.8, height: size * 0.8)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - SaveAvatarView (resolves iconPath from the save's note, then
// delegates rendering to SaveAvatarViewLocal so the two can't drift apart)
struct SaveAvatarView: View {
    let folderName: String
    let size: CGFloat
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        SaveAvatarViewLocal(iconPath: vm.getNote(for: folderName).customIconPath ?? "", size: size)
    }
}

// MARK: - SavesView
extension SaveGameInfo {
    /// « Ferme · An 3 Printemps 14 » — le sous-titre commun à la rangée de
    /// liste et au hero de la fiche : une seule écriture, pas deux qui
    /// divergent. Le format et la saison localisée viennent de l'appelant,
    /// qui seul connaît la langue.
    fileprivate func farmDayLine(format: String, localizedSeason: String) -> String {
        "\(farmName) · \(String(format: format, year, localizedSeason, day))"
    }
}

struct SavesView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var searchText = ""

    var filteredSaves: [SaveGameInfo] {
        vm.saves.filter {
            $0.playerName.localizedCaseInsensitiveContains(searchText) ||
            $0.farmName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        // Patron page de liste du dépôt, calé sur le pilote Mods : toolbar
        // fixe en deux rangées (primaire : recherche + disposition ;
        // secondaire : tri et filtre en chips), contenu qui scrolle, footer
        // fixe portant le compte honnête.
        VStack(spacing: 0) {
            // ── Toolbar fixe ────────────────────────────────────────────
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                // Rangée primaire : recherche à la frappe + disposition +
                // rechargement. La barre système `.searchable` est partie :
                // un geste, une place (P3).
                HStack {
                    searchField

                    Spacer()

                    Picker(vm.L(L10n.Saves.listViewHint), selection: $vm.saveViewMode) {
                        Image(systemName: "list.bullet")
                            .tag(SaveViewMode.list)
                        Image(systemName: "square.grid.2x2")
                            .tag(SaveViewMode.grid)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 64)
                    .help(vm.saveViewMode == .list
                          ? vm.L(L10n.Saves.listViewHint)
                          : vm.L(L10n.Saves.gridViewHint))

                    Button(action: { vm.reloadSaves() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(AppDesign.Font.caption)
                    }
                    .buttonStyle(.bordered)
                    .help(vm.L(L10n.Saves.reloadHint))
                }

                // Rangée secondaire : tri et filtre par tag, en chips au
                // motif Mods — un bloc « affiner la liste ».
                HStack(spacing: AppDesign.Spacing.sm) {
                    sortMenu

                    Divider()
                        .frame(height: 16)

                    tagMenu

                    Spacer()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // ── Contenu ─────────────────────────────────────────────────
            if vm.saves.isEmpty {
                VStack(spacing: AppDesign.Spacing.lg) {
                    Spacer()
                    Image(systemName: "cloud.bolt")
                        .font(AppDesign.Font.emptyScopeGlyph)
                        .foregroundColor(.secondary.opacity(AppDesign.Opacity.disabled))
                    Text(vm.L(L10n.Saves.noSaves))
                        .multilineTextAlignment(.center)
                        .font(AppDesign.Font.body)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if vm.saveViewMode == .grid {
                SavesGridView(vm: vm, saves: searchText.isEmpty ? vm.savesHierarchy.map(\.info) : filteredSaves)
            } else {
                // La liste, sortie du `Form` : le compte et la note de
                // récupération vivent dans le footer fixe ci-dessous, plus
                // dans un header/footer de Section.
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if searchText.isEmpty {
                            SaveTreeListView(vm: vm, nodes: vm.savesHierarchy, depth: 0)
                        } else {
                            ForEach(filteredSaves, id: \.id) { save in
                                Button(action: { vm.editingSave = save }) {
                                    SaveRow(vm: vm, save: save, depth: 0, hasChildren: false, isExpanded: false, onToggleExpand: nil)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, AppDesign.Spacing.lg)
                }
            }

            // ── Footer fixe ─────────────────────────────────────────────
            // Le compte honnête (P2) : ce qui est montré sur ce qui existe,
            // liste comme grille — l'ancien header de Section ne le portait
            // qu'en liste.
            if !vm.saves.isEmpty {
                Divider()
                HStack {
                    Text(String(format: vm.L(L10n.Saves.allSaves), Int64(displayedCount)))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(vm.L(L10n.Saves.autoFetch))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(item: $vm.saveToDuplicate) { save in
            DuplicateSaveSheet(vm: vm, save: save)
        }
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
            TextField(vm.L(L10n.Saves.searchPlaceholder), text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .frame(width: 18, height: 18)
                .contentShape(.rect)
                .help(vm.L(L10n.Discovery.clearSearch))
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
                HStack { Image(systemName: "clock"); Text(vm.L(L10n.Saves.sortLastPlayed)) }
                if vm.saveSortOption == .lastPlayed { Image(systemName: "checkmark") }
            }
            Button(action: { vm.saveSortOption = .name }) {
                HStack {
                    Image(systemName: "a.square")
                    Text(vm.L(L10n.Saves.sortName))
                }
                if vm.saveSortOption == .name { Image(systemName: "checkmark") }
            }
            Button(action: { vm.saveSortOption = .money }) {
                HStack { Image(systemName: "dollarsign"); Text(vm.L(L10n.Saves.sortMoney)) }
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
                HStack { Image(systemName: "tray.2"); Text(vm.L(L10n.Saves.filterAll)) }
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
                      text: vm.saveFilterTag.isEmpty ? vm.L(L10n.Saves.filterTag) : vm.saveFilterTag,
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
        case .name:       return vm.L(L10n.Saves.sortLabelName)
        case .lastPlayed: return vm.L(L10n.Saves.sortLabelLastPlayed)
        case .money:      return vm.L(L10n.Saves.sortLabelMoney)
        }
    }
}

// MARK: - Grid View
struct SavesGridView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let saves: [SaveGameInfo]
    let columns = [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 16)]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(saves) { save in
                    SaveCardView(vm: vm, save: save)
                }
            }
            .padding(20)
        }
    }
}

struct SaveCardView: View {
    @State private var confirmingDelete = false
    @ObservedObject var vm: StarHubTHViewModel
    let save: SaveGameInfo
    @State private var isHovered = false
    
    var body: some View {
        Button(action: { vm.editingSave = save }) {
            VStack(spacing: AppDesign.Spacing.md) {
                SaveAvatarView(folderName: save.folderName, size: 64, vm: vm)

                VStack(spacing: 2) {
                    let note = vm.getNote(for: save.folderName)
                    HStack(spacing: AppDesign.Spacing.xs) {
                        if !note.tag.isEmpty {
                            Text(note.tag).font(AppDesign.Font.body)
                        }
                        Text(save.playerName)
                            .font(AppDesign.Font.caption(.semibold))
                            .lineLimit(1)
                    }
                    Text(save.farmName)
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text(String(format: vm.L(L10n.Saves.yearDayFormat), save.year, vm.L(save.seasonName), save.day))
                        .font(AppDesign.Font.iconXS)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(isHovered ? Color.accentColor.opacity(AppDesign.Opacity.light)
                                  : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(AppDesign.Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.lg)
                    .stroke(isHovered ? Color.accentColor.opacity(AppDesign.Opacity.medium)
                                      : Color.secondary.opacity(AppDesign.Opacity.light),
                            lineWidth: 1)
            )
            // Pas de `scaleEffect` de survol : un mouvement que « réduire les
            // animations » ne coupe pas proprement — cohérent avec les cartes
            // Mods du pilote.
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(vm.L(L10n.Saves.edit)) { vm.editingSave = save }
            Button(vm.L(L10n.Saves.timeline)) { vm.viewingSaveTimeline = save }
            Divider()
            Button(vm.L(L10n.Saves.duplicate)) { vm.saveToDuplicate = save }
            Button(vm.L(L10n.Saves.openFolder)) { vm.openSaveInFinder(info: save) }
            Divider()
            Button(vm.L(L10n.Saves.deleteSave), role: .destructive) {
                confirmingDelete = true
            }
            .disabled(vm.isSaveOperationRunning)
        }
        // Supprimer une partie envoie tout son dossier à la corbeille. La
        // suppression d'une **sauvegarde de secours** confirmait déjà (audit
        // 2026-08-05) ; celle de la partie elle-même ne confirmait pas, ce qui
        // était l'inverse du risque.
        .confirmationDialog(vm.L(L10n.Saves.confirmDeleteSave),
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(vm.L(L10n.Saves.deleteSave), role: .destructive) {
                Task { await vm.deleteSave(info: save) }
            }
            Button(vm.L(L10n.Saves.cancel), role: .cancel) {}
        } message: {
            Text(vm.L(L10n.Saves.confirmDeleteSaveMsg))
        }
    }
}

// MARK: - Tree List View
struct SaveTreeListView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let nodes: [SaveNode]
    let depth: Int
    @State private var expandedSaves: Set<String> = []
    
    var body: some View {
        ForEach(nodes) { node in
            let hasChildren = !node.children.isEmpty
            let isExpanded = expandedSaves.contains(node.info.folderName)
            
            Button(action: { vm.editingSave = node.info }) {
                SaveRow(
                    vm: vm,
                    save: node.info,
                    depth: depth,
                    hasChildren: hasChildren,
                    isExpanded: isExpanded,
                    onToggleExpand: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded {
                                expandedSaves.remove(node.info.folderName)
                            } else {
                                expandedSaves.insert(node.info.folderName)
                            }
                        }
                    }
                )
            }
            .buttonStyle(.plain)
            
            if hasChildren && isExpanded {
                SaveTreeListView(vm: vm, nodes: node.children, depth: depth + 1)
            }
        }
    }
}

// MARK: - Save Row (List)
struct SaveRow: View {
    @State private var confirmingDelete = false
    @ObservedObject var vm: StarHubTHViewModel
    let save: SaveGameInfo
    let depth: Int
    
    var hasChildren: Bool = false
    var isExpanded: Bool = false
    var onToggleExpand: (() -> Void)? = nil
    
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            if depth > 0 {
                HStack(spacing: AppDesign.Spacing.xs) {
                    Spacer().frame(width: CGFloat(depth) * 16 - 8)
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundColor(.secondary.opacity(AppDesign.Opacity.disabled))
                        .font(AppDesign.Font.iconXS)
                }
            }

            // Expand/Collapse Chevron
            if hasChildren {
                Button(action: { onToggleExpand?() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(AppDesign.Font.iconXS(.bold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(vm.L(L10n.Saves.expandHint))
            } else {
                Spacer().frame(width: 32)
            }

            SaveAvatarView(folderName: save.folderName, size: 36, vm: vm)

            // Hiérarchie nom › attributs : le fermier, puis ferme et date
            // de jeu — l'argent vit en colonnes tenues à droite, il ne
            // rallonge plus la phrase.
            VStack(alignment: .leading, spacing: 2) {
                let note = vm.getNote(for: save.folderName)
                HStack(spacing: 6) {
                    if !note.tag.isEmpty {
                        Text(note.tag)
                            .font(AppDesign.Font.rowTitle)
                    }
                    Text(save.playerName)
                        .font(AppDesign.Font.rowTitle(.medium))
                        .foregroundColor(.primary)
                }
                Text(save.farmDayLine(format: vm.L(L10n.Saves.yearDayFormat),
                                      localizedSeason: vm.L(save.seasonName)))
                    .font(AppDesign.Font.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            moneyColumns

            Menu {
                Button(action: { vm.editingSave = save }) {
                    Label(vm.L(L10n.Saves.saveManagement), systemImage: "pencil")
                }
                Button(action: { vm.viewingSaveTimeline = save }) {
                    Label(vm.L(L10n.Saves.timeline), systemImage: "clock.arrow.circlepath")
                }
                Divider()
                Button(action: { vm.openSaveInFinder(info: save) }) {
                    Label(vm.L(L10n.Saves.openFolder), systemImage: "folder")
                }
                Button(action: { vm.saveToDuplicate = save }) {
                    Label(vm.L(L10n.Saves.duplicate), systemImage: "doc.on.doc")
                }
                Divider()
                Button(role: .destructive, action: { confirmingDelete = true }) {
                    Label(vm.L(L10n.Saves.deleteSave), systemImage: "trash")
                }
                .disabled(vm.isSaveOperationRunning)
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .font(AppDesign.Font.rowTitle)
                    .frame(width: 18, height: 18)
                    .contentShape(.rect)
                    .padding(.trailing, 4)
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .help(vm.L(L10n.Saves.saveManagement))
            .frame(width: 30)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        // Même garde que sur la carte : la partie part à la corbeille avec
        // tout son dossier. Un seul modificateur de présentation sur cette
        // vue — deux ne se présenteraient pas tous les deux.
        .confirmationDialog(vm.L(L10n.Saves.confirmDeleteSave),
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(vm.L(L10n.Saves.deleteSave), role: .destructive) {
                Task { await vm.deleteSave(info: save) }
            }
            Button(vm.L(L10n.Saves.cancel), role: .cancel) {}
        } message: {
            Text(vm.L(L10n.Saves.confirmDeleteSaveMsg))
        }
    }

    /// Argent et total gagné, en colonnes tenues : ce qui se compare d'une
    /// sauvegarde à l'autre se lit aligné, pas noyé dans une phrase.
    private var moneyColumns: some View {
        HStack(alignment: .top, spacing: AppDesign.Spacing.xl) {
            StatColumn(label: vm.L(L10n.Saves.money),
                       value: Self.moneyText(save.money))
            StatColumn(label: vm.L(L10n.Saves.totalMoneyEarned),
                       value: Self.moneyText(save.totalMoneyEarned))
        }
        .fixedSize()
    }

    /// Format monétaire localisé, comme l'ancienne phrase le faisait.
    /// Interne : la fiche l'utilise pour son `StatStrip`.
    static func moneyText(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

// MARK: - Hero band (fiche de sauvegarde)

/// Le bandeau d'une fiche de sauvegarde : l'avatar du fermier, son nom et sa
/// ferme sur l'illustration du splash — le pendant **local** du `HeroHeader`
/// de la fiche mod, qui vit sur une capture Nexus que cette fiche n'a pas. Le
/// composant partagé n'est donc pas touché.
///
/// Texte blanc ombré sur voile dégradé, comme le hero-image : depuis que le
/// bandeau porte `nexus_banner_final`, il y a bien une illustration à lire en
/// dessous et le texte `primary` s'y perdait.
///
/// L'avatar suit la même règle que les lignes de la liste : l'icône choisie
/// par l'utilisateur prime sur l'illustration générique par sexe.
private struct SaveHeroBand: View {
    let title: String
    /// Le sous-titre en deux morceaux plutôt qu'une chaîne : le point de
    /// séparation est un glyphe dessiné, pas un tiret, et la ferme est la
    /// seule des deux à pouvoir être tronquée quand la place manque.
    let dayLine: String
    let farmName: String
    let closeHelp: String
    let onClose: () -> Void
    let whichFarm: Int
    let iconPath: String
    let isFemale: Bool
    let hairStyle: Int
    let hairColor: Color
    let skinIndex: Int
    let farmHelp: String

    /// Le bandeau du splash, embarqué dans les resources (dossier
    /// `custom_ui`). absent → repli neutre.
    private static let bandImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "nexus_banner_final",
                                        withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let img = Self.bandImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(height: AppDesign.Metrics.heroHeight)
        .clipped()
        // Deux voiles, pas un. Le voile de pied seul ne couvrait pas la
        // hauteur où le titre se pose — il se lisait donc « parfois »,
        // selon la zone d'illustration qu'il recouvrait. Celui-ci part de
        // la gauche, là où le texte vit, et s'efface avant la vignette.
        .overlay {
            LinearGradient(stops: [
                .init(color: .black.opacity(0.62), location: 0),
                .init(color: .black.opacity(0.42), location: 0.46),
                .init(color: .clear, location: 0.78),
            ], startPoint: .leading, endPoint: .trailing)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.45)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: AppDesign.Metrics.heroHeight * 0.53)
                .allowsHitTesting(false)
        }
        // Une seule rangée centrée. Empilé en deux rangées, le bandeau
        // laissait ses 150 pt à moitié vides et bridait le titre à 20 pt ;
        // à plat, la hauteur existante paie 26 pt de titre et un avatar
        // de 76 — sans toucher au token `heroHeight`.
        .overlay {
            HStack(alignment: .center, spacing: AppDesign.Spacing.lg) {
                // Une **vraie image** posée sur la sauvegarde gagne : elle est
                // le seul portrait fidèle dont l'app dispose (le visage
                // illustré est fixe par sexe). Un préréglage, lui, est un
                // pictogramme générique et ne prend pas la place du portrait
                // — voir `SaveHeroPortrait`.
                if !SaveHeroPortrait.prefersCustomIcon(iconPath) {
                    EquatableView(content: SaveFarmerAvatar(
                        isFemale: isFemale,
                        hairStyle: hairStyle,
                        hairColor: hairColor,
                        skinIndex: skinIndex,
                        size: 76
                    ))
                } else {
                    SaveAvatarViewLocal(iconPath: iconPath, size: 76)
                }

                VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                    Text(title)
                        .font(AppDesign.Font.heroTitle)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
                        .lineLimit(1)
                    HStack(spacing: AppDesign.Spacing.sm) {
                        Text(dayLine)
                            .foregroundColor(.white)
                            .fixedSize(horizontal: true, vertical: false)
                        Circle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 3, height: 3)
                        Text(farmName)
                            .foregroundColor(.white.opacity(0.94))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(AppDesign.Font.heroSubtitle)
                    .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
                }

                Spacer(minLength: AppDesign.Spacing.sm)

                // 96×92 : la tuile illustrée est quasi carrée (248×260) —
                // plus basse, le toit partait au crop.
                EquatableView(content: SaveFarmGlyph(
                    whichFarm: whichFarm,
                    size: CGSize(width: 96, height: 92)
                ))
                // Liseré + ombre : la vignette se détache de
                // l'illustration du bandeau.
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesign.Radius.md)
                        .stroke(Color.white.opacity(0.92), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
                .help(farmHelp)
            }
            .padding(.horizontal, AppDesign.Spacing.lg)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: AppDesign.Icon.sm))
                    // Blanc ombré : sur l'illustration du bandeau, le
                    // glyphe secondaire se perdait.
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.6), radius: 2)
            }
            .buttonStyle(.plain)
            // Cible 18×18 : le glyphe nu rendrait `.help` muet (a11y §7).
            .frame(width: 18, height: 18)
            .contentShape(.rect)
            .help(closeHelp)
        }
    }
}

// MARK: - Editor View
/// Les confirmations de l'éditeur passent par **un seul** modificateur
/// `.alert`. Deux alertes sur la même vue ne se présentent pas toutes les deux
/// — leçon payée sur `SaveTimelineView` le 2026-09-02, dans les deux sens.
private enum SaveEditorConfirmation {
    /// Écriture sur une partie modifiée sur disque, ou pendant que le jeu tourne.
    case staleEdit
    /// Envoi du dossier de la partie à la corbeille.
    case deleteSave
}

struct SaveEditorView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let save: SaveGameInfo
    
    @State private var name: String
    @State private var farm: String
    @State private var fav: String
    @State private var moneyStr: String
    @State private var maxHealthStr: String
    @State private var maxStaminaStr: String
    @State private var goldenWalnutsStr: String
    @State private var qiGemsStr: String
    @State private var clubCoinsStr: String
    @State private var totalMoneyEarnedStr: String
    @State private var spouse: String   // empty = single
    
    /// All NPC names that can be married in Stardew Valley (vanilla)
    static let marriableNPCs: [String] = [
        "Abigail", "Alex", "Elliott", "Emily", "Harvey",
        "Haley", "Leah", "Maru", "Penny", "Sam",
        "Sebastian", "Shane"
    ]
    
    @State private var noteTag: String
    @State private var noteText: String
    @State private var iconPath: String
    @State private var confirmation: SaveEditorConfirmation?
    @State private var pendingSaveAction: (() -> Void)?

    /// Sous-titre enrichi du hero (H-T5b D2) : la date de jeu concaténée au
    /// nom de ferme résolu (vanille ou mod). Calculé une fois dans `init` car
    /// `SaveFarmNameResolver.resolve` n'a aucune raison d'être ré-évalué à
    /// chaque re-render : ses entrées ne bougent pas pendant la session.
    private let heroDayLine: String
    private let heroFarmName: String
    /// Tooltip affiché sur la vignette de ferme du hero. Calculé en amont
    /// pour respecter la même règle « Core pur » que `SaveFarmNameResolver`.
    private let farmHelp: String
    
    let availableTags = ["", "⭐", "🏆", "🧪", "❤️", "💎", "📅"]
    
    // Third element is an L10n key (resolved via `vm.L` at the tooltip call
    // site below) — these used to be hardcoded Thai text shown regardless
    // of the app's selected language.
    let presetIcons: [(String, String, String)] = [
        ("preset:person", "person.crop.circle.fill", L10n.Saves.avatarPresetDefault),
        ("preset:star",   "star.fill",               L10n.Saves.avatarPresetStar),
        ("preset:leaf",   "leaf.fill",               L10n.Saves.avatarPresetLeaf),
        ("preset:heart",  "heart.fill",              L10n.Saves.avatarPresetHeart),
        ("preset:cat",    "cat.fill",                L10n.Saves.avatarPresetCat),
        ("preset:dog",    "dog.fill",                L10n.Saves.avatarPresetDog),
        ("preset:hare",   "hare.fill",               L10n.Saves.avatarPresetHare),
        ("preset:ant",    "ant.fill",                L10n.Saves.avatarPresetAnt),
    ]
    
    init(vm: StarHubTHViewModel, save: SaveGameInfo) {
        self.vm = vm
        self.save = save
        _name = State(initialValue: save.playerName)
        _farm = State(initialValue: save.farmName)
        _fav = State(initialValue: save.favoriteThing)
        _moneyStr = State(initialValue: "\(save.money)")
        _maxHealthStr = State(initialValue: "\(save.maxHealth)")
        _maxStaminaStr = State(initialValue: "\(save.maxStamina)")
        _goldenWalnutsStr = State(initialValue: "\(save.goldenWalnuts)")
        _qiGemsStr = State(initialValue: "\(save.qiGems)")
        _clubCoinsStr = State(initialValue: "\(save.clubCoins)")
        _totalMoneyEarnedStr = State(initialValue: "\(save.totalMoneyEarned)")
        _spouse = State(initialValue: save.spouse)
        
        let note = vm.getNote(for: save.folderName)
        _noteTag = State(initialValue: note.tag)
        _noteText = State(initialValue: note.note)
        _iconPath = State(initialValue: note.customIconPath ?? "")

        let displayName = SaveFarmNameResolver.resolve(save, resolver: vm)
        let dayLine = save.farmDayLine(format: vm.L(L10n.Saves.yearDayFormat),
                                       localizedSeason: vm.L(save.seasonName))
        self.heroDayLine = dayLine
        self.heroFarmName = displayName
        self.farmHelp = SaveFarmNameResolver.heroHelp(for: save, resolver: vm)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SaveHeroBand(title: save.playerName,
                         dayLine: heroDayLine,
                         farmName: heroFarmName,
                         closeHelp: vm.L(L10n.Saves.cancel),
                         onClose: { vm.editingSave = nil },
                         whichFarm: save.whichFarm,
                         iconPath: iconPath,
                         isFemale: save.isFemale,
                         hairStyle: save.hairStyle,
                         hairColor: SaveFarmerPalette.hairColor(from: save.hairColor),
                         skinIndex: save.skinIndex,
                         farmHelp: farmHelp)

            // Ce qui décide avant d'ouvrir le formulaire : où l'on en est,
            // ce que l'on a. Tout se sert dans la sauvegarde elle-même.
            StatStrip(items: [
                .init(label: vm.L(L10n.Saves.colDay),
                      value: String(format: vm.L(L10n.Saves.yearDayFormat),
                                    save.year, vm.L(save.seasonName), save.day)),
                .init(label: vm.L(L10n.Saves.money),
                      value: SaveRow.moneyText(save.money)),
                .init(label: vm.L(L10n.Saves.totalMoneyEarned),
                      value: SaveRow.moneyText(save.totalMoneyEarned)),
            ])
            .padding(.horizontal, 24)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)

            // La bande fine reçoit l'exclu du strip : l'historique des
            // sauvegardes, qui déménage de l'ancien en-tête.
            HStack {
                Button(action: { vm.viewingSaveTimeline = save }) {
                    Label(vm.L(L10n.Saves.timeline), systemImage: "clock.arrow.circlepath")
                        .font(AppDesign.Font.footnote(.medium))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .foregroundColor(.accentColor)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, AppDesign.Spacing.sm)

            Divider()

            // Form
            Form {
                // MARK: Avatar Section
                Section(vm.L(L10n.Saves.avatarSection)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            SaveAvatarViewLocal(iconPath: iconPath, size: 56)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(vm.L(L10n.Saves.avatarPreset))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 8), spacing: 6) {
                                    ForEach(presetIcons, id: \.0) { (key, sfName, label) in
                                        Button(action: {
                                            iconPath = key
                                            SaveNotesStore.shared.setNote(for: save.folderName,
                                                tag: noteTag, note: noteText, customIconPath: key)
                                            vm.objectWillChange.send()
                                        }) {
                                            ZStack {
                                                Circle()
                                                    .fill(iconPath == key ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                                    .frame(width: 28, height: 28)
                                                Image(systemName: sfName)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(iconPath == key ? .accentColor : .secondary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .help(vm.L(label))
                                    }
                                }
                            }
                        }
                        
                        HStack(spacing: 8) {
                            Button(vm.L(L10n.Saves.avatarPickFile)) {
                                vm.selectCustomAvatar(forSave: save.folderName) { path in
                                    iconPath = path
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            if !iconPath.isEmpty {
                                Button(vm.L(L10n.Saves.avatarReset)) {
                                    iconPath = ""
                                    SaveNotesStore.shared.setNote(for: save.folderName,
                                        tag: noteTag, note: noteText, customIconPath: nil)
                                    vm.objectWillChange.send()
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                
                Section(vm.L(L10n.Saves.notes)) {
                    Picker(vm.L(L10n.Saves.tag), selection: $noteTag) {
                        ForEach(availableTags, id: \.self) { tag in
                            Text(tag.isEmpty ? vm.L(L10n.Saves.tagNone) : tag).tag(tag)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    TextField(vm.L(L10n.Saves.saveNote), text: $noteText)
                }
                
                Section(vm.L(L10n.Saves.characterInfo)) {
                    TextField(vm.L(L10n.Saves.characterName), text: $name)
                    TextField(vm.L(L10n.Saves.farmName), text: $farm)
                    TextField(vm.L(L10n.Saves.favoriteThing), text: $fav)
                }
                
                // MARK: Relationship Section
                Section(vm.L(L10n.Saves.relationshipSection)) {
                    Picker(vm.L(L10n.Saves.spouseLabel), selection: $spouse) {
                        Text(vm.L(L10n.Saves.spouseNone)).tag("")
                        ForEach(SaveEditorView.marriableNPCs, id: \.self) { npc in
                            Text(npc).tag(npc)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    // Show warning only when changing away from existing spouse
                    if !save.spouse.isEmpty && spouse != save.spouse {
                        Text(vm.L(L10n.Saves.spouseWarning))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Section(vm.L(L10n.Saves.resources)) {
                    TextField(vm.L(L10n.Saves.money), text: $moneyStr)
                    TextField(vm.L(L10n.Saves.totalMoneyEarned), text: $totalMoneyEarnedStr)
                    TextField(vm.L(L10n.Saves.casinoCoins), text: $clubCoinsStr)
                    TextField(vm.L(L10n.Saves.goldenWalnuts), text: $goldenWalnutsStr)
                    TextField(vm.L(L10n.Saves.qiGems), text: $qiGemsStr)
                }
                
                Section(vm.L(L10n.Saves.characterStats)) {
                    TextField(vm.L(L10n.Saves.maxHealth), text: $maxHealthStr)
                    TextField(vm.L(L10n.Saves.maxStamina), text: $maxStaminaStr)
                }
                
                Section(vm.L(L10n.Saves.inventoryEditor)) {
                    ForEach(vm.inventoryToEdit.indices, id: \.self) { index in
                        let item = vm.inventoryToEdit[index]
                        if item.isObject {
                            HStack {
                                Text("\(item.name)")
                                    .frame(width: 150, alignment: .leading)
                                Text("\(vm.L(L10n.Saves.itemId)): \(item.itemId)")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(vm.L(L10n.Saves.itemQuantity))
                                TextField("", value: $vm.inventoryToEdit[index].stack, formatter: NumberFormatter())
                                    .frame(width: 60)
                                    .textFieldStyle(.roundedBorder)
                                
                                Button(action: {
                                    vm.inventoryToEdit[index] = InventoryItem.empty(slot: index)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .help(vm.L(L10n.Saves.clearSlotHint))
                                .padding(.leading, 8)
                            }
                        } else if !item.name.isEmpty {
                            HStack {
                                Text("\(item.name)")
                                    .frame(width: 150, alignment: .leading)
                                if !item.itemId.isEmpty {
                                    Text("\(vm.L(L10n.Saves.itemId)): \(item.itemId)")
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(vm.L(L10n.Saves.nonObject))
                                    .foregroundColor(.secondary)
                                    
                                Button(action: {
                                    vm.inventoryToEdit[index] = InventoryItem.empty(slot: index)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .help(vm.L(L10n.Saves.clearSlotHint))
                                .padding(.leading, 8)
                            }
                        }
                    }
                    
                    Button(vm.L(L10n.Saves.saveInventory)) {
                        confirmedOrWarn(vm.saveInventory)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                
                Section(vm.L(L10n.Saves.saveManagement)) {
                    HStack {
                        Button(vm.L(L10n.Saves.openFolder)) { vm.openSaveInFinder(info: save) }
                        Button(vm.L(L10n.Saves.duplicate)) { vm.saveToDuplicate = save; vm.editingSave = nil }
                        Spacer()
                        // La fermeture de l'éditeur est faite par `deleteSave`
                        // lui-même, sur succès seulement (voir le ViewModel).
                        Button(vm.L(L10n.Saves.deleteSave)) {
                            confirmation = .deleteSave
                        }
                            .foregroundColor(.red)
                            .disabled(vm.isSaveOperationRunning)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            
            Divider()
            
            // Footer
            HStack {
                Text(vm.L(L10n.Saves.backupNote))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                
                Button(vm.L(L10n.Saves.saveChanges)) {
                    confirmedOrWarn(performSave)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(BorderedProminentButtonStyle())
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .alert(editorConfirmationTitle,
               isPresented: Binding(get: { confirmation != nil },
                                    set: { if !$0 { confirmation = nil; pendingSaveAction = nil } }),
               presenting: confirmation) { pending in
            switch pending {
            case .staleEdit:
                Button(vm.L(L10n.Saves.overwriteAnyway), role: .destructive) {
                    pendingSaveAction?()
                    pendingSaveAction = nil
                }
            case .deleteSave:
                Button(vm.L(L10n.Saves.deleteSave), role: .destructive) {
                    Task { await vm.deleteSave(info: save) }
                }
            }
            Button(vm.L(L10n.Saves.cancel), role: .cancel) { pendingSaveAction = nil }
        } message: { pending in
            switch pending {
            case .staleEdit: Text(vm.L(L10n.Saves.confirmStaleEditMsg))
            case .deleteSave: Text(vm.L(L10n.Saves.confirmDeleteSaveMsg))
            }
        }
    }

    private var editorConfirmationTitle: String {
        switch confirmation {
        case .staleEdit: return vm.L(L10n.Saves.confirmStaleEdit)
        case .deleteSave: return vm.L(L10n.Saves.confirmDeleteSave)
        case nil: return ""
        }
    }

    /// Runs `action` immediately, unless the save may have changed on disk
    /// or Stardew Valley appears to be running — in which case `action` is
    /// deferred until the user confirms through the warning alert. Shared by
    /// every write path in this editor (field edits, inventory) so none of
    /// them can silently overwrite newer progress or race the game's autosave.
    private func confirmedOrWarn(_ action: @escaping () -> Void) {
        if vm.isSaveStale(save) || vm.isGameRunning() {
            pendingSaveAction = action
            confirmation = .staleEdit
        } else {
            action()
        }
    }

    /// Writes the form's current field values to the save file. Go through
    /// `confirmedOrWarn` rather than calling this directly.
    private func performSave() {
        let newMoney = Int(moneyStr) ?? save.money
        let newTotalMoneyEarned = Int(totalMoneyEarnedStr) ?? save.totalMoneyEarned
        let newHealth = Int(maxHealthStr) ?? save.maxHealth
        let newStam = Int(maxStaminaStr) ?? save.maxStamina
        let newWalnuts = Int(goldenWalnutsStr) ?? save.goldenWalnuts
        let newQi = Int(qiGemsStr) ?? save.qiGems
        let newClub = Int(clubCoinsStr) ?? save.clubCoins

        vm.setNote(for: save.folderName, tag: noteTag, note: noteText)
        vm.editSave(info: save, newName: name, newFarm: farm, newFav: fav, newMoney: newMoney, newTotalMoneyEarned: newTotalMoneyEarned, newMaxHealth: newHealth, newMaxStamina: newStam, newGoldenWalnuts: newWalnuts, newQiGems: newQi, newClubCoins: newClub, newSpouse: spouse)
        vm.editingSave = nil
    }
}
