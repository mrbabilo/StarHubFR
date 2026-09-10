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

    // MARK: - `decodeInstalled` : la lecture d'un mod déjà en place

    /// Le scan lit un mod que SMAPI a **déjà chargé** : il n'a pas de décision
    /// à prendre, donc pas de raison d'être plus strict que le jeu. Ces tests
    /// verrouillent le sens de l'écart, mesuré le 2026-09-10 sur les 1 108
    /// manifestes du parc — `decodeInstalled` accepte strictement plus, et
    /// l'inverse n'existe pas.

    @Test func fourJson5FormsPassWhereTheJudgingDoorRefuses() throws {
        // Formes que Newtonsoft (donc SMAPI, donc le jeu) accepte. Un mod ainsi
        // écrit tourne dans le jeu ; le refuser le laisserait sans nom ni
        // version dans la liste.
        let tolerated = [
            #"{ Name: "X" }"#,                  // clé non quotée
            "{ 'Name': 'X' }",                  // chaîne en quote simple
            #"{ "Name": "X", "N": 0xFF }"#,     // nombre hexadécimal
            #"{ "Name": "X", "N": Infinity }"#
        ]
        for raw in tolerated {
            #expect(ManifestJSON.decode(raw) == nil, "decode devrait refuser : \(raw)")
            #expect(try ManifestJSON.decodeInstalled(raw)["Name"] as? String == "X")
        }
    }

    @Test func everythingTheJudgingDoorAcceptsIsAcceptedHereToo() throws {
        // L'écart n'a qu'un sens : pas de forme perdue en passant du décodeur
        // strict au tolérant. C'est ce qui rend le remplacement sûr.
        for raw in [realWorld,
                    #"{ "Keys": [ "a", "b", ], "UniqueID": "x", }"#,
                    "{ /* bloc */ \"Name\": \"X\" }",
                    "\u{FEFF}{ \"Name\": \"X\" }"] {
            #expect(ManifestJSON.decode(raw) != nil)
            #expect(throws: Never.self) { try ManifestJSON.decodeInstalled(raw) }
        }
    }

    @Test func aBlockCommentInsideAStringKeepsItsMiddle() throws {
        // Le scan retirait les commentaires bloc par expression régulière avant
        // de décoder. Une expression régulière ne peut pas être consciente des
        // chaînes : cette description perdait son milieu (« garde  intact »).
        // Aucun des 1 108 manifestes du parc n'était touché — 47 portent un
        // commentaire bloc, aucun dans une valeur — donc un défaut latent.
        let json = try ManifestJSON.decodeInstalled(#"{ "Description": "garde /* ceci */ intact" }"#)
        #expect(json["Description"] as? String == "garde /* ceci */ intact")
    }

    @Test func aBlockCommentAroundTheFieldsIsStillDropped() throws {
        // Ce que l'expression régulière faisait vraiment, JSON5 le fait aussi —
        // y compris un bloc en fin de fichier et un bloc multiligne.
        #expect(try ManifestJSON.decodeInstalled("{ /* a\nb */ \"Name\": \"X\" } /* fin */")["Name"] as? String == "X")
    }

    @Test func aFragmentIsRefusedByBothDoors() {
        // Même garde des deux côtés : un manifeste est un objet, pas une valeur
        // nue. L'accepter ferait passer un fichier tronqué pour un mod.
        #expect(throws: (any Error).self) { try ManifestJSON.decodeInstalled(#""just a string""#) }
        #expect(throws: (any Error).self) { try ManifestJSON.decodeInstalled("") }
    }

    @Test func anUnreadableManifestNamesItsCauseForTheLog() throws {
        // L'appelant journalise `error.localizedDescription` : un mod affiché
        // sans métadonnées doit être explicable depuis le journal.
        let error = #expect(throws: (any Error).self) {
            try ManifestJSON.decodeInstalled("{ \"Name\": ")
        }
        let cause = error?.localizedDescription ?? ""
        #expect(cause.isEmpty == false)
    }
}
