import Foundation
import Testing
@testable import StarHubTHCore

struct DeepLCredentialsTests {

    /// Le suffixe `:fx` désigne une clé du plan gratuit — c'est la
    /// documentation de DeepL qui le dit, et c'est ce qui choisit l'hôte.
    @Test func aFreeKeyRoutesToTheFreeHost() {
        let credentials = DeepLClient.Credentials(key: "279a2e9d-1234:fx")
        #expect(credentials?.baseURL.absoluteString == "https://api-free.deepl.com")
        #expect(credentials?.isFreePlan == true)
    }

    @Test func aProKeyRoutesToTheProHost() {
        let credentials = DeepLClient.Credentials(key: "279a2e9d-1234")
        #expect(credentials?.baseURL.absoluteString == "https://api.deepl.com")
        #expect(credentials?.isFreePlan == false)
    }

    /// Un copier-coller traîne des espaces : ils ne doivent ni casser l'hôte
    /// ni voyager dans l'en-tête d'authentification.
    @Test func surroundingWhitespaceIsTrimmed() {
        let credentials = DeepLClient.Credentials(key: "  279a2e9d-1234:fx \n")
        #expect(credentials?.key == "279a2e9d-1234:fx")
        #expect(credentials?.isFreePlan == true)
    }

    @Test func anEmptyKeyIsNoCredentialsAtAll() {
        #expect(DeepLClient.Credentials(key: "") == nil)
        #expect(DeepLClient.Credentials(key: "   ") == nil)
    }
}
