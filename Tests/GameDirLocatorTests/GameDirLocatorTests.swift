import Testing
import Foundation
@testable import StarHubTHCore

/// `detectDefaultGameDir` et le bloc avatar de `fetchSteamUser` vivaient en
/// ligne dans le ViewModel, sans aucun test. `home`/`gogRoot`/`fm` injectés :
/// les chemins réels de la machine (`/Applications` porte le jeu ici) ne
/// sont pas des entrées de test.
///
/// ⚠️ Les dossiers temporaires vivent sous un symlink (`/var/folders` →
/// `/private/var`) : les chemins attendus sont calculés par la même
/// résolution que celle du localisateur — c'est précisément le contrat
/// d'AGENTS §4.9.
struct GameDirLocatorTests {

    private let fm = FileManager.default

    /// Racine temporaire créée pour l'essai, avec son chemin **résolu** —
    /// celui que le localisateur doit rendre.
    @discardableResult
    private func makeDir(_ relative: String) throws -> (raw: String, resolved: String) {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent(relative)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let raw = root.path
        let resolved = (raw as NSString).resolvingSymlinksInPath
        return (raw, resolved)
    }

    // MARK: - detectDefault

    @Test func aSteamInstallWins() throws {
        let (raw, resolved) = try makeDir("Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS")
        let gogRoot = try makeDir("Stardew Valley.app/Contents/MacOS") // présent mais secondaire
        let detected = GameDirLocator.detectDefault(home: raw, gogRoot: gogRoot.raw)
        #expect(detected == "\(resolved)/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS")
    }

    @Test func gogIsTheFallback() throws {
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let gogRoot = try makeDir("Stardew Valley.app/Contents/MacOS")
        let detected = GameDirLocator.detectDefault(home: home.path, gogRoot: gogRoot.raw)
        #expect(detected == "\(gogRoot.resolved)/Stardew Valley.app/Contents/MacOS")
    }

    @Test func nothingFoundYieldsAnEmptyPath() throws {
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let gogRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        #expect(GameDirLocator.detectDefault(home: home.path, gogRoot: gogRoot) == "")
    }

    @Test func theReturnedPathIsSymlinkResolved() throws {
        // Le contrat d'AGENTS §4.9 : le chemin rendu nourrit des comparaisons
        // avec `physicalRoot` — il doit être résolu, pas brut.
        let (raw, resolved) = try makeDir("Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS")
        let detected = GameDirLocator.detectDefault(home: raw, gogRoot: "/nulle-part")
        #expect(detected.hasPrefix(resolved))
        #expect(!detected.hasPrefix(raw) || raw == resolved) // le cas non-symlinké reste juste
    }

    // MARK: - avatarPath

    @Test func pngWinsOverJpg() throws {
        let (raw, _) = try makeDir("Library/Application Support/Steam/config/avatarcache")
        let id = "76561198000000001"
        fm.createFile(atPath: "\(raw)/Library/Application Support/Steam/config/avatarcache/\(id).png", contents: Data())
        fm.createFile(atPath: "\(raw)/Library/Application Support/Steam/config/avatarcache/\(id).jpg", contents: Data())
        let path = GameDirLocator.avatarPath(steamID: id, home: raw)
        #expect(path?.hasSuffix(".png") == true)
    }

    @Test func jpgIsTheFallback() throws {
        let (raw, _) = try makeDir("Library/Application Support/Steam/config/avatarcache")
        let id = "76561198000000002"
        fm.createFile(atPath: "\(raw)/Library/Application Support/Steam/config/avatarcache/\(id).jpg", contents: Data())
        let path = GameDirLocator.avatarPath(steamID: id, home: raw)
        #expect(path?.hasSuffix(".jpg") == true)
    }

    @Test func noAvatarFileYieldsNil() throws {
        let (raw, _) = try makeDir("Library/Application Support/Steam/config/avatarcache")
        #expect(GameDirLocator.avatarPath(steamID: "76561198000000003", home: raw) == nil)
    }

    @Test func anEmptySteamIdLooksForNothing() throws {
        // Sans identifiant, aucun chemin d'avatar ne doit être construit —
        // le chemin aurait fini par un `/…/avatarcache/.png` fantôme.
        #expect(GameDirLocator.avatarPath(steamID: "", home: "/nulle-part") == nil)
    }

    // MARK: - normalize

    /// Le cas qui a motivé le correctif : l'utilisateur désigne l'app du jeu,
    /// pas le `Contents/MacOS` enfoui dedans.
    @Test func pickingTheAppBundleYieldsContentsMacOS() throws {
        let (raw, resolved) = try makeDir("Stardew Valley.app/Contents/MacOS")
        let picked = "\(raw)/Stardew Valley.app"
        #expect(GameDirLocator.normalize(pickedPath: picked)
                == "\(resolved)/Stardew Valley.app/Contents/MacOS")
    }

    /// L'installation Steam n'est pas un bundle — c'est un dossier ordinaire
    /// nommé `Stardew Valley` — mais la descente est la même.
    @Test func pickingTheSteamFolderYieldsContentsMacOS() throws {
        let (raw, resolved) = try makeDir("Stardew Valley/Contents/MacOS")
        #expect(GameDirLocator.normalize(pickedPath: "\(raw)/Stardew Valley")
                == "\(resolved)/Stardew Valley/Contents/MacOS")
    }

    /// Déjà au bon endroit : rien ne bouge, et surtout pas de descente vers un
    /// `Contents/MacOS/Contents/MacOS` fantôme.
    @Test func anAlreadyCorrectPathIsLeftAlone() throws {
        let (raw, resolved) = try makeDir("Stardew Valley.app/Contents/MacOS")
        let picked = "\(raw)/Stardew Valley.app/Contents/MacOS"
        #expect(GameDirLocator.normalize(pickedPath: picked)
                == "\(resolved)/Stardew Valley.app/Contents/MacOS")
    }

    @Test func stoppingAtContentsStillFindsMacOS() throws {
        let (raw, resolved) = try makeDir("Stardew Valley.app/Contents/MacOS")
        let picked = "\(raw)/Stardew Valley.app/Contents"
        #expect(GameDirLocator.normalize(pickedPath: picked)
                == "\(resolved)/Stardew Valley.app/Contents/MacOS")
    }

    /// « Où sont mes mods ? » — désigner `Mods/` lui-même remonte d'un cran :
    /// `gameDir` est le parent, tout le dépôt en dérive `Mods`.
    @Test func pickingTheModsFolderClimbsToItsParent() throws {
        let (raw, resolved) = try makeDir("Stardew Valley.app/Contents/MacOS/Mods")
        let picked = "\(raw)/Stardew Valley.app/Contents/MacOS/Mods"
        #expect(GameDirLocator.normalize(pickedPath: picked)
                == "\(resolved)/Stardew Valley.app/Contents/MacOS")
    }

    /// Aucune forme reconnue : on rend le chemin tel quel plutôt que de
    /// refuser — les installations exotiques existent, et l'accueil signale
    /// déjà un dossier sans SMAPI.
    @Test func anUnrecognisedFolderIsReturnedUnchanged() throws {
        let (raw, resolved) = try makeDir("quelque-part")
        #expect(GameDirLocator.normalize(pickedPath: "\(raw)/quelque-part")
                == "\(resolved)/quelque-part")
    }

    /// Un `Contents/MacOS` qui n'existe pas ne doit pas être inventé : le
    /// `.app` d'une autre application reste rendu tel quel.
    @Test func aBundleWithoutContentsMacOSIsNotInvented() throws {
        let (raw, resolved) = try makeDir("Autre.app/Contents/Resources")
        #expect(GameDirLocator.normalize(pickedPath: "\(raw)/Autre.app")
                == "\(resolved)/Autre.app")
    }

    /// Même contrat qu'`detectDefault` : le chemin rendu est résolu des
    /// symlinks, sinon il diverge en forme de celui que la détection pose.
    @Test func theNormalisedPathIsSymlinkResolved() throws {
        let (raw, resolved) = try makeDir("Stardew Valley.app/Contents/MacOS")
        let normalised = GameDirLocator.normalize(pickedPath: "\(raw)/Stardew Valley.app")
        #expect(normalised.hasPrefix(resolved))
        #expect(!normalised.hasPrefix(raw) || raw == resolved)
    }

    // MARK: - ensureModsFolder

    @Test func theModsFolderIsCreatedWhenMissing() throws {
        let (raw, _) = try makeDir("Stardew Valley.app/Contents/MacOS")
        let gameDir = "\(raw)/Stardew Valley.app/Contents/MacOS"
        #expect(!fm.fileExists(atPath: "\(gameDir)/Mods"))
        let mods = try GameDirLocator.ensureModsFolder(gameDir: gameDir)
        #expect(mods == "\(gameDir)/Mods")
        #expect(fm.fileExists(atPath: mods))
    }

    /// Un `Mods/` déjà peuplé n'est jamais réécrit — la création ne doit pas
    /// devenir un effaceur silencieux.
    @Test func anExistingModsFolderIsLeftIntact() throws {
        let (raw, _) = try makeDir("Stardew Valley.app/Contents/MacOS/Mods/UnMod")
        let gameDir = "\(raw)/Stardew Valley.app/Contents/MacOS"
        let mods = try GameDirLocator.ensureModsFolder(gameDir: gameDir)
        #expect(fm.fileExists(atPath: "\(mods)/UnMod"))
    }

    /// Le dossier ne peut pas être créé : la fonction lève au lieu de rendre
    /// un chemin qui n'existe pas. Ici, `Mods` est un **fichier**.
    @Test func aBlockedCreationThrows() throws {
        let (raw, _) = try makeDir("Stardew Valley.app/Contents/MacOS")
        let gameDir = "\(raw)/Stardew Valley.app/Contents/MacOS"
        fm.createFile(atPath: "\(gameDir)/Mods", contents: Data())
        #expect(throws: (any Error).self) {
            try GameDirLocator.ensureModsFolder(gameDir: gameDir)
        }
    }


    // MARK: - isGameFolder

    /// Les marqueurs relevés sur une installation réelle — un seul suffit,
    /// une installation neuve n'ayant pas encore `smapi-internal/`.
    @Test func eachMarkerIsEnoughOnItsOwn() throws {
        for marker in ["Stardew Valley", "StardewValley", "StardewModdingAPI",
                       "smapi-internal"] {
            let (raw, _) = try makeDir("jeu")
            let game = "\(raw)/jeu"
            #expect(!GameDirLocator.isGameFolder(game))
            fm.createFile(atPath: "\(game)/\(marker)", contents: Data())
            #expect(GameDirLocator.isGameFolder(game), "\(marker) devrait suffire")
        }
    }

    /// Le cas réel : un dossier qui **contient** des jeux n'en est pas un.
    /// Créer un `Mods/` dedans serait un dégât.
    @Test func aShelfOfGamesIsNotAGameFolder() throws {
        let (raw, _) = try makeDir("JEUX/RimWorld.app/Contents/MacOS")
        try fm.createDirectory(atPath: "\(raw)/JEUX/Stardew Valley.app/Contents/MacOS",
                               withIntermediateDirectories: true)
        #expect(!GameDirLocator.isGameFolder("\(raw)/JEUX"))
    }

    /// Une autre application n'est pas le jeu, même si sa structure de bundle
    /// est identique — c'est ce qui sépare `normalize` (structure) de
    /// `isGameFolder` (contenu).
    @Test func anotherAppBundleIsNotAGameFolder() throws {
        let (raw, _) = try makeDir("Autre.app/Contents/MacOS")
        fm.createFile(atPath: "\(raw)/Autre.app/Contents/MacOS/Autre", contents: Data())
        #expect(!GameDirLocator.isGameFolder("\(raw)/Autre.app/Contents/MacOS"))
    }


    /// ⚠️ `Mods/` ne doit **jamais** compter comme marqueur : c'est notre code
    /// qui le crée. S'il en était un, un dossier refusé une première fois
    /// serait accepté à la seconde tentative, le garde ne tenant qu'un tour.
    @Test func ourOwnModsFolderIsNotAMarker() throws {
        let (raw, _) = try makeDir("JEUX/Mods")
        #expect(!GameDirLocator.isGameFolder("\(raw)/JEUX"))
    }

}
