import Foundation
import Testing
@testable import StarHubTHCore

// MARK: - Test helpers

/// Builds a `SaveGameInfo` for tests with sensible defaults — only
/// `folderName`/`fileURL` need to be set per test (every test controls
/// where its fake save file lives).
func makeTestSave(
    folderName: String,
    fileURL: URL,
    lastModified: Date = Date(),
    playerName: String = "TestPlayer",
    farmName: String = "TestFarm",
    favoriteThing: String = "",
    money: Int = 500,
    spouse: String = "",
    maxHealth: Int = 100,
    maxStamina: Int = 270,
    goldenWalnuts: Int = 0,
    qiGems: Int = 0,
    clubCoins: Int = 0,
    totalMoneyEarned: Int = 500,
    year: Int = 1,
    season: Int = 0,
    day: Int = 1,
    whichFarm: Int = 0,
    hairStyle: Int = 0,
    hairColor: SaveHairColor = .default,
    skinIndex: Int = 0,
    modFarmName: String? = nil
) -> SaveGameInfo {
    SaveGameInfo(
        folderName: folderName,
        fileURL: fileURL,
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
        modFarmName: modFarmName
    )
}

/// Writes a UTF-8 text file at `url`, creating its parent directory if
/// needed.
func writeTestSaveFile(at url: URL, content: String = "test save content") throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try content.data(using: .utf8)!.write(to: url)
}

/// One isolated test environment: a fresh temp root containing a
/// `Saves/` folder, mirroring the real on-disk shape closely enough for
/// SaveManager's folder-operation methods (which never read
/// `SaveManager`'s own `savesDir` — every method operates on the URLs
/// passed via its `SaveGameInfo`/`SaveBackup` arguments). `cleanup()`
/// must be called (via `defer`) at the end of every test.
struct TestEnvironment {
    let savesDir: URL
    private let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarHubTHTests-\(UUID().uuidString)", isDirectory: true)
        savesDir = root.appendingPathComponent("Saves", isDirectory: true)
        try? FileManager.default.createDirectory(at: savesDir, withIntermediateDirectories: true)
    }

    /// Creates `Saves/<name>/<name>` (a save's XML file shares its
    /// folder's name, matching the real layout) with the given content,
    /// and returns a `SaveGameInfo` pointing at it.
    func makeSave(named name: String, content: String = "test save content") throws -> SaveGameInfo {
        let folderURL = savesDir.appendingPathComponent(name, isDirectory: true)
        let fileURL = folderURL.appendingPathComponent(name)
        try writeTestSaveFile(at: fileURL, content: content)
        return makeTestSave(folderName: name, fileURL: fileURL)
    }

    func cleanup() {
        // A later task's rollback test locks down a path inside `root` —
        // restore full permissions recursively first so removeItem can
        // actually delete everything, regardless of which specific
        // subpath got locked down.
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["-R", "u+rwX", root.path]
        try? chmod.run()
        chmod.waitUntilExit()
        try? FileManager.default.removeItem(at: root)
    }
}

// MARK: - Tests

@Suite struct SaveManagerTests {

    @Test func makeTestSaveBuildsAValidSaveGameInfo() {
        let save = makeTestSave(folderName: "SmokeTest", fileURL: URL(fileURLWithPath: "/tmp/SmokeTest/SmokeTest"))
        #expect(save.folderName == "SmokeTest")
        #expect(save.playerName == "TestPlayer")
    }

    @Test func branchFromBackupKeepsDotsInSaveName() throws {
        // Une partie dont le nom contient un point (« Farm.1 ») : l'ancien
        // `split(".")[0]` la réduisait à « Farm », le fichier interne n'était
        // jamais renommé, et Stardew ignorait la branche (nom dossier ≠ nom
        // fichier). On lit désormais le nom d'origine porté par le backup.
        let env = TestEnvironment()
        defer { env.cleanup() }

        let info = try env.makeSave(named: "Farm.1", content: "<SaveGame><name>Farm.1</name></SaveGame>")
        #expect(SaveManager.shared.backupSave(info: info))

        let backups = SaveManager.shared.listBackups(for: info)
        try #require(backups.count == 1)
        #expect(backups[0].saveFolder == "Farm.1")

        #expect(SaveManager.shared.branchFromBackup(backup: backups[0], newName: "Alice", newFarm: "NewFarm"))

        // Le fichier interne de la branche doit porter le nom du dossier
        // (Farm.1_branch) — pas rester « Farm.1 », sinon Stardew ne voit pas
        // la sauvegarde.
        let branchedFile = env.savesDir.appendingPathComponent("Farm.1_branch")
            .appendingPathComponent("Farm.1_branch")
        #expect(FileManager.default.fileExists(atPath: branchedFile.path))
    }

    /// Une balise **vide** doit pouvoir recevoir une valeur. La regex de
    /// remplacement exigeait au moins un caractère (`[^<]+`) : sur une sauvegarde
    /// où `<favoriteThing></favoriteThing>` est vide, l'édition rendait « réussi »
    /// et n'écrivait rien. Le champ restait vide sans un mot d'explication.
    @Test func anEmptyTagStillReceivesItsNewValue() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let xml = """
        <SaveGame><player><name>Alice</name><farmName>Ferme</farmName>\
        <favoriteThing></favoriteThing><money>500</money>\
        <totalMoneyEarned>500</totalMoneyEarned><maxHealth>100</maxHealth>\
        <maxStamina>270</maxStamina><goldenWalnuts>0</goldenWalnuts>\
        <qiGems>0</qiGems><clubCoins>0</clubCoins></player></SaveGame>
        """
        let info = try env.makeSave(named: "EmptyTag", content: xml)

        #expect(SaveManager.shared.updateSave(
            info: info, newName: "Alice", newFarm: "Ferme", newFav: "Le café",
            newMoney: 500, newTotalMoneyEarned: 500, newMaxHealth: 100,
            newMaxStamina: 270, newGoldenWalnuts: 0, newQiGems: 0,
            newClubCoins: 0, newSpouse: ""))

        let written = try String(contentsOf: info.fileURL, encoding: .utf8)
        #expect(written.contains("<favoriteThing>Le café</favoriteThing>"))
    }

    /// Le risque de la correction : accepter une balise vide élargit ce que la
    /// regex peut attraper, donc le « premier » résultat pourrait se déplacer.
    /// Ici un objet d'inventaire porte un `<name>` vide **après** celui du
    /// joueur — c'est bien celui du joueur qui doit être réécrit.
    @Test func anEmptyTagFurtherDownDoesNotStealTheMatch() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let xml = """
        <SaveGame><player><name>Alice</name><farmName>Ferme</farmName>\
        <favoriteThing></favoriteThing><money>500</money>\
        <totalMoneyEarned>500</totalMoneyEarned><maxHealth>100</maxHealth>\
        <maxStamina>270</maxStamina><goldenWalnuts>0</goldenWalnuts>\
        <qiGems>0</qiGems><clubCoins>0</clubCoins>\
        <items><Item><name></name></Item><Item><name>Houe</name></Item></items>\
        </player></SaveGame>
        """
        let info = try env.makeSave(named: "Inventory", content: xml)

        #expect(SaveManager.shared.updateSave(
            info: info, newName: "Bérénice", newFarm: "Ferme", newFav: "Le café",
            newMoney: 500, newTotalMoneyEarned: 500, newMaxHealth: 100,
            newMaxStamina: 270, newGoldenWalnuts: 0, newQiGems: 0,
            newClubCoins: 0, newSpouse: ""))

        let written = try String(contentsOf: info.fileURL, encoding: .utf8)
        #expect(written.contains("<name>Bérénice</name>"))
        // L'objet d'inventaire reste intact, vide comme il l'était.
        #expect(written.contains("<Item><name></name></Item>"))
        #expect(written.contains("<Item><name>Houe</name></Item>"))
    }

    // MARK: - H-T5b T2 : SaveGameInfo étendu + parsing <whichModFarm>

    /// XML ne contenant que `<player>` : les 4 nouveaux champs reçoivent leurs
    /// defaults (0/0/0/nil) plutôt que de crasher ou d'inventer des valeurs.
    @Test func saveGameInfoDefaultsWhenFieldsAbsent() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let xml = "<SaveGame><player><name>Alice</name></player></SaveGame>"
        let fileURL = env.savesDir.appendingPathComponent("Defaults").appendingPathComponent("Defaults")
        try writeTestSaveFile(at: fileURL, content: xml)
        let info = SaveManager.shared.parseSaveFile(url: fileURL, folderName: "Defaults")
        try #require(info != nil)
        #expect(info?.hairStyle == 0)
        #expect(info?.hairColor == SaveHairColor.default)
        #expect(info?.skinIndex == 0)
        #expect(info?.modFarmName == nil)
    }

    /// Forme vanilla : `<whichModFarm><name>X</name></whichModFarm>`.
    @Test func modFarmNameNestedForm() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let xml = "<SaveGame><player><name>Alice</name></player><whichModFarm><name>Ridgeside</name></whichModFarm></SaveGame>"
        let fileURL = env.savesDir.appendingPathComponent("ModNested").appendingPathComponent("ModNested")
        try writeTestSaveFile(at: fileURL, content: xml)
        let info = SaveManager.shared.parseSaveFile(url: fileURL, folderName: "ModNested")
        try #require(info != nil)
        #expect(info?.modFarmName == "Ridgeside")
    }

    /// Forme « mod mal codé » : texte brut directement dans `<whichModFarm>`.
    /// La regex tolérante accepte les deux formes.
    @Test func modFarmNameFlatForm() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let xml = "<SaveGame><player><name>Alice</name></player><whichModFarm>Ridgeside</whichModFarm></SaveGame>"
        let fileURL = env.savesDir.appendingPathComponent("ModFlat").appendingPathComponent("ModFlat")
        try writeTestSaveFile(at: fileURL, content: xml)
        let info = SaveManager.shared.parseSaveFile(url: fileURL, folderName: "ModFlat")
        try #require(info != nil)
        #expect(info?.modFarmName == "Ridgeside")
    }

    /// `<whichModFarm>` totalement absent → `nil`.
    @Test func modFarmNameAbsent() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let xml = "<SaveGame><player><name>Alice</name></player></SaveGame>"
        let fileURL = env.savesDir.appendingPathComponent("NoModFarm").appendingPathComponent("NoModFarm")
        try writeTestSaveFile(at: fileURL, content: xml)
        let info = SaveManager.shared.parseSaveFile(url: fileURL, folderName: "NoModFarm")
        try #require(info != nil)
        #expect(info?.modFarmName == nil)
    }

    /// `<whichModFarm></whichModFarm>` vide → `nil` (pas de chaîne vide).
    @Test func modFarmNameEmpty() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let xml = "<SaveGame><player><name>Alice</name></player><whichModFarm></whichModFarm></SaveGame>"
        let fileURL = env.savesDir.appendingPathComponent("ModEmpty").appendingPathComponent("ModEmpty")
        try writeTestSaveFile(at: fileURL, content: xml)
        let info = SaveManager.shared.parseSaveFile(url: fileURL, folderName: "ModEmpty")
        try #require(info != nil)
        #expect(info?.modFarmName == nil)
    }

    /// `<whichModFarm><id>X</id></whichModFarm>` : pas de `<name>` → `nil`.
    /// La regex tolère uniquement le contenu direct ou un `<name>` ; une
    /// autre sous-balise ne matche pas et l'absence de fallback laisse `nil`.
    @Test func modFarmNameWithoutName() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let xml = "<SaveGame><player><name>Alice</name></player><whichModFarm><id>X</id></whichModFarm></SaveGame>"
        let fileURL = env.savesDir.appendingPathComponent("ModNoName").appendingPathComponent("ModNoName")
        try writeTestSaveFile(at: fileURL, content: xml)
        let info = SaveManager.shared.parseSaveFile(url: fileURL, folderName: "ModNoName")
        try #require(info != nil)
        #expect(info?.modFarmName == nil)
    }

    /// `<whichFarm>abc</whichFarm>` (corrompu) → `Int(...) ?? 0` retombe sur 0,
    /// comme le code l'a toujours fait pour les autres tags numériques.
    @Test func whichFarmNonInt() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let xml = "<SaveGame><player><name>Alice</name></player><whichFarm>abc</whichFarm></SaveGame>"
        let fileURL = env.savesDir.appendingPathComponent("BadWhichFarm").appendingPathComponent("BadWhichFarm")
        try writeTestSaveFile(at: fileURL, content: xml)
        let info = SaveManager.shared.parseSaveFile(url: fileURL, folderName: "BadWhichFarm")
        try #require(info != nil)
        #expect(info?.whichFarm == 0)
    }

    /// `whichFarm` hors plage vanilla → `farmTypeName` retourne la **clé** L10n
    /// du fallback (pas le texte thaï historique, plus le texte résolu) :
    /// c'est le consommateur (`SaveFarmNameResolver`) qui résoudra la clé.
    @Test func farmTypeNameOutOfRangeReturnsFarmTypeModKey() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let xml = "<SaveGame><player><name>Alice</name></player><whichFarm>999999</whichFarm></SaveGame>"
        let fileURL = env.savesDir.appendingPathComponent("ModFarmBig").appendingPathComponent("ModFarmBig")
        try writeTestSaveFile(at: fileURL, content: xml)
        let info = SaveManager.shared.parseSaveFile(url: fileURL, folderName: "ModFarmBig")
        try #require(info != nil)
        #expect(info?.farmTypeName == "saves_farm_type_mod")
    }

    // MARK: - Avatar du fermier : les vrais tags du jeu (audit H-T5b)

    /// Vérité terrain mesurée sur une save réelle (2026-09-01) : la coiffure
    /// vit dans `<hair>` (int) et la couleur dans `<hairstyleColor>` — un
    /// Color XNA sérialisé en composantes, en ordre alphabétique B,G,R,A
    /// puis PackedValue. Les tags `<hairStyle>`/`<hairColor>` supposés par
    /// la spec n'existent pas dans le XML : l'avatar restait figé sur
    /// « chauve, couleur 0 » pour toutes les saves.
    @Test func avatarParsesTheRealGameTags() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let xml = """
        <SaveGame><player><name>Alice</name><hair>33</hair><skin>2</skin>\
        <hairstyleColor><B>108</B><G>81</G><R>27</R><A>255</A>\
        <PackedValue>4285288731</PackedValue></hairstyleColor></player></SaveGame>
        """
        let fileURL = env.savesDir.appendingPathComponent("RealAvatar").appendingPathComponent("RealAvatar")
        try writeTestSaveFile(at: fileURL, content: xml)
        let info = SaveManager.shared.parseSaveFile(url: fileURL, folderName: "RealAvatar")
        try #require(info != nil)
        #expect(info?.hairStyle == 33, "la coiffure vit dans <hair>, pas <hairStyle>")
        #expect(info?.hairColor == SaveHairColor(r: 27, g: 81, b: 108),
                "la couleur est libre (R/G/B 0-255), pas un index de palette")
        #expect(info?.skinIndex == 2)
    }

    /// Composantes dans un autre ordre que la sérialisation XNA : la lecture
    /// se fait par nom, l'ordre du XML n'est jamais supposé.
    @Test func avatarHairColorIsOrderIndependent() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let xml = """
        <SaveGame><player><name>Alice</name>\
        <hairstyleColor><R>255</R><G>0</G><B>0</B></hairstyleColor></player></SaveGame>
        """
        let fileURL = env.savesDir.appendingPathComponent("RedHair").appendingPathComponent("RedHair")
        try writeTestSaveFile(at: fileURL, content: xml)
        let info = SaveManager.shared.parseSaveFile(url: fileURL, folderName: "RedHair")
        try #require(info != nil)
        #expect(info?.hairColor == SaveHairColor(r: 255, g: 0, b: 0))
    }

    /// `<hairstyleColor>` absent (vieille save) ou une composante manquante :
    /// couleur par défaut, jamais une valeur inventée.
    @Test func avatarHairColorFallsBackToDefault() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let noBlock = "<SaveGame><player><name>Alice</name><hair>4</hair></player></SaveGame>"
        let noBlockURL = env.savesDir.appendingPathComponent("NoHairColor").appendingPathComponent("NoHairColor")
        try writeTestSaveFile(at: noBlockURL, content: noBlock)
        let noBlockInfo = SaveManager.shared.parseSaveFile(url: noBlockURL, folderName: "NoHairColor")
        try #require(noBlockInfo != nil)
        #expect(noBlockInfo?.hairColor == SaveHairColor.default)

        let partial = "<SaveGame><player><name>Alice</name><hairstyleColor><R>10</R></hairstyleColor></player></SaveGame>"
        let partialURL = env.savesDir.appendingPathComponent("PartialHairColor").appendingPathComponent("PartialHairColor")
        try writeTestSaveFile(at: partialURL, content: partial)
        let partialInfo = SaveManager.shared.parseSaveFile(url: partialURL, folderName: "PartialHairColor")
        try #require(partialInfo != nil)
        #expect(partialInfo?.hairColor == SaveHairColor.default)
    }

    @Test func saveHairColorClampsOutOfRangeComponents() {
        #expect(SaveHairColor(r: -5, g: 81, b: 300) == SaveHairColor(r: 0, g: 81, b: 255))
        #expect(SaveHairColor(r: 27, g: 81, b: 108) ==
                SaveHairColor(r: 27, g: 81, b: 108))
    }

    // MARK: - Sexe du fermier (avatar illustré)

    /// `<gender>` est textuel (Male/Female/Undefined) et la première
    /// occurrence du fichier est le fermier — mesuré sur une vraie save :
    /// la sienne porte ~70 occurrences (PNJ, bébés), celle du joueur vient
    /// en tête, juste après `difficultyModifier`.
    @Test func genderParsesTheFarmerNotAnNPC() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let xml = """
        <SaveGame><player><name>Alice</name><difficultyModifier>1</difficultyModifier>\
        <gender>Female</gender></player>\
        <characters><NPC><gender>Male</gender></NPC></characters></SaveGame>
        """
        let fileURL = env.savesDir.appendingPathComponent("GenderF").appendingPathComponent("GenderF")
        try writeTestSaveFile(at: fileURL, content: xml)
        let info = SaveManager.shared.parseSaveFile(url: fileURL, folderName: "GenderF")
        try #require(info != nil)
        #expect(info?.isFemale == true)
    }

    @Test func genderMaleAndAbsentDefaultToMale() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let male = "<SaveGame><player><name>Bob</name><gender>Male</gender></player></SaveGame>"
        let maleURL = env.savesDir.appendingPathComponent("GenderM").appendingPathComponent("GenderM")
        try writeTestSaveFile(at: maleURL, content: male)
        let maleInfo = SaveManager.shared.parseSaveFile(url: maleURL, folderName: "GenderM")
        try #require(maleInfo != nil)
        #expect(maleInfo?.isFemale == false)

        let none = "<SaveGame><player><name>Bob</name></player></SaveGame>"
        let noneURL = env.savesDir.appendingPathComponent("GenderNone").appendingPathComponent("GenderNone")
        try writeTestSaveFile(at: noneURL, content: none)
        let noneInfo = SaveManager.shared.parseSaveFile(url: noneURL, folderName: "GenderNone")
        try #require(noneInfo != nil)
        #expect(noneInfo?.isFemale == false, "sexe absent ou inconnu → fermier")
    }

    /// Le pendant : une balise déjà remplie garde le comportement d'avant.
    @Test func aFilledTagIsStillReplaced() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let xml = """
        <SaveGame><player><name>Alice</name><farmName>Ferme</farmName>\
        <favoriteThing>Ancien</favoriteThing><money>500</money>\
        <totalMoneyEarned>500</totalMoneyEarned><maxHealth>100</maxHealth>\
        <maxStamina>270</maxStamina><goldenWalnuts>0</goldenWalnuts>\
        <qiGems>0</qiGems><clubCoins>0</clubCoins></player></SaveGame>
        """
        let info = try env.makeSave(named: "FilledTag", content: xml)

        #expect(SaveManager.shared.updateSave(
            info: info, newName: "Alice", newFarm: "Ferme", newFav: "Nouveau",
            newMoney: 700, newTotalMoneyEarned: 500, newMaxHealth: 100,
            newMaxStamina: 270, newGoldenWalnuts: 0, newQiGems: 0,
            newClubCoins: 0, newSpouse: ""))

        let written = try String(contentsOf: info.fileURL, encoding: .utf8)
        #expect(written.contains("<favoriteThing>Nouveau</favoriteThing>"))
        #expect(written.contains("<money>700</money>"))
    }
}
