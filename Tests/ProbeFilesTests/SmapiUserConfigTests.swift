import Foundation
import Testing
@testable import StarHubTHCore

struct SmapiUserConfigTests {
    private let probe = "mrbabilo.StarHubFR.Probe"
    // Le fichier réel de l'auteur (2026-10-01), BOM compris.
    private let real = "\u{FEFF}{\n  \"ConsoleColorScheme\": \"LightBackground\",\n  \"VerboseLogging\": [\n    \"SinZ.Profiler\",\n    \"Arshia1381.Stardropium\"\n  ]\n}"

    @Test func addsTheKeyToAnExistingFileAndKeepsTheRest() throws {
        let out = try #require(SmapiUserConfig.settingLoadEarly(real, modId: probe, present: true))
        #expect(out.hasPrefix("\u{FEFF}{"))
        #expect(out.contains("\"ConsoleColorScheme\": \"LightBackground\""))
        #expect(out.contains("\"Arshia1381.Stardropium\""))
        #expect(SmapiUserConfig.listsLoadEarly(out, modId: probe))
        // Relisible par SMAPI (Newtonsoft accepte le BOM ; ici JSON strict sans BOM).
        let body = String(out.drop { $0 == "\u{FEFF}" })
        #expect((try? JSONSerialization.jsonObject(with: Data(body.utf8))) is [String: Any])
    }

    @Test func appendsToTheAuthorsOwnListAndRemovesOnlyItself() throws {
        let mine = "{\n  \"ModsToLoadEarly\": [\"Author.First\"],\n  \"DeveloperMode\": false\n}"
        let added = try #require(SmapiUserConfig.settingLoadEarly(mine, modId: probe, present: true))
        #expect(added.contains("\"Author.First\""))
        #expect(SmapiUserConfig.listsLoadEarly(added, modId: probe))
        let removed = try #require(SmapiUserConfig.settingLoadEarly(added, modId: probe.uppercased(), present: false))
        #expect(removed.contains("\"Author.First\""))
        #expect(!SmapiUserConfig.listsLoadEarly(removed, modId: probe))
        #expect(removed.contains("\"DeveloperMode\": false"))
    }

    @Test func nothingToChangeGivesNil() {
        let listed = "{ \"ModsToLoadEarly\": [ \"MRBABILO.starhubfr.probe\" ] }"
        #expect(SmapiUserConfig.settingLoadEarly(listed, modId: probe, present: true) == nil)
        #expect(SmapiUserConfig.settingLoadEarly(real, modId: probe, present: false) == nil)
    }

    @Test func aMissingOrEmptyFileBecomesAMinimalObject() throws {
        for text in [nil, "", "  \n"] as [String?] {
            let out = try #require(SmapiUserConfig.settingLoadEarly(text, modId: probe, present: true))
            let object = try #require(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
            #expect(object["ModsToLoadEarly"] as? [String] == [probe])
        }
        #expect(SmapiUserConfig.settingLoadEarly(nil, modId: probe, present: false) == nil)
    }

    /// Review Focus 1 : un fichier illisible n'est jamais écrasé.
    @Test func anUnreadableFileIsNeverRewritten() {
        #expect(SmapiUserConfig.settingLoadEarly("{ \"VerboseLogging\": [ ", modId: probe, present: true) == nil)
        #expect(SmapiUserConfig.settingLoadEarly("[1, 2]", modId: probe, present: true) == nil)
    }

    @Test func commentsSurviveTheEdit() throws {
        let commented = "{\n  // réglage de l'auteur\n  \"ModsToLoadEarly\": [],\n  /* bloc */ \"X\": 1\n}"
        let out = try #require(SmapiUserConfig.settingLoadEarly(commented, modId: probe, present: true))
        #expect(out.contains("// réglage de l'auteur"))
        #expect(out.contains("/* bloc */"))
        #expect(SmapiUserConfig.listsLoadEarly(out, modId: probe))
        let back = try #require(SmapiUserConfig.settingLoadEarly(out, modId: probe, present: false))
        #expect(back.contains("\"ModsToLoadEarly\": []"))
    }
}
