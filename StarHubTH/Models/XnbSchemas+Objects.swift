import Foundation

/// Schémas de `Data/Objects` et `Data/BigCraftables` (jeu 1.6), relevés
/// sur `StardewValley.GameData.dll` : membres dans l'ordre du
/// `ReflectiveReader` (base d'abord, propriétés puis champs). Les membres
/// `Optional` sont écrits quand même ; les champs privés (`IdImpl`) non.
extension XnbSchema {
    /// `Data/Objects` : `Dictionary<string, ObjectData>`.
    public static let objects = XnbSchema.dictionary(key: .string, value: objectData)

    /// `Data/BigCraftables` : `Dictionary<string, BigCraftableData>`.
    public static let bigCraftables = XnbSchema.dictionary(key: .string, value: bigCraftableData)

    static let stringMap = XnbSchema.dictionary(key: .string, value: .string)

    static let objectData = XnbSchema.object(name: "StardewValley.GameData.Objects.ObjectData", members: [
        ("Name", .string),
        ("DisplayName", .string),
        ("Description", .string),
        ("Type", .string),
        ("Category", .int),
        ("Price", .int),
        ("Texture", .string),
        ("SpriteIndex", .int),
        ("ColorOverlayFromNextIndex", .bool),
        ("Edibility", .int),
        ("IsDrink", .bool),
        ("Buffs", .list(objectBuffData)),
        ("GeodeDropsDefaultItems", .bool),
        ("GeodeDrops", .list(objectGeodeDropData)),
        ("ArtifactSpotChances", .dictionary(key: .string, value: .float)),
        ("CanBeGivenAsGift", .bool),
        ("CanBeTrashed", .bool),
        ("ExcludeFromFishingCollection", .bool),
        ("ExcludeFromShippingCollection", .bool),
        ("ExcludeFromRandomSale", .bool),
        ("ContextTags", .list(.string)),
        ("CustomFields", stringMap),
    ])

    static let objectBuffData = XnbSchema.object(name: "StardewValley.GameData.Objects.ObjectBuffData", members: [
        ("Id", .string),
        ("BuffId", .string),
        ("IconTexture", .string),
        ("IconSpriteIndex", .int),
        ("Duration", .int),
        ("IsDebuff", .bool),
        ("GlowColor", .string),
        ("CustomAttributes", buffAttributesData),
        ("CustomFields", stringMap),
    ])

    /// 18 `float`, dans l'ordre de la classe.
    static let buffAttributesData = XnbSchema.object(
        name: "StardewValley.GameData.Buffs.BuffAttributesData",
        members: [
            "CombatLevel", "FarmingLevel", "FishingLevel", "MiningLevel", "LuckLevel",
            "ForagingLevel", "MaxStamina", "MagneticRadius", "Speed", "Defense", "Attack",
            "AttackMultiplier", "Immunity", "KnockbackMultiplier", "WeaponSpeedMultiplier",
            "CriticalChanceMultiplier", "CriticalPowerMultiplier", "WeaponPrecisionMultiplier",
        ].map { ($0, XnbSchema.float) })

    /// `ObjectGeodeDropData` : `GenericSpawnItemData`, puis
    /// `GenericSpawnItemDataWithCondition`, puis ses propres membres.
    static let objectGeodeDropData = XnbSchema.object(
        name: "StardewValley.GameData.Objects.ObjectGeodeDropData",
        members: genericSpawnItemDataMembers + [
            ("Condition", .string),
            ("Chance", .double),
            ("SetFlagOnPickup", .string),
            ("Precedence", .int),
        ])

    static let genericSpawnItemDataMembers: [(String, XnbSchema)] = [
        ("Id", .string),
        ("ItemId", .string),
        ("RandomItemId", .list(.string)),
        ("MaxItems", .nullable(.int)),
        ("MinStack", .int),
        ("MaxStack", .int),
        ("Quality", .int),
        ("ObjectInternalName", .string),
        ("ObjectDisplayName", .string),
        ("ObjectColor", .string),
        ("ToolUpgradeLevel", .int),
        ("IsRecipe", .bool),
        ("StackModifiers", .list(quantityModifier)),
        ("StackModifierMode", .enumInt),
        ("QualityModifiers", .list(quantityModifier)),
        ("QualityModifierMode", .enumInt),
        ("ModData", stringMap),
        ("PerItemCondition", .string),
    ]

    static let quantityModifier = XnbSchema.object(name: "StardewValley.GameData.QuantityModifier", members: [
        ("Id", .string),
        ("Condition", .string),
        ("Modification", .enumInt),
        ("Amount", .float),
        ("RandomAmount", .list(.float)),
    ])

    static let bigCraftableData = XnbSchema.object(
        name: "StardewValley.GameData.BigCraftables.BigCraftableData",
        members: [
            ("Name", .string),
            ("DisplayName", .string),
            ("Description", .string),
            ("Price", .int),
            ("Fragility", .int),
            ("CanBePlacedOutdoors", .bool),
            ("CanBePlacedIndoors", .bool),
            ("IsLamp", .bool),
            ("Texture", .string),
            ("SpriteIndex", .int),
            ("ContextTags", .list(.string)),
            ("CustomFields", stringMap),
        ])
}
