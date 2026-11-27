import Foundation
import Testing
@testable import StarHubTHCore

/// Le catalogue des objets du jeu (B4) : noms traduits, repli sur le fichier
/// de base puis sur `Name`, table des gros objets à part. Dictionnaires
/// fabriqués en mémoire — aucune donnée du jeu dans le dépôt ; le jeu réel
/// seulement derrière `STARDEW_CONTENT_DIR`.
struct GameCatalogTests {
    static func object(_ name: String, _ displayName: String, category: Int32 = -75,
                       texture: XnbValue = .null, sprite: Int32 = 0) -> XnbValue {
        .object(["Name": .string(name), "DisplayName": .string(displayName), "Category": .int(category),
                 "Texture": texture, "SpriteIndex": .int(sprite)])
    }

    static func table(_ entries: [(String, XnbValue)]) -> XnbValue {
        .dictionary(entries.map { XnbPair(key: .string($0.0), value: $0.1) })
    }

    static let objects = table([
        ("24", object("Parsnip", "[LocalizedText Strings\\Objects:Parsnip_Name]", sprite: 24)),
        ("130", object("Tuna", "[LocalizedText Strings\\Objects:Tuna_Name]", category: -4, sprite: 130)),
        ("388", object("Wood", "[LocalizedText Strings\\Objects:Wood_Name]", category: -16, sprite: 388)),
        ("Mod.Thing", object("Mod Thing", "Plain Name", texture: .string("Mods/Thing"))),
    ])
    static let bigCraftables = table([
        ("130", .object(["Name": .string("Chest"), "DisplayName": .string("[LocalizedText Strings\\BigCraftables:Chest_Name]"),
                         "Texture": .null, "SpriteIndex": .int(130)])),
    ])
    static let strings: [String: [String: String]] = [
        "Strings/Objects.fr-FR": ["Parsnip_Name": "Panais", "Tuna_Name": "Thon"],
        "Strings/Objects": ["Parsnip_Name": "Parsnip", "Tuna_Name": "Tuna", "Wood_Name": "Wood"],
        "Strings/BigCraftables.fr-FR": ["Chest_Name": "Coffre"],
    ]

    static func catalog(_ language: String = "fr") -> GameCatalog {
        GameCatalog.build(objects: objects, bigCraftables: bigCraftables, language: language) { strings[$0] }
    }

    static func item(_ id: String, object: Bool = true, bigCraftable: Bool = false) -> InventoryItem {
        InventoryItem(slotIndex: 0, itemId: id, name: "internal", stack: 1,
                      isObject: object, isBigCraftable: bigCraftable)
    }

    @Test func localizedTextIsResolvedInTheGameLanguage() {
        let entry = Self.catalog().entry(for: Self.item("24"))
        #expect(entry?.displayName == "Panais")
        #expect(entry?.id == "24")
        #expect(entry?.spriteIndex == 24)
        #expect(entry?.category == -75)
        #expect(entry?.texture == nil)
        #expect(Self.catalog("en").entry(for: Self.item("24"))?.displayName == "Parsnip")
    }

    @Test func aMissingTranslationFallsBackToTheBaseFile() {
        let catalog = Self.catalog()
        #expect(catalog.entry(for: Self.item("388"))?.displayName == "Wood")
        // Clé absente partout : le nom interne de l'objet.
        let noStrings = GameCatalog.build(objects: Self.objects, bigCraftables: Self.bigCraftables,
                                          language: "fr") { _ in nil }
        #expect(noStrings.entry(for: Self.item("24"))?.displayName == "Parsnip")
        // Nom littéral (objet de mod) : gardé tel quel.
        let modEntry = catalog.entry(for: Self.item("Mod.Thing"))
        #expect(modEntry?.displayName == "Plain Name")
        #expect(modEntry?.texture == "Mods/Thing")
    }

    @Test func aBigCraftableIsNotLookedUpAsAnObject() {
        let catalog = Self.catalog()
        #expect(catalog.entry(for: Self.item("130", bigCraftable: true))?.displayName == "Coffre")
        // Un coffre rangé n'est pas un `Object` dans la partie, mais reste un gros objet.
        #expect(catalog.entry(for: Self.item("130", object: false, bigCraftable: true))?.displayName == "Coffre")
        #expect(catalog.entry(for: Self.item("130"))?.displayName == "Thon")
        #expect(catalog.entry(for: Self.item("(O)130"))?.displayName == "Thon")
        #expect(catalog.entry(for: Self.item("(BC)130", bigCraftable: true))?.displayName == "Coffre")
    }

    @Test func weaponsAreNotLookedUp() {
        // Une arme d'identifiant `24` n'est pas le Panais.
        #expect(Self.catalog().entry(for: Self.item("24", object: false)) == nil)
        #expect(Self.catalog().entry(for: Self.item("unknown")) == nil)
    }

    @Test func languageCodeFrMapsToFrFR() {
        #expect(GameCatalog.fileSuffix(languageCode: "fr") == "fr-FR")
        #expect(GameCatalog.fileSuffix(languageCode: "de") == "de-DE")
        #expect(GameCatalog.fileSuffix(languageCode: "en") == nil)
        #expect(GameCatalog.fileSuffix(languageCode: "mod") == nil)
        let prefs = Data("<StartupPreferences><languageCode>fr</languageCode></StartupPreferences>".utf8)
        #expect(GameCatalog.gameLanguage(startupPreferences: prefs, appLanguage: "en") == "fr")
        #expect(GameCatalog.gameLanguage(startupPreferences: nil, appLanguage: "fr") == "fr")
        #expect(GameCatalog.gameLanguage(startupPreferences: Data("<x/>".utf8), appLanguage: "en") == "en")
    }

    @Test func aMissingGameIsNamed() {
        let nowhere = URL(fileURLWithPath: "/nonexistent/Content")
        guard case .failure(let problem) = GameCatalog.load(gameContent: nowhere, language: "fr") else {
            Issue.record("catalogue chargé sans jeu")
            return
        }
        #expect(problem == .gameNotFound)
        #expect(GameCatalog.contentFolder(gameDir: "") == nil)
        #expect(GameCatalog.contentFolder(gameDir: "/nonexistent/Stardew Valley.app/Contents/MacOS") == nil)
    }

    @Test(.enabled(if: XnbGameDataTests.content != nil, "STARDEW_CONTENT_DIR absent — dossier Content du jeu"))
    func theInstalledGameNamesItsItemsInFrench() throws {
        guard let content = XnbGameDataTests.content else { return }
        let catalog = try GameCatalog.load(gameContent: content, language: "fr").get()
        #expect(catalog.entry(for: Self.item("24"))?.displayName == "Panais")
        #expect(catalog.entry(for: Self.item("130", object: false, bigCraftable: true))?.displayName == "Coffre")
        #expect(catalog.entry(for: Self.item("130"))?.displayName == "Thon")
    }
}
