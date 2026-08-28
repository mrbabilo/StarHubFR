import Testing
import Foundation
@testable import StarHubTHCore

/// Le `ConfigSchema` d'un `content.json` de Content Patcher (**C4-T4**).
///
/// Chaque cas ci-dessous fige une forme **relevée sur le parc réel** le
/// 2026-08-28 (1017 mods, 276 packs à schéma, 6376 tokens), pas une lecture de
/// la documentation : celle-ci ne mentionne ni `Section` — le champ le plus
/// fréquent après `Default` et `AllowValues` — ni les coquilles qui circulent.
/// Détail des relevés : `docs/audit-config-menus.md`.
struct ContentPackConfigSchemaTests {

    @Test func keepsTheAuthorsOrderRatherThanAlphabetical() {
        // L'éditeur affiche aujourd'hui les options triées par nom
        // (`ModConfigEditorView`, `dict.keys.sorted()`), ce que C4-T5 corrige.
        // Le schéma, lui, doit rendre l'ordre du fichier.
        let options = ContentPackConfigSchema.parse(#"""
        {
          "Format": "2.7.0",
          "ConfigSchema": {
            "Zoom":    { "Default": true },
            "Alpha":   { "Default": false },
            "Middle":  { "Default": true }
          }
        }
        """#)
        #expect(options.map(\.token) == ["Zoom", "Alpha", "Middle"])
    }

    @Test func readsNameDescriptionAndSection() {
        let options = ContentPackConfigSchema.parse(#"""
        { "ConfigSchema": { "EnableJohn": {
            "Name": "Activer John",
            "Description": "Ajoute le PNJ John au village.",
            "Section": "Personnages",
            "Default": true } } }
        """#)
        #expect(options.count == 1)
        #expect(options[0].name == "Activer John")
        #expect(options[0].description == "Ajoute le PNJ John au village.")
        #expect(options[0].section == "Personnages")
    }

    @Test func allowValuesSplitsOnCommaAndDropsTheTrailingEmpty() {
        // Relevé : « 3, 7, 14, 21, » et « 1, 2, …, 20, » — la virgule
        // traînante est courante et ne doit pas produire une valeur vide,
        // qui s'afficherait comme un choix sélectionnable sans libellé.
        let options = ContentPackConfigSchema.parse(#"""
        { "ConfigSchema": { "Delay": { "AllowValues": "3, 7, 14, 21,", "Default": "7" } } }
        """#)
        #expect(options[0].allowValues == ["3", "7", "14", "21"])
    }

    @Test func defaultKeepsItsLiteralWhateverTheJsonType() {
        // Relevé : Default arrive en chaîne (5586), booléen (466),
        // entier (243) et flottant (77). Aucun ne doit être perdu ni reformaté
        // — `0.5` ne doit pas devenir `0.500000`.
        let options = ContentPackConfigSchema.parse(#"""
        { "ConfigSchema": {
            "AsText":  { "Default": "OneDay" },
            "AsBool":  { "Default": true },
            "AsInt":   { "Default": 12 },
            "AsFloat": { "Default": 0.5 } } }
        """#)
        #expect(options.map(\.defaultLiteral) == ["OneDay", "true", "12", "0.5"])
    }

    @Test func fieldNamesAreMatchedIgnoringCaseAndSpaces() {
        // Relevé : « Allow Multiple » avec une espace (40 fois),
        // « section » et « description » en minuscules (36 fois).
        let options = ContentPackConfigSchema.parse(#"""
        { "ConfigSchema": { "Tok": {
            "Allow Multiple": true,
            "section": "Divers",
            "description": "en minuscules" } } }
        """#)
        #expect(options[0].allowMultiple == true)
        #expect(options[0].section == "Divers")
        #expect(options[0].description == "en minuscules")
    }

    @Test func booleanFlagsAlsoAcceptTheStringForm() {
        // Relevé : AllowBlank / AllowMultiple sont booléens 1220 fois,
        // mais des chaînes 99 fois.
        let options = ContentPackConfigSchema.parse(#"""
        { "ConfigSchema": { "Tok": { "AllowBlank": "true", "AllowMultiple": "FALSE" } } }
        """#)
        #expect(options[0].allowBlank == true)
        #expect(options[0].allowMultiple == false)
    }

    @Test func unknownFieldsAreIgnoredWithoutLosingTheOption() {
        // Relevé : « HostowValues » et « HostowBlank », une occurrence chacune
        // — un remplacement « All » → « Host » qui a débordé chez un auteur.
        // L'option doit survivre, amputée du champ, jamais disparaître.
        let options = ContentPackConfigSchema.parse(#"""
        { "ConfigSchema": { "Tok": { "HostowValues": "a, b", "Default": "a" } } }
        """#)
        #expect(options.count == 1)
        #expect(options[0].token == "Tok")
        #expect(options[0].allowValues.isEmpty)
        #expect(options[0].defaultLiteral == "a")
    }

    @Test func acceptsTheJson5ThatContentPatcherItselfAccepts() {
        // Les `content.json` du parc portent commentaires et virgules
        // traînantes ; 14 restent illisibles même ainsi, et l'appelant doit
        // alors se replier sur l'éditeur brut — d'où le tableau vide, jamais
        // une erreur.
        let options = ContentPackConfigSchema.parse(#"""
        {
          // le format d'abord
          "Format": "2.7.0",
          "ConfigSchema": {
            "Tok": { "Default": true, }, /* bloc */
          },
        }
        """#)
        #expect(options.map(\.token) == ["Tok"])
        #expect(ContentPackConfigSchema.parse("{ pas du json").isEmpty)
    }

    @Test func aContentJsonWithoutConfigSchemaYieldsNothing() {
        #expect(ContentPackConfigSchema.parse(#"{ "Format": "2.7.0", "Changes": [] }"#).isEmpty)
    }
}

/// Distinguer « ce pack ne décrit rien » de « ce pack décrit ses options et
/// nous n'avons pas su le lire ». Sur le parc, **14 `content.json` sur 591**
/// tombent dans le second cas : sans cette distinction, l'éditeur y affiche
/// des clés brutes sans dire pourquoi.
struct ConfigSchemaReadingTests {

    @Test func anUnreadableContentJsonIsNotTheSameAsOneWithoutSchema() {
        #expect(ContentPackConfigSchema.read("{ pas du json") == .unreadable)
        #expect(ContentPackConfigSchema.read(#"{ "Format": "2.7.0" }"#) == .noSchema)
    }

    @Test func anEmptySchemaHasNothingToSignal() {
        // Lisible, et rien à décorer : l'éditeur montre les clés brutes sans
        // avertissement — ce n'est pas un échec.
        #expect(ContentPackConfigSchema.read(#"{ "ConfigSchema": {} }"#) == .noSchema)
    }

    @Test func aReadableSchemaCarriesItsOptions() {
        let reading = ContentPackConfigSchema.read(#"{ "ConfigSchema": { "Tok": { "Default": true } } }"#)
        #expect(reading.options.map(\.token) == ["Tok"])
        #expect(reading != .noSchema)
    }

    @Test func optionsIsEmptyOnBothFailingReadings() {
        #expect(ContentPackConfigSchema.read("{ pas du json").options.isEmpty)
        #expect(ContentPackConfigSchema.read(#"{ "Format": "2.7.0" }"#).options.isEmpty)
    }
}
