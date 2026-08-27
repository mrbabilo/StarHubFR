import Testing
import Foundation
@testable import StarHubTHCore

/// Le `config.json` est le seul JSON du dépôt qu'on doive réécrire **dans
/// l'ordre de son auteur** : SMAPI écrit les clés dans l'ordre des champs de
/// sa classe C#, et 1 fichier sur 79 seulement se trouve en ordre
/// alphabétique (spec §2.1). `JSONSerialization` rend un dictionnaire non
/// ordonné : ce parseur garde l'ordre sans trier.
struct ConfigJSONTreeTests {

    // MARK: - Le contenu, pas juste la syntaxe

    @Test func parsesARealConfigWithDecimalsAndBooleans() {
        // Extrait réel de Nullnnow.MS-Books v2.0.5/config.json (revérifié
        // le 2026-08-27 : ce fichier se parse désormais en strict — voir la
        // note « État du parc » du plan).
        let tree = ConfigJSONTree.parse("""
        {
          "TVSceneDuration": 1000.0,
          "TVAutoTurnOff": true,
          "PigChance": 0.1,
          "ShrineStyle": "Default"
        }
        """)
        guard case .object(let obj)? = tree else {
            Issue.record("attendu un objet"); return
        }
        #expect(obj.keys == ["TVSceneDuration", "TVAutoTurnOff",
                             "PigChance", "ShrineStyle"])
        #expect(obj.members["PigChance"] == .number("0.1"))
        #expect(obj.members["TVSceneDuration"] == .number("1000.0"))
        #expect(obj.members["TVAutoTurnOff"] == .bool(true))
        #expect(obj.members["ShrineStyle"] == .string("Default"))
    }

    @Test func booleansWrittenAsStringsStayStrings() {
        // Réel : .[Gen]NatureInTheValley/[CP]NatureInTheValley/config.json.
        // L'auteur écrit "false" entre guillemets. Un booléen déguisé en
        // chaîne doit rester une chaîne : le réécrire en bool le changerait
        // aux yeux du mod.
        let tree = ConfigJSONTree.parse(#"{ "MenuingPack": "false" }"#)
        guard case .object(let obj)? = tree else {
            Issue.record("attendu un objet"); return
        }
        #expect(obj.members["MenuingPack"] == .string("false"))
    }

    @Test func parsesARealArray() {
        // Réel : PassableCrops/config.json — "IncludeObjects": ["", "…"].
        let tree = ConfigJSONTree.parse("""
        { "IncludeObjects": ["", "PassableCrops.Crop"], "PassableTreeGrowth": 3 }
        """)
        guard case .object(let obj)? = tree,
              case .array(let items)? = obj.members["IncludeObjects"] else {
            Issue.record("attendu un tableau"); return
        }
        #expect(items == [.string(""), .string("PassableCrops.Crop")])
        #expect(obj.members["PassableTreeGrowth"] == .number("3"))
    }

    @Test func keepsSchemaAndKeyOrderVerbatim() {
        // Leçon OrderedJSONWriter : il perdait `$schema`. Ici il doit
        // traverser, en tête, comme dans le manifest de MEEP.
        let tree = ConfigJSONTree.parse("""
        {
          "$schema": "https://smapi.io/schemas/manifest.json",
          "Zoom": 1,
          "Alpha": false
        }
        """)
        guard case .object(let obj)? = tree else {
            Issue.record("attendu un objet"); return
        }
        #expect(obj.keys.first == "$schema")
        #expect(obj.keys == ["$schema", "Zoom", "Alpha"])
    }

    @Test func nestsToRealDepths() {
        // La spec §2 mesure une profondeur maximale de 8 sur le parc.
        // Construit au patron réel des configs de contrôles imbriqués.
        let text = """
        { "L1": { "L2": { "L3": { "L4": { "L5": { "L6": { "L7": { "L8": 42 } } } } } } } }
        """
        var node = ConfigJSONTree.parse(text)
        var depth = 0
        while case .object(let obj)? = node, let key = obj.keys.first {
            node = obj.members[key]; depth += 1
        }
        #expect(depth == 8)
        #expect(node == .number("42"))
    }

    // MARK: - La tolérance de Newtonsoft, le chargeur réel de SMAPI

    @Test func toleratesLineComments() {
        let tree = ConfigJSONTree.parse("""
        {
          // Which controls to show
          "ShowControls": true
        }
        """)
        guard case .object(let obj)? = tree else {
            Issue.record("attendu un objet"); return
        }
        #expect(obj.members["ShowControls"] == .bool(true))
    }

    @Test func toleratesBlockComments() {
        let tree = ConfigJSONTree.parse("""
        {
          /* Hidden by the author
             across two lines */
          "Hidden": 1
        }
        """)
        guard case .object(let obj)? = tree else {
            Issue.record("attendu un objet"); return
        }
        #expect(obj.members["Hidden"] == .number("1"))
    }

    @Test func toleratesTrailingCommas() {
        let tree = ConfigJSONTree.parse("""
        { "A": 1, "B": [1, 2, 3,], }
        """)
        guard case .object(let obj)? = tree,
              case .array(let items)? = obj.members["B"] else {
            Issue.record("attendu un objet avec tableau"); return
        }
        #expect(obj.members["A"] == .number("1"))
        #expect(items.count == 3)
    }

    @Test func aSlashSlashInsideAStringIsNotAComment() {
        // Le piège mesuré par I18nLenientParser : une URL contient `//`
        // sans être un commentaire.
        let tree = ConfigJSONTree.parse(
            #"{ "UpdateUrl": "https://example.com/mod" }"#)
        guard case .object(let obj)? = tree else {
            Issue.record("attendu un objet"); return
        }
        #expect(obj.members["UpdateUrl"] == .string("https://example.com/mod"))
    }

    @Test func crlfIsWhitespaceNotCorruption() {
        // Réel : 9 configs du parc sont en CRLF. Un \r\n est UN Character en
        // Swift — le parseur travaille sur Unicode.Scalar pour cette raison.
        let tree = ConfigJSONTree.parse("{\r\n  \"A\": 1\r\n}")
        guard case .object(let obj)? = tree else {
            Issue.record("attendu un objet"); return
        }
        #expect(obj.members["A"] == .number("1"))
    }

    // MARK: - Les refus — nil, jamais un arbre inventé

    @Test func brokenTextGivesNil() {
        // Le repli verbatim de la restauration dépend de ce nil : un parseur
        // « tolérant » qui rendrait un arbre partiel ferait écrire une
        // reconstruction au lieu du texte mémorisé.
        #expect(ConfigJSONTree.parse("{ \"A\": 1, oops }") == nil)
        #expect(ConfigJSONTree.parse("") == nil)
        #expect(ConfigJSONTree.parse("[1, 2") == nil)
        #expect(ConfigJSONTree.parse("\"just a string\"") == nil) // pas un document-object
    }

    @Test func bigRealSizedConfigParses() {
        // La spec §2 mesure un maximum de 45 354 octets. Un texte de cette
        // taille doit parser sans explosion combinatoire.
        let keys = (0..<2800).map { "\"K\($0)\": \($0 % 2 == 0 ? "1" : "\"v\"")" }
        let text = "{\n  " + keys.joined(separator: ",\n  ") + "\n}"
        #expect(text.utf8.count > 40_000)
        guard case .object(let obj)? = ConfigJSONTree.parse(text) else {
            Issue.record("attendu un objet"); return
        }
        #expect(obj.keys.count == 2800)
    }

    @Test func duplicateKeysKeepFirstPositionLastValue() {
        // Comportement Newtonsoft sur un objet : la dernière valeur gagne.
        // La position, elle, reste celle de la première rencontre — l'ordre
        // du fichier est la seule vérité qu'on ait.
        let tree = ConfigJSONTree.parse(#"{ "A": 1, "B": 2, "A": 3 }"#)
        guard case .object(let obj)? = tree else {
            Issue.record("attendu un objet"); return
        }
        #expect(obj.keys == ["A", "B"])
        #expect(obj.members["A"] == .number("3"))
    }

    @Test func stringEscapesRoundTrip() {
        let tree = ConfigJSONTree.parse(
            #"{ "Path": "C:\\Mods\\\"quoted\"", "Newline": "a\nb" }"#)
        guard case .object(let obj)? = tree else {
            Issue.record("attendu un objet"); return
        }
        #expect(obj.members["Path"] == .string(#"C:\Mods\"quoted""#))
        #expect(obj.members["Newline"] == .string("a\nb"))
    }

    // MARK: - Écriture (format SMAPI, spec §5.2)

    @Test func writesSmapiFormatExactly() throws {
        // Le format de SMAPI : 2 espaces, LF, pas de saut de ligne final.
        // Comparé caractère à caractère — l'octet près, pas « à peu près ».
        let tree = try #require(ConfigJSONTree.parse(#"{"Zoom": 1, "Alpha": false}"#))
        let text = try #require(ConfigJSONTree.write(tree))
        #expect(text == "{\n  \"Zoom\": 1,\n  \"Alpha\": false\n}")
        #expect(!text.hasSuffix("\n"))
    }

    @Test func writeRoundTripsARealConfig() throws {
        let real = """
        {
          "TVSceneDuration": 1000.0,
          "PigChance": 0.1,
          "ShrineStyle": "Default",
          "IncludeObjects": ["", "PassableCrops.Crop"]
        }
        """
        let tree = try #require(ConfigJSONTree.parse(real))
        let written = try #require(ConfigJSONTree.write(tree))
        #expect(ConfigJSONTree.parse(written) == tree)
        // Le littéral décimal d'origine, tel quel : jamais 0.1 → 0.100…
        #expect(written.contains("\"PigChance\": 0.1"))
        #expect(written.contains("\"TVSceneDuration\": 1000.0"))
    }

    @Test func writeKeepsKeyOrderUnsorted() {
        // 1 fichier du parc sur 79 seulement est en ordre alphabétique :
        // écrire trié rendrait le fichier méconnaissable pour l'auteur.
        let tree = ConfigJSONTree.parse(#"{"Zoom": 1, "Alpha": false}"#)!
        let text = ConfigJSONTree.write(tree)!
        #expect(text.range(of: "\"Zoom\"")!.lowerBound < text.range(of: "\"Alpha\"")!.lowerBound)
    }

    @Test func writeEmptyContainers() throws {
        let tree = try #require(ConfigJSONTree.parse(#"{"Empty": {}, "List": []}"#))
        let text = try #require(ConfigJSONTree.write(tree))
        #expect(text == "{\n  \"Empty\": {},\n  \"List\": []\n}")
    }

    @Test func writeNestsWithTwoSpaces() throws {
        let tree = try #require(ConfigJSONTree.parse(#"{"A": {"B": 1}}"#))
        let text = try #require(ConfigJSONTree.write(tree))
        #expect(text == "{\n  \"A\": {\n    \"B\": 1\n  }\n}")
    }

    @Test func writeCrlfSourceBecomesLf() throws {
        // Le merge réécrit au format de SMAPI : un config source en CRLF
        // (9 dans le parc) ressort en LF. Le verbatim, lui, ne passe jamais
        // par ici — c'est la différence assumée entre restaurer octets pour
        // octets et reconstruire le seul résultat d'un merge.
        let tree = try #require(ConfigJSONTree.parse("{\r\n  \"A\": 1\r\n}"))
        let text = try #require(ConfigJSONTree.write(tree))
        #expect(!text.contains("\r"))
    }

    @Test func inlineRendersCompactly() {
        let tree = ConfigJSONTree.parse(#"{"A": 1, "B": [1, 2], "C": {"D": true}}"#)!
        let text = ConfigJSONTree.inline(tree)
        #expect(text == #"{"A":1,"B":[1,2],"C":{"D":true}}"#)
    }
}
