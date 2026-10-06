import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct SloDiagnosticReportTests {
    private func minute(_ at: String, location: String? = "Farm", inactive: Int = 0,
                        p50: Double = 16.7, p99: Double = 30,
                        workingSet: Double? = nil) throws -> ProbeMinute {
        var json: [String: Any] = [
            "Session": "2026-10-06T23:58:00Z", "At": at, "WallSeconds": 60,
            "Fps": 60, "InactiveTicks": inactive,
            "FrameInterval": ["Count": 3_600, "Avg": p50, "P50": p50,
                              "P99": p99, "Max": p99 * 2]
        ]
        if let location { json["Location"] = location }
        if let workingSet { json["WorkingSetMB"] = workingSet }
        return try ProbeJSON.decoder().decode(
            ProbeMinute.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func cost(_ at: String, msPerSecond: Double,
                      patchesMeasured: Bool) throws -> ProbeModCostMinute {
        let json: [String: Any] = [
            "Session": "2026-10-06T23:58:00Z", "At": at, "WallSeconds": 60,
            "Frames": 3_600, "InactiveTicks": 0, "Location": "Farm",
            "PatchesMeasured": patchesMeasured,
            "Mods": [["Mod": SloDiagnosticContract.uniqueId, "SelfMs": msPerSecond * 60,
                      "MsPerSecond": msPerSecond, "MaxMs": 2.5, "AllocKB": 64,
                      "Calls": 3_600, "Events": []]]
        ]
        return try ProbeJSON.decoder().decode(
            ProbeModCostMinute.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func load(_ kind: ProbeLoadRecord.Kind, total: Double,
                      patchesMeasured: Bool = true) -> ProbeLoadRecord {
        let prefix = kind == .launch ? "L" : "S"
        let final = kind == .launch ? "L4" : "S9"
        return ProbeLoadRecord(
            kind: kind, session: "2026-10-06T23:58:00Z", atText: "2026-10-06T23:58:10Z",
            at: Date(timeIntervalSince1970: 0), probeVersion: "1.0.0", complete: true,
            reload: false, saveName: kind == .save ? "Farm" : nil,
            patchesMeasured: patchesMeasured, saveBytes: nil, saveDate: nil,
            milestones: [.init(name: "\(prefix)0", ms: 0), .init(name: final, ms: total)],
            phases: [.init(from: "\(prefix)0", to: kind == .launch ? "L1" : "S1",
                           ms: total,
                           costs: [.init(mod: "Example.Mod", kind: .event, label: "event",
                                         ms: total * 0.7, allocMb: 1, calls: 1)])],
            final: nil,
            health: .init(packSeam: "ok", assetHook: "ok", loadHook: "ok",
                          offThreadSections: 0))
    }

    @Test func parsesLatestCumulativeCacheSnapshots() throws {
        let log = SloDiagnosticLog.parse("""
        [18:00:00 INFO SLO] [MAP CACHE SNAPSHOT] hits=700, misses=2, corruptions=1, files=700
        [18:00:01 INFO SLO] [MAP CACHE SNAPSHOT] corruptions=0, files=802, misses=0, hits=802
        [18:00:02 INFO SLO] [MAP CACHE SNAPSHOT] hits=-1, misses=0, corruptions=0
        [18:00:03 INFO SLO] [IMAGE CACHE SNAPSHOT] evictions=179, misses=1604, limitMB=384, hits=1692, usedMB=382,5, refused=3
        """)
        let map = try #require(log.mapCache)
        #expect(map.hits == 802)
        #expect(map.misses == 0)
        #expect(map.corruptions == 0)
        #expect(map.files == 802)
        let image = try #require(log.imageCache)
        #expect(image.usedMB == 382.5)
        #expect(image.limitMB == 384)
        #expect(image.hits == 1_692)
        #expect(image.misses == 1_604)
        #expect(image.evictions == 179)
        #expect(image.refusedAdmissions == 3)
    }

    @Test func parsesPreparationAndIntegrationSnapshots() throws {
        let log = SloDiagnosticLog.parse("""
        [PREFETCH SNAPSHOT] planned=120, read=80, bytes=1048576, complete=false
        [PREFETCH SNAPSHOT] bytes=2097152, complete=true, read=120, planned=120
        [DEFERRED TILE SNAPSHOT] calls=31, pending=2, warmed=29, failures=0
        [SPACECORE SNAPSHOT] fastPath=4, fallbacks=1, failures=0, parallelInitializations=3
        """)
        #expect(log.prefetch == SloPrefetchSnapshot(plannedFiles: 120, readFiles: 120,
                                                   bytes: 2_097_152, complete: true))
        #expect(log.deferredTiles == SloDeferredTileSnapshot(calls: 31, pending: 2,
                                                            warmed: 29, failures: 0))
        #expect(log.spaceCore == SloSpaceCoreSnapshot(fastPath: 4, fallbacks: 1,
                                                     failures: 0, parallelInitializations: 3))
    }

    @Test func parsesWarpOutcomesAndIgnoresMalformedLines() {
        let durations = [1440.9, 603.1, 498.6, 288.6, 351.7, 377.5, 441.0, 366.4,
                         278.9, 341.3, 438.3, 299.8, 297.9, 431.4, 358.5, 364.3]
        let complete = durations.enumerated().map {
            "[23:59:\(String(format: "%02d", $0.offset)) INFO SLO] [FAST WARP COMPLETE] destination=L\($0.offset), durationMs=\($0.element)"
        }
        let text = (complete + [
            "[00:00:20 INFO SLO] [FAST WARP ABORT] reason=event-active",
            "[00:01:20 INFO SLO] [FAST WARP EXCLUDED] reason=multiplayer",
            "[FAST WARP COMPLETE] destination=Broken, durationMs=nan",
            "[MAP CACHE SNAPSHOT] hits=oops, misses=0, corruptions=0"
        ]).joined(separator: "\n")
        let log = SloDiagnosticLog.parse(text)
        #expect(log.warps.filter { $0.outcome == .complete }.count == 16)
        #expect(log.warps.filter { $0.outcome == .abort }.count == 1)
        #expect(log.warps.filter { $0.outcome == .excluded }.count == 1)
        #expect(log.warps.first?.timeOfDaySeconds == 86_340)
    }

    @Test func keepsNestedScopesSeparateAndOptionalFieldsOptional() throws {
        let log = SloDiagnosticLog.parse("""
        [NATIVE PHASE] name=SaveGame.Load, durationMs=810,5
        [CONTENT PATCHER HOTSPOTS] name=EditData:Characters, durationMs=240.25, top=Pack.A:120;Pack.B:80
        [READY SLOW UPDATE] durationMs=32.4
        """)
        #expect(log.nativePhases == [SloDurationScope(name: "SaveGame.Load", durationMs: 810.5)])
        #expect(log.contentPatcherHotspots == [
            SloDurationScope(name: "EditData:Characters", durationMs: 240.25)
        ])
        let update = try #require(log.readyStalls.first)
        #expect(update.durationMs == 32.4)
        #expect(update.label == nil)
    }

    @Test func reportUsesLatestConfigAndKeepsScopesUnstacked() throws {
        let text = """
        [OPTIMIZER CONFIG] profile=2, detailedDiagnostics=False, performanceMeasurement=False.
        [OPTIMIZER CONFIG MIGRATION] profile=2, reason=upgrade.
        [OPTIMIZER CONFIG] profile=3, detailedDiagnostics=True, performanceMeasurement=True, workingSetSoftLimit=1000 MB.
        [NATIVE PHASE] name=SaveGame.Load, durationMs=810
        [CONTENT PATCHER HOTSPOTS] name=Pack work, durationMs=240
        """
        let report = SloDiagnosticReport.build(
            log: SloDiagnosticLog.parse(text),
            probe: SloDiagnosticProbeInput(session: nil, loads: [load(.launch, total: 1_000)],
                                           inventory: nil),
            startedAt: Date(timeIntervalSince1970: 0))
        #expect(report.config?.profile == 3)
        #expect(report.launch?.totalMs == 1_000)
        #expect(report.primaryWait == SloObservedWait(label: "smapiAndMods", durationMs: 1_000,
                                                      source: .probe))
        #expect(report.loadScopeMarks.contains(.init(label: "SaveGame.Load", durationMs: 810,
                                                    source: .sloNative)))
        #expect(report.loadScopeMarks.contains(.init(label: "Pack work", durationMs: 240,
                                                    source: .sloContentPatcher)))
        #expect(report.loadScopeMarks.count == 3)
    }

    @Test func warpSummaryUsesMedianAndCachePressureStaysSeparateFromMemory() throws {
        let values = [1440.9, 603.1, 498.6, 288.6, 351.7, 377.5, 441.0, 366.4,
                      278.9, 341.3, 438.3, 299.8, 297.9, 431.4, 358.5, 364.3]
        let lines = values.map { "[FAST WARP COMPLETE] durationMs=\($0), destination=Farm" }
            + ["[IMAGE CACHE SNAPSHOT] usedMB=382.5, limitMB=384, hits=1692, misses=1604, evictions=179"]
        let report = SloDiagnosticReport.build(
            log: .parse(lines.joined(separator: "\n")),
            probe: .init(session: nil, loads: [], inventory: nil), startedAt: .distantPast)
        #expect(report.warps?.completed == 16)
        #expect(report.warps?.medianMs == 365.35)
        #expect(report.warps?.minimumMs == 278.9)
        #expect(report.warps?.maximumMs == 1_440.9)
        #expect(report.imageCache?.capacity == .nearLimit)
        #expect(report.memory == nil)
    }

    @Test func memoryThresholdsAreInclusiveAtNinetyAndOneHundredPercent() throws {
        func report(_ workingSet: Double) throws -> SloDiagnosticReport {
            let session = ProbeSession(id: "2026-10-06T23:58:00Z",
                                       minutes: [try minute("2026-10-07T00:03:00Z",
                                                            workingSet: workingSet)], costs: [])
            return SloDiagnosticReport.build(
                log: .parse("[OPTIMIZER CONFIG] workingSetSoftLimit=1000 MB."),
                probe: .init(session: session, loads: [], inventory: nil),
                startedAt: Date(timeIntervalSince1970: 0))
        }
        #expect(try report(900).memory?.pressure == .nearLimit)
        #expect(try report(999).memory?.pressure == .nearLimit)
        #expect(try report(1_000).memory?.pressure == .exceeded)
    }

    @Test func stableGameplayExcludesLoadingInactiveAndMidnightTransitions() throws {
        let minutes = [
            try minute("2026-10-06T23:59:00Z", location: nil),
            try minute("2026-10-07T00:00:00Z", p50: 100),
            try minute("2026-10-07T00:01:00Z", p50: 80),
            try minute("2026-10-07T00:02:00Z", inactive: 1, p50: 70),
            try minute("2026-10-07T00:03:00Z", p50: 20, workingSet: 800),
            try minute("2026-10-07T00:04:00Z", p50: 30, workingSet: 900)
        ]
        let costs = [try cost("2026-10-07T00:03:00Z", msPerSecond: 0.2, patchesMeasured: true),
                     try cost("2026-10-07T00:04:00Z", msPerSecond: 0.4, patchesMeasured: false)]
        let session = ProbeSession(id: "2026-10-06T23:58:00Z", minutes: minutes, costs: costs)
        let log = SloDiagnosticLog.parse("""
        [23:59:50 INFO SLO] [FAST WARP COMPLETE] durationMs=300, destination=Farm
        [00:00:20 INFO SLO] [FAST WARP ABORT] reason=event
        """)
        let report = SloDiagnosticReport.build(log: log,
                                               probe: .init(session: session, loads: [], inventory: nil),
                                               startedAt: Date(timeIntervalSince1970: 0))
        #expect(report.steadyGameplay?.sampleCount == 2)
        #expect(report.frameMarks.map(\.value) == [20, 30])
        #expect(report.sloRuntime?.sampleCount == 2)
        #expect(report.sloRuntime?.averageMsPerSecond == 0.3)
        #expect(report.sloRuntime?.maximumMs == 2.5)
        #expect(report.limitations.contains(.patchesNotMeasured))
        #expect(!report.limitations.contains(.transitionWindowsUnknown))
    }

    @Test func uncorrelatableTransitionIsNamedAndDoesNotInventExclusion() throws {
        let session = ProbeSession(id: "2026-10-06T23:58:00Z",
                                   minutes: [try minute("2026-10-07T00:03:00Z")], costs: [])
        let report = SloDiagnosticReport.build(
            log: .parse("[FAST WARP ABORT] reason=no-clock"),
            probe: .init(session: session, loads: [], inventory: nil), startedAt: .distantPast)
        #expect(report.steadyGameplay?.sampleCount == 1)
        #expect(report.limitations.contains(.transitionWindowsUnknown))
    }

    @Test func partialReportNamesMissingEvidenceInsteadOfUsingZero() {
        let report = SloDiagnosticReport.build(log: .parse(""),
                                               probe: .init(session: nil, loads: [], inventory: nil),
                                               startedAt: Date(timeIntervalSince1970: 0))
        #expect(report.launch == nil)
        #expect(report.save == nil)
        #expect(report.warps == nil)
        #expect(report.steadyGameplay == nil)
        #expect(report.limitations.contains(.sloLogMissing))
        #expect(report.limitations.contains(.probeMissing))
        #expect(report.limitations.contains(.singleSession))
        #expect(report.limitations.contains(.noControlRun))
    }
}
