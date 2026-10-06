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

    /// Une session de benchmark n'est pas un côté : sa minute unique est
    /// toujours écartée (première en partie), et la paire par défaut la
    /// choisirait contre la dernière session manuelle. La ligne `loads` garde
    /// l'échappement réel de la sonde (`+`) : l'appariement se fait sur
    /// les identifiants décodés.
    @Test func benchmarkSessionsAreNotSides() throws {
        let line = #"{"Kind":"launch","Session":"2026-09-28T19:21:10.7621750+02:00","At":"2026-09-28T19:21:00.0000000+02:00","ProbeVersion":"0.7.0","Complete":true,"Reload":false,"SaveName":null,"PatchesMeasured":false,"SaveBytes":null,"SaveDate":null,"Milestones":[],"Phases":[],"Final":null,"Health":{"PackSeam":"ok","AssetHook":"ok","LoadHook":"ok","OffThreadSections":0},"BenchmarkRun":"run-1"}"#
        let manual = #"{"Kind":"launch","Session":"2026-09-28T18:56:39.7835810+02:00","At":"2026-09-28T18:56:00.0000000+02:00","ProbeVersion":"0.7.0","Complete":true,"Reload":false,"SaveName":null,"PatchesMeasured":false,"SaveBytes":null,"SaveDate":null,"Milestones":[],"Phases":[],"Final":null,"Health":{"PackSeam":"ok","AssetHook":"ok","LoadHook":"ok","OffThreadSections":0}}"#
        let records = ProbeLoadRecords.decode(Data((line + "\n" + manual).utf8)).records
        #expect(records.count == 2)
        let excluded = ProbeLoadRecords.benchmarkSessions(records)
        #expect(excluded == ["2026-09-28T19:21:10.7621750+02:00"])

        let sessions = ProbeSessions.decode(timings: try Fixture.data("timings.jsonl"),
                                            costs: try Fixture.data("mod-costs.jsonl"))
        let inventory = ProbeInventory.decode(try Fixture.data("inventory.jsonl"))
        let all = ProbePerformance.sides(sessions: sessions, launches: inventory.launches,
                                         changes: inventory.changes, measurements: [],
                                         excludingSessions: excluded)
        #expect(all.map { String($0.session.prefix(16)) }
                == ["2026-09-26T01:38", "2026-09-26T01:53", "2026-09-26T20:30", "2026-09-28T18:56"])
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

    /// Un côté sans minute comparable n'a aucun coût mesuré : pas de delta,
    /// jamais chaque mod de l'autre côté présenté en « nouveau » (parc réel,
    /// 2026-09-29 : UltraSmooth « nouveau +51 ms/s » pour un réglage changé).
    @Test func noCostDeltaWhenOneSideHasNoComparableMinute() throws {
        let all = try sides()
        let empty = try #require(all.first { $0.comparable.kept.isEmpty })
        let measured = try #require(all.first {
            !ProbeCosts.perMod($0.comparable.kept, costs: $0.costs).isEmpty })
        let report = ProbePerformance.report(before: empty, after: measured)
        #expect(report.keptBefore.isEmpty && report.keptAfter.isEmpty)
        #expect(report.scope.issues.contains(.noSharedLocation))
        #expect(report.costDeltas.isEmpty)
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

    private func guided(_ side: ProbeSide, outcome: ProbeMeasurement.Outcome, role: ProbeMeasurement.Role,
                        pairedWith: UUID? = nil, id: UUID = UUID()) -> ProbeMeasurement {
        let kept = Set(side.minutes.compactMap { ProbeDate.parse($0.at) })
        return ProbeMeasurement(id: id, name: "\(role)", start: kept.min()!, end: kept.max(), keptAt: kept,
                                outcome: outcome, role: role, pairedWith: pairedWith, location: "Farm")
    }

    /// La paire par défaut suit `PairedWith`, quel que soit l'ordre des rôles ;
    /// une mesure abandonnée n'est pas un côté.
    @Test func defaultPairFollowsPairedWith() throws {
        let plain = try sides()
        let before = guided(plain[0], outcome: .stable, role: .before)
        let after = guided(plain[2], outcome: .stable, role: .after, pairedWith: before.id)
        let dropped = guided(plain[1], outcome: .abandoned, role: .before)
        let all = try sides(measurements: [before, after, dropped])
        #expect(!all.contains { $0.measurement?.id == dropped.id })
        let pair = try #require(ProbePerformance.defaultPair(all))
        #expect(pair.before.measurement?.id == before.id && pair.after.measurement?.id == after.id)
    }

    /// Review Focus 4 — la mesure désignée a disparu : règle actuelle.
    @Test func orphanPairedWithFallsBackToTheUsualPair() throws {
        let plain = try sides()
        let orphan = guided(plain[2], outcome: .stable, role: .after, pairedWith: UUID())
        let all = try sides(measurements: [orphan])
        // Pas de paire guidée possible : la règle actuelle répond, sans planter.
        let pair = try #require(ProbePerformance.defaultPair(all))
        #expect(pair.before.id != pair.after.id)
    }

    /// Review Focus 1 — une minute de `keptAt` absente des segments (minute
    /// mixte d'une coupure) : le côté existe avec les autres minutes.
    @Test func keptMinuteMissingFromSegmentsIsTolerated() throws {
        let plain = try sides()
        var m = guided(plain[2], outcome: .stable, role: .before)
        m.keptAt?.insert(Date(timeIntervalSince1970: 0))
        let all = try sides(measurements: [m])
        let side = try #require(all.first { $0.measurement?.id == m.id })
        #expect(side.minutes.count == plain[2].minutes.count)
    }

    /// Mesure propre seulement si les deux côtés sont guidés et stables ; un
    /// côté bruité le dit. (La fixture n'a aucun côté à 5 minutes gardées :
    /// tester la règle, pas la preuve, qui exige 5 minutes de chaque côté.)
    @Test func guidedStatusNeedsTwoStableSides() {
        func m(_ outcome: ProbeMeasurement.Outcome) -> ProbeMeasurement {
            ProbeMeasurement(name: "m", start: .now, end: nil, outcome: outcome)
        }
        #expect(ProbePerformance.guidedStatus(m(.stable), m(.stable)) == (clean: true, noisy: false))
        #expect(ProbePerformance.guidedStatus(m(.stable), m(.noisy)) == (clean: false, noisy: true))
        #expect(ProbePerformance.guidedStatus(nil, m(.stable)) == (clean: false, noisy: false))
    }
}
