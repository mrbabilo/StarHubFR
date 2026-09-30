import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct ProbeLoadComparisonTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    static func record(_ session: String, at minutes: Double, total: Double, kind: ProbeLoadRecord.Kind = .save,
                       save: String? = "TestOK_444827372", bytes: Int64? = 33_922_308, probe: String = "0.6.0",
                       complete: Bool = true, reload: Bool = false, patches: Bool = false,
                       costs: [ProbeLoadCost] = []) -> ProbeLoadRecord {
        let last = kind == .launch ? "L4" : "S9"
        let first = kind == .launch ? "L0" : "S0"
        return ProbeLoadRecord(kind: kind, session: session, atText: "", at: t0.addingTimeInterval(minutes * 60),
                               probeVersion: probe, complete: complete, reload: reload,
                               saveName: kind == .save ? save : nil, patchesMeasured: patches,
                               saveBytes: kind == .save ? bytes : nil, saveDate: nil,
                               milestones: [.init(name: first, ms: 0), .init(name: last, ms: total)],
                               phases: [.init(from: first, to: last, ms: total, costs: costs)],
                               final: nil, health: .init(packSeam: "ok", assetHook: "ok", loadHook: "ok", offThreadSections: 0))
    }

    static func launch(_ session: String, at minutes: Double, mods: [(String, String)]) -> ProbeInventoryLaunch {
        ProbeInventoryLaunch(session: session, at: t0.addingTimeInterval(minutes * 60), probe: "0.6.0",
                             mods: mods.map { ProbeInventoryEntry(modId: $0.0, version: $0.1, configSha: nil) })
    }

    static let withAF = [("Pathoschild.AutoForager", "1.0"), ("X", "1.0")]
    static let withoutAF = [("X", "1.0")]

    @Test func pausedModGivesFaster() throws {
        let records = [Self.record("a", at: 0, total: 90_000), Self.record("b", at: 60, total: 78_000)]
        let launches = [Self.launch("a", at: -1, mods: Self.withAF), Self.launch("b", at: 59, mods: Self.withoutAF)]
        let r = try #require(ProbeLoadComparison.compare(records, kind: .save, launches: launches, changes: [], coldBefore: nil))
        guard case .faster(let s, _) = r.verdict else { Issue.record("\(r.verdict)"); return }
        #expect(abs(s - 12) < 0.01)
        #expect(r.diff.changes.map(\.modId) == ["Pathoschild.AutoForager"])
    }

    @Test func sameStateTwiceIsNoComparison() {
        let records = [Self.record("a", at: 0, total: 90_000), Self.record("b", at: 60, total: 89_000)]
        let launches = [Self.launch("a", at: -1, mods: Self.withAF), Self.launch("b", at: 59, mods: Self.withAF)]
        #expect(ProbeLoadComparison.compare(records, kind: .save, launches: launches, changes: [], coldBefore: nil) == nil)
    }

    @Test func otherSaveIsExcluded() throws {
        let records = [Self.record("a", at: 0, total: 90_000, save: "Zofia_443716371"),
                       Self.record("b", at: 30, total: 91_000), Self.record("c", at: 60, total: 78_000)]
        let launches = [Self.launch("a", at: -1, mods: Self.withAF), Self.launch("b", at: 29, mods: Self.withAF),
                        Self.launch("c", at: 59, mods: Self.withoutAF)]
        let r = try #require(ProbeLoadComparison.compare(records, kind: .save, launches: launches, changes: [], coldBefore: nil))
        #expect(r.before.map(\.session) == ["b"])
        #expect(r.exclusions[.otherSave] == 1)
    }

    @Test func incompleteIsExcluded() throws {
        let records = [Self.record("a", at: 0, total: 90_000), Self.record("b", at: 30, total: 5_000, complete: false),
                       Self.record("c", at: 60, total: 78_000)]
        let launches = [Self.launch("a", at: -1, mods: Self.withAF), Self.launch("b", at: 29, mods: Self.withoutAF),
                        Self.launch("c", at: 59, mods: Self.withoutAF)]
        let r = try #require(ProbeLoadComparison.compare(records, kind: .save, launches: launches, changes: [], coldBefore: nil))
        #expect(r.after.map(\.session) == ["c"])
        #expect(r.exclusions[.incomplete] == 1)
    }

    @Test(arguments: [
        (ProbeLoadExclusion.olderProbe, "0.5.9", Int64(33_922_308), false, false),
        (.saveSize, "0.6.0", Int64(34_300_000), false, false),     // +1,1 %
        (.reloadDiffers, "0.6.0", Int64(33_922_308), true, false),
        (.patchesDiffer, "0.6.0", Int64(33_922_308), false, true),
    ])
    func eachGuardExcludesTheBeforeSide(_ reason: ProbeLoadExclusion, _ probe: String, _ bytes: Int64,
                                        _ reload: Bool, _ patches: Bool) {
        let records = [Self.record("a", at: 0, total: 90_000, bytes: bytes, probe: probe, reload: reload, patches: patches),
                       Self.record("c", at: 60, total: 78_000)]
        let launches = [Self.launch("a", at: -1, mods: Self.withAF), Self.launch("c", at: 59, mods: Self.withoutAF)]
        // Seul « avant » exclu : plus de comparaison possible, et le motif est compté.
        #expect(ProbeLoadComparison.compare(records, kind: .save, launches: launches, changes: [], coldBefore: nil) == nil)
        #expect(ProbeLoadComparison.exclusions(records, kind: .save, launches: launches, changes: [], coldBefore: nil)[reason] == 1)
    }

    @Test func saveSizeWithinOnePercentStillPairs() throws {
        let records = [Self.record("a", at: 0, total: 90_000, bytes: 34_200_000),   // +0,8 %
                       Self.record("c", at: 60, total: 78_000)]
        let launches = [Self.launch("a", at: -1, mods: Self.withAF), Self.launch("c", at: 59, mods: Self.withoutAF)]
        #expect(ProbeLoadComparison.compare(records, kind: .save, launches: launches, changes: [], coldBefore: nil) != nil)
    }

    @Test func coldLaunchIsExcludedOnlyWhenARuleIsGiven() throws {
        let records = [Self.record("a", at: 0, total: 110_000, kind: .launch), Self.record("b", at: 10, total: 100_000, kind: .launch),
                       Self.record("c", at: 60, total: 90_000, kind: .launch)]
        let launches = [Self.launch("a", at: -1, mods: Self.withAF), Self.launch("b", at: 9, mods: Self.withAF),
                        Self.launch("c", at: 59, mods: Self.withoutAF)]
        let cold = try #require(ProbeLoadComparison.compare(records, kind: .launch, launches: launches, changes: [],
                                                             coldBefore: Self.t0.addingTimeInterval(-120)))
        #expect(cold.before.map(\.session) == ["b"])
        #expect(cold.exclusions[.coldDisk] == 1)
        let none = try #require(ProbeLoadComparison.compare(records, kind: .launch, launches: launches, changes: [], coldBefore: nil))
        #expect(none.before.count == 2)
    }

    @Test func configChangedBeforeS0IsTheRecordState() throws {
        // Session b : lancée avec AutoForager réglé "old", réglage changé avant le chargement.
        let launchB = ProbeInventoryLaunch(session: "b", at: Self.t0.addingTimeInterval(59 * 60), probe: "0.6.0",
                                           mods: [ProbeInventoryEntry(modId: "Pathoschild.AutoForager", version: "1.0", configSha: "old")])
        let launchA = ProbeInventoryLaunch(session: "a", at: Self.t0.addingTimeInterval(-60), probe: "0.6.0",
                                           mods: [ProbeInventoryEntry(modId: "Pathoschild.AutoForager", version: "1.0", configSha: "old")])
        let change = ProbeInventoryChange(session: "b", at: Self.t0.addingTimeInterval(59.5 * 60),
                                          changedAt: Self.t0.addingTimeInterval(59.5 * 60), configs: ["Pathoschild.AutoForager": "new"])
        let records = [Self.record("a", at: 0, total: 90_000), Self.record("b", at: 60, total: 80_000)]
        let r = try #require(ProbeLoadComparison.compare(records, kind: .save, launches: [launchA, launchB],
                                                          changes: [change], coldBefore: nil))
        #expect(r.diff.changes.count == 1)
    }

    @Test func verdictZones() {
        let t = ProbeLoadComparison.thresholdPercent, n = ProbeLoadComparison.noiseMaxPercent
        #expect(ProbeLoadComparison.verdict(before: [100_000], after: [100_000 * (1 - (t + 0.5) / 100)]).isFaster)
        #expect(ProbeLoadComparison.verdict(before: [100_000], after: [100_000 * (1 + n / 200)]) == .noDifference)
        if t > n + 0.2 {
            let mid = (t + n) / 2
            #expect(ProbeLoadComparison.verdict(before: [100_000], after: [100_000 * (1 - mid / 100)])
                    == .grayZone(beforeCount: 1, afterCount: 1))
        }
    }

    @Test func thresholdNeverBelowFivePercent() {
        #expect(ProbeLoadComparison.thresholdPercent >= 5)
        #expect(ProbeLoadComparison.thresholdPercent == 5)   // mesuré 2026-09-30 : bruit 2,2 % → 2 × 2,2 < 5
    }

    @Test func verdictDecidedFlags() {
        #expect(ProbeLoadVerdict.faster(seconds: 1, percent: 10).isDecided)
        #expect(ProbeLoadVerdict.slower(seconds: 1, percent: 10).isDecided)
        #expect(!ProbeLoadVerdict.noDifference.isDecided)
        #expect(!ProbeLoadVerdict.grayZone(beforeCount: 1, afterCount: 1).isDecided)
    }
}
