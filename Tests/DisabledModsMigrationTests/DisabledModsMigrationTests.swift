import Foundation
import Testing
@testable import StarHubTHCore

/// La migration one-shot `Mods_disabled/` → préfixe point (REFACTORING §6,
/// domaine Scan). Chaque mécanisme — drapeau, déplacement, junk ignoré,
/// collision suffixée, dossier illisible qui ne fige pas le drapeau — est
/// éprouvé sur un arbre temporaire avec une suite UserDefaults jetable.
@Suite struct DisabledModsMigrationTests {

    private let fm = FileManager.default

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "DisabledModsMigrationTests-\(UUID().uuidString)")!
    }

    private func makeGameDir() throws -> String {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root.path
    }

    private func makeDisabledDir(in gameDir: String, entries: [String]) throws -> String {
        let disabled = URL(fileURLWithPath: gameDir).appendingPathComponent("Mods_disabled")
        try fm.createDirectory(at: disabled, withIntermediateDirectories: true)
        for entry in entries {
            try fm.createDirectory(at: disabled.appendingPathComponent(entry),
                                   withIntermediateDirectories: true)
        }
        return disabled.path
    }

    private func migrate(_ gameDir: String, defaults: UserDefaults,
                         log: ((String, LogLevel) -> Void)? = nil) {
        var logged: [(String, LogLevel)] = []
        DisabledModsMigration.runIfNeeded(
            gameDir: gameDir, defaults: defaults,
            log: log ?? { logged.append(($0, $1)) })
        _ = logged // les essais qui affirment sur le journal passent leur closure
    }

    @Test func noLegacyFolderSetsFlagAndDoesNothing() throws {
        let gameDir = try makeGameDir()
        let defaults = makeDefaults()
        migrate(gameDir, defaults: defaults)
        #expect(defaults.bool(forKey: UDKey.disabledModsMigratedToDotPrefix))
        #expect(!fm.fileExists(atPath: gameDir + "/Mods"))
    }

    /// Le cœur : `Mods_disabled/X` devient `Mods/.X` — en pause, pas absente.
    @Test func movesEntriesToDotPrefix() throws {
        let gameDir = try makeGameDir()
        try makeDisabledDir(in: gameDir, entries: ["OldMod"])
        let defaults = makeDefaults()
        migrate(gameDir, defaults: defaults)
        #expect(fm.fileExists(atPath: gameDir + "/Mods/.OldMod"))
        #expect(!fm.fileExists(atPath: gameDir + "/Mods_disabled/OldMod"))
        #expect(defaults.bool(forKey: UDKey.disabledModsMigratedToDotPrefix))
    }

    /// Un résidu système dans `Mods_disabled/` n'est pas un mod à migrer —
    /// il reste sur place et le dossier n'est pas supprimé pour autant que
    /// lui seul y reste… non : junk seul → le dossier **est** supprimé.
    @Test func junkEntriesAreLeftBehindAndJunkOnlyFolderRemoved() throws {
        let gameDir = try makeGameDir()
        let disabled = try makeDisabledDir(in: gameDir, entries: ["Real", ".DS_Store"])
        let defaults = makeDefaults()
        migrate(gameDir, defaults: defaults)
        #expect(fm.fileExists(atPath: gameDir + "/Mods/.Real"))
        // Le dossier ne contient plus que du junk → supprimé ENTIÈREMENT en
        // fin de passe, le .DS_Store avec lui.
        #expect(!fm.fileExists(atPath: disabled))
        #expect(defaults.bool(forKey: UDKey.disabledModsMigratedToDotPrefix))
    }

    /// Une collision `.X` déjà présent ne détruit rien : le déplacement va
    /// dans un suffixe unique, l'existant reste intact.
    @Test func collisionMovesUnderUniqueSuffix() throws {
        let gameDir = try makeGameDir()
        try makeDisabledDir(in: gameDir, entries: ["Clash"])
        // L'existant : Mods/.Clash, déjà là (plantage d'un passage précédent).
        try fm.createDirectory(at: URL(fileURLWithPath: gameDir)
            .appendingPathComponent("Mods/.Clash"), withIntermediateDirectories: true)
        let defaults = makeDefaults()
        var warnings: [String] = []
        migrate(gameDir, defaults: defaults) { message, _ in warnings.append(message) }
        let mods = gameDir + "/Mods"
        #expect(fm.fileExists(atPath: mods + "/.Clash"))               // l'existant intact
        let moved = try fm.contentsOfDirectory(atPath: mods).filter { $0.hasPrefix(".Clash_") }
        #expect(moved.count == 1)                                       // le déplacé, suffixé
        #expect(warnings.contains { $0.contains("collision") })
    }

    /// Un dossier illisible : aucun déplacement, et **le drapeau reste
    /// levé** — c'est ce qui fait réessayer au prochain lancement.
    @Test func unreadableLegacyFolderDoesNotSetFlag() throws {
        let gameDir = try makeGameDir()
        let disabled = try makeDisabledDir(in: gameDir, entries: ["Hidden"])
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: disabled)
        let defaults = makeDefaults()
        migrate(gameDir, defaults: defaults)
        #expect(!defaults.bool(forKey: UDKey.disabledModsMigratedToDotPrefix))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: disabled)
    }

    /// Un fichier perdu à la racine de `Mods_disabled/` n'est pas un mod :
    /// laissé en place, signalé, et le dossier survit.
    @Test func strayFileIsLeftAndReported() throws {
        let gameDir = try makeGameDir()
        let disabled = try makeDisabledDir(in: gameDir, entries: [])
        try "stray".write(toFile: (disabled as NSString).appendingPathComponent("loose.txt"),
                          atomically: true, encoding: .utf8)
        let defaults = makeDefaults()
        var warnings: [String] = []
        migrate(gameDir, defaults: defaults) { message, _ in warnings.append(message) }
        #expect(fm.fileExists(atPath: (disabled as NSString).appendingPathComponent("loose.txt")))
        #expect(warnings.contains { $0.contains("still contains") })
        #expect(defaults.bool(forKey: UDKey.disabledModsMigratedToDotPrefix))
    }
}
