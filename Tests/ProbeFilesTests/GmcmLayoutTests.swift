import Testing
import Foundation
@testable import StarHubTHCore

/// L'éditeur range les réglages comme le menu en jeu (GMCM ou
/// ModernConfigMenu) : mêmes sections, même ordre. Ce que le menu ne montre
/// pas reste à la fin, dans l'ordre du fichier.
struct GmcmLayoutTests {
    private let config = #"{"EnablePureDiskMode": false, "EnableDeferredXmlMirroring": true, "XmlMirrorDebounceSeconds": 6, "VerboseLogging": false}"#

    private func option(_ field: String, _ name: String, _ value: String, _ section: String?) -> [String: Any] {
        var o: [String: Any] = ["Kind": "SimpleModOption", "Name": name, "Tooltip": "Aide de \(name)",
                                "ValueType": "Boolean", "Value": value,
                                "AccessPath": ["Config", field], "ClosureStrings": [String]()]
        if let section { o["Section"] = section }
        return o
    }

    private func gmcm() throws -> GmcmModOptions {
        let capture: [String: Any] = [
            "CapturedAt": "2026-11-02T21:00:00+01:00", "Language": "fr",
            "Mods": [["UniqueID": "palmhacker13.PureBinarySave", "Name": "PureBinarySave", "Version": "1.0.7",
                      "ConfigSnapshot": config,
                      "Options": [
                        option("EnableDeferredXmlMirroring", "Deferred XML Mirroring", "True", "Save Storage & Format"),
                        option("EnablePureDiskMode", "Pure Disk Mode (No XML)", "False", "Save Storage & Format"),
                        option("VerboseLogging", "Verbose Logging", "False", "Developer"),
                      ]]],
        ]
        let data = try JSONSerialization.data(withJSONObject: capture)
        let parsed = try #require(GmcmCapture.decode(data))
        return try #require(parsed.options(forMod: "palmhacker13.PureBinarySave", installedVersion: "1.0.7"))
    }

    @Test func settingsFollowTheInGameSectionsAndOrder() throws {
        let gmcm = try gmcm()
        let tree = try #require(ConfigJSONTree.parse(config))
        let groups = GmcmModOptions.arranged(
            ConfigEditorModel.groups(of: tree, describedBy: [], gmcm: gmcm, appLanguage: "fr"), by: gmcm)
        #expect(groups.map(\.section) == ["Save Storage & Format", "Developer", nil])
        #expect(groups[0].rows.map(\.label) == ["Deferred XML Mirroring", "Pure Disk Mode (No XML)"])
        #expect(groups[0].rows.first?.description == "Aide de Deferred XML Mirroring")
        // Absent du menu : gardé, à la fin, sous sa clé.
        #expect(groups[2].rows.map(\.label) == ["XmlMirrorDebounceSeconds"])
    }

    @Test func withoutACaptureTheFileOrderStays() throws {
        let tree = try #require(ConfigJSONTree.parse(config))
        let groups = GmcmModOptions.arranged(ConfigEditorModel.groups(of: tree, describedBy: []), by: nil)
        #expect(groups.count == 1)
        #expect(groups[0].rows.map(\.label).first == "EnablePureDiskMode")
    }
}
