import Testing
import Foundation
@testable import StarHubTHCore

/// L'ordre d'un fichier neuf suit celui de sa source ; celui d'un fichier
/// existant lui appartient. Réordonner le travail d'un traducteur sur la source
/// lui réécrirait son fichier sans qu'il l'ait demandé.
struct TranslationDocumentTests {

    private let source = """
    {
      "intro": "Hello",
      "middle": "World",
      "outro": "Bye"
    }
    """

    @Test func aNewFileFollowsTheSourceOrder() throws {
        let text = try TranslationDocument.create(
            fromSource: source,
            translations: ["outro": "Salut", "intro": "Bonjour"])
        let intro = try #require(text.range(of: "\"intro\""))
        let outro = try #require(text.range(of: "\"outro\""))
        #expect(intro.lowerBound < outro.lowerBound)
    }

    @Test func anUntranslatedKeyIsAbsentFromANewFile() throws {
        // Omise, pas vide : SMAPI retombe sur `default.json`, quand une chaîne
        // vide n'afficherait rien du tout en jeu.
        let text = try TranslationDocument.create(fromSource: source,
                                                  translations: ["intro": "Bonjour"])
        #expect(text.contains("\"middle\"") == false)
    }

    @Test func anEditKeepsTheExistingOrderOfTheTargetFile() throws {
        let target = """
        {
          "outro": "Salut",
          "intro": "Bonjour"
        }
        """
        let text = try TranslationDocument.apply(edits: ["intro": "Salut à toi"],
                                                 toTarget: target, sourceText: source)
        let outro = try #require(text.range(of: "\"outro\""))
        let intro = try #require(text.range(of: "\"intro\""))
        #expect(outro.lowerBound < intro.lowerBound, "l'ordre du traducteur est conservé")
        #expect(try I18nLenientParser.parse(text)["intro"] == "Salut à toi")
    }

    @Test func aNewlyTranslatedKeyIsAppendedNotInserted() throws {
        // Une clé que la cible n'avait pas rejoint la fin : lui deviner une
        // place au milieu réordonnerait le fichier du traducteur.
        let target = "{ \"intro\": \"Bonjour\" }"
        let text = try TranslationDocument.apply(edits: ["outro": "Salut"],
                                                 toTarget: target, sourceText: source)
        let intro = try #require(text.range(of: "\"intro\""))
        let outro = try #require(text.range(of: "\"outro\""))
        #expect(intro.lowerBound < outro.lowerBound)
    }

    @Test func anEmptyEditRemovesTheKey() throws {
        let target = "{ \"intro\": \"Bonjour\", \"outro\": \"Salut\" }"
        let text = try TranslationDocument.apply(edits: ["outro": ""],
                                                 toTarget: target, sourceText: source)
        #expect(text.contains("\"outro\"") == false)
        #expect(try I18nLenientParser.parse(text)["intro"] == "Bonjour")
    }

    @Test func anUnreadableSourceIsRejectedNotEmptied() {
        // Jamais d'état inventé : un source cassé doit lever, pas produire un
        // fichier vide qui effacerait la traduction qu'il prétend mettre à jour.
        #expect(throws: TranslationDocument.DocumentError.sourceUnreadable) {
            try TranslationDocument.create(fromSource: "{ cassé", translations: [:])
        }
    }

    @Test func anUnreadableTargetIsRejectedNotOverwritten() {
        #expect(throws: TranslationDocument.DocumentError.targetUnreadable) {
            try TranslationDocument.apply(edits: ["intro": "Bonjour"],
                                          toTarget: "{ cassé", sourceText: source)
        }
    }

    @Test func aKeyTheSourceDoesNotDeclareIsRefused() throws {
        // Traduire une clé qui n'existe ni dans la cible ni dans la source n'a
        // pas de sens : elle ne serait jamais lue par le jeu. Refuser plutôt
        // que d'écrire une ligne morte.
        #expect(throws: (any Error).self) {
            try TranslationDocument.create(fromSource: source,
                                           translations: ["inconnue": "X"])
        }
    }

    @Test func aJsoncTargetKeepsItsOrderThroughAnEdit() throws {
        // Les fichiers réels portent commentaires et virgules finales : c'est
        // le cas courant, pas un cas limite.
        let target = """
        {
          // les adieux d'abord
          "outro": "Salut",
          "intro": "Bonjour",
        }
        """
        let text = try TranslationDocument.apply(edits: ["intro": "Coucou"],
                                                 toTarget: target, sourceText: source)
        let outro = try #require(text.range(of: "\"outro\""))
        let intro = try #require(text.range(of: "\"intro\""))
        #expect(outro.lowerBound < intro.lowerBound)
        #expect(try I18nLenientParser.parse(text)["intro"] == "Coucou")
    }

    @Test func aTargetWithARepeatedKeyStaysEditable() throws {
        // Mesuré : 71 des 2387 fichiers i18n du parc portent une clé répétée,
        // `fr.json` compris. Refuser de les enregistrer les rendrait
        // définitivement inéditables. Le doublon disparaît donc du fichier
        // écrit : c'est une réparation, et le `.bak` garde l'original.
        //
        // La valeur retenue est la **première**, et la position aussi — c'est
        // ce que rendent `I18nLenientParser` et `JSONSerialization`, vérifié.
        // Autrement dit : on réécrit exactement ce que l'app a montré au
        // traducteur. ⚠️ Ce que le jeu retient, lui, n'est pas vérifié ici —
        // Newtonsoft pourrait garder la dernière. À trancher avant de se fier
        // à ces 71 fichiers pour autre chose que de l'édition.
        let target = """
        {
          "intro": "Bonjour",
          "outro": "Salut",
          "intro": "Rebonjour"
        }
        """
        let text = try TranslationDocument.apply(edits: [:], toTarget: target,
                                                 sourceText: source)
        let parsed = try I18nLenientParser.parse(text)
        #expect(parsed["intro"] == "Bonjour", "celle que l'app a montrée au traducteur")
        let intro = try #require(text.range(of: "\"intro\""))
        let outro = try #require(text.range(of: "\"outro\""))
        #expect(intro.lowerBound < outro.lowerBound, "la première position est gardée")
        #expect(text.components(separatedBy: "\"intro\"").count == 2, "une seule occurrence")
    }
}
