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
