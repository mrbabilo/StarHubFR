import Foundation

public enum ProbeMemoryTrend {
    public struct Segment: Equatable, Sendable {
        public let start: Date
        public let end: Date
        public let location: String
        public let count: Int
        public let slopeMBPerMinute: Double?
        public let deltaMB: Double?
        public let sampled: Bool
    }
    private struct Point { let at: Date; let location: String; let value: Double }

    public static func analyze(_ minutes: [ProbeComparableMinute], excludedAt: [Date]) -> [Segment] {
        let ordered = minutes.compactMap { item -> (Date, ProbeMinute)? in
            ProbeDate.parse(item.minute.at).map { ($0, item.minute) }
        }.sorted { $0.0 < $1.0 }
        var groups: [[Point]] = [], current: [Point] = []
        for (at, minute) in ordered {
            guard let value = ProbeMetric.workingSet.value(minute), let location = minute.location, !location.isEmpty else {
                if !current.isEmpty { groups.append(current); current = [] }
                continue
            }
            if let previous = current.last {
                if at == previous.at { current.removeLast() }
                else if location != previous.location || at.timeIntervalSince(previous.at) > 90
                    || excludedAt.contains(where: { $0 > previous.at && $0 <= at }) {
                    groups.append(current); current = []
                }
            }
            current.append(Point(at: at, location: location, value: value))
        }
        if !current.isEmpty { groups.append(current) }
        return groups.compactMap { points in
            guard let first = points.first, let last = points.last else { return nil }
            let sampled = points.count > 300
            let subset = sampled ? (0..<300).map { points[$0 * (points.count - 1) / 299] } : points
            var slopes: [Double] = []
            if points.count >= 10 {
                for i in subset.indices {
                    for j in subset.indices where j > i {
                        let elapsed = subset[j].at.timeIntervalSince(subset[i].at) / 60
                        if elapsed > 0 { slopes.append((subset[j].value - subset[i].value) / elapsed) }
                    }
                }
            }
            let startValue = ProbeStats.median(points.prefix(3).map(\.value))
            let endValue = ProbeStats.median(points.suffix(3).map(\.value))
            let delta = points.count >= 10 ? startValue.flatMap { a in endValue.map { $0 - a } } : nil
            return Segment(start: first.at, end: last.at, location: first.location, count: points.count,
                           slopeMBPerMinute: ProbeStats.median(slopes), deltaMB: delta, sampled: sampled)
        }
    }
}
