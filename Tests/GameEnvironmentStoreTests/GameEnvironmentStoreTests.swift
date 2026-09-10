import Foundation
import Testing
@testable import StarHubTHCore

/// Le bouchon de `FilePicking` — première frontière d'I/O en protocole du
/// dépôt (REFACTORING §3 : protocole, implémentation `Live` et bouchon
/// dans le même commit). Il vit ici, seul consommateur pour l'instant ; un
/// second consommateur le promouvra dans un dossier partagé.
private final class StubFilePicker: FilePicking {
    let path: String?
    private(set) var callCount = 0

    init(path: String?) {
        self.path = path
    }

    func pickDirectory() -> String? {
        callCount += 1
        return path
    }
}

/// Le store du domaine Environnement : état publié, repli de chargement,
/// décision du panneau. La logique pure qu'il orchestre est testée ailleurs
/// (`SteamLoginUsersTests`, `GameDirLocatorTests`,
/// `SmapiVersionEvidenceTests`) — ici, ce sont l'état et les décisions.
///
/// Les préférences passent par une suite jetable (CLAUDE.md : aucun test
/// n'écrit dans le vrai domaine), le disque par des dossiers temporaires.
@Suite struct GameEnvironmentStoreTests {

    private let fm = FileManager.default

    /// Suite UserDefaults jetable, unique par essai.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "GameEnvironmentStoreTests-\(UUID().uuidString))")!
    }

    /// Un « jeu » avec `smapi-internal/` et son marqueur de version.
    private func makeGameDir(markerVersion: String? = nil) throws -> String {
        let game = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: game.appendingPathComponent("smapi-internal"),
                               withIntermediateDirectories: true)
        if let markerVersion {
            try markerVersion.write(
                to: game.appendingPathComponent("smapi-internal/.starhubth-installed-version"),
                atomically: true, encoding: .utf8)
        }
        return game.path
    }

    /// Attend que la file principale ait vidé ce qui y est déjà en file —
    /// un hop postérieur à l'appel garantit (FIFO) que celui du store est
    /// passé.
    private func drainMainQueue() {
        var landed = false
        DispatchQueue.main.async { landed = true }
        let deadline = Date().addingTimeInterval(5)
        while !landed && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        #expect(landed)
    }

    // MARK: - restoreGameDir

    @Test func aPersistedExistingPathIsKept() throws {
        let game = try makeGameDir()
        let defaults = makeDefaults()
        defaults.set(game, forKey: UDKey.gameDir)
        let store = GameEnvironmentStore(defaults: defaults, picker: StubFilePicker(path: nil))
        store.restoreGameDir(home: "/nulle-part")
        #expect(store.gameDir == game)
    }

    @Test func aPersistedButGonePathFallsBackToDetection() throws {
        let defaults = makeDefaults()
        defaults.set("/nulle-part/jeu-supprime", forKey: UDKey.gameDir)
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: home.appendingPathComponent(
            "Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS"),
            withIntermediateDirectories: true)
        let store = GameEnvironmentStore(defaults: defaults, picker: StubFilePicker(path: nil))
        store.restoreGameDir(home: home.path)
        let expected = ((home.path + "/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS") as NSString)
            .resolvingSymlinksInPath
        #expect(store.gameDir == expected)
    }

    @Test func nothingAnywhereYieldsAnEmptyGameDir() throws {
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let store = GameEnvironmentStore(defaults: makeDefaults(), picker: StubFilePicker(path: nil))
        // `gogRoot` injecté : le vrai `/Applications` porte le jeu sur la
        // machine de référence — un état de la machine n'est pas une entrée
        // de test.
        store.restoreGameDir(home: home.path, gogRoot: "/nulle-part")
        #expect(store.gameDir == "")
    }

    /// Le didSet persiste — une détection première installation doit se
    /// retrouver dans les préférences au lancement suivant.
    @Test func aDetectedPathIsPersistedForTheNextLaunch() throws {
        let game = try makeGameDir()
        let defaults = makeDefaults()
        defaults.set(game, forKey: UDKey.gameDir)
        let store = GameEnvironmentStore(defaults: defaults, picker: StubFilePicker(path: nil))
        store.restoreGameDir(home: "/nulle-part")
        #expect(defaults.string(forKey: UDKey.gameDir) == game)
    }

    // MARK: - selectGameDir

    @Test func pickingADirectorySetsTheGameDirAndCallsBack() throws {
        let game = try makeGameDir()
        let picker = StubFilePicker(path: game)
        let store = GameEnvironmentStore(defaults: makeDefaults(), picker: picker)
        var picked = 0
        store.selectGameDir { picked += 1 }
        #expect(store.gameDir == game)
        #expect(picked == 1)
        #expect(picker.callCount == 1)
    }

    /// Annuler le panneau : rien ne bouge, et le scan n'est pas relancé.
    @Test func cancellingThePanelLeavesEverythingUntouched() throws {
        let game = try makeGameDir()
        let defaults = makeDefaults()
        defaults.set(game, forKey: UDKey.gameDir)
        let store = GameEnvironmentStore(defaults: defaults, picker: StubFilePicker(path: nil))
        store.restoreGameDir(home: "/nulle-part")
        var picked = 0
        store.selectGameDir { picked += 1 }
        #expect(store.gameDir == game)
        #expect(picked == 0)
    }

    // MARK: - checkSmapiVersion

    @Test func anEmptyGameDirMakesSMAPIAbsent() {
        let store = GameEnvironmentStore(defaults: makeDefaults(), picker: StubFilePicker(path: nil))
        store.checkSmapiVersion(home: "/nulle-part")
        #expect(store.smapiInstalledVersion == nil)
    }

    @Test func theInstalledMarkerIsReadThroughTheStore() throws {
        let game = try makeGameDir(markerVersion: "4.5.2")
        let defaults = makeDefaults()
        defaults.set(game, forKey: UDKey.gameDir)
        let store = GameEnvironmentStore(defaults: defaults, picker: StubFilePicker(path: nil))
        store.restoreGameDir(home: "/nulle-part")
        store.checkSmapiVersion(home: "/nulle-part")
        #expect(store.smapiInstalledVersion == "4.5.2")
    }

    // MARK: - fetchSteamUser

    /// Un `loginusers.vdf` réel + un avatar png : le nom du compte et le
    /// chemin de l'avatar sont publiés sur main.
    @Test func theVDFDrivesTheSteamIdentity() throws {
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vdf = home.appendingPathComponent("Library/Application Support/Steam/config/loginusers.vdf")
        try fm.createDirectory(at: vdf.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        "users"
        {
            "76561198000000042"
            {
                "PersonaName"   "David"
                "MostRecent"    "1"
            }
        }
        """.write(to: vdf, atomically: true, encoding: .utf8)
        let avatar = home.appendingPathComponent("Library/Application Support/Steam/config/avatarcache/76561198000000042.png")
        try fm.createDirectory(at: avatar.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: avatar.path, contents: Data())

        let store = GameEnvironmentStore(defaults: makeDefaults(), picker: StubFilePicker(path: nil))
        store.fetchSteamUser(home: home.path, systemUserName: "David Baudoin",
                             fallbackFarmerName: { "Fermier" })
        drainMainQueue()
        #expect(store.steamUsername == "David")
        #expect(store.steamAvatarPath == avatar.path)
    }

    /// VDF absent : **silence** — comportement historique. Pas de repli
    /// « Farmer », pas d'effacement : le nom déjà affiché reste.
    @Test func withoutAVDFNothingIsPublished() {
        let store = GameEnvironmentStore(defaults: makeDefaults(), picker: StubFilePicker(path: nil))
        store.fetchSteamUser(home: "/nulle-part", systemUserName: "David Baudoin",
                             fallbackFarmerName: { "Fermier" })
        drainMainQueue()
        #expect(store.steamUsername == "")
        #expect(store.steamAvatarPath == nil)
    }

    /// VDF lisible mais sans `PersonaName` : repli sur le prénom du compte
    /// macOS. Un nom système vide tombe sur la valeur localisée reçue — le
    /// store n'invente rien, il reçoit.
    @Test func aVDFWithoutPersonaNameFallsBackThenToTheLocalizedValue() throws {
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vdf = home.appendingPathComponent("Library/Application Support/Steam/config/loginusers.vdf")
        try fm.createDirectory(at: vdf.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        "users"
        {
            "76561198000000042"
            {
                "MostRecent"    "1"
            }
        }
        """.write(to: vdf, atomically: true, encoding: .utf8)

        let store = GameEnvironmentStore(defaults: makeDefaults(), picker: StubFilePicker(path: nil))
        store.fetchSteamUser(home: home.path, systemUserName: "David Baudoin",
                             fallbackFarmerName: { "Fermier" })
        drainMainQueue()
        #expect(store.steamUsername == "David")

        let store2 = GameEnvironmentStore(defaults: makeDefaults(), picker: StubFilePicker(path: nil))
        store2.fetchSteamUser(home: home.path, systemUserName: "",
                              fallbackFarmerName: { "Fermier" })
        drainMainQueue()
        #expect(store2.steamUsername == "Fermier")
    }
}
