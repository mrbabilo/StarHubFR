import SwiftUI

/// Une option du `config.json` telle que l'écran la manipule.
///
/// L'identité est le **chemin**, pas un `UUID` tiré à chaque analyse : le
/// texte est ré-analysé à chaque frappe dans l'onglet JSON, et une identité
/// neuve à chaque tour ferait remonter toutes les vues — le champ en cours
/// d'édition perdrait le focus.
struct ConfigItem: Identifiable {
    let keyPath: [String]
    var control: ConfigEditorModel.Control

    var id: String { keyPath.joined(separator: "\u{1}") }
    var key: String { keyPath.joined(separator: " > ") }
}

class ConfigTreeNode: Identifiable {
    let id: String
    let title: String
    let item: ConfigItem?
    var children: [ConfigTreeNode]
    
    init(id: String, title: String, item: ConfigItem? = nil, children: [ConfigTreeNode] = []) {
        self.id = id
        self.title = title
        self.item = item
        self.children = children
    }
}

struct ModConfigEditorView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ModItem
    
    @State private var configText: String = ""
    @State private var originalText: String = ""
    @State private var isInvalidJson: Bool = false
    @State private var selectedTab: Int
    @State private var configItems: [ConfigItem] = []
    @State private var searchText: String = ""

    init(vm: StarHubTHViewModel, mod: ModItem, initialTab: Int = 0) {
        self.vm = vm
        self.mod = mod
        self._selectedTab = State(initialValue: initialTab)
    }

    var configPath: String {
        // A mod always lives under Mods/ — disabled ones carry a leading dot
        // in `physicalFolderName`, so a single construction works for both.
        let basePath = (vm.gameDir as NSString).appendingPathComponent("Mods")
        let modPath = (basePath as NSString).appendingPathComponent(mod.physicalFolderName)
        return (modPath as NSString).appendingPathComponent("config.json")
    }
    
    private func buildTree(items: [ConfigItem]) -> [ConfigTreeNode] {
        let root = ConfigTreeNode(id: "root", title: "root")
        
        for item in items {
            var currentNode = root
            var currentPath = ""
            
            for (index, segment) in item.keyPath.enumerated() {
                currentPath += (currentPath.isEmpty ? "" : " > ") + segment
                let isLast = index == item.keyPath.count - 1
                
                if isLast {
                    let leaf = ConfigTreeNode(id: item.id, title: segment, item: item)
                    currentNode.children.append(leaf)
                } else {
                    if let existing = currentNode.children.first(where: { $0.title == segment }) {
                        currentNode = existing
                    } else {
                        let newGroup = ConfigTreeNode(id: currentPath, title: segment)
                        currentNode.children.append(newGroup)
                        currentNode = newGroup
                    }
                }
            }
        }
        
        return root.children
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if selectedTab == 0 {
                if configItems.isEmpty {
                    VStack {
                        Spacer()
                        Text(vm.L(L10n.Settings.configNoSettingsFound))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            let filteredItems = configItems.filter { item in
                                searchText.isEmpty || item.key.localizedCaseInsensitiveContains(searchText)
                            }
                            
                            if filteredItems.isEmpty && !searchText.isEmpty {
                                Text(String(format: vm.L(L10n.Settings.configNoSettingsFoundFor), searchText))
                                    .foregroundColor(.secondary)
                                    .padding()
                            } else {
                                let tree = buildTree(items: filteredItems)
                                let rootLeaves = tree.filter { $0.item != nil }
                                let rootGroups = tree.filter { $0.item == nil }
                                
                                if !rootLeaves.isEmpty {
                                    StandardSection(title: vm.L(L10n.Settings.settings)) {
                                        VStack(spacing: 0) {
                                            ForEach(Array(rootLeaves.enumerated()), id: \.element.id) { index, leafNode in
                                                if let item = leafNode.item {
                                                    renderItemRow(item: item, label: leafNode.title)
                                                        .padding(.vertical, 4)
                                                    if index < rootLeaves.count - 1 {
                                                        Divider()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                ForEach(rootGroups) { groupNode in
                                    StandardSection(title: groupNode.title) {
                                        renderNodeChildren(nodes: groupNode.children)
                                    }
                                }
                            }
                        }
                        .padding(30)
                    }
                }
            } else {
                VStack {
                    StandardSection(title: vm.L(L10n.Settings.configRawJson)) {
                        CodeEditorView(text: $configText)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                            .frame(minHeight: 320)
                            .onChange(of: configText) { _, newValue in
                                validateJson(newValue)
                                if !isInvalidJson {
                                    parseToVisual()
                                }
                            }
                    }
                }
                .padding(30)
            }
            
            Divider()
            
            // Footer Action Bar
            HStack {
                Button(action: { restoreConfigBackup() }) {
                    Label(vm.L(L10n.Settings.configRestoreConfig), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                
                if isInvalidJson {
                    Text(vm.L(L10n.Settings.configInvalidJson))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.leading, 8)
                }
                
                Spacer()
                
                Button(action: {
                    configText = originalText
                    isInvalidJson = false
                    parseToVisual()
                }) {
                    Text(vm.L(L10n.Settings.configReset))
                }
                .buttonStyle(.bordered)
                .disabled(configText == originalText)
                
                Button(vm.L(L10n.Saves.saveChanges)) {
                    if saveConfig() {
                        vm.editingModConfig = nil
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(configText == originalText || isInvalidJson)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .searchable(text: $searchText, prompt: Text(vm.L(L10n.Settings.configSearchPlaceholder)))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    Text(vm.L(L10n.Settings.configVisualEditor)).tag(0)
                    Text(vm.L(L10n.Settings.configCodeEditor)).tag(1)
                }
                .pickerStyle(.segmented)
            }
        }
        .toolbarBackground(.hidden, for: .automatic)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear(perform: loadConfig)
    }
    
    private func loadConfig() {
        if FileManager.default.fileExists(atPath: configPath) {
            do {
                let content = try String(contentsOfFile: configPath, encoding: .utf8)
                configText = content
                originalText = content
                validateJson(configText)
                parseToVisual()
            } catch {
                configText = vm.L(L10n.Settings.configReadError)
                isInvalidJson = true
            }
        } else {
            configText = "{}"
            parseToVisual()
        }
    }
    
    private func validateJson(_ text: String) {
        // Un fichier vide (ou seulement des espaces) n'est pas un JSON valide :
        // laisser le bouton Save actif écraserait config.json par un fichier que
        // SMAPI ne pourrait pas parser au prochain lancement.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isInvalidJson = true
            return
        }
        // `ConfigJSONTree` plutôt que `JSONSerialization` : c'est la
        // tolérance de Newtonsoft, donc celle de SMAPI — commentaires et
        // virgules traînantes comprises. L'écran refusait des fichiers que le
        // jeu charge sans broncher.
        isInvalidJson = ConfigJSONTree.parse(text) == nil
    }
    
    /// Les options, **dans l'ordre où l'auteur les a écrites**.
    ///
    /// C'est le tri alphabétique qui partait ici : sur le parc de référence,
    /// **363 des 462 `config.json` de premier niveau** ont un ordre d'auteur
    /// différent de l'ordre alphabétique, et celui-ci sépare des réglages qui
    /// vont ensemble (`BigSilo_BuildCost` atterrissait à côté de `BigSilo`,
    /// très loin de la section où l'auteur l'avait rangé).
    private func parseToVisual() {
        guard let tree = ConfigJSONTree.parse(configText) else { return }
        configItems = ConfigEditorModel.leaves(of: tree).compactMap { leaf in
            ConfigEditorModel.control(for: leaf.value)
                .map { ConfigItem(keyPath: leaf.keyPath, control: $0) }
        }
    }
    
    /// Réécrit **la seule valeur touchée** dans le texte.
    ///
    /// L'ancienne version reconstruisait tout le fichier à chaque clic, par
    /// `JSONSerialization` : l'ordre des clés devenait celui d'un
    /// dictionnaire, et chaque nombre repassait par un `Double` (`1.50`
    /// ressortait `1.5`, un entier hors plage piégeait). Ici, ce que
    /// l'utilisateur n'a pas ouvert garde le littéral exact de son fichier.
    ///
    /// Le fichier est reformaté par `ConfigJSONTree.write` — indentation à
    /// deux espaces, commentaires perdus s'il y en avait. Aucun `config.json`
    /// de premier niveau du parc n'en porte, et ce n'est de toute façon vrai
    /// qu'à partir de la première modification.
    /// L'état courant de l'option, retrouvé par son chemin.
    private func current(_ item: ConfigItem) -> ConfigEditorModel.Control {
        configItems.first(where: { $0.id == item.id })?.control ?? item.control
    }

    private func update(_ item: ConfigItem, to control: ConfigEditorModel.Control) {
        guard let index = configItems.firstIndex(where: { $0.id == item.id }) else { return }
        configItems[index].control = control
        applyEdit(configItems[index])
    }

    private func applyEdit(_ item: ConfigItem) {
        guard let current = ConfigJSONTree.parse(configText) else { return }
        guard let value = ConfigEditorModel.value(of: item.control),
              let updated = ConfigEditorModel.apply(value, at: item.keyPath, to: current),
              let text = ConfigJSONTree.write(updated) else {
            // Une valeur qui ne s'écrit pas (nombre non fini, chemin qui ne
            // retombe plus sur l'arbre) laisserait sinon le contrôle bouger à
            // l'écran sans que rien ne change dans le fichier.
            vm.log(String(format: vm.L(L10n.Settings.configEditNotApplied), item.key), level: .warning)
            return
        }
        // Rien n'a bougé dans l'arbre : ne pas réécrire le texte, sinon un
        // simple aller-retour reformaterait le fichier et activerait
        // « Enregistrer » pour rien.
        guard updated != current else { return }
        configText = text
    }

    private func saveConfig() -> Bool {
        do {
            backUpCurrentConfig()
            try configText.write(toFile: configPath, atomically: true, encoding: .utf8)
            originalText = configText
            vm.showModal(message: vm.L(L10n.Settings.configSaved))
            return true
        } catch {
            vm.showModal(message: String(format: vm.L(L10n.Settings.configSaveError), error.localizedDescription))
            return false
        }
    }
    
    /// Met la version actuelle à l'abri **avant** de l'écraser.
    ///
    /// Passe par `ModConfigBackupManager` au lieu du `config.json.bak` qui
    /// était déposé dans le dossier du mod : la sauvegarde devient visible
    /// depuis l'écran des sauvegardes, datée, et ne survit plus seule à côté
    /// du fichier qu'elle double.
    ///
    /// `onlyEnabled: false` parce que l'éditeur s'ouvre aussi sur un mod en
    /// pause — **379 des 462 mods à `config.json` du parc de référence**.
    ///
    /// Un échec n'empêche pas d'enregistrer : bloquer l'édition d'un fichier
    /// parce que son filet a raté serait un blocage dur pour une raison molle.
    /// Il est journalisé, pas avalé.
    private func backUpCurrentConfig() {
        guard FileManager.default.fileExists(atPath: configPath) else { return }
        do {
            _ = try ModConfigBackupManager.shared.createBackup(gameDir: vm.gameDir,
                                                              mods: [mod],
                                                              onlyEnabled: false)
            _ = ModConfigBackupManager.shared.cleanupOldBackups()
        } catch {
            vm.log(String(format: vm.L(L10n.Settings.configBackupFailed),
                          mod.name, error.localizedDescription), level: .warning)
        }
    }

    /// Recharge une version sauvegardée **dans l'écran**, sans l'écrire.
    ///
    /// L'utilisateur voit ce qu'il s'apprête à remettre et garde la main :
    /// c'est « Enregistrer » qui écrit, et qui met au passage la version
    /// actuelle à l'abri. La version précédente écrasait le fichier sur-le-champ.
    private func loadIntoEditor(_ content: String) {
        configText = content
        validateJson(configText)
        parseToVisual()
    }

    private func restoreConfigBackup() {
        // 1. La sauvegarde la plus récente qui contient ce `config.json`.
        if let found = ModConfigBackupManager.shared.mostRecentBackedUpFile(named: "config.json",
                                                                           forMod: mod.folderName),
           let content = try? String(contentsOf: found.url, encoding: .utf8) {
            loadIntoEditor(content)
            vm.showModal(message: String(format: vm.L(L10n.Settings.configRestoredFromBackup),
                                         found.backup.formattedDate))
            return
        }

        // 2. Le `config.json.bak` voisin : plus personne n'en dépose, mais
        //    ceux laissés par les versions précédentes restent lisibles.
        let backupPath = configPath + ".bak"
        if FileManager.default.fileExists(atPath: backupPath) {
            do {
                let content = try String(contentsOfFile: backupPath, encoding: .utf8)
                loadIntoEditor(content)
                vm.showModal(message: vm.L(L10n.Settings.configRestoredBak))
                return
            } catch {
                // Consigné, pas avalé : l'échec fait retomber sur le sélecteur
                // de fichier ci-dessous, ce qui, sans trace, ressemble à un
                // simple changement d'avis de l'app.
                vm.log(String(format: vm.L(L10n.Settings.configRestoreBakFailed),
                              error.localizedDescription), level: .warning)
            }
        }
        
        // 3. Un fichier choisi à la main.
        let panel = NSOpenPanel()
        panel.title = vm.L(L10n.Settings.configBackupPanelTitle)
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                loadIntoEditor(content)
                vm.showModal(message: String(format: vm.L(L10n.Settings.configLoadedFrom), url.lastPathComponent))
            } catch {
                vm.showModal(message: String(format: vm.L(L10n.Settings.configLoadFailed), error.localizedDescription))
            }
        }
    }
    
    @ViewBuilder
    private func renderNodeChildren(nodes: [ConfigTreeNode]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                if let item = node.item {
                    renderItemRow(item: item, label: node.title)
                        .padding(.vertical, 4)
                    if index < nodes.count - 1 {
                        Divider()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(node.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                        
                        AnyView(renderNodeChildren(nodes: node.children))
                            .padding(.leading, 12)
                    }
                    if index < nodes.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func renderItemRow(item: ConfigItem, label: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()

            // Chaque `get` **relit** l'état plutôt que de rendre la valeur
            // capturée au rendu : un incrémenteur maintenu enfoncé émet
            // plusieurs pas avant que la vue ne se redessine, et une valeur
            // figée les ferait tous repartir du même nombre.
            switch item.control {
            case .toggle(let isOn, let asString):
                Toggle("", isOn: Binding(
                    get: {
                        guard case .toggle(let live, _) = current(item) else { return isOn }
                        return live
                    },
                    // `asString` est reconduit tel quel : une option écrite
                    // `"true"` par son auteur doit se réécrire `"false"`, pas
                    // `false` — le mod lit une chaîne.
                    set: { update(item, to: .toggle($0, asString: asString)) }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .controlSize(.small)
                .labelsHidden()

            case .integer(let value):
                numberField(value: Binding(
                    get: {
                        guard case .integer(let live) = current(item) else { return value }
                        return live
                    },
                    set: { update(item, to: .integer($0)) }
                ), step: 1, formatter: Self.integerFormatter)

            case .decimal(let value):
                numberField(value: Binding(
                    get: {
                        guard case .decimal(let live) = current(item) else { return value }
                        return live
                    },
                    set: { update(item, to: .decimal($0)) }
                ), step: 0.5, formatter: Self.decimalFormatter)

            case .text(let value):
                TextField("", text: Binding(
                    get: {
                        guard case .text(let live) = current(item) else { return value }
                        return live
                    },
                    set: { update(item, to: .text($0)) }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
    }

    private static let integerFormatter = NumberFormatter()

    /// Un `NumberFormatter` nu a `numberStyle = .none`, donc **zéro décimale** :
    /// le champ décimal affichait `0` pour `0,5` et `1` pour `1,25`, et
    /// refusait la saisie qu'il venait d'afficher. Le défaut précède C4-T5 —
    /// l'ancien champ `Double` avait le même formateur nu — et touche
    /// **758 des 11 891 options du parc**.
    ///
    /// Le séparateur reste celui de la langue de l'utilisateur (une virgule en
    /// français) ; le fichier, lui, est toujours écrit avec un point.
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 15
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    /// Le champ numérique, entier ou décimal — pas et formateur près.
    /// Les deux versions étaient copiées l'une sur l'autre à 4 lignes près.
    @ViewBuilder
    private func numberField<Number: Numeric & Comparable>(value: Binding<Number>,
                                                           step: Number,
                                                           formatter: NumberFormatter) -> some View {
        HStack(spacing: 6) {
            TextField("", value: value, formatter: formatter)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .multilineTextAlignment(.trailing)
                .frame(width: 70)

            Stepper("", onIncrement: { value.wrappedValue += step },
                    onDecrement: { value.wrappedValue -= step })
                .labelsHidden()
        }
    }
}
