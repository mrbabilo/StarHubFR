import Testing
import Foundation
@testable import StarHubTHCore

struct UpdateCheckPolicyTests {
    /// Le TTL d'A2-T4 : 12 h retenu au cadrage du 2026-08-31.
    private let ttl: TimeInterval = 12 * 3600
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func jamaisVérifié() {
        #expect(UpdateCheckPolicy.shouldAutoCheck(lastSuccess: nil, now: now, ttl: ttl))
    }

    @Test func frais() {
        let last = now.addingTimeInterval(-(11 * 3600))
        #expect(!UpdateCheckPolicy.shouldAutoCheck(lastSuccess: last, now: now, ttl: ttl))
    }

    @Test func périmé() {
        let limit = now.addingTimeInterval(-ttl)
        #expect(UpdateCheckPolicy.shouldAutoCheck(lastSuccess: limit, now: now, ttl: ttl))
        let older = now.addingTimeInterval(-(12 * 3600 + 60))
        #expect(UpdateCheckPolicy.shouldAutoCheck(lastSuccess: older, now: now, ttl: ttl))
    }
}
