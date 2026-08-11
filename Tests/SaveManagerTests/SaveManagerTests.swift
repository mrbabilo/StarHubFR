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
    whichFarm: Int = 0
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
        whichFarm: whichFarm
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
