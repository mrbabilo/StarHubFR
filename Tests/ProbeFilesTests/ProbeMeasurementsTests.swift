import Testing
import Foundation
@testable import StarHubTHCore

struct ProbeMeasurementsTests {

    private func sessions() throws -> ProbeSessions {
        ProbeSessions.decode(timings: try Fixture.data("timings.jsonl"), costs: nil)
    }

    private func segments(_ prefix: String) throws -> (session: ProbeSession, segments: [ProbeSegment]) {
        let session = try #require(try sessions().sessions.first { $0.id.hasPrefix(prefix) })
        let inv = ProbeInventory.decode(try Fixture.data("inventory.jsonl"))
        return (session, ProbeSegments.split(session, launches: inv.launches, changes: inv.changes).segments)
    }

    /// La fenêtre coupe : minutes dedans, la coupure signalée, les minutes
    /// d'après exclues.
    @Test func windowExcludesMinutesAfterCrossedChange() throws {
        let (session, segments) = try segments("2026-09-28T19:21")
        let measurement = ProbeMeasurement(name: "à travers la coupure",
                                           start: try #require(session.startedAt),
                                           end: Date().addingTimeInterval(3600))
        let result = ProbeMeasurementsLogic.segment(measurement, segments: segments)
        // La fenêtre traverse la coupure de 19:24:56 : la minute d'avant
        // compte, celle d'après est exclue (spec « Mesure propre »).
        #expect(result.minutes.count == 1)
        #expect(result.crossedChangeAt == ProbeDate.parse("2026-09-28T19:24:56.7752188+02:00"))
    }

    /// Sans coupure, la fin du dernier segment (la dernière minute) n'est pas
    /// un changement de réglage.
    @Test func windowOverWholeSessionCrossesNothing() throws {
        let (session, segments) = try segments("2026-09-28T18:56")
        let measurement = ProbeMeasurement(name: "toute la session",
                                           start: try #require(session.startedAt), end: nil)
        let result = ProbeMeasurementsLogic.segment(measurement, segments: segments)
        #expect(result.minutes.count == 5)
        #expect(result.crossedChangeAt == nil)
    }

    /// La fenêtre ne garde que les minutes de `keptAt` : la sonde a écarté
    /// les autres (autre lieu, minute partielle), l'app les garderait.
    @Test func windowKeepsOnlyTheProbeKeptMinutes() throws {
        let (session, segments) = try segments("2026-09-28T18:56")
        let dates = session.minutes.compactMap { ProbeDate.parse($0.at) }.sorted()
        let measurement = ProbeMeasurement(name: "guidée", start: dates[0], end: dates[4],
                                           keptAt: [dates[1], dates[3]], outcome: .stable)
        let result = ProbeMeasurementsLogic.segment(measurement, segments: segments)
        #expect(result.minutes.compactMap { ProbeDate.parse($0.at) } == [dates[1], dates[3]])
    }
}
