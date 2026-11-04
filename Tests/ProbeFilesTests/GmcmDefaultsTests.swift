import Foundation
import Testing
@testable import StarHubTHCore

/// C4-T18 — la sonde exporte la config qu'écrirait `new T()` : l'éditeur y
/// lit la valeur par défaut de chaque réglage, au même chemin que le fichier.
struct GmcmDefaultsTests {
    private func rows(config: String, defaults: String?,
                      schema: [ConfigSchemaOption] = []) throws -> [ConfigEditorModel.Row] {
        var mod: [String: Any] = ["UniqueID": "Test.Mod", "Name": "Test", "Version": "1.0.0",
                                  "ConfigSnapshot": config, "Options": [[String: Any]]()]
        mod["DefaultConfig"] = defaults ?? NSNull()
        let json: [String: Any] = ["CapturedAt": "2026-11-05T00:00:00.0000000+01:00",
                                   "GmcmVersion": "1.16.0", "Language": "fr", "Mods": [mod]]
        let capture = try #require(GmcmCapture.decode(try JSONSerialization.data(withJSONObject: json)))
        let gmcm = try #require(capture.options(forMod: "Test.Mod", installedVersion: "1.0.0"))
        let tree = try #require(ConfigJSONTree.parse(config))
        return ConfigEditorModel.groups(of: tree, describedBy: schema, labeledBy: [:],
                                        gmcm: gmcm, appLanguage: "fr").flatMap(\.rows)
    }

    private func defaultControl(_ config: String, _ defaults: String?) throws -> ConfigEditorModel.Control? {
        try #require(try rows(config: config, defaults: defaults).first).defaultControl
    }

    @Test func aChangedValueOffersItsDefault() throws {
        #expect(try defaultControl(#"{"On": false}"#, #"{"On": true}"#) == .toggle(true, asString: false))
        #expect(try defaultControl(#"{"Speed": 3}"#, #"{"Speed": 2}"#) == .integer(2))
        #expect(try defaultControl(#"{"Key": "F6"}"#, #"{"Key": "F5, LeftStick"}"#) != nil)
    }

    @Test func anUnchangedValueOffersNothing() throws {
        #expect(try defaultControl(#"{"On": true}"#, #"{"On": true}"#) == nil)
        #expect(try defaultControl(#"{"Rate": 1.50}"#, #"{"Rate": 1.5}"#) == nil)
        #expect(try defaultControl(#"{"Mode": "both"}"#, #"{"Mode": "Both"}"#) == nil)
    }

    /// Remettre un défaut ne doit pas changer le type que le fichier emploie.
    @Test func aDefaultOfAnotherTypeIsIgnored() throws {
        #expect(try defaultControl(#"{"Size": "big"}"#, #"{"Size": 3}"#) == nil)
    }

    @Test func nestedKeysFollowTheSamePath() throws {
        let control = try defaultControl(#"{"Audio": {"Volume": 3}}"#, #"{"audio": {"volume": 5}}"#)
        #expect(control == .integer(5))
    }

    @Test func withoutADefaultNothingIsOffered() throws {
        #expect(try defaultControl(#"{"On": false}"#, nil) == nil)
        #expect(try defaultControl(#"{"On": false}"#, #"{"Other": true}"#) == nil)
        #expect(try defaultControl(#"{"On": false}"#, "not json") == nil)
    }

    /// Le mod déclare ses valeurs admises : le défaut garde leur orthographe.
    @Test func aListKeepsItsChoices() throws {
        let option = ConfigSchemaOption(token: "Mode", name: nil, description: nil, section: nil,
                                        allowValues: ["Fast", "Slow"], defaultLiteral: nil,
                                        allowBlank: false, allowMultiple: false)
        let row = try #require(try rows(config: #"{"Mode": "Slow"}"#, defaults: #"{"Mode": "fast"}"#,
                                        schema: [option]).first)
        #expect(row.defaultControl == .choice(selected: "Fast", among: ["Fast", "Slow"]))
    }
}
