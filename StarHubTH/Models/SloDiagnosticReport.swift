import Foundation

public struct SloDiagnosticProbeInput: Equatable, Sendable {
    public let session: ProbeSession?
    public let loads: [ProbeLoadRecord]
    public let inventory: ProbeInventoryLaunch?

    public init(session: ProbeSession?, loads: [ProbeLoadRecord], inventory: ProbeInventoryLaunch?) {
        self.session = session
        self.loads = loads
        self.inventory = inventory
    }
}

public enum SloDiagnosticLimitation: String, Codable, Equatable, Sendable {
    case singleSession
    case noControlRun
    case sloLogMissing
    case probeMissing
    case loadEvidenceMissing
    case diagnosticsIncomplete
    case patchesNotMeasured
    case shortGameplay
    case transitionWindowsUnknown
    case nestedScopes
    case sessionInterrupted
}

public enum SloEvidenceSource: String, Codable, Equatable, Sendable {
    case probe
    case sloNative
    case sloContentPatcher
}

public struct SloObservedWait: Codable, Equatable, Sendable {
    public let label: String
    public let durationMs: Double
    public let source: SloEvidenceSource

    public init(label: String, durationMs: Double, source: SloEvidenceSource) {
        self.label = label
        self.durationMs = durationMs
        self.source = source
    }
}

public struct SloLoadScopeMark: Codable, Equatable, Sendable {
    public let label: String
    public let durationMs: Double
    public let source: SloEvidenceSource

    public init(label: String, durationMs: Double, source: SloEvidenceSource) {
        self.label = label
        self.durationMs = durationMs
        self.source = source
    }
}

public struct SloLoadCostSummary: Codable, Equatable, Sendable {
    public let mod: String
    public let durationMs: Double
    public let isPack: Bool
}

public struct SloLoadSummary: Codable, Equatable, Sendable {
    public let totalMs: Double
    public let complete: Bool
    public let spans: [SloLoadScopeMark]
    public let directCosts: [SloLoadCostSummary]
}

public enum SloCapacityState: String, Codable, Equatable, Sendable {
    case normal
    case nearLimit
    case exceeded
}

public struct SloMapCacheAnalysis: Codable, Equatable, Sendable {
    public let snapshot: SloMapCacheSnapshot
    public let used: Bool
    public let failuresObserved: Bool
}

public struct SloImageCacheAnalysis: Codable, Equatable, Sendable {
    public let snapshot: SloImageCacheSnapshot
    public let used: Bool
    public let failuresObserved: Bool
    public let capacity: SloCapacityState
}

public struct SloWarpSummary: Codable, Equatable, Sendable {
    public let completed: Int
    public let aborted: Int
    public let excluded: Int
    public let medianMs: Double?
    public let minimumMs: Double?
    public let maximumMs: Double?
}

public struct SloStableGameplaySummary: Codable, Equatable, Sendable {
    public let sampleCount: Int
    public let medianFrameMs: Double
    public let p99FrameMs: Double
}

public struct SloChartMark: Codable, Equatable, Sendable {
    public let at: Date
    public let value: Double
}

public struct SloRuntimeSummary: Codable, Equatable, Sendable {
    public let sampleCount: Int
    public let averageMsPerSecond: Double
    public let maximumMs: Double
    public let allocationKB: Double
}

public struct SloMemorySummary: Codable, Equatable, Sendable {
    public let maximumWorkingSetMB: Double
    public let softLimitMB: Double
    public let pressure: SloCapacityState
}

public struct SloReadyStallSummary: Codable, Equatable, Sendable {
    public let count: Int
    public let maximumMs: Double
}

public struct SloDiagnosticReport: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let config: SloOptimizerConfig?
    public let launch: SloLoadSummary?
    public let save: SloLoadSummary?
    public let primaryWait: SloObservedWait?
    public let loadScopeMarks: [SloLoadScopeMark]
    public let mapCache: SloMapCacheAnalysis?
    public let imageCache: SloImageCacheAnalysis?
    public let prefetch: SloPrefetchSnapshot?
    public let deferredTiles: SloDeferredTileSnapshot?
    public let spaceCore: SloSpaceCoreSnapshot?
    public let warps: SloWarpSummary?
    public let steadyGameplay: SloStableGameplaySummary?
    public let frameMarks: [SloChartMark]
    public let memoryMarks: [SloChartMark]
    public let sloRuntime: SloRuntimeSummary?
    public let memory: SloMemorySummary?
    public let readyStalls: SloReadyStallSummary?
    public let limitations: [SloDiagnosticLimitation]

    public static func build(log: SloDiagnosticLog, probe: SloDiagnosticProbeInput,
                             startedAt: Date) -> SloDiagnosticReport {
        let launchBreakdown = selectedLoad(.launch, in: probe.loads).map(ProbeLoadBreakdown.of)
        let saveBreakdown = selectedLoad(.save, in: probe.loads).map(ProbeLoadBreakdown.of)
        let launch = launchBreakdown.map(loadSummary)
        let save = saveBreakdown.map(loadSummary)

        let probeMarks = launch?.spans ?? []
        let nativeMarks = log.nativePhases.map {
            SloLoadScopeMark(label: $0.name, durationMs: $0.durationMs, source: .sloNative)
        }
        let contentPatcherMarks = log.contentPatcherHotspots.map {
            SloLoadScopeMark(label: $0.name, durationMs: $0.durationMs,
                             source: .sloContentPatcher)
        }
        let primary = probeMarks.max { $0.durationMs < $1.durationMs }.map {
            SloObservedWait(label: $0.label, durationMs: $0.durationMs, source: $0.source)
        }

        var limitations: Set<SloDiagnosticLimitation> = [.singleSession, .noControlRun]
        if !log.nativePhases.isEmpty || !log.contentPatcherHotspots.isEmpty {
            limitations.insert(.nestedScopes)
        }
        if probe.loads.isEmpty { limitations.insert(.loadEvidenceMissing) }
        if probe.loads.contains(where: { !$0.complete }) { limitations.insert(.sessionInterrupted) }

        let hasSloEvidence = log.config != nil || log.mapCache != nil || log.imageCache != nil
            || log.prefetch != nil || log.deferredTiles != nil || log.spaceCore != nil
            || !log.nativePhases.isEmpty || !log.contentPatcherHotspots.isEmpty
            || !log.warps.isEmpty || !log.readyStalls.isEmpty
        if !hasSloEvidence { limitations.insert(.sloLogMissing) }
        if let config = log.config {
            if SloOptimizerConfig.bool(config.raw["detailedDiagnostics"]) != true
                || SloOptimizerConfig.bool(config.raw["performanceMeasurement"]) != true {
                limitations.insert(.diagnosticsIncomplete)
            }
        }

        let stable = stableMinutes(session: probe.session, warps: log.warps,
                                   limitations: &limitations)
        let frameMarks = stable.compactMap { minute -> SloChartMark? in
            guard let at = ProbeDate.parse(minute.at) else { return nil }
            return SloChartMark(at: at, value: minute.frameInterval.p50)
        }
        let memoryMarks = stable.compactMap { minute -> SloChartMark? in
            guard let at = ProbeDate.parse(minute.at), let value = minute.workingSetMB else { return nil }
            return SloChartMark(at: at, value: value)
        }
        let steady = stable.isEmpty ? nil : SloStableGameplaySummary(
            sampleCount: stable.count,
            medianFrameMs: median(stable.map { $0.frameInterval.p50 }) ?? 0,
            p99FrameMs: median(stable.map { $0.frameInterval.p99 }) ?? 0)
        if probe.session == nil {
            limitations.insert(.probeMissing)
        } else if stable.count < 2 {
            limitations.insert(.shortGameplay)
        }

        let stableTimes = Set(stable.map(\.at))
        let matchingCosts = probe.session?.costs.filter { stableTimes.contains($0.at) } ?? []
        if matchingCosts.contains(where: { $0.patchesMeasured == false }) {
            limitations.insert(.patchesNotMeasured)
        }
        let sloCosts = matchingCosts.flatMap(\.mods).filter {
            $0.mod.caseInsensitiveCompare(SloDiagnosticContract.uniqueId) == .orderedSame
        }
        let runtimeAverage = sloCosts.isEmpty ? 0
            : sloCosts.map(\.msPerSecond).reduce(0, +) / Double(sloCosts.count)
        let runtime = sloCosts.isEmpty ? nil : SloRuntimeSummary(
            sampleCount: sloCosts.count,
            averageMsPerSecond: (runtimeAverage * 1_000_000_000).rounded() / 1_000_000_000,
            maximumMs: sloCosts.map(\.maxMs).max() ?? 0,
            allocationKB: sloCosts.map(\.allocKB).reduce(0, +))

        let memory = memorySummary(marks: memoryMarks, config: log.config)
        let completedDurations = log.warps.compactMap {
            $0.outcome == .complete ? $0.durationMs : nil
        }
        let warpSummary = log.warps.isEmpty ? nil : SloWarpSummary(
            completed: completedDurations.count,
            aborted: log.warps.filter { $0.outcome == .abort }.count,
            excluded: log.warps.filter { $0.outcome == .excluded }.count,
            medianMs: median(completedDurations), minimumMs: completedDurations.min(),
            maximumMs: completedDurations.max())
        let imageCache = log.imageCache.map { snapshot in
            let ratio = snapshot.limitMB > 0 ? snapshot.usedMB / snapshot.limitMB : 1
            return SloImageCacheAnalysis(
                snapshot: snapshot, used: snapshot.hits > 0,
                failuresObserved: snapshot.misses > 0 || (snapshot.refusedAdmissions ?? 0) > 0,
                capacity: capacity(ratio))
        }
        let mapCache = log.mapCache.map {
            SloMapCacheAnalysis(snapshot: $0, used: $0.hits > 0,
                                failuresObserved: $0.misses > 0 || $0.corruptions > 0)
        }
        let ready = log.readyStalls.isEmpty ? nil : SloReadyStallSummary(
            count: log.readyStalls.count,
            maximumMs: log.readyStalls.map(\.durationMs).max() ?? 0)

        return SloDiagnosticReport(
            startedAt: startedAt, config: log.config, launch: launch, save: save,
            primaryWait: primary, loadScopeMarks: probeMarks + nativeMarks + contentPatcherMarks,
            mapCache: mapCache, imageCache: imageCache, prefetch: log.prefetch,
            deferredTiles: log.deferredTiles, spaceCore: log.spaceCore, warps: warpSummary,
            steadyGameplay: steady, frameMarks: frameMarks, memoryMarks: memoryMarks,
            sloRuntime: runtime, memory: memory, readyStalls: ready,
            limitations: limitations.sorted { $0.rawValue < $1.rawValue })
    }

    private static func selectedLoad(_ kind: ProbeLoadRecord.Kind,
                                     in loads: [ProbeLoadRecord]) -> ProbeLoadRecord? {
        let matching = loads.filter { $0.kind == kind }
        return matching.last(where: \.complete) ?? matching.last
    }

    private static func loadSummary(_ breakdown: ProbeLoadBreakdown) -> SloLoadSummary {
        let spans = breakdown.spans.filter { $0.name != .waitingForPlayer }.map {
            SloLoadScopeMark(label: $0.name.rawValue, durationMs: $0.ms, source: .probe)
        }
        let costs = breakdown.mods.map {
            SloLoadCostSummary(mod: $0.mod, durationMs: $0.ms, isPack: $0.isPack)
        }
        return SloLoadSummary(totalMs: breakdown.record.totalMs,
                              complete: breakdown.record.complete, spans: spans,
                              directCosts: costs)
    }

    private static func stableMinutes(session: ProbeSession?, warps: [SloWarpEvent],
                                      limitations: inout Set<SloDiagnosticLimitation>) -> [ProbeMinute] {
        guard let session else { return [] }
        let candidates = session.minutes.filter { !$0.isAtTitle && !$0.isUnfocused }
        guard !warps.isEmpty else { return candidates }
        guard let transitionDates = transitionDates(warps, session: session) else {
            limitations.insert(.transitionWindowsUnknown)
            return candidates
        }
        return candidates.filter { minute in
            guard let end = ProbeDate.parse(minute.at) else { return false }
            let start = end.addingTimeInterval(-minute.wallSeconds)
            return !transitionDates.contains { $0 > start && $0 <= end }
        }
    }

    private static func transitionDates(_ warps: [SloWarpEvent], session: ProbeSession) -> [Date]? {
        guard warps.allSatisfy({ $0.timeOfDaySeconds != nil }),
              let sessionStart = session.startedAt,
              let zone = timeZone(from: session.id) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let day = calendar.startOfDay(for: sessionStart)
        var previous: Date?
        var result: [Date] = []
        for event in warps {
            guard let seconds = event.timeOfDaySeconds else { return nil }
            var date = day.addingTimeInterval(seconds)
            while date < sessionStart.addingTimeInterval(-1) || (previous.map { date < $0 } ?? false) {
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
            }
            result.append(date)
            previous = date
        }
        return result
    }

    private static func timeZone(from sessionID: String) -> TimeZone? {
        if sessionID.hasSuffix("Z") { return TimeZone(secondsFromGMT: 0) }
        guard let match = sessionID.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) else {
            return nil
        }
        let suffix = sessionID[match]
        let sign = suffix.first == "-" ? -1 : 1
        let values = suffix.dropFirst().split(separator: ":").compactMap { Int($0) }
        guard values.count == 2 else { return nil }
        return TimeZone(secondsFromGMT: sign * (values[0] * 3_600 + values[1] * 60))
    }

    private static func memorySummary(marks: [SloChartMark],
                                      config: SloOptimizerConfig?) -> SloMemorySummary? {
        guard let maximum = marks.map(\.value).max(),
              let rawLimit = config?.raw["workingSetSoftLimit"],
              let first = rawLimit.split(whereSeparator: { $0.isWhitespace }).first,
              let limit = Double(first.replacingOccurrences(of: ",", with: ".")), limit > 0
        else { return nil }
        return SloMemorySummary(maximumWorkingSetMB: maximum, softLimitMB: limit,
                                pressure: capacity(maximum / limit))
    }

    private static func capacity(_ ratio: Double) -> SloCapacityState {
        if ratio >= 1 { return .exceeded }
        if ratio >= 0.9 { return .nearLimit }
        return .normal
    }

    private static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
