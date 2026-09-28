import Testing
import Foundation
@testable import StarHubTHCore

struct ProbePerformanceTests {
    private func sides(measurements: [ProbeMeasurement] = []) throws -> [ProbeSide] {
        let sessions = ProbeSessions.decode(timings: try Fixture.data("timings.jsonl"),
                                            costs: try Fixture.data("mod-costs.jsonl"))
        let inventory = ProbeInventory.decode(try Fixture.data("inventory.jsonl"))
        return ProbePerformance.sides(sessions: sessions, launches: inventory.launches,
                                      changes: inventory.changes, measurements: measurements)
    }

    /// Un côté par segment qui a des minutes : la session de 02:33 (coûts
    /// seuls) n'en donne aucun ; celle de 19:21 en donne deux (coupure).
    @Test func oneSidePerSegmentWithMinutes() throws {
        let all = try sides()
        #expect(all.map { String($0.session.prefix(16)) }
                == ["2026-09-26T01:38", "2026-09-26T01:53", "2026-09-26T20:30",
                    "2026-09-28T18:56", "2026-09-28T19:21", "2026-09-28T19:21"])
        #expect(all.map(\.minutes.count) == [8, 11, 8, 5, 1, 1])
        #expect(all.filter { $0.inventory == nil }.count == 3)
    }

    /// Paire par défaut : les deux derniers côtés dont l'inventaire diffère
    /// — ici les deux segments de 19:21, séparés par le réglage GMCM.
    @Test func defaultPairIsTheLastInventoryChange() throws {
        let pair = try #require(ProbePerformance.defaultPair(try sides()))
        #expect(pair.before.id.hasPrefix("2026-09-28T19:21") && pair.before.id.hasSuffix("#0"))
        #expect(pair.after.id.hasSuffix("#1"))
    }

    /// Review Focus 2 — un côté sans inventaire (sonde < 0.4.12) : le rapport
    /// se construit, sans différence inventée.
    @Test func sideWithoutInventoryGivesNoDiff() throws {
        let all = try sides()
        let report = ProbePerformance.report(before: all[2], after: all[3])
        #expect(report.diff == nil)
        #expect(report.comparison.frameP50.a.count == report.keptBefore.count)
    }

    /// Entre deux côtés inventoriés : la différence GMCM, réglage changé.
    @Test func reportCarriesTheInventoryDiff() throws {
        let all = try sides()
        let report = ProbePerformance.report(before: all[4], after: all[5])
        #expect(report.diff?.changes.map(\.modId) == ["spacechase0.GenericModConfigMenu"])
    }

    /// Un segment qui commence après une coupure garde les verdicts de la
    /// session : sa première minute n'est pas un « chargement ».
    @Test func aSegmentAfterACutIsNotALoadingStart() throws {
        func minute(_ at: String) throws -> ProbeMinute {
            let json = """
            {"Session":"2026-09-28T09:59:00.0000000+02:00","At":"2026-09-28T\(at):00.0000000+02:00",
             "WallSeconds":60,"Fps":30,"FrameInterval":{"Count":45,"Avg":30,"P50":30,"P99":50,"Max":60},
             "InactiveTicks":0,"Location":"Farm","MenuTicks":0,
             "Tick":{"Count":60,"Avg":20,"P50":20,"P99":40,"Max":50},"GameTime":650}
            """
            return try ProbeJSON.decoder().decode(ProbeMinute.self, from: Data(json.utf8))
        }
        let minutes = try ["10:00", "10:01", "10:02", "10:03"].map(minute)
        let id = "2026-09-28T09:59:00.0000000+02:00"   // `group` range les minutes par leur `Session`
        let launch = ProbeInventoryLaunch(session: id, at: nil, probe: "0.4.13",
                                          mods: [ProbeInventoryEntry(modId: "A", version: "1", configSha: "aa")])
        let cut = ProbeInventoryChange(session: id, at: nil,
                                       changedAt: ProbeDate.parse("2026-09-28T10:01:30.0000000+02:00"),
                                       configs: ["A": .some("bb")])
        let all = ProbePerformance.sides(sessions: ProbeSessions.group(minutes: minutes, costs: []),
                                         launches: [launch], changes: [cut], measurements: [])
        // 10:00 chargement ; 10:01 gardée ; 10:02 mixte (coupure dedans) ; 10:03 gardée.
        #expect(all.map(\.comparable.kept.count) == [1, 1])
        #expect(all.last?.comparable.exclusions.isEmpty == true)
    }

    /// Une mesure propre devient un côté à part, dans sa fenêtre.
    @Test func aMeasurementIsItsOwnSide() throws {
        let start = try #require(ProbeDate.parse("2026-09-28T18:56:39.7835810+02:00"))
        let measurement = ProbeMeasurement(name: "essai", start: start,
                                           end: start.addingTimeInterval(4 * 60))
        let all = try sides(measurements: [measurement])
        let side = try #require(all.first { $0.id == "m:\(measurement.id.uuidString)" })
        #expect(side.kind == .measurement(measurement, crossedChangeAt: nil))
        #expect(side.minutes.count == 2)
        #expect(side.inventory?.count == 289)
    }
}
