import Testing
import Foundation
@testable import StarHubTHCore

struct ProbeSegmentsTests {
    private func sessions() throws -> ProbeSessions {
        ProbeSessions.decode(timings: try Fixture.data("timings.jsonl"),
                             costs: try Fixture.data("mod-costs.jsonl"))
    }
    private func inventory() throws -> (launches: [ProbeInventoryLaunch],
                                        changes: [ProbeInventoryChange], unreadable: Int) {
        ProbeInventory.decode(try Fixture.data("inventory.jsonl"))
    }
    private func session(_ prefix: String) throws -> ProbeSession {
        try #require(try sessions().sessions.first { $0.id.hasPrefix(prefix) })
    }

    /// La session 0.4.13 coupe au ChangedAt : 1 minute avant, 1 écartée
    /// (fenêtre contenant la coupure), 1 après.
    @Test func sessionIsCutAtChangedAt() throws {
        let session = try session("2026-09-28T19:21")
        let inv = try inventory()
        let result = ProbeSegments.split(session, launches: inv.launches, changes: inv.changes)
        #expect(result.segments.count == 2)
        #expect(result.segments.map(\.minutes.count) == [1, 1])
        #expect(result.mixedMinutes.count == 1)
        #expect(result.mixedMinutes.first?.at.hasPrefix("2026-09-28T19:25:09") == true)
        // Inventaire résolu : le réglage GMCM est **remplacé** par la coupure
        // (3fa643ce au lancement 0.4.13, ramené à bbe0048a en cours de partie).
        let before = result.segments[0].inventory?["spacechase0.GenericModConfigMenu"]
        let after = result.segments[1].inventory?["spacechase0.GenericModConfigMenu"]
        #expect(before?.configSha?.hasPrefix("3fa643ce") == true)
        #expect(after?.configSha?.hasPrefix("bbe0048a") == true)
    }

    /// Session avec inventaire mais sans coupure : un seul segment.
    @Test func sessionWithoutChangeStaysWhole() throws {
        let session = try session("2026-09-28T18:56")
        let inv = try inventory()
        let result = ProbeSegments.split(session, launches: inv.launches, changes: inv.changes)
        #expect(result.segments.count == 1)
        #expect(result.segments.first?.minutes.count == 5)
        #expect(result.segments.first?.inventory?.count == 289)
    }

    /// Session de la sonde 0.3 (sans inventaire) : un segment « inconnu »,
    /// toutes les minutes gardées.
    @Test func sessionWithoutInventoryIsUnknown() throws {
        let session = try session("2026-09-26T01:38")
        let inv = try inventory()
        let result = ProbeSegments.split(session, launches: inv.launches, changes: inv.changes)
        #expect(result.segments.count == 1)
        #expect(result.segments.first?.inventory == nil)
        #expect(result.segments.first?.minutes.count == 8)
    }

    /// Un `configChanged` sans `ChangedAt` : la coupure retombe sur `At`.
    @Test func changeWithoutChangedAtFallsBackToAt() throws {
        let session = try session("2026-09-28T18:56")
        let launch = try #require(try inventory().launches.first { $0.session.hasPrefix("2026-09-28T18:56") })
        let at = session.minutes[1].at
        let change = ProbeInventoryChange(session: session.id,
                                          at: ProbeDate.parse(at),
                                          changedAt: nil,
                                          configs: ["X.SomeMod": .some("abc123")])
        let result = ProbeSegments.split(session, launches: [launch], changes: [change])
        // La coupure à At de la minute 2 la rend mixte.
        #expect(result.mixedMinutes.map(\.at) == [at])
        #expect(result.segments.map(\.minutes.count) == [1, 3])
    }

    /// Horloge décalée : une coupure hors de la session ne perd aucune minute.
    @Test func outOfBoundsChangeLosesNoMinute() throws {
        let session = try session("2026-09-28T18:56")
        let launch = try #require(try inventory().launches.first { $0.session.hasPrefix("2026-09-28T18:56") })
        for cut in [Date.distantFuture, Date.distantPast] {
            let change = ProbeInventoryChange(session: session.id, at: nil, changedAt: cut,
                                              configs: ["X.SomeMod": .some("abc123")])
            let result = ProbeSegments.split(session, launches: [launch], changes: [change])
            #expect(result.segments.flatMap(\.minutes).count == 5)
            #expect(result.mixedMinutes.isEmpty)
        }
    }
}
