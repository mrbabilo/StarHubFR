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

    // MARK: - Les deux portes parlent la langue du jeu

    /// Depuis le 2026-09-10, `decode` accepte les quatre formes JSON5 que le
    /// strict refusait : l'oracle Newtonsoft (la DLL exacte de SMAPI, 13.0.0.0,
    /// exécutée) les accepte toutes — un mod ainsi écrit tourne dans le jeu,
    /// et l'installer, le réparer ou le renommer ne devaient pas le refuser
    /// (la classe même du bug X29). Le scan les lisait déjà ; aucun des
    /// 1 106 manifestes du parc n'en porte, l'invariance est mesurée.

    @Test func theFourJson5FormsTheGameAcceptsPassBothDoors() throws {
        let tolerated = [
            #"{ Name: "X" }"#,                  // clé non quotée
            "{ 'Name': 'X' }",                  // chaîne en quote simple
            #"{ "Name": "X", "N": 0xFF }"#,     // nombre hexadécimal
            #"{ "Name": "X", "N": Infinity }"#
        ]
        for raw in tolerated {
            #expect(try ManifestJSON.decodeInstalled(raw)["Name"] as? String == "X")
            #expect(ManifestJSON.decode(raw)?["Name"] as? String == "X",
                    "decode devrait lire ce que le jeu charge : \(raw)")
        }
    }

    /// Chez Newtonsoft, `0x1F` se lit comme l'entier 31 — l'hexadécimal est un
    /// nombre, pas une chaîne. Le même sens doit sortir de nos portes, sinon
    /// un champ numérique lu par le scan et par un juge divergerait.
    @Test func hexNumbersReadAsTheIntegerValue() {
        let doors = [ManifestJSON.decode(#"{ "N": 0xFF }"#),
                     try? ManifestJSON.decodeInstalled(#"{ "N": 0xFF }"#)]
        for fields in doors {
            #expect(fields?["N"] as? Int == 255)
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
