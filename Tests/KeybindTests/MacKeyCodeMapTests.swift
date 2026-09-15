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

    /// C4-T10, suite — l'indice de touche pressée. Les `SButton` nomment des
    /// **positions physiques US** (convention du jeu, confirmée par le wiki
    /// Stardew et FNA#121) : sur AZERTY, presser la touche A enregistre `Q`.
    /// L'indice montre ce que l'utilisateur a réellement tapé — sauf quand
    /// il n'apprend rien.
    @Test func keycapHintShowsThePressedCharacterWhenItDiffers() {
        #expect(MacKeyCodeMap.keycapHint(physicalName: "Q", typedCharacter: "a") == "a")
        #expect(MacKeyCodeMap.keycapHint(physicalName: "D2", typedCharacter: "é") == "é")
    }

    @Test func keycapHintStaysSilentWhenItTeachesNothing() {
        #expect(MacKeyCodeMap.keycapHint(physicalName: "Q", typedCharacter: "Q") == nil) // QWERTY
        #expect(MacKeyCodeMap.keycapHint(physicalName: "D1", typedCharacter: "1") == nil) // D1↔1, évident
        #expect(MacKeyCodeMap.keycapHint(physicalName: "F8", typedCharacter: "") == nil) // pas de caractère
        #expect(MacKeyCodeMap.keycapHint(physicalName: "Space", typedCharacter: " ") == nil)
        #expect(MacKeyCodeMap.keycapHint(physicalName: "Up", typedCharacter: "\u{F702}") == nil) // usage privé
        #expect(MacKeyCodeMap.keycapHint(physicalName: "Q", typedCharacter: nil) == nil)
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
