import Testing
import Foundation
@testable import StarHubTHCore

struct KeybindGrammarTests {

    // — Table : valeurs clés, figées du relevé IL (fixtures, pas mémoire)
    @Test func tableKnowsItsKeyEntries() {
        #expect(SButtonTable.canonicalName(for: "F8") == "F8")
        #expect(SButtonTable.canonicalName(for: "leftcontrol") == "LeftControl")
        #expect(SButtonTable.canonicalName(for: "MouseLeft") == "MouseLeft")
        #expect(SButtonTable.canonicalName(for: "D1") == "D1")
        #expect(SButtonTable.canonicalName(for: "ctrl") == nil)      // rejeté par SMAPI aussi
        #expect(SButtonTable.canonicalName(for: "paris") == nil)
        #expect(SButtonTable.keyboardValues.contains(0x77))          // F8
        #expect(!SButtonTable.keyboardValues.contains(1000))         // souris : pas un entier clavier
    }

    // — Parseur : les trois formes réelles
    @Test func parsesSingleButton() {
        #expect(KeybindParser.parse(.string("F8")) == [KeybindCombo(buttons: ["F8"])!])
    }

    @Test func parsesComboRegardlessOfSpacingCaseAndOrder() {
        let a = KeybindParser.parse(.string("leftcontrol+F8"))!
        let b = KeybindParser.parse(.string("F8 + LeftControl"))!
        #expect(a == b)
        #expect(a.first?.display == "F8 + LeftControl")              // trié, séparateur SMAPI
    }

    @Test func parsesCommaListAndArrayAndInts() {
        #expect(KeybindParser.parse(.string("F8, K"))?.count == 2)
        #expect(KeybindParser.parse(.array([.string("F8"), .string("K")]))?.count == 2)
        #expect(KeybindParser.parse(.array([.number("119"), .number("75")]))?.count == 2) // 0x77 F8, 0x4B K
        #expect(KeybindParser.parse(.number("119")) == [KeybindCombo(buttons: ["F8"])!])
    }

    @Test func noneIsAnEmptyInertCombo() {
        #expect(KeybindParser.parse(.string("None")) == [KeybindCombo(buttons: [])!])
        #expect(KeybindParser.parse(.string("None"))?.first?.display == "None")
        #expect(KeybindParser.parse(.string("None"))?.first?.isDistinctive == false)
        // L'entier 0 est le None numérique : même combo vide, même inertie
        // (sinon deux mods hintés à 0 collisionnent sur « None » — §3).
        #expect(KeybindParser.parse(.number("0")) == [KeybindCombo(buttons: [])!])
        // « None » au milieu d'un combo : jamais déclenchable, rejeté.
        #expect(KeybindParser.parse(.string("None + F8")) == nil)
    }

    @Test func rejectsGarbageEmptyAndOutOfRangeInts() {
        #expect(KeybindParser.parse(.string("parfois")) == nil)
        #expect(KeybindParser.parse(.string("")) == nil)
        #expect(KeybindParser.parse(.number("3.5")) == nil)
        #expect(KeybindParser.parse(.number("1000")) == nil)          // souris : pas entier clavier
        #expect(KeybindParser.parse(.bool(true)) == nil)
    }

    @Test func toleratesCRLF() {
        #expect(KeybindParser.parse(.string("F8,\r\nK"))?.count == 2)
    }

    // — Distinctivité (règle R2)
    @Test func distinctiveness() {
        #expect(KeybindCombo(buttons: ["K"])?.isDistinctive == false)          // 1 caractère
        #expect(KeybindCombo(buttons: ["F8"])?.isDistinctive == true)
        #expect(KeybindCombo(buttons: ["LeftControl", "K"])?.isDistinctive == true)
    }
}
