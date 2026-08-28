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


/// La traduction d'un schéma de content pack par le `i18n/` du pack.
///
/// Découvert à l'écran, pas par les tests : sur `[CP] More Upgrades`, les
/// `Name` et `Description` du schéma valent `{{i18n: config.Appearance.Name}}`
/// — un jeton que Content Patcher résout à l'exécution et que l'app affichait
/// tel quel. **9 des 210 packs à schéma du parc** posent des jetons (285 en
/// tout, tous dans `Name` et `Description`, aucun dans `Section` ni
/// `AllowValues`), et les 9 ont un `i18n/` avec `fr.json`.
///
/// La mesure a rapporté plus large : Content Patcher cherche aussi
/// `config.<clé>.name` **sans jeton**, par convention. Sur les 116 packs à
/// table de traduction, **1888 clés sur 2061 y ont un libellé** et 1581 une
/// description — là où le schéma seul n'en donnait presque aucune (173 `Name`
/// sur tout le parc).
struct ContentPackI18nTests {

    private func option(_ token: String, name: String? = nil,
                        description: String? = nil, section: String? = nil) -> ConfigSchemaOption {
        ConfigSchemaOption(token: token, name: name, description: description, section: section,
                           allowValues: [], defaultLiteral: nil, allowBlank: nil, allowMultiple: nil)
    }

    @Test func resolvesAnI18nToken() {
        let localized = ContentPackI18n.localized(
            [option("Appearance", name: "{{i18n: config.Appearance.Name}}")],
            with: ["config.Appearance.Name": "Apparence"])
        #expect(localized[0].name == "Apparence")
    }

    @Test func theKeyLookupIgnoresCase() {
        // SMAPI compare les clés de traduction sans regard pour la casse, et
        // les paquets du parc écrivent `.Name` dans le jeton pour `.name` dans
        // la table aussi souvent que l'inverse.
        let localized = ContentPackI18n.localized(
            [option("Appearance", name: "{{i18n: config.Appearance.Name}}")],
            with: ["config.appearance.name": "Apparence"])
        #expect(localized[0].name == "Apparence")
    }

    @Test func toleratesASpacelessTokenAndSurroundingText() {
        let localized = ContentPackI18n.localized(
            [option("A", name: "→ {{i18n:k}} ←")],
            with: ["k": "valeur"])
        #expect(localized[0].name == "→ valeur ←")
    }

    @Test func theImplicitConventionLabelsAnOptionTheSchemaLeftBare() {
        // Le cas le plus fréquent : le schéma ne porte **aucun** `Name`, mais
        // la table du pack a `config.<clé>.name`.
        let localized = ContentPackI18n.localized(
            [option("SuperBarn")],
            with: ["config.superbarn.name": "Super grange",
                   "config.superbarn.description": "Agrandit la grange."])
        #expect(localized[0].name == "Super grange")
        #expect(localized[0].description == "Agrandit la grange.")
    }

    @Test func sectionsAreTranslatedByTheirOwnConvention() {
        let localized = ContentPackI18n.localized(
            [option("A", section: "General")],
            with: ["config.section.general.name": "Options générales"])
        #expect(localized[0].section == "Options générales")
    }

    @Test func anUnresolvedTokenFallsBackToTheConventionThenToNothing() {
        // Jamais le jeton brut à l'écran : `ConfigEditorModel.Row` retombe sur
        // la clé, qui est au moins lisible.
        let withConvention = ContentPackI18n.localized(
            [option("A", name: "{{i18n: absente}}")],
            with: ["config.a.name": "Rattrapé"])
        #expect(withConvention[0].name == "Rattrapé")

        let withNothing = ContentPackI18n.localized([option("A", name: "{{i18n: absente}}")], with: [:])
        #expect(withNothing[0].name == nil)
    }

    @Test func aTokenThatIsNotAnI18nLookupIsNotShownEither() {
        // Relevé sur le parc : `{{config.OMEGAlinc_….name}}`, qui désigne la
        // valeur d'une autre option, pas une traduction. 4 cas.
        let localized = ContentPackI18n.localized(
            [option("A", name: "{{config.Autre.name}}")], with: [:])
        #expect(localized[0].name == nil)
    }

    @Test func aPlainLabelIsLeftAlone() {
        let localized = ContentPackI18n.localized(
            [option("A", name: "Mon réglage", description: "Ce qu'il fait.", section: "Divers")],
            with: [:])
        #expect(localized[0].name == "Mon réglage")
        #expect(localized[0].description == "Ce qu'il fait.")
        #expect(localized[0].section == "Divers")
    }

    @Test func theSchemaWinsOverTheConvention() {
        // Un `Name` explicite et sans jeton est ce que l'auteur a écrit là
        // pour cette option : il passe avant la table.
        let localized = ContentPackI18n.localized(
            [option("A", name: "Explicite")], with: ["config.a.name": "Par convention"])
        #expect(localized[0].name == "Explicite")
    }

    @Test func theLocaleIsTriedThenDefaultThenEnglish() {
        #expect(ContentPackI18n.localeCandidates(for: "fr") == ["fr", "default", "en"])
        #expect(ContentPackI18n.localeCandidates(for: "en") == ["en", "default"])
    }
}
