import Foundation
import Testing
@testable import StarHubTHCore

/// Le balayage de `Mods/` (REFACTORING §6, domaine Scan, tranche 1) :
/// classification des entrées, lecture des manifestes, préfixe point,
/// groupement des packs, cache mtime et sa course.
///
/// Tous les arbres vivent dans des dossiers temporaires — qui, sur macOS,
/// sont déjà derrière le symlink `/var/folders` → `/private/var/folders` :
/// la résolution de symlinks du chemin relatif canonique est donc exercée
/// par **tous** les essais sans le vouloir.
@Suite struct ModScannerTests {

    private let fm = FileManager.default

    private func makeGameDir() throws -> String {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root.appendingPathComponent("Mods"),
                               withIntermediateDirectories: true)
        return root.path
    }

    @discardableResult
    private func makeMod(in modsPath: String, name: String,
                         manifest: String? = nil, disabled: Bool = false) throws -> String {
        let leaf = disabled ? "." + name : name
        let dir = URL(fileURLWithPath: modsPath).appendingPathComponent(leaf)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let manifest {
            try manifest.write(to: dir.appendingPathComponent("manifest.json"),
                               atomically: true, encoding: .utf8)
        }
        return dir.path
    }

    private let fullManifest = """
    {
        "Name": "Cheats Menu",
        "Description": "In-game cheats menu",
        "Author": "CJBok",
        "Version": "1.2.3",
        "UniqueID": "CJB.CheatsMenu",
        "UpdateKeys": ["Nexus:914"]
    }
    """

    private func scan(_ gameDir: String,
                      installedModDate: ((String) -> Date?)? = nil,
                      log: ((String) -> Void)? = nil) throws -> ModScanner.Outcome {
        var logged: [String] = []
        let scanner = ModScanner()
        return scanner.scan(
            gameDir: gameDir,
            installedModDate: installedModDate ?? { _ in nil },
            onProgress: { _ in },
            log: log ?? { logged.append($0) }
        )
    }

    // MARK: - Classification des entrées

    @Test func readsManifestFields() throws {
        let gameDir = try makeGameDir()
        try makeMod(in: gameDir + "/Mods", name: "CheatsMenu", manifest: fullManifest)
        let outcome = try scan(gameDir)
        #expect(outcome.mods.count == 1)
        let mod = try #require(outcome.mods.first)
        #expect(mod.folderName == "CheatsMenu")
        #expect(mod.name == "Cheats Menu")
        #expect(mod.uniqueId == "CJB.CheatsMenu")
        #expect(mod.version == "1.2.3")
        #expect(mod.author == "CJBok")
        #expect(mod.isEnabled)
    }

    /// Un mod en pause vit dans `Mods/.X` : le nom **logique** ne porte
    /// jamais le point (clé du registre, des profils, des ancres).
    @Test func disabledModStripsDotPrefix() throws {
        let gameDir = try makeGameDir()
        try makeMod(in: gameDir + "/Mods", name: "CheatsMenu",
                    manifest: fullManifest, disabled: true)
        let outcome = try scan(gameDir)
        let mod = try #require(outcome.mods.first)
        #expect(mod.folderName == "CheatsMenu")
        #expect(!mod.isEnabled)
    }

    /// Un dossier sans manifeste n'est pas un mod.
    @Test func folderWithoutManifestIsSkipped() throws {
        let gameDir = try makeGameDir()
        try makeMod(in: gameDir + "/Mods", name: "NotAMod")
        let outcome = try scan(gameDir)
        #expect(outcome.mods.isEmpty)
    }

    /// Le repli du nom : un manifeste sans `Name` affiche le nom logique du
    /// dossier, jamais `.X` pour un mod en pause ; version par défaut.
    @Test func missingNameFallsBackToLogicalLeaf() throws {
        let gameDir = try makeGameDir()
        try makeMod(in: gameDir + "/Mods", name: "Bare",
                    manifest: "{ \"UniqueID\": \"some.Mod\" }", disabled: true)
        let outcome = try scan(gameDir)
        let mod = try #require(outcome.mods.first)
        #expect(mod.name == "Bare")
        #expect(mod.version == "Unknown")
        #expect(mod.uniqueId == "some.Mod")
    }

    /// Un manifeste mal formé garde les valeurs par défaut mais crie —
    /// l'utilisateur doit comprendre pourquoi les métadonnées sont vides.
    @Test func invalidManifestWarnsAndUsesDefaults() throws {
        let gameDir = try makeGameDir()
        var logged: [String] = []
        try makeMod(in: gameDir + "/Mods", name: "Broken",
                    manifest: "{ not json at all")
        let outcome = try scan(gameDir) { logged.append($0) }
        let mod = try #require(outcome.mods.first)
        #expect(mod.name == "Broken")
        #expect(mod.version == "Unknown")
        #expect(logged.contains { $0.hasPrefix("Manifest invalide pour Broken") })
    }

    /// Un pack (plusieurs manifestes sous un dossier) devient une entrée
    /// groupée ; les enfants portent le chemin relatif `Pack/Enfant`.
    @Test func packBecomesGroupWithRelativeChildPaths() throws {
        let gameDir = try makeGameDir()
        let pack = gameDir + "/Mods/MyPack"
        try makeMod(in: pack, name: "Part1", manifest: fullManifest)
        try makeMod(in: pack, name: "Part2",
                    manifest: "{ \"Name\": \"Part Two\", \"UniqueID\": \"pack.Part2\" }")
        let outcome = try scan(gameDir)
        let group = try #require(outcome.mods.first)
        #expect(group.isGroup)
        #expect(group.folderName == "MyPack")
        #expect(group.children?.count == 2)
        // L'ordre d'énumération du système de fichiers n'est pas garanti.
        #expect(Set(group.children?.map(\.folderName) ?? []) == ["MyPack/Part1", "MyPack/Part2"])
    }

    /// Les résidus système et les corbeilles de réparation ne sont pas des
    /// mods — ni dans la liste, ni dans la détection de doublons.
    @Test func junkAndTrashEntriesAreSkipped() throws {
        let gameDir = try makeGameDir()
        let modsPath = gameDir + "/Mods"
        try fm.createDirectory(at: URL(fileURLWithPath: modsPath).appendingPathComponent(".DS_Store"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: URL(fileURLWithPath: modsPath)
            .appendingPathComponent(ModFolderRepairer.trashPrefix + "20260910"),
                               withIntermediateDirectories: true)
        try makeMod(in: modsPath, name: "Real", manifest: fullManifest)
        let outcome = try scan(gameDir)
        #expect(outcome.mods.count == 1)
        #expect(outcome.mods.first?.folderName == "Real")
    }

    /// « Rien vu » n'est pas « rien installé » (X71) : un `Mods/` absent ou
    /// illisible rend un lot vide **et** le dit, pour que les purges de fin
    /// de passe se suspendent au lieu d'effacer le registre.
    @Test func unreadableModsFolderIsReported() throws {
        // Pas de Mods/ du tout — makeGameDir en crée un, on construit nu.
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let outcome = try scan(root.path)
        #expect(outcome.mods.isEmpty)
        #expect(!outcome.modsFolderWasReadable)
    }

    // MARK: - Cache mtime

    /// Le cache sert la valeur **stale** tant que le mtime ne bouge pas —
    /// c'est lui le contrat : un rescan à rien ne re-décode rien.
    @Test func cacheServesStaleManifestWhileMtimeUnchanged() throws {
        let gameDir = try makeGameDir()
        let modsPath = gameDir + "/Mods"
        let dir = try makeMod(in: modsPath, name: "Cached")
        let manifestURL = URL(fileURLWithPath: dir).appendingPathComponent("manifest.json")
        try "{ \"Name\": \"V1\", \"UniqueID\": \"cache.V1\" }".write(to: manifestURL, atomically: true, encoding: .utf8)
        let scanner = ModScanner()
        var calls = 0
        func run() throws -> ModItem {
            calls += 1
            let outcome = scanner.scan(gameDir: gameDir, installedModDate: { _ in nil },
                                       onProgress: { _ in }, log: { _ in })
            return try #require(outcome.mods.first)
        }
        // Réchauffe le cache : premier balayage, manifeste lisible.
        #expect(try run().name == "V1")
        // Contenu rendu illisible sans toucher au mtime. Pas de
        // setAttributes de date ici : deux Date passees par setAttributes
        // ne sont plus `==` (piege CLAUDE.md) et le faux cache-miss aurait
        // teste notre outillage, pas le cache. Le stat reste permis a
        // 0o000, le hit sert donc la valeur stale bien que le fichier soit
        // illisible - c'est exactement "zero re-decodage".
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: manifestURL.path)
        let probe = try run()
        #expect(probe.name == "V1")

        // Lisible a nouveau, contenu different -> le mtime a bouge, le
        // cache rend la main.
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: manifestURL.path)
        try "{ \"Name\": \"V2\", \"UniqueID\": \"cache.V2\" }".write(to: manifestURL, atomically: true, encoding: .utf8)
        #expect(try run().name == "V2")
        #expect(calls == 3)
    }

    /// La régression de juillet 2026 : deux balayages concurrents sur la
    /// même instance — le subscript du cache sans verrou y perdait un
    /// `EXC_BAD_ACCESS`. L'instance est volontairement **partagée**.
    @Test func concurrentScansOnSharedInstanceDoNotRace() throws {
        let gameDir = try makeGameDir()
        let modsPath = gameDir + "/Mods"
        for i in 0..<12 {
            try makeMod(in: modsPath, name: "Mod\(i)",
                        manifest: "{ \"Name\": \"M\(i)\", \"UniqueID\": \"race.\(i)\" }")
        }
        let scanner = ModScanner()
        let queue = DispatchQueue.global(qos: .userInitiated)
        let group = DispatchGroup()
        let lock = NSLock()
        var totals: [Int] = []
        for _ in 0..<4 {
            group.enter()
            queue.async {
                for _ in 0..<5 {
                    let outcome = scanner.scan(gameDir: gameDir, installedModDate: { _ in nil },
                                               onProgress: { _ in }, log: { _ in })
                    lock.lock()
                    totals.append(outcome.mods.count)
                    lock.unlock()
                }
                group.leave()
            }
        }
        #expect(group.wait(timeout: .now() + 30) == .success)
        #expect(totals == Array(repeating: 12, count: 20))
    }

    // MARK: - Date d'installation

    /// La date du registre gagne sur le mtime du dossier — c'est elle qui
    /// survit à une copie qui préservait la date d'empaquetage.
    @Test func registryDateWinsOverFolderMtime() throws {
        let gameDir = try makeGameDir()
        try makeMod(in: gameDir + "/Mods", name: "Dated", manifest: fullManifest)
        let registry = Date(timeIntervalSince1970: 1_700_000_000)
        let outcome = try scan(gameDir, installedModDate: { folder in
            folder == "Dated" ? registry : nil
        })
        #expect(outcome.mods.first?.installedFileDate == registry)
    }
}
