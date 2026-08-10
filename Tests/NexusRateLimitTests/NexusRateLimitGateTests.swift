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
}
