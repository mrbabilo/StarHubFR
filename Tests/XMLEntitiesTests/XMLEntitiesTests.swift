import Testing
@testable import StarHubTHCore

/// Échappement XML des valeurs de sauvegarde : sans lui, « D&D Farm » produit
/// un XML invalide et la save disparaît au prochain scan. Audit 2026-08-05,
/// `SaveManager:540/578`.
struct XMLEntitiesTests {
    @Test func ampersandIsEscaped() {
        #expect(XMLEntities.escape("D&D Farm") == "D&amp;D Farm")
    }

    @Test func angleBracketsAreEscaped() {
        #expect(XMLEntities.escape("x<y>z") == "x&lt;y&gt;z")
    }

    @Test func quotesAreEscaped() {
        #expect(XMLEntities.escape("a\"b'c") == "a&quot;b&apos;c")
    }

    @Test func ampersandIsNotDoubleEscaped() {
        // Le `&` ajouté par `&lt;` ne doit pas être ré-échappé en `&amp;lt;`.
        #expect(XMLEntities.escape("<") == "&lt;")
        #expect(XMLEntities.escape(">") == "&gt;")
        #expect(XMLEntities.escape("&") == "&amp;")
        #expect(XMLEntities.escape("& <") == "&amp; &lt;")
    }

    @Test func unescapeReversesEachEntity() {
        #expect(XMLEntities.unescape("D&amp;D Farm") == "D&D Farm")
        #expect(XMLEntities.unescape("x&lt;y&gt;z") == "x<y>z")
        #expect(XMLEntities.unescape("a&quot;b&apos;c") == "a\"b'c")
    }

    @Test func escapeAndUnescapeRoundTrip() {
        let samples = [
            "D&D Farm", "x<y", "a\"b'c>d", "Tom & Jerry",
            "", "plain", "100% < 200% & more", "Mœbius < ∞"
        ]
        for s in samples {
            #expect(XMLEntities.unescape(XMLEntities.escape(s)) == s, "round-trip failed for: \(s)")
        }
    }

    @Test func unescapeAmpersandLastDoesNotCollapseAmpLt() {
        // `&amp;lt;` représente le littéral « &lt; », pas « < » : traiter
        // `&amp;` en dernier le préserve.
        #expect(XMLEntities.unescape("&amp;lt;") == "&lt;")
        #expect(XMLEntities.unescape("&amp;gt;") == "&gt;")
    }

    @Test func emptyStaysEmpty() {
        #expect(XMLEntities.escape("") == "")
        #expect(XMLEntities.unescape("") == "")
    }

    @Test func alreadyEscapedTextIsLeftAsIsByUnescape() {
        // Une valeur lue proprement (déjà échappée par Stardew) est décodée
        // une seule fois, pas deux.
        #expect(XMLEntities.unescape("B&amp;J") == "B&J")
        #expect(XMLEntities.escape(XMLEntities.unescape("B&amp;J")) == "B&amp;J")
    }
}
