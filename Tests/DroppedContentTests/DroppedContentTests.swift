import Testing
import Foundation
@testable import StarHubTHCore

/// Reconnaître un fichier qui n'est pas un mod mais du contenu destiné au
/// dossier d'un autre mod.
///
/// Cas d'origine : `Cloth And Colors Bag` (Nexus 50108), une archive de 1,4 Ko
/// contenant un unique JSON de sac ItemBags, sans `manifest.json`. Le refuser
/// comme mod était juste ; laisser l'utilisateur sans destination ne l'était pas.
struct DroppedContentRecognizerTests {
    /// Les clés d'un vrai fichier de sac, relevées sur
    /// `assets/Modded Bags/Samples/Aquilegia.SweetTooth.json`.
    private let realBagKeys: Set<String> = [
        "IsEnabled", "ModUniqueId", "BagId", "BagName", "BagDescription",
        "IconTexture", "IconPosition", "Prices", "Capacities", "SizeSellers",
        "SizeMenuOptions",
    ]

    @Test func aRealItemBagsFileIsRecognized() {
        let rule = DroppedContentRecognizer.rule(forJSONKeys: realBagKeys)
        #expect(rule?.hostUniqueId == "SlayerDharok.Item_Bags")
        #expect(rule?.destinationSubpath == "assets/Modded Bags")
    }

    @Test func aPartialSignatureIsNotEnough() {
        // Sans quoi n'importe quel JSON portant un champ `Prices` serait
        // expédié dans le dossier d'ItemBags.
        #expect(DroppedContentRecognizer.rule(forJSONKeys: ["Prices", "BagName"]) == nil)
    }

    @Test func anOrdinaryJsonIsNotRecognized() {
        #expect(DroppedContentRecognizer.rule(forJSONKeys: ["Name", "Author", "Version"]) == nil)
    }

    @Test func aModManifestIsNotRecognized() {
        // Un manifeste passe par le chemin normal d'installation, jamais ici.
        #expect(DroppedContentRecognizer.rule(
            forJSONKeys: ["Name", "UniqueID", "Version", "Author", "Description"]) == nil)
    }

    @Test func extraKeysDoNotPreventRecognition() {
        // La signature est un sous-ensemble requis : un auteur peut ajouter un
        // champ sans que le fichier cesse d'être un sac.
        var keys = realBagKeys
        keys.insert("SomeFutureField")
        #expect(DroppedContentRecognizer.rule(forJSONKeys: keys) != nil)
    }
}

/// Le nom de fichier vient de l'archive, donc d'une source non fiable.
struct DroppedContentFileNameTests {
    @Test func anOrdinaryNameIsKept() {
        #expect(DroppedContentRecognizer.safeFileName(from: "Cloth and Colors Bag.json")
                == "Cloth and Colors Bag.json")
    }

    @Test func aTraversalAttemptIsRefusedNotSanitized() {
        // Refuser, pas réduire en silence : une archive qui tente d'écrire
        // ailleurs est un signal, pas une coquille à corriger pour elle.
        #expect(DroppedContentRecognizer.safeFileName(from: "../../evil.json") == nil)
        #expect(DroppedContentRecognizer.safeFileName(from: "a/b.json") == nil)
        #expect(DroppedContentRecognizer.safeFileName(from: "..") == nil)
    }

    @Test func anEmptyOrHiddenNameIsRefused() {
        #expect(DroppedContentRecognizer.safeFileName(from: "") == nil)
        #expect(DroppedContentRecognizer.safeFileName(from: "   ") == nil)
        #expect(DroppedContentRecognizer.safeFileName(from: ".DS_Store") == nil)
    }
}

/// Où le fichier doit atterrir, selon l'état du mod hôte.
struct DroppedContentDestinationTests {
    private func rule() -> DroppedContentRule {
        DroppedContentRecognizer.rules[0]
    }

    private func host(folderName: String, enabled: Bool) -> ModItem {
        ModItem(uniqueId: "SlayerDharok.Item_Bags", name: "Item Bags",
                folderName: folderName, version: "3.1.0", author: "SlayerDharok",
                description: "", nexusUrl: "", nexusModId: "", isEnabled: enabled,
                dependencies: [], children: nil, isGroup: false, installedFileDate: nil)
    }

    @Test func anActiveHostGivesItsOwnFolder() {
        let result = DroppedContentRecognizer.destination(
            for: rule(), fileName: "Bag.json",
            installedMods: [host(folderName: "ItemBags", enabled: true)],
            gameDir: "/Game")
        #expect(result == .ready(URL(fileURLWithPath:
            "/Game/Mods/ItemBags/assets/Modded Bags/Bag.json"), hostIsPaused: false))
    }

    @Test func aPausedHostKeepsItsDottedFolder() {
        // Convention du fork : un mod en pause est un dossier préfixé d'un point
        // resté dans `Mods/`. Écrire dans `ItemBags/` créerait un dossier
        // fantôme à côté du vrai.
        let result = DroppedContentRecognizer.destination(
            for: rule(), fileName: "Bag.json",
            installedMods: [host(folderName: "ItemBags", enabled: false)],
            gameDir: "/Game")
        #expect(result == .ready(URL(fileURLWithPath:
            "/Game/Mods/.ItemBags/assets/Modded Bags/Bag.json"), hostIsPaused: true))
    }

    @Test func anAbsentHostIsNamedRatherThanCreated() {
        let result = DroppedContentRecognizer.destination(
            for: rule(), fileName: "Bag.json", installedMods: [], gameDir: "/Game")
        #expect(result == .hostMissing(hostDisplayName: rule().hostDisplayName))
    }

    @Test func theHostIsMatchedIgnoringCase() {
        // SMAPI compare les `UniqueID` sans égard à la casse ; deux auteurs
        // n'écrivent pas le même identifiant de la même façon.
        let oddCase = ModItem(uniqueId: "slayerdharok.item_bags", name: "Item Bags",
                              folderName: "ItemBags", version: "3.1.0", author: "",
                              description: "", nexusUrl: "", nexusModId: "",
                              isEnabled: true, dependencies: [], children: nil,
                              isGroup: false, installedFileDate: nil)
        let result = DroppedContentRecognizer.destination(
            for: rule(), fileName: "Bag.json", installedMods: [oddCase], gameDir: "/Game")
        #expect(result == .ready(URL(fileURLWithPath:
            "/Game/Mods/ItemBags/assets/Modded Bags/Bag.json"), hostIsPaused: false))
    }

    @Test func aRefusedFileNameYieldsNoDestinationForTraversal() {
        let result = DroppedContentRecognizer.destination(
            for: rule(), fileName: "../evil.json",
            installedMods: [host(folderName: "ItemBags", enabled: true)],
            gameDir: "/Game")
        #expect(result == .unusableFileName)
    }
}

/// La reconnaissance sur une archive réellement extraite.
struct DroppedContentScanTests {
    /// Un dossier extrait jetable. `cleanup()` via `defer`, comme les autres
    /// suites qui touchent le disque.
    private struct Extracted {
        let directory: URL
        init(files: [String: String]) throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("dropped-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, content) in files {
                try Data(content.utf8).write(to: directory.appendingPathComponent(name))
            }
        }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }

    private let bagJSON = """
    {"IsEnabled": true, "ModUniqueId": "selph.textileexpansion", "BagId": "x",
     "BagName": "Cloth and Colors Bag", "Prices": {}, "Capacities": {}, "SizeSellers": {}}
    """

    @Test func aBagFileAtTheRootIsFound() throws {
        let extracted = try Extracted(files: ["Cloth and Colors Bag.json": bagJSON])
        defer { extracted.cleanup() }
        let found = DroppedContentRecognizer.recognize(inExtractedDirectory: extracted.directory)
        #expect(found?.rule.hostUniqueId == "SlayerDharok.Item_Bags")
        #expect(found?.fileURL.lastPathComponent == "Cloth and Colors Bag.json")
    }

    @Test func anArchiveOfOrdinaryJsonIsNotRecognized() throws {
        let extracted = try Extracted(files: ["data.json": #"{"a": 1}"#])
        defer { extracted.cleanup() }
        #expect(DroppedContentRecognizer.recognize(inExtractedDirectory: extracted.directory) == nil)
    }

    @Test func anUnparsableJsonDoesNotCrashTheScan() throws {
        let extracted = try Extracted(files: ["broken.json": "{not json"])
        defer { extracted.cleanup() }
        #expect(DroppedContentRecognizer.recognize(inExtractedDirectory: extracted.directory) == nil)
    }

    @Test func anEmptyDirectoryIsNotRecognized() throws {
        let extracted = try Extracted(files: [:])
        defer { extracted.cleanup() }
        #expect(DroppedContentRecognizer.recognize(inExtractedDirectory: extracted.directory) == nil)
    }
}

/// L'écriture elle-même.
struct DroppedContentInstallTests {
    private func makeSandbox() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropped-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func writingCreatesMissingParentDirectories() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let source = sandbox.appendingPathComponent("Bag.json")
        try Data(#"{"BagName": "x"}"#.utf8).write(to: source)
        // `assets/Modded Bags/` n'existe pas encore : un hôte fraîchement
        // installé peut ne pas avoir le sous-dossier.
        let destination = sandbox.appendingPathComponent("Host/assets/Modded Bags/Bag.json")

        try DroppedContentRecognizer.install(from: source, to: destination)

        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(try String(contentsOf: destination, encoding: .utf8) == #"{"BagName": "x"}"#)
    }

    @Test func writingReplacesAnExistingFile() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let source = sandbox.appendingPathComponent("Bag.json")
        try Data("neuf".utf8).write(to: source)
        let destination = sandbox.appendingPathComponent("Host/Bag.json")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("ancien".utf8).write(to: destination)

        try DroppedContentRecognizer.install(from: source, to: destination)

        #expect(try String(contentsOf: destination, encoding: .utf8) == "neuf")
    }
}

/// Défense en profondeur : la destination doit rester sous le dossier de l'hôte,
/// vérifié après construction du chemin et non seulement sur le nom.
struct DroppedContentContainmentTests {
    @Test func aDestinationEscapingTheHostFolderIsRefused() {
        // Le sous-dossier d'une règle est une donnée de notre table, pas une
        // entrée utilisateur — mais la vérification ne coûte rien et fermerait
        // la porte si une règle future était mal écrite.
        let escaping = DroppedContentRule(
            requiredKeys: ["X"], hostUniqueId: "host.id",
            destinationSubpath: "../../..", hostDisplayName: "Host")
        let host = ModItem(uniqueId: "host.id", name: "Host", folderName: "Host",
                           version: "1.0.0", author: "", description: "", nexusUrl: "",
                           nexusModId: "", isEnabled: true, dependencies: [],
                           children: nil, isGroup: false, installedFileDate: nil)
        let result = DroppedContentRecognizer.destination(
            for: escaping, fileName: "Bag.json", installedMods: [host], gameDir: "/Game")
        #expect(result == .unusableFileName)
    }
}

/// De bout en bout : une archive extraite, un hôte en pause, le fichier écrit
/// au bon endroit. C'est le parcours que l'utilisateur déclenche.
struct DroppedContentEndToEndTests {
    @Test func aBagLandsInsideAPausedHost() throws {
        let gameDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("e2e-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: gameDir) }

        // L'hôte, en pause : dossier préfixé d'un point, convention du fork.
        let hostFolder = gameDir.appendingPathComponent("Mods/.ItemBags")
        try FileManager.default.createDirectory(at: hostFolder, withIntermediateDirectories: true)

        // L'archive extraite : un unique JSON de sac, sans manifeste.
        let extracted = gameDir.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try Data("""
        {"IsEnabled": true, "ModUniqueId": "selph.textileexpansion", "BagId": "b",
         "BagName": "Cloth and Colors Bag", "Prices": {}, "Capacities": {}, "SizeSellers": {}}
        """.utf8).write(to: extracted.appendingPathComponent("Cloth and Colors Bag.json"))

        let host = ModItem(uniqueId: "SlayerDharok.Item_Bags", name: "Item Bags",
                           folderName: "ItemBags", version: "3.1.0", author: "",
                           description: "", nexusUrl: "", nexusModId: "", isEnabled: false,
                           dependencies: [], children: nil, isGroup: false,
                           installedFileDate: nil)

        let found = try #require(DroppedContentRecognizer.recognize(inExtractedDirectory: extracted))
        let destination = DroppedContentRecognizer.destination(
            for: found.rule, fileName: found.fileURL.lastPathComponent,
            installedMods: [host], gameDir: gameDir.path)
        guard case .ready(let url, let paused) = destination else {
            Issue.record("destination inattendue : \(destination)")
            return
        }
        #expect(paused)
        try DroppedContentRecognizer.install(from: found.fileURL, to: url)

        let written = hostFolder.appendingPathComponent("assets/Modded Bags/Cloth and Colors Bag.json")
        #expect(FileManager.default.fileExists(atPath: written.path))
        // Et surtout : rien n'a été créé dans un `ItemBags` sans point.
        #expect(!FileManager.default.fileExists(
            atPath: gameDir.appendingPathComponent("Mods/ItemBags").path))
    }
}

/// La sauvegarde promise avant écrasement — sur un hôte **en pause**, où le
/// dossier réel porte un point que `folderName` n'a pas.
struct DroppedContentBackupTests {
    @Test func overwritingAPausedHostBacksItUpFirst() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropped-backup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let gameDir = root.appendingPathComponent("Game")
        let bagsDir = gameDir.appendingPathComponent("Mods/.ItemBags/assets/Modded Bags")
        try FileManager.default.createDirectory(at: bagsDir, withIntermediateDirectories: true)
        // Le fichier déjà présent, retouché à la main — c'est lui qu'on doit
        // pouvoir retrouver après coup.
        let existing = bagsDir.appendingPathComponent("Bag.json")
        try Data("réglages personnalisés".utf8).write(to: existing)

        let host = ModItem(uniqueId: "SlayerDharok.Item_Bags", name: "Item Bags",
                           folderName: "ItemBags", version: "3.1.0", author: "",
                           description: "", nexusUrl: "", nexusModId: "", isEnabled: false,
                           dependencies: [], children: nil, isGroup: false,
                           installedFileDate: nil)

        let manager = ModInstallBackupManager(backupsBasePath: root.appendingPathComponent("Backups"))
        // `createBackup` résout le dossier par `physicalFolderName`, qui ajoute
        // le point : sans cela il lèverait `modNotFound` sur un hôte en pause.
        let backup = try manager.createBackup(for: host, gameDir: gameDir.path,
                                              reason: .beforeInstall)

        let saved = URL(fileURLWithPath: backup.backupPath)
            .appendingPathComponent("assets/Modded Bags/Bag.json")
        #expect(FileManager.default.fileExists(atPath: saved.path))
        #expect(try String(contentsOf: saved, encoding: .utf8) == "réglages personnalisés")
    }
}

/// Ces fichiers sont écrits à la main par des auteurs de mods, exactement comme
/// les fichiers i18n — et ils portent les mêmes tolérances.
struct DroppedContentLenientParsingTests {
    private func extracted(_ content: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lenient-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(content.utf8).write(to: dir.appendingPathComponent("Bag.json"))
        return dir
    }

    @Test func aBagFileWithCommentsIsStillRecognized() throws {
        // Cas réel : `Cloth And Colors Bag` (Nexus 50108) porte un
        // `//Special Items` au milieu de sa liste d'objets. `JSONSerialization`
        // le refuse ; le fichier n'en est pas moins un sac parfaitement
        // ordinaire, et ItemBags le charge.
        let dir = try extracted("""
        {
          "BagId": "b", "BagName": "Cloth and Colors Bag",
          "Prices": {}, "Capacities": {},
          "SizeSellers": {},
          "Items": [
            {"Name": "Cloth"},
            //Special Items
            {"Name": "Linen"}
          ]
        }
        """)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(DroppedContentRecognizer.recognize(inExtractedDirectory: dir) != nil)
    }

    @Test func aBagFileWithATrailingCommaIsStillRecognized() throws {
        let dir = try extracted("""
        {"BagId": "b", "BagName": "x", "Prices": {}, "Capacities": {}, "SizeSellers": {},}
        """)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(DroppedContentRecognizer.recognize(inExtractedDirectory: dir) != nil)
    }

    @Test func trulyBrokenJsonIsStillRefused() throws {
        let dir = try extracted("{not json at all")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(DroppedContentRecognizer.recognize(inExtractedDirectory: dir) == nil)
    }
}
