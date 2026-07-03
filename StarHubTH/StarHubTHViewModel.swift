import Foundation
import Cocoa
import SwiftUI

struct ModItem: Identifiable, Equatable {
    var id: String { folderName }
    let name: String
    let folderName: String
    let version: String
    let author: String
    let description: String
    let nexusUrl: String
    var isEnabled: Bool
}

class StarHubTHViewModel: ObservableObject {
    @Published var gameDir: String = "" {
        didSet {
            UserDefaults.standard.set(gameDir, forKey: "gameDir")
            self.refresh()
        }
    }
    
    @Published var smapiInstalledVersion: String = "ยังไม่ได้ติดตั้ง"
    @Published var mods: [ModItem] = []
    @Published var logOutput: String = ""
    @Published var alertMessage: String = ""
    @Published var showAlert: Bool = false
    @Published var isThaiTranslationInstalled: Bool = false
    
    @Published var saves: [SaveGameInfo] = []
    @Published var editingSave: SaveGameInfo? = nil
    
    @Published var steamUsername: String = "ชาวไร่"
    @Published var steamAvatarPath: String? = nil
    
    let smapiInstaller = SmapiInstaller()
    
    init() {
        // Automatically retrieve saved game path, or attempt to find the default Steam path on Mac
        let savedPath = UserDefaults.standard.string(forKey: "gameDir") ?? ""
        if !savedPath.isEmpty && FileManager.default.fileExists(atPath: savedPath) {
            self.gameDir = savedPath
        } else {
            self.gameDir = self.detectDefaultGameDir()
        }
        self.refresh()
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
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let currentURL = URL(string: gameDir) {
            panel.directoryURL = currentURL
        }
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                self.gameDir = url.path
            }
        }
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
        func parseModFolder(at path: String, isEnabled: Bool) -> ModItem? {
            let manifestPath = (path as NSString).appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestPath) else { return nil }
            
            var name = (path as NSString).lastPathComponent
            var version = "Unknown"
            var author = "Unknown"
            var description = ""
            var nexusUrl = ""
            
            if let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
               let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                if let mName = json["Name"] as? String { name = mName }
                if let mVer = json["Version"] as? String { version = mVer }
                if let mAuthor = json["Author"] as? String { author = mAuthor }
                if let mDesc = json["Description"] as? String { description = mDesc }
                
                if let updateKeys = json["UpdateKeys"] as? [String] {
                    for key in updateKeys {
                        if key.lowercased().hasPrefix("nexus:") {
                            let id = key.replacingOccurrences(of: "nexus:", with: "", options: .caseInsensitive)
                            nexusUrl = "https://www.nexusmods.com/stardewvalley/mods/\(id.trimmingCharacters(in: .whitespacesAndNewlines))"
                            break
                        }
                    }
                }
            }
            
            return ModItem(
                name: name,
                folderName: (path as NSString).lastPathComponent,
                version: version,
                author: author,
                description: description,
                nexusUrl: nexusUrl,
                isEnabled: isEnabled
            )
        }
        
        // Scan enabled mods folder
        if let contents = try? fm.contentsOfDirectory(atPath: modsPath) {
            for entry in contents {
                if entry.hasPrefix(".") { continue }
                let entryPath = (modsPath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: entryPath, isDirectory: &isDir) && isDir.boolValue {
                    if let mod = parseModFolder(at: entryPath, isEnabled: true) {
                        scannedMods.append(mod)
                    }
                }
            }
        }
        
        // Scan disabled mods folder
        if let contents = try? fm.contentsOfDirectory(atPath: disabledModsPath) {
            for entry in contents {
                if entry.hasPrefix(".") { continue }
                let entryPath = (disabledModsPath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: entryPath, isDirectory: &isDir) && isDir.boolValue {
                    if let mod = parseModFolder(at: entryPath, isEnabled: false) {
                        scannedMods.append(mod)
                    }
                }
            }
        }
        
        self.mods = scannedMods.sorted { $0.name.lowercased() < $1.name.lowercased() }
        if self.selectedMod == nil, let first = self.mods.first {
            self.selectedMod = first
        }
        self.isThaiTranslationInstalled = scannedMods.contains {
            $0.folderName.lowercased() == "stardew valley - thai" ||
            $0.name.localizedCaseInsensitiveContains("thai")
        }
    }
    
    // Toggle Mod Status (Enabled / Disabled)
    func toggleMod(_ mod: ModItem) {
        let fm = FileManager.default
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let disabledModsPath = (gameDir as NSString).appendingPathComponent("Mods_disabled")
        
        let srcPath = ((mod.isEnabled ? modsPath : disabledModsPath) as NSString).appendingPathComponent(mod.folderName)
        let destFolder = mod.isEnabled ? disabledModsPath : modsPath
        let destPath = ((destFolder as NSString).appendingPathComponent(mod.folderName) as String)
        
        do {
            if !fm.fileExists(atPath: destFolder) {
                try fm.createDirectory(atPath: destFolder, withIntermediateDirectories: true, attributes: nil)
            }
            if fm.fileExists(atPath: destPath) {
                try fm.removeItem(atPath: destPath)
            }
            try fm.moveItem(atPath: srcPath, toPath: destPath)
            
            // Log action
            log("\(mod.isEnabled ? "ปิดใช้งาน" : "เปิดใช้งาน")ม็อด: \(mod.name)")
            
            // Refresh
            self.scanMods()
        } catch {
            self.showModal(message: "เปลี่ยนสถานะม็อดไม่สำเร็จ: \(error.localizedDescription)")
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
    
    func openSavesFolder() {
        let home = NSHomeDirectory()
        let savesDir = URL(fileURLWithPath: "\(home)/.config/StardewValley/Saves")
        NSWorkspace.shared.open(savesDir)
    }
}
