import Testing
import Foundation
@testable import StarHubTHCore

struct ManifestJSONTests {
    /// Le manifeste réel de « Susan of Emerald Farm » (Nexus 45990), refusé à
    /// l'installation avec « manifest.json manquant » alors qu'il était bien là.
    /// C'est le modèle fourni par SMAPI, commentaires compris.
    private let realWorld = """
    {
    // manifest.json is what makes SMAPI recognize your mod as a mod. See https://stardewvalleywiki.com/Modding:Modder_Guide/APIs/Manifest
      "Name": "Susan of Emerald Farm",
      "Version": "1.1.0",
      "UniqueID": "DolphINaF.Susan",
      "UpdateKeys": [ "Nexus:45990" ],
      "ContentPackFor": {
        "UniqueID": "Pathoschild.ContentPatcher"
      },
    }
    """

    @Test func decodesTheManifestThatUsedToBeRejected() {
        guard let json = ManifestJSON.decode(realWorld) else {
            Issue.record("manifeste refusé"); return
        }
        #expect(json["UniqueID"] as? String == "DolphINaF.Susan")
        #expect(json["Name"] as? String == "Susan of Emerald Farm")
        #expect((json["ContentPackFor"] as? [String: Any])?["UniqueID"] as? String
                == "Pathoschild.ContentPatcher")
    }

    @Test func urlsInsideStringsSurvive() {
        // Le piège d'une regex : « https:// » n'est pas un commentaire.
        let json = ManifestJSON.decode("""
        { "Name": "X", "Url": "https://example.com/a//b", "UniqueID": "x" }
        """)
        #expect(json?["Url"] as? String == "https://example.com/a//b")
    }

    @Test func blockCommentsAndBomAreRemoved() {
        let json = ManifestJSON.decode("\u{FEFF}{ /* en-tête */ \"UniqueID\": \"x\" }")
        #expect(json?["UniqueID"] as? String == "x")
    }

    @Test func trailingCommasInArraysAndObjectsAreRemoved() {
        let json = ManifestJSON.decode("""
        { "Keys": [ "a", "b", ], "UniqueID": "x", }
        """)
        #expect((json?["Keys"] as? [String]) == ["a", "b"])
    }

    @Test func aCommaInsideAStringIsNotTouched() {
        let json = ManifestJSON.decode("""
        { "Description": "un, deux, trois", "UniqueID": "x" }
        """)
        #expect(json?["Description"] as? String == "un, deux, trois")
    }

    @Test func aFragmentIsRefused() {
        // Un manifeste est un objet. Accepter un fragment ferait passer un
        // fichier tronqué pour un mod valide.
        #expect(ManifestJSON.decode(#""just a string""#) == nil)
        #expect(ManifestJSON.decode("") == nil)
    }
}
