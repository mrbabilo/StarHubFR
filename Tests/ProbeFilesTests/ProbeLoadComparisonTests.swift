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
        // Deux sessions de chaque côté : le bruit se mesure dans la comparaison (option 4).
        let records = [Self.record("a", at: 0, total: 90_000), Self.record("a2", at: 30, total: 91_000),
                       Self.record("b", at: 60, total: 78_000), Self.record("b2", at: 90, total: 78_500)]
        let launches = [Self.launch("a", at: -1, mods: Self.withAF), Self.launch("a2", at: 29, mods: Self.withAF),
                        Self.launch("b", at: 59, mods: Self.withoutAF), Self.launch("b2", at: 89, mods: Self.withoutAF)]
        let r = try #require(ProbeLoadComparison.compare(records, kind: .save, launches: launches, changes: [], coldBefore: nil))
        guard case .faster(let s, _) = r.verdict else { Issue.record("\(r.verdict)"); return }
        #expect(abs(s - 12.25) < 0.01)
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

    /// Option 4 (2026-09-30) : le bruit se mesure dans la comparaison même,
    /// sur la dispersion de chaque côté — trois sessions 0.6.2 sur le parc de
    /// 286 mods ont donné 89,6/83,0/82,3 s, soit 8,9 %.
    @Test func noiseIsTheWidestSpreadOfEitherSide() {
        #expect(ProbeLoadComparison.observedNoisePercent(before: [100, 102], after: [80, 100]) == 25)
        #expect(ProbeLoadComparison.observedNoisePercent(before: [82_300, 89_600, 83_000], after: [80_000, 80_000]) != nil)
        #expect(ProbeLoadComparison.observedNoisePercent(before: [100], after: [90, 90]) == 0)
        #expect(ProbeLoadComparison.observedNoisePercent(before: [100], after: [90]) == nil)
    }

    @Test func thresholdIsTwiceTheNoiseWithAFivePercentFloor() {
        #expect(ProbeLoadComparison.thresholdPercent(noise: 1) == 5)
        #expect(ProbeLoadComparison.thresholdPercent(noise: 2.5) == 5)
        #expect(abs(ProbeLoadComparison.thresholdPercent(noise: 8.9) - 17.8) < 1e-9)
    }

    @Test func quietSidesDecideAtFivePercent() {
        // Bruit 1 % : seuil 5 %.
        #expect(ProbeLoadComparison.verdict(before: [100_000, 101_000], after: [94_000, 94_500]).isFaster)
        #expect(ProbeLoadComparison.verdict(before: [100_000, 101_000], after: [100_500, 101_000]) == .noDifference)
        #expect(ProbeLoadComparison.verdict(before: [100_000, 101_000], after: [97_000, 97_500])
                == .grayZone(beforeCount: 2, afterCount: 2))
    }

    @Test func noisySidesWidenTheThreshold() {
        // Les trois sessions réelles d'un côté : 8,9 % de bruit, seuil 17,8 %.
        // Un gain de 10 % n'est plus tranché ; un gain de 25 % l'est.
        let before = [89_600.0, 83_000, 82_300]
        #expect(ProbeLoadComparison.verdict(before: before, after: [74_700, 74_900])
                == .grayZone(beforeCount: 3, afterCount: 2))
        #expect(ProbeLoadComparison.verdict(before: before, after: [62_000, 62_500]).isFaster)
    }

    @Test func aSingleSessionOnEitherSideNeverDecides() {
        #expect(ProbeLoadComparison.verdict(before: [100_000], after: [50_000, 50_100])
                == .grayZone(beforeCount: 1, afterCount: 2))
        #expect(ProbeLoadComparison.verdict(before: [100_000, 100_100], after: [50_000])
                == .grayZone(beforeCount: 2, afterCount: 1))
        #expect(ProbeLoadComparison.verdict(before: [100_000], after: [100_000])
                == .grayZone(beforeCount: 1, afterCount: 1))
    }

    @Test func verdictDecidedFlags() {
        #expect(ProbeLoadVerdict.faster(seconds: 1, percent: 10).isDecided)
        #expect(ProbeLoadVerdict.slower(seconds: 1, percent: 10).isDecided)
        #expect(!ProbeLoadVerdict.noDifference.isDecided)
        #expect(!ProbeLoadVerdict.grayZone(beforeCount: 1, afterCount: 1).isDecided)
    }

    /// La position de la sonde (étape 2) : deux places, pas de comparaison —
    /// et le motif frappe avant « sans inventaire » (fixtures qui n'en ont pas).
    @Test func aDifferentProbePositionIsExcluded() throws {
        let records = ProbeLoadRecords.decode(try Fixture.data("loads-load.jsonl")).records
        // Inventaire pour chaque session : sans lui, la référence elle-même
        // compte un noInventory et masquerait l'ordre des motifs.
        let launches = records.map { record in
            ProbeInventoryLaunch(session: record.session, at: record.at, probe: record.probeVersion,
                                 mods: [ProbeInventoryEntry(modId: "X", version: "1", configSha: nil)])
        }
        let exclusions = ProbeLoadComparison.exclusions(records, kind: .launch, launches: launches,
                                                        changes: [], coldBefore: nil)
        #expect(exclusions[.probePosition, default: 0] >= 1)
        #expect(exclusions[.noInventory, default: 0] == 0)   // le motif frappe avant
    }
}
