import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

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
    let hairColor: RGBColor
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
     @Bindable var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let save: SaveGameInfo
    @Binding var currentTab: SidebarDestination
    
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
    
    init(vm: StarHubTHViewModel, localization: LocalizationStore, save: SaveGameInfo,
         currentTab: Binding<SidebarDestination>) {
        _currentTab = currentTab
        self.localization = localization
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

        let displayName = SaveFarmNameResolver.resolve(save, resolver: localization)
        let dayLine = save.farmDayLine(format: localization.L(L10n.Saves.yearDayFormat),
                                       localizedSeason: localization.L(save.seasonName))
        self.heroDayLine = dayLine
        self.heroFarmName = displayName
        self.farmHelp = SaveFarmNameResolver.heroHelp(for: save, resolver: localization)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SaveHeroBand(title: save.playerName,
                         dayLine: heroDayLine,
                         farmName: heroFarmName,
                         closeHelp: localization.L(L10n.Saves.cancel),
                         onClose: { vm.navigationStore.setEditingSave(nil) },
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
                .init(label: localization.L(L10n.Saves.colDay),
                      value: String(format: localization.L(L10n.Saves.yearDayFormat),
                                    save.year, localization.L(save.seasonName), save.day)),
                .init(label: localization.L(L10n.Saves.money),
                      value: SaveRow.moneyText(save.money)),
                .init(label: localization.L(L10n.Saves.totalMoneyEarned),
                      value: SaveRow.moneyText(save.totalMoneyEarned)),
            ])
            .padding(.horizontal, 24)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)

            // La bande fine reçoit l'exclu du strip : l'historique des
            // sauvegardes, qui déménage de l'ancien en-tête.
            HStack {
                Button(action: { vm.navigationStore.viewingSaveTimeline = save }) {
                    Label(localization.L(L10n.Saves.timeline), systemImage: "clock.arrow.circlepath")
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
                Section(localization.L(L10n.Saves.avatarSection)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            SaveAvatarViewLocal(iconPath: iconPath, size: 56)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(localization.L(L10n.Saves.avatarPreset))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 8), spacing: 6) {
                                    ForEach(presetIcons, id: \.0) { (key, sfName, label) in
                                        Button(action: {
                                            iconPath = key
                                            SaveNotesStore.shared.setNote(for: save.folderName,
                                                tag: noteTag, note: noteText, customIconPath: key)
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
                                        .help(localization.L(label))
                                    }
                                }
                            }
                        }
                        
                        HStack(spacing: 8) {
                            Button(localization.L(L10n.Saves.avatarPickFile)) {
                                vm.selectCustomAvatar(forSave: save.folderName) { path in
                                    iconPath = path
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            if !iconPath.isEmpty {
                                Button(localization.L(L10n.Saves.avatarReset)) {
                                    iconPath = ""
                                    SaveNotesStore.shared.setNote(for: save.folderName,
                                        tag: noteTag, note: noteText, customIconPath: nil)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                
                Section(localization.L(L10n.Saves.notes)) {
                    Picker(localization.L(L10n.Saves.tag), selection: $noteTag) {
                        ForEach(availableTags, id: \.self) { tag in
                            Text(tag.isEmpty ? localization.L(L10n.Saves.tagNone) : tag).tag(tag)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    TextField(localization.L(L10n.Saves.saveNote), text: $noteText)
                }
                
                SavePausedFootprintSection(vm: vm, localization: localization, save: save, currentTab: $currentTab)

                SaveAbsentModsSection(vm: vm, localization: localization, save: save)
                
                Section(localization.L(L10n.Saves.characterInfo)) {
                    TextField(localization.L(L10n.Saves.characterName), text: $name)
                    TextField(localization.L(L10n.Saves.farmName), text: $farm)
                    TextField(localization.L(L10n.Saves.favoriteThing), text: $fav)
                }
                
                // MARK: Relationship Section
                Section(localization.L(L10n.Saves.relationshipSection)) {
                    Picker(localization.L(L10n.Saves.spouseLabel), selection: $spouse) {
                        Text(localization.L(L10n.Saves.spouseNone)).tag("")
                        ForEach(SaveEditorView.marriableNPCs, id: \.self) { npc in
                            Text(npc).tag(npc)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    // Show warning only when changing away from existing spouse
                    if !save.spouse.isEmpty && spouse != save.spouse {
                        Text(localization.L(L10n.Saves.spouseWarning))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Section(localization.L(L10n.Saves.resources)) {
                    TextField(localization.L(L10n.Saves.money), text: $moneyStr)
                    TextField(localization.L(L10n.Saves.totalMoneyEarned), text: $totalMoneyEarnedStr)
                    TextField(localization.L(L10n.Saves.casinoCoins), text: $clubCoinsStr)
                    TextField(localization.L(L10n.Saves.goldenWalnuts), text: $goldenWalnutsStr)
                    TextField(localization.L(L10n.Saves.qiGems), text: $qiGemsStr)
                }
                
                Section(localization.L(L10n.Saves.characterStats)) {
                    TextField(localization.L(L10n.Saves.maxHealth), text: $maxHealthStr)
                    TextField(localization.L(L10n.Saves.maxStamina), text: $maxStaminaStr)
                }
                
                Section(localization.L(L10n.Saves.inventoryEditor)) {
                    // Le binding sous-indexé exige un chemin écrivable :
                    // `vm.navigationStore` est un `let`, la projection
                    // `@Bindable` fournit la vue écrivable du store.
                    @Bindable var navigationStore = vm.navigationStore
                    ForEach(navigationStore.inventoryToEdit.indices, id: \.self) { index in
                        let item = navigationStore.inventoryToEdit[index]
                        if item.isObject {
                            HStack {
                                Text("\(item.name)")
                                    .frame(width: 150, alignment: .leading)
                                Text("\(localization.L(L10n.Saves.itemId)): \(item.itemId)")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(localization.L(L10n.Saves.itemQuantity))
                                TextField("", value: $navigationStore.inventoryToEdit[index].stack, formatter: NumberFormatter())
                                    .frame(width: 60)
                                    .textFieldStyle(.roundedBorder)
                                
                                Button(action: {
                                    navigationStore.inventoryToEdit[index] = InventoryItem.empty(slot: index)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .help(localization.L(L10n.Saves.clearSlotHint))
                                .padding(.leading, 8)
                            }
                        } else if !item.name.isEmpty {
                            HStack {
                                Text("\(item.name)")
                                    .frame(width: 150, alignment: .leading)
                                if !item.itemId.isEmpty {
                                    Text("\(localization.L(L10n.Saves.itemId)): \(item.itemId)")
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(localization.L(L10n.Saves.nonObject))
                                    .foregroundColor(.secondary)
                                    
                                Button(action: {
                                    navigationStore.inventoryToEdit[index] = InventoryItem.empty(slot: index)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .help(localization.L(L10n.Saves.clearSlotHint))
                                .padding(.leading, 8)
                            }
                        }
                    }
                    
                    Button(localization.L(L10n.Saves.saveInventory)) {
                        confirmedOrWarn(vm.saveInventory)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                
                Section(localization.L(L10n.Saves.saveManagement)) {
                    HStack {
                        Button(localization.L(L10n.Saves.openFolder)) { vm.openSaveInFinder(info: save) }
                        Button(localization.L(L10n.Saves.duplicate)) { vm.saveToDuplicate = save; vm.navigationStore.setEditingSave(nil) }
                        Spacer()
                        // La fermeture de l'éditeur est faite par `deleteSave`
                        // lui-même, sur succès seulement (voir le ViewModel).
                        Button(localization.L(L10n.Saves.deleteSave)) {
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
                Text(localization.L(L10n.Saves.backupNote))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                
                Button(localization.L(L10n.Saves.saveChanges)) {
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
                Button(localization.L(L10n.Saves.overwriteAnyway), role: .destructive) {
                    pendingSaveAction?()
                    pendingSaveAction = nil
                }
            case .deleteSave:
                Button(localization.L(L10n.Saves.deleteSave), role: .destructive) {
                    Task { await vm.deleteSave(info: save) }
                }
            }
            Button(localization.L(L10n.Saves.cancel), role: .cancel) { pendingSaveAction = nil }
        } message: { pending in
            switch pending {
            case .staleEdit: Text(localization.L(L10n.Saves.confirmStaleEditMsg))
            case .deleteSave: Text(localization.L(L10n.Saves.confirmDeleteSaveMsg))
            }
        }
    }

    private var editorConfirmationTitle: String {
        switch confirmation {
        case .staleEdit: return localization.L(L10n.Saves.confirmStaleEdit)
        case .deleteSave: return localization.L(L10n.Saves.confirmDeleteSave)
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
        vm.navigationStore.setEditingSave(nil)
    }
}
