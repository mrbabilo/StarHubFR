import Foundation

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
    /// Santé et endurance du moment, `nil` si la partie ne les porte pas (B6-T3).
    public var health: Int? = nil
    public var stamina: Int? = nil
    /// Les six compétences (`SaveSkills.levelTags`), vide si illisibles.
    public var skills: [SaveSkill] = []

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
        isFemale: Bool = false,
        health: Int? = nil,
        stamina: Int? = nil,
        skills: [SaveSkill] = []
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
        self.health = health
        self.stamina = stamina
        self.skills = skills
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
