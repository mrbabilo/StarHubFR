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

    /// Une mesure ouverte se clôt à la dernière minute de sa session.
    @Test func openMeasurementClosesAtLastMinute() throws {
        let all = try sessions()
        let session = try #require(all.sessions.first { $0.id.hasPrefix("2026-09-28T18:56") })
        let lastAt = session.minutes.compactMap { ProbeDate.parse($0.at) }.max()
        let open = ProbeMeasurement(name: "en cours", start: try #require(session.startedAt), end: nil)
        let closed = ProbeMeasurementsLogic.closeOpen([open], sessions: all)
        #expect(closed.first?.end != nil)
        #expect(closed.first?.end == lastAt)
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

    /// La session en cours n'a pas fini d'écrire : sa mesure ouverte reste
    /// ouverte.
    @Test func openMeasurementOfTheRunningSessionStaysOpen() throws {
        let all = try sessions()
        let session = try #require(all.sessions.first { $0.id.hasPrefix("2026-09-28T18:56") })
        let open = ProbeMeasurement(name: "en cours", start: try #require(session.startedAt), end: nil)
        let result = ProbeMeasurementsLogic.closeOpen([open], sessions: all, runningSession: session.id)
        #expect(result.first?.end == nil)
    }
}
