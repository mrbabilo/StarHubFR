import Testing
import Foundation
@testable import StarHubTHCore

struct ModsFolderSizerTests {
    /// Construit un `Mods/` jetable : `[nom de dossier: [nom de fichier: octets]]`.
    private func makeModsFolder(_ layout: [String: [String: Int]]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sizer-\(UUID().uuidString)/Mods")
        for (folder, files) in layout {
            let dir = root.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (name, bytes) in files {
                try Data(repeating: 0x41, count: bytes)
                    .write(to: dir.appendingPathComponent(name))
            }
        }
        return root
    }

    @Test func aModFolderIsWeighedUnderItsOnDiskName() throws {
        let root = try makeModsFolder(["SpaceCore": ["manifest.json": 400, "SpaceCore.dll": 600]])
        let sizes = try #require(ModsFolderSizer.measure(modsFolder: root))
        // La place allouée arrondit au bloc : ce qui compte est qu'elle couvre
        // les octets écrits et reste dans un ordre de grandeur crédible.
        let bytes = try #require(sizes.bytes(forPhysicalFolder: "SpaceCore"))
        #expect(bytes >= 1000)
        #expect(sizes.totalBytes == bytes)
    }

    /// **Le défaut que cette mesure devait éviter.** Un mod en pause est un
    /// dossier préfixé d'un point ; sa clé est donc `.Foo`, pas `Foo`. Sur le
    /// parc réel, cinq des huit plus gros mods sont en pause : les joindre sur
    /// le nom logique les afficherait tous à 0 octet.
    @Test func aPausedModIsKeyedUnderItsDottedName() throws {
        let root = try makeModsFolder([".SexyCombatIdols": ["big.png": 5000]])
        let sizes = try #require(ModsFolderSizer.measure(modsFolder: root))
        #expect(sizes.bytes(forPhysicalFolder: ".SexyCombatIdols") != nil)
        #expect(sizes.bytes(forPhysicalFolder: "SexyCombatIdols") == nil)
    }

    /// `.skipsHiddenFiles` sauterait le dossier entier : le poids des mods en
    /// pause disparaîtrait de la mesure sans un chiffre pour le signaler.
    @Test func pausedModsCountInTheTotalAndInTheirOwnSubtotal() throws {
        let root = try makeModsFolder([
            "Active": ["a.dat": 2000],
            ".Paused": ["b.dat": 8000],
        ])
        let sizes = try #require(ModsFolderSizer.measure(modsFolder: root))
        let active = try #require(sizes.bytes(forPhysicalFolder: "Active"))
        let paused = try #require(sizes.bytes(forPhysicalFolder: ".Paused"))
        #expect(sizes.totalBytes == active + paused)
        #expect(sizes.pausedBytes == paused)
        #expect(sizes.pausedBytes > 0)
    }

    @Test func withoutAnyPausedModTheSubtotalIsZero() throws {
        let root = try makeModsFolder(["Active": ["a.dat": 100]])
        let sizes = try #require(ModsFolderSizer.measure(modsFolder: root))
        #expect(sizes.pausedBytes == 0)
    }

    /// `.Spotlight-V100` commence par un point sans être un mod en pause :
    /// sans ce filtre, son poids gonflerait le sous-total « en pause ».
    @Test func systemLitterIsNotAPausedMod() throws {
        let root = try makeModsFolder([
            "Active": ["a.dat": 100],
            ".Spotlight-V100": ["index": 9000],
            "__MACOSX": ["junk": 9000],
        ])
        let sizes = try #require(ModsFolderSizer.measure(modsFolder: root))
        #expect(sizes.bytes(forPhysicalFolder: ".Spotlight-V100") == nil)
        #expect(sizes.bytes(forPhysicalFolder: "__MACOSX") == nil)
        #expect(sizes.pausedBytes == 0)
        #expect(sizes.totalBytes == sizes.bytes(forPhysicalFolder: "Active"))
    }

    /// Les sous-dossiers comptent : un mod range ses assets en profondeur.
    @Test func nestedFilesAreCounted() throws {
        let root = try makeModsFolder(["Deep": ["top.dat": 100]])
        let nested = root.appendingPathComponent("Deep/assets/portraits")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 4000).write(to: nested.appendingPathComponent("abigail.png"))
        let sizes = try #require(ModsFolderSizer.measure(modsFolder: root))
        #expect(try #require(sizes.bytes(forPhysicalFolder: "Deep")) >= 4100)
    }

    /// Un composant de pack n'a pas de clé à lui : son `physicalFolderName`
    /// porte un `/`. Afficher le poids du pack sur chacun de ses composants
    /// compterait la même place autant de fois qu'il y en a.
    @Test func aPackIsWeighedOnceOnItsTopLevelFolder() throws {
        let root = try makeModsFolder([
            "SVE/SVE Core": ["manifest.json": 1000],
            "SVE/SVE Extras": ["manifest.json": 1000],
        ])
        let sizes = try #require(ModsFolderSizer.measure(modsFolder: root))
        #expect(sizes.bytes(forPhysicalFolder: "SVE/SVE Core") == nil)
        let pack = try #require(sizes.bytes(forPhysicalFolder: "SVE"))
        #expect(sizes.totalBytes == pack)
    }

    /// Un fichier isolé posé à la racine de `Mods/` n'est pas un mod.
    @Test func aLooseFileAtTheRootIsNotWeighed() throws {
        let root = try makeModsFolder(["Active": ["a.dat": 100]])
        try Data(repeating: 0x43, count: 7000).write(to: root.appendingPathComponent("notes.txt"))
        let sizes = try #require(ModsFolderSizer.measure(modsFolder: root))
        #expect(sizes.byPhysicalFolder.keys.sorted() == ["Active"])
    }

    /// Mieux vaut ne rien afficher qu'annoncer « 0 octet » à qui n'a pas
    /// encore désigné son jeu.
    @Test func anAbsentFolderIsNotAMeasurementOfZero() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nowhere-\(UUID().uuidString)")
        #expect(ModsFolderSizer.measure(modsFolder: missing) == nil)
    }

    @Test func anEmptyModsFolderWeighsNothingButIsStillAMeasurement() throws {
        let root = try makeModsFolder([:])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sizes = try #require(ModsFolderSizer.measure(modsFolder: root))
        #expect(sizes.totalBytes == 0)
        #expect(sizes.byPhysicalFolder.isEmpty)
    }

    /// L'espace libre est celui du volume qui porte `Mods/`, pas celui de `/` :
    /// le jeu peut vivre sur un disque externe.
    @Test func freeSpaceIsReadFromTheVolumeHoldingTheFolder() throws {
        let root = try makeModsFolder(["Active": ["a.dat": 100]])
        let sizes = try #require(ModsFolderSizer.measure(modsFolder: root))
        #expect(try #require(sizes.availableBytes) > 0)
        #expect(sizes.availableBytes == ModsFolderSizer.availableBytes(on: root))
    }
}
