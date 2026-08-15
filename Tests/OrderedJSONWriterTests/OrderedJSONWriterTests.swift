import Testing
import Foundation
@testable import StarHubTHCore

/// L'ordre des clés est l'invariant fil rouge du hub : un auteur range son
/// fichier par scène, par personnage, par ordre d'apparition. Le réécrire trié
/// ou au hasard rend son fichier méconnaissable et tout diff ultérieur
/// illisible.
struct OrderedJSONWriterTests {

    @Test func keysAreWrittenInTheGivenOrderNotSorted() throws {
        let text = try OrderedJSONWriter.text(
            orderedKeys: ["zeta", "alpha", "mid"],
            values: ["zeta": "Z", "alpha": "A", "mid": "M"])
        let zeta = try #require(text.range(of: "\"zeta\""))
        let alpha = try #require(text.range(of: "\"alpha\""))
        let mid = try #require(text.range(of: "\"mid\""))
        #expect(zeta.lowerBound < alpha.lowerBound)
        #expect(alpha.lowerBound < mid.lowerBound)
    }

    @Test func theResultReparsesToTheSameValues() throws {
        let values = ["a": "Bonjour {{PlayerName}}",
                      "b": "Ligne\nsuivante",
                      "c": "Guillemet \" et \\ antislash"]
        let text = try OrderedJSONWriter.text(orderedKeys: ["a", "b", "c"], values: values)
        #expect(try I18nLenientParser.parse(text) == values)
    }

    @Test func aKeyWithoutValueIsOmitted() throws {
        // Une clé non traduite ne s'écrit pas : SMAPI retombe sur
        // `default.json`, alors qu'une chaîne vide n'affiche rien en jeu.
        let text = try OrderedJSONWriter.text(orderedKeys: ["a", "b"], values: ["a": "A"])
        #expect(text.contains("\"b\"") == false)
    }

    @Test func anEmptyDocumentIsStillValidJSON() throws {
        let text = try OrderedJSONWriter.text(orderedKeys: [], values: [:])
        #expect(try I18nLenientParser.parse(text).isEmpty)
    }

    @Test func theTextEndsWithASingleNewline() throws {
        let text = try OrderedJSONWriter.text(orderedKeys: ["a"], values: ["a": "A"])
        #expect(text.hasSuffix("}\n"))
        #expect(text.hasSuffix("}\n\n") == false)
    }

    @Test func aControlCharacterIsEscapedNotEmitted() throws {
        // Un caractère de contrôle brut rend le JSON illisible au jeu. Le
        // parseur laxiste du dépôt les tolère en lecture ; à l'écriture, on
        // n'en produit pas.
        let text = try OrderedJSONWriter.text(orderedKeys: ["a"], values: ["a": "x\u{1}y"])
        #expect(text.contains("\u{1}") == false)
        #expect(try I18nLenientParser.parse(text)["a"] == "x\u{1}y")
    }
}
