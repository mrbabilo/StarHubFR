import Testing
import Foundation
@testable import StarHubTHCore

struct NexusAccountTests {
    private let t0 = Date(timeIntervalSince1970: 1_787_595_034)

    /// La réponse réelle de `/v1/users/validate.json`, relevée le 2026-08-25.
    /// Elle porte le statut sous **deux** clés à la fois.
    @Test func theLiveResponseIsRead() throws {
        let account = try #require(NexusAccount(
            json: ["name": "mrbabilo", "is_premium": false, "is_premium?": false,
                   "is_supporter": false], now: t0))
        #expect(account.name == "mrbabilo")
        #expect(account.isPremium == false)
        #expect(account.checkedAt == t0)
    }

    /// N'en lire qu'une exposerait à ce qu'un renommage fasse passer un compte
    /// premium pour gratuit, et prive l'utilisateur d'un bouton auquel il a
    /// droit.
    @Test func eitherSpellingOfTheFlagIsAccepted() {
        #expect(NexusAccount(json: ["is_premium": true], now: t0)?.isPremium == true)
        #expect(NexusAccount(json: ["is_premium?": true], now: t0)?.isPremium == true)
    }

    /// Sans le moindre indice de statut, on ne conclut pas : mieux vaut ne rien
    /// savoir que supposer « gratuit » et retirer un bouton à tort.
    @Test func aResponseWithoutTheFlagIsNotAnAccount() {
        #expect(NexusAccount(json: [:], now: t0) == nil)
        #expect(NexusAccount(json: ["name": "quelqu'un"], now: t0) == nil)
    }

    @Test func aMissingNameDoesNotDiscardTheStatus() {
        #expect(NexusAccount(json: ["is_premium": true], now: t0)?.name == "")
    }

    /// Un compte peut devenir premium, ou cesser de l'être.
    @Test func theAnswerAgesAfterAWeek() {
        let account = NexusAccount(name: "x", isPremium: false, checkedAt: t0)
        #expect(!account.isStale(now: t0.addingTimeInterval(6 * 24 * 3600)))
        #expect(account.isStale(now: t0.addingTimeInterval(7 * 24 * 3600)))
    }

    @Test func itSurvivesAnEncodeDecodeRoundTrip() throws {
        let account = NexusAccount(name: "mrbabilo", isPremium: false, checkedAt: t0)
        let data = try JSONEncoder().encode(account)
        #expect(try JSONDecoder().decode(NexusAccount.self, from: data) == account)
    }
}
