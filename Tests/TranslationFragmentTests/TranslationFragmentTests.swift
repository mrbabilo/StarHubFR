import Foundation
import Testing
@testable import StarHubTHCore

/// Ce qu'une sélection de l'anglais a le droit d'être avant de partir chez un
/// service de traduction.
struct TranslationFragmentTests {

    @Test func aPlainWordIsReady() {
        #expect(TranslationFragment.prepare("deep") == .ready("deep"))
    }

    /// Une sélection à la souris emporte presque toujours une espace de trop.
    @Test func surroundingWhitespaceIsTrimmed() {
        #expect(TranslationFragment.prepare("  grow very deep \n") == .ready("grow very deep"))
    }

    @Test func anEmptySelectionIsNothingToTranslate() {
        #expect(TranslationFragment.prepare("") == .empty)
        #expect(TranslationFragment.prepare("   \n ") == .empty)
    }

    /// Une marque prise dans la sélection ne part pas : le service la
    /// traduirait ou la déformerait, et la pastille rendue porterait une
    /// marque abîmée qu'un clic verserait dans le français.
    @Test func aSelectionCarryingAMarkerIsRefusedByName() {
        #expect(TranslationFragment.prepare("Hi {{Name}}, welcome")
                == .containsMarkers(["{{Name}}"]))
    }

    /// Les marques sont nommées **dédoublonnées et triées** : la même deux
    /// fois n'a pas à s'annoncer deux fois, et l'ordre ne doit pas sauter
    /// d'une sélection à l'autre.
    @Test func theMarkersAreNamedOnceAndInAStableOrder() {
        #expect(TranslationFragment.prepare("%kid1 et {{Name}} et %kid1")
                == .containsMarkers(["%kid1", "{{Name}}"]))
    }

    /// Le saut de ligne littéral n'est pas une marque du jeu — il ne bloque
    /// rien à l'écriture, il n'a pas à bloquer ici.
    @Test func aLineBreakIsNotAMarker() {
        #expect(TranslationFragment.prepare("deux\r\nlignes") == .ready("deux\r\nlignes"))
    }
}
