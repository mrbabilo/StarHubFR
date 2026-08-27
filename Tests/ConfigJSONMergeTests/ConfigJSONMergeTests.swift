import Testing
import Foundation
@testable import StarHubTHCore

/// Le cas couvert est étroit et mesuré (spec §5.3) : le mod a été mis à jour
/// depuis la mémorisation et a gagné des clés. Le merge doit rendre au mod
/// ses nouveaux réglages par défaut **et** à l'utilisateur les siens.
struct ConfigJSONMergeTests {

    @Test func theNarrowCaseNewKeysOnDiskAreKept() throws {
        // Le disque (nouvelle version 1.1 du mod) a gagné "NewFeature" ;
        // le mémorisé (réglages de l'utilisateur sur la 1.0) règle "Zoom".
        let disk = """
        {
          "Zoom": 4,
          "Alpha": false,
          "NewFeature": "on"
        }
        """
        let memorized = """
        {
          "Zoom": 9,
          "Alpha": false
        }
        """
        let result = try #require(ConfigJSONMerge.mergedText(disk: disk, memorized: memorized))
        #expect(result.addedKeyPaths == 0)
        #expect(result.text == """
        {
          "Zoom": 9,
          "Alpha": false,
          "NewFeature": "on"
        }
        """)
    }

    @Test func keysOnlyInMemorizedAreAppendedInTail() throws {
        // L'utilisateur avait réglé une clé que le disque n'a plus (champ
        // retiré par l'auteur, ou config régénéré). On la rend : si le champ
        // C# n'existe plus, SMAPI l'évacuera au lancement suivant — l'écrire
        // ne peut rien casser, l'omettre perdrait un réglage peut-être venu.
        let disk = "{\n  \"A\": 1\n}"
        let memorized = "{\n  \"A\": 1,\n  \"Retired\": \"keep me\"\n}"
        let result = try #require(ConfigJSONMerge.mergedText(disk: disk, memorized: memorized))
        #expect(result.addedKeyPaths == 1)
        #expect(result.text == "{\n  \"A\": 1,\n  \"Retired\": \"keep me\"\n}")
    }

    @Test func arraysAreReplacedWholeNeverElementWise() throws {
        // Une liste de raccourcis clavier ne se « fusionne » pas : le
        // mémorisé remplace le tableau du disque en entier.
        let disk = "{\n  \"Hotkeys\": [\"F1\", \"F2\", \"F3\"],\n  \"Size\": 1\n}"
        let memorized = "{\n  \"Hotkeys\": [\"F5\"],\n  \"Size\": 1\n}"
        let result = try #require(ConfigJSONMerge.mergedText(disk: disk, memorized: memorized))
        #expect(result.text.contains("\"Hotkeys\": [\n    \"F5\"\n  ]"))
        #expect(!result.text.contains("F1"))
    }

    @Test func recursionGoesIntoNestedObjects() throws {
        let disk = """
        {
          "Controls": {
            "ToggleKey": "K",
            "NewNested": true
          }
        }
        """
        let memorized = """
        {
          "Controls": {
            "ToggleKey": "L"
          }
        }
        """
        let result = try #require(ConfigJSONMerge.mergedText(disk: disk, memorized: memorized))
        #expect(result.text.contains("\"ToggleKey\": \"L\""))
        #expect(result.text.contains("\"NewNested\": true"))
    }

    @Test func objectOnDiskReplacedByScalarInMemorized() throws {
        // L'auteur a transformé un sous-objet en scalaire entre deux
        // versions, ou l'inverse : pas de "demi-fusion" possible — la valeur
        // du mémorisé remplace, la règle 3 vaut pour toute valeur composée.
        let disk = "{\n  \"Setting\": {\n    \"A\": 1\n  }\n}"
        let memorized = "{\n  \"Setting\": \"plain\"\n}"
        let result = try #require(ConfigJSONMerge.mergedText(disk: disk, memorized: memorized))
        #expect(result.text == "{\n  \"Setting\": \"plain\"\n}")
    }

    @Test func unparseableDiskFallsToNilNotToReconstruction() throws {
        // Le repli verbatim dépend de ce nil : reconstruire depuis le seul
        // mémorisé ferait perdre les nouvelles clés du disque, ce que le
        // merge existe pour éviter.
        let result = ConfigJSONMerge.mergedText(disk: "{ broken",
                                               memorized: "{\n  \"A\": 1\n}")
        #expect(result == nil)
    }

    @Test func unparseableMemorizedFallsToNil() {
        let result = ConfigJSONMerge.mergedText(disk: "{\n  \"A\": 1\n}",
                                               memorized: "{ also broken")
        #expect(result == nil)
    }

    @Test func emptyMemorizedObjectKeepsDiskVerbatimContent() throws {
        // "{}" mémorisé : rien à appliquer, mais ce n'est pas une erreur —
        // le résultat est le disque, réécrit au format SMAPI.
        let result = try #require(ConfigJSONMerge.mergedText(disk: "{\n  \"A\": 1\n}",
                                                            memorized: "{}"))
        #expect(result.addedKeyPaths == 0)
        #expect(result.text == "{\n  \"A\": 1\n}")
    }

    @Test func decimalsSurviveTheMerge() throws {
        let disk = "{\n  \"Duration\": 1000.0\n}"
        let memorized = "{\n  \"Duration\": 250.50\n}"
        let result = try #require(ConfigJSONMerge.mergedText(disk: disk, memorized: memorized))
        #expect(result.text.contains("250.50"))
    }
}
