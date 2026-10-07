import Foundation

/// D2-T5. Two snapshots around each background cleanup, not a continuous trace.
/// The mod labels MiB as MB (bytes / 1_048_576). Keep signed deltas and file order.
public struct StardropiumMemorySample: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let time: String
    public let residentBefore: Double
    public let residentAfter: Double
    public let managedBefore: Double
    public let managedAfter: Double
    public let purgedTextures: Int
    public var residentDelta: Double { residentAfter - residentBefore }
    public var managedDelta: Double { managedAfter - managedBefore }
}

public struct StardropiumMemoryReport: Codable, Equatable, Sendable {
    public var samples: [StardropiumMemorySample] = []
    public var version: String?
    public var sessionStart: Date?
    /// False means no positive evidence, not proof that the profile is disabled.
    public var lowMemoryProfileDetected = false
    public var unreadableSamples = 0

    public static func parse(_ text: String) -> Self {
        var result = Self()
        let header, sample, version, start: NSRegularExpression
        do {
            header = try NSRegularExpression(pattern: #"^\[(\d{2}:\d{2}:\d{2})\s+INFO\s+Stardropium\]\s+(.*)$"#)
            sample = try NSRegularExpression(pattern: #"^\[Morning Memory Optimizer \(Background\)\] RAM: ([0-9]+(?:\.[0-9]+)?) MB -> ([0-9]+(?:\.[0-9]+)?) MB \(Managed Heap: ([0-9]+(?:\.[0-9]+)?) MB -> ([0-9]+(?:\.[0-9]+)?) MB, ([0-9]+) cached textures purged/bounded\)\.$"#)
            version = try NSRegularExpression(pattern: #"^\[\d{2}:\d{2}:\d{2}\s+INFO\s+SMAPI\]\s+Stardropium ([^\s]+) by Arshia1381\s*\|"#)
            start = try NSRegularExpression(pattern: #"^\[\d{2}:\d{2}:\d{2}\s+TRACE\s+SMAPI\] Log started at (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}) UTC$"#)
        } catch {
            assertionFailure("Invalid Stardropium parser expression: \(error)")
            return result
        }
        let dateParser = ISO8601DateFormatter()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if let value = captures(version, in: line)?.first { result.version = value }
            if let value = captures(start, in: line)?.first {
                result.sessionStart = dateParser.date(from: value + "Z")
            }
            guard let fields = captures(header, in: line) else { continue }
            let time = fields[0], message = fields[1]
            if message.hasPrefix("Detected low-memory / unified memory device"),
               message.contains("Activating Low Memory & Unified Memory Profile") {
                result.lowMemoryProfileDetected = true
            }
            guard message.hasPrefix("[Morning Memory Optimizer (Background)]") else { continue }
            let parts = time.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 3, parts[0] < 24, parts[1] < 60, parts[2] < 60,
                  let values = captures(sample, in: message),
                  let residentBefore = Double(values[0]), residentBefore.isFinite,
                  let residentAfter = Double(values[1]), residentAfter.isFinite,
                  let managedBefore = Double(values[2]), managedBefore.isFinite,
                  let managedAfter = Double(values[3]), managedAfter.isFinite,
                  let textures = Int(values[4]) else {
                result.unreadableSamples += 1
                continue
            }
            result.samples.append(StardropiumMemorySample(
                id: result.samples.count, time: time,
                residentBefore: residentBefore, residentAfter: residentAfter,
                managedBefore: managedBefore, managedAfter: managedAfter,
                purgedTextures: textures))
        }
        return result
    }

    private static func captures(_ expression: NSRegularExpression?, in text: String) -> [String]? {
        guard let match = expression?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}
