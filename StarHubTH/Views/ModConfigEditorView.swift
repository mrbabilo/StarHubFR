import SwiftUI

struct ConfigItem: Identifiable {
    let id = UUID()
    let keyPath: [String]
    var key: String { keyPath.joined(separator: " > ") }
    var boolValue: Bool = false
    var stringValue: String = ""
    var numberValue: Double = 0
    var isInt: Bool = false
    
    enum ItemType {
        case boolean, string, number, other
    }
    var type: ItemType
    var originalValue: Any? // Keep nested arrays/objects unmodified
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
        let basePath = (vm.gameDir as NSString).appendingPathComponent(mod.isEnabled ? "Mods" : "Mods_disabled")
        let modPath = (basePath as NSString).appendingPathComponent(mod.folderName)
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
                    let leaf = ConfigTreeNode(id: item.id.uuidString, title: segment, item: item)
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
                            .onChange(of: configText) { newValue in
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
                configText = "Error reading config.json"
                isInvalidJson = true
            }
        } else {
            configText = "{}"
            parseToVisual()
        }
    }
    
    private func validateJson(_ text: String) {
        if text.isEmpty {
            isInvalidJson = false
            return
        }
        if let data = text.data(using: .utf8) {
            do {
                _ = try JSONSerialization.jsonObject(with: data, options: [])
                isInvalidJson = false
            } catch {
                isInvalidJson = true
            }
        }
    }
    
    private func parseToVisual() {
        guard let data = configText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return
        }
        
        var newItems: [ConfigItem] = []
        
        func extractItems(from value: Any, parentPath: [String]) {
            if let dict = value as? [String: Any] {
                for key in dict.keys.sorted() {
                    if let val = dict[key] {
                        extractItems(from: val, parentPath: parentPath + [key])
                    }
                }
            } else if let arr = value as? [Any] {
                for (index, elem) in arr.enumerated() {
                    extractItems(from: elem, parentPath: parentPath + ["[\(index)]"])
                }
            } else if let num = value as? NSNumber {
                if CFGetTypeID(num) == CFBooleanGetTypeID() {
                    newItems.append(ConfigItem(keyPath: parentPath, boolValue: num.boolValue, type: .boolean, originalValue: value))
                } else {
                    let isInt = CFNumberIsFloatType(num) == false
                    newItems.append(ConfigItem(keyPath: parentPath, numberValue: num.doubleValue, isInt: isInt, type: .number, originalValue: value))
                }
            } else if let s = value as? String {
                if s.lowercased() == "true" {
                    newItems.append(ConfigItem(keyPath: parentPath, boolValue: true, stringValue: "true_as_string", type: .boolean, originalValue: value))
                } else if s.lowercased() == "false" {
                    newItems.append(ConfigItem(keyPath: parentPath, boolValue: false, stringValue: "false_as_string", type: .boolean, originalValue: value))
                }
            }
        }
        
        extractItems(from: json, parentPath: [])
        configItems = newItems
    }
    
    private func syncToText() {
        guard let data = configText.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: data, options: []) else { return }
        
        func setValue(in container: inout Any, path: [String], value: Any) {
            guard let first = path.first else { return }
            
            if path.count == 1 {
                if first.hasPrefix("[") && first.hasSuffix("]"),
                   let idxStr = String(first.dropFirst().dropLast()) as String?,
                   let idx = Int(idxStr), var arr = container as? [Any], idx < arr.count {
                    arr[idx] = value
                    container = arr
                } else if var dict = container as? [String: Any] {
                    dict[first] = value
                    container = dict
                }
            } else {
                let remaining = Array(path.dropFirst())
                if first.hasPrefix("[") && first.hasSuffix("]"),
                   let idxStr = String(first.dropFirst().dropLast()) as String?,
                   let idx = Int(idxStr), var arr = container as? [Any], idx < arr.count {
                    var child = arr[idx]
                    setValue(in: &child, path: remaining, value: value)
                    arr[idx] = child
                    container = arr
                } else if var dict = container as? [String: Any] {
                    var child = dict[first] ?? [String: Any]()
                    setValue(in: &child, path: remaining, value: value)
                    dict[first] = child
                    container = dict
                }
            }
        }
        
        for item in configItems {
            let valToSet: Any
            switch item.type {
            case .boolean:
                if item.stringValue == "true_as_string" || item.stringValue == "false_as_string" {
                    valToSet = item.boolValue ? "true" : "false"
                } else {
                    valToSet = item.boolValue
                }
            case .number:
                valToSet = item.isInt ? Int(item.numberValue) : item.numberValue
            case .string, .other:
                continue
            }
            setValue(in: &json, path: item.keyPath, value: valToSet)
        }
        
        if let newJsonData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
           let str = String(data: newJsonData, encoding: .utf8) {
            let cleanedCurrent = configText.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\n", with: "")
            let cleanedNew = str.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\n", with: "")
            if cleanedCurrent != cleanedNew {
                configText = str.replacingOccurrences(of: "\\/", with: "/")
            }
        }
    }
    
    private func saveConfig() -> Bool {
        do {
            let backupPath = configPath + ".bak"
            if FileManager.default.fileExists(atPath: configPath) {
                if FileManager.default.fileExists(atPath: backupPath) {
                    try FileManager.default.removeItem(atPath: backupPath)
                }
                try FileManager.default.copyItem(atPath: configPath, toPath: backupPath)
            }
            try configText.write(toFile: configPath, atomically: true, encoding: .utf8)
            originalText = configText
            vm.showModal(message: vm.L(L10n.Settings.configSaved))
            return true
        } catch {
            vm.showModal(message: "Error saving config.json: \(error.localizedDescription)")
            return false
        }
    }
    
    private func restoreConfigBackup() {
        let backupPath = configPath + ".bak"
        if FileManager.default.fileExists(atPath: backupPath) {
            do {
                let content = try String(contentsOfFile: backupPath, encoding: .utf8)
                try content.write(toFile: configPath, atomically: true, encoding: .utf8)
                configText = content
                originalText = content
                validateJson(configText)
                parseToVisual()
                vm.showModal(message: "Restored config from config.json.bak successfully!")
                return
            } catch {
                print("Failed to restore .bak: \(error)")
            }
        }
        
        let panel = NSOpenPanel()
        panel.title = "Select Config Backup (.json)"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                try content.write(toFile: configPath, atomically: true, encoding: .utf8)
                configText = content
                originalText = content
                validateJson(configText)
                parseToVisual()
                vm.showModal(message: "Loaded config from \(url.lastPathComponent) successfully!")
            } catch {
                vm.showModal(message: "Failed to load config: \(error.localizedDescription)")
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
            
            switch item.type {
            case .boolean:
                Toggle("", isOn: Binding(
                    get: { item.boolValue },
                    set: { newValue in
                        if let i = configItems.firstIndex(where: { $0.id == item.id }) {
                            configItems[i].boolValue = newValue
                            syncToText()
                        }
                    }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .controlSize(.small)
                .labelsHidden()
                
            case .number:
                if item.isInt {
                    HStack(spacing: 6) {
                        TextField("", value: Binding(
                            get: { Int(item.numberValue) },
                            set: { newValue in
                                if let i = configItems.firstIndex(where: { $0.id == item.id }) {
                                    configItems[i].numberValue = Double(newValue)
                                    syncToText()
                                }
                            }
                        ), formatter: NumberFormatter())
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        
                        Stepper("", onIncrement: {
                            if let i = configItems.firstIndex(where: { $0.id == item.id }) {
                                configItems[i].numberValue += 1
                                syncToText()
                            }
                        }, onDecrement: {
                            if let i = configItems.firstIndex(where: { $0.id == item.id }) {
                                configItems[i].numberValue -= 1
                                syncToText()
                            }
                        })
                        .labelsHidden()
                    }
                } else {
                    HStack(spacing: 6) {
                        TextField("", value: Binding(
                            get: { item.numberValue },
                            set: { newValue in
                                if let i = configItems.firstIndex(where: { $0.id == item.id }) {
                                    configItems[i].numberValue = newValue
                                    syncToText()
                                }
                            }
                        ), formatter: NumberFormatter())
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        
                        Stepper("", onIncrement: {
                            if let i = configItems.firstIndex(where: { $0.id == item.id }) {
                                configItems[i].numberValue += 0.5
                                syncToText()
                            }
                        }, onDecrement: {
                            if let i = configItems.firstIndex(where: { $0.id == item.id }) {
                                configItems[i].numberValue -= 0.5
                                syncToText()
                            }
                        })
                        .labelsHidden()
                    }
                }
            default:
                EmptyView()
            }
        }
        .padding(.vertical, 8)
    }
}
