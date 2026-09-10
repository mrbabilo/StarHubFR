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
}
