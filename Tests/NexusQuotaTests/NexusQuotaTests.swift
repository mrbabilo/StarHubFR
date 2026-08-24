import Testing
import Foundation
@testable import StarHubTHCore

struct NexusQuotaTests {
    private let t0 = Date(timeIntervalSince1970: 1_787_595_034) // 2026-08-24 18:10:34 UTC

    /// Les en-têtes d'une réponse réelle de `api.nexusmods.com` (compte
    /// premium), relevés le 2026-08-24.
    private let liveHeaders: [String: String] = [
        "x-rl-hourly-limit": "2000",
        "x-rl-hourly-remaining": "1997",
        "x-rl-hourly-reset": "2026-08-24 19:00:00 +0000",
        "x-rl-daily-limit": "20000",
        "x-rl-daily-remaining": "19983",
        "x-rl-daily-reset": "2026-08-25 00:00:00 +0000",
    ]

    @Test func theSixLiveHeadersAreRead() throws {
        let quota = try #require(NexusQuota(headers: liveHeaders, now: t0))
        #expect(quota.hourly?.limit == 2000)
        #expect(quota.hourly?.remaining == 1997)
        #expect(quota.daily?.limit == 20000)
        #expect(quota.daily?.remaining == 19983)
        #expect(quota.measuredAt == t0)
        // 2026-08-25 00:00:00 UTC
        #expect(quota.daily?.reset == Date(timeIntervalSince1970: 1_787_616_000))
    }

    @Test func headerCasingDoesNotMatter() throws {
        let quota = try #require(NexusQuota(headers: ["X-RL-Daily-Remaining": "42"], now: t0))
        #expect(quota.daily?.remaining == 42)
    }

    /// La patte CDN d'un téléchargement ne porte aucun `x-rl-*` : sans ce
    /// refus, un fichier téléchargé écraserait la dernière mesure par un zéro.
    @Test func aResponseWithoutQuotaHeadersIsNotAMeasurement() {
        #expect(NexusQuota(headers: [:], now: t0) == nil)
        #expect(NexusQuota(headers: ["content-type": "application/json"], now: t0) == nil)
    }

    /// Un plafond seul ne dit pas ce qu'il reste : ce n'est pas une mesure.
    @Test func aLimitWithoutARemainingIsNotAMeasurement() {
        #expect(NexusQuota(headers: ["x-rl-daily-limit": "2500"], now: t0) == nil)
    }

    @Test func aMissingLimitStillLeavesAUsableRemaining() throws {
        let quota = try #require(NexusQuota(headers: ["x-rl-daily-remaining": "7"], now: t0))
        #expect(quota.daily?.limit == nil)
        #expect(quota.daily?.remaining == 7)
    }

    /// Le quota épuisé est précisément le moment où l'affichage compte : zéro
    /// est une mesure comme une autre, pas une absence.
    @Test func zeroRemainingIsAValidMeasurement() throws {
        let quota = try #require(NexusQuota(headers: ["x-rl-daily-remaining": "0"], now: t0))
        #expect(quota.daily?.remaining == 0)
    }

    @Test func anUnreadableResetLeavesTheCountsIntact() throws {
        let quota = try #require(NexusQuota(
            headers: ["x-rl-daily-remaining": "12", "x-rl-daily-reset": "demain"], now: t0))
        #expect(quota.daily?.remaining == 12)
        #expect(quota.daily?.reset == nil)
    }

    @Test func isoFormattedResetsAreAlsoAccepted() {
        #expect(NexusQuota.parseDate("2026-08-25T00:00:00+00:00")
                == Date(timeIntervalSince1970: 1_787_616_000))
        #expect(NexusQuota.parseDate("2026-08-25T00:00:00.000Z")
                == Date(timeIntervalSince1970: 1_787_616_000))
        #expect(NexusQuota.parseDate(nil) == nil)
        #expect(NexusQuota.parseDate("  ") == nil)
    }

    @Test func aFreshMeasurementIsNotStale() throws {
        let quota = try #require(NexusQuota(headers: liveHeaders, now: t0))
        #expect(quota.isStale(now: t0) == false)
        #expect(quota.isStale(now: t0.addingTimeInterval(600)) == false)
    }

    /// Une mesure d'hier annonçant « 2 appels restants » ment après minuit.
    @Test func aMeasurementIsStaleOnceItsWindowHasReset() throws {
        let quota = try #require(NexusQuota(headers: liveHeaders, now: t0))
        // 19:00:00 UTC : la fenêtre horaire s'est remise à zéro.
        #expect(quota.isStale(now: Date(timeIntervalSince1970: 1_787_598_000)) == true)
    }

    @Test func withoutAResetTheNominalWindowDecidesStaleness() throws {
        let daily = try #require(NexusQuota(headers: ["x-rl-daily-remaining": "5"], now: t0))
        #expect(daily.isStale(now: t0.addingTimeInterval(23 * 3600)) == false)
        #expect(daily.isStale(now: t0.addingTimeInterval(24 * 3600)) == true)

        let hourly = try #require(NexusQuota(headers: ["x-rl-hourly-remaining": "5"], now: t0))
        #expect(hourly.isStale(now: t0.addingTimeInterval(3599)) == false)
        #expect(hourly.isStale(now: t0.addingTimeInterval(3600)) == true)
    }

    @Test func aMeasurementSurvivesAnEncodeDecodeRoundTrip() throws {
        let quota = try #require(NexusQuota(headers: liveHeaders, now: t0))
        let data = try JSONEncoder().encode(quota)
        #expect(try JSONDecoder().decode(NexusQuota.self, from: data) == quota)
    }
}
