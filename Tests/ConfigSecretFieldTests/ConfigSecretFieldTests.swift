import Testing
@testable import StarHubTHCore

struct ConfigSecretFieldTests {
    @Test func apiKeysAndPasswordsAreSecrets() {
        #expect(ConfigSecretField.isSecret(["TranslationApiKey"]))
        #expect(ConfigSecretField.isSecret(["TranslationApiKeys", "DeepL"]))
        #expect(ConfigSecretField.isSecret(["Auth", "access_token"]))
        #expect(ConfigSecretField.isSecret(["Password"]))
    }

    /// Mesuré sur le parc : ces mots-là sont des lieux et des objets du jeu.
    @Test func gameWordsAreNotSecrets() {
        #expect(!ConfigSecretField.isSecret(["EnableSeaCaveSecrets"]))
        #expect(!ConfigSecretField.isSecret(["StarToken"]))
        #expect(!ConfigSecretField.isSecret(["ShopPreferences", "Festival_StardewValleyFair_StarTokens"]))
        #expect(!ConfigSecretField.isSecret(["OpenKey"]))
    }
}
