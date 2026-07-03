import Foundation
import Cocoa
import SwiftUI

extension Dictionary where Key == String {
    func caseInsensitiveValue(forKey key: String) -> Value? {
        if let value = self[key] { return value }
        let lowerKey = key.lowercased()
        if let match = self.first(where: { $0.key.lowercased() == lowerKey }) {
            return match.value
        }
        return nil
    }
}

struct ModDependency: Equatable {
    let uniqueId: String
    let isRequired: Bool
}

struct ModItem: Identifiable, Equatable {
    var id: String { folderName }
    let uniqueId: String
    let name: String
    let folderName: String
    let version: String
    let author: String
    let description: String
    let nexusUrl: String
    var isEnabled: Bool
    let dependencies: [ModDependency]
    var children: [ModItem]?
    var isGroup: Bool = false
}

struct ModUpdateInfo: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let version: String
    let url: String
}

struct ThaiTranslationMod: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let author: String
    let version: String
    let status: String
    let url: String
    let nexusUrl: String
    var isInstalled: Bool = false
    var isOriginalModInstalled: Bool = false
    
    func translatedStatus(vm: StarHubTHViewModel) -> String {
        if status.contains("เสร็จสมบูรณ์") {
            return "✅ " + vm.localizedString(for: "เสร็จสมบูรณ์")
        } else if status.contains("รอแปล") {
            return "⏳ " + vm.localizedString(for: "รอแปล")
        }
        return status
    }
    
    func installationStatusText(vm: StarHubTHViewModel) -> String {
        if isInstalled {
            return vm.localizedString(for: "ติดตั้งแล้ว")
        } else if isOriginalModInstalled {
            return vm.localizedString(for: "พร้อมให้ดาวน์โหลด")
        } else {
            return vm.localizedString(for: "ขาดม็อดต้นฉบับ")
        }
    }
}

class StarHubTHViewModel: ObservableObject {
    @Published var gameDir: String = "" {
        didSet {
            UserDefaults.standard.set(gameDir, forKey: "gameDir")
            self.refresh()
        }
    }
    
    @Published var outOfDateMods: [ModUpdateInfo] = []
    @Published var smapiErrors: [String] = []
    @Published var showSmapiAlerts: Bool = false
    
    @Published var smapiInstalledVersion: String = "ยังไม่ได้ติดตั้ง"
    @Published var mods: [ModItem] = []
    
    // Thai Translation Hub State
    @Published var thaiTranslations: [ThaiTranslationMod] = []
    @Published var viewingThaiMod: ThaiTranslationMod? = nil
    
    @Published var logOutput: String = ""
    @Published var alertMessage: String = ""
    @Published var showAlert: Bool = false
    @Published var isThaiTranslationInstalled: Bool = false
    
    @Published var saves: [SaveGameInfo] = []
    @Published var editingSave: SaveGameInfo? = nil
    
    @Published var steamUsername: String = "ชาวไร่"
    @Published var steamAvatarPath: String? = nil
    
    @Published var currentLanguage: String = UserDefaults.standard.string(forKey: "currentLanguage") ?? "en" {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "currentLanguage")
            UserDefaults.standard.set([currentLanguage], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }
    
    
    @Published var modProfiles: [ModProfile] = []
    @Published var activeProfileId: UUID? = nil
    
    let smapiInstaller = SmapiInstaller()
    
    init() {
        // Force sync AppleLanguages with currentLanguage at startup
        let savedLang = UserDefaults.standard.string(forKey: "currentLanguage") ?? "en"
        UserDefaults.standard.set([savedLang], forKey: "AppleLanguages")
        
        // Automatically retrieve saved game path, or attempt to find the default Steam path on Mac
        let savedPath = UserDefaults.standard.string(forKey: "gameDir") ?? ""
        if !savedPath.isEmpty && FileManager.default.fileExists(atPath: savedPath) {
            self.gameDir = savedPath
        } else {
            self.gameDir = self.detectDefaultGameDir()
        }
        self.refresh()
        self.loadProfiles()
    }
    
    func detectDefaultGameDir() -> String {
        let home = NSHomeDirectory()
        let steamPath = "\(home)/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS"
        if FileManager.default.fileExists(atPath: steamPath) {
            return steamPath
        }
        
        let gogPath = "/Applications/Stardew Valley.app/Contents/MacOS"
        if FileManager.default.fileExists(atPath: gogPath) {
            return gogPath
        }
        
        return ""
    }
    
    func selectGameDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            self.gameDir = panel.url?.path ?? ""
            UserDefaults.standard.set(self.gameDir, forKey: "gameDir")
            scanMods()
            checkSmapiVersion()
        }
    }
    
    // Helper to force localization using the currently selected language bundle
    func localizedString(for key: String) -> String {
        guard let path = Bundle.main.path(forResource: currentLanguage, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }
        return NSLocalizedString(key, tableName: nil, bundle: bundle, value: "", comment: "")
    }
    
    func refresh() {
        self.checkSmapiVersion()
        self.scanMods()
        self.reloadSaves()
        self.fetchSteamUser()
    }
    
    func fetchSteamUser() {
        let home = NSHomeDirectory()
        let vdfPath = "\(home)/Library/Application Support/Steam/config/loginusers.vdf"
        guard let content = try? String(contentsOfFile: vdfPath, encoding: .utf8) else { return }
        
        // Very basic VDF parsing
        var currentSteamID = ""
        var personaName = ""
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let tLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if tLine.hasPrefix("\"7656") {
                currentSteamID = tLine.replacingOccurrences(of: "\"", with: "")
            }
            if tLine.hasPrefix("\"PersonaName\"") {
                let parts = tLine.components(separatedBy: "\"")
                if parts.count >= 4 { personaName = parts[3] }
            }
            if tLine.hasPrefix("\"MostRecent\"") && tLine.contains("\"1\"") {
                break
            }
        }
        
        if !personaName.isEmpty {
            self.steamUsername = personaName
        } else {
            self.steamUsername = NSFullUserName().components(separatedBy: " ").first ?? "ชาวไร่"
        }
        
        if !currentSteamID.isEmpty {
            let avatarPathPng = "\(home)/Library/Application Support/Steam/config/avatarcache/\(currentSteamID).png"
            let avatarPathJpg = "\(home)/Library/Application Support/Steam/config/avatarcache/\(currentSteamID).jpg"
            if FileManager.default.fileExists(atPath: avatarPathPng) {
                self.steamAvatarPath = avatarPathPng
            } else if FileManager.default.fileExists(atPath: avatarPathJpg) {
                self.steamAvatarPath = avatarPathJpg
            }
        }
    }
    
    func checkSmapiVersion() {
        guard !gameDir.isEmpty else {
            self.smapiInstalledVersion = "ไม่ได้ระบุโฟลเดอร์เกม"
            return
        }
        if let version = SmapiInstaller.getInstalledVersion(gameDir: gameDir) {
            self.smapiInstalledVersion = version
        } else {
            self.smapiInstalledVersion = "ยังไม่ได้ติดตั้ง"
        }
    }
    
    func scanMods() {
        guard !gameDir.isEmpty else {
            self.mods = []
            return
        }
        
        let fm = FileManager.default
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let disabledModsPath = (gameDir as NSString).appendingPathComponent("Mods_disabled")
        
        var scannedMods: [ModItem] = []
        
        // Helper to parse a folder containing manifest.json
        func parseModFolder(at path: String, relativePath: String, isEnabled: Bool) -> ModItem? {
            let manifestPath = (path as NSString).appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestPath) else { return nil }
            
            var name = (path as NSString).lastPathComponent
            var uniqueId = ""
            var version = "Unknown"
            var author = "Unknown"
            var description = ""
            var nexusUrl = ""
            var dependencies: [ModDependency] = []
            
            if let rawData = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
               let rawString = String(data: rawData, encoding: .utf8) {
                
                // Strip block comments (/* ... */) often added by ModManifestBuilder
                let cleanString = rawString.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
                
                var options: JSONSerialization.ReadingOptions = []
                if #available(macOS 12.0, *) {
                    options.insert(.json5Allowed)
                }
                
                if let data = cleanString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data, options: options) as? [String: Any] {
                    
                    if let mName = json.caseInsensitiveValue(forKey: "Name") as? String { name = mName }
                if let mUniqueId = json.caseInsensitiveValue(forKey: "UniqueID") as? String { uniqueId = mUniqueId }
                
                let mVer = json.caseInsensitiveValue(forKey: "Version")
                if let vStr = mVer as? String { 
                    version = vStr 
                } else if let vDict = mVer as? [String: Any] {
                    let major = vDict.caseInsensitiveValue(forKey: "MajorVersion") as? Int ?? 1
                    let minor = vDict.caseInsensitiveValue(forKey: "MinorVersion") as? Int ?? 0
                    let patch = vDict.caseInsensitiveValue(forKey: "PatchVersion") as? Int ?? 0
                    version = "\(major).\(minor).\(patch)"
                }
                
                if let mAuthor = json.caseInsensitiveValue(forKey: "Author") as? String { author = mAuthor }
                if let mDesc = json.caseInsensitiveValue(forKey: "Description") as? String { description = mDesc }
                
                if let deps = json.caseInsensitiveValue(forKey: "Dependencies") as? [[String: Any]] {
                    for dep in deps {
                        if let depId = dep.caseInsensitiveValue(forKey: "UniqueID") as? String {
                            let isReq = dep.caseInsensitiveValue(forKey: "IsRequired") as? Bool ?? true
                            dependencies.append(ModDependency(uniqueId: depId, isRequired: isReq))
                        }
                    }
                }
                
                if let updateKeys = json.caseInsensitiveValue(forKey: "UpdateKeys") as? [String] {
                    for key in updateKeys {
                        if key.lowercased().hasPrefix("nexus:") {
                            let id = key.replacingOccurrences(of: "nexus:", with: "", options: .caseInsensitive)
                            nexusUrl = "https://www.nexusmods.com/stardewvalley/mods/\(id.trimmingCharacters(in: .whitespacesAndNewlines))"
                            break
                        }
                    }
                }
            }
        }
            
            return ModItem(
                uniqueId: uniqueId,
                name: name,
                folderName: relativePath.isEmpty ? (path as NSString).lastPathComponent : relativePath,
                version: version,
                author: author,
                description: description,
                nexusUrl: nexusUrl,
                isEnabled: isEnabled,
                dependencies: dependencies
            )
        }
        
        // Helper to recursively scan folders for manifest.json and group them
        func scanFolderForMods(at path: String, isEnabled: Bool) {
            let url = URL(fileURLWithPath: path)
            var groups: [String: [ModItem]] = [:]
            var ungrouped: [ModItem] = []
            
            if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent.lowercased() == "manifest.json" {
                        let modFolderURL = fileURL.deletingLastPathComponent()
                        let relativePath = modFolderURL.path.replacingOccurrences(of: url.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        if let mod = parseModFolder(at: modFolderURL.path, relativePath: relativePath, isEnabled: isEnabled) {
                            
                            // Determine top-level folder
                            let pathComponents = relativePath.components(separatedBy: "/")
                            
                            if pathComponents.count > 1, let topFolder = pathComponents.first, !topFolder.isEmpty {
                                groups[topFolder, default: []].append(mod)
                            } else {
                                ungrouped.append(mod)
                            }
                        }
                    }
                }
            }
            
            scannedMods.append(contentsOf: ungrouped)
            
            for (groupName, modsInGroup) in groups {
                if modsInGroup.count == 1 {
                    scannedMods.append(modsInGroup[0])
                } else {
                    let groupMod = ModItem(
                        uniqueId: "",
                        name: groupName,
                        folderName: groupName,
                        version: "",
                        author: "Group",
                        description: "\(modsInGroup.count) mods",
                        nexusUrl: "",
                        isEnabled: isEnabled,
                        dependencies: [],
                        children: modsInGroup,
                        isGroup: true
                    )
                    scannedMods.append(groupMod)
                }
            }
        }
        
        // Scan enabled mods folder
        if fm.fileExists(atPath: modsPath) {
            scanFolderForMods(at: modsPath, isEnabled: true)
        }
        
        // Scan disabled mods folder
        if fm.fileExists(atPath: disabledModsPath) {
            scanFolderForMods(at: disabledModsPath, isEnabled: false)
        }
        
        parseSMAPILog()
            
        DispatchQueue.main.async {
            self.mods = scannedMods.sorted { 
                if $0.isGroup != $1.isGroup {
                    return $0.isGroup 
                }
                return $0.name.lowercased() < $1.name.lowercased() 
            }
            if self.selectedMod == nil, let first = self.mods.first {
                self.selectedMod = first
            }
            self.isThaiTranslationInstalled = scannedMods.contains {
                $0.folderName.lowercased() == "stardew valley - thai" ||
                $0.name.localizedCaseInsensitiveContains("thai")
            }
        }
    }
    
    // Parses the SMAPI-latest.txt log for updates and errors
    func parseSMAPILog() {
        guard !gameDir.isEmpty else { return }
        
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let logPath = (homeDir as NSString).appendingPathComponent(".config/StardewValley/ErrorLogs/SMAPI-latest.txt")
        guard FileManager.default.fileExists(atPath: logPath),
              let logContent = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.outOfDateMods = []
                self.smapiErrors = []
            }
            return
        }
        
        var updates: [ModUpdateInfo] = []
        var errors: [String] = []
        
        let lines = logContent.components(separatedBy: .newlines)
        var isParsingUpdates = false
        var isParsingErrors = false
        
        for line in lines {
            // Check for Updates
            if line.contains("You can update") {
                isParsingUpdates = true
                continue
            }
            if isParsingUpdates {
                if line.contains("ALERT SMAPI") && line.contains("https://") {
                    // Example: [12:00:00 ALERT SMAPI]    Content Patcher 2.0.0: https://smapi.io/mods#Content_Patcher
                    let parts = line.components(separatedBy: "ALERT SMAPI]")
                    if parts.count > 1 {
                        let infoString = parts[1].trimmingCharacters(in: .whitespaces)
                        let split = infoString.components(separatedBy: ": https://")
                        if split.count == 2 {
                            let nameAndVersion = split[0]
                            let url = "https://" + split[1]
                            
                            // Naive split by last space for version
                            let nvSplit = nameAndVersion.components(separatedBy: " ")
                            let version = nvSplit.last ?? ""
                            let name = nvSplit.dropLast().joined(separator: " ")
                            
                            updates.append(ModUpdateInfo(name: name, version: version, url: url))
                        }
                    }
                } else if !line.contains("ALERT SMAPI") {
                    // Reached end of alert block
                    isParsingUpdates = false
                }
            }
            
            // Check for Errors (Skipped mods or general red text)
            if line.contains("ERROR SMAPI") {
                if line.contains("Skipped mods") {
                    isParsingErrors = true
                    continue
                }
                
                if isParsingErrors {
                    if line.contains("-------------------------") || line.contains("These mods could not be added") {
                        continue
                    }
                    if line.contains("WARN ") || line.contains("INFO ") || line.contains("TRACE ") || line.contains("DEBUG ") {
                        isParsingErrors = false
                    } else {
                        let parts = line.components(separatedBy: "ERROR SMAPI]")
                        if parts.count > 1 {
                            let msg = parts[1].trimmingCharacters(in: .whitespaces)
                            if !msg.isEmpty {
                                errors.append(msg)
                            }
                        }
                    }
                } else {
                    // General error line not in "Skipped mods"
                    if !line.contains("Skipped mods") && !line.contains("-------------------------") {
                        let parts = line.components(separatedBy: "ERROR")
                        if parts.count > 1 {
                            let msg = parts[1].trimmingCharacters(in: .whitespaces)
                            // Filter out known empty or structural lines
                            if msg.hasPrefix("SMAPI]") {
                                let actualMsg = msg.replacingOccurrences(of: "SMAPI]", with: "").trimmingCharacters(in: .whitespaces)
                                if !actualMsg.isEmpty {
                                    errors.append(actualMsg)
                                }
                            }
                        }
                    }
                }
            } else if isParsingErrors && (line.contains("WARN ") || line.contains("INFO ") || line.contains("TRACE ") || line.contains("DEBUG ")) {
                isParsingErrors = false
            }
        }
        
        // Remove duplicates and limit error messages
        let uniqueErrors = Array(NSOrderedSet(array: errors)).prefix(10).map { $0 as! String }
        
        DispatchQueue.main.async {
            self.outOfDateMods = updates
            self.smapiErrors = uniqueErrors
        }
    }
    
    // Returns missing required unique IDs for a given mod
    func getMissingDependencies(for mod: ModItem) -> [String] {
        var allUniqueIds = Set<String>()
        for m in mods {
            if m.isGroup, let children = m.children {
                for c in children {
                    allUniqueIds.insert(c.uniqueId.lowercased())
                }
            } else {
                allUniqueIds.insert(m.uniqueId.lowercased())
            }
        }
        
        return mod.dependencies.compactMap { dep in
            guard dep.isRequired else { return nil }
            return allUniqueIds.contains(dep.uniqueId.lowercased()) ? nil : dep.uniqueId
        }
    }
    
    // Toggle Mod Status (Enabled / Disabled)
    func toggleMod(_ mod: ModItem) {
        var modsToToggle: Set<String> = [mod.uniqueId]
        let targetState = !mod.isEnabled // True if we are enabling, false if disabling
        
        if targetState == true {
            // Enabling: Also enable all dependencies recursively
            var queue = [mod]
            while !queue.isEmpty {
                let current = queue.removeFirst()
                for dep in current.dependencies {
                    if let depMod = self.mods.first(where: { $0.uniqueId.caseInsensitiveCompare(dep.uniqueId) == .orderedSame }), !depMod.isEnabled {
                        if !modsToToggle.contains(depMod.uniqueId) {
                            modsToToggle.insert(depMod.uniqueId)
                            queue.append(depMod)
                        }
                    }
                }
            }
        } else {
            // Disabling: Disable dependencies if they are not used by other enabled mods
            var queue = [mod]
            while !queue.isEmpty {
                let current = queue.removeFirst()
                for dep in current.dependencies {
                    if let depMod = self.mods.first(where: { $0.uniqueId.caseInsensitiveCompare(dep.uniqueId) == .orderedSame }), depMod.isEnabled {
                        if !modsToToggle.contains(depMod.uniqueId) {
                            // Check if this dependency is required by another enabled mod that we are NOT disabling
                            let isUsedByOther = self.mods.contains { otherMod in
                                otherMod.isEnabled && 
                                !modsToToggle.contains(otherMod.uniqueId) &&
                                otherMod.dependencies.contains { $0.uniqueId.caseInsensitiveCompare(depMod.uniqueId) == .orderedSame }
                            }
                            
                            if !isUsedByOther {
                                modsToToggle.insert(depMod.uniqueId)
                                queue.append(depMod)
                            }
                        }
                    }
                }
            }
        }
        
        let fm = FileManager.default
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let disabledModsPath = (gameDir as NSString).appendingPathComponent("Mods_disabled")
        var anyMoved = false
        
        for uniqueId in modsToToggle {
            guard let m = self.mods.first(where: { $0.uniqueId == uniqueId }) else { continue }
            if m.isEnabled == targetState { continue }
            
            let srcPath = ((m.isEnabled ? modsPath : disabledModsPath) as NSString).appendingPathComponent(m.folderName)
            let destFolder = m.isEnabled ? disabledModsPath : modsPath
            let destPath = ((destFolder as NSString).appendingPathComponent(m.folderName) as String)
            
            do {
                let destParent = (destPath as NSString).deletingLastPathComponent
                if !fm.fileExists(atPath: destParent) {
                    try fm.createDirectory(atPath: destParent, withIntermediateDirectories: true, attributes: nil)
                }
                if fm.fileExists(atPath: destPath) {
                    try fm.removeItem(atPath: destPath)
                }
                try fm.moveItem(atPath: srcPath, toPath: destPath)
                anyMoved = true
            } catch {
                print("Failed to toggle \(m.name): \(error.localizedDescription)")
            }
        }
        
        if anyMoved {
            log("\(targetState ? "เปิดใช้งาน" : "ปิดใช้งาน")ม็อด: \(mod.name)\(modsToToggle.count > 1 ? " และ Dependencies" : "")")
            self.scanMods()
        }
    }
    
    // Install SMAPI via Installer Helper
    func installSmapi() {
        smapiInstaller.install(gameDir: gameDir) { success, msg in
            self.checkSmapiVersion()
            self.showModal(message: msg)
            self.log("\(msg)")
        }
    }
    
    // Uninstall SMAPI
    func uninstallSmapi() {
        smapiInstaller.uninstall(gameDir: gameDir) { success, msg in
            self.checkSmapiVersion()
            self.showModal(message: msg)
            self.log("\(msg)")
        }
    }
    
    @Published var selectedMod: ModItem? = nil {
        didSet {
            if let mod = selectedMod, selectedModID != mod.folderName {
                selectedModID = mod.folderName
            }
        }
    }
    @Published var selectedModID: String? = nil {
        didSet {
            if let id = selectedModID, selectedMod?.folderName != id {
                selectedMod = mods.first { $0.folderName == id }
            }
        }
    }
    @Published var isPlayingGame: Bool = false
    @Published var selectedProfile: String = "SMAPI"
    
    // Launch Stardew Valley (with selected profile)
    func launchGame() {
        guard !gameDir.isEmpty else {
            showModal(message: "กรุณาระบุโฟลเดอร์เกมก่อน")
            return
        }
        
        let profile = UserDefaults.standard.string(forKey: "launchProfile") ?? "SMAPI"
        let closeAfter = UserDefaults.standard.bool(forKey: "closeAfterLaunch")
        
        self.isPlayingGame = true
        
        let originalPath = (gameDir as NSString).appendingPathComponent("StardewValley-original")
        
        if profile == "Vanilla" && FileManager.default.fileExists(atPath: originalPath) {
            log("กำลังเริ่มเปิดเกม Stardew Valley (Vanilla)...")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [originalPath]
            process.currentDirectoryURL = URL(fileURLWithPath: gameDir)
            do {
                try process.run()
                log("เปิดเกมเซสชัน Vanilla สำเร็จ")
                if closeAfter { NSApplication.shared.terminate(nil) }
            } catch {
                log("ไม่สามารถเปิดไฟล์ตัวเกมหลักโดยตรงได้: \(error.localizedDescription)")
                showModal(message: "ไม่สามารถเริ่มเกมแบบ Vanilla ได้")
            }
        } else {
            log("กำลังเริ่มเปิดเกม Stardew Valley (SMAPI)...")
            if let steamURL = URL(string: "steam://run/413150") {
                if NSWorkspace.shared.open(steamURL) {
                    log("เปิดเกมผ่าน Steam สำเร็จ")
                    if closeAfter { NSApplication.shared.terminate(nil) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        self.isPlayingGame = false
                    }
                    return
                }
            }
            
        let nsPath = gameDir as NSString
        var appPath = gameDir
        if nsPath.contains(".app") {
            var current = nsPath
            while current.length > 0 && !current.lastPathComponent.hasSuffix(".app") {
                current = current.deletingLastPathComponent as NSString
            }
            if current.length > 0 {
                appPath = current as String
            }
        }
        
        // Fallback: Open app directly
        let appURL = URL(fileURLWithPath: appPath)
            if NSWorkspace.shared.open(appURL) {
                log("เปิดไฟล์แอปตัวเกมโดยตรงสำเร็จ")
                if closeAfter { NSApplication.shared.terminate(nil) }
            } else {
                log("ไม่สามารถเปิดเกมได้ โปรดตรวจสอบโฟลเดอร์เกมของคุณ")
                showModal(message: "ไม่สามารถเริ่มเกมได้โดยตรง")
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            self.isPlayingGame = false
        }
    }
    
    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        logOutput += "[\(timestamp)] \(message)\n"
    }
    
    func showModal(message: String) {
        self.alertMessage = message
        self.showAlert = true
    }
    
    // MARK: - Saves
    func reloadSaves() {
        self.saves = SaveManager.shared.fetchSaves()
    }
    
    func editSave(info: SaveGameInfo, newName: String, newFarm: String, newFav: String, newMoney: Int, newMaxHealth: Int, newMaxStamina: Int, newGoldenWalnuts: Int, newQiGems: Int, newClubCoins: Int) {
        let success = SaveManager.shared.updateSave(info: info, newName: newName, newFarm: newFarm, newFav: newFav, newMoney: newMoney, newMaxHealth: newMaxHealth, newMaxStamina: newMaxStamina, newGoldenWalnuts: newGoldenWalnuts, newQiGems: newQiGems, newClubCoins: newClubCoins)
        if success {
            reloadSaves()
            showModal(message: "บันทึกเซฟและสำรองไฟล์เรียบร้อยแล้ว!")
        } else {
            showModal(message: "เกิดข้อผิดพลาดในการบันทึกเซฟ")
        }
    }
    
    func deleteSave(info: SaveGameInfo) {
        if SaveManager.shared.deleteSave(info: info) {
            reloadSaves()
            showModal(message: "ย้ายเซฟลงถังขยะเรียบร้อยแล้ว")
        } else {
            showModal(message: "ไม่สามารถลบเซฟได้")
        }
    }
    
    func duplicateSave(info: SaveGameInfo) {
        if SaveManager.shared.duplicateSave(info: info) {
            reloadSaves()
            showModal(message: "ทำสำเนาเซฟเรียบร้อยแล้ว")
        } else {
            showModal(message: "ไม่สามารถทำสำเนาเซฟได้ (อาจมีซ้ำอยู่แล้ว)")
        }
    }
    
    func openSaveInFinder(info: SaveGameInfo) {
        SaveManager.shared.openSaveInFinder(info: info)
    }
    
    // MARK: - Backup & Management
    func backupAllSaves() {
        let home = NSHomeDirectory()
        let savesDir = "\(home)/.config/StardewValley/Saves"
        let desktopDir = "\(home)/Desktop"
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "")
        let zipPath = "\(desktopDir)/StardewSaves_Backup_\(timestamp).zip"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", zipPath, "."]
        process.currentDirectoryURL = URL(fileURLWithPath: savesDir)
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                showModal(message: "สำรองไฟล์เซฟทั้งหมดไปที่ Desktop เรียบร้อยแล้ว\n(\(zipPath))")
            } else {
                showModal(message: "เกิดข้อผิดพลาดในการ Zip ไฟล์เซฟ")
            }
        } catch {
            showModal(message: "ไม่สามารถสั่งรันคำสั่ง Zip ได้")
        }
    }
    
    func backupAllMods() {
        guard !gameDir.isEmpty else {
            showModal(message: "กรุณาระบุโฟลเดอร์เกมก่อน")
            return
        }
        let modsDir = (gameDir as NSString).appendingPathComponent("Mods")
        let home = NSHomeDirectory()
        let desktopDir = "\(home)/Desktop"
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "")
        let zipPath = "\(desktopDir)/StardewMods_Backup_\(timestamp).zip"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", zipPath, "."]
        process.currentDirectoryURL = URL(fileURLWithPath: modsDir)
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                showModal(message: "สำรองโฟลเดอร์ม็อดไปที่ Desktop เรียบร้อยแล้ว\n(\(zipPath))")
            } else {
                showModal(message: "เกิดข้อผิดพลาดในการ Zip โฟลเดอร์ม็อด")
            }
        } catch {
            showModal(message: "ไม่สามารถสั่งรันคำสั่ง Zip ได้")
        }
    }
    
    func cleanDisabledMods() {
        guard !gameDir.isEmpty else { return }
        let disabledModsPath = (gameDir as NSString).appendingPathComponent("Mods_disabled")
        do {
            if FileManager.default.fileExists(atPath: disabledModsPath) {
                try FileManager.default.removeItem(atPath: disabledModsPath)
                showModal(message: "ลบโฟลเดอร์ Mods_disabled เรียบร้อยแล้ว")
                self.scanMods()
            } else {
                showModal(message: "ไม่พบโฟลเดอร์ Mods_disabled")
            }
        } catch {
            showModal(message: "ลบโฟลเดอร์ Mods_disabled ไม่สำเร็จ: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Thai Translation Hub Logic
    
    func fetchThaiTranslations() {
        guard let url = URL(string: "https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/README.md") else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, let content = String(data: data, encoding: .utf8) else { return }
            
            var newTranslations: [ThaiTranslationMod] = []
            let lines = content.components(separatedBy: .newlines)
            var inTable = false
            
            for line in lines {
                if line.starts(with: "| ชื่อม็อด") {
                    inTable = true
                    continue
                }
                if inTable && line.starts(with: "| :---") { continue }
                if inTable && line.starts(with: "|") {
                    let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.count >= 6 {
                        let rawName = parts[1] // **[[CP] Additional Farm Cave](https://...)**
                        var cleanName = rawName.replacingOccurrences(of: "**", with: "")
                        var url = ""
                        
                        // Use regex to extract name and URL: [Name](URL)
                        let pattern = "\\[(.*?)\\]\\((.*?)\\)"
                        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                           let match = regex.firstMatch(in: cleanName, options: [], range: NSRange(location: 0, length: cleanName.utf16.count)) {
                            if let nameRange = Range(match.range(at: 1), in: cleanName) {
                                let extractedName = String(cleanName[nameRange])
                                if let urlRange = Range(match.range(at: 2), in: cleanName) {
                                    url = String(cleanName[urlRange])
                                }
                                cleanName = extractedName
                            }
                        }
                        
                        let author = parts[2]
                        let version = parts[3]
                        let status = parts[4]
                        
                        let rawNexus = parts[5]
                        var nexusUrl = ""
                        if let r1 = rawNexus.range(of: "("), let r2 = rawNexus.range(of: ")") {
                            nexusUrl = String(rawNexus[rawNexus.index(after: r1.lowerBound)..<r2.lowerBound])
                        }
                        
                        let mod = ThaiTranslationMod(
                            name: cleanName,
                            author: author,
                            version: version,
                            status: status,
                            url: url,
                            nexusUrl: nexusUrl,
                            isInstalled: false,
                            isOriginalModInstalled: false
                        )
                        newTranslations.append(mod)
                    }
                } else if inTable && line.isEmpty {
                    inTable = false
                }
            }
            
            DispatchQueue.main.async {
                self.thaiTranslations = newTranslations
                self.evaluateThaiTranslationStatus()
            }
        }.resume()
    }
    
    func evaluateThaiTranslationStatus() {
        guard !gameDir.isEmpty else { return }
        let fm = FileManager.default
        let modsDir = (gameDir as NSString).appendingPathComponent("Mods")
        
        for i in 0..<thaiTranslations.count {
            // Very simple check: does any mod folder contain an i18n/th.json?
            // AND does the folder name sort of match the mod name?
            let nameToCheck = thaiTranslations[i].name.replacingOccurrences(of: "[CP]", with: "").trimmingCharacters(in: .whitespaces)
            var foundTranslation = false
            var foundOriginal = false
            for mod in mods {
                if mod.name.localizedCaseInsensitiveContains(nameToCheck) || nameToCheck.localizedCaseInsensitiveContains(mod.name) {
                    foundOriginal = true
                    let thJsonPath = (modsDir as NSString).appendingPathComponent("\(mod.folderName)/i18n/th.json")
                    let cpThJsonPath = (modsDir as NSString).appendingPathComponent("\(mod.folderName)/[CP] \(mod.folderName)/i18n/th.json") // Handle nested [CP]
                    if fm.fileExists(atPath: thJsonPath) || fm.fileExists(atPath: cpThJsonPath) {
                        foundTranslation = true
                    }
                }
            }
            thaiTranslations[i].isOriginalModInstalled = foundOriginal
            thaiTranslations[i].isInstalled = foundTranslation
        }
        
        // Sort installed mods first, then alphabetically
        thaiTranslations.sort { mod1, mod2 in
            if mod1.isInstalled != mod2.isInstalled {
                return mod1.isInstalled
            }
            return mod1.name.localizedStandardCompare(mod2.name) == .orderedAscending
        }
    }
    
    func installThaiTranslation(mod: ThaiTranslationMod) {
        guard !gameDir.isEmpty else { return }
        
        let modsDir = (gameDir as NSString).appendingPathComponent("Mods")
        let zipName = "\(mod.name.replacingOccurrences(of: "[CP] ", with: "")) - Thai Translation.zip"
        let encodedZipName = zipName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? zipName
        let downloadUrlStr = "https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/bundles/\(encodedZipName)"
        
        guard let downloadUrl = URL(string: downloadUrlStr) else {
            showModal(message: "เกิดข้อผิดพลาดในการสร้าง URL ดาวน์โหลด")
            return
        }
        
        showModal(message: "กำลังดาวน์โหลดไฟล์แปลภาษา: \(mod.name)...")
        
        let task = URLSession.shared.downloadTask(with: downloadUrl) { localUrl, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.showModal(message: "ดาวน์โหลดล้มเหลว: \(error.localizedDescription)")
                }
                return
            }
            
            guard let localUrl = localUrl else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", localUrl.path, "-d", modsDir]
            
            do {
                try process.run()
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        self.showModal(message: "ติดตั้งภาษาไทยสำหรับ \(mod.name) สำเร็จ!")
                        self.evaluateThaiTranslationStatus()
                    } else {
                        self.showModal(message: "เกิดข้อผิดพลาดในการแตกไฟล์ Zip ลงโฟลเดอร์ Mods")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showModal(message: "ไม่สามารถรันคำสั่ง Unzip ได้: \(error.localizedDescription)")
                }
            }
        }
        task.resume()
    }
    
    func openSavesFolder() {
        let home = NSHomeDirectory()
        let savesDir = URL(fileURLWithPath: "\(home)/.config/StardewValley/Saves")
        NSWorkspace.shared.open(savesDir)
    }
    
    // MARK: - Mod Profiles
    func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: "modProfiles"),
           let profiles = try? JSONDecoder().decode([ModProfile].self, from: data) {
            self.modProfiles = profiles
        } else {
            self.modProfiles = []
        }
        
        if let activeIdStr = UserDefaults.standard.string(forKey: "activeProfileId"),
           let activeId = UUID(uuidString: activeIdStr) {
            self.activeProfileId = activeId
        }
    }
    
    func saveProfiles() {
        if let data = try? JSONEncoder().encode(modProfiles) {
            UserDefaults.standard.set(data, forKey: "modProfiles")
        }
        if let activeId = activeProfileId {
            UserDefaults.standard.set(activeId.uuidString, forKey: "activeProfileId")
        } else {
            UserDefaults.standard.removeObject(forKey: "activeProfileId")
        }
    }
    
    func createProfile(name: String) {
        let newProfile = ModProfile(name: name, enabledModIds: [])
        modProfiles.append(newProfile)
        saveProfiles()
        applyProfile(id: newProfile.id)
    }
    
    func deleteProfile(id: UUID) {
        modProfiles.removeAll { $0.id == id }
        if activeProfileId == id {
            activeProfileId = nil
        }
        saveProfiles()
    }
    
    func updateProfile(id: UUID, newName: String, enabledModIds: [String]) {
        if let index = modProfiles.firstIndex(where: { $0.id == id }) {
            modProfiles[index].name = newName
            modProfiles[index].enabledModIds = enabledModIds
            saveProfiles()
            
            // If the active profile is updated, we should probably re-apply it to sync mods?
            // Wait, the user might just be editing a background profile. If it's active, maybe apply it?
            if activeProfileId == id {
                applyProfile(id: id)
            }
        }
    }
    
    func applyProfile(id: UUID?) {
        guard let id = id, let profile = modProfiles.first(where: { $0.id == id }) else {
            activeProfileId = nil
            saveProfiles()
            return
        }
        
        activeProfileId = id
        saveProfiles()
        
        let fm = FileManager.default
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let disabledModsPath = (gameDir as NSString).appendingPathComponent("Mods_disabled")
        
        // 1. First, move all currently enabled mods to disabled (except those that need to stay enabled)
        let currentlyEnabled = mods.filter { $0.isEnabled }
        for mod in currentlyEnabled {
            if !profile.enabledModIds.contains(mod.uniqueId) {
                let srcPath = (modsPath as NSString).appendingPathComponent(mod.folderName)
                let destPath = (disabledModsPath as NSString).appendingPathComponent(mod.folderName)
                let destParent = (destPath as NSString).deletingLastPathComponent
                try? fm.createDirectory(atPath: destParent, withIntermediateDirectories: true, attributes: nil)
                try? fm.moveItem(atPath: srcPath, toPath: destPath)
            }
        }
        
        // 2. Next, move all required disabled mods to enabled
        let currentlyDisabled = mods.filter { !$0.isEnabled }
        for mod in currentlyDisabled {
            if profile.enabledModIds.contains(mod.uniqueId) {
                let srcPath = (disabledModsPath as NSString).appendingPathComponent(mod.folderName)
                let destPath = (modsPath as NSString).appendingPathComponent(mod.folderName)
                let destParent = (destPath as NSString).deletingLastPathComponent
                try? fm.createDirectory(atPath: destParent, withIntermediateDirectories: true, attributes: nil)
                try? fm.moveItem(atPath: srcPath, toPath: destPath)
            }
        }
        
        // 3. Refresh mods list
        self.scanMods()
        self.log("สลับโปรไฟล์ม็อดเป็น: \(profile.name)")
    }
}
