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

    /// Le chemin tel qu'il vaut **aujourd'hui**. Celui qui dort dans
    /// `SaveNotes_v2` est absolu : le déplacement du dossier de données (F5)
    /// l'a périmé, et `NSImage(contentsOfFile:)` retombait alors en silence
    /// sur le pictogramme générique — l'avatar disparaissait sans un mot.
    private var resolvedPath: String {
        SaveHeroPortrait.resolvedImagePath(iconPath,
                                           avatarsDirectory: AppSupport.avatarsDirectory)
    }

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
            } else if !iconPath.isEmpty, let img = NSImage(contentsOfFile: resolvedPath) {
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
    var vm: StarHubTHViewModel

    var body: some View {
        SaveAvatarViewLocal(iconPath: vm.getNote(for: folderName).customIconPath ?? "", size: size)
    }
}

// MARK: - SaveGameInfo · sous-titre de rangée et de hero
extension SaveGameInfo {
    /// « Ferme · An 3 Printemps 14 » — le sous-titre commun à la rangée de
    /// liste et au hero de la fiche : une seule écriture, pas deux qui
    /// divergent. Le format et la saison localisée viennent de l'appelant,
    /// qui seul connaît la langue.
    /// Interne : `SaveRow` (ici) et `SaveEditorView` (`SaveEditorView.swift`)
    /// l'utilisent — l'ancien `fileprivate` était lié au fichier d'avant la
    /// coupe T3.
    func farmDayLine(format: String, localizedSeason: String) -> String {
        "\(farmName) · \(String(format: format, year, localizedSeason, day))"
    }
}

// MARK: - Grid View
struct SavesGridView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let saves: [SaveGameInfo]
    let columns = [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 16)]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(saves) { save in
                    SaveCardView(vm: vm, localization: localization, save: save)
                }
            }
            .padding(20)
        }
    }
}

struct SaveCardView: View {
    @State private var confirmingDelete = false
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let save: SaveGameInfo
    @State private var isHovered = false
    
    var body: some View {
        Button(action: { vm.navigationStore.setEditingSave(save) }) {
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
                    Text(String(format: localization.L(L10n.Saves.yearDayFormat), save.year, localization.L(save.seasonName), save.day))
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
            Button(localization.L(L10n.Saves.edit)) { vm.navigationStore.setEditingSave(save) }
            Button(localization.L(L10n.Saves.timeline)) { vm.navigationStore.viewingSaveTimeline = save }
            Divider()
            Button(localization.L(L10n.Saves.duplicate)) { vm.saveToDuplicate = save }
            Button(localization.L(L10n.Saves.openFolder)) { vm.openSaveInFinder(info: save) }
            Divider()
            Button(localization.L(L10n.Saves.deleteSave), role: .destructive) {
                confirmingDelete = true
            }
            .disabled(vm.isSaveOperationRunning)
        }
        // Supprimer une partie envoie tout son dossier à la corbeille. La
        // suppression d'une **sauvegarde de secours** confirmait déjà (audit
        // 2026-08-05) ; celle de la partie elle-même ne confirmait pas, ce qui
        // était l'inverse du risque.
        .confirmationDialog(localization.L(L10n.Saves.confirmDeleteSave),
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(localization.L(L10n.Saves.deleteSave), role: .destructive) {
                Task { await vm.deleteSave(info: save) }
            }
            Button(localization.L(L10n.Saves.cancel), role: .cancel) {}
        } message: {
            Text(localization.L(L10n.Saves.confirmDeleteSaveMsg))
        }
    }
}

// MARK: - Tree List View
struct SaveTreeListView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let nodes: [SaveNode]
    let depth: Int
    @State private var expandedSaves: Set<String> = []
    
    var body: some View {
        ForEach(nodes) { node in
            let hasChildren = !node.children.isEmpty
            let isExpanded = expandedSaves.contains(node.info.folderName)
            
            Button(action: { vm.navigationStore.setEditingSave(node.info) }) {
                SaveRow(
                    vm: vm,
                    localization: localization,
                    save: node.info,
                    depth: depth,
                    hasChildren: hasChildren,
                    isExpanded: isExpanded,
                    onToggleExpand: {
                        withMotion(.easeInOut(duration: 0.2)) {
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
                SaveTreeListView(vm: vm, localization: localization, nodes: node.children, depth: depth + 1)
            }
        }
    }
}

// MARK: - Save Row (List)
struct SaveRow: View {
    @State private var confirmingDelete = false
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
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
                        .foregroundColor(AppDesign.Color.dimmedSecondary(AppDesign.Opacity.disabled))
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
                .help(localization.L(L10n.Saves.expandHint))
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
                Text(save.farmDayLine(format: localization.L(L10n.Saves.yearDayFormat),
                                      localizedSeason: localization.L(save.seasonName)))
                    .font(AppDesign.Font.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            moneyColumns

            Menu {
                Button(action: { vm.navigationStore.setEditingSave(save) }) {
                    Label(localization.L(L10n.Saves.saveManagement), systemImage: "pencil")
                }
                Button(action: { vm.navigationStore.viewingSaveTimeline = save }) {
                    Label(localization.L(L10n.Saves.timeline), systemImage: "clock.arrow.circlepath")
                }
                Divider()
                Button(action: { vm.openSaveInFinder(info: save) }) {
                    Label(localization.L(L10n.Saves.openFolder), systemImage: "folder")
                }
                Button(action: { vm.saveToDuplicate = save }) {
                    Label(localization.L(L10n.Saves.duplicate), systemImage: "doc.on.doc")
                }
                Divider()
                Button(role: .destructive, action: { confirmingDelete = true }) {
                    Label(localization.L(L10n.Saves.deleteSave), systemImage: "trash")
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
            .help(localization.L(L10n.Saves.saveManagement))
            .frame(width: 30)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        // Même garde que sur la carte : la partie part à la corbeille avec
        // tout son dossier. Un seul modificateur de présentation sur cette
        // vue — deux ne se présenteraient pas tous les deux.
        .confirmationDialog(localization.L(L10n.Saves.confirmDeleteSave),
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(localization.L(L10n.Saves.deleteSave), role: .destructive) {
                Task { await vm.deleteSave(info: save) }
            }
            Button(localization.L(L10n.Saves.cancel), role: .cancel) {}
        } message: {
            Text(localization.L(L10n.Saves.confirmDeleteSaveMsg))
        }
    }

    /// Argent et total gagné, en colonnes tenues : ce qui se compare d'une
    /// sauvegarde à l'autre se lit aligné, pas noyé dans une phrase.
    private var moneyColumns: some View {
        HStack(alignment: .top, spacing: AppDesign.Spacing.xl) {
            StatColumn(label: localization.L(L10n.Saves.money),
                       value: Self.moneyText(save.money))
            StatColumn(label: localization.L(L10n.Saves.totalMoneyEarned),
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
