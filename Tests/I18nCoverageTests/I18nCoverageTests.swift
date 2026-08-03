import Testing
import Foundation
@testable import StarHubTHCore

/// Le parseur i18n laxiste : il reproduit la tolérance du chargeur SMAPI
/// (Newtonsoft.Json) en 4 passes string-aware — commentaires, virgules
/// trailing, clés nues, caractères de contrôle bruts — pour ne refuser
/// aucun fichier qu'un auteur a écrit à la main et que le jeu charge.
/// Port fidèle de `scanner.rs` (Nana1873/stardew-i18n-translator).
struct I18nLenientParserTests {
    @Test func parsesCleanFlatObject() throws {
        let json = #"{"a": "Hello", "b": "World"}"#
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["a"] == "Hello")
        #expect(out["b"] == "World")
        #expect(out.count == 2)
    }

    @Test func stripsLineComments() throws {
        // Vue en conditions réelles (Sebastian's Frog Sanctuary) : des `//`
        // servent de séparateurs de section devant les clés.
        let json = """
        {
            // Config
            "config.name": "Frogs",
            // Dialogue
            "dialogue": "Hi"
        }
        """
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["config.name"] == "Frogs")
        #expect(out["dialogue"] == "Hi")
        #expect(out.count == 2)
    }

    @Test func doesNotStripDoubleSlashInsideAString() throws {
        // Une URL ou un chemin dans une valeur ne doit pas être coupé.
        let json = #"{"url": "https://nexusmods.com/x"}"#
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["url"] == "https://nexusmods.com/x")
    }

    @Test func stripsBlockComments() throws {
        let json = """
        { /* a comment */
            "a": "1" /* trailing */,
            "b": "2"
        }
        """
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["a"] == "1")
        #expect(out["b"] == "2")
    }

    @Test func stripsTrailingCommas() throws {
        let json = #"{"a": "1", "b": "2",}"#
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out.count == 2)
        #expect(out["b"] == "2")
    }

    @Test func trailingCommaRemovalIsStringAware() throws {
        // Une virgule suivie de `}` dans une valeur ne doit pas être retirée —
        // seul le séparateur structural trailing l'est. Un regex non
        // string-aware corromprait `"x,}"` en `"x}"`. (Bug évité dans la réf.)
        let out = try #require(try? I18nLenientParser.parse(#"{"a": "x,}",}"#))
        #expect(out["a"] == "x,}")
        #expect(out.count == 1)
    }

    @Test func quotesBareJavaScriptStyleKeys() throws {
        // Newtonsoft accepte les clés non quotées ; JSONSerialization non.
        let out = try #require(try? I18nLenientParser.parse(#"{ Key: "v", "other": "w" }"#))
        #expect(out["Key"] == "v")
        #expect(out["other"] == "w")
    }

    @Test func doesNotQuoteBareLookingTextInValues() throws {
        // Le quantage des clés nues n'agit qu'en position de clé (après `{`/`,`),
        // jamais dans une valeur.
        let out = try #require(try? I18nLenientParser.parse(#"{"a": "not: a key"}"#))
        #expect(out["a"] == "not: a key")
    }

    @Test func stripsBom() throws {
        let json = "\u{FEFF}" + #"{"a": "1"}"#
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["a"] == "1")
    }

    @Test func escapesRawNewlineInsideAString() throws {
        // SMAPI accepte un raw \n dans une valeur ; JSON strict non.
        // Le parseur l'échappe avant JSONSerialization.
        let json = "{\n\"a\": \"line one\nline two\"\n}"
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["a"] == "line one\nline two")
    }

    @Test func stripsLineCommentsInACrlfFile() throws {
        // Cas réel ([CP] Cornucopia More Flowers) : fichier en CRLF avec des
        // commentaires de section. En Swift, `\r\n` est **un seul** Character —
        // le comparer à `"\n"` échoue, et un parcours par Character fait courir
        // la coupure du commentaire jusqu'à la fin du fichier.
        let json = "{\r\n\t// Crop produce\r\n  \"a\": \"1\",\r\n  \"b\": \"2\"\r\n}"
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["a"] == "1")
        #expect(out["b"] == "2")
        #expect(out.count == 2)
    }

    @Test func stripsLineCommentsTerminatedByALoneCarriageReturn() throws {
        // Fins de ligne héritées de Mac OS classique : le commentaire s'arrête
        // au `\r` seul comme il s'arrêterait à un `\n`.
        let json = "{\r // note\r \"a\": \"1\"\r}"
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["a"] == "1")
    }

    @Test func escapesRawCrlfInsideAString() throws {
        // Même racine que ci-dessus, passe 4 : le cluster `\r\n` ne correspond
        // ni au cas `"\n"` ni au cas `"\r"` et resterait brut dans le JSON.
        let json = "{\"a\": \"line one\r\nline two\"}"
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["a"] == "line one\r\nline two")
    }

    @Test func ignoresDollarSchemaKey() throws {
        let json = #"{"$schema": "http://…", "a": "1"}"#
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out.count == 1)
        #expect(out["a"] == "1")
    }

    @Test func rejectsMalformedJson() throws {
        #expect(throws: I18nLenientParser.ParseError.self) {
            _ = try I18nLenientParser.parse("{not json at all")
        }
    }

    @Test func rejectsNonStringValue() throws {
        // Un objet i18n SMAPI est plat et string-string ; une valeur
        // non-string n'en est pas un.
        #expect(throws: I18nLenientParser.ParseError.self) {
            _ = try I18nLenientParser.parse(#"{"a": 42}"#)
        }
    }

    @Test func parsesARealShape() throws {
        // Forme réelle observée (.StorageTerminal) : indentation, lignes vides,
        // tokens entre accolades.
        let json = """
        {
            "menu.network-chests.one": "Network: {{count}} chest linked",
            "menu.filtered-count": "   [{{shown}}/{{total}} filtered]"
        }
        """
        let out = try #require(try? I18nLenientParser.parse(json))
        #expect(out["menu.network-chests.one"] == "Network: {{count}} chest linked")
    }
}

/// Ce que SMAPI **charge réellement**. Le parseur va plus loin que lui pour
/// pouvoir lire un fichier abîmé ; cette fonction dit si le jeu l'accepterait.
/// Sans elle, un mod afficherait « 100 % traduit » alors que son français ne se
/// chargera jamais — l'inverse du service rendu.
struct I18nSmapiAcceptanceTests {
    @Test func whatSmapiToleratesIsAccepted() throws {
        // Commentaires et virgules trailing : le schéma officiel i18n.json les
        // autorise (allowComments, allowTrailingCommas).
        #expect(I18nLenientParser.smapiAccepts(#"{"a": "1"}"#))
        #expect(I18nLenientParser.smapiAccepts("{\n // note\n \"a\": \"1\",\n}"))
    }

    @Test func crlfLineEndingsStayAcceptedBySmapi() throws {
        // Un CRLF entre deux entrées est une espace JSON parfaitement légale :
        // la réparation ne doit pas s'y déclencher, sinon la moitié du parc de
        // fichiers (écrits sous Windows) serait signalée à tort comme refusée
        // par le jeu.
        #expect(I18nLenientParser.smapiAccepts("{\r\n\t// note\r\n  \"a\": \"1\",\r\n}"))
    }

    @Test func ordinaryBareKeysAreAcceptedBySmapi() throws {
        // Mesuré sur la `Newtonsoft.Json.dll` du jeu : une clé nue passe tant
        // qu'elle reste dans son jeu de caractères — lettres, chiffres, `_`, `$`.
        #expect(I18nLenientParser.smapiAccepts(#"{ Key: "v" }"#))
        #expect(I18nLenientParser.smapiAccepts(#"{ key_1: "v", $x: "w", clé: "y" }"#))
    }

    @Test func dottedOrHyphenatedBareKeysAreRejectedBySmapi() throws {
        // C'est là que Newtonsoft s'arrête, et c'est le seul cas où notre
        // réparation de clé nue signale un refus du jeu. Les clés i18n étant
        // pointées par convention, la distinction n'est pas théorique.
        #expect(!I18nLenientParser.smapiAccepts(#"{ config.name: "v" }"#))
        #expect(!I18nLenientParser.smapiAccepts(#"{ my-key: "v" }"#))
    }

    @Test func rawControlCharactersAreAcceptedBySmapi() throws {
        // Newtonsoft lit un retour à la ligne ou une tabulation bruts dans une
        // valeur ; seul `JSONSerialization` les refuse, d'où notre passe 4.
        #expect(I18nLenientParser.smapiAccepts("{\"a\": \"line one\nline two\"}"))
        #expect(I18nLenientParser.smapiAccepts("{\"a\": \"col\tonne\"}"))
    }

    @Test func aFileSmapiRefusesIsStillReadable() throws {
        // Les deux réponses sont indépendantes : on lit, et on signale.
        let text = #"{ config.name: "v" }"#
        #expect((try? I18nLenientParser.parse(text)) != nil)
        #expect(!I18nLenientParser.smapiAccepts(text))
    }

    @Test func malformedJsonIsNotAcceptedEither() throws {
        #expect(!I18nLenientParser.smapiAccepts("{not json at all"))
    }
}

