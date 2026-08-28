import Testing
import Foundation
@testable import StarHubTHCore

/// La logique que l'éditeur de config visuel pose sur un `ConfigJSONTree`
/// (**C4-T5**) : aplatir l'arbre en options affichables, et réinjecter la
/// seule valeur que l'utilisateur a touchée.
///
/// Pourquoi ces règles vivent ici et non dans `ModConfigEditorView` : l'écran
/// est hors de portée de `swift test`, et c'est précisément l'ordre des clés
/// et la fidélité des littéraux qui se cassent en silence. Mesuré sur le parc
/// le 2026-08-28 — **363 des 462 `config.json` de premier niveau ont un ordre
/// d'auteur différent de l'ordre alphabétique**, celui que l'écran imposait.
struct ConfigEditorModelTests {

    // MARK: - Aplatissement

    @Test func keepsTheAuthorsOrderRatherThanAlphabetical() {
        let tree = ConfigJSONTree.parse(#"{ "Zoom": true, "Alpha": false, "Middle": 3 }"#)!
        let leaves = ConfigEditorModel.leaves(of: tree)
        #expect(leaves.map { $0.keyPath } == [["Zoom"], ["Alpha"], ["Middle"]])
    }

    @Test func nestedObjectsBecomeMultiSegmentPaths() {
        let tree = ConfigJSONTree.parse(#"{ "Group": { "Inner": { "Leaf": 1 } }, "Top": 2 }"#)!
        let leaves = ConfigEditorModel.leaves(of: tree)
        #expect(leaves.map { $0.keyPath } == [["Group", "Inner", "Leaf"], ["Top"]])
    }

    @Test func arrayElementsAreIndexed() {
        let tree = ConfigJSONTree.parse(#"{ "Keys": ["a", "b"] }"#)!
        let leaves = ConfigEditorModel.leaves(of: tree)
        #expect(leaves.map { $0.keyPath } == [["Keys", "[0]"], ["Keys", "[1]"]])
    }

    @Test func nullIsNotAnEditableOption() {
        // Rien à montrer et rien à réécrire : une valeur nulle sans type
        // n'offre aucun contrôle, et la retyper en chaîne la corromprait.
        let tree = ConfigJSONTree.parse(#"{ "A": null, "B": 1 }"#)!
        #expect(ConfigEditorModel.leaves(of: tree).map { $0.keyPath } == [["B"]])
    }

    @Test func numbersKeepTheirLiteral() {
        let tree = ConfigJSONTree.parse(#"{ "Rate": 1.50, "Big": 9007199254740993 }"#)!
        let leaves = ConfigEditorModel.leaves(of: tree)
        #expect(leaves[0].value == .number("1.50"))
        #expect(leaves[1].value == .number("9007199254740993"))
    }

    @Test func readsAJson5FileThatStrictJsonRefuses() {
        // `JSONSerialization` — ce que l'écran utilisait — rend « JSON
        // invalide » sur ce fichier ; SMAPI, lui, le charge.
        let tree = ConfigJSONTree.parse("""
        {
          // le commentaire de l'auteur
          "Enabled": true,
        }
        """)!
        #expect(ConfigEditorModel.leaves(of: tree).map { $0.keyPath } == [["Enabled"]])
    }

    @Test func readsACrlfFile() {
        let tree = ConfigJSONTree.parse("{\r\n  // note\r\n  \"A\": 1,\r\n  \"B\": 2\r\n}")!
        #expect(ConfigEditorModel.leaves(of: tree).map { $0.keyPath } == [["A"], ["B"]])
    }

    // MARK: - Application d'une édition

    @Test func applyingOneEditLeavesEveryOtherLiteralUntouched() {
        let tree = ConfigJSONTree.parse(#"{ "Rate": 1.50, "Enabled": false, "Big": 9007199254740993 }"#)!
        let edited = ConfigEditorModel.apply(.bool(true), at: ["Enabled"], to: tree)!
        let text = ConfigJSONTree.write(edited)!
        #expect(text.contains("1.50"))
        #expect(text.contains("9007199254740993"))
        #expect(text.contains("\"Enabled\": true"))
    }

    @Test func applyingAnEditKeepsTheKeyOrder() {
        let tree = ConfigJSONTree.parse(#"{ "Zoom": 1, "Alpha": 2 }"#)!
        let edited = ConfigEditorModel.apply(.number("9"), at: ["Alpha"], to: tree)!
        let text = ConfigJSONTree.write(edited)!
        #expect(text.range(of: "Zoom")!.lowerBound < text.range(of: "Alpha")!.lowerBound)
    }

    @Test func appliesInsideNestedObjectsAndArrays() {
        let tree = ConfigJSONTree.parse(#"{ "G": { "Keys": ["a", "b"] } }"#)!
        let edited = ConfigEditorModel.apply(.string("z"), at: ["G", "Keys", "[1]"], to: tree)!
        #expect(ConfigEditorModel.leaves(of: edited).map { $0.value } == [.string("a"), .string("z")])
    }

    @Test func anUnknownPathChangesNothing() {
        // Le chemin vient toujours de l'arbre lui-même ; s'il n'y retombe
        // pas, c'est que le texte a changé sous l'écran — créer la clé
        // ajouterait une option que l'auteur n'a jamais prévue.
        let tree = ConfigJSONTree.parse(#"{ "A": 1 }"#)!
        #expect(ConfigEditorModel.apply(.number("2"), at: ["B"], to: tree) == nil)
        #expect(ConfigEditorModel.apply(.number("2"), at: ["A", "Deeper"], to: tree) == nil)
        #expect(ConfigEditorModel.apply(.number("2"), at: [], to: tree) == nil)
    }

    @Test func anOutOfRangeArrayIndexChangesNothing() {
        let tree = ConfigJSONTree.parse(#"{ "Keys": ["a"] }"#)!
        #expect(ConfigEditorModel.apply(.string("z"), at: ["Keys", "[7]"], to: tree) == nil)
    }

    @Test func anObjectKeyThatLooksLikeAnIndexIsStillAKey() {
        // `[0]` est une notation d'affichage, pas une syntaxe : c'est le type
        // du conteneur qui tranche. L'ancien code testait le préfixe `[` et
        // aurait manqué cette clé.
        let tree = ConfigJSONTree.parse(#"{ "Slots": { "[0]": 1 } }"#)!
        let edited = ConfigEditorModel.apply(.number("5"), at: ["Slots", "[0]"], to: tree)!
        #expect(ConfigEditorModel.leaves(of: edited).map { $0.value } == [.number("5")])
    }

    // MARK: - Littéraux numériques

    @Test func recognisesIntegerLiterals() {
        #expect(ConfigEditorModel.isIntegerLiteral("3"))
        #expect(ConfigEditorModel.isIntegerLiteral("-4"))
        #expect(!ConfigEditorModel.isIntegerLiteral("3.0"))
        #expect(!ConfigEditorModel.isIntegerLiteral("1e3"))
        #expect(!ConfigEditorModel.isIntegerLiteral("1E3"))
    }

    @Test func rendersAnEditedNumberWithoutTrailingNoise() {
        #expect(ConfigEditorModel.numberLiteral(3, asInteger: true) == "3")
        #expect(ConfigEditorModel.numberLiteral(0.5, asInteger: false) == "0.5")
        #expect(ConfigEditorModel.numberLiteral(2, asInteger: false) == "2.0")
    }

    @Test func refusesANumberThatCannotBeWritten() {
        // `Int(1e19)` piège à l'exécution ; l'écran se contentait de le faire.
        #expect(ConfigEditorModel.numberLiteral(.infinity, asInteger: false) == nil)
        #expect(ConfigEditorModel.numberLiteral(.nan, asInteger: true) == nil)
        #expect(ConfigEditorModel.numberLiteral(1e19, asInteger: true) == nil)
    }

    @Test func readsANumberLiteralBackAsADouble() {
        #expect(ConfigEditorModel.doubleValue(ofLiteral: "1.50") == 1.5)
        #expect(ConfigEditorModel.doubleValue(ofLiteral: "not a number") == nil)
    }

    // MARK: - Le contrôle qu'une valeur mérite à l'écran

    @Test func aBooleanBecomesAToggle() {
        #expect(ConfigEditorModel.control(for: .bool(true)) == .toggle(true, asString: false))
    }

    @Test func aStringSayingTrueBecomesAToggleThatStaysAString() {
        // Des mods écrivent `"Enabled": "true"`. L'afficher en champ texte
        // ferait taper le mot ; le réécrire en booléen changerait le type que
        // le mod attend.
        #expect(ConfigEditorModel.control(for: .string("true")) == .toggle(true, asString: true))
        #expect(ConfigEditorModel.control(for: .string("False")) == .toggle(false, asString: true))
        #expect(ConfigEditorModel.control(for: .string("hello")) == .text("hello"))
    }

    @Test func aNumberBecomesAnIntegerOrDecimalField() {
        #expect(ConfigEditorModel.control(for: .number("3")) == .integer(3))
        #expect(ConfigEditorModel.control(for: .number("3.5")) == .decimal(3.5))
    }

    @Test func anIntegerLiteralTooLargeForIntFallsBackToADecimalField() {
        // `Int(1e19)` piège à l'exécution, et l'ancien champ entier faisait
        // cette conversion à chaque rendu.
        #expect(ConfigEditorModel.control(for: .number("99999999999999999999")) == .decimal(1e20))
    }

    @Test func aValueWithNoUsableControlIsRefused() {
        #expect(ConfigEditorModel.control(for: .number("1e999")) == nil)
        #expect(ConfigEditorModel.control(for: .null) == nil)
        #expect(ConfigEditorModel.control(for: .array([])) == nil)
    }

    @Test func aControlGoesBackToTheValueItCameFrom() {
        #expect(ConfigEditorModel.value(of: .toggle(true, asString: false)) == .bool(true))
        #expect(ConfigEditorModel.value(of: .toggle(true, asString: true)) == .string("true"))
        #expect(ConfigEditorModel.value(of: .toggle(false, asString: true)) == .string("false"))
        #expect(ConfigEditorModel.value(of: .integer(3)) == .number("3"))
        #expect(ConfigEditorModel.value(of: .decimal(0.5)) == .number("0.5"))
        #expect(ConfigEditorModel.value(of: .text("x")) == .string("x"))
    }

    @Test func aDecimalThatCannotBeWrittenYieldsNoValue() {
        #expect(ConfigEditorModel.value(of: .decimal(.infinity)) == nil)
    }
}
