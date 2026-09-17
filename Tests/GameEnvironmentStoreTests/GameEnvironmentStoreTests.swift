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
/// `@MainActor` : le store s'isole sur l'acteur principal depuis P5-L5 — son
/// état publié est celui que les vues lisent. Seul `fetchSteamUser` en sort
/// (`nonisolated`), et il publie par un hop : d'où les `waitUntil` déjà
/// présents sur ces trois tests.
@Suite @MainActor struct GameEnvironmentStoreTests {

    private let fm = FileManager.default

    /// Suite UserDefaults jetable, unique par essai.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "GameEnvironmentStoreTests-\(UUID().uuidString))")!
    }

    /// Un « jeu » avec `smapi-internal/` et son marqueur de version. Le
    /// chemin rendu est **résolu** (`/var/folders` → `/private/var`) : c'est
    /// la forme que `GameDirLocator.normalize` pose désormais dans `gameDir`,
    /// et comparer à la forme brute rougirait sur le symlink, pas sur un bug.
    private func makeGameDir(markerVersion: String? = nil) throws -> String {
        let game = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: game.appendingPathComponent("smapi-internal"),
                               withIntermediateDirectories: true)
        if let markerVersion {
            try markerVersion.write(
                to: game.appendingPathComponent("smapi-internal/.starhubth-installed-version"),
                atomically: true, encoding: .utf8)
        }
        return (game.path as NSString).resolvingSymlinksInPath
    }

    /// Attend que la file principale ait vidé ce qui y est déjà en file —
    /// un hop postérieur à l'appel garantit (FIFO) que celui du store est
    /// passé.
    ///
    /// ⚠️ **Attendre sans bloquer l'acteur.** La suite est `@MainActor` depuis
    /// que le store l'est : une boucle qui pompe la `RunLoop` retient
    /// l'acteur principal, et le hop qu'on attend ne peut alors jamais
    /// s'exécuter — les quatre attentes expiraient. `await` rend la main.
    private func drainMainQueue() async {
        let landed = LandedFlag()
        DispatchQueue.main.async { landed.value = true }
        let deadline = Date().addingTimeInterval(5)
        while !landed.value && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        #expect(landed.value)
    }

    /// Le drapeau traverse la frontière du hop : une capture de `var` local
    /// dans une closure concurrente ne passe pas en concurrence stricte.
    private final class LandedFlag: @unchecked Sendable {
        var value = false
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
        var problem: GameDirLocator.SelectionProblem?
        store.selectGameDir { picked += 1; problem = $0 }
        #expect(store.gameDir == game)
        #expect(picked == 1)
        #expect(picker.callCount == 1)
        #expect(problem == nil)
    }

    /// Le cas qui a motivé le correctif : l'utilisateur désigne l'application
    /// du jeu, pas le `Contents/MacOS` enfoui dedans. Le store enregistre le
    /// second — tout le dépôt dérive `Mods` de `gameDir`.
    @Test func pickingTheAppBundleStoresContentsMacOS() throws {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let macOS = root.appendingPathComponent("Stardew Valley.app/Contents/MacOS")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        fm.createFile(atPath: macOS.appendingPathComponent("StardewValley").path, contents: Data())
        let bundle = root.appendingPathComponent("Stardew Valley.app").path
        let store = GameEnvironmentStore(defaults: makeDefaults(),
                                         picker: StubFilePicker(path: bundle))
        store.selectGameDir { _ in }
        #expect(store.gameDir == (macOS.path as NSString).resolvingSymlinksInPath)
    }

    /// Un jeu sans `Mods/` — celui qu'on vient d'installer — repart avec le
    /// dossier créé, sinon le scan rend zéro mod sans rien dire.
    @Test func theModsFolderIsCreatedOnSelection() throws {
        let game = try makeGameDir()
        #expect(!fm.fileExists(atPath: "\(game)/Mods"))
        let store = GameEnvironmentStore(defaults: makeDefaults(),
                                         picker: StubFilePicker(path: game))
        var problem: GameDirLocator.SelectionProblem?
        store.selectGameDir { problem = $0 }
        #expect(fm.fileExists(atPath: "\(game)/Mods"))
        #expect(problem == nil)
    }

    /// `Mods/` impossible à créer : le dossier reste choisi — le chemin n'est
    /// pas en cause — mais l'échec remonte à l'appelant, qui le journalise.
    @Test func aBlockedModsFolderIsReportedWithoutLosingTheChoice() throws {
        let game = try makeGameDir()
        fm.createFile(atPath: "\(game)/Mods", contents: Data())
        let store = GameEnvironmentStore(defaults: makeDefaults(),
                                         picker: StubFilePicker(path: game))
        var called = false
        var problem: GameDirLocator.SelectionProblem?
        store.selectGameDir { called = true; problem = $0 }
        #expect(store.gameDir == game)
        #expect(called)
        #expect(problem == .modsFolderUnavailable)
    }

    /// Le défaut trouvé sur le parc réel le 2026-09-17 : `gameDir` valait le
    /// dossier qui **contient** les jeux, faute de pouvoir cliquer le bundle.
    /// Y semer un `Mods/` vide serait un dégât — le dossier est enregistré, le
    /// problème remonte, et rien n'est écrit.
    @Test func aFolderOfGamesIsFlaggedAndNothingIsWrittenInIt() throws {
        let shelf = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for game in ["RimWorld.app", "Disco Elysium.app", "Stardew Valley.app"] {
            try fm.createDirectory(at: shelf.appendingPathComponent("\(game)/Contents/MacOS"),
                                   withIntermediateDirectories: true)
        }
        let picked = (shelf.path as NSString).resolvingSymlinksInPath
        let store = GameEnvironmentStore(defaults: makeDefaults(),
                                         picker: StubFilePicker(path: shelf.path))
        var problem: GameDirLocator.SelectionProblem?
        store.selectGameDir { problem = $0 }
        #expect(problem == .notAGameFolder)
        #expect(!fm.fileExists(atPath: "\(picked)/Mods"))
        #expect(store.gameDir == picked) // choisi quand même : pas de bouton sans effet
    }

    /// Annuler le panneau : rien ne bouge, et le scan n'est pas relancé.
    @Test func cancellingThePanelLeavesEverythingUntouched() throws {
        let game = try makeGameDir()
        let defaults = makeDefaults()
        defaults.set(game, forKey: UDKey.gameDir)
        let store = GameEnvironmentStore(defaults: defaults, picker: StubFilePicker(path: nil))
        store.restoreGameDir(home: "/nulle-part")
        var picked = 0
        store.selectGameDir { _ in picked += 1 }
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
    @Test func theVDFDrivesTheSteamIdentity() async throws {
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
                             fallbackFarmerName: "Fermier")
        await drainMainQueue()
        #expect(store.steamUsername == "David")
        #expect(store.steamAvatarPath == avatar.path)
    }

    /// VDF absent : **silence** — comportement historique. Pas de repli
    /// « Farmer », pas d'effacement : le nom déjà affiché reste.
    @Test func withoutAVDFNothingIsPublished() async {
        let store = GameEnvironmentStore(defaults: makeDefaults(), picker: StubFilePicker(path: nil))
        store.fetchSteamUser(home: "/nulle-part", systemUserName: "David Baudoin",
                             fallbackFarmerName: "Fermier")
        await drainMainQueue()
        #expect(store.steamUsername == "")
        #expect(store.steamAvatarPath == nil)
    }

    /// VDF lisible mais sans `PersonaName` : repli sur le prénom du compte
    /// macOS. Un nom système vide tombe sur la valeur localisée reçue — le
    /// store n'invente rien, il reçoit.
    @Test func aVDFWithoutPersonaNameFallsBackThenToTheLocalizedValue() async throws {
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
                             fallbackFarmerName: "Fermier")
        await drainMainQueue()
        #expect(store.steamUsername == "David")

        let store2 = GameEnvironmentStore(defaults: makeDefaults(), picker: StubFilePicker(path: nil))
        store2.fetchSteamUser(home: home.path, systemUserName: "",
                              fallbackFarmerName: "Fermier")
        await drainMainQueue()
        #expect(store2.steamUsername == "Fermier")
    }
}
