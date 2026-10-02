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

    // MARK: - La capture lit le libellé (corrigé le 2026-10-02)
    //
    // Les tests d'avant figeaient « sur AZERTY, presser la touche A
    // enregistre Q » (règle FNA#121, ère FNA). Inversés : MonoGame lit
    // `Keysym.Sym`, la SDL du jeu rend le caractère de la disposition, et
    // en jeu `Ctrl + Q` répond à la touche gravée Q. Fixture : les vrais
    // caractères d'un AZERTY français, relevés par `UCKeyTranslate`.

    /// La touche gravée A d'un AZERTY (position US du Q, keyCode 0x0C) :
    /// le jeu la lit `A`, la capture doit écrire `A`.
    @Test func azertyLetterIsNamedByItsEngraving() {
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x0C, character: "a") == "A")
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x00, character: "q") == "Q")
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x0D, character: "z") == "Z")
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x29, character: "m") == "M")
    }

    /// Le cas voisin : sur QWERTY, rien ne change.
    @Test func qwertyLetterIsUnchanged() {
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x00, character: "a") == "A")
    }

    /// La rangée des chiffres se lit par position, quelle que soit la
    /// gravure (`&` rend `1` dans la SDL du jeu).
    @Test func numberRowIsAlwaysADigit() {
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x12, character: "&") == "D1")
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x1D, character: "à") == "D0")
    }

    /// La ponctuation suit la table de MonoGame, par caractère.
    @Test func punctuationFollowsTheGameTable() {
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x2E, character: ",") == "OemComma")
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x2B, character: ";") == "OemSemicolon")
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x32, character: "<") == "OemBackslash")
    }

    /// Une touche que le jeu ne voit pas est refusée, sans nom deviné.
    @Test func keysTheGameCannotReadAreRefused() {
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x1B, character: ")") == nil)
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x27, character: "ù") == nil)
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x0A, character: "@") == nil)
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x00, character: nil) == nil)
    }

    /// Les touches sans caractère gardent leur nom, toutes dispositions.
    @Test func namedKeysIgnoreTheLayout() {
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x64, character: nil) == "F8")
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x31, character: " ") == "Space")
        #expect(MacKeyCodeMap.capturedName(keyCode: 0x7B, character: "\u{F702}") == "Left")
    }

    @Test func everyPunctuationNameIsARealSButtonName() {
        for name in MacKeyCodeMap.punctuationByCharacter.values {
            #expect(SButtonTable.canonicalName(for: name) == name, "« \(name) »")
        }
    }

    @Test func displayHintShowsOnlyWhatTheNameHides() {
        #expect(MacKeyCodeMap.displayHint(storedName: "OemComma") == ",")
        #expect(MacKeyCodeMap.displayHint(storedName: "Q") == nil)
        #expect(MacKeyCodeMap.displayHint(storedName: "D1") == nil)
        #expect(MacKeyCodeMap.displayHint(storedName: "F8") == nil)
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
