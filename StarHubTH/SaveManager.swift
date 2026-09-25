import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Save Backup Model

/// `Sendable` explicite (P5-L6, type public : jamais inféré, §9).
public struct SaveBackup: Identifiable, Equatable, Sendable {
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

/// `@MainActor` (P5-L5) : un `static let shared` non-`Sendable` est une
/// erreur en Swift 6. Magasin `@Observable` lu par les vues ; ses huit
/// appelants sont déjà sur main, aucun `await` ajouté.
@Observable
@MainActor
final class SaveNotesStore {
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

/// Couleur de cheveux (`<hairstyleColor>`) : un `Color` XNA **libre**
/// (B,G,R,A,PackedValue), pas un index de palette. Bornée à 0-255.
public struct SaveHairColor: Hashable, Sendable {
    public var r: Int
    public var g: Int
    public var b: Int

    public init(r: Int, g: Int, b: Int) {
        func clamp255(_ v: Int) -> Int { min(max(v, 0), 255) }
        self.r = clamp255(r)
        self.g = clamp255(g)
        self.b = clamp255(b)
    }

    /// Brun du préréglage n° 0, sans couleur lisible.
    public static let `default` = SaveHairColor(r: 90, g: 73, b: 38)
}

/// `Sendable` explicite (P5-L6) : emporté hors de l'acteur principal par
/// les opérations lourdes.
public struct SaveGameInfo: Identifiable, Equatable, Hashable, Sendable {
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
    public var hairStyle: Int = 0
    public var hairColor: SaveHairColor = .default
    public var skinIndex: Int = 0
    public var modFarmName: String? = nil
    /// Sexe du fermier, lu sur l'enfant **direct** de `<player>` (la première
    /// occurrence du fichier est un objet ou un monstre : 41 à 294 par save).
    /// `Undefined`/absent = fermier.
    public var isFemale: Bool = false

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
        whichFarm: Int,
        hairStyle: Int = 0,
        hairColor: SaveHairColor = .default,
        skinIndex: Int = 0,
        modFarmName: String? = nil,
        isFemale: Bool = false
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
        self.hairStyle = hairStyle
        self.hairColor = hairColor
        self.skinIndex = skinIndex
        self.modFarmName = modFarmName
        self.isFemale = isFemale
    }

    var farmTypeName: String {
        switch whichFarm {
        case 0: return L10n.Saves.farmTypeStandard
        case 1: return L10n.Saves.farmTypeRiverland
        case 2: return L10n.Saves.farmTypeForest
        case 3: return L10n.Saves.farmTypeHilltop
        case 4: return L10n.Saves.farmTypeWilderness
        case 5: return L10n.Saves.farmTypeFourCorners
        case 6: return L10n.Saves.farmTypeBeach
        case 7: return L10n.Saves.farmTypeMeadowlands
        default: return L10n.Saves.farmTypeMod
        }
    }

    static func farmIcon(for whichFarm: Int) -> String {
        switch whichFarm {
        case 0: return "leaf.fill"
        case 1: return "water.waves"
        case 2: return "tree.fill"
        case 3: return "mountain.2.fill"
        case 4: return "moon.stars.fill"
        case 5: return "square.grid.2x2.fill"
        case 6: return "sun.max.fill"
        case 7: return "pawprint.fill"
        // Ferme de mod reconnue (`SaveFarmType`) : pas de point d'interrogation.
        default: return "house.fill"
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

/// `@unchecked` : `parseCache` (état d'instance) pris sous
/// `parseCacheLock` à ses trois accès ; `regexCache` sous
/// `regexCacheLock`. Lit le disque depuis des files de fond : pas
/// `@MainActor`.
public final class SaveManager: @unchecked Sendable {
    public static let shared = SaveManager()

    private let savesDir: URL

    /// Compiled regex cache per tag (~14 tags per save, reloaded often).
    /// `nonisolated(unsafe)` : tout accès passe par `regexCacheLock`.
    nonisolated(unsafe) private static var regexCache: [String: NSRegularExpression] = [:]
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

    /// Une lecture mémorisée, avec l'empreinte du fichier qui l'a produite.
    private struct ParsedSave {
        let modified: Date
        let size: Int64
        let folderName: String
        let info: SaveGameInfo
    }

    /// Mémoïsation de `fetchSaves()` (~230 ms par fichier de 37 Mo inchangé),
    /// empreinte **date + taille** (la date seule survit à une restauration) ;
    /// angle mort fermé par l'invalidation de tout chemin d'écriture. Verrou
    /// dédié (lu hors main). **Par instance** : un cache statique rendait les
    /// tests parallèles intermittents (2026-09-03).
    private var parseCache: [String: ParsedSave] = [:]
    private let parseCacheLock = NSLock()

    /// Vide tout le cache à chaque écriture : une invalidation partielle
    /// oubliée resservirait du périmé.
    public func invalidateParseCache() {
        parseCacheLock.lock()
        parseCache.removeAll()
        parseCacheLock.unlock()
    }

    private static func stamp(of url: URL) -> (modified: Date, size: Int64)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              let size = (attrs[.size] as? NSNumber)?.int64Value else { return nil }
        return (modified, size)
    }

    private func cached(path: String, folderName: String,
                        modified: Date, size: Int64) -> SaveGameInfo? {
        parseCacheLock.lock()
        defer { parseCacheLock.unlock() }
        guard let hit = parseCache[path], hit.folderName == folderName,
              hit.modified == modified, hit.size == size else { return nil }
        return hit.info
    }

    private func remember(_ info: SaveGameInfo, path: String, folderName: String,
                          modified: Date, size: Int64) {
        parseCacheLock.lock()
        parseCache[path] = ParsedSave(modified: modified, size: size,
                                      folderName: folderName, info: info)
        parseCacheLock.unlock()
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
    
    func parseSaveFile(url: URL, folderName: String) -> SaveGameInfo? {
        let stamp = Self.stamp(of: url)
        if let stamp,
           let hit = cached(path: url.path, folderName: folderName,
                                 modified: stamp.modified, size: stamp.size) {
            return hit
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        // Une passe sur les enfants directs de `<player>` (`SavePlayerFields`) :
        // la première occurrence peut être un monstre de quête.
        let player = SavePlayerFields.directChildren(in: content)
        func playerInt(_ tag: String, default fallback: Int) -> Int {
            player[tag].flatMap(Int.init) ?? fallback
        }

        let playerName = player["name"] ?? "Unknown"
        let farmName = player["farmName"] ?? "Unknown"
        let favoriteThing = player["favoriteThing"] ?? "Unknown"
        let money = playerInt("money", default: 0)
        let spouse = extractSpouseFromPlayer(from: content) ?? ""

        // Date = champ du fermier (10/10 fichiers) ; repli hors du bloc.
        func dateInt(_ tag: String, default fallback: Int) -> Int {
            if let value = player[tag].flatMap(Int.init) { return value }
            return Int(extractTag(tag: tag, from: content) ?? "") ?? fallback
        }
        let year = dateInt("yearForSaveGame", default: 1)
        let season = dateInt("seasonForSaveGame", default: 0)
        let day = dateInt("dayOfMonthForSaveGame", default: 1)

        // Scalaires de `<SaveGame>` cherchés en fin de fichier (~90 ms au lieu de
        // ~980 ms sur 37 Mo) ; ancre `whichFarm`, sinon fichier entier.
        let saveScope = SaveGameFields.trailingScope(of: content, anchor: "whichFarm") ?? content
        // `<whichFarm>` peut être un identifiant de mod (`FrontierFarm`).
        let farmType = SaveFarmType.parse(rawWhichFarm: extractTag(tag: "whichFarm", from: saveScope))
        let whichFarm = farmType.whichFarm
        // Vrais tags : `<hair>` et `<hairstyleColor>` (pas `hairStyle`/
        // `hairColor`, inexistants — H-T5b).
        let hairStyle = playerInt("hair", default: 0)
        let hairColor = extractHairColor(from: content) ?? .default
        let skinIndex = playerInt("skin", default: 0)
        // `<whichModFarm>` absent du parc : l'id de `<whichFarm>` sert de nom ;
        // présent, il prime.
        let modFarmName = extractModFarmName(from: saveScope) ?? farmType.modFarmId
        // Textuel (Male/Female/Undefined). Tout sauf « Female » lit fermier.
        let isFemale = player["gender"] == "Female" || player["Gender"] == "Female"

        // Advanced. `goldenWalnuts` est à l'échelle de la ferme, hors `<player>`.
        let maxHealth = playerInt("maxHealth", default: 100)
        let maxStamina = playerInt("maxStamina", default: 270)
        let goldenWalnuts = Int(extractTag(tag: "goldenWalnuts", from: saveScope) ?? "0") ?? 0
        let qiGems = playerInt("qiGems", default: 0)
        let clubCoins = playerInt("clubCoins", default: 0)
        let totalMoneyEarned = playerInt("totalMoneyEarned", default: 0)

        let lastModified = stamp?.modified ?? Date()

        let parsed = SaveGameInfo(
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
            whichFarm: whichFarm,
            hairStyle: hairStyle,
            hairColor: hairColor,
            skinIndex: skinIndex,
            modFarmName: modFarmName,
            isFemale: isFemale
        )
        if let stamp {
            remember(parsed, path: url.path, folderName: folderName,
                          modified: stamp.modified, size: stamp.size)
        }
        return parsed
    }

    /// Bloc composé : `<R>`, `<G>`, `<B>` lus par nom (ordre XNA
    /// alphabétique). `nil` si incomplet : couleur par défaut.
    private func extractHairColor(from xml: String) -> SaveHairColor? {
        // Scopé à `<player>`.
        let scope = SavePlayerFields.playerBlock(in: xml).map(String.init) ?? xml
        guard let block = extractBlock(tag: "hairstyleColor", from: scope) else { return nil }
        guard let r = Int(extractTag(tag: "R", from: block) ?? ""),
              let g = Int(extractTag(tag: "G", from: block) ?? ""),
              let b = Int(extractTag(tag: "B", from: block) ?? "") else { return nil }
        return SaveHairColor(r: r, g: g, b: b)
    }

    /// Premier bloc `<tag>…</tag>` complet ; `<tag />` ne matche pas (voulu).
    private func extractBlock(tag: String, from xml: String) -> String? {
        let pattern = "<\(tag)>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, options: [], range: range),
              let swiftRange = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[swiftRange])
    }

    /// Deux formes : `<whichModFarm><name>X</name></whichModFarm>` (vanilla)
    /// ou `<whichModFarm>X</whichModFarm>`. `nil` si absent ou vide.
    private func extractModFarmName(from xml: String) -> String? {
        // ⚠️ Pas de pré-filtre `range(of:)` (37 Mo : regex 353 ms, `range(of:)`
        // 1 108 ms, `utf8.firstRange` 15,7 s).
        let pattern = "<whichModFarm>(?:\\s*<name>)?([^<]+)(?:</name>)?\\s*</whichModFarm>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, options: [], range: range),
              let swiftRange = Range(match.range(at: 1), in: xml) else { return nil }
        let value = String(xml[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    
    private func extractTag(tag: String, from xml: String) -> String? {
        // Find <tag>value</tag>: money, farmName… are unique or first.

        guard let regex = Self.cachedRegex(for: tag) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        if let match = regex.firstMatch(in: xml, options: [], range: range) {
            if let swiftRange = Range(match.range(at: 1), in: xml) {
                // Noms échappés (« D&amp;D ») décodés : vraie valeur, pas de double
                // encodage.
                return XMLEntities.unescape(String(xml[swiftRange]))
            }
        }
        return nil
    }
    
    /// Spouse from inside <player> only (NPCs have <spouse> too).
    private func extractSpouseFromPlayer(from xml: String) -> String? {
        // Find the <player> block
        guard let playerStart = xml.range(of: "<player>"),
              let playerEnd = xml.range(of: "</player>", range: playerStart.upperBound..<xml.endIndex) else {
            return extractTag(tag: "spouse", from: xml)  // fallback
        }
        let playerBlock = String(xml[playerStart.lowerBound..<playerEnd.upperBound])
        return extractTag(tag: "spouse", from: playerBlock)
    }
    
    /// Sets <spouse> in <player>, or removes it when empty.
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
            // Échapper le nom du conjoint (peut contenir des caractères XML).
            let escapedSpouse = XMLEntities.escape(newSpouse)
            let replacement = "<spouse>\(escapedSpouse)</spouse>"
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
                modified.insert(contentsOf: "<spouse>\(escapedSpouse)</spouse>", at: nameRange.upperBound)
                return modified
            }
        }
    }
    
    /// Marque UTF-8 (`EF BB BF`) : **Stardew en écrit une** (38/38 fichiers
    /// du jeu). Lecture et écriture Swift la perdent : on la rend comme on l'a
    /// prise.
    static let utf8BOM = Data([0xEF, 0xBB, 0xBF])

    /// Marque présente ? Lu par poignée (36 Mo), variantes non lançantes
    /// (cliquet `try?`).
    static func fileStartsWithBOM(at url: URL) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return false }
        defer { handle.closeFile() }
        return handle.readData(ofLength: 3) == utf8BOM
    }

    /// Contenu précédé de la marque si l'original la portait (règle pure).
    static func bytes(_ payload: Data, preservingBOM: Bool) -> Data {
        guard preservingBOM, !payload.starts(with: utf8BOM) else { return payload }
        return utf8BOM + payload
    }

    public func backupSave(info: SaveGameInfo) -> Bool { backupSaveURL(info: info) != nil }

    /// Dossier de backup créé, vérifiable avant écriture (A1-T10).
    public func backupSaveURL(info: SaveGameInfo) -> URL? {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        
        let folderPath = info.fileURL.deletingLastPathComponent()
        // Même seconde : suffixe plutôt qu'échec.
        var backupPath = folderPath.appendingPathExtension("backup_\(timestamp)")
        var n = 2
        while fm.fileExists(atPath: backupPath.path) {
            backupPath = folderPath.appendingPathExtension("backup_\(timestamp)-\(n)")
            n += 1
        }

        do {
            try fm.copyItem(at: folderPath, to: backupPath)
            print("Backup created at: \(backupPath.path)")
            return backupPath
        } catch {
            print("Failed to backup save: \(error)")
            return nil
        }
    }
    
    func updateSave(info: SaveGameInfo, newName: String, newFarm: String, newFav: String, newMoney: Int, newTotalMoneyEarned: Int, newMaxHealth: Int, newMaxStamina: Int, newGoldenWalnuts: Int, newQiGems: Int, newClubCoins: Int, newSpouse: String) -> Bool {
        // Invalidation en tête : un échec partiel a pu toucher le disque.
        invalidateParseCache()
        guard backupSave(info: info) else { return false }

        // Marque relevée **avant** la lecture, qui la consomme.
        let hadBOM = Self.fileStartsWithBOM(at: info.fileURL)
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
        
        // Old spouse: fix their friendship entry (home and schedule).
        if !oldSpouse.isEmpty && newSpouse != oldSpouse {
            content = cleanDivorceNPCFriendship(npcName: oldSpouse, in: content)
        }

        // Nouveau conjoint promu : sinon « marié » contre « Friendly » (audit
        // 2026-08-05).
        if !newSpouse.isEmpty && newSpouse != oldSpouse {
            content = promoteMarriageNPCFriendship(npcName: newSpouse, in: content)
        }
        
        do {
            guard let payload = content.data(using: .utf8) else { return false }
            try Self.bytes(payload, preservingBOM: hadBOM)
                .write(to: info.fileURL, options: .atomic)
            return true
        } catch {
            print("Failed to write updated save: \(error)")
            return false
        }
    }
    
    /// Demotes a former spouse: `Status` Married → Friendly, `WeddingDate`
    /// removed. Scoped to `<player>` (and `<friendshipData>`), so farmhands and
    /// unrelated `<string>Npc</string>` are untouched.
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

    /// Narrows to `<friendshipData>` when present.
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

    /// Edits the `<item>` keyed by `npcName`.
    private func cleanDivorceNPCFriendshipEntry(npcName: String, in xml: String) -> String {
        // <item><key><string>Npc</string></key><value><Friendship>…
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

        // 2. Remove the <WeddingDate> block.
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

    // MARK: Marriage — promotion du nouveau conjoint

    /// Index de saison du save = enum `Season` du jeu (mesuré) :
    /// Spring=0, Summer=1, Fall=2, Winter=3.
    private static let seasonsByIndex = ["spring", "summer", "fall", "winter"]

    /// Promotes the new spouse: `Status` → Married + `WeddingDate` at the
    /// current in-game date (`WorldDate`: `Year`, `DayOfMonth`, season
    /// **string** — measured on the 1.6.15 assemblies). No friendship entry:
    /// nothing invented.
    private func promoteMarriageNPCFriendship(npcName: String, in xml: String) -> String {
        // Date courante du fermier (mesuré : enfants directs de <player>).
        guard let year = extractTag(tag: "yearForSaveGame", from: xml), !year.isEmpty,
              let day = extractTag(tag: "dayOfMonthForSaveGame", from: xml), !day.isEmpty,
              let seasonRaw = extractTag(tag: "seasonForSaveGame", from: xml),
              let seasonIndex = Int(seasonRaw),
              Self.seasonsByIndex.indices.contains(seasonIndex) else {
            print("[Marriage] Could not read the current in-game date — new spouse not promoted")
            return xml
        }
        let weddingDate = "<WeddingDate><Year>\(year)</Year>"
                        + "<DayOfMonth>\(day)</DayOfMonth>"
                        + "<Season>\(Self.seasonsByIndex[seasonIndex])</Season></WeddingDate>"

        guard let playerStartRange = xml.range(of: "<player>"),
              let playerEndRange = xml.range(of: "</player>", range: playerStartRange.upperBound..<xml.endIndex) else {
            print("[Marriage] Could not find <player> block")
            return xml
        }

        let beforePlayer = String(xml[..<playerStartRange.lowerBound])
        let playerBlock  = String(xml[playerStartRange.lowerBound..<playerEndRange.upperBound])
        let afterPlayer  = String(xml[playerEndRange.upperBound...])

        let updatedPlayerBlock = promoteNPCFriendshipInScope(npcName: npcName, in: playerBlock, weddingDate: weddingDate)
        return beforePlayer + updatedPlayerBlock + afterPlayer
    }

    /// Même resserrement que la démotion.
    private func promoteNPCFriendshipInScope(npcName: String, in xml: String, weddingDate: String) -> String {
        guard let fdStartRange = xml.range(of: "<friendshipData>"),
              let fdEndRange = xml.range(of: "</friendshipData>", range: fdStartRange.upperBound..<xml.endIndex) else {
            return promoteNPCFriendshipEntry(npcName: npcName, in: xml, weddingDate: weddingDate)
        }

        let before = String(xml[..<fdStartRange.lowerBound])
        let fdBlock  = String(xml[fdStartRange.lowerBound..<fdEndRange.upperBound])
        let after  = String(xml[fdEndRange.upperBound...])

        return before + promoteNPCFriendshipEntry(npcName: npcName, in: fdBlock, weddingDate: weddingDate) + after
    }

    /// Motifs constants, `try!` (idiome du dépôt).
    private static let statusTagRegex = try! NSRegularExpression(pattern: "<Status>[^<]*</Status>")
    private static let weddingDateTagRegex = try! NSRegularExpression(
        pattern: "<WeddingDate>.*?</WeddingDate>", options: .dotMatchesLineSeparators)

    /// Edits the `<item>` keyed by `npcName`: Married + WeddingDate.
    private func promoteNPCFriendshipEntry(npcName: String, in xml: String, weddingDate: String) -> String {
        let keyMarker = "<string>\(npcName)</string>"
        guard let keyRange = xml.range(of: keyMarker) else {
            print("[Marriage] Could not find friendship entry for \(npcName)")
            return xml
        }

        let beforeKey = String(xml[..<keyRange.lowerBound])
        guard let itemStart = beforeKey.range(of: "<item>", options: .backwards) else {
            print("[Marriage] Could not find <item> before key for \(npcName)")
            return xml
        }
        guard let itemEnd = xml.range(of: "</item>", range: keyRange.upperBound..<xml.endIndex) else {
            print("[Marriage] Could not find </item> after key for \(npcName)")
            return xml
        }

        let beforeItem = String(xml[..<itemStart.lowerBound])
        var itemBlock  = String(xml[itemStart.lowerBound..<itemEnd.upperBound])
        let afterItem  = String(xml[itemEnd.upperBound...])

        // Statut → Married ; ancienne WeddingDate retirée, la neuve insérée
        // après le statut.
        let nsBlock = itemBlock as NSString
        let fullRange = NSRange(location: 0, length: nsBlock.length)
        itemBlock = Self.statusTagRegex.stringByReplacingMatches(
            in: itemBlock, options: [], range: fullRange,
            withTemplate: "<Status>Married</Status>")
        itemBlock = Self.weddingDateTagRegex.stringByReplacingMatches(
            in: itemBlock, options: [], range: fullRange,
            withTemplate: "")
        if let statusRange = itemBlock.range(of: "<Status>Married</Status>") {
            itemBlock.insert(contentsOf: weddingDate, at: statusRange.upperBound)
        } else {
            print("[Marriage] Could not find <Status> in the friendship entry for \(npcName)")
        }

        return beforeItem + itemBlock + afterItem
    }


    /// Like replaceFirstTag, scoped to <player> (not an NPC's or farmhand's
    /// tag). Falls back to the whole file when absent from <player>
    /// (goldenWalnuts is farm-wide).
    private func replaceFirstTagInPlayer(tag: String, with value: String, in xml: String) -> String {
        guard let playerStartRange = xml.range(of: "<player>"),
              let playerEndRange = xml.range(of: "</player>", range: playerStartRange.upperBound..<xml.endIndex) else {
            return replaceFirstTag(tag: tag, with: value, in: xml)
        }

        let beforePlayer = String(xml[..<playerStartRange.lowerBound])
        let playerBlock  = String(xml[playerStartRange.lowerBound..<playerEndRange.upperBound])
        let afterPlayer  = String(xml[playerEndRange.upperBound...])

        // Enfant **direct** de `<player>` : `<maxHealth>` la première vaut 24
        // (un monstre), pas 150.
        if let updated = SavePlayerFields.replacingDirectChild(tag, with: value, in: xml) {
            return updated
        }

        guard playerBlock.contains("<\(tag)>") else {
            return replaceFirstTag(tag: tag, with: value, in: xml)
        }

        let updatedPlayer = replaceFirstTag(tag: tag, with: value, in: playerBlock)
        return beforePlayer + updatedPlayer + afterPlayer
    }

    private func replaceFirstTag(tag: String, with value: String, in xml: String) -> String {
        // `*`, pas `+` : une balise vide est une valeur (sinon « réussi » sans
        // écrire).
        let pattern = "(<\(tag)>)([^<]*)(</\(tag)>)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return xml }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        
        // We only want to replace the first occurrence (player data is always at the top)
        if let match = regex.firstMatch(in: xml, options: [], range: range) {

            // Mutating replacement on the matched range.
            if let swiftRange = Range(match.range, in: xml) {
                var modified = xml
                // Valeur échappée ici pour tous les appelants (« D&D » cassait le XML) ;
                // symétrique d'`extractTag`.
                modified.replaceSubrange(swiftRange, with: "<\(tag)>\(XMLEntities.escape(value))</\(tag)>")
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
        // Invalidation en tête : un échec partiel a pu toucher le disque.
        invalidateParseCache()
        let folderPath = info.fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.trashItem(at: folderPath, resultingItemURL: nil)
            return true
        } catch {
            print("Failed to trash save: \(error)")
            return false
        }
    }
    
    private func modifyInternalSaveNames(in folderURL: URL, newSaveName: String, newPlayerName: String, newFarmName: String) throws {
        let fm = FileManager.default
        let saveGameInfoURL = folderURL.appendingPathComponent("SaveGameInfo")
        let mainSaveURL = folderURL.appendingPathComponent(newSaveName)

        func updateFile(at url: URL) throws {
            // Lecture tolérante, écriture propagée (sinon clone sous l'ancien nom
            // interne, invisible pour Stardew). Marque d'octets relevée et rendue.
            let hadBOM = Self.fileStartsWithBOM(at: url)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
            var modified = replaceFirstTag(tag: "name", with: newPlayerName, in: content)
            modified = replaceFirstTag(tag: "farmName", with: newFarmName, in: modified)
            guard let payload = modified.data(using: .utf8) else { return }
            try Self.bytes(payload, preservingBOM: hadBOM).write(to: url, options: .atomic)
        }

        if fm.fileExists(atPath: saveGameInfoURL.path) {
            try updateFile(at: saveGameInfoURL)
        }
        if fm.fileExists(atPath: mainSaveURL.path) {
            try updateFile(at: mainSaveURL)
        }
    }

    /// Copies a save or backup folder into "<baseName>_<suffix>" (+ "_2"…),
    /// renames the inner file and patches the name fields (duplicateSave,
    /// branchFromBackup).
    private func cloneSaveFolder(sourceFolder: URL, baseName: String, suffix: String, newPlayerName: String, newFarmName: String, context: String) -> Bool {
        // Invalidation ici, pas chez un seul des deux appelants.
        invalidateParseCache()
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
            try modifyInternalSaveNames(in: newFolderPath, newSaveName: newSaveName, newPlayerName: newPlayerName, newFarmName: newFarmName)

            return true
        } catch {
            // Clone partiel retiré plutôt qu'une réussite sur un dossier cassé.
            try? fm.removeItem(at: newFolderPath)
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
        // Nom d'origine complet (« Farm.1 ») : l'ancien `split(".")` coupait au
        // point et Stardew ignorait la branche.
        let originalSaveName = backup.saveFolder
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
        // Invalidation en tête : un échec partiel a pu toucher le disque.
        invalidateParseCache()
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

        // Leftover `tempTrash` from a failed attempt would block `moveItem`:
        // clear it (already superseded).
        if fm.fileExists(atPath: tempTrash.path) {
            try? fm.removeItem(at: tempTrash)
        }

        // Live folder moved aside? A later failure moves it back.
        var liveFolderMovedAside = false
        // Only failures before the copy roll back.
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

            // Trash the temp; non-fatal (cleaned next time).
            try? fm.trashItem(at: tempTrash, resultingItemURL: nil)

            return true
        } catch {
            print("Failed to restore backup: \(error)")
            if liveFolderMovedAside && !restoreCompleted {
                // Put the live save back; clear a partial folder first.
                if fm.fileExists(atPath: saveFolder.path) {
                    try? fm.removeItem(at: saveFolder)
                }
                do {
                    try fm.moveItem(at: tempTrash, to: saveFolder)
                } catch {
                    // Ne pas avaler : la save vivante est dans `tempTrash`, signaler le
                    // chemin (sinon perte invisible).
                    print("CRITICAL: restore rollback failed — live save still in \(tempTrash.path) (could not move to \(saveFolder.path): \(error))")
                }
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
        // Invalidation en tête : un échec partiel a pu toucher le disque.
        invalidateParseCache()
        // Backup first
        guard backupSave(info: info) else { return false }
        
        let hadBOM = Self.fileStartsWithBOM(at: info.fileURL)
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
            try Self.bytes(updatedXMLData, preservingBOM: hadBOM)
                .write(to: info.fileURL, options: .atomic)
            return true
        } catch {
            print("Failed to save updated inventory XML: \(error)")
            return false
        }
    }
}
