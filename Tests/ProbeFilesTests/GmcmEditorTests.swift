import Testing
import Foundation
@testable import StarHubTHCore

struct GmcmEditorTests {
    private struct Mod {
        let tree: ConfigJSONTree.Value
        let gmcm: GmcmModOptions
    }

    /// L'arbre de la copie elle-même : sur le parc, c'est aussi le fichier
    /// que l'éditeur ouvrirait tant que rien n'a changé.
    private func mod(_ uid: String, _ version: String) throws -> Mod {
        let data = try Fixture.data("gmcm-options.json")
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let mods = try #require(json["Mods"] as? [[String: Any]])
        let raw = try #require(mods.first { ($0["UniqueID"] as? String) == uid })
        let snapshot = try #require(raw["ConfigSnapshot"] as? String)
        let capture = try #require(GmcmCapture.decode(data))
        return Mod(tree: try #require(ConfigJSONTree.parse(snapshot)),
                   gmcm: try #require(capture.options(forMod: uid, installedVersion: version)))
    }

    private func rows(_ mod: Mod, labels: [String: ConfigLabelResolver.Labels] = [:],
                      schema: [ConfigSchemaOption] = [], language: String? = "fr") -> [ConfigEditorModel.Row] {
        ConfigEditorModel.groups(of: mod.tree, describedBy: schema, labeledBy: labels,
                                 gmcm: mod.gmcm, appLanguage: language).flatMap(\.rows)
    }

    private func row(_ key: String, in rows: [ConfigEditorModel.Row]) throws -> ConfigEditorModel.Row {
        try #require(rows.first { $0.keyPath.last?.lowercased() == key.lowercased() })
    }

    @Test func ultraSmoothGetsSlidersChoicesAndLabels() throws {
        let rows = rows(try mod("palmhacker13.UltraSmooth", "2.3.8"))
        #expect(rows.filter { $0.bounds != nil }.count == 14)
        #expect(try row("TimeSliceBudgetMs", in: rows).bounds == .init(min: 0.1, max: 5, step: 0.1))
        let fps = try row("FpsMode", in: rows)
        #expect(fps.label == "Fréquence d'actualisation (Mode FPS)")
        #expect(fps.control == .choice(selected: "Standard",
                                       among: ["Standard", "Enhanced60", "MonitorHz", "Unlimited"]))
    }

    /// `SpawnDensity = 15`, choix `5…25` : un nombre JSON garde son champ.
    @Test func numericChoiceKeepsItsField() throws {
        let density = try row("SpawnDensity", in: rows(try mod("Nullnnow.MS-Books", "2.0.6")))
        #expect(density.control == .integer(15))
    }

    /// Même langue : GMCM est ce que le jeu montre. Autre langue : l'i18n.
    @Test func languageDecidesBetweenGmcmAndI18n() throws {
        let us = try mod("palmhacker13.UltraSmooth", "2.3.8")
        let labels = ["fpsmode": ConfigLabelResolver.Labels(text: "FPS mode", detail: "From i18n")]
        #expect(try row("FpsMode", in: rows(us, labels: labels, language: "fr")).label
                == "Fréquence d'actualisation (Mode FPS)")
        let english = try row("FpsMode", in: rows(us, labels: labels, language: "en"))
        #expect(english.label == "FPS mode")
        #expect(english.description == "From i18n")
        // Sans i18n, GMCM même dans une autre langue : mieux que la clé brute.
        #expect(try row("FpsMode", in: rows(us, language: "en")).label
                == "Fréquence d'actualisation (Mode FPS)")
    }

    @Test func anExplicitSchemaNameStillWins() throws {
        let museum = try mod("Exonika.TheMuseumPays", "1.5.8")
        let schema = [ConfigSchemaOption(token: "Reward Amount", name: "Montant", description: nil,
                                         section: nil, allowValues: [], defaultLiteral: nil,
                                         allowBlank: nil, allowMultiple: nil)]
        #expect(try row("Reward Amount", in: rows(museum, schema: schema)).label == "Montant")
        #expect(try row("Reward Amount", in: rows(museum)).label == "Quantité de récompense")
    }

    /// Mail Services : l'option inversée est écartée, la clé brute reste.
    @Test func aRejectedOptionLeavesTheRowAsToday() throws {
        let rows = rows(try mod("Digus.MailServicesMod", "1.6.2"))
        let gift = try row("DisableGiftService", in: rows)
        #expect(gift.label == "DisableGiftService")
        #expect(gift.bounds == nil)
    }

    /// Valeur changée dans l'app après la capture : la copie a servi au
    /// rapprochement, le fichier actuel garde son curseur.
    @Test func editedValueKeepsTheSlider() throws {
        let us = try mod("palmhacker13.UltraSmooth", "2.3.8")
        guard case .object(var object) = us.tree else { Issue.record("objet attendu"); return }
        let key = try #require(object.keys.first { $0.lowercased() == "timeslicebudgetms" })
        object.members[key] = .number("2.5")
        let edited = Mod(tree: .object(object), gmcm: us.gmcm)
        let slice = try row("TimeSliceBudgetMs", in: rows(edited))
        #expect(slice.control == .decimal(2.5))
        #expect(slice.bounds == .init(min: 0.1, max: 5, step: 0.1))
    }

    @Test func gmcmChoiceLabelsFillTheMenu() throws {
        let json = #"{"CapturedAt": "2026-09-27T01:34:37.0734180+02:00", "GmcmVersion": "1.16.0", "Language": "fr", "Mods": [{"UniqueID": "Test.Mod", "Name": "Test", "Version": "1.0.0", "ConfigSnapshot": "{\"Mode\": \"both\"}", "Options": [{"Kind": "ChoiceModOption", "Name": "Mode", "Tooltip": null, "ValueType": "String", "Value": "both", "Min": null, "Max": null, "Interval": null, "Choices": ["both", "keybind"], "ChoiceLabels": ["Les deux", "Touche"], "AccessPath": ["Mode"], "ClosureStrings": []}]}]}"#
        let capture = try #require(GmcmCapture.decode(Data(json.utf8)))
        let gmcm = try #require(capture.options(forMod: "Test.Mod", installedVersion: "1.0.0"))
        let tree = try #require(ConfigJSONTree.parse(#"{"Mode": "both"}"#))
        let mode = try row("Mode", in: ConfigEditorModel.groups(of: tree, describedBy: [], gmcm: gmcm,
                                                                 appLanguage: "fr").flatMap(\.rows))
        #expect(mode.choiceLabels == ["both": "Les deux", "keybind": "Touche"])
    }

    /// Un nombre que le schéma du pack met en menu n'a pas de curseur, même
    /// si GMCM déclare des bornes pour lui.
    @Test func aSchemaMenuGetsNoSlider() throws {
        let json = #"{"CapturedAt": "2026-09-27T01:34:37.0734180+02:00", "GmcmVersion": "1.16.0", "Language": "fr", "Mods": [{"UniqueID": "Test.Mod", "Name": "Test", "Version": "1.0.0", "ConfigSnapshot": "{\"Level\": 2}", "Options": [{"Kind": "NumericModOption", "Name": "Level", "Tooltip": null, "ValueType": "Int32", "Value": "2", "Min": "1", "Max": "3", "Interval": null, "Choices": null, "ChoiceLabels": null, "AccessPath": ["Level"], "ClosureStrings": []}]}]}"#
        let capture = try #require(GmcmCapture.decode(Data(json.utf8)))
        let gmcm = try #require(capture.options(forMod: "Test.Mod", installedVersion: "1.0.0"))
        let tree = try #require(ConfigJSONTree.parse(#"{"Level": 2}"#))
        let schema = [ConfigSchemaOption(token: "Level", name: nil, description: nil, section: nil,
                                         allowValues: ["1", "2", "3"], defaultLiteral: nil,
                                         allowBlank: nil, allowMultiple: nil)]
        let level = try row("Level", in: ConfigEditorModel.groups(of: tree, describedBy: schema, gmcm: gmcm,
                                                                   appLanguage: "fr").flatMap(\.rows))
        #expect(level.control == .choice(selected: "2", among: ["1", "2", "3"]))
        #expect(level.bounds == nil)
        #expect(gmcm.entry(for: ["Level"])?.bounds == .init(min: 1, max: 3, step: nil))
    }

    /// Sans capture : l'éditeur d'aujourd'hui, à l'identique.
    @Test func withoutGmcmNothingChanges() throws {
        let us = try mod("palmhacker13.UltraSmooth", "2.3.8")
        let plain = ConfigEditorModel.groups(of: us.tree, describedBy: [])
        let explicit = ConfigEditorModel.groups(of: us.tree, describedBy: [], gmcm: nil, appLanguage: "fr")
        #expect(plain == explicit)
        #expect(plain.flatMap(\.rows).allSatisfy { $0.bounds == nil })
    }
}
