import Testing
import Foundation
@testable import StarHubTHCore

struct NexusRequestBuilderTests {
    // MARK: - isValidModId — garde contre le path traversal / l'injection d'URL

    /// Un modId vient d'un `UpdateKey` de manifest (« nexus:191 »), source
    /// externe non fiable. Il est interpolé tel quel dans le chemin de l'API
    /// (`/games/.../mods/<modId>.json`) : sans validation, un modId malveillant
    /// ferait du path traversal (« ../games/fallout4 ») ou de l'injection de
    /// query (« 191?fields=… »).

    @Test func validModIdsAreAccepted() {
        #expect(NexusRequestBuilder.isValidModId("191") == true)
        #expect(NexusRequestBuilder.isValidModId("240") == true)
        #expect(NexusRequestBuilder.isValidModId("41318") == true)
        #expect(NexusRequestBuilder.isValidModId("0012") == true)   // Nexus normalise
    }

    @Test func traversalIsRejected() {
        #expect(NexusRequestBuilder.isValidModId("../games/fallout4") == false)
        #expect(NexusRequestBuilder.isValidModId("..") == false)
    }

    @Test func queryInjectionIsRejected() {
        #expect(NexusRequestBuilder.isValidModId("191?fields=secret") == false)
        #expect(NexusRequestBuilder.isValidModId("191#frag") == false)
    }

    @Test func nonNumericIsRejected() {
        #expect(NexusRequestBuilder.isValidModId("") == false)
        #expect(NexusRequestBuilder.isValidModId("abc") == false)
        #expect(NexusRequestBuilder.isValidModId("191abc") == false)
        #expect(NexusRequestBuilder.isValidModId("1.5") == false)
        #expect(NexusRequestBuilder.isValidModId("0x10") == false)
    }

    @Test func zeroAndNegativesAreRejected() {
        // Le modId 0 n'existe pas chez Nexus ; un négatif non plus.
        #expect(NexusRequestBuilder.isValidModId("0") == false)
        #expect(NexusRequestBuilder.isValidModId("-5") == false)
    }

    @Test func whitespaceIsRejected() {
        // parseNexusId trim en amont ; rejeter ici évite qu'un « 191 » espacé
        // ne devienne une URL avec %20.
        #expect(NexusRequestBuilder.isValidModId(" 191") == false)
        #expect(NexusRequestBuilder.isValidModId("191 ") == false)
        #expect(NexusRequestBuilder.isValidModId("1 91") == false)
    }
}
