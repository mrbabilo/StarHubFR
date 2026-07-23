import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Save Backup Model

public struct SaveBackup: Identifiable, Equatable {
    public var id: String { folderPath.path }
    public let folderPath: URL
    public let timestamp: Date
    public let saveFolder: String   // parent save folder name

    public init(folderPath: URL, timestamp: Date, saveFolder: String) {
        self.folderPath = folderPath
        self.timestamp = timestamp
        self.saveFolder = saveFolder
    }
}

struct SaveNote: Codable {
    var tag: String   // emoji tag key e.g. "⭐", "🏆", ""
    var note: String  // free text
    var customIconPath: String?
}

// MARK: - Save Notes Store (UserDefaults-backed)

class SaveNotesStore {
    static let shared = SaveNotesStore()
    private let key = "SaveNotes_v2" // Upgraded version key to prevent conflicts

    private var cache: [String: SaveNote] = [:]

    init() { load() }

    func note(for folderName: String) -> SaveNote {
        cache[folderName] ?? SaveNote(tag: "", note: "", customIconPath: nil)
    }

    func setNote(for folderName: String, tag: String, note: String, customIconPath: String? = nil) {
        cache[folderName] = SaveNote(tag: tag, note: note, customIconPath: customIconPath)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: SaveNote].self, from: data)
        else { return }
        cache = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}


struct SaveNode: Identifiable, Equatable {
    var id: String { info.id }
    let info: SaveGameInfo
    var children: [SaveNode]
}

public struct SaveGameInfo: Identifiable, Equatable, Hashable {
    public var id: String { folderName }
    public let folderName: String
    public let fileURL: URL
    public let lastModified: Date

    public var playerName: String
    public var farmName: String
    public var favoriteThing: String
    public var money: Int
    public var spouse: String   // empty string = single (no <spouse> tag)

    // Advanced Stats
    public var maxHealth: Int
    public var maxStamina: Int
    public var goldenWalnuts: Int
    public var qiGems: Int
    public var clubCoins: Int
    public var totalMoneyEarned: Int

    public var year: Int
    public var season: Int
    public var day: Int
    public var whichFarm: Int

    public init(
        folderName: String,
        fileURL: URL,
        lastModified: Date,
        playerName: String,
        farmName: String,
        favoriteThing: String,
        money: Int,
        spouse: String,
        maxHealth: Int,
        maxStamina: Int,
        goldenWalnuts: Int,
        qiGems: Int,
        clubCoins: Int,
        totalMoneyEarned: Int,
        year: Int,
        season: Int,
        day: Int,
        whichFarm: Int
    ) {
        self.folderName = folderName
        self.fileURL = fileURL
        self.lastModified = lastModified
        self.playerName = playerName
        self.farmName = farmName
        self.favoriteThing = favoriteThing
        self.money = money
        self.spouse = spouse
        self.maxHealth = maxHealth
        self.maxStamina = maxStamina
        self.goldenWalnuts = goldenWalnuts
        self.qiGems = qiGems
        self.clubCoins = clubCoins
        self.totalMoneyEarned = totalMoneyEarned
        self.year = year
        self.season = season
        self.day = day
        self.whichFarm = whichFarm
    }

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
        case 0: return L10n.Saves.spring
        case 1: return L10n.Saves.summer
        case 2: return L10n.Saves.fall
        case 3: return L10n.Saves.winter
        default: return L10n.Saves.spring
        }
    }
}

public class SaveManager {
    public static let shared = SaveManager()

    private let savesDir: URL

    /// Cache of compiled regexes for `<tag>([^<]+)</tag>` keyed by tag name.
    /// `NSRegularExpression` compilation is expensive; `fetchSaves()` parses ~14
    /// tags per save file, so caching avoids recompiling the same pattern hundreds
    /// of times across reloads.
    private static var regexCache: [String: NSRegularExpression] = [:]
    private static let regexCacheLock = NSLock()

    private static func cachedRegex(for tag: String) -> NSRegularExpression? {
        Self.regexCacheLock.lock()
        let cached = Self.regexCache[tag]
        Self.regexCacheLock.unlock()
        if let cached = cached { return cached }
        let pattern = "<\(tag)>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        Self.regexCacheLock.lock()
        Self.regexCache[tag] = regex
        Self.regexCacheLock.unlock()
        return regex
    }

    public init() {
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
        let spouse = extractSpouseFromPlayer(from: content) ?? ""
        
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
        let totalMoneyEarned = Int(extractTag(tag: "totalMoneyEarned", from: content) ?? "0") ?? 0
        
        let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
        let lastModified = attr?[.modificationDate] as? Date ?? Date()
        
        return SaveGameInfo(
            folderName: folderName,
            fileURL: url,
            lastModified: lastModified,
            playerName: playerName,
            farmName: farmName,
            favoriteThing: favoriteThing,
            money: money,
            spouse: spouse,
            maxHealth: maxHealth,
            maxStamina: maxStamina,
            goldenWalnuts: goldenWalnuts,
            qiGems: qiGems,
            clubCoins: clubCoins,
            totalMoneyEarned: totalMoneyEarned,
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

        guard let regex = Self.cachedRegex(for: tag) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        if let match = regex.firstMatch(in: xml, options: [], range: range) {
            if let swiftRange = Range(match.range(at: 1), in: xml) {
                return String(xml[swiftRange])
            }
        }
        return nil
    }
    
    /// Extract spouse from inside the <player>...</player> block only,
    /// to avoid picking up NPC <spouse> tags in other parts of the save.
    private func extractSpouseFromPlayer(from xml: String) -> String? {
        // Find the <player> block
        guard let playerStart = xml.range(of: "<player>"),
              let playerEnd = xml.range(of: "</player>", range: playerStart.upperBound..<xml.endIndex) else {
            return extractTag(tag: "spouse", from: xml)  // fallback
        }
        let playerBlock = String(xml[playerStart.lowerBound..<playerEnd.upperBound])
        return extractTag(tag: "spouse", from: playerBlock)
    }
    
    /// Update or remove the <spouse> tag inside the <player> block.
    /// - If newSpouse is non-empty: sets <spouse>newSpouse</spouse>
    /// - If newSpouse is empty: removes the <spouse>...</spouse> tag
    private func updateSpouseInPlayer(newSpouse: String, in xml: String) -> String {
        let spousePattern = "<spouse>[^<]*</spouse>"
        guard let regex = try? NSRegularExpression(pattern: spousePattern, options: []) else { return xml }
        
        // Find <player> block range
        guard let playerStartRange = xml.range(of: "<player>"),
              let playerEndRange = xml.range(of: "</player>", range: playerStartRange.upperBound..<xml.endIndex) else {
            // Fallback: operate on whole file
            return replaceOrRemoveSpouseTag(newSpouse: newSpouse, in: xml, using: regex)
        }
        
        let beforePlayer = String(xml[..<playerStartRange.lowerBound])
        let playerBlock  = String(xml[playerStartRange.lowerBound..<playerEndRange.upperBound])
        let afterPlayer  = String(xml[playerEndRange.upperBound...])
        
        let updatedPlayer = replaceOrRemoveSpouseTag(newSpouse: newSpouse, in: playerBlock, using: regex)
        return beforePlayer + updatedPlayer + afterPlayer
    }
    
    private func replaceOrRemoveSpouseTag(newSpouse: String, in block: String, using regex: NSRegularExpression) -> String {
        let nsBlock = block as NSString
        let fullRange = NSRange(location: 0, length: nsBlock.length)
        
        if newSpouse.isEmpty {
            // Remove the <spouse>...</spouse> tag entirely
            return regex.stringByReplacingMatches(in: block, options: [], range: fullRange, withTemplate: "")
        } else {
            let replacement = "<spouse>\(newSpouse)</spouse>"
            let firstMatch = regex.firstMatch(in: block, options: [], range: fullRange)
            if firstMatch != nil {
                // Tag exists — replace it
                return regex.stringByReplacingMatches(in: block, options: [], range: firstMatch!.range, withTemplate: replacement)
            } else {
                // Tag doesn't exist — insert after <name>...</name>
                let namePattern = "(<name>[^<]*</name>)"
                guard let nameRegex = try? NSRegularExpression(pattern: namePattern, options: []),
                      let nameMatch = nameRegex.firstMatch(in: block, options: [], range: fullRange),
                      let nameRange = Range(nameMatch.range, in: block) else {
                    return block  // cannot insert safely
                }
                var modified = block
                modified.insert(contentsOf: "<spouse>\(newSpouse)</spouse>", at: nameRange.upperBound)
                return modified
            }
        }
    }
    
    public func backupSave(info: SaveGameInfo) -> Bool {
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
    
    func updateSave(info: SaveGameInfo, newName: String, newFarm: String, newFav: String, newMoney: Int, newTotalMoneyEarned: Int, newMaxHealth: Int, newMaxStamina: Int, newGoldenWalnuts: Int, newQiGems: Int, newClubCoins: Int, newSpouse: String) -> Bool {
        guard backupSave(info: info) else { return false }
        
        guard var content = try? String(contentsOf: info.fileURL, encoding: .utf8) else { return false }
        
        // Replace values using regex
        content = replaceFirstTagInPlayer(tag: "name", with: newName, in: content)
        content = replaceFirstTagInPlayer(tag: "farmName", with: newFarm, in: content)
        content = replaceFirstTagInPlayer(tag: "favoriteThing", with: newFav, in: content)
        content = replaceFirstTagInPlayer(tag: "money", with: "\(newMoney)", in: content)
        content = replaceFirstTagInPlayer(tag: "totalMoneyEarned", with: "\(newTotalMoneyEarned)", in: content)

        content = replaceFirstTagInPlayer(tag: "maxHealth", with: "\(newMaxHealth)", in: content)
        content = replaceFirstTagInPlayer(tag: "maxStamina", with: "\(newMaxStamina)", in: content)
        content = replaceFirstTagInPlayer(tag: "goldenWalnuts", with: "\(newGoldenWalnuts)", in: content)
        content = replaceFirstTagInPlayer(tag: "qiGems", with: "\(newQiGems)", in: content)
        content = replaceFirstTagInPlayer(tag: "clubCoins", with: "\(newClubCoins)", in: content)
        
        let oldSpouse = info.spouse   // NPC name before the edit
        
        // Spouse: update or remove tag inside <player> block
        content = updateSpouseInPlayer(newSpouse: newSpouse, in: content)
        
        // If removing or changing a spouse, also fix the NPC's friendship entry
        // so they return to their original home/schedule without glitching.
        if !oldSpouse.isEmpty && newSpouse != oldSpouse {
            content = cleanDivorceNPCFriendship(npcName: oldSpouse, in: content)
        }
        
        do {
            try content.write(to: info.fileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("Failed to write updated save: \(error)")
            return false
        }
    }
    
    /// Cleans up a previously married NPC's friendship entry so they return
    /// to their normal home and schedule without bugging out.
    ///
    /// Changes inside the NPC's `<Friendship>` block (inside a `<key><string>NpcName</string></key>` item):
    ///   - `<Status>Married</Status>`  →  `<Status>Friendly</Status>`
    ///   - `<WeddingDate>...</WeddingDate>` block is removed entirely
    ///
    /// Scoped to the `<player>` block (and `<friendshipData>` within it when
    /// present) so this can't match a farmhand's own friendship data or an
    /// unrelated `<string>NpcName</string>` occurrence elsewhere in the save.
    private func cleanDivorceNPCFriendship(npcName: String, in xml: String) -> String {
        guard let playerStartRange = xml.range(of: "<player>"),
              let playerEndRange = xml.range(of: "</player>", range: playerStartRange.upperBound..<xml.endIndex) else {
            print("[Divorce] Could not find <player> block")
            return xml
        }

        let beforePlayer = String(xml[..<playerStartRange.lowerBound])
        let playerBlock  = String(xml[playerStartRange.lowerBound..<playerEndRange.upperBound])
        let afterPlayer  = String(xml[playerEndRange.upperBound...])

        let updatedPlayerBlock = cleanDivorceNPCFriendshipInScope(npcName: npcName, in: playerBlock)
        return beforePlayer + updatedPlayerBlock + afterPlayer
    }

    /// Narrows further to `<friendshipData>...</friendshipData>` when present,
    /// then delegates to `cleanDivorceNPCFriendshipEntry` for the actual edit.
    private func cleanDivorceNPCFriendshipInScope(npcName: String, in xml: String) -> String {
        guard let fdStartRange = xml.range(of: "<friendshipData>"),
              let fdEndRange = xml.range(of: "</friendshipData>", range: fdStartRange.upperBound..<xml.endIndex) else {
            // friendshipData tag not found under this name in this save version — operate on the player block itself.
            return cleanDivorceNPCFriendshipEntry(npcName: npcName, in: xml)
        }

        let before = String(xml[..<fdStartRange.lowerBound])
        let fdBlock = String(xml[fdStartRange.lowerBound..<fdEndRange.upperBound])
        let after  = String(xml[fdEndRange.upperBound...])

        return before + cleanDivorceNPCFriendshipEntry(npcName: npcName, in: fdBlock) + after
    }

    /// Locates the `<item>` block keyed by `npcName` within the given scope
    /// and applies the Married→Friendly / WeddingDate-removal edit to it.
    private func cleanDivorceNPCFriendshipEntry(npcName: String, in xml: String) -> String {
        // We locate the <item> block that belongs to this NPC.
        // Structure: <item><key><string>NpcName</string></key><value><Friendship>...</Friendship></value></item>
        let keyMarker = "<string>\(npcName)</string>"
        guard let keyRange = xml.range(of: keyMarker) else {
            print("[Divorce] Could not find friendship entry for \(npcName)")
            return xml
        }

        // Find the enclosing <item>...</item> that contains this key
        let beforeKey = String(xml[..<keyRange.lowerBound])
        guard let itemStart = beforeKey.range(of: "<item>", options: .backwards) else {
            print("[Divorce] Could not find <item> before key for \(npcName)")
            return xml
        }

        let itemStartIdx = itemStart.lowerBound
        guard let itemEnd = xml.range(of: "</item>", range: keyRange.upperBound..<xml.endIndex) else {
            print("[Divorce] Could not find </item> after key for \(npcName)")
            return xml
        }

        let itemEndIdx = itemEnd.upperBound

        let beforeItem = String(xml[..<itemStartIdx])
        var itemBlock  = String(xml[itemStartIdx..<itemEndIdx])
        let afterItem  = String(xml[itemEndIdx...])

        // 1. Change <Status>Married</Status> → <Status>Friendly</Status>
        itemBlock = itemBlock.replacingOccurrences(of: "<Status>Married</Status>", with: "<Status>Friendly</Status>")

        // 2. Remove <WeddingDate>...</WeddingDate> (multiline/nested block)
        //    Pattern matches <WeddingDate> followed by any content up to </WeddingDate>
        if let wdRegex = try? NSRegularExpression(pattern: "<WeddingDate>.*?</WeddingDate>", options: .dotMatchesLineSeparators) {
            let nsBlock = itemBlock as NSString
            itemBlock = wdRegex.stringByReplacingMatches(
                in: itemBlock, options: [],
                range: NSRange(location: 0, length: nsBlock.length),
                withTemplate: ""
            )
        }

        return beforeItem + itemBlock + afterItem
    }


    /// Like replaceFirstTag, but scoped to the <player> block so it can't
    /// accidentally match an NPC's, farmhand's (<Farmer> in <farmhands>), or
    /// location's identically named tag that happens to appear earlier in
    /// the file than the intended player field.
    ///
    /// Falls back to whole-file replacement if the <player> block can't be
    /// found, or if the tag doesn't appear inside it — some save fields
    /// (e.g. goldenWalnuts, which is farm-wide) live outside <player>, and
    /// those must remain editable rather than silently no-op.
    private func replaceFirstTagInPlayer(tag: String, with value: String, in xml: String) -> String {
        guard let playerStartRange = xml.range(of: "<player>"),
              let playerEndRange = xml.range(of: "</player>", range: playerStartRange.upperBound..<xml.endIndex) else {
            return replaceFirstTag(tag: tag, with: value, in: xml)
        }

        let beforePlayer = String(xml[..<playerStartRange.lowerBound])
        let playerBlock  = String(xml[playerStartRange.lowerBound..<playerEndRange.upperBound])
        let afterPlayer  = String(xml[playerEndRange.upperBound...])

        guard playerBlock.contains("<\(tag)>") else {
            return replaceFirstTag(tag: tag, with: value, in: xml)
        }

        let updatedPlayer = replaceFirstTag(tag: tag, with: value, in: playerBlock)
        return beforePlayer + updatedPlayer + afterPlayer
    }

    private func replaceFirstTag(tag: String, with value: String, in xml: String) -> String {
        let pattern = "(<\(tag)>)([^<]+)(</\(tag)>)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return xml }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        
        // We only want to replace the first occurrence (player data is always at the top)
        if let match = regex.firstMatch(in: xml, options: [], range: range) {

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
    
    public func deleteSave(info: SaveGameInfo) -> Bool {
        let folderPath = info.fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.trashItem(at: folderPath, resultingItemURL: nil)
            return true
        } catch {
            print("Failed to trash save: \(error)")
            return false
        }
    }
    
    private func modifyInternalSaveNames(in folderURL: URL, newSaveName: String, newPlayerName: String, newFarmName: String) {
        let fm = FileManager.default
        let saveGameInfoURL = folderURL.appendingPathComponent("SaveGameInfo")
        let mainSaveURL = folderURL.appendingPathComponent(newSaveName)
        
        func updateFile(at url: URL) {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
            var modified = replaceFirstTag(tag: "name", with: newPlayerName, in: content)
            modified = replaceFirstTag(tag: "farmName", with: newFarmName, in: modified)
            try? modified.write(to: url, atomically: true, encoding: .utf8)
        }
        
        if fm.fileExists(atPath: saveGameInfoURL.path) {
            updateFile(at: saveGameInfoURL)
        }
        if fm.fileExists(atPath: mainSaveURL.path) {
            updateFile(at: mainSaveURL)
        }
    }

    /// Copies `sourceFolder` (a save's own folder or a backup's folder) into
    /// a new sibling folder named "<baseName>_<suffix>" (appending "_2",
    /// "_3"... on collision), renames the internal save file to match, and
    /// patches its name/farm-name XML fields. Shared by duplicateSave and
    /// branchFromBackup, which differ only in where sourceFolder/baseName
    /// come from.
    private func cloneSaveFolder(sourceFolder: URL, baseName: String, suffix: String, newPlayerName: String, newFarmName: String, context: String) -> Bool {
        let fm = FileManager.default
        let parentDir = sourceFolder.deletingLastPathComponent()

        var newSaveName = "\(baseName)_\(suffix)"
        var newFolderPath = parentDir.appendingPathComponent(newSaveName)

        var counter = 1
        while fm.fileExists(atPath: newFolderPath.path) {
            newSaveName = "\(baseName)_\(suffix)_\(counter)"
            newFolderPath = parentDir.appendingPathComponent(newSaveName)
            counter += 1
        }

        do {
            try fm.copyItem(at: sourceFolder, to: newFolderPath)

            // Rename internal file
            let oldFilePath = newFolderPath.appendingPathComponent(baseName)
            let newFilePath = newFolderPath.appendingPathComponent(newSaveName)
            if fm.fileExists(atPath: oldFilePath.path) {
                try fm.moveItem(at: oldFilePath, to: newFilePath)
            }

            // Modify name and farm name inside XML files
            modifyInternalSaveNames(in: newFolderPath, newSaveName: newSaveName, newPlayerName: newPlayerName, newFarmName: newFarmName)

            return true
        } catch {
            print("Failed to \(context): \(error)")
            return false
        }
    }

    public func duplicateSave(info: SaveGameInfo, newName: String, newFarm: String) -> Bool {
        let folderPath = info.fileURL.deletingLastPathComponent()
        let saveName = folderPath.lastPathComponent
        return cloneSaveFolder(sourceFolder: folderPath, baseName: saveName, suffix: "copy", newPlayerName: newName, newFarmName: newFarm, context: "duplicate save")
    }

    // MARK: - Backup Timeline

    public func branchFromBackup(backup: SaveBackup, newName: String, newFarm: String) -> Bool {
        let backupFolderPath = backup.folderPath
        let originalSaveName = String(backupFolderPath.lastPathComponent.split(separator: ".")[0])
        return cloneSaveFolder(sourceFolder: backupFolderPath, baseName: originalSaveName, suffix: "branch", newPlayerName: newName, newFarmName: newFarm, context: "branch backup")
    }

    /// List all `.backup_*` sibling folders for a given save
    public func listBackups(for info: SaveGameInfo) -> [SaveBackup] {
        let saveFolder = info.fileURL.deletingLastPathComponent()
        let parentDir = saveFolder.deletingLastPathComponent()
        let saveName = saveFolder.lastPathComponent

        guard let items = try? FileManager.default.contentsOfDirectory(
            at: parentDir,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var backups: [SaveBackup] = []
        for item in items {
            let name = item.lastPathComponent
            // Match pattern: saveName.backup_YYYYMMDD_HHMMSS
            let prefix = "\(saveName).backup_"
            guard name.hasPrefix(prefix) else { continue }

            let tsString = String(name.dropFirst(prefix.count))
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let date = formatter.date(from: tsString) ?? Date()

            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                backups.append(SaveBackup(folderPath: item, timestamp: date, saveFolder: saveName))
            }
        }
        return backups.sorted { $0.timestamp > $1.timestamp }
    }

    /// Restore a backup: backup current save first, then swap
    public func restoreBackup(backup: SaveBackup, info: SaveGameInfo) -> Bool {
        let fm = FileManager.default
        let saveFolder = info.fileURL.deletingLastPathComponent()

        // 1. First backup the current state before restoring
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let preRestoreBackupPath = saveFolder
            .deletingLastPathComponent()
            .appendingPathComponent("\(saveFolder.lastPathComponent).backup_\(timestamp)")
        let tempTrash = saveFolder.deletingLastPathComponent()
            .appendingPathComponent("\(saveFolder.lastPathComponent)_RESTORING_TEMP")

        // A previous restore attempt that failed before reaching cleanup can
        // leave `tempTrash` behind, which would make `moveItem` below refuse
        // to overwrite it. Clear it first — anything in it is already
        // superseded by `preRestoreBackupPath` copies from those attempts.
        if fm.fileExists(atPath: tempTrash.path) {
            try? fm.removeItem(at: tempTrash)
        }

        // Tracks whether the live save folder has been moved aside to
        // `tempTrash` yet, so a failure after that point can move it back
        // instead of leaving the path the game expects to find empty.
        var liveFolderMovedAside = false
        // Set once the backup has actually been copied into `saveFolder`.
        // Only failures *before* this point should trigger the rollback —
        // a failure afterward (e.g. trashing the now-redundant temp copy)
        // must not undo a restore that already succeeded.
        var restoreCompleted = false

        do {
            // Backup current state
            try fm.copyItem(at: saveFolder, to: preRestoreBackupPath)

            // Remove current save folder content (move to trash first, then restore)
            try fm.moveItem(at: saveFolder, to: tempTrash)
            liveFolderMovedAside = true

            // Copy backup into place
            try fm.copyItem(at: backup.folderPath, to: saveFolder)
            restoreCompleted = true

            // Trash the temp. Non-fatal: the restore already succeeded, so a
            // failure here just leaves `tempTrash` for next time to clean up
            // (see the check at the top of this function) rather than
            // reverting a completed restore.
            try? fm.trashItem(at: tempTrash, resultingItemURL: nil)

            return true
        } catch {
            print("Failed to restore backup: \(error)")
            if liveFolderMovedAside && !restoreCompleted {
                // Put the live save back where the game expects it. Clear
                // any partial folder a failed copy may have left behind
                // first — moveItem refuses to overwrite an existing
                // destination.
                if fm.fileExists(atPath: saveFolder.path) {
                    try? fm.removeItem(at: saveFolder)
                }
                try? fm.moveItem(at: tempTrash, to: saveFolder)
            }
            return false
        }
    }

    /// Delete a single backup folder
    public func deleteBackup(_ backup: SaveBackup) -> Bool {
        do {
            try FileManager.default.trashItem(at: backup.folderPath, resultingItemURL: nil)
            return true
        } catch {
            print("Failed to delete backup: \(error)")
            return false
        }
    }
    // MARK: - Inventory Editing
    
    func fetchInventory(for info: SaveGameInfo) -> [InventoryItem]? {
        guard let data = try? Data(contentsOf: info.fileURL),
              let document = try? XMLDocument(data: data, options: .documentTidyXML),
              let root = document.rootElement() else {
            return nil
        }
        
        var inventory: [InventoryItem] = []
        
        // Find /SaveGame/player/items
        let player = root.elements(forName: "player").first
        let itemsElement = player?.elements(forName: "items").first
        
        guard let itemsNode = itemsElement else { return nil }
        
        let itemNodes = itemsNode.elements(forName: "Item")
        
        for (index, itemNode) in itemNodes.enumerated() {
            let xsiType = itemNode.attribute(forName: "xsi:type")?.stringValue ?? ""
            
            if xsiType == "Object" {
                let name = itemNode.elements(forName: "name").first?.stringValue ?? "Unknown"
                let itemId = itemNode.elements(forName: "itemId").first?.stringValue ?? "Unknown"
                let stack = Int(itemNode.elements(forName: "stack").first?.stringValue ?? "1") ?? 1
                
                inventory.append(InventoryItem(slotIndex: index, itemId: itemId, name: name, stack: stack, isObject: true))
            } else if itemNode.attribute(forName: "xsi:nil")?.stringValue == "true" {
                // Empty slot
                inventory.append(InventoryItem.empty(slot: index))
            } else {
                // Other items like weapons, rings, etc.
                let name = itemNode.elements(forName: "name").first?.stringValue ?? xsiType
                let itemId = itemNode.elements(forName: "itemId").first?.stringValue ?? ""
                let displayName = name.isEmpty ? (xsiType.isEmpty ? "Unknown Item" : xsiType) : name
                inventory.append(InventoryItem(slotIndex: index, itemId: itemId, name: displayName, stack: 1, isObject: false))
            }
        }
        
        return inventory
    }
    
    func updateInventory(info: SaveGameInfo, items: [InventoryItem]) -> Bool {
        // Backup first
        guard backupSave(info: info) else { return false }
        
        guard let data = try? Data(contentsOf: info.fileURL),
              let document = try? XMLDocument(data: data, options: .documentTidyXML),
              let root = document.rootElement() else {
            return false
        }
        
        // Find /SaveGame/player/items
        guard let player = root.elements(forName: "player").first,
              let itemsElement = player.elements(forName: "items").first else {
            return false
        }
        
        let itemNodes = itemsElement.elements(forName: "Item")
        
        for updatedItem in items {
            guard updatedItem.slotIndex >= 0 && updatedItem.slotIndex < itemNodes.count else { continue }
            let nodeToUpdate = itemNodes[updatedItem.slotIndex]
            
            // Only update if it's an Object
            if updatedItem.isObject {
                // Stack
                if let stackNode = nodeToUpdate.elements(forName: "stack").first {
                    stackNode.stringValue = "\(updatedItem.stack)"
                } else {
                    let newStack = XMLElement(name: "stack", stringValue: "\(updatedItem.stack)")
                    nodeToUpdate.addChild(newStack)
                }
                
                // Item ID (if needed, but usually we just update stack for safety)
                if let idNode = nodeToUpdate.elements(forName: "itemId").first {
                    idNode.stringValue = updatedItem.itemId
                }
            } else if updatedItem.name.isEmpty {
                // Delete the item (make it an empty slot)
                nodeToUpdate.setChildren(nil)
                if let nilAttr = XMLNode.attribute(withName: "xsi:nil", stringValue: "true") as? XMLNode {
                    nodeToUpdate.attributes = [nilAttr]
                }
            }
        }
        
        do {
            let updatedXMLData = document.xmlData(options: .nodePrettyPrint)
            try updatedXMLData.write(to: info.fileURL, options: .atomic)
            return true
        } catch {
            print("Failed to save updated inventory XML: \(error)")
            return false
        }
    }
}
