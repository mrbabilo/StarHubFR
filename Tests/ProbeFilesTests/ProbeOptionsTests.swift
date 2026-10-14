import Testing
import Foundation
@testable import StarHubTHCore

/// D4-T6 bis — les options de configuration de la sonde, lues et réécrites
/// par l'app : la fiche sonde les expose en Toggles, et l'écriture est
/// **toujours propre** — la config éditée à la main du 2026-10-05 portait une
/// virgule manquante que SMAPI rejetait en silence (défauts, mesure jamais
/// armée).
struct ProbeOptionsTests {

    @Test func readsTheTwoKnownOptionsWithTheirDefaults() throws {
        let json = #"{"MeasureHarmonyPatches": true, "MeasureTextures": true}"#
        let options = try ProbeOptions.read(Data(json.utf8)).get()
        #expect(options.measureHarmonyPatches == true)
        #expect(options.measureTextures == true)

        let partial = #"{"MeasureTextures": false}"#
        let options2 = try ProbeOptions.read(Data(partial.utf8)).get()
        #expect(options2.measureHarmonyPatches == ProbeOptions.defaultHarmonyPatches)
        #expect(options2.measureTextures == false)
    }

    /// Une virgule manquante (l'édition à la main) : la lecture échoue et le
    /// dit — jamais un faux « option désactivée » sur un fichier illisible.
    @Test func aMissingCommaFailsTheReadLoudly() {
        let broken = "{ \"MeasureHarmonyPatches\": true\n  \"MeasureTextures\": true }"
        guard case .failure(.unreadable) = ProbeOptions.read(Data(broken.utf8)) else {
            Issue.record("attendu : .unreadable")
            return
        }
    }

    /// La réécriture est **toujours valable** : les deux options connues, et
    /// tout champ inconnu du fichier d'origine préservé.
    @Test func rewritingProducesValidJSONAndKeepsUnknownFields() throws {
        let original = Data(#"{"MeasureHarmonyPatches": true, "MeasureTextures": false, "FutureOption": 3}"#.utf8)
        let data = try ProbeOptions.rewritten(original: original,
                                              options: ProbeOptions(measureHarmonyPatches: false, measureTextures: true))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["MeasureHarmonyPatches"] as? Bool == false)
        #expect(object["MeasureTextures"] as? Bool == true)
        #expect(object["FutureOption"] as? Int == 3)
        // Stable : réécrire la même chose rend les mêmes octets.
        let again = try ProbeOptions.rewritten(original: data,
                                               options: ProbeOptions(measureHarmonyPatches: false, measureTextures: true))
        #expect(again == data)
    }

    /// Fichier cassé ou absent : la réécriture part des défauts et rend un
    /// JSON valable — c'est le geste « réparer ».
    @Test func rewritingABrokenFileRepairsIt() throws {
        let broken = Data("{ \"MeasureTextures\": true\n \"MeasureHarmonyPatches\": true }".utf8)
        let data = try ProbeOptions.rewritten(original: broken,
                                              options: ProbeOptions(measureHarmonyPatches: true, measureTextures: true))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.count == 3)
    }

    /// Les mini-stats en jeu (FPS, P50/P99, mémoire), option de la sonde 0.9.25+ :
    /// lues, coupées par défaut, réécrites sans toucher aux deux autres.
    @Test func miniStatsAreReadAndWrittenLikeTheOtherOptions() throws {
        let on = try ProbeOptions.read(Data(#"{"ShowMiniStats": true}"#.utf8)).get()
        #expect(on.showMiniStats)
        let absent = try ProbeOptions.read(Data(#"{"MeasureTextures": true}"#.utf8)).get()
        #expect(absent.showMiniStats == ProbeOptions.defaultMiniStats)
        let original = Data(#"{"MeasureHarmonyPatches": true, "MeasureTextures": true, "ShowMiniStats": false}"#.utf8)
        let data = try ProbeOptions.rewritten(original: original,
                                              options: ProbeOptions(measureHarmonyPatches: true, measureTextures: true,
                                                                    showMiniStats: true))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["ShowMiniStats"] as? Bool == true)
        #expect(object["MeasureHarmonyPatches"] as? Bool == true)
        #expect(object.count == 3)
    }
}
