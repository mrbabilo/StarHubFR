import Foundation
import Testing
@testable import StarHubTHCore

/// Le trousseau, derrière un seul type. Les tests écrivent sous un compte
/// jetable — jamais celui de l'application — et nettoient derrière eux.
struct KeychainSecretTests {

    private func secret() -> KeychainSecret {
        KeychainSecret(service: "com.appleboiy.StarHubTH.tests",
                       account: "test-\(UUID().uuidString)")
    }

    @Test func writeThenReadGivesTheValueBack() {
        let store = secret()
        defer { store.clear() }
        #expect(store.write("abc123"))
        #expect(store.read() == "abc123")
    }

    @Test func writingTwiceReplacesRatherThanDuplicates() {
        let store = secret()
        defer { store.clear() }
        #expect(store.write("premier"))
        #expect(store.write("second"))
        #expect(store.read() == "second")
    }

    @Test func anAbsentSecretReadsAsNil() {
        #expect(secret().read() == nil)
    }

    @Test func clearRemovesIt() {
        let store = secret()
        #expect(store.write("à effacer"))
        store.clear()
        #expect(store.read() == nil)
    }

    /// F5 phase 2 — la clé vit désormais sous le service **propre au fork** ;
    /// l'ancien service reste le filet : `legacyService` le désigne, et
    /// `read()` y retombe une fois en recopiant. Le compte, lui, n'a jamais
    /// bougé. (Le test verrouillait l'inverse avant la migration d'identité.)
    @Test func theNexusIdentifiersAreThoseAlreadyInUse() {
        #expect(KeychainSecret.nexusApiKey.service == "com.mrbabilo.StarHubFR")
        #expect(KeychainSecret.nexusApiKey.account == "nexusApiKey")
        #expect(KeychainSecret.legacyService == "com.appleboiy.StarHubTH")
        #expect(KeychainSecret.deepLApiKey.service == "com.mrbabilo.StarHubFR")
        #expect(KeychainSecret.deepLApiKey.account == "deeplApiKey")
    }
}
