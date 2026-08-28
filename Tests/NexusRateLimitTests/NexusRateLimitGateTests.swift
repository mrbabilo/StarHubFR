import Testing
import Foundation
@testable import StarHubTHCore

struct NexusRateLimitGateTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func aFreshGateLetsEverythingThrough() {
        let gate = NexusRateLimitGate()
        #expect(gate.isBlocked(now: t0) == false)
        #expect(gate.remaining(now: t0) == nil)
    }

    @Test func a429BlocksForTheAnnouncedDelay() {
        var gate = NexusRateLimitGate()
        gate.note(retryAfter: 30, now: t0)
        #expect(gate.isBlocked(now: t0) == true)
        #expect(gate.remaining(now: t0) == 30)
        #expect(gate.isBlocked(now: t0.addingTimeInterval(29)) == true)
    }

    @Test func theGateOpensOnceTheDelayHasPassed() {
        var gate = NexusRateLimitGate()
        gate.note(retryAfter: 30, now: t0)
        #expect(gate.isBlocked(now: t0.addingTimeInterval(30)) == false)
        #expect(gate.remaining(now: t0.addingTimeInterval(31)) == nil)
    }

    /// Un quota journalier peut annoncer des heures d'attente : sans plafond,
    /// les fonctions Nexus seraient coupées pour toute la session.
    @Test func anAbsurdDelayIsCappedAtFifteenMinutes() {
        var gate = NexusRateLimitGate()
        gate.note(retryAfter: 86_400, now: t0)
        #expect(gate.remaining(now: t0) == NexusRateLimitGate.maxBackoff)
    }

    @Test func aNonPositiveDelayArmsNothing() {
        var gate = NexusRateLimitGate()
        gate.note(retryAfter: 0, now: t0)
        #expect(gate.isBlocked(now: t0) == false)
        gate.note(retryAfter: -5, now: t0)
        #expect(gate.isBlocked(now: t0) == false)
    }

    /// Deux réponses 429 en vol : la plus courte ne doit pas raccourcir
    /// l'attente déjà accordée à la plus longue.
    @Test func theFurthestDeadlineWins() {
        var gate = NexusRateLimitGate()
        gate.note(retryAfter: 120, now: t0)
        gate.note(retryAfter: 10, now: t0)
        #expect(gate.remaining(now: t0) == 120)
    }

    @Test func aLaterDeadlineExtendsTheBlock() {
        var gate = NexusRateLimitGate()
        gate.note(retryAfter: 10, now: t0)
        gate.note(retryAfter: 120, now: t0)
        #expect(gate.remaining(now: t0) == 120)
    }

    /// Un 429 reçu plus tard repousse l'échéance même avec un délai plus court
    /// que le précédent, parce qu'il part d'un « maintenant » plus avancé.
    @Test func aFreshHitFromALaterInstantStillCounts() {
        var gate = NexusRateLimitGate()
        gate.note(retryAfter: 60, now: t0)
        gate.note(retryAfter: 30, now: t0.addingTimeInterval(50))
        #expect(gate.remaining(now: t0.addingTimeInterval(50)) == 30)
    }

    // MARK: - Quota épuisé (B2-T8)

    private func exhaustedQuota(hourlyReset: Date? = nil, dailyReset: Date? = nil,
                                hourlyRemaining: Int = 0, dailyRemaining: Int = 0) -> NexusQuota {
        NexusQuota(hourly: .init(limit: 2_000, remaining: hourlyRemaining, reset: hourlyReset),
                   daily: .init(limit: 20_000, remaining: dailyRemaining, reset: dailyReset),
                   measuredAt: t0)
    }

    /// Un quota horaire épuisé dont la remise à zéro est connue : la porte
    /// s'arme jusqu'à elle, **au-delà du plafond** — retenter toutes les
    /// 15 minutes une fenêtre fermée pour 48 ne fait que consommer des
    /// réponses 429.
    @Test func anExhaustedWindowBlocksUntilItsRealReset() {
        var gate = NexusRateLimitGate()
        let reset = t0.addingTimeInterval(48 * 60)
        gate.note(retryAfter: 900, quota: exhaustedQuota(hourlyReset: reset), now: t0)
        #expect(gate.blockedUntil == reset)
        #expect(gate.isBlocked(now: reset.addingTimeInterval(-1)) == true)
        #expect(gate.isBlocked(now: reset) == false)
    }

    /// Les deux fenêtres épuisées : c'est la remise à zéro la plus lointaine
    /// qui compte — tant que la journalière n'est pas repassée, toute requête
    /// repart en 429.
    @Test func bothWindowsExhaustedBlocksUntilTheLatestReset() {
        var gate = NexusRateLimitGate()
        let hourlyReset = t0.addingTimeInterval(30 * 60)
        let dailyReset = t0.addingTimeInterval(5 * 3_600)
        gate.note(retryAfter: 60, quota: exhaustedQuota(hourlyReset: hourlyReset,
                                                        dailyReset: dailyReset),
                  now: t0)
        #expect(gate.blockedUntil == dailyReset)
    }

    /// Le reset réel d'un quota épuisé ne doit pas être raccourci par un
    /// `Retry-After` plus optimiste : l'échéance est la plus lointaine des deux.
    @Test func aRealResetIsNotShortenedByAShorterRetryAfter() {
        var gate = NexusRateLimitGate()
        let reset = t0.addingTimeInterval(40 * 60)
        gate.note(retryAfter: 60, quota: exhaustedQuota(hourlyReset: reset), now: t0)
        #expect(gate.blockedUntil == reset)
    }

    /// Une fenêtre épuisée sans instant de remise à zéro ne dit rien de plus
    /// qu'avant : le plafond de 15 minutes garde son rôle, on ne devine pas.
    @Test func anExhaustedWindowWithoutResetKeepsTheCappedBackoff() {
        var gate = NexusRateLimitGate()
        gate.note(retryAfter: 86_400, quota: exhaustedQuota(), now: t0)
        #expect(gate.remaining(now: t0) == NexusRateLimitGate.maxBackoff)
    }

    /// Un 429 alors qu'il reste du quota n'est pas un quota épuisé (limitation
    /// ponctuelle du serveur) : comportement inchangé, reset ignoré.
    @Test func a429WithRemainingQuotaIgnoresTheReset() {
        var gate = NexusRateLimitGate()
        let reset = t0.addingTimeInterval(40 * 60)
        gate.note(retryAfter: 60,
                  quota: exhaustedQuota(hourlyReset: reset, hourlyRemaining: 500),
                  now: t0)
        #expect(gate.remaining(now: t0) == 60)
    }

    /// Un reset déjà passé n'étend rien : seule une échéance future arme.
    @Test func aResetInThePastArmsNothingNew() {
        var gate = NexusRateLimitGate()
        gate.note(retryAfter: 0,
                  quota: exhaustedQuota(hourlyReset: t0.addingTimeInterval(-60)),
                  now: t0)
        #expect(gate.isBlocked(now: t0) == false)
    }
}
