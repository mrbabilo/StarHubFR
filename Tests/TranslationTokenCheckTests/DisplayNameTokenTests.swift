import Testing
@testable import StarHubTHCore

/// `%DISPLAY_NAME` et `%PRESERVED_DISPLAY_NAME` : deux substitutions du jeu
/// 1.6 (chaînes relevées dans `Stardew Valley.dll`), en majuscules — la liste
/// des noms `%` est sensible à la casse. Ni l'une ni l'autre n'est en tête de
/// page : sans leur nom dans la liste, le `%` du milieu de ligne restait du
/// texte et leur perte passait inaperçue.
struct DisplayNameTokenTests {

    @Test func aDisplayNameIsRecognisedMidLineAndBlocks() {
        #expect(TranslationTokenCheck.extract("Un %DISPLAY_NAME tout frais.") == ["%DISPLAY_NAME"])
        #expect(TranslationTokenCheck.isHard("%DISPLAY_NAME"))
        let lost = TranslationTokenCheck.mismatches(source: "A fresh %DISPLAY_NAME.",
                                                    target: "Un objet tout frais.")
        #expect(lost.map(\.token) == ["%DISPLAY_NAME"])
        #expect(lost.allSatisfy { $0.isHard })
    }

    /// Le plus long d'abord : `%PRESERVED_DISPLAY_NAME` ne doit pas se lire
    /// `%P…` ni s'arrêter à un nom plus court.
    @Test func aPreservedDisplayNameIsRecognisedWholeAndBlocks() {
        #expect(TranslationTokenCheck.extract("Du %PRESERVED_DISPLAY_NAME maison.")
                == ["%PRESERVED_DISPLAY_NAME"])
        #expect(TranslationTokenCheck.isHard("%PRESERVED_DISPLAY_NAME"))
        let lost = TranslationTokenCheck.mismatches(source: "Homemade %PRESERVED_DISPLAY_NAME.",
                                                    target: "Fait maison.")
        #expect(lost.map(\.token) == ["%PRESERVED_DISPLAY_NAME"])
        #expect(lost.allSatisfy { $0.isHard })
    }
}
