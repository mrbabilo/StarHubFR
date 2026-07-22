import SwiftUI

/// A Stardew Valley Nexus Mods category.
///
/// Stardew Valley has 26 published mod categories (plus a root category id `1`
/// that is never assigned to a mod). The mapping below was reverse-engineered
/// from `https://www.nexusmods.com/stardewvalley/mods/categories` because the
/// Nexus public API's `/categories.json` endpoint is deprecated (404). Each mod
/// endpoint returns its `category_id`, which we resolve against this table.
///
/// Colors are curated per category so that adjacent ids stay visually distinct,
/// making the mods list scannable at a glance even when sorted alphabetically.
struct NexusCategory: Identifiable, Hashable {
    let id: Int
    /// L10n key (e.g. `"category_3"`). Falls back to `englishName` if missing.
    let l10nKey: String
    let englishName: String
    let color: Color
    /// Unicode glyph shown in the category picker (SwiftUI Menus render
    /// labels as plain text, so this carries the visual identity a `Label`
    /// icon normally would). Kept as a field here — rather than a separate
    /// id→emoji table elsewhere — so it can never drift out of sync with
    /// `all`.
    let emoji: String

    /// All 26 Stardew Valley categories, ordered by Nexus category id.
    static let all: [NexusCategory] = [
        .init(id: 2,  l10nKey: "category_2",  englishName: "Miscellaneous",         color: Color(red: 0.50, green: 0.52, blue: 0.55), emoji: "🗂"),
        .init(id: 3,  l10nKey: "category_3",  englishName: "Gameplay Mechanics",    color: Color(red: 0.80, green: 0.30, blue: 0.30), emoji: "🎮"),
        .init(id: 4,  l10nKey: "category_4",  englishName: "Player",                color: Color(red: 0.90, green: 0.55, blue: 0.25), emoji: "🧑‍🌾"),
        .init(id: 5,  l10nKey: "category_5",  englishName: "Characters",           color: Color(red: 0.85, green: 0.45, blue: 0.65), emoji: "👥"),
        .init(id: 6,  l10nKey: "category_6",  englishName: "Portraits",            color: Color(red: 0.80, green: 0.35, blue: 0.55), emoji: "🖼"),
        .init(id: 7,  l10nKey: "category_7",  englishName: "Livestock and Animals",color: Color(red: 0.55, green: 0.35, blue: 0.20), emoji: "🐾"),
        .init(id: 8,  l10nKey: "category_8",  englishName: "Pets / Horses",        color: Color(red: 0.70, green: 0.55, blue: 0.35), emoji: "🐾"),
        .init(id: 9,  l10nKey: "category_9",  englishName: "Modding Tools",        color: Color(red: 0.25, green: 0.45, blue: 0.80), emoji: "🛠"),
        .init(id: 10, l10nKey: "category_10", englishName: "User Interface",       color: Color(red: 0.35, green: 0.30, blue: 0.70), emoji: "🖥"),
        .init(id: 11, l10nKey: "category_11", englishName: "Cheats",               color: Color(red: 0.55, green: 0.30, blue: 0.65), emoji: "🎲"),
        .init(id: 12, l10nKey: "category_12", englishName: "Audio",                color: Color(red: 0.30, green: 0.60, blue: 0.60), emoji: "🔊"),
        .init(id: 13, l10nKey: "category_13", englishName: "Clothing",             color: Color(red: 0.75, green: 0.35, blue: 0.60), emoji: "👕"),
        .init(id: 14, l10nKey: "category_14", englishName: "Crops",                color: Color(red: 0.40, green: 0.65, blue: 0.35), emoji: "🌱"),
        .init(id: 15, l10nKey: "category_15", englishName: "Items",                color: Color(red: 0.80, green: 0.65, blue: 0.25), emoji: "📦"),
        .init(id: 16, l10nKey: "category_16", englishName: "Locations",            color: Color(red: 0.40, green: 0.60, blue: 0.55), emoji: "📍"),
        .init(id: 17, l10nKey: "category_17", englishName: "Buildings",            color: Color(red: 0.55, green: 0.50, blue: 0.45), emoji: "🏠"),
        .init(id: 18, l10nKey: "category_18", englishName: "Events",               color: Color(red: 0.30, green: 0.65, blue: 0.75), emoji: "🎉"),
        .init(id: 19, l10nKey: "category_19", englishName: "Interiors",            color: Color(red: 0.55, green: 0.60, blue: 0.40), emoji: "🛋"),
        .init(id: 20, l10nKey: "category_20", englishName: "Dialogue",             color: Color(red: 0.65, green: 0.55, blue: 0.75), emoji: "💬"),
        .init(id: 21, l10nKey: "category_21", englishName: "Maps",                 color: Color(red: 0.30, green: 0.60, blue: 0.45), emoji: "🗺"),
        .init(id: 22, l10nKey: "category_22", englishName: "Crafting",             color: Color(red: 0.80, green: 0.60, blue: 0.30), emoji: "🔨"),
        .init(id: 23, l10nKey: "category_23", englishName: "Furniture",            color: Color(red: 0.60, green: 0.40, blue: 0.30), emoji: "🪑"),
        .init(id: 24, l10nKey: "category_24", englishName: "New Characters",       color: Color(red: 0.90, green: 0.55, blue: 0.55), emoji: "👥"),
        .init(id: 25, l10nKey: "category_25", englishName: "Visuals and Graphics", color: Color(red: 0.40, green: 0.55, blue: 0.80), emoji: "🎨"),
        .init(id: 26, l10nKey: "category_26", englishName: "Fishing",              color: Color(red: 0.35, green: 0.65, blue: 0.65), emoji: "🎣"),
        .init(id: 27, l10nKey: "category_27", englishName: "Expansions",           color: Color(red: 0.50, green: 0.35, blue: 0.70), emoji: "✨"),
    ]

    /// O(1) lookup by Nexus category id.
    private static let byId: [Int: NexusCategory] = {
        var map: [Int: NexusCategory] = [:]
        for c in all { map[c.id] = c }
        return map
    }()

    /// Returns the category for a given Nexus id, or `nil` for unknown ids
    /// (e.g. id `1` root, or freshly introduced categories not yet mapped).
    static func from(id: Int) -> NexusCategory? { byId[id] }

    /// Localized display name. Falls back to the English name when the key is
    /// missing from the current bundle (defensive — should never happen since
    /// build_app.py regenerates `.strings` from the JSON source of truth).
    func localizedName(_ L: (String) -> String) -> String {
        let resolved = L(l10nKey)
        // The lookup helper returns the key itself on miss.
        return resolved == l10nKey ? englishName : resolved
    }
}
