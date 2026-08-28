import SwiftUI

/// Un nœud de l'arborescence dressée pour les mods **sans schéma** — les 246
/// mods C# du parc, dont le `config.json` porte des objets imbriqués. Les
/// content packs, eux, sont plats et se rangent par section du schéma.
class ConfigTreeNode: Identifiable {
    let id: String
    let title: String
    let row: ConfigEditorModel.Row?
    var children: [ConfigTreeNode]

    init(id: String, title: String, row: ConfigEditorModel.Row? = nil, children: [ConfigTreeNode] = []) {
        self.id = id
        self.title = title
        self.row = row
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
    @State private var configGroups: [ConfigEditorModel.Group] = []
    /// Ce que le `content.json` voisin a donné. `nil` quand le mod n'en a pas
    /// — 246 des 462 mods à `config.json` du parc sont des mods C#.
    @State private var schemaReading: ContentPackConfigSchema.Reading?
    @State private var searchText: String = ""

    private var configRows: [ConfigEditorModel.Row] { configGroups.flatMap(\.rows) }

    /// `true` quand le pack décrit ses options : l'écran se range alors par
    /// section du schéma plutôt que par imbrication du JSON.
    private var hasSchema: Bool {
        if case .options = schemaReading { return true }
        return false
    }

    /// Le `content.json` de Content Patcher vit à côté du `config.json`.
    var contentPackPath: String {
        let basePath = (vm.gameDir as NSString).appendingPathComponent("Mods")
        let modPath = (basePath as NSString).appendingPathComponent(mod.physicalFolderName)
        return (modPath as NSString).appendingPathComponent("content.json")
    }

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
    
    private func buildTree(rows: [ConfigEditorModel.Row]) -> [ConfigTreeNode] {
        let root = ConfigTreeNode(id: "root", title: "root")

        for row in rows {
            var currentNode = root
            var currentPath = ""

            for (index, segment) in row.keyPath.enumerated() {
                currentPath += (currentPath.isEmpty ? "" : " > ") + segment
                let isLast = index == row.keyPath.count - 1

                if isLast {
                    let leaf = ConfigTreeNode(id: row.id, title: segment, row: row)
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
                if configRows.isEmpty {
                    VStack {
                        Spacer()
                        Text(vm.L(L10n.Settings.configNoSettingsFound))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            if schemaReading == .unreadable {
                                schemaUnreadableBanner
                            }

                            let filtered = filteredGroups
                            if filtered.isEmpty && !searchText.isEmpty {
                                Text(String(format: vm.L(L10n.Settings.configNoSettingsFoundFor), searchText))
                                    .foregroundColor(.secondary)
                                    .padding()
                            } else if hasSchema {
                                // Le pack décrit ses options : ses sections
                                // remplacent l'imbrication du JSON, qu'un
                                // content pack n'a de toute façon pas (0 clé
                                // imbriquée sur les 3900 décrites du parc).
                                // Identité par section, jamais par rang : la
                                // recherche fait varier le nombre de groupes,
                                // et un rang réutiliserait la vue d'une
                                // section pour une autre.
                                ForEach(filtered, id: \.section) { group in
                                    StandardSection(title: sectionTitle(of: group, among: filtered)) {
                                        rowList(group.rows)
                                    }
                                }
                            } else {
                                let tree = buildTree(rows: filtered.flatMap(\.rows))
                                let rootLeaves = tree.filter { $0.row != nil }
                                let rootGroups = tree.filter { $0.row == nil }

                                if !rootLeaves.isEmpty {
                                    StandardSection(title: vm.L(L10n.Settings.settings)) {
                                        rowList(rootLeaves.compactMap(\.row))
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
        loadSchema()
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
        configGroups = ConfigEditorModel.groups(of: tree, describedBy: schemaReading?.options ?? [])
    }

    /// Lit le `ConfigSchema` du `content.json` voisin, s'il y en a un.
    ///
    /// Lecture **synchrone** : mesuré sur le parc, les 216 `content.json`
    /// voisins d'un `config.json` se lisent en 226 ms **au total**, pire cas
    /// 20 ms pour 552 Ko. Un chargement en tâche de fond coûterait un état
    /// intermédiaire à l'écran pour rien.
    private func loadSchema() {
        // `contents(atPath:)` plutôt qu'une lecture qui lève : l'absence de
        // `content.json` est le cas **normal** — 246 des 462 mods à
        // `config.json` du parc sont des mods C#, qui n'en ont pas. C'est déjà
        // la voie de `topLevelJSONKeys` pour les mêmes raisons.
        guard let data = FileManager.default.contents(atPath: contentPackPath),
              let content = String(data: data, encoding: .utf8) else {
            schemaReading = nil
            return
        }
        schemaReading = ContentPackConfigSchema.read(content)
    }

    /// L'état courant de l'option, relu par son chemin.
    private func current(_ row: ConfigEditorModel.Row) -> ConfigEditorModel.Control {
        configRows.first(where: { $0.id == row.id })?.control ?? row.control
    }

    /// Réécrit **la seule valeur touchée** dans le texte, puis relit l'écran
    /// depuis ce texte.
    ///
    /// L'ancienne version reconstruisait tout le fichier à chaque clic, par
    /// `JSONSerialization` : l'ordre des clés devenait celui d'un
    /// dictionnaire, et chaque nombre repassait par un `Double` (`1.50`
    /// ressortait `1.5`, un entier hors plage piégeait). Ici, ce que
    /// l'utilisateur n'a pas ouvert garde le littéral exact de son fichier.
    ///
    /// Le texte est la **seule** source de l'écran : rien n'est modifié à côté
    /// de lui, donc un contrôle ne peut pas bouger sans que le fichier suive.
    ///
    /// Le fichier est reformaté par `ConfigJSONTree.write` — indentation à
    /// deux espaces, commentaires perdus s'il y en avait. Aucun `config.json`
    /// de premier niveau du parc n'en porte, et ce n'est de toute façon vrai
    /// qu'à partir de la première modification.
    private func update(_ row: ConfigEditorModel.Row, to control: ConfigEditorModel.Control) {
        guard let tree = ConfigJSONTree.parse(configText) else { return }
        guard let value = ConfigEditorModel.value(of: control),
              let updated = ConfigEditorModel.apply(value, at: row.keyPath, to: tree),
              let text = ConfigJSONTree.write(updated) else {
            // Une valeur qui ne s'écrit pas (nombre non fini, chemin qui ne
            // retombe plus sur l'arbre) laisserait sinon le contrôle bouger à
            // l'écran sans que rien ne change dans le fichier.
            vm.log(String(format: vm.L(L10n.Settings.configEditNotApplied),
                          row.keyPath.joined(separator: " > ")), level: .warning)
            return
        }
        // Rien n'a bougé dans l'arbre : ne pas réécrire le texte, sinon un
        // simple aller-retour reformaterait le fichier et activerait
        // « Enregistrer » pour rien.
        guard updated != tree else { return }
        configText = text
        parseToVisual()
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
    ///
    /// **Une sauvegarde par mod et par jour** : dix réglages modifiés dans
    /// l'après-midi déposeraient sinon dix entrées d'un seul mod en tête de
    /// l'écran des sauvegardes, devant les sauvegardes complètes. C'est la
    /// première du jour qui reste — l'état avec lequel le jeu a tourné avant
    /// qu'on y touche — et une sauvegarde générale du même jour compte aussi.
    private func backUpCurrentConfig() {
        guard FileManager.default.fileExists(atPath: configPath) else { return }
        guard ModConfigBackupManager.shared.backupFromToday(protecting: "config.json",
                                                            forMod: mod.folderName) == nil
        else { return }
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
    
    // MARK: - Rendu

    /// Les groupes filtrés par la recherche, ceux devenus vides en moins.
    ///
    /// La recherche porte sur le **libellé** autant que sur la clé : quand le
    /// schéma donne un nom, c'est celui-là qui est à l'écran, et chercher un
    /// mot qu'on y lit ne doit pas rendre zéro résultat.
    private var filteredGroups: [ConfigEditorModel.Group] {
        guard !searchText.isEmpty else { return configGroups }
        return configGroups.compactMap { group in
            let rows = group.rows.filter { row in
                row.label.localizedCaseInsensitiveContains(searchText)
                    || row.keyPath.joined(separator: " > ").localizedCaseInsensitiveContains(searchText)
            }
            return rows.isEmpty ? nil : ConfigEditorModel.Group(section: group.section, rows: rows)
        }
    }

    /// Le titre d'un groupe : sa section, « Autres » quand il rassemble ce que
    /// le schéma n'a pas rangé (11 packs du parc mêlent les deux), et le titre
    /// habituel quand il n'y a qu'un groupe sans nom.
    private func sectionTitle(of group: ConfigEditorModel.Group,
                              among groups: [ConfigEditorModel.Group]) -> String {
        if let section = group.section { return section }
        return groups.count > 1 ? vm.L(L10n.Settings.configOtherSettings)
                                : vm.L(L10n.Settings.settings)
    }

    /// Le pack décrit ses options, mais son `content.json` n'a pas pu être lu
    /// — 5 mods du parc. Sans ce mot, l'écran montre des clés brutes et rien
    /// ne dit qu'il manque quelque chose.
    private var schemaUnreadableBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(vm.L(L10n.Settings.configSchemaUnreadable))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func rowList(_ rows: [ConfigEditorModel.Row]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                renderItemRow(row: row)
                    .padding(.vertical, 4)
                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func renderNodeChildren(nodes: [ConfigTreeNode]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                if let row = node.row {
                    renderItemRow(row: row)
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
    private func renderItemRow(row: ConfigEditorModel.Row) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.label)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    if row.defaultControl != nil {
                        Text(vm.L(L10n.Settings.configModified))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(3)
                    }
                }
                // La description que le schéma du pack donne — 1759 clés du
                // parc en ont une. Deux lignes : c'est ce qui rend « ShirtSpring »
                // compréhensible sans faire tripler la hauteur de la rangée.
                if let description = row.description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)

            control(for: row)

            if let defaultControl = row.defaultControl {
                Button {
                    update(row, to: defaultControl)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        // 18×18 : un `.help` posé sur un glyphe plus petit
                        // reste muet, la cible ne recevant pas le survol.
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(PlainButtonStyle())
                .help(String(format: vm.L(L10n.Settings.configResetToDefault),
                             defaultLabel(of: defaultControl)))
                .accessibilityLabel(String(format: vm.L(L10n.Settings.configResetToDefault),
                                           defaultLabel(of: defaultControl)))
            }
        }
        .padding(.vertical, 8)
    }

    /// Le contrôle d'une rangée. Chaque `get` **relit** l'état plutôt que de
    /// rendre la valeur capturée au rendu : un incrémenteur maintenu enfoncé
    /// émet plusieurs pas avant que la vue ne se redessine, et une valeur figée
    /// les ferait tous repartir du même nombre.
    @ViewBuilder
    private func control(for row: ConfigEditorModel.Row) -> some View {
        switch row.control {
        case .toggle(let isOn, let asString):
            Toggle("", isOn: Binding(
                get: {
                    guard case .toggle(let live, _) = current(row) else { return isOn }
                    return live
                },
                // `asString` est reconduit tel quel : une option écrite
                // `"true"` par son auteur doit se réécrire `"false"`, pas
                // `false` — le mod lit une chaîne.
                set: { update(row, to: .toggle($0, asString: asString)) }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .blue))
            .controlSize(.small)
            .labelsHidden()

        case .integer(let value):
            numberField(value: Binding(
                get: {
                    guard case .integer(let live) = current(row) else { return value }
                    return live
                },
                set: { update(row, to: .integer($0)) }
            ), step: 1, formatter: Self.integerFormatter)

        case .decimal(let value):
            numberField(value: Binding(
                get: {
                    guard case .decimal(let live) = current(row) else { return value }
                    return live
                },
                set: { update(row, to: .decimal($0)) }
            ), step: 0.5, formatter: Self.decimalFormatter)

        case .text(let value):
            TextField("", text: Binding(
                get: {
                    guard case .text(let live) = current(row) else { return value }
                    return live
                },
                set: { update(row, to: .text($0)) }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .controlSize(.small)

        case .choice(let selected, let among):
            Picker("", selection: Binding(
                get: {
                    guard case .choice(let live, _) = current(row) else { return selected }
                    return live
                },
                set: { update(row, to: .choice(selected: $0, among: among)) }
            )) {
                ForEach(among, id: \.self) { value in
                    Text(choiceLabel(value, in: row)).tag(value)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)
        }
    }

    /// Le libellé d'une entrée de menu. Deux cas que le schéma impose : le
    /// vide autorisé (358 clés du parc), et la valeur que le fichier porte
    /// alors qu'elle n'est pas dans la liste du mod (6 cas) — signalée plutôt
    /// que remplacée en silence.
    private func choiceLabel(_ value: String, in row: ConfigEditorModel.Row) -> String {
        if value.isEmpty { return vm.L(L10n.Settings.configEmptyValue) }
        if row.isOutsideAllowedValues, case .choice(let selected, _) = row.control, value == selected {
            return "\(value) — \(vm.L(L10n.Settings.configValueOutsideList))"
        }
        return value
    }

    private func defaultLabel(of control: ConfigEditorModel.Control) -> String {
        switch control {
        case .toggle(let flag, _): return flag ? "true" : "false"
        case .integer(let value):  return String(value)
        case .decimal(let value):  return String(value)
        case .text(let value):     return value.isEmpty ? vm.L(L10n.Settings.configEmptyValue) : value
        case .choice(let value, _): return value.isEmpty ? vm.L(L10n.Settings.configEmptyValue) : value
        }
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
