import Testing
import Foundation
@testable import StarHubTHCore

/// Le magasin ne décode jamais un `config.json` : il en mémorise le **texte**.
/// C'est ce qui préserve l'ordre des clés — SMAPI écrit dans l'ordre des champs
/// de sa classe C#, et un aller-retour par `JSONSerialization` le mélangerait.
struct ProfileConfigStoreTests {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 2_000_000)

    @Test func capturingRecordsTheTextVerbatim() {
        // Clés volontairement dans le désordre alphabétique : c'est l'ordre de
        // SMAPI, et il doit ressortir tel quel.
        let text = "{\n  \"Zoom\": 1,\n  \"Alpha\": false\n}"
        let after = ProfileConfigStore.captured([:], folderName: "TractorMod",
                                                diskText: text, now: t0)
        #expect(after["TractorMod"]?.text == text)
        #expect(after["TractorMod"]?.capturedAt == t0)
    }

    @Test func anAbsentConfigRemovesTheEntry() {
        // Le bouton « Repartir des réglages par défaut » supprime le fichier.
        // Sans cette règle, revenir au profil le ferait ressusciter — le geste
        // le plus explicite de l'utilisateur serait annulé par le mécanisme.
        let before = ["TractorMod": ProfileConfigEntry(text: "{}", capturedAt: t0)]
        let after = ProfileConfigStore.captured(before, folderName: "TractorMod",
                                                diskText: nil, now: t1)
        #expect(after["TractorMod"] == nil)
    }

    @Test func anIdenticalCaptureLeavesTheDateAlone() {
        // Rafraîchir la date pour une capture qui n'a rien changé afficherait
        // de l'activité là où il n'y en a pas.
        let text = "{\n  \"A\": 1\n}"
        let before = ["ItemBags": ProfileConfigEntry(text: text, capturedAt: t0)]
        let after = ProfileConfigStore.captured(before, folderName: "ItemBags",
                                                diskText: text, now: t1)
        #expect(after["ItemBags"]?.capturedAt == t0)
    }

    @Test func crlfSurvivesTheStore() {
        // 9 configs du parc réel sont en CRLF. Normaliser les fins de ligne
        // serait réécrire un fichier qu'on n'a pas à toucher.
        let text = "{\r\n  \"A\": 1\r\n}"
        let after = ProfileConfigStore.captured([:], folderName: "M",
                                                diskText: text, now: t0)
        #expect(after["M"]?.text == text)
        #expect(after["M"]?.text.contains("\r\n") == true)
    }

    @Test func unparseableJSONIsStoredAnyway() {
        // Mesuré : 2 configs du parc ne se parsent pas, même en tolérant
        // commentaires et virgules traînantes. Le magasin ne parse rien, donc
        // il les avale.
        let broken = "{ \"A\": 1, oops }"
        let after = ProfileConfigStore.captured([:], folderName: "MS-Books",
                                                diskText: broken, now: t0)
        #expect(after["MS-Books"]?.text == broken)
    }

    @Test func saveThenLoadRoundTripsWithoutTouchingOrder() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("p.json")

        let text = "{\n  \"Zoom\": 1,\n  \"Alpha\": false\n}"
        ProfileConfigStore.save(["M": ProfileConfigEntry(text: text, capturedAt: t0)], to: url)
        let back = ProfileConfigStore.load(from: url, fileManager: .default)
        #expect(back["M"]?.text == text)
    }

    @Test func loadingAMissingFileGivesAnEmptyStore() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).json")
        #expect(ProfileConfigStore.load(from: url, fileManager: .default).isEmpty)
    }

    @Test func loadingATruncatedFileGivesAnEmptyStore() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("p.json")
        try Data("{ not json".utf8).write(to: url)
        #expect(ProfileConfigStore.load(from: url, fileManager: .default).isEmpty)
    }

    @Test func theConfigURLUsesThePhysicalFolderName() {
        // Un mod en pause vit dans un dossier préfixé par un point. La clé du
        // magasin est le nom *logique* ; le chemin sur disque, lui, est le nom
        // *physique*. Les confondre écrirait à côté.
        let url = ProfileConfigStore.configURL(modsPath: "/Games/Mods",
                                               physicalFolderName: ".TractorMod")
        #expect(url.path == "/Games/Mods/.TractorMod/config.json")
    }

    @Test func aPackComponentKeepsItsRelativePath() {
        // `folderName` porte le chemin relatif quand un mod est imbriqué —
        // 19 packs à plat dans le parc réel.
        let url = ProfileConfigStore.configURL(modsPath: "/Games/Mods",
                                               physicalFolderName: "Pack/Child")
        #expect(url.path == "/Games/Mods/Pack/Child/config.json")
    }
}
