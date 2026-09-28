import Testing
import Foundation
@testable import StarHubTHCore

struct ProbeComparisonChartTests {
    private func report(_ a: Int, _ b: Int) throws -> ProbePerformanceReport {
        let sessions = ProbeSessions.decode(timings: try Fixture.data("timings.jsonl"),
                                            costs: try Fixture.data("mod-costs.jsonl"))
        let inventory = ProbeInventory.decode(try Fixture.data("inventory.jsonl"))
        let sides = ProbePerformance.sides(sessions: sessions, launches: inventory.launches,
                                           changes: inventory.changes, measurements: [])
        return ProbePerformance.report(before: sides[a], after: sides[b])
    }

    /// Un point par minute gardée, de chaque côté ; une boîte seulement à
    /// 5 minutes ou plus (spec §3c, « Moins de 5 minutes d'un côté »).
    @Test func pointsForEveryKeptMinuteAndBoxesFromFive() throws {
        let r = try report(0, 2)
        let chart = ProbeComparisonChart.distribution(r, measure: .frameP50)
        #expect(chart.points.filter { $0.side == .before }.count == r.keptBefore.count)
        #expect(chart.points.filter { $0.side == .after }.count == r.keptAfter.count)
        #expect(chart.boxes.map(\.side) == [r.keptBefore.count >= 5 ? .before : nil,
                                            r.keptAfter.count >= 5 ? .after : nil].compactMap { $0 })
        #expect(chart.points.allSatisfy { abs($0.jitter) <= 0.3 })
    }

    /// Review Focus 1 — côté entièrement écarté (18:56) : aucun point, et la
    /// chronologie porte chaque minute avec sa raison, sans valeur.
    @Test func distributionOfAFullyExcludedSideIsEmptyAndTimelineGivesReasons() throws {
        let r = try report(3, 4)   // 18:56 → 19:21#0
        #expect(ProbeComparisonChart.distribution(r, measure: .frameP50).points
                .filter { $0.side == .before }.isEmpty)
        let excluded = ProbeComparisonChart.timeline(r).marks.filter { $0.side == .before }
        #expect(excluded.count == 5)
        #expect(excluded.allSatisfy { $0.value == nil && $0.reason != nil })
    }

    /// Haltères : les 8 plus fortes variations absolues, le reste compté.
    @Test func dumbbellsKeepTheLargestEightAndFoldTheRest() {
        let deltas = (0..<11).map {
            ProbeCostDelta(modId: "Mod.\($0)", msPerSecondA: 1, msPerSecondB: 1 + Double($0),
                           presence: .both)
        }.sorted { abs($0.delta) > abs($1.delta) }
        let result = ProbeComparisonChart.dumbbells(deltas)
        #expect(result.rows.count == 8)
        #expect(result.rows.first?.modId == "Mod.10")
        #expect(result.others == 3)
        let added = ProbeComparisonChart.dumbbells([
            ProbeCostDelta(modId: "New", msPerSecondA: nil, msPerSecondB: 2, presence: .added)])
        #expect(added.rows.first?.before == nil && added.rows.first?.after == 2)
    }

    @Test func measuresReadTheRightField() throws {
        let json = """
        {"Session":"s","At":"2026-09-28T10:00:00.0000000+02:00","WallSeconds":60,"Fps":42,
         "FrameInterval":{"Count":45,"Avg":30,"P50":24,"P99":50,"Max":60},
         "Update":{"Count":60,"Avg":5,"P50":5,"P99":9,"Max":10},
         "Draw":{"Count":45,"Avg":4,"P50":4,"P99":8,"Max":9}}
        """
        let minute = try ProbeJSON.decoder().decode(ProbeMinute.self, from: Data(json.utf8))
        #expect(ProbeComparisonChart.value(of: minute, .frameP50) == 24)
        #expect(ProbeComparisonChart.value(of: minute, .frameP99) == 50)
        #expect(ProbeComparisonChart.value(of: minute, .work) == 9)
        #expect(ProbeComparisonChart.value(of: minute, .fps) == 42)
    }
}
