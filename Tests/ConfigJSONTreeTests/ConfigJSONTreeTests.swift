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

    // MARK: - Ce que Newtonsoft accepte et que nous refusions

    // Ces cas viennent des 14 `content.json` (sur 606) que ce parseur
    // refusait sur le parc réel — 7 d'entre eux portent un `ConfigSchema`,
    // 6 ont un `config.json` que l'éditeur ouvre. Le fichier de chaque cas
    // est nommé : ce ne sont pas des formes imaginées.

    @Test func aBareNumericKeyIsRead() throws {
        // Réel : `.HB/content.json` L.2829 — la clé interne est le numéro de
        // la ligne de dialogue, écrite nue. Newtonsoft l'accepte.
        let tree = try #require(ConfigJSONTree.parse(
            #"{ "AnimalShop.6": {0: "un texte"} }"#))
        guard case .object(let root) = tree,
              case .object(let inner)? = root.members["AnimalShop.6"] else {
            Issue.record("attendu un objet imbriqué"); return
        }
        #expect(inner.keys == ["0"])
        #expect(inner.members["0"] == .string("un texte"))
    }

    @Test func aBareWordKeyIsRead() throws {
        // Réel : `[CP] Krobus Dialogue Mod - SVE/content.json` L.83.
        let tree = try #require(ConfigJSONTree.parse(#"{ winter_2: "une réplique" }"#))
        guard case .object(let root) = tree else { Issue.record("attendu un objet"); return }
        #expect(root.keys == ["winter_2"])
        #expect(root.members["winter_2"] == .string("une réplique"))
    }

    @Test func aBareKeyOutsideNewtonsoftsSetStaysRefused() {
        // La borne du cas précédent : `.` et `-` sont **hors** du jeu de
        // caractères d'une clé nue chez Newtonsoft. Un nettoyeur les tolère
        // pour lire ; nous, non — `parse` alimente le témoin « JSON
        // invalide » de l'éditeur, et le dire valide pour un fichier que le
        // jeu refuse serait le mensonge inverse.
        #expect(ConfigJSONTree.parse(#"{ config.name: 1 }"#) == nil)
        #expect(ConfigJSONTree.parse(#"{ mon-reglage: 1 }"#) == nil)
    }

    @Test func aSingleQuotedStringIsRead() throws {
        // Réel : `[CP] WTDR/content.json` L.2249 — une action entière entre
        // guillemets simples, avec des guillemets **doubles** à l'intérieur.
        // Le guillemet ouvrant fait terminateur : les doubles sont du texte.
        let tree = try #require(ConfigJSONTree.parse(
            #"{ "Actions": ['MigrateIds Items "JsonAssets:objects:Eerie Seeds" (O)Seeds'] }"#))
        guard case .object(let root) = tree,
              case .array(let items)? = root.members["Actions"] else {
            Issue.record("attendu un tableau"); return
        }
        #expect(items == [.string(#"MigrateIds Items "JsonAssets:objects:Eerie Seeds" (O)Seeds"#)])
    }

    @Test func aSingleQuotedKeyIsRead() throws {
        let tree = try #require(ConfigJSONTree.parse("{ 'A': 1 }"))
        guard case .object(let root) = tree else { Issue.record("attendu un objet"); return }
        #expect(root.keys == ["A"])
    }

    @Test func aStringMayRunAcrossLines() throws {
        // Réel : `[CP] Friendable Mr Qi/content.json` L.105-109 — la cible
        // du patch est une liste écrite sur cinq lignes, dans une seule
        // chaîne. Newtonsoft lit les retours à la ligne bruts (mesuré sur sa
        // DLL pour `I18nLenientParser`) ; nous les refusions.
        let tree = try #require(ConfigJSONTree.parse("""
        {
        \t"Target":\u{0020}
        \t"Mods/AngelOfStars.Mrqifriendable/QiObjects,
        \tMods/AngelOfStars.Mrqifriendable/QiCrops"
        }
        """))
        guard case .object(let root) = tree,
              case .string(let target)? = root.members["Target"] else {
            Issue.record("attendu une chaîne"); return
        }
        #expect(target.contains("\n"))
        #expect(target.contains("QiObjects"))
        #expect(target.contains("QiCrops"))
    }

    @Test func aMultilineStringSurvivesARoundTrip() throws {
        // La leniance ne doit rien perdre : le retour à la ligne brut
        // ressort **échappé**, et `write` se relit — sans quoi il rendrait
        // `nil` au lieu d'un fichier.
        let tree = try #require(ConfigJSONTree.parse("{\"A\": \"deux\nlignes\"}"))
        let text = try #require(ConfigJSONTree.write(tree))
        #expect(text == "{\n  \"A\": \"deux\\nlignes\"\n}")
        #expect(ConfigJSONTree.parse(text) == tree)
    }

    @Test func aByteOrderMarkDoesNotHideTheFile() throws {
        // Le piège documenté du dépôt : `EF BB BF` en tête fait échouer une
        // lecture sur un fichier par ailleurs parfaitement valide. SMAPI
        // retire la marque ; `I18nLenientParser` aussi.
        let tree = try #require(ConfigJSONTree.parse("\u{FEFF}{ \"A\": 1 }"))
        guard case .object(let root) = tree else { Issue.record("attendu un objet"); return }
        #expect(root.keys == ["A"])
    }

    @Test func brokenTextIsStillRefused() {
        // La contrepartie : la leniance n'est pas un « accepte tout ». Le
        // repli verbatim de la restauration dépend de ce `nil`.
        #expect(ConfigJSONTree.parse(#"{ "A": "jamais fermée"#) == nil)
        #expect(ConfigJSONTree.parse(#"{ "A" 1 }"#) == nil)
        #expect(ConfigJSONTree.parse(#"{ "A": 1,, "B": 2 }"#) == nil)
        // Réel : `.BushBloomMod/content.json` — un tableau en racine. Un
        // `config.json` est un objet ; ce fichier reste illisible, et c'est
        // juste (il ne porte aucun `ConfigSchema`).
        #expect(ConfigJSONTree.parse(#"[{ "StartSeason": "fall" }]"#) == nil)
    }

    @Test func anEscapedEmojiIsRead() throws {
        // Une paire de substitution est la forme **normale** d'un caractère
        // hors du plan de base en JSON, et celle que .NET produit dès qu'il
        // échappe. Le parc en porte : trois `i18n` de `.SexyMarketIdols`
        // écrivent leurs libellés comme ça. Aucun `config.json` (0 sur 593)
        // ni `content.json` (0 sur 606) pour l'instant — d'où un
        // durcissement sans cas observé côté configs.
        let json = ##"{ "A": "\ud83d\ude00 ok" }"##
        let tree = try #require(ConfigJSONTree.parse(json))
        guard case .object(let root) = tree else { Issue.record("attendu un objet"); return }
        #expect(root.members["A"] == .string("\u{1F600} ok"))
    }

    @Test func aBasicPlaneEscapeStillWorks() throws {
        let json = ##"{ "A": "caf\u00e9" }"##
        let tree = try #require(ConfigJSONTree.parse(json))
        guard case .object(let root) = tree else { Issue.record("attendu un objet"); return }
        #expect(root.members["A"] == .string("café"))
    }

    @Test func anOrphanSurrogateIsRefusedRatherThanSubstituted() {
        // Jamais U+FFFD : cet arbre repart en écriture, et une substitution
        // silencieuse corromprait la valeur que l'éditeur réécrit.
        #expect(ConfigJSONTree.parse(#"{ "A": "\ud83d" }"#) == nil)
        #expect(ConfigJSONTree.parse(#"{ "A": "\ude00" }"#) == nil)
        #expect(ConfigJSONTree.parse(#"{ "A": "\ud83dA" }"#) == nil)
    }

    @Test func anEmojiSurvivesARoundTrip() throws {
        let tree = try #require(ConfigJSONTree.parse(##"{ "A": "\ud83d\ude00" }"##))
        let text = try #require(ConfigJSONTree.write(tree))
        // `escape` rend le caractère tel quel — JSON valide — et la relecture
        // que `write` s'impose le confirme.
        #expect(text.contains("\u{1F600}"))
        #expect(ConfigJSONTree.parse(text) == tree)
    }

    @Test func inlineRendersCompactly() {
        let tree = ConfigJSONTree.parse(#"{"A": 1, "B": [1, 2], "C": {"D": true}}"#)!
        let text = ConfigJSONTree.inline(tree)
        #expect(text == #"{"A":1,"B":[1,2],"C":{"D":true}}"#)
    }
}
