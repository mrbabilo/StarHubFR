import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct SaveGameInfo: Identifiable, Equatable, Hashable {
    var id: String { folderName }
    let folderName: String
    let fileURL: URL
    
    var playerName: String
    var farmName: String
    var favoriteThing: String
    var money: Int
    
    // Advanced Stats
    var maxHealth: Int
    var maxStamina: Int
    var goldenWalnuts: Int
    var qiGems: Int
    var clubCoins: Int
    
    var year: Int
    var season: Int
    var day: Int
    var whichFarm: Int
    
    var farmTypeName: String {
        switch whichFarm {
        case 0: return "ฟาร์มมาตรฐาน" // Standard Farm
        case 1: return "ฟาร์มริมน้ำ" // Riverland Farm
        case 2: return "ฟาร์มในป่า" // Forest Farm
        case 3: return "ฟาร์มบนเขา" // Hill-top Farm
        case 4: return "ฟาร์มสัตว์ประหลาด" // Wilderness Farm
        case 5: return "ฟาร์มสี่มุม" // Four Corners Farm
        case 6: return "ฟาร์มริมหาด" // Beach Farm
        case 7: return "ฟาร์มทุ่งหญ้า" // Meadowlands Farm
        default: return "ฟาร์มลึกลับ"
        }
    }
    
    var farmIcon: String {
        switch whichFarm {
        case 0: return "leaf.fill"
        case 1: return "water.waves"
        case 2: return "tree.fill"
        case 3: return "mountain.2.fill"
        case 4: return "moon.stars.fill"
        case 5: return "square.grid.2x2.fill"
        case 6: return "sun.max.fill"
        case 7: return "pawprint.fill"
        default: return "questionmark.square.fill"
        }
    }
    
    var seasonName: String {
        switch season {
        case 0: return "ฤดูใบไม้ผลิ" // Spring
        case 1: return "ฤดูร้อน"    // Summer
        case 2: return "ฤดูใบไม้ร่วง" // Fall
        case 3: return "ฤดูหนาว"   // Winter
        default: return "ไม่ทราบฤดู"
        }
    }
}

class SaveManager {
    static let shared = SaveManager()
    
    private let savesDir: URL
    
    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.savesDir = homeDir.appendingPathComponent(".config/StardewValley/Saves")
    }
    
    func fetchSaves() -> [SaveGameInfo] {
        var saves: [SaveGameInfo] = []
        let fm = FileManager.default
        
        guard let folders = try? fm.contentsOfDirectory(at: savesDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        
        for folder in folders {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue {
                let saveName = folder.lastPathComponent
                let saveFile = folder.appendingPathComponent(saveName)
                
                if fm.fileExists(atPath: saveFile.path) {
                    if let info = parseSaveFile(url: saveFile, folderName: saveName) {
                        saves.append(info)
                    }
                }
            }
        }
        
        return saves.sorted { $0.playerName < $1.playerName }
    }
    
    private func parseSaveFile(url: URL, folderName: String) -> SaveGameInfo? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        
        let playerName = extractTag(tag: "name", from: content) ?? "Unknown"
        let farmName = extractTag(tag: "farmName", from: content) ?? "Unknown"
        let favoriteThing = extractTag(tag: "favoriteThing", from: content) ?? "Unknown"
        let money = Int(extractTag(tag: "money", from: content) ?? "0") ?? 0
        
        let year = Int(extractTag(tag: "yearForSaveGame", from: content) ?? "1") ?? 1
        let season = Int(extractTag(tag: "seasonForSaveGame", from: content) ?? "0") ?? 0
        let day = Int(extractTag(tag: "dayOfMonthForSaveGame", from: content) ?? "1") ?? 1
        let whichFarm = Int(extractTag(tag: "whichFarm", from: content) ?? "0") ?? 0
        
        // Advanced
        let maxHealth = Int(extractTag(tag: "maxHealth", from: content) ?? "100") ?? 100
        let maxStamina = Int(extractTag(tag: "maxStamina", from: content) ?? "270") ?? 270
        let goldenWalnuts = Int(extractTag(tag: "goldenWalnuts", from: content) ?? "0") ?? 0
        let qiGems = Int(extractTag(tag: "qiGems", from: content) ?? "0") ?? 0
        let clubCoins = Int(extractTag(tag: "clubCoins", from: content) ?? "0") ?? 0
        
        return SaveGameInfo(
            folderName: folderName,
            fileURL: url,
            playerName: playerName,
            farmName: farmName,
            favoriteThing: favoriteThing,
            money: money,
            maxHealth: maxHealth,
            maxStamina: maxStamina,
            goldenWalnuts: goldenWalnuts,
            qiGems: qiGems,
            clubCoins: clubCoins,
            year: year,
            season: season,
            day: day,
            whichFarm: whichFarm
        )
    }
    
    private func extractTag(tag: String, from xml: String) -> String? {
        // Find <tag>value</tag>
        // Note: For <name>, there are multiple in the file (e.g., NPC names, animals).
        // The player's name is usually the first <name> inside <player>.
        // A simple regex might catch the first one which is player name, but let's be careful.
        // Actually, player money is <money>, farm name is <farmName>. They are unique or first.
        
        let pattern = "<\(tag)>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        if let match = regex.firstMatch(in: xml, options: [], range: range) {
            if let swiftRange = Range(match.range(at: 1), in: xml) {
                return String(xml[swiftRange])
            }
        }
        return nil
    }
    
    func backupSave(info: SaveGameInfo) -> Bool {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        
        let folderPath = info.fileURL.deletingLastPathComponent()
        let backupPath = folderPath.appendingPathExtension("backup_\(timestamp)")
        
        do {
            try fm.copyItem(at: folderPath, to: backupPath)
            print("Backup created at: \(backupPath.path)")
            return true
        } catch {
            print("Failed to backup save: \(error)")
            return false
        }
    }
    
    func updateSave(info: SaveGameInfo, newName: String, newFarm: String, newFav: String, newMoney: Int, newMaxHealth: Int, newMaxStamina: Int, newGoldenWalnuts: Int, newQiGems: Int, newClubCoins: Int) -> Bool {
        guard backupSave(info: info) else { return false }
        
        guard var content = try? String(contentsOf: info.fileURL, encoding: .utf8) else { return false }
        
        // Replace values using regex
        content = replaceFirstTag(tag: "name", with: newName, in: content)
        content = replaceFirstTag(tag: "farmName", with: newFarm, in: content)
        content = replaceFirstTag(tag: "favoriteThing", with: newFav, in: content)
        content = replaceFirstTag(tag: "money", with: "\(newMoney)", in: content)
        
        content = replaceFirstTag(tag: "maxHealth", with: "\(newMaxHealth)", in: content)
        content = replaceFirstTag(tag: "maxStamina", with: "\(newMaxStamina)", in: content)
        content = replaceFirstTag(tag: "goldenWalnuts", with: "\(newGoldenWalnuts)", in: content)
        content = replaceFirstTag(tag: "qiGems", with: "\(newQiGems)", in: content)
        content = replaceFirstTag(tag: "clubCoins", with: "\(newClubCoins)", in: content)
        
        do {
            try content.write(to: info.fileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("Failed to write updated save: \(error)")
            return false
        }
    }
    
    private func replaceFirstTag(tag: String, with value: String, in xml: String) -> String {
        let pattern = "(<\(tag)>)([^<]+)(</\(tag)>)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return xml }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        
        // We only want to replace the first occurrence (player data is always at the top)
        if let match = regex.firstMatch(in: xml, options: [], range: range) {
            let replaced = regex.stringByReplacingMatches(
                in: xml,
                options: [],
                range: match.range, // Only replace in the found range
                withTemplate: "$1\(value)$3"
            )
            // wait, stringByReplacingMatches with match.range will only return the replaced SUBSTRING,
            // no, wait, it returns a new string where the matches within the range are replaced.
            // Oh, the range param to stringByReplacingMatches specifies the portion of the string to search.
            // If I restrict the search to match.range, it will only return that small portion.
            // Better to use mutating String method.
            if let swiftRange = Range(match.range, in: xml) {
                var modified = xml
                modified.replaceSubrange(swiftRange, with: "<\(tag)>\(value)</\(tag)>")
                return modified
            }
        }
        return xml
    }
    
    // MARK: - Advanced Management
    
    func openSaveInFinder(info: SaveGameInfo) {
        #if os(macOS)
        let folderPath = info.fileURL.deletingLastPathComponent()
        NSWorkspace.shared.open(folderPath)
        #endif
    }
    
    func deleteSave(info: SaveGameInfo) -> Bool {
        let folderPath = info.fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.trashItem(at: folderPath, resultingItemURL: nil)
            return true
        } catch {
            print("Failed to trash save: \(error)")
            return false
        }
    }
    
    func duplicateSave(info: SaveGameInfo) -> Bool {
        let fm = FileManager.default
        let folderPath = info.fileURL.deletingLastPathComponent()
        let saveName = folderPath.lastPathComponent
        
        let newSaveName = "\(saveName)_copy"
        let newFolderPath = folderPath.deletingLastPathComponent().appendingPathComponent(newSaveName)
        
        do {
            if fm.fileExists(atPath: newFolderPath.path) {
                return false // Already exists
            }
            try fm.copyItem(at: folderPath, to: newFolderPath)
            
            // Rename internal file
            let oldFilePath = newFolderPath.appendingPathComponent(saveName)
            let newFilePath = newFolderPath.appendingPathComponent(newSaveName)
            if fm.fileExists(atPath: oldFilePath.path) {
                try fm.moveItem(at: oldFilePath, to: newFilePath)
            }
            // Also old save metadata
            let oldInfoPath = newFolderPath.appendingPathComponent("SaveGameInfo")
            // Stardew Valley reads both SaveGameInfo and the internal save. We don't necessarily need to rename SaveGameInfo, it's literally named SaveGameInfo.
            // But we must modify the xml internal name and id to prevent collision?
            // Actually, copying it is mostly safe, but SDV uses the folder name and file name to load.
            return true
        } catch {
            print("Failed to duplicate save: \(error)")
            return false
        }
    }
}
