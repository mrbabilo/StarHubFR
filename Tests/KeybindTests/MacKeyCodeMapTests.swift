import Testing
import Foundation
@testable import StarHubTHCore

/// La table que la capture de raccourci emploie pour nommer une touche
/// (**C4-T10**) : un keyCode macOS entre, un nom `SButton` canonique sort.
/// Deux gardes : aucun nom hors table de référence — la capture ne peut
/// pas produire une combinaison que la grammaire refuserait — et les
/// familles attendues (lettres, chiffres, F1–F20) couvertes en entier.
struct MacKeyCodeMapTests {

    @Test func everyMappedNameIsARealSButtonName() {
        for (keyCode, name) in MacKeyCodeMap.table {
            #expect(SButtonTable.canonicalName(for: name) == name,
                    "keyCode \(keyCode) → « \(name) » n'est pas un nom canonique")
        }
    }

    @Test func famousKeyCodesLandOnTheRightButton() {
        #expect(MacKeyCodeMap.name(for: 0) == "A")          // kVK_ANSI_A
        #expect(MacKeyCodeMap.name(for: 29) == "D0")        // kVK_ANSI_0
        #expect(MacKeyCodeMap.name(for: 100) == "F8")       // kVK_F8
        #expect(MacKeyCodeMap.name(for: 49) == "Space")     // kVK_Space
        #expect(MacKeyCodeMap.name(for: 53) == "Escape")    // kVK_Escape
        #expect(MacKeyCodeMap.name(for: 36) == "Enter")     // kVK_Return
        #expect(MacKeyCodeMap.name(for: 123) == "Left")     // kVK_LeftArrow
        #expect(MacKeyCodeMap.name(for: 82) == "NumPad0")   // kVK_ANSI_Keypad0
        #expect(MacKeyCodeMap.name(for: 27) == "OemMinus")  // kVK_ANSI_Minus
        #expect(MacKeyCodeMap.name(for: 999) == nil)        // hors table
    }

    @Test func theExpectedFamiliesAreFullyCovered() {
        let names = Set(MacKeyCodeMap.table.values)
        let letters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init))
        #expect(letters.isSubset(of: names), "une lettre manque : \(letters.subtracting(names))")
        let digits = Set((0...9).map { "D\($0)" })
        #expect(digits.isSubset(of: names))
        let functionKeys = Set((1...20).map { "F\($0)" })
        #expect(functionKeys.isSubset(of: names), "une touche F manque : \(functionKeys.subtracting(names))")
    }

    /// Les modificateurs que la capture écrit : valeurs exactes, validées
    /// contre la même table. La vue les emploie par ce nom — un renommage
    /// ici casse son test.
    @Test func modifierNamesArePinnedAndCanonical() {
        #expect(MacKeyCodeMap.modifierNames.shift == "LeftShift")
        #expect(MacKeyCodeMap.modifierNames.control == "LeftControl")
        #expect(MacKeyCodeMap.modifierNames.alt == "LeftAlt")
        #expect(MacKeyCodeMap.modifierNames.command == "LeftWindows")
        let all = [MacKeyCodeMap.modifierNames.shift,
                   MacKeyCodeMap.modifierNames.control,
                   MacKeyCodeMap.modifierNames.alt,
                   MacKeyCodeMap.modifierNames.command]
        #expect(all.allSatisfy { SButtonTable.canonicalName(for: $0) != nil })
    }
}
