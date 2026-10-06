import Foundation

public struct SloMapCacheSnapshot: Codable, Equatable, Sendable {
    public let hits: Int64
    public let misses: Int64
    public let corruptions: Int64
    public let files: Int64?
    public let bytes: Int64?
    public let durationMs: Double?
}

public struct SloImageCacheSnapshot: Codable, Equatable, Sendable {
    public let usedMB: Double
    public let limitMB: Double
    public let hits: Int64
    public let misses: Int64
    public let evictions: Int64
    public let refusedAdmissions: Int64?
    public let initialDecodes: Int64?
    public let backgroundPrepared: Int64?
}

public struct SloPrefetchSnapshot: Codable, Equatable, Sendable {
    public let plannedFiles: Int64
    public let readFiles: Int64
    public let bytes: Int64
    public let complete: Bool

    public init(plannedFiles: Int64, readFiles: Int64, bytes: Int64, complete: Bool) {
        self.plannedFiles = plannedFiles
        self.readFiles = readFiles
        self.bytes = bytes
        self.complete = complete
    }
}

public struct SloDeferredTileSnapshot: Codable, Equatable, Sendable {
    public let calls: Int64
    public let pending: Int64
    public let warmed: Int64
    public let failures: Int64

    public init(calls: Int64, pending: Int64, warmed: Int64, failures: Int64) {
        self.calls = calls
        self.pending = pending
        self.warmed = warmed
        self.failures = failures
    }
}

public struct SloSpaceCoreSnapshot: Codable, Equatable, Sendable {
    public let fastPath: Int64
    public let fallbacks: Int64
    public let failures: Int64
    public let parallelInitializations: Int64

    public init(fastPath: Int64, fallbacks: Int64, failures: Int64,
                parallelInitializations: Int64) {
        self.fastPath = fastPath
        self.fallbacks = fallbacks
        self.failures = failures
        self.parallelInitializations = parallelInitializations
    }
}

public struct SloDurationScope: Codable, Equatable, Sendable {
    public let name: String
    public let durationMs: Double

    public init(name: String, durationMs: Double) {
        self.name = name
        self.durationMs = durationMs
    }
}

public enum SloWarpOutcome: String, Codable, Equatable, Sendable {
    case request
    case complete
    case abort
    case excluded
}

public struct SloWarpEvent: Codable, Equatable, Sendable {
    public let outcome: SloWarpOutcome
    public let timeOfDaySeconds: Double?
    public let durationMs: Double?
    public let destination: String?
    public let reason: String?
}

public struct SloReadyStall: Codable, Equatable, Sendable {
    public let durationMs: Double
    public let label: String?
}

/// Données SLO reconnues dans une tranche de journal. Chaque famille
/// cumulative garde son dernier instantané valide ; événements restent séparés.
public struct SloDiagnosticLog: Codable, Equatable, Sendable {
    public let config: SloOptimizerConfig?
    public let mapCache: SloMapCacheSnapshot?
    public let imageCache: SloImageCacheSnapshot?
    public let prefetch: SloPrefetchSnapshot?
    public let deferredTiles: SloDeferredTileSnapshot?
    public let spaceCore: SloSpaceCoreSnapshot?
    public let nativePhases: [SloDurationScope]
    public let contentPatcherHotspots: [SloDurationScope]
    public let warps: [SloWarpEvent]
    public let readyStalls: [SloReadyStall]

    public static func parse(_ text: String) -> SloDiagnosticLog {
        var mapCache: SloMapCacheSnapshot?
        var imageCache: SloImageCacheSnapshot?
        var prefetch: SloPrefetchSnapshot?
        var deferred: SloDeferredTileSnapshot?
        var spaceCore: SloSpaceCoreSnapshot?
        var native: [SloDurationScope] = []
        var hotspots: [SloDurationScope] = []
        var warps: [SloWarpEvent] = []
        var stalls: [SloReadyStall] = []

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.contains("[MAP CACHE SNAPSHOT]"),
               let hits = count("hits", line), let misses = count("misses", line),
               let corruptions = count("corruptions", line) {
                mapCache = SloMapCacheSnapshot(hits: hits, misses: misses, corruptions: corruptions,
                                               files: count("files", line), bytes: count("bytes", line),
                                               durationMs: duration(line))
            } else if line.contains("[IMAGE CACHE SNAPSHOT]"),
                      let used = number("usedMB", line), let limit = number("limitMB", line),
                      used >= 0, limit >= 0,
                      let hits = count("hits", line), let misses = count("misses", line),
                      let evictions = count("evictions", line) {
                imageCache = SloImageCacheSnapshot(
                    usedMB: used, limitMB: limit, hits: hits, misses: misses, evictions: evictions,
                    refusedAdmissions: count("refused", line) ?? count("refusedAdmissions", line),
                    initialDecodes: count("initialDecodes", line),
                    backgroundPrepared: count("backgroundPrepared", line))
            } else if line.contains("[PREFETCH SNAPSHOT]"),
                      let planned = count("planned", line), let read = count("read", line),
                      let bytes = count("bytes", line), let complete = boolean("complete", line) {
                prefetch = SloPrefetchSnapshot(plannedFiles: planned, readFiles: read,
                                               bytes: bytes, complete: complete)
            } else if line.contains("[DEFERRED TILE SNAPSHOT]"),
                      let calls = count("calls", line), let pending = count("pending", line),
                      let warmed = count("warmed", line), let failures = count("failures", line) {
                deferred = SloDeferredTileSnapshot(calls: calls, pending: pending,
                                                   warmed: warmed, failures: failures)
            } else if line.contains("[SPACECORE SNAPSHOT]"),
                      let fastPath = count("fastPath", line), let fallbacks = count("fallbacks", line),
                      let failures = count("failures", line),
                      let parallel = count("parallelInitializations", line) {
                spaceCore = SloSpaceCoreSnapshot(fastPath: fastPath, fallbacks: fallbacks,
                                                 failures: failures, parallelInitializations: parallel)
            } else if line.contains("[NATIVE PHASE]"), let scope = scope(line) {
                native.append(scope)
            } else if line.contains("[CONTENT PATCHER HOTSPOTS]"), let scope = scope(line) {
                hotspots.append(scope)
            } else if line.contains("[FAST WARP REQUEST]") {
                warps.append(warp(line, outcome: .request))
            } else if line.contains("[FAST WARP COMPLETE]"), let event = completedWarp(line) {
                warps.append(event)
            } else if line.contains("[FAST WARP ABORT]") {
                warps.append(warp(line, outcome: .abort))
            } else if line.contains("[FAST WARP EXCLUDED]") {
                warps.append(warp(line, outcome: .excluded))
            } else if line.contains("[READY SLOW UPDATE]"), let ms = duration(line) {
                stalls.append(SloReadyStall(durationMs: ms, label: string("label", line)))
            }
        }

        return SloDiagnosticLog(config: SloOptimizerConfig.parseLatest(log: text),
                                mapCache: mapCache, imageCache: imageCache, prefetch: prefetch,
                                deferredTiles: deferred, spaceCore: spaceCore,
                                nativePhases: native, contentPatcherHotspots: hotspots,
                                warps: warps, readyStalls: stalls)
    }

    private static func completedWarp(_ line: String) -> SloWarpEvent? {
        guard let ms = duration(line) else { return nil }
        return SloWarpEvent(outcome: .complete, timeOfDaySeconds: timeOfDay(line),
                            durationMs: ms, destination: string("destination", line), reason: nil)
    }

    private static func warp(_ line: String, outcome: SloWarpOutcome) -> SloWarpEvent {
        SloWarpEvent(outcome: outcome, timeOfDaySeconds: timeOfDay(line),
                     durationMs: duration(line), destination: string("destination", line),
                     reason: string("reason", line))
    }

    private static func scope(_ line: String) -> SloDurationScope? {
        guard let name = string("name", line), let ms = duration(line) else { return nil }
        return SloDurationScope(name: name, durationMs: ms)
    }

    private static func duration(_ line: String) -> Double? {
        for key in ["durationMs", "elapsedMs", "ms"] {
            if let value = number(key, line), value >= 0, value.isFinite { return value }
        }
        return nil
    }

    private static func count(_ key: String, _ line: String) -> Int64? {
        guard let value = capture(#"(?:^|[\s,])"# + NSRegularExpression.escapedPattern(for: key)
                                  + #"\s*=\s*(-?\d+)"#, in: line),
              let count = Int64(value), count >= 0 else { return nil }
        return count
    }

    private static func number(_ key: String, _ line: String) -> Double? {
        guard let value = capture(#"(?:^|[\s,])"# + NSRegularExpression.escapedPattern(for: key)
                                  + #"\s*=\s*(-?\d+(?:[\.,]\d+)?)"#, in: line),
              let number = Double(value.replacingOccurrences(of: ",", with: ".")), number.isFinite
        else { return nil }
        return number
    }

    private static func boolean(_ key: String, _ line: String) -> Bool? {
        guard let value = capture(#"(?:^|[\s,])"# + NSRegularExpression.escapedPattern(for: key)
                                  + #"\s*=\s*(true|false)\b"#, in: line)?.lowercased()
        else { return nil }
        return value == "true"
    }

    private static func string(_ key: String, _ line: String) -> String? {
        guard let value = capture(#"(?:^|[\s,])"# + NSRegularExpression.escapedPattern(for: key)
                                  + #"\s*=\s*([^,]+)"#, in: line)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func timeOfDay(_ line: String) -> Double? {
        guard let groups = captures(#"\[(\d{2}):(\d{2}):(\d{2}(?:[\.,]\d+)?)"#, in: line),
              groups.count == 3, let hours = Double(groups[0]), let minutes = Double(groups[1]),
              let seconds = Double(groups[2].replacingOccurrences(of: ",", with: ".")),
              hours < 24, minutes < 60, seconds < 60 else { return nil }
        return hours * 3_600 + minutes * 60 + seconds
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        captures(pattern, in: text)?.first
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}
