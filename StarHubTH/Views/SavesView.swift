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
        VStack(spacing: 0) {
            // MARK: Finder-like Toolbar
            HStack(spacing: 8) {
                // View mode toggle
                HStack(spacing: 2) {
                    Button(action: { withAnimation { vm.saveViewMode = .list } }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 12, weight: .medium))
                            .padding(5)
                            .background(vm.saveViewMode == .list ? Color.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(vm.saveViewMode == .list ? .accentColor : .secondary)

                    Button(action: { withAnimation { vm.saveViewMode = .grid } }) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 12, weight: .medium))
                            .padding(5)
                            .background(vm.saveViewMode == .grid ? Color.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(vm.saveViewMode == .grid ? .accentColor : .secondary)
                }
                .padding(2)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(7)
                
                Divider().frame(height: 20)
                
                // Sort
                Menu {
                    Button(action: { vm.saveSortOption = .lastPlayed }) {
                        HStack { Image(systemName: "clock"); Text(vm.L(L10n.Saves.sortLastPlayed)) }
                        if vm.saveSortOption == .lastPlayed { Image(systemName: "checkmark") }
                    }
                    Button(action: { vm.saveSortOption = .name }) {
                        HStack {
                            if vm.currentLanguage == "th" {
                                Image(systemName: "character.textbox.th") // Icon ก ในช่องสี่เหลี่ยม
                            } else {
                                Image(systemName: "a.square")
                            }
                            Text(vm.L(L10n.Saves.sortName))
                        }
                        if vm.saveSortOption == .name { Image(systemName: "checkmark") }
                    }
                    Button(action: { vm.saveSortOption = .money }) {
                        HStack { Image(systemName: "dollarsign"); Text(vm.L(L10n.Saves.sortMoney)) }
                        if vm.saveSortOption == .money { Image(systemName: "checkmark") }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11))
                        Text(sortLabel)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                // Tag Filter
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
                    HStack(spacing: 3) {
                        Image(systemName: vm.saveFilterTag.isEmpty ? "tag" : "tag.fill")
                            .font(.system(size: 11))
                        Text(vm.saveFilterTag.isEmpty ? vm.L(L10n.Saves.filterTag) : vm.saveFilterTag)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(vm.saveFilterTag.isEmpty ? .secondary : .accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(vm.saveFilterTag.isEmpty ? Color(nsColor: .controlBackgroundColor) : Color.accentColor.opacity(0.12))
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                Spacer()
                
                Button(action: { vm.reloadSaves() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // MARK: Content
            if vm.saves.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "cloud.bolt")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(vm.L(L10n.Saves.noSaves))
                        .multilineTextAlignment(.center)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if vm.saveViewMode == .grid {
                SavesGridView(vm: vm, saves: searchText.isEmpty ? vm.savesHierarchy.map(\.info) : filteredSaves)
            } else {
                Form {
                    Section {
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
                    } header: {
                        Text(String(format: vm.L(L10n.Saves.allSaves), Int64(searchText.isEmpty ? vm.savesHierarchy.count : filteredSaves.count)))
                    } footer: {
                        Text(vm.L(L10n.Saves.autoFetch))
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .searchable(text: $searchText, prompt: Text(vm.L(L10n.Main.search)))
        .sheet(item: $vm.saveToDuplicate) { save in
            DuplicateSaveSheet(vm: vm, save: save)
        }
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
    @ObservedObject var vm: StarHubTHViewModel
    let save: SaveGameInfo
    @State private var isHovered = false
    
    var body: some View {
        Button(action: { vm.editingSave = save }) {
            VStack(spacing: 10) {
                SaveAvatarView(folderName: save.folderName, size: 64, vm: vm)
                
                VStack(spacing: 2) {
                    let note = vm.getNote(for: save.folderName)
                    HStack(spacing: 4) {
                        if !note.tag.isEmpty {
                            Text(note.tag).font(.system(size: 13))
                        }
                        Text(save.playerName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    Text(save.farmName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text(String(format: vm.L(L10n.Saves.yearDayFormat), save.year, vm.L(save.seasonName), save.day))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(isHovered ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
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
            Button(vm.L(L10n.Saves.deleteSave), role: .destructive) { vm.deleteSave(info: save) }
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
    @ObservedObject var vm: StarHubTHViewModel
    let save: SaveGameInfo
    let depth: Int
    
    var hasChildren: Bool = false
    var isExpanded: Bool = false
    var onToggleExpand: (() -> Void)? = nil
    
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            if depth > 0 {
                HStack(spacing: 4) {
                    Spacer().frame(width: CGFloat(depth) * 16 - 8)
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundColor(.secondary.opacity(0.5))
                        .font(.system(size: 10))
                }
            }
            
            // Expand/Collapse Chevron
            if hasChildren {
                Button(action: { onToggleExpand?() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 32)
            }
            
            SaveAvatarView(folderName: save.folderName, size: 36, vm: vm)
            
            VStack(alignment: .leading, spacing: 2) {
                let note = vm.getNote(for: save.folderName)
                HStack(spacing: 6) {
                    if !note.tag.isEmpty {
                        Text(note.tag)
                            .font(.system(size: 14))
                    }
                    Text(save.playerName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
                let format = vm.L(L10n.Saves.farmFormat)
                let moneyStr = NumberFormatter.localizedString(from: NSNumber(value: save.money), number: .decimal)
                let formattedStr = String(format: format, save.farmName, save.year, vm.L(save.seasonName), save.day, moneyStr)
                Text(formattedStr)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                let earnedStr = NumberFormatter.localizedString(from: NSNumber(value: save.totalMoneyEarned), number: .decimal)
                Text("\(vm.L(L10n.Saves.totalMoneyEarned)): \(earnedStr)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            
            Spacer()
            
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
                Button(role: .destructive, action: { vm.deleteSave(info: save) }) {
                    Label(vm.L(L10n.Saves.deleteSave), systemImage: "trash")
                }
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
                    .padding(.trailing, 4)
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .frame(width: 30)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Editor View
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
    @State private var showStaleWarning = false
    @State private var pendingSaveAction: (() -> Void)?
    
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
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(save.playerName)
                    .font(.headline)
                Spacer()
                Button(action: { vm.viewingSaveTimeline = save }) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text(vm.L(L10n.Saves.timeline))
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .padding(.trailing, 8)
                
                Button(action: { vm.editingSave = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
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
                        Button(vm.L(L10n.Saves.deleteSave)) { vm.deleteSave(info: save); vm.editingSave = nil }
                            .foregroundColor(.red)
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
        .alert(isPresented: $showStaleWarning) {
            Alert(
                title: Text(vm.L(L10n.Saves.confirmStaleEdit)),
                message: Text(vm.L(L10n.Saves.confirmStaleEditMsg)),
                primaryButton: .destructive(Text(vm.L(L10n.Saves.overwriteAnyway))) {
                    pendingSaveAction?()
                    pendingSaveAction = nil
                },
                secondaryButton: .cancel(Text(vm.L(L10n.Saves.cancel))) {
                    pendingSaveAction = nil
                }
            )
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
            showStaleWarning = true
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
