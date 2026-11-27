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
    private let key = UDKey.saveNotes // Upgraded version key to prevent conflicts

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
        self.savesDir = FolderStamps.savesDirectory
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
        guard let content = PureBinarySave.readableText(of: url) else { return nil }

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
    
    /// Écrit la fiche du fermier en une passe sur l'arbre de la partie
    /// (B6-T1) : refus X138, partie modifiée pendant l'opération, backup raté.
    func updateSave(info: SaveGameInfo, newName: String, newFarm: String, newFav: String, newMoney: Int, newTotalMoneyEarned: Int, newMaxHealth: Int, newMaxStamina: Int, newGoldenWalnuts: Int, newQiGems: Int, newClubCoins: Int, newSpouse: String) -> Bool {
        // Invalidation en tête : un échec partiel a pu toucher le disque.
        invalidateParseCache()
        guard let save = try? SaveDocument(contentsOf: info.fileURL) else { return false }
        // Champs du fermier, recopiés aussi dans `SaveGameInfo` après l'écriture (X158).
        let farmerFields = [("name", newName), ("farmName", newFarm), ("favoriteThing", newFav), ("money", "\(newMoney)"),
                            ("totalMoneyEarned", "\(newTotalMoneyEarned)"), ("maxHealth", "\(newMaxHealth)"),
                            ("maxStamina", "\(newMaxStamina)"), ("qiGems", "\(newQiGems)"), ("clubCoins", "\(newClubCoins)")]
        for (tag, value) in farmerFields { save.setFarmerField(tag, to: value) }
        save.setFarmerField("goldenWalnuts", to: "\(newGoldenWalnuts)")  // hors `<player>`
        let oldSpouse = info.spouse
        save.setSpouse(newSpouse)
        if !oldSpouse.isEmpty && newSpouse != oldSpouse { save.demoteSpouse(oldSpouse) }
        // Nouveau conjoint promu : sinon « marié » contre « Friendly » (audit 2026-08-05).
        if !newSpouse.isEmpty && newSpouse != oldSpouse { save.promoteSpouse(newSpouse) }
        do {
            try save.write(backup: { backupSave(info: info) })
        } catch {
            print("Save not written: \(error)")
            return false
        }
        syncSaveGameInfo(in: info.fileURL.deletingLastPathComponent(), fields: farmerFields)
        return true
    }
    
    /// X158 — l'écran de chargement lit `SaveGameInfo` (racine `<Farmer>`). Champ absent laissé tel quel ; échec non
    /// bloquant : la partie est écrite, et le jeu réécrit ce fichier à sa prochaine sauvegarde.
    private func syncSaveGameInfo(in folder: URL, fields: [(String, String)]) {
        let url = folder.appendingPathComponent("SaveGameInfo")
        let hadBOM = Self.fileStartsWithBOM(at: url)
        do {  // fichier absent ou illisible : rien à recopier
            var content = try String(contentsOf: url, encoding: .utf8)
            for (tag, value) in fields { content = SavePlayerFields.replacingRootChild(tag, with: value, in: content) ?? content }
            try PureBinarySave.write(Self.bytes(Data(content.utf8), preservingBOM: hadBOM), to: url)
        } catch { return }
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
            try PureBinarySave.write(Self.bytes(payload, preservingBOM: hadBOM), to: url)
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
    /// Rend le nom du dossier créé (celui que le jeu charge), ou nil en échec.
    private func cloneSaveFolder(sourceFolder: URL, baseName: String, suffix: String, newPlayerName: String, newFarmName: String, context: String) -> String? {
        invalidateParseCache()  // ici, pas chez un seul des deux appelants
        guard PureBinarySave.allowsEditing(sourceFolder.appendingPathComponent(baseName)) else { return nil }  // X138
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

            PureBinarySave.dropBinaries(named: baseName, in: newFolderPath)  // X138, avant le renommage
            let oldFilePath = newFolderPath.appendingPathComponent(baseName)
            let newFilePath = newFolderPath.appendingPathComponent(newSaveName)
            if fm.fileExists(atPath: oldFilePath.path) {
                try fm.moveItem(at: oldFilePath, to: newFilePath)
            }

            // Modify name and farm name inside XML files
            try modifyInternalSaveNames(in: newFolderPath, newSaveName: newSaveName, newPlayerName: newPlayerName, newFarmName: newFarmName)

            return newSaveName
        } catch {
            // Clone partiel retiré plutôt qu'une réussite sur un dossier cassé.
            try? fm.removeItem(at: newFolderPath)
            print("Failed to \(context): \(error)")
            return nil
        }
    }

    public func duplicateSave(info: SaveGameInfo, newName: String, newFarm: String) -> Bool {
        let folderPath = info.fileURL.deletingLastPathComponent()
        let saveName = folderPath.lastPathComponent
        return cloneSaveFolder(sourceFolder: folderPath, baseName: saveName, suffix: "copy", newPlayerName: newName, newFarmName: newFarm, context: "duplicate save") != nil
    }

    /// Benchmark automatique : le jeu ne charge qu'une copie, jamais l'original.
    /// Rend le nom du dossier copié (celui que `SaveGame.Load` attend).
    public func cloneForBenchmark(info: SaveGameInfo) -> String? {
        let folderPath = info.fileURL.deletingLastPathComponent()
        return cloneSaveFolder(sourceFolder: folderPath, baseName: folderPath.lastPathComponent,
                               suffix: "bench", newPlayerName: info.playerName,
                               newFarmName: info.farmName, context: "benchmark copy")
    }

    // MARK: - Backup Timeline

    public func branchFromBackup(backup: SaveBackup, newName: String, newFarm: String) -> Bool {
        let backupFolderPath = backup.folderPath
        // Nom d'origine complet (« Farm.1 ») : l'ancien `split(".")` coupait au
        // point et Stardew ignorait la branche.
        let originalSaveName = backup.saveFolder
        return cloneSaveFolder(sourceFolder: backupFolderPath, baseName: originalSaveName, suffix: "branch", newPlayerName: newName, newFarmName: newFarm, context: "branch backup") != nil
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
    
    /// Empreinte de la dernière lecture de l'inventaire, par partie : l'écriture
    /// refuse un fichier qui a changé depuis que l'écran l'a montré (B6-T1,
    /// B5-T1). Verrou dédié : lecture et écriture tournent hors main.
    private var inventoryStamps: [URL: SaveDocument.Stamp] = [:]
    private let inventoryStampsLock = NSLock()

    private func inventoryStamp(for url: URL) -> SaveDocument.Stamp? {
        inventoryStampsLock.lock()
        defer { inventoryStampsLock.unlock() }
        return inventoryStamps[url]
    }

    private func rememberInventoryStamp(_ stamp: SaveDocument.Stamp, for url: URL) {
        inventoryStampsLock.lock()
        inventoryStamps[url] = stamp
        inventoryStampsLock.unlock()
    }

    func fetchInventory(for info: SaveGameInfo) -> [InventoryItem]? {
        // Même lecture que l'écriture (`.nodePreserveAll`) : l'arbre montré est
        // celui qui sera écrit, et son empreinte garde l'écriture.
        guard let save = try? SaveDocument(contentsOf: info.fileURL), let items = save.inventory() else { return nil }
        rememberInventoryStamp(save.stamp, for: info.fileURL)
        return items
    }

    /// Écrit le sac. Refusé — rien d'écrit — si la partie a changé depuis la
    /// dernière lecture de l'inventaire (`fetchInventory`), si le `.bin` porte
    /// la seule copie complète (X138) ou si le backup échoue.
    func updateInventory(info: SaveGameInfo, items: [InventoryItem]) -> Bool {
        // Invalidation en tête : un échec partiel a pu toucher le disque.
        invalidateParseCache()
        guard let save = try? SaveDocument(contentsOf: info.fileURL), save.applyInventory(items) else { return false }
        do {
            try save.write(expected: inventoryStamp(for: info.fileURL), backup: { backupSave(info: info) })
            if let written = SaveDocument.Stamp.current(of: info.fileURL) {
                rememberInventoryStamp(written, for: info.fileURL)
            }
            return true
        } catch {
            print("Inventory not written: \(error)")
            return false
        }
    }
}
