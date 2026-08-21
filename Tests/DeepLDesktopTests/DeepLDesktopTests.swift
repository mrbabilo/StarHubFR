import Foundation
import Testing
@testable import StarHubTHCore

/// La détection de l'application de bureau DeepL. Le test ne prouve rien de
/// LaunchServices — il fixe l'identifiant relevé sur une installation réelle
/// et le sens de la réponse quand la résolution ne rend rien.
struct DeepLDesktopTests {

    /// Relevé le 2026-08-21 sur `/Applications/DeepL.app` (v26.6) :
    /// l'identifiant porte encore le nom du produit d'origine.
    @Test func theBundleIdentifierIsTheOneMeasuredOnADiskInstall() {
        #expect(DeepLDesktop.bundleIdentifier == "com.linguee.DeepLCopyTranslator")
    }

    @Test func aResolvedURLMeansInstalled() {
        #expect(DeepLDesktop.isInstalled { _ in URL(fileURLWithPath: "/Applications/DeepL.app") })
    }

    /// Une résolution vide ne prouve **pas** l'absence — LaunchServices peut
    /// être en retard, l'application vivre ailleurs. C'est pour ça que
    /// l'interface ne dit rien dans ce cas, au lieu d'affirmer une absence.
    @Test func nothingResolvedMeansNothingIsClaimed() {
        #expect(!DeepLDesktop.isInstalled { _ in nil })
    }
}
